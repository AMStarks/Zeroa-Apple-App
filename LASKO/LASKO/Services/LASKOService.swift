import Foundation
import UIKit
import CryptoKit

// Accept ints or strings for numeric fields across API shapes
enum IntOrString: Decodable {
    case int(Int)
    case string(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        let s = try c.decode(String.self)
        self = .string(s)
    }
    func asInt() -> Int? {
        switch self {
        case .int(let i): return i
        case .string(let s): return Int(s)
        }
    }
}

@MainActor
class LASKOService: ObservableObject {
    static let shared = LASKOService()
    
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isConnectedToTelestai = false
    @Published var isAuthenticatedWithZeroa = false
    @Published var currentTLSAddress: String?
    @Published var repliesByCode: [String: [Post]] = [:]
    @Published var username: String = UserDefaults.standard.string(forKey: "lasko_username") ?? generateRandomUsername() {
        didSet {
            print("🔍 LASKO: Username changed to: \(username)")
            UserDefaults.standard.set(username, forKey: "lasko_username")
            print("🔍 LASKO: Username saved to UserDefaults")
        }
    }
    
    private static func generateRandomUsername() -> String {
        // Generate a random username for new users
        let adjectives = ["Swift", "Bright", "Quick", "Smart", "Bold", "Sharp", "Fast", "Cool", "Fresh", "New"]
        let nouns = ["User", "Member", "Player", "Explorer", "Pioneer", "Trader", "Builder", "Creator", "Voyager", "Navigator"]
        
        let randomAdjective = adjectives.randomElement() ?? "Swift"
        let randomNoun = nouns.randomElement() ?? "User"
        let randomNumber = Int.random(in: 100...999)
        
        return "\(randomAdjective)\(randomNoun)\(randomNumber)"
    }
    
    private func generateAddressBasedUsername() -> String {
        // Generate a username based on the TLS address
        if let address = currentTLSAddress, !address.isEmpty {
            // Take the first 6 characters of the address and capitalize them
            let prefix = String(address.prefix(6)).uppercased()
            return "User\(prefix)"
        }
        return LASKOService.generateRandomUsername()
    }
    
