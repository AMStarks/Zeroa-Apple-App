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
    
    func websocketBaseURLString() -> String {
        let restString = restBaseURLString()
        guard var comps = URLComponents(string: restString) else {
            return restString.removingTrailingSlash().appendingPathComponentIfNeeded("ws")
        }
        if let scheme = comps.scheme?.lowercased() {
            if scheme == "https" {
                comps.scheme = "wss"
            } else if scheme == "http" {
                comps.scheme = "ws"
            }
        }
        guard let base = comps.url?.absoluteString else {
            return restString.removingTrailingSlash().appendingPathComponentIfNeeded("ws")
        }
        return base.removingTrailingSlash().appendingPathComponentIfNeeded("ws")
    }
    
    func websocketURL(for address: String) -> URL? {
        let base = websocketBaseURLString()
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? address
        let separator = base.hasSuffix("/") ? "" : "/"
        return URL(string: "\(base)\(separator)\(encoded)")
    }
}

private extension String {
    func removingTrailingSlash() -> String {
        guard hasSuffix("/") else { return self }
        return String(dropLast())
    }
    
    func appendingPathComponentIfNeeded(_ component: String) -> String {
        let trimmed = removingTrailingSlash()
        return "\(trimmed)/\(component)"
    }
    
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

class TLSLayer2MessagingService: ObservableObject {
    static let shared = TLSLayer2MessagingService()
    
    @Published var contacts: [P2PContact] = []
    @Published var conversations: [P2PConversation] = []
    @Published var messages: [P2PMessage] = []
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    
    private var cancellables = Set<AnyCancellable>()
    private let walletService = WalletService.shared
    private let haloAPI = HaloAPIService.shared
    private let endpointResolver = MessagingEndpointResolver()
    private lazy var restBaseURLString = endpointResolver.restBaseURLString()
    private lazy var websocketBaseURLString = endpointResolver.websocketBaseURLString()
    private var accountActivationObserver: NSObjectProtocol?
    private var webSocketTask: URLSessionWebSocketTask?
    private let isMessagingFeatureEnabled: Bool = TLSLayer2MessagingService.messagingFeatureEnabled()
    
    private var isProfileActive: Bool {
        AppGroupsService.shared.isProfileActive()
    }
    
    init() {
        setupMockData() // Keep some initial data for UI
        accountActivationObserver = NotificationCenter.default.addObserver(
            forName: .zeroaAccountActivationChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let isActive = notification.userInfo?["isActive"] as? Bool else { return }
            self?.handleAccountActivationChange(isActive: isActive)
        }
        startConnection()
    }
    
    private func setupMockData() {
        // Initial mock data for UI testing
        DispatchQueue.main.async {
            self.contacts = [
                P2PContact(name: "Alice", address: "alice123", publicKey: "pubkey1", isOnline: true),
                P2PContact(name: "Bob", address: "bob456", publicKey: "pubkey2", isOnline: false),
                P2PContact(name: "Charlie", address: "charlie789", publicKey: "pubkey3", isOnline: true)
            ]
            
            self.conversations = [
                P2PConversation(contactId: "alice123", contactName: "Alice", lastMessage: "Hey, how are you?", unreadCount: 2),
                P2PConversation(contactId: "bob456", contactName: "Bob", lastMessage: "Thanks for the help!", unreadCount: 0),
                P2PConversation(contactId: "charlie789", contactName: "Charlie", lastMessage: "See you later!", unreadCount: 1)
            ]
            
            self.messages = [
                P2PMessage(senderId: "alice123", receiverId: "self", content: "Hey, how are you?"),
                P2PMessage(senderId: "self", receiverId: "alice123", content: "I'm good, thanks!"),
                P2PMessage(senderId: "bob456", receiverId: "self", content: "Thanks for the help!"),
                P2PMessage(senderId: "charlie789", receiverId: "self", content: "See you later!")
            ]
        }
    }
    
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
        guard isMessagingFeatureEnabled else {
            suspendConnection(reason: "Halo messaging offline")
            return
        }
        guard isProfileActive else {
            suspendConnection(reason: "Inactive")
            return
        }
        connectWebSocket()
        registerPeer()
        discoverPeers()
        loadMessageHistory()
    }
    
    private func handleAccountActivationChange(isActive: Bool) {
        if isActive {
            startConnection()
        } else {
            suspendConnection(reason: "Inactive")
        }
    }
    
