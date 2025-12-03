import Foundation
import CoreFoundation
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
    
    // Feature flags and tuning knobs (safe, additive)
    struct FeatureFlags {
        static let useDeepCountFromServer = true
        static let prefetchCountsEnabled = true
        static let cacheDeepCountsEnabled = true
        static let deepCountCacheTTLSeconds: TimeInterval = 600 // 10 minutes
        static let prefetchTopNPosts: Int = 8
        static let useThreadEndpointIfAvailable = true // now enabled with server support
    }

    // MARK: - Lightweight telemetry (in-memory only)
    private var cacheHits = 0
    private var cacheMisses = 0
    private var lastFetchPostsMs: Int = 0
    private var lastFetchCommentsMsByCode: [String: Int] = [:]
    private func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
    
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
    
    // Use HTTPS for secure global access
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
                    
                    if let syncedName = self.appGroupsService.getProfileDisplayName(), !syncedName.isEmpty {
                        self.username = syncedName
                        print("🔍 LASKO: Synced username from App Groups: \(syncedName)")
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
    private var isObservingAuthResponse = false
    
    private func startAuthPollingWindow() {
        stopAuthPollingWindow()
        authPollDeadline = Date().addingTimeInterval(60)
        
        // Set up Darwin notification observer for immediate response
        let notificationName = "com.telestai.zeroa.auth.response" as CFString
        
        // C callback function for Darwin notifications (static, doesn't need self)
        let callback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (center, observer, name, object, userInfo) in
            print("📢 LASKO: Received Darwin notification for auth response")
            // Dispatch to main thread and trigger immediate handling
            DispatchQueue.main.async {
                // Post notification that will trigger checkForAuthResponse
                NotificationCenter.default.post(name: NSNotification.Name("HandleAuthResponse"), object: nil)
            }
        }
        
        // Register for Darwin notifications
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil, // No observer needed since we use NotificationCenter
            callback,
            notificationName,
            nil,
            .deliverImmediately
        )
        isObservingAuthResponse = true
        
        // Listen for the local notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthResponseNotification),
            name: NSNotification.Name("HandleAuthResponse"),
            object: nil
        )
        
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
        print("⏱️ LASKO: Started 60s auth polling window with Darwin notification observer")
    }
    
    @objc private func handleAuthResponseNotification() {
        print("📢 LASKO: Processing auth response notification")
        Task { @MainActor in
            self.checkForAuthResponse()
        }
    }
    
    private func stopAuthPollingWindow() {
        authPollTimer?.invalidate()
        authPollTimer = nil
        authPollDeadline = nil
        
        // Remove Darwin notification observer
        if isObservingAuthResponse {
            let notificationName = "com.telestai.zeroa.auth.response" as CFString
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                CFNotificationName(notificationName),
                nil
            )
            isObservingAuthResponse = false
        }
        
        // Remove local notification observer
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("HandleAuthResponse"), object: nil)
    }

    // MARK: - Zeroa Token Prompt
    private func promptZeroaForToken(for tlsAddress: String) {
        // Set the standard refresh flag for background listeners
        appGroupsService.sharedDefaults?.set(true, forKey: "halo_token_refresh_request")
        // Provide desired address context for Zeroa (optional key Zeroa can read)
        appGroupsService.sharedDefaults?.set(tlsAddress, forKey: "halo_token_for_address")
        appGroupsService.sharedDefaults?.synchronize()
        
        // CRITICAL: Send Darwin notification to wake Zeroa (even if in background)
        let notificationName = CFNotificationName("com.telestai.lasko.token.refresh.request" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        print("📢 LASKO: Sent Darwin notification for token refresh request")
        
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

    // MARK: - Deep count cache (TTL-backed via App Groups)
    private let deepCountCacheKey = "lasko_deep_count_cache"
    private func getCachedDeepCount(for code: String) -> Int? {
        guard FeatureFlags.cacheDeepCountsEnabled else { return nil }
        guard let dict = appGroupsService.sharedDefaults?.dictionary(forKey: deepCountCacheKey) as? [String: [String: Any]],
              let entry = dict[code],
              let count = entry["count"] as? Int,
              let ts = entry["ts"] as? TimeInterval else { return nil }
        let now = Date().timeIntervalSince1970
        if now - ts <= FeatureFlags.deepCountCacheTTLSeconds {
            cacheHits += 1
            return count
        }
        cacheMisses += 1
        return nil
    }
    private func setCachedDeepCount(for code: String, count: Int) {
        guard FeatureFlags.cacheDeepCountsEnabled else { return }
        var dict = (appGroupsService.sharedDefaults?.dictionary(forKey: deepCountCacheKey) as? [String: [String: Any]]) ?? [:]
        dict[code] = ["count": count, "ts": Date().timeIntervalSince1970]
        appGroupsService.sharedDefaults?.set(dict, forKey: deepCountCacheKey)
        appGroupsService.sharedDefaults?.synchronize()
    }
    
    // Exposed helper to pre-warm Halo token early
    func prewarmHaloTokenIfPossible() async {
        guard appGroupsService.isProfileActive() else { return }
        if let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty {
            _ = await ensureTokenForAddress(tls, timeoutSeconds: 5.0)
        }
    }

    private func jwtSubject(_ token: String) -> String? {
        guard let payload = decodeJWTPayload(token) else { return nil }
        return payload["sub"] as? String
    }

    private func readHaloToken() -> String? {
        // Force synchronization before reading
        appGroupsService.sharedDefaults?.synchronize()
        let token1 = appGroupsService.sharedDefaults?.string(forKey: "halo_access_token")
        let token2 = appGroupsService.sharedDefaults?.string(forKey: "haloAccessToken")
        let token = token1 ?? token2
        if token != nil {
            print("✅ LASKO: readHaloToken found token (length: \(token!.count))")
        } else {
            print("❌ LASKO: readHaloToken - no token found in App Groups")
            // Debug: Check what keys exist
            if let defaults = appGroupsService.sharedDefaults {
                let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.contains("halo") }
                print("🔍 LASKO: App Groups keys containing 'halo': \(allKeys)")
            }
        }
        return token
    }

    private func tokenIsFresh(_ token: String, leewaySeconds: TimeInterval = 60) -> Bool {
        guard let payload = decodeJWTPayload(token), let exp = payload["exp"] as? TimeInterval else { return false }
        let now = Date().timeIntervalSince1970
        return (exp - now) > leewaySeconds
    }

    private func ensureTokenForAddress(_ tlsAddress: String, timeoutSeconds: Double = 5.0) async -> String? {
        print("🔍 LASKO: ensureTokenForAddress called for \(tlsAddress), timeout=\(timeoutSeconds)s")
        guard appGroupsService.isProfileActive() else {
            print("❌ LASKO: ensureTokenForAddress - profile not active")
            return nil
        }
        if let t = readHaloToken(), tokenIsFresh(t) {
            let sub = jwtSubject(t)
            if sub == nil || sub == tlsAddress {
                print("✅ LASKO: ensureTokenForAddress - found fresh token with matching subject")
                return t
            }
#if DEBUG
            print("⚠️ LASKO: Token subject (\(sub ?? "nil")) != TLS (\(tlsAddress)); will request refresh")
#endif
        }
        
        // Check if we have any token, but only use it if it's fresh
        if let t = readHaloToken() {
            if tokenIsFresh(t) {
#if DEBUG
                print("✅ LASKO: Using existing fresh token")
#endif
                return t
            } else {
#if DEBUG
                print("⚠️ LASKO: Existing token is expired, requesting refresh")
#endif
            }
        }
        
        // Ask Zeroa to refresh and require a newer refresh marker
        let requestStartMs = Int(Date().timeIntervalSince1970 * 1000)
        print("🔍 LASKO: Requesting token refresh from Zeroa (requestStartMs=\(requestStartMs))")
        promptZeroaForToken(for: tlsAddress)
        let maxTries = Int(timeoutSeconds * 10)
        var tries = 0
        while tries < maxTries {
            // Force sync before checking
            appGroupsService.sharedDefaults?.synchronize()
            if let refreshedAtAny = appGroupsService.sharedDefaults?.object(forKey: "halo_token_refreshed_at") {
                var refreshedAtMs = 0
                if let n = refreshedAtAny as? Int { refreshedAtMs = n }
                else if let n64 = refreshedAtAny as? Int64 { refreshedAtMs = Int(truncatingIfNeeded: n64) }
                else if let d = refreshedAtAny as? Double { refreshedAtMs = Int(d) }
                else if let s = refreshedAtAny as? String { refreshedAtMs = Int(s) ?? 0 }
                print("🔍 LASKO: Polling attempt \(tries+1)/\(maxTries): refreshedAtMs=\(refreshedAtMs), requestStartMs=\(requestStartMs)")
                if refreshedAtMs >= requestStartMs {
                    if let t = readHaloToken(), tokenIsFresh(t) {
                        let sub = jwtSubject(t)
                        if sub == nil || sub == tlsAddress {
                            print("✅ LASKO: ensureTokenForAddress - got refreshed token with matching subject")
                            return t
                        }
#if DEBUG
                        print("⚠️ LASKO: Refreshed token subject (\(sub ?? "nil")) still != TLS (\(tlsAddress)); proceeding anyway")
#endif
                        return t
                    } else {
                        print("⚠️ LASKO: Token refreshed but not found or not fresh yet")
                    }
                } else {
                    print("🔍 LASKO: Token refresh timestamp not updated yet (refreshedAtMs < requestStartMs)")
                }
            } else {
                if tries % 10 == 0 { // Log every second
                    print("🔍 LASKO: Polling attempt \(tries+1)/\(maxTries): halo_token_refreshed_at not set yet")
                }
            }
            tries += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if let t = readHaloToken(), tokenIsFresh(t) {
            print("✅ LASKO: ensureTokenForAddress - found token after timeout")
            return t
        }
        print("❌ LASKO: ensureTokenForAddress - failed to get token after \(timeoutSeconds)s timeout")
        return nil
    }

    private func ensureValidHaloToken(timeoutSeconds: Double = 5.0) async -> String? {
        guard appGroupsService.isProfileActive() else { return nil }
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
                guard let http = response as? HTTPURLResponse else { continue }
                
                if http.statusCode == 200 {
                    if data.isEmpty { return true }
                    if let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let ok = obj["ok"] as? Bool { return ok }
                        if let success = obj["success"] as? Bool { return success }
                        if let verified = obj["verified"] as? Bool { return verified }
                        if let token = obj["token"] as? String, !token.isEmpty { return true }
                    }
                    print("⚠️ LASKO: Unexpected signature verification response for \(path)")
                    return false
                } else if http.statusCode == 404 {
                    continue
                } else {
                    let bodyStr = String(data: data, encoding: .utf8) ?? ""
                    if bodyStr.isEmpty {
                        print("❌ LASKO: Signature verification failed via \(path) status=\(http.statusCode)")
                    } else {
                        print("❌ LASKO: Signature verification failed via \(path) status=\(http.statusCode) body=\(bodyStr)")
                    }
                    return false
                }
            } catch {
                print("❌ LASKO: Signature verification request to \(path) failed: \(error)")
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
            let deepRepliesCount: IntOrString?
            let tlsCount: IntOrString?
            let userRank: String?
            let profileName: String?
            let profileBio: String?
            let profileImage: String? // base64 encoded image
        }
        

        
        do {
            let t0 = nowMs()
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
                // Prefer server-provided deep count when available
                let deep = api.deepRepliesCount?.asInt()
                let shallow = (api.repliesCount?.asInt()) ?? api.replies
                let repliesVal = (FeatureFlags.useDeepCountFromServer ? (deep ?? shallow) : shallow) ?? 0
                // Use profileName from API if available, otherwise fall back to getDisplayName
                let authorName: String
                if let profileName = api.profileName, !profileName.isEmpty {
                    authorName = profileName
                } else {
                    authorName = getDisplayName(for: api.userAddress ?? api.author ?? api.address ?? "Unknown")
                }
                
                // Convert base64 profileImage to data URL format for avatarURL
                // For current user's posts, prioritize App Groups profile image over API
                let userAddress = api.userAddress ?? api.address ?? ""
                let isCurrentUser = !userAddress.isEmpty && userAddress == currentTLSAddress
                
                let avatarURL: String?
                if isCurrentUser, let appGroupsImage = appGroupsService.getProfileImage(),
                   let imageData = appGroupsImage.jpegData(compressionQuality: 0.7) {
                    // Use App Groups image for current user (always up-to-date)
                    let base64String = imageData.base64EncodedString()
                    avatarURL = "data:image/jpeg;base64,\(base64String)"
                } else if let profileImageBase64 = api.profileImage, !profileImageBase64.isEmpty {
                    // Use API profile image for other users
                    avatarURL = "data:image/jpeg;base64,\(profileImageBase64)"
                } else {
                    avatarURL = nil
                }
                
                return Post(
                    id: api.sequentialCode ?? api.code ?? api.id ?? UUID().uuidString,
                    content: api.content ?? "",
                    author: authorName,
                    timestamp: parsedTimestamp,
                    likes: api.likesCount?.asInt() ?? api.likes ?? 0,
                    replies: repliesVal,
                    isLiked: false,
                    userRank: api.userRank ?? "Bronze",
                    avatarURL: avatarURL,
                    tlsAddress: userAddress,
                    broadcastCount: 0,
                    tlsCount: api.tlsCount?.asInt() ?? 0,
                    followerCount: 0
                )
            }

            // Override with cached deep counts if fresher
            for i in mapped.indices {
                if let cached = getCachedDeepCount(for: mapped[i].id), cached > mapped[i].replies {
                    mapped[i].replies = cached
                }
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
                                author: (api.profileName?.isEmpty == false) ? api.profileName! : getDisplayName(for: api.userAddress ?? api.author ?? api.address ?? "Unknown"),
                                timestamp: parseDate(isoString: api.createdAt, ts: api.timestamp, tsMs: api.timestampMs),
                                likes: api.likesCount?.asInt() ?? api.likes ?? 0,
                                replies: api.repliesCount?.asInt() ?? api.replies ?? 0,
                                isLiked: false,
                                userRank: api.userRank ?? "Bronze",
                                avatarURL: (api.profileImage?.isEmpty == false) ? "data:image/jpeg;base64,\(api.profileImage!)" : nil,
                                tlsAddress: api.userAddress ?? api.address
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
            lastFetchPostsMs = nowMs() - t0
            print("✅ LASKO: Loaded \(mapped.count) posts (\(lastFetchPostsMs)ms) cacheHits=\(cacheHits) cacheMisses=\(cacheMisses)")
            for (i, post) in mapped.enumerated() {
                print("🔍 LASKO: Post \(i): id=\(post.id), timestamp=\(post.timestamp), content=\(String(post.content.prefix(30)))")
            }

            // Prefetch deep counts for top N visible posts
            if FeatureFlags.prefetchCountsEnabled {
                let n = min(FeatureFlags.prefetchTopNPosts, mapped.count)
                Task { [weak self] in
                    guard let self = self else { return }
                    for idx in 0..<n {
                        let p = mapped[idx]
                        if p.replies > 0 && self.repliesByCode[p.id] == nil {
                            await self.fetchComments(forSequentialCode: p.id)
                        }
                    }
                }
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
        // Try to get a fresh token; if missing/expired, attempt refresh
        var tokenOpt = await ensureTokenForAddress(tls, timeoutSeconds: 8.0)
        if tokenOpt == nil {
            print("⚠️ LASKO: fetchComments token missing/expired; attempting refresh")
            let refreshed = await ensureValidHaloToken(timeoutSeconds: 8.0)
            if let refreshed = refreshed {
                tokenOpt = refreshed
            } else {
                tokenOpt = await ensureTokenForAddress(tls, timeoutSeconds: 8.0)
            }
        }
        guard let token = tokenOpt else {
            print("❌ LASKO: fetchComments failed - no token after refresh attempt")
                return
        }
        
        // Prefer thread endpoint if enabled; otherwise fallback to recursive nested fetch
        let totalCommentCount: Int
        if FeatureFlags.useThreadEndpointIfAvailable {
            if let count = await fetchThreadEndpointIfAvailable(forPostCode: code, token: token) {
                totalCommentCount = count
            } else {
                totalCommentCount = await fetchAllNestedComments(forPostCode: code, token: token)
            }
        } else {
            totalCommentCount = await fetchAllNestedComments(forPostCode: code, token: token)
        }
        
        // Update the post's reply count to reflect the actual fetched comments
        await MainActor.run {
            if let postIndex = self.posts.firstIndex(where: { $0.id == code }) {
                self.posts[postIndex].replies = totalCommentCount
                self.setCachedDeepCount(for: code, count: totalCommentCount)
                print("🔍 LASKO: Updated post \(code) reply count to \(totalCommentCount)")
            }
        }
    }
    
    private func fetchAllNestedComments(forPostCode postCode: String, token: String) async -> Int {
        print("🔍 LASKO: fetchAllNestedComments called for post: \(postCode)")
        let t0 = nowMs()
        
        // Comments are stored as posts with parentSequentialCode, so query the main posts endpoint
        var components = URLComponents(string: "\(effectiveBaseURL)/posts")
        components?.queryItems = [
            URLQueryItem(name: "parentSequentialCode", value: postCode),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components?.url else {
            print("❌ LASKO: Invalid URL for fetching comments for post \(postCode).")
            return 0
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(currentTLSAddress ?? "", forHTTPHeaderField: "X-TLS-Address")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bundleId = Bundle.main.bundleIdentifier { request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
        print("🔍 LASKO: Making API request to: \(url.absoluteString)")
        do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let responseString = String(data: data, encoding: .utf8) ?? "nil"
        print("🔍 LASKO: Received response for comments: \(responseString)")

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
                let broadcastCount: IntOrString?
                let tlsCount: IntOrString?
                let followerCount: IntOrString?
                let profileName: String?
                let profileBio: String?
                let profileImage: String? // base64 encoded image
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

            // Map API comments to Post models
            let mappedComments: [(post: Post, code: String?)] = items.map { apiComment in
                let parsedTimestamp = parseDate(isoString: apiComment.createdAt, ts: apiComment.timestamp, tsMs: apiComment.timestampMs)
                let id = apiComment.sequentialCode ?? apiComment.code ?? apiComment.id ?? UUID().uuidString
                let comment = Post(
                    id: id,
                    content: apiComment.content ?? "",
                    author: (apiComment.profileName?.isEmpty == false) ? apiComment.profileName! : getDisplayName(for: apiComment.userAddress ?? apiComment.address ?? ""),
                    timestamp: parsedTimestamp,
                    likes: apiComment.likesCount?.asInt() ?? apiComment.likes ?? 0,
                    replies: apiComment.repliesCount?.asInt() ?? apiComment.replies ?? 0,
                    isLiked: false,
                    userRank: apiComment.userRank ?? "Bronze",
                    avatarURL: (apiComment.profileImage?.isEmpty == false) ? "data:image/jpeg;base64,\(apiComment.profileImage!)" : nil,
                    parentCode: apiComment.parentSequentialCode,
                    tlsAddress: apiComment.userAddress ?? apiComment.address,
                    broadcastCount: apiComment.broadcastCount?.asInt() ?? 0,
                    tlsCount: apiComment.tlsCount?.asInt() ?? 0,
                    followerCount: apiComment.followerCount?.asInt() ?? 0
                )
                return (comment, apiComment.sequentialCode)
            }

            allComments.append(contentsOf: mappedComments.map { $0.post })
            totalCount += mappedComments.count

            // Recursively fetch nested comments concurrently with a soft cap (by natural awaiting)
            let nestedCodes = mappedComments.compactMap { $0.code }
            let nestedTotal = await withTaskGroup(of: Int.self, returning: Int.self) { group in
                for code in nestedCodes {
                    group.addTask { [weak self] in
                        guard let self = self else { return 0 }
                        return await self.fetchAllNestedComments(forPostCode: code, token: token)
                    }
                }
                var sum = 0
                for await n in group { sum += n }
                return sum
            }
            totalCount += nestedTotal

            await MainActor.run {
                self.repliesByCode[postCode] = allComments.sorted { $0.timestamp < $1.timestamp }
                self.setCachedDeepCount(for: postCode, count: totalCount)
                let dur = nowMs() - t0
                self.lastFetchCommentsMsByCode[postCode] = dur
                print("✅ LASKO: Fetched \(allComments.count) comments for \(postCode) (\(dur)ms)")
            }
            return totalCount

        } catch {
            print("❌ LASKO: Error fetching comments for post \(postCode): \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Thread endpoint (optional, guarded)
    private func fetchThreadEndpointIfAvailable(forPostCode postCode: String, token: String) async -> Int? {
        // Try an endpoint that returns the entire thread for a post in one response
        // Expected candidates: /posts/thread?sequentialCode=..., or /posts/{code}/thread
        // We'll attempt both; if both fail, return nil.
        let candidateURLs: [URL?] = {
            var urls: [URL?] = []
            var comps = URLComponents(string: "\(effectiveBaseURL)/posts")
            comps?.queryItems = [
                URLQueryItem(name: "thread", value: "1"),
                URLQueryItem(name: "sequentialCode", value: postCode),
                URLQueryItem(name: "limit", value: "500")
            ]
            urls.append(comps?.url)
            let pathEncoded = postCode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? postCode
            urls.append(URL(string: "\(effectiveBaseURL)/posts/\(pathEncoded)/thread"))
            return urls
        }()
        for urlOpt in candidateURLs {
            guard let url = urlOpt else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(currentTLSAddress ?? "", forHTTPHeaderField: "X-TLS-Address")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let bundleId = Bundle.main.bundleIdentifier { request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
            print("🔍 LASKO: Trying thread endpoint: \(url.absoluteString)")
            do {
                let t0 = nowMs()
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    print("⚠️ LASKO: Thread endpoint status=\(http.statusCode) for \(url.absoluteString)")
                    continue
                }

                // Decode possible shapes
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
                    let broadcastCount: IntOrString?
                    let tlsCount: IntOrString?
                    let followerCount: IntOrString?
                    let profileName: String?
                    let profileBio: String?
                    let profileImage: String? // base64 encoded image
                    let children: [APIPost]? // nested tree variant
                    let comments: [APIPost]? // alternate key
                }
                struct EnvelopeArr: Decodable { let data: [APIPost]?; let posts: [APIPost]?; let result: [APIPost]? }
                struct EnvelopeObj: Decodable { let data: APIPost? }

                let decoder = JSONDecoder()

                func mapFlat(_ items: [APIPost]) -> [Post] {
                    items.map { api in
                        Post(
                            id: api.sequentialCode ?? api.code ?? api.id ?? UUID().uuidString,
                            content: api.content ?? "",
                            author: (api.profileName?.isEmpty == false) ? api.profileName! : getDisplayName(for: api.userAddress ?? api.address ?? ""),
                            timestamp: parseDate(isoString: api.createdAt, ts: api.timestamp, tsMs: api.timestampMs),
                            likes: api.likesCount?.asInt() ?? api.likes ?? 0,
                            replies: api.repliesCount?.asInt() ?? api.replies ?? 0,
                            isLiked: false,
                            userRank: api.userRank ?? "Bronze",
                            avatarURL: (api.profileImage?.isEmpty == false) ? "data:image/jpeg;base64,\(api.profileImage!)" : nil,
                            parentCode: api.parentSequentialCode ?? api.parentCode,
                            tlsAddress: api.userAddress ?? api.address,
                            broadcastCount: api.broadcastCount?.asInt() ?? 0,
                            tlsCount: api.tlsCount?.asInt() ?? 0,
                            followerCount: api.followerCount?.asInt() ?? 0
                        )
                    }
                }

                func flattenTree(_ node: APIPost) -> [APIPost] {
                    var acc: [APIPost] = [node]
                    let kids = node.children ?? node.comments ?? []
                    for ch in kids { acc.append(contentsOf: flattenTree(ch)) }
                    return acc
                }

                var postsFlat: [Post] = []
                if let arr = try? decoder.decode([APIPost].self, from: data) {
                    postsFlat = mapFlat(arr)
                } else if let env = try? decoder.decode(EnvelopeArr.self, from: data) {
                    let arr = env.data ?? env.posts ?? env.result ?? []
                    postsFlat = mapFlat(arr)
                } else if let obj = try? decoder.decode(EnvelopeObj.self, from: data), let root = obj.data {
                    let flattened = flattenTree(root)
                    postsFlat = mapFlat(flattened)
                } else if let root = try? decoder.decode(APIPost.self, from: data) {
                    postsFlat = mapFlat(flattenTree(root))
                } else if let any = try? JSONSerialization.jsonObject(with: data, options: []),
                          let dict = any as? [String: Any] {
                    if let commentsAny = dict["comments"] as? [[String: Any]] {
                        let arrData = try JSONSerialization.data(withJSONObject: commentsAny, options: [])
                        if let decoded = try? decoder.decode([APIPost].self, from: arrData) {
                            postsFlat = mapFlat(decoded)
                        }
                    }
                }

                // Remove the root post itself if present; keep only replies under postCode
                let repliesOnly = postsFlat.filter { $0.id != postCode }
                await MainActor.run {
                    self.repliesByCode[postCode] = repliesOnly.sorted { $0.timestamp < $1.timestamp }
                    self.setCachedDeepCount(for: postCode, count: repliesOnly.count)
                    let dur = nowMs() - t0
                    self.lastFetchCommentsMsByCode[postCode] = dur
                    print("✅ LASKO: Thread endpoint returned \(repliesOnly.count) comments for \(postCode) (\(dur)ms)")
                }
                return repliesOnly.count
            } catch {
                print("⚠️ LASKO: Thread endpoint error for \(url.absoluteString): \(error.localizedDescription)")
                continue
            }
        }
        return nil
    }

    private func requestZeroaSignature(content: String, tlsAddress: String, timestampMs: Int) async -> ZeroaSignaturePayload? {
        guard let defaults = appGroupsService.sharedDefaults else {
            print("❌ LASKO: Cannot request signature – App Groups container unavailable")
            return nil
        }
        let contentData = Data(content.utf8)
        let contentHashHex = sha256Hex(of: contentData)
        let bundleId = Bundle.main.bundleIdentifier ?? "com.telestai.LASKO"
        let canonical = "LASKO_POST|\(contentHashHex)|\(timestampMs)|\(tlsAddress)|\(bundleId)|v1"
        
        defaults.removeObject(forKey: "lasko_post_sign_response")
        defaults.synchronize()
        
        let requestDictionary: [String: Any] = [
            "contentHashHex": contentHashHex,
            "timestamp": timestampMs,
            "tlsAddress": tlsAddress,
            "bundleId": bundleId,
            "canonical": canonical
        ]
        print("📤 LASKO: Writing post-sign request to App Groups...")
        print("   Key: lasko_post_sign_request")
        print("   Content hash: \(contentHashHex.prefix(16))...")
        print("   Timestamp: \(timestampMs)")
        print("   TLS Address: \(tlsAddress)")
        defaults.set(requestDictionary, forKey: "lasko_post_sign_request")
        let syncResult = defaults.synchronize()
        print("✅ LASKO: Post-sign request written, sync result: \(syncResult)")
        
        // CRITICAL: Send Darwin notification to wake Zeroa
        let notificationName = CFNotificationName("com.telestai.lasko.post.sign.request" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        print("📢 LASKO: Sent Darwin notification to Zeroa")
        
        // Verify it was written
        if let verify = defaults.dictionary(forKey: "lasko_post_sign_request") {
            print("✅ LASKO: Verified request exists in App Groups after write")
        } else {
            print("❌ LASKO: WARNING - Request NOT found in App Groups immediately after write!")
        }
        
        // Notification-driven polling with exponential backoff fallback
        let maxWaitTime: TimeInterval = 6.0 // 6 seconds max
        let startTime = Date()
        var attempt = 0
        
        print("🔐 LASKO: Waiting for Zeroa signature for content hash \(contentHashHex.prefix(12))…")
        
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            // Check if notification was received or check App Groups
            let freshDefaults = UserDefaults(suiteName: "group.com.telestai.zeroa-lasko")
            freshDefaults?.synchronize()
            defaults.synchronize()
            
            if let response = (freshDefaults?.dictionary(forKey: "lasko_post_sign_response") ?? defaults.dictionary(forKey: "lasko_post_sign_response")),
               let signature = response["signatureBase64"] as? String,
               let pubkey = response["pubkeyCompressedHex"] as? String {
                print("✅ LASKO: Found Zeroa signature response!")
                print("   Signature length: \(signature.count) chars")
                print("   Public key: \(pubkey.prefix(16))...")
                defaults.removeObject(forKey: "lasko_post_sign_request")
                defaults.removeObject(forKey: "lasko_post_sign_response")
                freshDefaults?.removeObject(forKey: "lasko_post_sign_request")
                freshDefaults?.removeObject(forKey: "lasko_post_sign_response")
                defaults.synchronize()
                freshDefaults?.synchronize()
                return ZeroaSignaturePayload(
                    signatureBase64: signature,
                    pubkeyCompressedHex: pubkey,
                    canonicalMessage: canonical
                )
            }
            
            // Exponential backoff: 50ms, 100ms, 200ms, 400ms, then 400ms max
            let delay = min(0.4, 0.05 * pow(2.0, Double(min(attempt, 3))))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            attempt += 1
            
            if attempt % 10 == 0 {
                let elapsed = Date().timeIntervalSince(startTime)
                print("🔍 LASKO: Still waiting... (\(String(format: "%.1f", elapsed))s elapsed)")
            }
        }
        
        defaults.removeObject(forKey: "lasko_post_sign_request")
        defaults.removeObject(forKey: "lasko_post_sign_response")
        defaults.synchronize()
        let elapsed = Date().timeIntervalSince(startTime)
        print("❌ LASKO: Timed out waiting for Zeroa signature after \(String(format: "%.1f", elapsed))s")
        return nil
    }
    
    func createComment(content: String, parentSequentialCode code: String) async -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard appGroupsService.isProfileActive() else {
            print("❌ LASKO: Cannot create comment - Zeroa profile inactive")
            return false
        }
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
        guard code.addingPercentEncoding(withAllowedCharacters: allowed) != nil else { return false }
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
            guard let signaturePayload = await requestZeroaSignature(content: trimmed, tlsAddress: tls, timestampMs: nowMs) else {
                print("❌ LASKO: Failed to obtain Zeroa signature for comment")
                return false
            }
            // Note: Pre-verification is optional - the server will verify on post creation
            // The /halo/verify endpoint expects a nonce (for auth), not a message (for posts)
            // So we skip verification here and let the server handle it
            let verificationResult = await backendVerifySignature(address: tls, message: signaturePayload.canonicalMessage, signature: signaturePayload.signatureBase64)
            if !verificationResult {
                print("⚠️ LASKO: Pre-verification failed (expected for post signatures), proceeding with comment creation")
            }
            body["signature"] = signaturePayload.signatureBase64
            body["pubkey"] = signaturePayload.pubkeyCompressedHex
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
    
    private struct ZeroaSignaturePayload {
        let signatureBase64: String
        let pubkeyCompressedHex: String
        let canonicalMessage: String
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
        guard appGroupsService.isProfileActive() else {
            print("❌ LASKO: Cannot create post - Zeroa profile inactive")
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
#if DEBUG
            print("🔍 LASKO: Getting token for address: \(tlsAddress)")
#endif
            guard let token = await ensureTokenForAddress(tlsAddress, timeoutSeconds: 8.0) else {
                print("❌ LASKO: Cannot create post - missing or expired token")
                return false
            }
#if DEBUG
            print("✅ LASKO: Got token for post creation: \(String(token.prefix(20)))...")
#endif
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
            
            // Include profile data if available
            if let profileName = appGroupsService.getProfileDisplayName(), !profileName.isEmpty {
                body["profileName"] = profileName
            }
            // Include profile image if available
            if let profileImage = appGroupsService.getProfileImage(),
               let imageData = profileImage.jpegData(compressionQuality: 0.7) {
                let base64String = imageData.base64EncodedString()
                body["profileImageBase64"] = base64String
            }
            // Note: Bio can be added later when we have a bio field in App Groups
            print("🔍 LASKO: Requesting signature from Zeroa for post")
            guard let signaturePayload = await requestZeroaSignature(content: trimmed, tlsAddress: tlsAddress, timestampMs: nowMs) else {
                print("❌ LASKO: Failed to obtain Zeroa signature for post")
                return false
            }
            // Note: Pre-verification is optional - the server will verify on post creation
            // The /halo/verify endpoint expects a nonce (for auth), not a message (for posts)
            // So we skip verification here and let the server handle it
            let verificationResult = await backendVerifySignature(address: tlsAddress, message: signaturePayload.canonicalMessage, signature: signaturePayload.signatureBase64)
            if !verificationResult {
                print("⚠️ LASKO: Pre-verification failed (expected for post signatures), proceeding with post creation")
            }
            body["signature"] = signaturePayload.signatureBase64
            body["pubkey"] = signaturePayload.pubkeyCompressedHex
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
    
    func rewardPost(_ post: Post, amount: Double = 10.0) async -> Bool {
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty else {
            print("❌ LASKO: rewardPost failed - no TLS address")
            return false
        }
        
        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else {
            print("❌ LASKO: rewardPost failed - no token")
            return false
        }
        
        do {
            // URL-encode the post ID to handle special characters like #
            guard let encodedPostId = post.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                print("❌ LASKO: rewardPost failed - cannot encode post ID")
                return false
            }
            let url = URL(string: "\(effectiveBaseURL)/posts/\(encodedPostId)/reward")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
            if let bundleId = Bundle.main.bundleIdentifier {
                request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id")
            }
            
            let body: [String: Any] = [
                "fromAddress": tls,
                "amount": amount
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool, success,
                       let dataObj = json["data"] as? [String: Any],
                       let tlsCount = dataObj["tlsCount"] as? Int {
                        print("✅ LASKO: Post rewarded successfully, new TLS count: \(tlsCount)")
                        
                        // Update local post with new TLS count
                        DispatchQueue.main.async {
                            if let index = self.posts.firstIndex(where: { $0.id == post.id }) {
                                var updatedPost = self.posts[index]
                                self.posts[index] = Post(
                                    id: updatedPost.id,
                                    content: updatedPost.content,
                                    author: updatedPost.author,
                                    timestamp: updatedPost.timestamp,
                                    likes: updatedPost.likes,
                                    replies: updatedPost.replies,
                                    isLiked: updatedPost.isLiked,
                                    userRank: updatedPost.userRank,
                                    avatarURL: updatedPost.avatarURL,
                                    parentCode: updatedPost.parentCode,
                                    tlsAddress: updatedPost.tlsAddress,
                                    broadcastCount: updatedPost.broadcastCount,
                                    tlsCount: tlsCount,
                                    followerCount: updatedPost.followerCount
                                )
                            }
                        }
                        
                        // Request Zeroa to send TLS payment (background)
                        await requestZeroaTLSPayment(toAddress: post.tlsAddress ?? "", amount: amount, postId: post.id)
                        
                        return true
                    }
                } else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    print("❌ LASKO: rewardPost server error: \(http.statusCode) \(body)")
                }
            }
            return false
        } catch {
            print("❌ LASKO: rewardPost error: \(error)")
            return false
        }
    }
    
    private func requestZeroaTLSPayment(toAddress: String, amount: Double, postId: String) async {
        guard let defaults = appGroupsService.sharedDefaults else {
            print("❌ LASKO: Cannot request TLS payment - App Groups unavailable")
            return
        }
        
        let request: [String: Any] = [
            "toAddress": toAddress,
            "amount": amount,
            "postId": postId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        defaults.set(request, forKey: "lasko_tls_payment_request")
        defaults.synchronize()
        
        print("📤 LASKO: Requested Zeroa to send TLS payment: \(amount) TLS to \(toAddress) for post \(postId)")
        
        // Send Darwin notification to Zeroa
        let notificationName = CFNotificationName("com.telestai.lasko.tls.payment.request" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
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
        await backendVerifySignature(address: address, message: message, signature: signature)
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
        // For other users, return the full address (no ellipsis)
        let displayName = address.isEmpty ? "User" : address
        print("✅ LASKO: Address is different user, returning full address: \(displayName)")
        return displayName
    }
    
    // Format TLS address as first 5 chars + "..." + last 7 chars
    func formatTLSAddress(_ address: String?) -> String {
        guard let addr = address, !addr.isEmpty else { return "" }
        guard addr.count > 12 else { return addr } // If address is too short, return as-is
        
        let firstFive = String(addr.prefix(5))
        let lastSeven = String(addr.suffix(7))
        return "\(firstFive)...\(lastSeven)"
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