    private func parseDate(isoString: String?, ts: IntOrString?, tsMs: IntOrString?) -> Date {
        // The server timestamp field is in milliseconds, not seconds
        if let msVal = tsMs?.asInt() { 
            return Date(timeIntervalSince1970: TimeInterval(msVal) / 1000.0) 
        }
        if let tsVal = ts?.asInt() {
            // Server's "timestamp" field is actually milliseconds since epoch
            if tsVal > 1_000_000_000_000 { // If > 1 trillion, it's milliseconds
                return Date(timeIntervalSince1970: TimeInterval(tsVal) / 1000.0)
            } else {
                return Date(timeIntervalSince1970: TimeInterval(tsVal)) // Treat as seconds
            }
        }
        if let s = isoString {
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: s) { return d }
        }
        return Date()
    }
    
    private let baseURL = "https://halo.telestai.io/api"
    private var effectiveBaseURL: String {
        if let override = appGroupsService.sharedDefaults?.string(forKey: "halo_indexer_base_url"), !override.isEmpty {
            if let host = URL(string: override)?.host, host.range(of: "^\\d+\\.\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil {
                // Ignore raw IP overrides to avoid ATS TLS failures
                return baseURL
            }
            return override
        }
        return baseURL
    }
    private let appGroupsService = AppGroupsService.shared
    
    init() {
        // Do not auto-check authentication on init; allow explicit user-triggered flow
        print("🔍 LASKO: LASKOService initialized with username: \(username)")
        print("🔍 LASKO: UserDefaults username: \(UserDefaults.standard.string(forKey: "lasko_username") ?? "nil")")
    }
    
    // MARK: - Zeroa Integration
    
    func checkZeroaAuthentication() {
        print("🔍 LASKO: Checking Zeroa authentication...")
        
        // If already authenticated, do not downgrade state on subsequent polls
        if isAuthenticatedWithZeroa {
            print("✅ LASKO: Already authenticated; skipping further checks")
            return
        }
        
        // Process completed auth response if available (do not require request to persist)
        if let resp = AppGroupsService.shared.getLASKOAuthResponse() {
            Task { @MainActor in
                let ok = true
                if ok {
                    self.isAuthenticatedWithZeroa = true
                    self.currentTLSAddress = resp.tlsAddress
                    
                    // Only generate username for new users if not already set
                    if UserDefaults.standard.string(forKey: "lasko_username") == nil {
                        self.username = self.generateAddressBasedUsername()
                        print("🔍 LASKO: Generated new username: \(self.username)")
                    } else {
                        // Preserve existing username
                        print("🔍 LASKO: Preserving existing username: \(self.username)")
                    }
                    
                    // Clear consumed response; request may already be cleared by Zeroa
                    AppGroupsService.shared.clearAuthResponse()
                    self.stopAuthPollingWindow()
                    print("✅ LASKO: Signature verified; identity established for \(resp.tlsAddress)")
                } else {
                    self.isAuthenticatedWithZeroa = false
                    self.currentTLSAddress = nil
                    print("❌ LASKO: Signature verification failed")
                }
            }
            return
        }
        
        // If no response yet, remain unauthenticated until request is approved in Zeroa
        print("❌ LASKO: No completed Zeroa response yet")
        // Do not explicitly set to false here to avoid flicker after success
    }
    
    func requestZeroaAuthentication() {
        // Headless identity flow: create a fresh nonce request for Zeroa to sign
        print("🔍 LASKO: Creating headless auth request (nonce) for Zeroa…")
        let req = LASKOAuthRequest(
            appName: "LASKO",
            appId: Bundle.main.bundleIdentifier ?? "com.telestai.LASKO",
            permissions: ["post", "read"],
            callbackURL: "lasko://auth/callback",
            username: nil,
            nonce: nil
        )
        AppGroupsService.shared.storeLASKOAuthRequest(req)
        // Start a 60s polling window for the auth response
        startAuthPollingWindow()
    }
    
    func checkForAuthResponse() {
        // Headless polling: check App Groups for response
        print("🔍 LASKO: Polling for Zeroa auth response…")
        checkZeroaAuthentication()
    }
    
    // Lightweight check used by UI to detect if a response already exists without changing state
    func hasExistingAuthResponse() -> Bool { false }

    // MARK: - Headless Polling Window
    private var authPollTimer: Timer?
    private var authPollDeadline: Date?
    
    private func startAuthPollingWindow() {
        stopAuthPollingWindow()
        authPollDeadline = Date().addingTimeInterval(60)
        authPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.checkForAuthResponse()
                if let deadline = self.authPollDeadline, Date() >= deadline {
                    self.stopAuthPollingWindow()
                    // Timeout: clear request and inform UI
                    AppGroupsService.shared.clearAuthRequest()
                    self.isAuthenticatedWithZeroa = false
                    self.errorMessage = "Login timed out. Open Zeroa and try again."
                    print("⏱️ LASKO: Auth polling timed out after 60s")
                }
            }
        }
        print("⏱️ LASKO: Started 60s auth polling window")
    }
    
    private func stopAuthPollingWindow() {
        authPollTimer?.invalidate()
        authPollTimer = nil
        authPollDeadline = nil
    }

    // MARK: - Zeroa Token Prompt
    private func promptZeroaForToken(for tlsAddress: String) {
        // Set the standard refresh flag for background listeners
        appGroupsService.sharedDefaults?.set(true, forKey: "halo_token_refresh_request")
        // Provide desired address context for Zeroa (optional key Zeroa can read)
        appGroupsService.sharedDefaults?.set(tlsAddress, forKey: "halo_token_for_address")
        // For interactive foreground handoff, also drop a lightweight auth request if not present
        if appGroupsService.sharedDefaults?.object(forKey: "lasko_auth_request_nonce") == nil {
            let req = LASKOAuthRequest(
            appName: "LASKO",
                appId: Bundle.main.bundleIdentifier ?? "com.telestai.LASKO",
            permissions: ["post", "read"],
            callbackURL: "lasko://auth/callback",
                username: nil,
            nonce: nil
        )
            AppGroupsService.shared.storeLASKOAuthRequest(req)
            startAuthPollingWindow()
        }
        appGroupsService.sharedDefaults?.synchronize()
    }

    // MARK: - Crypto utils
    private func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - JWT helpers
    private func base64UrlDecode(_ str: String) -> Data? {
        var base64 = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 { base64.append(String(repeating: "=", count: padding)) }
        return Data(base64Encoded: base64)
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        guard let data = base64UrlDecode(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    private func jwtSubject(_ token: String) -> String? {
        guard let payload = decodeJWTPayload(token) else { return nil }
        return payload["sub"] as? String
    }

    private func readHaloToken() -> String? {
        return appGroupsService.sharedDefaults?.string(forKey: "halo_access_token") ??
               appGroupsService.sharedDefaults?.string(forKey: "haloAccessToken")
    }

    private func tokenIsFresh(_ token: String, leewaySeconds: TimeInterval = 60) -> Bool {
        guard let payload = decodeJWTPayload(token), let exp = payload["exp"] as? TimeInterval else { return false }
        let now = Date().timeIntervalSince1970
        return (exp - now) > leewaySeconds
    }

    private func ensureTokenForAddress(_ tlsAddress: String, timeoutSeconds: Double = 5.0) async -> String? {
        if let t = readHaloToken(), tokenIsFresh(t) {
            let sub = jwtSubject(t)
            if sub == nil || sub == tlsAddress { return t }
            print("⚠️ LASKO: Token subject (\(sub ?? "nil")) != TLS (\(tlsAddress)); will request refresh")
        }
        
        // Check if we have any token, but only use it if it's fresh
        if let t = readHaloToken() {
            if tokenIsFresh(t) {
                print("✅ LASKO: Using existing fresh token")
                return t
            } else {
                print("⚠️ LASKO: Existing token is expired, requesting refresh")
            }
        }
        
        // Ask Zeroa to refresh and require a newer refresh marker
        let requestStartMs = Int(Date().timeIntervalSince1970 * 1000)
        promptZeroaForToken(for: tlsAddress)
        let maxTries = Int(timeoutSeconds * 10)
        var tries = 0
        while tries < maxTries {
            if let refreshedAtAny = appGroupsService.sharedDefaults?.object(forKey: "halo_token_refreshed_at") {
                var refreshedAtMs = 0
                if let n = refreshedAtAny as? Int { refreshedAtMs = n }
                else if let n64 = refreshedAtAny as? Int64 { refreshedAtMs = Int(truncatingIfNeeded: n64) }
                else if let d = refreshedAtAny as? Double { refreshedAtMs = Int(d) }
                else if let s = refreshedAtAny as? String { refreshedAtMs = Int(s) ?? 0 }
                if refreshedAtMs >= requestStartMs {
                    if let t = readHaloToken(), tokenIsFresh(t) {
                        let sub = jwtSubject(t)
                        if sub == nil || sub == tlsAddress { return t }
                        print("⚠️ LASKO: Refreshed token subject (\(sub ?? "nil")) still != TLS (\(tlsAddress)); proceeding anyway")
                        return t
                    }
                }
            }
            tries += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if let t = readHaloToken(), tokenIsFresh(t) { return t }
        return nil
    }

    private func ensureValidHaloToken(timeoutSeconds: Double = 5.0) async -> String? {
        if let t = readHaloToken(), tokenIsFresh(t) { return t }
        // Ask Zeroa to refresh and require a newer refresh marker
        let requestStartMs = Int(Date().timeIntervalSince1970 * 1000)
        appGroupsService.sharedDefaults?.set(true, forKey: "halo_token_refresh_request")
        appGroupsService.sharedDefaults?.synchronize()
        let maxTries = Int(timeoutSeconds * 10)
        var tries = 0
        while tries < maxTries {
            if let refreshedAtAny = appGroupsService.sharedDefaults?.object(forKey: "halo_token_refreshed_at") {
                var refreshedAtMs = 0
                if let n = refreshedAtAny as? Int { refreshedAtMs = n }
                else if let n64 = refreshedAtAny as? Int64 { refreshedAtMs = Int(truncatingIfNeeded: n64) }
                else if let d = refreshedAtAny as? Double { refreshedAtMs = Int(d) }
                else if let s = refreshedAtAny as? String { refreshedAtMs = Int(s) ?? 0 }
                if refreshedAtMs >= requestStartMs {
                    if let t = readHaloToken(), tokenIsFresh(t) { return t }
                }
            }
            tries += 1
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        if let t = readHaloToken(), tokenIsFresh(t) { return t }
        return nil
    }

    // MARK: - Signature verification via backend
    private func backendVerifySignature(address: String, message: String, signature: String) async -> Bool {
        // Try primary endpoint /auth/verify, allow alternate /halo/verify if first is missing
        let endpoints = ["auth/verify", "halo/verify"]
        for path in endpoints {
            guard let url = URL(string: "\(effectiveBaseURL)/\(path)") else { continue }
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let bundleId = Bundle.main.bundleIdentifier { req.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
                let body: [String: Any] = [
                    "address": address,
                    "message": message,
                    "signature": signature
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    // Accept either {ok:true} or {token:...,exp:...} shapes
                    if let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let ok = obj["ok"] as? Bool, ok { return true }
                        // If server returns a token on verify, presence implies success
                        if obj["token"] != nil { return true }
                    }
            return true
                } else if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                    continue
                }
            } catch {
                continue
            }
        }
        return false
    }
    
    // MARK: - Mock Data for Development
    func loadMockData() {
        posts = Post.mockPosts
    }
    
    // MARK: - API Methods
    
    func fetchPosts() async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // Require TLS address and a fresh JWT bound to that address before fetching
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty else {
            print("❌ LASKO: fetchPosts aborted - missing TLS address")
            DispatchQueue.main.async { self.isLoading = false; self.errorMessage = "Missing TLS address. Connect Zeroa." }
            return
        }
        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else {
            print("❌ LASKO: fetchPosts aborted - no fresh Halo token for address \(tls)")
            DispatchQueue.main.async { self.isLoading = false; self.errorMessage = "Missing Halo token. Open Zeroa." }
            return
        }
        print("🔐 LASKO: JWT subject=\(jwtSubject(token) ?? "nil") TLS=\(tls)")
        
        // Fetch from production API

        struct APIPost: Decodable {
            let id: String?
        let sequentialCode: String?
            let code: String?
        let content: String?
            let author: String?
            let address: String?
            let userAddress: String?
        let createdAt: String?
            let timestamp: IntOrString?
            let timestampMs: IntOrString?
            let likes: Int?
            let likesCount: IntOrString?
            let replies: Int?
            let repliesCount: IntOrString?
            let userRank: String?
            let broadcastCount: IntOrString?
            let tlsCount: IntOrString?
            let followerCount: IntOrString?
        }
        

        
        do {
            print("🔗 LASKO: Using Indexer base URL: \(effectiveBaseURL)")
            guard let url = URL(string: "\(effectiveBaseURL)/posts?limit=50") else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let bundleId = Bundle.main.bundleIdentifier { request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
            let (data, response) = try await URLSession.shared.data(for: request)
            print("🔍 LASKO: Raw API response: \(String(data: data, encoding: .utf8) ?? "nil")")
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("❌ LASKO: fetchPosts server error: \(http.statusCode) \(body)")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load posts (\(http.statusCode))"
                    self.isLoading = false
                }
                return
            }

            // Robust decoding: handle bare arrays and common wrapped shapes
            struct PostsDataEnvelope: Decodable { let data: [APIPost]? }
            struct PostsPostsEnvelope: Decodable { let posts: [APIPost]? }
            struct PostsResultEnvelope: Decodable { let result: [APIPost]? }

            let decoder = JSONDecoder()
            var items: [APIPost] = []
            if let arr = try? decoder.decode([APIPost].self, from: data) {
                items = arr
            } else if let env = try? decoder.decode(PostsDataEnvelope.self, from: data), let arr = env.data {
                items = arr
            } else if let env = try? decoder.decode(PostsPostsEnvelope.self, from: data), let arr = env.posts {
                items = arr
            } else if let env = try? decoder.decode(PostsResultEnvelope.self, from: data), let arr = env.result {
                items = arr
            } else if let any = try? JSONSerialization.jsonObject(with: data, options: []),
                      let dict = any as? [String: Any],
                      let dataObj = dict["data"] as? [String: Any],
                      let nestedArrAny = (dataObj["items"] as? [[String: Any]]) ?? (dataObj["posts"] as? [[String: Any]]) {
                let arrData = try JSONSerialization.data(withJSONObject: nestedArrAny, options: [])
                items = try decoder.decode([APIPost].self, from: arrData)
            } else {
                // Fallback: search common keys in a generic JSON object
                if let any = try? JSONSerialization.jsonObject(with: data, options: []),
                   let dict = any as? [String: Any] {
                    let candidateKeys = ["data", "posts", "items", "result"]
                    if let key = candidateKeys.first(where: { dict[$0] is [[String: Any]] }),
                       let arrAny = dict[key] as? [[String: Any]] {
                        let arrData = try JSONSerialization.data(withJSONObject: arrAny, options: [])
                        items = try decoder.decode([APIPost].self, from: arrData)
                    } else {
                        throw DecodingError.typeMismatch([APIPost].self, DecodingError.Context(codingPath: [], debugDescription: "No posts array found"))
                    }
                } else {
                    throw DecodingError.typeMismatch([APIPost].self, DecodingError.Context(codingPath: [], debugDescription: "Unexpected JSON shape"))
                }
            }
            var mapped: [Post] = items.map { api in
                let parsedTimestamp = parseDate(isoString: api.createdAt, ts: api.timestamp, tsMs: api.timestampMs)
                let tsStr = api.timestamp?.asInt()?.description ?? "nil"
                let tsMsStr = api.timestampMs?.asInt()?.description ?? "nil"
                print("🔍 LASKO: Parsing post \(api.sequentialCode ?? "nil"): createdAt=\(api.createdAt ?? "nil"), timestamp=\(tsStr), timestampMs=\(tsMsStr) -> parsed=\(parsedTimestamp)")
                return Post(
                    id: api.sequentialCode ?? api.code ?? api.id ?? UUID().uuidString,
                    content: api.content ?? "",
                    author: getDisplayName(for: api.userAddress ?? api.author ?? api.address ?? "Unknown"),
                    timestamp: parsedTimestamp,
                    likes: api.likesCount?.asInt() ?? api.likes ?? 0,
                    replies: api.repliesCount?.asInt() ?? api.replies ?? 0,
                    isLiked: false,
                    userRank: api.userRank ?? "Bronze",
                    tlsAddress: api.userAddress ?? api.address,
                    broadcastCount: api.broadcastCount?.asInt() ?? 0,
                    tlsCount: api.tlsCount?.asInt() ?? 0,
                    followerCount: api.followerCount?.asInt() ?? 0
                )
            }

            // Also fetch user's own posts to ensure previously created posts appear
            if let userURL = URL(string: "\(effectiveBaseURL)/users/\(tls)/posts?limit=50") {
                var userReq = URLRequest(url: userURL)
                userReq.httpMethod = "GET"
                userReq.setValue("application/json", forHTTPHeaderField: "Accept")
                userReq.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
                userReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let bundleId = Bundle.main.bundleIdentifier { userReq.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
                if let (uData, uResp) = try? await URLSession.shared.data(for: userReq),
                   let http2 = uResp as? HTTPURLResponse, http2.statusCode < 400 {
                    if let arr = try? decoder.decode([APIPost].self, from: uData) {
                        let more = arr.map { api in
                            Post(
                                id: api.sequentialCode ?? api.code ?? api.id ?? UUID().uuidString,
                                content: api.content ?? "",
                                author: getDisplayName(for: api.userAddress ?? api.author ?? api.address ?? "Unknown"),
                                timestamp: parseDate(isoString: api.createdAt, ts: api.timestamp, tsMs: api.timestampMs),
                                likes: api.likesCount?.asInt() ?? api.likes ?? 0,
                                replies: api.repliesCount?.asInt() ?? api.replies ?? 0,
                                isLiked: false,
                                userRank: api.userRank ?? "Bronze",
                                tlsAddress: api.userAddress ?? api.address,
                                broadcastCount: api.broadcastCount?.asInt() ?? 0,
                                tlsCount: api.tlsCount?.asInt() ?? 0,
                                followerCount: api.followerCount?.asInt() ?? 0
                            )
                        }
                        // Deduplicate by id
                        let existingIds = Set(mapped.map { $0.id })
                        mapped.append(contentsOf: more.filter { !existingIds.contains($0.id) })
                    }
                }
            }

            // For now, use the replies count from the API response
            // The comment counts should be accurate from the server
            print("🔍 LASKO: Using reply counts from API response for \(mapped.count) posts")
            DispatchQueue.main.async {
                self.posts = mapped
                self.isLoading = false
            }
            print("✅ LASKO: Loaded \(mapped.count) posts")
            for (i, post) in mapped.enumerated() {
                print("🔍 LASKO: Post \(i): id=\(post.id), timestamp=\(post.timestamp), content=\(String(post.content.prefix(30)))")
            }
        } catch {
            print("❌ LASKO: fetchPosts error: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to load posts"
                self.isLoading = false
            }
        }
    }

    // MARK: - Comments API
    func fetchComments(forSequentialCode code: String) async {
        print("🔍 LASKO: fetchComments called for code: \(code)")
        // Ensure auth
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty else { 
            print("❌ LASKO: fetchComments failed - no TLS address")
                return
        }
        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else { 
            print("❌ LASKO: fetchComments failed - no token")
                    return
                }
        
        // Fetch all comments for this post (including nested replies)
        let _ = await fetchAllNestedComments(forPostCode: code, token: token)
    }
    
    private func fetchAllNestedComments(forPostCode postCode: String, token: String) async -> Int {
        print("🔍 LASKO: fetchAllNestedComments called for post: \(postCode)")
        
        // Comments are stored as posts with parentSequentialCode, so query the main posts endpoint
        guard let url = URL(string: "\(effectiveBaseURL)/posts?parentSequentialCode=\(postCode)") else {
            print("❌ LASKO: Invalid URL for fetching comments for post \(postCode).")
            return 0
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("❌ LASKO: fetchAllNestedComments server error for \(postCode): \(statusCode) \(responseString)")
                return 0
            }

            // Reuse decoding helpers
            struct APIPost: Decodable {
                let id: String?
                let sequentialCode: String?
                let code: String?
                let content: String?
                let author: String?
                let address: String?
                let userAddress: String?
                let parentSequentialCode: String?
                let parentCode: String?
                let createdAt: String?
                let timestamp: IntOrString?
                let timestampMs: IntOrString?
                let likes: Int?
                let likesCount: IntOrString?
                let replies: Int?
                let repliesCount: IntOrString?
                let userRank: String?
            }
            struct Envelope: Decodable { let data: [APIPost]? }
            
            let decoder = JSONDecoder()
            var items: [APIPost] = []
            if let arr = try? decoder.decode([APIPost].self, from: data) {
                items = arr
            } else if let env = try? decoder.decode(Envelope.self, from: data), let arr = env.data {
                items = arr
            } else if let any = try? JSONSerialization.jsonObject(with: data, options: []), let dict = any as? [String: Any], let arrAny = dict["data"] as? [[String: Any]] {
                let arrData = try JSONSerialization.data(withJSONObject: arrAny, options: [])
                items = (try? decoder.decode([APIPost].self, from: arrData)) ?? []
            }

            var allComments: [Post] = []
            var totalCount = 0

            for apiComment in items {
                let parsedTimestamp = parseDate(isoString: apiComment.createdAt, ts: apiComment.timestamp, tsMs: apiComment.timestampMs)
                let comment = Post(
                    id: apiComment.sequentialCode ?? apiComment.code ?? apiComment.id ?? UUID().uuidString,
                    content: apiComment.content ?? "",
                    author: getDisplayName(for: apiComment.userAddress ?? apiComment.address ?? ""),
                    timestamp: parsedTimestamp,
                    likes: apiComment.likesCount?.asInt() ?? apiComment.likes ?? 0,
                    replies: apiComment.repliesCount?.asInt() ?? apiComment.replies ?? 0,
                    isLiked: false,
                    userRank: apiComment.userRank ?? "Bronze",
                    avatarURL: nil,
                    parentCode: apiComment.parentSequentialCode
                )
                allComments.append(comment)
                totalCount += 1

                // Recursively fetch nested comments
                if let commentCode = apiComment.sequentialCode {
                    let nestedCount = await fetchAllNestedComments(forPostCode: commentCode, token: token)
                    totalCount += nestedCount
                }
            }

            await MainActor.run {
                self.repliesByCode[postCode] = allComments.sorted { $0.timestamp < $1.timestamp }
                print("✅ LASKO: Fetched \(allComments.count) comments for \(postCode)")
            }
            return totalCount

        } catch {
            print("❌ LASKO: Error fetching comments for post \(postCode): \(error.localizedDescription)")
            return 0
        }
    }

    func createComment(content: String, parentSequentialCode code: String) async -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Ensure auth
        var tlsAddress = currentTLSAddress
        if !isAuthenticatedWithZeroa || (tlsAddress ?? "").isEmpty {
            if let addr = appGroupsService.getTLSAddress(), !addr.isEmpty,
               let _ = appGroupsService.sharedDefaults?.string(forKey: "halo_access_token") ?? appGroupsService.sharedDefaults?.string(forKey: "haloAccessToken") {
                self.isAuthenticatedWithZeroa = true
                self.currentTLSAddress = addr
                tlsAddress = addr
            }
        }
        guard isAuthenticatedWithZeroa, let tls = tlsAddress else { return false }
        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else { return false }
        let allowed = CharacterSet.urlPathAllowed
        guard let encoded = code.addingPercentEncoding(withAllowedCharacters: allowed) else { return false }
        // Use the correct indexer endpoint: POST /posts with parentSequentialCode for replies
        guard let url = URL(string: "\(effectiveBaseURL)/posts") else { return false }
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let bundleId = Bundle.main.bundleIdentifier { req.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            var body: [String: Any] = [
                "content": trimmed,
                "userAddress": tls,
                "timestamp": nowMs,
                "postType": "free",
                "parentSequentialCode": code  // This makes it a reply/comment
            ]
            if let pubHex = appGroupsService.sharedDefaults?.string(forKey: "zeroa_pubkey_compressed_hex") {
                body["pubkey"] = pubHex
            }
            if body["signature"] == nil {
                let contentHashHex = sha256Hex(of: Data(trimmed.utf8))
                let signReq: [String: Any] = ["contentHashHex": contentHashHex, "timestamp": nowMs]
                appGroupsService.sharedDefaults?.set(signReq, forKey: "lasko_post_sign_request")
                appGroupsService.sharedDefaults?.synchronize()
                var tries = 0
                while tries < 100 { // Increased timeout for signature polling to 10s
                    if let resp = appGroupsService.sharedDefaults?.dictionary(forKey: "lasko_post_sign_response"),
                       let sig = resp["signatureBase64"] as? String,
                       let pub = resp["pubkeyCompressedHex"] as? String {
                        body["signature"] = sig
                        body["pubkey"] = pub
                        appGroupsService.sharedDefaults?.removeObject(forKey: "lasko_post_sign_response")
                        break
                    }
                    tries += 1
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard body["signature"] != nil else { return false }
            }
            print("🔗 LASKO: POST /posts (comment) parent=\(code) tls=\(tls) contentLen=\(trimmed.count)")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 && http.statusCode != 201 {
                print("❌ LASKO: createComment server error: \(http.statusCode) \(String(data: data, encoding: .utf8) ?? "")")
                return false
            }
            // After posting a comment, refresh the main post's comments to show the new comment
            if let mainPostCode = getMainPostCode(forCommentCode: code) {
                await fetchComments(forSequentialCode: mainPostCode)
            } else {
                await fetchComments(forSequentialCode: code)
            }
            // Refresh main posts to update reply counts in UI
            await fetchPosts()
            return true
        } catch {
            print("❌ LASKO: createComment error: \(error)")
            return false
        }
    }
    
    // Legacy helper kept for compatibility with older call sites
    func createPost(content: String, author: String) async -> Bool {
        await createPost(content: content)
    }
    
    // MARK: - New Create Post (parity with older app)
    struct CreatePostRequest: Codable {
        let content: String
        let tlsAddress: String
        let signature: String
        let timestamp: Int64
        let postType: String
        let zeroaSessionId: String?
        let zeroaVersion: String?
    }
    
    struct LASKOPostSignature {
        let publicKey: String
        let signature: String
        let timestamp: Int64
    }
    
    private func signPost(_ content: String, address: String) -> LASKOPostSignature {
        // Placeholder signing – replace with real signing when available
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let sig = "mock-signature-\(ts)"
        return LASKOPostSignature(publicKey: address, signature: sig, timestamp: ts)
    }
    
    func createPost(content: String) async -> Bool {
        print("🚀 LASKO: createPost called with content length: \(content.count)")
        // Validation
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { 
            print("❌ LASKO: createPost failed - empty content")
            return false 
        }
        guard trimmed.count <= 1000 else { 
            print("❌ LASKO: createPost failed - content too long: \(trimmed.count)")
            return false 
        }
        // Ensure auth: soft-recover from App Groups if in-memory flag is out-of-sync
        var tlsAddress = currentTLSAddress
        if !isAuthenticatedWithZeroa || (tlsAddress ?? "").isEmpty {
            if let addr = appGroupsService.getTLSAddress(), !addr.isEmpty,
               let _ = appGroupsService.sharedDefaults?.string(forKey: "halo_access_token") ??
                         appGroupsService.sharedDefaults?.string(forKey: "haloAccessToken") {
                self.isAuthenticatedWithZeroa = true
                self.currentTLSAddress = addr
                tlsAddress = addr
                print("✅ LASKO: Recovered auth state from App Groups for posting")
            }
        }
        guard isAuthenticatedWithZeroa, let tlsAddress = tlsAddress else {
            print("❌ LASKO: Cannot create post - not authenticated with Zeroa. isAuth=\(isAuthenticatedWithZeroa), tls=\(tlsAddress ?? "nil")")
            return false
        }
        print("✅ LASKO: Auth check passed, proceeding with post creation")
        
        do {
            var req = URLRequest(url: URL(string: "\(effectiveBaseURL)/posts")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            // Removed X-Moderation-Preview to enable live posting
            if let bundleId = Bundle.main.bundleIdentifier { req.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
            print("🔍 LASKO: Getting token for address: \(tlsAddress)")
            guard let token = await ensureTokenForAddress(tlsAddress, timeoutSeconds: 8.0) else {
                print("❌ LASKO: Cannot create post - missing or expired token")
                return false
            }
            print("✅ LASKO: Got token for post creation: \(String(token.prefix(20)))...")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // Pass TLS address as header for backend convenience
            req.setValue(tlsAddress, forHTTPHeaderField: "X-TLS-Address")
            // Build body to match server contract (userAddress, signature, pubkey, timestamp in ms)
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            var body: [String: Any] = [
                "content": trimmed,
                "userAddress": tlsAddress,
                "postType": "free",
                "timestamp": nowMs
            ]
            if let pubHex = appGroupsService.sharedDefaults?.string(forKey: "zeroa_pubkey_compressed_hex") {
                body["pubkey"] = pubHex
            }
            // Try silent post-sign: request signature from Zeroa if not already present
            if body["signature"] == nil {
                print("🔍 LASKO: Requesting signature from Zeroa for post")
                let contentHashHex = sha256Hex(of: Data(trimmed.utf8))
                let signReq: [String: Any] = ["contentHashHex": contentHashHex, "timestamp": nowMs]
                appGroupsService.sharedDefaults?.set(signReq, forKey: "lasko_post_sign_request")
                appGroupsService.sharedDefaults?.synchronize()
                // Poll briefly for response (up to 3s)
                var tries = 0
                while tries < 30 {
                    if let resp = appGroupsService.sharedDefaults?.dictionary(forKey: "lasko_post_sign_response"),
                       let sig = resp["signatureBase64"] as? String,
                       let pub = resp["pubkeyCompressedHex"] as? String {
                        body["signature"] = sig
                        body["pubkey"] = pub
                        appGroupsService.sharedDefaults?.removeObject(forKey: "lasko_post_sign_response")
                break
            }
                    tries += 1
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard body["signature"] != nil else { 
                    print("❌ LASKO: Failed to get signature from Zeroa after 3s")
                    return false 
                }
                print("✅ LASKO: Got signature from Zeroa for post")
            }
            let payload = body
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            print("🔗 LASKO: POST /posts base=\(effectiveBaseURL) tls=\(tlsAddress) contentLen=\(trimmed.count)")
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 && http.statusCode != 201 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                var detail = bodyStr
                if let any = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let parts = [any["error"], any["message"], any["reason"], any["code"]].compactMap { $0 as? String }
                    if !parts.isEmpty { detail = parts.joined(separator: " | ") }
                }
                print("❌ LASKO: createPost server error: status=\(http.statusCode) detail=\(detail)")
                if http.statusCode == 401 {
                    if let token2 = await ensureTokenForAddress(tlsAddress, timeoutSeconds: 8.0) {
                        req.setValue("Bearer \(token2)", forHTTPHeaderField: "Authorization")
                        let (data2, resp2) = try await URLSession.shared.data(for: req)
                        if let http2 = resp2 as? HTTPURLResponse, (http2.statusCode == 200 || http2.statusCode == 201) {
                DispatchQueue.main.async {
                    let newPost = Post(
                        content: trimmed,
                                    author: tlsAddress,
                        timestamp: Date(),
                        likes: 0,
                        replies: 0,
                        userRank: "Bronze"
                    )
                    self.posts.insert(newPost, at: 0)
                }
                return true
            } else {
                            print("❌ LASKO: retry after token refresh failed: \((resp2 as? HTTPURLResponse)?.statusCode ?? -1) \(String(data: data2, encoding: .utf8) ?? "")")
                        }
                    }
                }
                return false
            }
            // Success: try to extract LAS# from response for logging
            if let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                var las: String? = obj["sequentialCode"] as? String
                if las == nil, let dataObj = obj["data"] as? [String: Any] { las = dataObj["sequentialCode"] as? String }
                if let las = las { print("✅ LASKO: Post created with LAS=\(las)") }
            }
            DispatchQueue.main.async {
                let newPost = Post(
                    content: trimmed,
                    author: tlsAddress,
                    timestamp: Date(),
                    likes: 0,
                    replies: 0,
                    userRank: "Bronze"
                )
                self.posts.insert(newPost, at: 0)
            }
                return true
        } catch {
            print("❌ LASKO: createPost error: \(error)")
            return false
        }
    }
    
    func likePost(_ post: Post) async {
        // Mock implementation for now
        DispatchQueue.main.async {
            if let index = self.posts.firstIndex(where: { $0.id == post.id }) {
                self.posts[index] = Post(
                    id: post.id,
                    content: post.content,
                    author: post.author,
                    timestamp: post.timestamp,
                    likes: post.likes + 1,
                    replies: post.replies,
                    isLiked: true,
                    userRank: post.userRank
                )
            }
        }
    }
    
    // Helper function to find the main post code for a given comment
    private func getMainPostCode(forCommentCode commentCode: String) -> String? {
        // First, check if this comment is directly under a main post
        if let replies = repliesByCode[commentCode] {
            for reply in replies {
                if reply.parentCode == commentCode {
                    // This is a direct reply to the main post
                    return commentCode
                }
            }
        }
        
        // If not, traverse up the comment chain to find the main post
        var currentCode = commentCode
        var visited = Set<String>()
        
        while !visited.contains(currentCode) {
            visited.insert(currentCode)
            
            // Look for this comment in all reply collections
            for (postCode, replies) in repliesByCode {
                if let comment = replies.first(where: { $0.id == currentCode }) {
                    if let parentCode = comment.parentCode, !parentCode.isEmpty {
                        // Check if parent is a main post (no parent or parent is the post itself)
                        if parentCode == postCode || repliesByCode[parentCode] == nil {
                            return postCode
                        }
                        currentCode = parentCode
                        break
                    } else {
                        // This comment has no parent, so it's directly under the main post
                        return postCode
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Blockchain Methods (Placeholder)
    
    func getBlockchainInfo() async -> TelestaiBlock? {
        // Placeholder for future implementation
        return nil
    }
    
    func getNextBlockTiming() async -> (height: Int, estimatedTime: Date)? {
        // Placeholder for future implementation
        return nil
    }
    
    func getAddressBalance(address: String) async -> TelestaiAddress? {
        // Placeholder for future implementation
        return nil
    }
    
    func signMessage(message: String, address: String, privateKey: String) async -> TelestaiMessage? {
        // Placeholder for future implementation
        return nil
    }
    
    func verifyMessage(message: String, signature: String, address: String) async -> Bool {
        // Placeholder for future implementation
        return false
    }

    private func verifySignature(address: String, message: String, signature: String) async -> Bool {
        // For now, defer to backend verification when available; if not, return true to unblock
        // TODO: Replace with call to Indexer verify endpoint for message/signature
        // let ok = await Backend.verify(address: address, message: message, signature: signature)
        return true
    }
    
    // MARK: - Username Management
    
    func getDisplayName(for address: String) -> String {
        print("🔍 LASKO: getDisplayName called for address: \(address)")
        print("🔍 LASKO: currentTLSAddress: \(currentTLSAddress ?? "nil")")
        print("🔍 LASKO: username: \(username)")
        
        // If this is the current user's address, return their username
        if address == currentTLSAddress {
            print("✅ LASKO: Address matches current user, returning username: \(username)")
            return username
        }
        // For other users, return a shortened version of their address
        let displayName = address.isEmpty ? "User" : String(address.prefix(8)) + "..."
        print("✅ LASKO: Address is different user, returning shortened: \(displayName)")
        return displayName
    }
}

// MARK: - Placeholder Models for Telestai
struct TelestaiBlock {
    let height: Int
    let hash: String
    let timestamp: Int
    let transactions: [String]
}

struct TelestaiAddress {
    let address: String
    let balance: Double
    let unconfirmedBalance: Double
    let txCount: Int
}

struct TelestaiMessage {
    let message: String
    let signature: String
    let address: String
    let timestamp: Int
}

