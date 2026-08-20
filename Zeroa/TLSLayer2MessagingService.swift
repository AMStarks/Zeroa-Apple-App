import Foundation
import Combine
import Network

private struct MessagingEndpointResolver {
    private let environmentKey = "L2_MESSAGING_BASE_URL"
    private let defaultRestBase = "https://halo.telestai.io"

    func restBaseURLString() -> String {
        let override = ProcessInfo.processInfo.environment[environmentKey]
        let candidate = override?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? defaultRestBase
        return candidate.removingTrailingSlash()
    }

    func websocketURL(for address: String, token: String) -> URL? {
        let restString = restBaseURLString()
        guard var comps = URLComponents(string: restString) else { return nil }
        if let scheme = comps.scheme?.lowercased() {
            if scheme == "https" { comps.scheme = "wss" }
            else if scheme == "http" { comps.scheme = "ws" }
        }
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? address
        comps.path = "/ws/\(encoded)"
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps.url
    }
}

private extension String {
    func removingTrailingSlash() -> String {
        hasSuffix("/") ? String(dropLast()) : self
    }

    var nonEmpty: String? { isEmpty ? nil : self }
}

final class TLSLayer2MessagingService: ObservableObject {
    static let shared = TLSLayer2MessagingService()

    @Published var contacts: [P2PContact] = []
    @Published var conversations: [P2PConversation] = []
    @Published var messages: [P2PMessage] = []
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"

    private var cancellables = Set<AnyCancellable>()
    private let walletService = WalletService.shared
    private let haloAPI = HaloAPIService.shared
    private let crypto = CryptoService.shared
    private let keychain = KeychainService.shared
    private let endpointResolver = MessagingEndpointResolver()
    private lazy var restBaseURLString = endpointResolver.restBaseURLString()
    private var accountActivationObserver: NSObjectProtocol?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private let contactsStoreKey = "switchboard_contacts_v1"
    private let messagesStoreKey = "switchboard_messages_v1"

    private var isMessagingFeatureEnabled: Bool { Self.messagingFeatureEnabled() }

    private var isProfileActive: Bool {
        AppGroupsService.shared.isProfileActive()
    }

    init() {
        loadPersistedContacts()
        loadPersistedMessages()
        accountActivationObserver = NotificationCenter.default.addObserver(
            forName: .zeroaAccountActivationChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let isActive = notification.userInfo?["isActive"] as? Bool else { return }
            if isActive { self?.startConnection() }
            else { self?.suspendConnection(reason: "Inactive") }
        }
        startConnection()
    }

    private static func messagingFeatureEnabled() -> Bool {
        // Switchboard MVP: enabled for com.tls.Zeroa builds.
        // Kill-switch: UserDefaults ZEROA_DISABLE_HALO_MESSAGING=true
        if UserDefaults.standard.bool(forKey: "ZEROA_DISABLE_HALO_MESSAGING") { return false }
        if ProcessInfo.processInfo.environment["ZEROA_DISABLE_HALO_MESSAGING"] == "1" { return false }
        return true
    }

    // MARK: - Connection

    func startConnection() {
        guard isMessagingFeatureEnabled else {
            suspendConnection(reason: "Halo messaging offline")
            return
        }
        guard isProfileActive else {
            suspendConnection(reason: "Inactive")
            return
        }
        Task {
            await HaloService.shared.ensureToken()
            await MainActor.run { [weak self] in
                self?.openMessagingChannels()
            }
        }
    }

    private func openMessagingChannels() {
        guard isMessagingFeatureEnabled, isProfileActive else { return }
        registerPeer()
        connectWebSocket()
        loadMessageHistory()
    }