    private func suspendConnection(reason: String) {
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
        guard isMessagingFeatureEnabled else { return }
        guard isProfileActive else { return }
        guard let address = walletService.loadAddress(), !address.isEmpty else {
            print("❌ WebSocket connection aborted - missing TLS address")
            return
        }
        guard let token = currentHaloToken() else {
            print("❌ WebSocket connection aborted - missing Halo token")
            return
        }
        guard let url = endpointResolver.websocketURL(for: address) else {
            print("❌ Invalid WebSocket URL")
            return
        }
        
        DispatchQueue.main.async {
            self.connectionStatus = "Connecting..."
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id")
        }
        
        let session = URLSession(configuration: makeSessionConfiguration())
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        receiveMessage()
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionStatus = "Connected"
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                self?.receiveMessage() // Continue receiving
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    guard let strongSelf = self, strongSelf.isProfileActive else { return }
                    strongSelf.connectionStatus = "Reconnecting..."
                    strongSelf.connectWebSocket()
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8),
               let messageData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if messageData["type"] as? String == "message",
                   let data = messageData["data"] as? [String: Any] {
                    
                    let message = P2PMessage(
                        senderId: data["sender_address"] as? String ?? "",
                        receiverId: data["receiver_address"] as? String ?? "",
                        content: data["encrypted_content"] as? String ?? "",
                        messageType: P2PMessage.P2PMessageType(rawValue: data["message_type"] as? String ?? "text") ?? .text
                    )
                    
                    DispatchQueue.main.async {
                        self.messages.append(message)
                        self.updateConversation(for: message)
                    }
                }
            }
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleWebSocketMessage(.string(text))
            }
        @unknown default:
            break
        }
    }
    
    private func registerPeer() {
        guard isMessagingFeatureEnabled else { return }
        guard let address = walletService.loadAddress() else { return }
        
        let peerData: [String: Any] = [
            "address": address,
            "public_key": address, // Using address as public key for now
            "connection_info": [:],
            "is_online": true
        ]
        
        sendAPIRequest(endpoint: "/api/v1/peer/register", method: "POST", data: peerData) { [weak self] result in
            switch result {
            case .success(let response):
#if DEBUG
                print("✅ Peer registered: \(response)")
#endif
            case .failure(let error):
                print("❌ Peer registration failed: \(error)")
            }
        }
    }
    
    private func discoverPeers() {
        guard isMessagingFeatureEnabled else { return }
        guard let address = walletService.loadAddress() else { return }
        
        sendAPIRequest(endpoint: "/api/v1/peers/discover?address=\(address)", method: "GET") { [weak self] result in
            switch result {
            case .success(let response):
                if let data = response as? [String: Any],
                   let peersData = data["peers"] as? [[String: Any]] {
                    
                    DispatchQueue.main.async {
                        self?.contacts = peersData.compactMap { peerData in
                            guard let address = peerData["address"] as? String,
                                  let publicKey = peerData["public_key"] as? String else { return nil }
                            
                            return P2PContact(
                                name: address, // Use address as name for now
                                address: address,
                                publicKey: publicKey,
                                isOnline: peerData["is_online"] as? Bool ?? false
                            )
                        }
                    }
                }
            case .failure(let error):
                print("❌ Peer discovery failed: \(error)")
            }
        }
    }
    
    private func loadMessageHistory() {
        guard isMessagingFeatureEnabled else { return }
        guard let address = walletService.loadAddress() else { return }
        
        sendAPIRequest(endpoint: "/api/v1/messages/\(address)", method: "GET") { [weak self] result in
            switch result {
            case .success(let response):
                if let data = response as? [String: Any],
                   let messagesData = data["messages"] as? [[String: Any]] {
                    
                    DispatchQueue.main.async {
                        self?.messages = messagesData.compactMap { messageData in
                            guard let senderId = messageData["sender_address"] as? String,
                                  let receiverId = messageData["receiver_address"] as? String,
                                  let content = messageData["encrypted_content"] as? String else { return nil }
                            
                            return P2PMessage(
                                senderId: senderId,
                                receiverId: receiverId,
                                content: content,
                                messageType: P2PMessage.P2PMessageType(rawValue: messageData["message_type"] as? String ?? "text") ?? .text
                            )
                        }
                        
                        // Update conversations based on messages
                        self?.updateConversationsFromMessages()
                    }
                }
            case .failure(let error):
                print("❌ Message history load failed: \(error)")
            }
        }
    }
    
    private func sendAPIRequest(endpoint: String, method: String, data: [String: Any]? = nil, completion: @escaping (Result<Any, Error>) -> Void) {
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
        let urlString = "\(restBaseURLString)\(endpoint)"
        guard let url = URL(string: urlString) else {
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
        
        if let data = data {
            request.httpBody = try? JSONSerialization.data(withJSONObject: data)
        }
        
        let session = URLSession(configuration: makeSessionConfiguration())
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                completion(.success(json))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func sendMessage(to contactId: String, content: String) {
        guard isMessagingFeatureEnabled else {
            print("⚠️ Messaging disabled - cannot send message.")
            return
        }
        guard let senderAddress = walletService.loadAddress() else { return }
        
        let messageData: [String: Any] = [
            "sender_address": senderAddress,
            "receiver_address": contactId,
            "encrypted_content": content, // In production, this should be encrypted
            "message_type": "text",
            "signature": "dummy_signature" // In production, this should be a real signature
        ]
        
        sendAPIRequest(endpoint: "/api/v1/message/relay", method: "POST", data: messageData) { [weak self] result in
            switch result {
            case .success(let response):
#if DEBUG
                print("✅ Message sent: \(response)")
#endif
                
                // Add message locally
                let message = P2PMessage(senderId: senderAddress, receiverId: contactId, content: content)
                DispatchQueue.main.async {
                    self?.messages.append(message)
                    self?.updateConversation(for: message)
                }
                
            case .failure(let error):
                print("❌ Message send failed: \(error)")
            }
        }
    }
    
    private func updateConversation(for message: P2PMessage) {
        let contactId = message.senderId == walletService.loadAddress() ? message.receiverId : message.senderId
        
        if let index = conversations.firstIndex(where: { $0.contactId == contactId }) {
            conversations[index] = P2PConversation(
                contactId: contactId,
                contactName: conversations[index].contactName,
                lastMessage: message.content,
                unreadCount: message.senderId != walletService.loadAddress() ? conversations[index].unreadCount + 1 : 0
            )
        } else {
            // Create new conversation
            let contact = contacts.first { $0.address == contactId }
            let conversation = P2PConversation(
                contactId: contactId,
                contactName: contact?.name ?? contactId,
                lastMessage: message.content,
                unreadCount: message.senderId != walletService.loadAddress() ? 1 : 0
            )
            conversations.append(conversation)
        }
    }
    
    private func updateConversationsFromMessages() {
        var conversationMap: [String: P2PConversation] = [:]
        
        for message in messages {
            let contactId = message.senderId == walletService.loadAddress() ? message.receiverId : message.senderId
            
            if let existing = conversationMap[contactId] {
                conversationMap[contactId] = P2PConversation(
                    contactId: contactId,
                    contactName: existing.contactName,
                    lastMessage: message.content,
                    unreadCount: message.senderId != walletService.loadAddress() ? existing.unreadCount + 1 : existing.unreadCount
                )
            } else {
                let contact = contacts.first { $0.address == contactId }
                conversationMap[contactId] = P2PConversation(
                    contactId: contactId,
                    contactName: contact?.name ?? contactId,
                    lastMessage: message.content,
                    unreadCount: message.senderId != walletService.loadAddress() ? 1 : 0
                )
            }
        }
        
        conversations = Array(conversationMap.values)
    }
    
    func getMessages(for contactId: String) -> [P2PMessage] {
        return messages.filter { message in
            (message.senderId == contactId && message.receiverId == walletService.loadAddress()) ||
            (message.senderId == walletService.loadAddress() && message.receiverId == contactId)
        }.sorted { $0.timestamp < $1.timestamp }
    }
    
    func addContact(name: String, address: String, publicKey: String) {
        let contact = P2PContact(name: name, address: address, publicKey: publicKey)
        contacts.append(contact)
    }
    
    func getContacts() -> [P2PContact] {
        return contacts
    }
    
    func sendP2PMessage(to contactId: String, content: String) async -> Bool {
        guard isMessagingFeatureEnabled else { return false }
        sendMessage(to: contactId, content: content)
        return true
    }
    
    func removeContact(contactId: String) {
        contacts.removeAll { $0.id == contactId }
        conversations.removeAll { $0.contactId == contactId }
        messages.removeAll { $0.senderId == contactId || $0.receiverId == contactId }
    }
    
    func markAsRead(contactId: String) {
        // Mark messages as read
        for i in 0..<messages.count {
            if messages[i].senderId == contactId && messages[i].receiverId == walletService.loadAddress() {
                messages[i] = P2PMessage(
                    id: messages[i].id,
                    senderId: messages[i].senderId,
                    receiverId: messages[i].receiverId,
                    content: messages[i].content,
                    timestamp: messages[i].timestamp,
                    messageType: messages[i].messageType,
                    isRead: true
                )
            }
        }
        
        // Update conversation unread count
        if let index = conversations.firstIndex(where: { $0.contactId == contactId }) {
            conversations[index] = P2PConversation(
                contactId: contactId,
                contactName: conversations[index].contactName,
                lastMessage: conversations[index].lastMessage,
                unreadCount: 0
            )
        }
    }
    
    deinit {
        if let observer = accountActivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
    
    private static func messagingFeatureEnabled() -> Bool {
#if DEBUG
        return ProcessInfo.processInfo.environment["ZEROA_ENABLE_HALO_MESSAGING"] == "1"
#else
        return false
#endif
    }
}