    private func suspendConnection(reason: String) {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = reason
        }
    }

    private func currentHaloToken() -> String? {
        haloAPI.storedToken()?.token
    }

    private func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        return configuration
    }

    private func connectWebSocket() {
        guard isMessagingFeatureEnabled, isProfileActive else { return }
        guard let address = walletService.loadAddress(), !address.isEmpty else { return }
        guard let token = currentHaloToken() else {
            connectionStatus = "Missing Halo token"
            return
        }
        guard let url = endpointResolver.websocketURL(for: address, token: token) else { return }

        DispatchQueue.main.async { self.connectionStatus = "Connecting…" }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: makeSessionConfiguration())
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
        startPing()

        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionStatus = "Connected"
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.webSocketTask?.send(.string("{\"type\":\"ping\"}")) { _ in }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                self?.receiveMessage()
            case .failure:
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard let self, self.isProfileActive, self.isMessagingFeatureEnabled else { return }
                    self.connectionStatus = "Reconnecting…"
                    self.connectWebSocket()
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let text,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        if type == "message" || type == "message_ack",
           let payload = obj["data"] as? [String: Any] {
            if let msg = decodeServerMessage(payload) {
                DispatchQueue.main.async {
                    self.upsertMessage(msg)
                    self.updateConversation(for: msg)
                }
            }
        }
    }

    // MARK: - Peers / contacts

    private func registerPeer() {
        guard let address = walletService.loadAddress(),
              let pubkey = crypto.getCompressedPublicKeyHex(keychain: keychain) else { return }
        let body: [String: Any] = [
            "address": address,
            "public_key": pubkey,
            "connection_info": ["websocket": true],
            "is_online": true,
        ]
        sendAPIRequest(endpoint: "/api/v1/peer/register", method: "POST", data: body) { _ in }
    }

    func lookupPeerPubkey(address: String, completion: @escaping (String?) -> Void) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? address
        sendAPIRequest(endpoint: "/api/v1/peer/\(encoded)", method: "GET") { result in
            switch result {
            case .success(let response):
                let pubkey = (response as? [String: Any])
                    .flatMap { $0["peer"] as? [String: Any] }?
                    .flatMap { $0["public_key"] as? String }
                completion((pubkey?.isEmpty == false) ? pubkey : nil)
            case .failure:
                completion(nil)
            }
        }
    }

    func addContact(name: String, address: String, publicKey: String? = nil) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        func finish(with pubkey: String) {
            let contact = P2PContact(
                id: trimmed,
                name: name.isEmpty ? String(trimmed.prefix(12)) : name,
                address: trimmed,
                publicKey: pubkey,
                isOnline: false
            )
            DispatchQueue.main.async {
                self.contacts.removeAll { $0.address == trimmed }
                self.contacts.insert(contact, at: 0)
                self.persistContacts()
            }
        }

        if let publicKey, !publicKey.isEmpty {
            finish(with: publicKey)
            return
        }
        lookupPeerPubkey(address: trimmed) { pubkey in
            finish(with: pubkey ?? "")
        }
    }

    func removeContact(_ contact: P2PContact) {
        DispatchQueue.main.async {
            self.contacts.removeAll { $0.address == contact.address }
            self.persistContacts()
        }
    }

    private func loadPersistedContacts() {
        guard let data = UserDefaults.standard.data(forKey: contactsStoreKey),
              let decoded = try? JSONDecoder().decode([P2PContact].self, from: data) else { return }
        contacts = decoded
    }

    private func persistContacts() {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: contactsStoreKey)
        }
    }

    private func loadPersistedMessages() {
        guard let data = UserDefaults.standard.data(forKey: messagesStoreKey),
              let decoded = try? JSONDecoder().decode([P2PMessage].self, from: data) else { return }
        messages = decoded
        updateConversationsFromMessages()
    }

    private func persistMessages() {
        if let data = try? JSONEncoder().encode(messages.suffix(500)) {
            UserDefaults.standard.set(data, forKey: messagesStoreKey)
        }
    }

    private func pubkey(for address: String) -> String? {
        if let c = contacts.first(where: { $0.address == address }), !c.publicKey.isEmpty {
            return c.publicKey
        }
        return nil
    }

    // MARK: - Messages

    private func loadMessageHistory() {
        guard let address = walletService.loadAddress() else { return }
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? address
        sendAPIRequest(endpoint: "/api/v1/messages/\(encoded)", method: "GET") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                guard let data = response as? [String: Any],
                      let rows = data["messages"] as? [[String: Any]] else { return }
                let decoded = rows.compactMap { self.decodeServerMessage($0) }
                DispatchQueue.main.async {
                    // Merge server decrypts with locally cached plaintext
                    var byId = Dictionary(uniqueKeysWithValues: self.messages.map { ($0.id, $0) })
                    for msg in decoded {
                        if let existing = byId[msg.id],
                           (msg.content == "(encrypted)" || msg.content == "(unable to decrypt)"),
                           !existing.content.hasPrefix("(") {
                            byId[msg.id] = existing
                        } else {
                            byId[msg.id] = msg
                        }
                    }
                    self.messages = Array(byId.values).sorted { $0.timestamp < $1.timestamp }
                    self.persistMessages()
                    self.updateConversationsFromMessages()
                }
            case .failure(let error):
                print("❌ Switchboard history: \(error)")
            }
        }
    }

    private func decodeServerMessage(_ data: [String: Any]) -> P2PMessage? {
        guard let sender = data["sender_address"] as? String,
              let receiver = data["receiver_address"] as? String,
              let encrypted = data["encrypted_content"] as? String else { return nil }
        let id = data["id"] as? String ?? UUID().uuidString
        let ts: Date = {
            if let s = data["timestamp"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = f.date(from: s) { return d }
                f.formatOptions = [.withInternetDateTime]
                return f.date(from: s) ?? Date()
            }
            return Date()
        }()

        let plaintext: String
        if let me = walletService.loadAddress(), sender == me {
            // Own outbound: try decrypt (works if we were recipient of echo) else show placeholder until local cache
            if let p = crypto.decryptDirectMessage(payload: encrypted, keychain: keychain) {
                plaintext = p
            } else if let cached = messages.first(where: { $0.id == id })?.content {
                plaintext = cached
            } else {
                plaintext = "(encrypted)"
            }
        } else if let p = crypto.decryptDirectMessage(payload: encrypted, keychain: keychain) {
            plaintext = p
        } else {
            plaintext = "(unable to decrypt)"
        }

        return P2PMessage(
            id: id,
            senderId: sender,
            receiverId: receiver,
            content: plaintext,
            timestamp: ts,
            messageType: .text,
            isRead: false
        )
    }

    func sendP2PMessage(to contactAddress: String, content: String) {
        sendMessage(to: contactAddress, content: content)
    }

    func sendMessage(to contactAddress: String, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let sender = walletService.loadAddress() else { return }

        Task {
            await HaloService.shared.ensureToken()
            var recipientKey = self.pubkey(for: contactAddress)
            if recipientKey == nil || recipientKey?.isEmpty == true {
                recipientKey = await withCheckedContinuation { cont in
                    self.lookupPeerPubkey(address: contactAddress) { cont.resume(returning: $0) }
                }
            }
            guard let recipientKey, !recipientKey.isEmpty else {
                await MainActor.run { self.connectionStatus = "Recipient has no public key yet" }
                return
            }
            guard let encrypted = crypto.encryptDirectMessage(
                plaintext: trimmed,
                recipientCompressedPubkeyHex: recipientKey,
                keychain: keychain
            ),
            let senderPub = crypto.getCompressedPublicKeyHex(keychain: keychain) else { return }

            let ts = ISO8601DateFormatter().string(from: Date())
            let canonical = "MSG|\(sender)|\(contactAddress)|\(encrypted)|\(ts)"
            guard let signature = crypto.signMessageBase64(canonical, keychain: keychain) else { return }

            let body: [String: Any] = [
                "sender_address": sender,
                "receiver_address": contactAddress,
                "encrypted_content": encrypted,
                "message_type": "text",
                "signature": signature,
                "sender_pubkey": senderPub,
                "timestamp": ts,
            ]

            // Optimistic local plaintext
            let local = P2PMessage(
                senderId: sender,
                receiverId: contactAddress,
                content: trimmed,
                messageType: .text
            )
            await MainActor.run {
                self.upsertMessage(local)
                self.updateConversation(for: local)
            }

            sendAPIRequest(endpoint: "/api/v1/message/relay", method: "POST", data: body) { [weak self] result in
                switch result {
                case .success(let response):
                    if let dict = response as? [String: Any],
                       let msg = dict["message"] as? [String: Any],
                       let id = msg["id"] as? String {
                        DispatchQueue.main.async {
                            if let idx = self?.messages.firstIndex(where: { $0.id == local.id }) {
                                let updated = P2PMessage(
                                    id: id,
                                    senderId: sender,
                                    receiverId: contactAddress,
                                    content: trimmed,
                                    timestamp: local.timestamp,
                                    messageType: .text,
                                    isRead: true
                                )
                                self?.messages[idx] = updated
                            }
                        }
                    }
                case .failure(let error):
                    print("❌ Switchboard send failed: \(error)")
                    DispatchQueue.main.async {
                        self?.connectionStatus = "Send failed"
                    }
                }
            }
        }
    }

    func getMessages(for contactAddress: String) -> [P2PMessage] {
        guard let me = walletService.loadAddress() else { return [] }
        return messages
            .filter {
                ($0.senderId == contactAddress && $0.receiverId == me) ||
                ($0.senderId == me && $0.receiverId == contactAddress)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func markAsRead(contactAddress: String) {
        // Local-only for MVP
        DispatchQueue.main.async {
            if let idx = self.conversations.firstIndex(where: { $0.contactId == contactAddress }) {
                let c = self.conversations[idx]
                self.conversations[idx] = P2PConversation(
                    id: c.id,
                    contactId: c.contactId,
                    contactName: c.contactName,
                    lastMessage: c.lastMessage,
                    timestamp: c.timestamp,
                    unreadCount: 0
                )
            }
        }
    }

    private func upsertMessage(_ message: P2PMessage) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else if !messages.contains(where: {
            $0.senderId == message.senderId &&
            $0.receiverId == message.receiverId &&
            $0.content == message.content &&
            abs($0.timestamp.timeIntervalSince(message.timestamp)) < 2
        }) {
            messages.append(message)
        }
        persistMessages()
    }

    private func updateConversation(for message: P2PMessage) {
        guard let me = walletService.loadAddress() else { return }
        let other = message.senderId == me ? message.receiverId : message.senderId
        let name = contacts.first(where: { $0.address == other })?.name ?? String(other.prefix(12))
        let unread = message.senderId == me ? 0 : 1
        if let idx = conversations.firstIndex(where: { $0.contactId == other }) {
            let prev = conversations[idx]
            conversations[idx] = P2PConversation(
                id: prev.id,
                contactId: other,
                contactName: name,
                lastMessage: message.content,
                timestamp: message.timestamp,
                unreadCount: prev.unreadCount + unread
            )
        } else {
            conversations.insert(
                P2PConversation(
                    contactId: other,
                    contactName: name,
                    lastMessage: message.content,
                    unreadCount: unread
                ),
                at: 0
            )
        }
        conversations.sort { $0.timestamp > $1.timestamp }
    }

    private func updateConversationsFromMessages() {
        guard let me = walletService.loadAddress() else { return }
        var map: [String: P2PConversation] = [:]
        for message in messages.sorted(by: { $0.timestamp < $1.timestamp }) {
            let other = message.senderId == me ? message.receiverId : message.senderId
            let name = contacts.first(where: { $0.address == other })?.name ?? String(other.prefix(12))
            map[other] = P2PConversation(
                contactId: other,
                contactName: name,
                lastMessage: message.content,
                timestamp: message.timestamp,
                unreadCount: 0
            )
        }
        conversations = map.values.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - HTTP

    private func sendAPIRequest(
        endpoint: String,
        method: String,
        data: [String: Any]? = nil,
        completion: @escaping (Result<Any, Error>) -> Void
    ) {
        guard isMessagingFeatureEnabled else {
            completion(.failure(NSError(domain: "MessagingService", code: -13, userInfo: [NSLocalizedDescriptionKey: "Halo messaging disabled"])))
            return
        }
        guard isProfileActive else {
            completion(.failure(NSError(domain: "MessagingService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Account inactive"])))
            return
        }
        guard let token = currentHaloToken() else {
            completion(.failure(NSError(domain: "MessagingService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Missing Halo token"])))
            return
        }
        guard let url = URL(string: "\(restBaseURLString)\(endpoint)") else {
            completion(.failure(NSError(domain: "MessagingService", code: -12, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id")
        }
        request.timeoutInterval = 20
        if let data { request.httpBody = try? JSONSerialization.data(withJSONObject: data) }

        URLSession(configuration: makeSessionConfiguration()).dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let data else {
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(NSError(domain: "MessagingService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            do {
                completion(.success(try JSONSerialization.jsonObject(with: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    deinit {
        if let observer = accountActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pingTimer?.invalidate()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}
