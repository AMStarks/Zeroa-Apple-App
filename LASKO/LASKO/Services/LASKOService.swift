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
    /// Set when silent Darwin post-sign times out; UI should offer an explicit "Open Zeroa" action (never auto-switch).
    @Published var needsOpenZeroaToSign = false
    @Published var isReviewingContent = false
    @Published var isConnectedToTelestai = false
    @Published var isAuthenticatedWithZeroa = false
    @Published private(set) var isAuthPolling = false
    @Published var currentTLSAddress: String?
    /// Addresses the current user follows (for green avatar rings + Follow UX).
    @Published var followedAddresses: Set<String> = []
    @Published var repliesByCode: [String: [Post]] = [:]
    @Published var username: String = "User" {
        didSet {
            guard !isApplyingIdentity else { return }
            print("🔍 LASKO: Username changed to: \(username)")
            persistUsernameForCurrentTLS()
            Task { await publishProfileToHalo() }
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
    private var inFlightCommentFetches: Set<String> = []
    /// When "Require Zeroa Each Launch" is on, block App Groups session restore until manual login.
    private var sessionRestoreBlocked = false
    /// Suppresses username persistence while swapping wallets.
    private var isApplyingIdentity = false

    // MARK: - Per-user post action state (persisted per TLS address)
    @Published private(set) var userActionStateVersion = 0
    private var likedPostIds = Set<String>()
    private var announcedPostIds = Set<String>()
    private var commentedPostIds = Set<String>()
    private var userActionsTLSAddress: String?
    /// Prevents stale feed refreshes from re-marking a post announced after the user un-announced it.
    private var suppressedAnnounceSyncIds = Set<String>()

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
    private let legacyUsernameKey = "lasko_username"
    /// TLS address → Zeroa display name (from feed/API).
    private var profileNameByAddress: [String: String] = [:]
    private var isVerifyingAuthResponse = false
    private var processedAuthSessionTokens = Set<String>()

    private func usernameKey(for tlsAddress: String) -> String {
        "lasko_username_\(tlsAddress)"
    }

    private func persistUsernameForCurrentTLS() {
        guard let tlsAddress = currentTLSAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tlsAddress.isEmpty else {
            print("⚠️ LASKO: Skipping username persistence; no active TLS address")
            return
        }
        guard !isGeneratedAddressUsername(username, tls: tlsAddress) else {
            print("⚠️ LASKO: Not persisting placeholder username \(username)")
            return
        }
        UserDefaults.standard.set(username, forKey: usernameKey(for: tlsAddress))
        UserDefaults.standard.removeObject(forKey: legacyUsernameKey)
        appGroupsService.sharedDefaults?.set(username, forKey: "profile_display_name_\(tlsAddress)")
        appGroupsService.sharedDefaults?.synchronize()
        print("🔍 LASKO: Username saved for TLS \(tlsAddress)")
    }

    private func loadUsername(for tlsAddress: String) -> String? {
        let scopedKey = usernameKey(for: tlsAddress)
        if let scoped = UserDefaults.standard.string(forKey: scopedKey), !scoped.isEmpty {
            return scoped
        }
        return nil
    }
    
    init() {
        isApplyingIdentity = true
        username = "User"
        isApplyingIdentity = false
        UserDefaults.standard.removeObject(forKey: legacyUsernameKey)
        appGroupsService.clearLegacyGlobalProfileKeys()
        print("🔍 LASKO: LASKOService initialized")
    }

    func resetIdentitySession(reason: String) {
        print("🔄 LASKO: Resetting identity session — \(reason)")
        isApplyingIdentity = true
        isAuthenticatedWithZeroa = false
        currentTLSAddress = nil
        followedAddresses = []
        username = "User"
        posts = []
        profileNameByAddress.removeAll()
        processedAuthSessionTokens.removeAll()
        isVerifyingAuthResponse = false
        stopAuthPollingWindow()
        isApplyingIdentity = false
        UserDefaults.standard.removeObject(forKey: legacyUsernameKey)
    }

    private func isGeneratedAddressUsername(_ name: String, tls: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "User" || trimmed == "PAAI User" { return true }
        let prefix = String(tls.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6))
        return trimmed.caseInsensitiveCompare("User\(prefix)") == .orderedSame
    }

    private func applyIdentity(tls: String) {
        appGroupsService.migrateLegacyGlobalsIfNeeded(tlsAddress: tls)
        isApplyingIdentity = true
        isAuthenticatedWithZeroa = true
        currentTLSAddress = tls
        if let syncedName = appGroupsService.getProfileDisplayName(for: tls),
           !syncedName.isEmpty,
           !isGeneratedAddressUsername(syncedName, tls: tls) {
            username = syncedName
            print("🔍 LASKO: Synced username from App Groups for TLS \(tls): \(syncedName)")
        } else if let scopedUsername = loadUsername(for: tls),
                  !scopedUsername.isEmpty,
                  !isGeneratedAddressUsername(scopedUsername, tls: tls) {
            username = scopedUsername
            print("🔍 LASKO: Loaded TLS-scoped username: \(scopedUsername)")
        } else {
            username = generateAddressBasedUsername()
            print("🔍 LASKO: Using local placeholder username: \(username)")
        }
        isApplyingIdentity = false
        if !isGeneratedAddressUsername(username, tls: tls) {
            persistUsernameForCurrentTLS()
            Task { await publishProfileToHalo() }
        }
        loadUserActionSets(for: tls)
    }

    func syncIdentityWithAppGroups() {
        appGroupsService.sharedDefaults?.synchronize()
        appGroupsService.clearLegacyGlobalProfileKeys()
        let sharedTLS = appGroupsService.getTLSAddress()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appGroupsService.isProfileActive() || sharedTLS == nil || sharedTLS?.isEmpty == true {
            if isAuthenticatedWithZeroa {
                resetIdentitySession(reason: "Zeroa profile inactive or TLS cleared")
            }
            return
        }
        guard let tls = sharedTLS else { return }
        if isAuthenticatedWithZeroa, currentTLSAddress == tls {
            return
        }
        if isAuthenticatedWithZeroa, currentTLSAddress != tls {
            resetIdentitySession(reason: "App Groups TLS changed to \(tls)")
        }
        _ = restoreZeroaSessionFromAppGroups()
    }

    private func publishProfileToHalo() async {
        guard let tls = currentTLSAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !tls.isEmpty else { return }
        guard let token = readHaloToken(), tokenIsFresh(token) else { return }
        let name = appGroupsService.getProfileDisplayName(for: tls) ?? username
        guard !name.isEmpty, !isGeneratedAddressUsername(name, tls: tls) else { return }
        guard let url = URL(string: "\(effectiveBaseURL)/halo/profile") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["profileName": name]
        if let image = appGroupsService.getProfileImage(for: tls),
           let data = image.jpegData(compressionQuality: 0.7) {
            body["profileImageBase64"] = data.base64EncodedString()
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                print("🔍 LASKO: Halo profile upsert status \(http.statusCode) for \(tls)")
            }
        } catch {
            print("⚠️ LASKO: Halo profile upsert failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Zeroa Integration

    func prepareSessionForLaunch() {
        if LASKOSecurityPreferences.requireZeroaEachLaunch {
            sessionRestoreBlocked = true
            resetIdentitySession(reason: "Require Zeroa each launch")
            print("🔒 LASKO: Require Zeroa each launch — manual login required this session")
        }
    }

    func enforceRequireZeroaEachLaunch() {
        sessionRestoreBlocked = true
        resetIdentitySession(reason: "Zeroa login required")
        print("🔒 LASKO: Zeroa login required — session cleared for this launch")
    }

    /// Reuse an existing Zeroa session from App Groups when Halo JWT + TLS address are already present.
    @discardableResult
    func restoreZeroaSessionFromAppGroups() -> Bool {
        if sessionRestoreBlocked {
            print("🔒 LASKO: Session restore blocked — require Zeroa each launch enabled")
            return false
        }
        guard appGroupsService.isProfileActive() else {
            print("🔍 LASKO: Cannot restore session — Zeroa profile inactive")
            return false
        }
        guard let tls = appGroupsService.getTLSAddress()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tls.isEmpty else {
            return false
        }
        if isAuthenticatedWithZeroa, currentTLSAddress == tls { return true }
        if isAuthenticatedWithZeroa, currentTLSAddress != tls {
            resetIdentitySession(reason: "restore saw different TLS \(tls)")
        }
        guard let token = readHaloToken(), tokenIsFresh(token) else {
            return false
        }
        if let sub = jwtSubject(token), sub != tls {
            print("⚠️ LASKO: Halo token subject (\(sub)) != TLS address (\(tls)); not restoring")
            return false
        }
        applyIdentity(tls: tls)
        stopAuthPollingWindow()
        print("✅ LASKO: Restored Zeroa session from App Groups for \(tls)")
        return true
    }

    // MARK: - User action persistence (like / announce / comment highlights)

    private func userActionsStorageKey(_ suffix: String, tls: String) -> String {
        "lasko_user_\(suffix)_\(tls)"
    }

    func loadUserActionSets(for tlsAddress: String?) {
        guard let tls = tlsAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !tls.isEmpty else {
            likedPostIds = []
            announcedPostIds = []
            commentedPostIds = []
            userActionsTLSAddress = nil
            return
        }
        if userActionsTLSAddress == tls { return }
        userActionsTLSAddress = tls
        likedPostIds = Set(UserDefaults.standard.stringArray(forKey: userActionsStorageKey("liked", tls: tls)) ?? [])
        announcedPostIds = Set(UserDefaults.standard.stringArray(forKey: userActionsStorageKey("announced", tls: tls)) ?? [])
        commentedPostIds = Set(UserDefaults.standard.stringArray(forKey: userActionsStorageKey("commented", tls: tls)) ?? [])
        userActionStateVersion += 1
        print("✅ LASKO: Loaded user actions for \(tls): liked=\(likedPostIds.count) announced=\(announcedPostIds.count) commented=\(commentedPostIds.count)")
    }

    /// Guarantee the action sets are loaded for the active TLS before we mutate them.
    /// Without this, a tap that happens before session restore runs would mutate the
    /// in-memory sets but silently fail to persist (userActionsTLSAddress == nil).
    private func ensureUserActionSetsLoaded() {
        guard userActionsTLSAddress == nil else { return }
        let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let tls, !tls.isEmpty {
            loadUserActionSets(for: tls)
        }
    }

    private func persistUserActionSets() {
        guard let tls = (userActionsTLSAddress ?? currentTLSAddress ?? appGroupsService.getTLSAddress())?
            .trimmingCharacters(in: .whitespacesAndNewlines), !tls.isEmpty else {
            print("⚠️ LASKO: Skipping user-action persistence; no active TLS address")
            return
        }
        if userActionsTLSAddress == nil { userActionsTLSAddress = tls }
        UserDefaults.standard.set(Array(likedPostIds), forKey: userActionsStorageKey("liked", tls: tls))
        UserDefaults.standard.set(Array(announcedPostIds), forKey: userActionsStorageKey("announced", tls: tls))
        UserDefaults.standard.set(Array(commentedPostIds), forKey: userActionsStorageKey("commented", tls: tls))
    }

    private func bumpUserActionState() {
        persistUserActionSets()
        userActionStateVersion += 1
    }

    func hasUserLikedPost(_ postId: String) -> Bool { likedPostIds.contains(postId) }
    func hasUserAnnouncedPost(_ postId: String) -> Bool { announcedPostIds.contains(postId) }
    func hasUserCommentedOnPost(_ postId: String) -> Bool { commentedPostIds.contains(postId) }

    func markUserLikedPost(_ postId: String) {
        ensureUserActionSetsLoaded()
        guard likedPostIds.insert(postId).inserted else { return }
        bumpUserActionState()
        print("✅ LASKO: Marked liked \(postId)")
    }

    func unmarkUserLikedPost(_ postId: String) {
        ensureUserActionSetsLoaded()
        guard likedPostIds.remove(postId) != nil else { return }
        bumpUserActionState()
        print("✅ LASKO: Unmarked liked \(postId)")
    }

    func markUserAnnouncedPost(_ postId: String) {
        ensureUserActionSetsLoaded()
        suppressedAnnounceSyncIds.remove(postId)
        guard announcedPostIds.insert(postId).inserted else { return }
        bumpUserActionState()
        print("✅ LASKO: Marked announced \(postId)")
    }

    func unmarkUserAnnouncedPost(_ postId: String) {
        ensureUserActionSetsLoaded()
        suppressedAnnounceSyncIds.insert(postId)
        guard announcedPostIds.remove(postId) != nil else { return }
        bumpUserActionState()
        print("✅ LASKO: Unmarked announced \(postId)")
    }

    func markUserCommentedOnPost(_ postId: String) {
        ensureUserActionSetsLoaded()
        guard commentedPostIds.insert(postId).inserted else { return }
        bumpUserActionState()
        print("✅ LASKO: Marked commented \(postId)")
    }

    private func syncUserActionsFromFeed(_ posts: [Post]) {
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress())?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tls.isEmpty else { return }
        loadUserActionSets(for: tls)
        let announcedInFeed = Set(
            posts.filter { $0.isAnnounceRepost && $0.announcedBy == tls }.map { $0.id }
        )
        var changed = false

        for id in announcedInFeed {
            if suppressedAnnounceSyncIds.contains(id) { continue }
            if announcedPostIds.insert(id).inserted { changed = true }
        }

        for id in suppressedAnnounceSyncIds where !announcedInFeed.contains(id) {
            suppressedAnnounceSyncIds.remove(id)
        }

        if changed {
            persistUserActionSets()
            userActionStateVersion += 1
        }
    }

    /// When an announce repost is in the feed, hide the duplicate chronological copy of the same post.
    /// Show BOTH the original post and any announce reposts of it (e.g. "<user> announced").
    /// We only drop exact duplicate feed rows (same feedKey), which the backend already prevents,
    /// so this is just a defensive guard. The original chronological post is intentionally kept.
    private static func dedupeAnnounceShadowPosts(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        return posts.filter { seen.insert($0.feedKey).inserted }
    }

    private func removeAnnounceRepostsFromFeed(postId: String, announcedBy: String) {
        posts.removeAll { $0.id == postId && $0.isAnnounceRepost && $0.announcedBy == announcedBy }
    }
    
    func checkZeroaAuthentication() {
        print("🔍 LASKO: Checking Zeroa authentication...")
        
        let sharedTLS = appGroupsService.getTLSAddress()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAuthenticatedWithZeroa {
            if let sharedTLS, !sharedTLS.isEmpty, sharedTLS != currentTLSAddress {
                resetIdentitySession(reason: "auth check saw TLS change to \(sharedTLS)")
            } else if AppGroupsService.shared.getLASKOAuthResponse() == nil {
                print("✅ LASKO: Already authenticated; skipping further checks")
                return
            }
        }
        if isVerifyingAuthResponse {
            print("🔍 LASKO: Auth response verification already in progress")
            return
        }
        
        // Process completed auth response if available (do not require request to persist)
        if let resp = AppGroupsService.shared.getLASKOAuthResponse() {
            guard !isVerifyingAuthResponse else {
                print("🔍 LASKO: Auth response verification already in progress")
                return
            }
            guard !processedAuthSessionTokens.contains(resp.sessionToken) else {
                print("🔍 LASKO: Auth response session already processed")
                return
            }
            isVerifyingAuthResponse = true
            processedAuthSessionTokens.insert(resp.sessionToken)
            let canonicalMessage = resp.canonicalMessage ?? "LASKO_AUTH:\(resp.tlsAddress):\(resp.sessionToken)"
            let signatureForVerification = resp.signatureBase64 ?? resp.signature
            Task { @MainActor in
                let ok = await self.verifyMessage(
                    message: canonicalMessage,
                    signature: signatureForVerification,
                    address: resp.tlsAddress,
                    pubkeyCompressedHex: resp.pubkeyCompressedHex
                )
                self.isVerifyingAuthResponse = false
                if ok {
                    if self.currentTLSAddress != resp.tlsAddress {
                        self.resetIdentitySession(reason: "handshake for \(resp.tlsAddress)")
                    }
                    self.applyIdentity(tls: resp.tlsAddress)

                    // Clear consumed response; request may already be cleared by Zeroa
                    AppGroupsService.shared.clearAuthResponse()
                    self.stopAuthPollingWindow()
                    print("✅ LASKO: Signature verified; identity established for \(resp.tlsAddress)")
                } else {
                    self.isAuthenticatedWithZeroa = false
                    self.currentTLSAddress = nil
                    AppGroupsService.shared.clearAuthResponse()
                    self.errorMessage = "Could not verify Zeroa signature. Update the Halo app or try again."
                    self.stopAuthPollingWindow()
                    print("❌ LASKO: Signature verification failed for TLS \(resp.tlsAddress)")
                }
            }
            return
        }
        
        // If no response yet, remain unauthenticated until request is approved in Zeroa
        print("❌ LASKO: No completed Zeroa response yet")
        // Do not explicitly set to false here to avoid flicker after success
    }
    
    func requestZeroaAuthentication() {
        if restoreZeroaSessionFromAppGroups() {
            print("✅ LASKO: Skipping auth handshake — session restored from App Groups")
            return
        }
        // Headless identity flow: create a fresh nonce request for Zeroa to sign
        print("🔍 LASKO: Creating headless auth request (nonce) for Zeroa…")
        processedAuthSessionTokens.removeAll()
        isVerifyingAuthResponse = false
        AppGroupsService.shared.clearAuthResponse()
        let req = LASKOAuthRequest(
            appName: "LASKO",
            appId: Bundle.main.bundleIdentifier ?? "com.zeroa.lasko",
            permissions: ["post", "read"],
            callbackURL: "lasko://auth/callback",
            username: nil,
            nonce: nil
        )
        AppGroupsService.shared.storeLASKOAuthRequest(req)
        notifyZeroaAuthRequestReady()
        openZeroaForAuthRequest()
        // Start a 60s polling window for the auth response
        startAuthPollingWindow()
    }

    private func notifyZeroaAuthRequestReady() {
        let notificationName = CFNotificationName("com.telestai.lasko.auth.request" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        print("📢 LASKO: Sent Darwin notification to Zeroa (auth request ready)")
    }

    private func openZeroaForAuthRequest() {
        guard let url = URL(string: "zeroa://auth/request") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                print("⚠️ LASKO: Could not open Zeroa via URL scheme")
            }
        }
    }

    /// User-initiated only — opens Zeroa so the user can approve a fresh 1-hour posting key.
    func openZeroaToFinishSigning() {
        needsOpenZeroaToSign = false
        guard let url = URL(string: "zeroa://posting-key/reissue") else { return }
        print("🔗 LASKO: User opened Zeroa via zeroa://posting-key/reissue")
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                print("⚠️ LASKO: Could not open Zeroa for posting-key reissue")
            }
        }
    }

    /// Prefer the hourly delegated posting key. If missing/expired, ask the user to reissue in Zeroa.
    private func obtainPostSignature(content: String, tlsAddress: String, timestampMs: Int) async -> ZeroaSignaturePayload? {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.zeroa.lasko"
        if let local = PostingKeySigner.signPost(
            content: content,
            tlsAddress: tlsAddress,
            timestampMs: timestampMs,
            bundleId: bundleId,
            defaults: appGroupsService.sharedDefaults
        ) {
            print("✅ LASKO: Signed post locally with hourly posting key")
            await MainActor.run { self.needsOpenZeroaToSign = false }
            return ZeroaSignaturePayload(
                signatureBase64: local.signatureBase64,
                pubkeyCompressedHex: local.pubkeyCompressedHex,
                canonicalMessage: local.canonicalMessage
            )
        }

        print("⚠️ LASKO: No valid posting key — prompting Zeroa reissue")
        await MainActor.run {
            self.needsOpenZeroaToSign = true
            self.errorMessage = "Your posting signature expired. Tap Open Zeroa to reissue for another hour."
        }
        return nil
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
    private var isObservingSubscriptionPayment = false
    private var subscriptionPaymentContinuation: CheckedContinuation<Bool, Never>?
    private var subscriptionPaymentResolved = false
    
    private func startAuthPollingWindow() {
        stopAuthPollingWindow()
        isAuthPolling = true
        authPollDeadline = Date().addingTimeInterval(90)
        
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
        
        // Slow backup poll: Darwin notification + immediate checks handle the common path.
        authPollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.checkForAuthResponse()
                if let deadline = self.authPollDeadline, Date() >= deadline {
                    if self.isVerifyingAuthResponse {
                        self.authPollDeadline = Date().addingTimeInterval(15)
                        print("⏳ LASKO: Auth response received; waiting for signature verification to finish")
                        return
                    }
                    self.stopAuthPollingWindow()
                    // Timeout: clear request and inform UI
                    AppGroupsService.shared.clearAuthRequest()
                    self.isAuthenticatedWithZeroa = false
                    self.errorMessage = "Login timed out. Open Zeroa (leave it in the foreground), then try again."
                    if let url = URL(string: "zeroa://auth/request") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                    print("⏱️ LASKO: Auth polling timed out after 90s")
                }
            }
        }
        print("⏱️ LASKO: Started 60s auth polling window (Darwin + 2.5s backup poll)")
        // One immediate read in case the response was written before the observer was registered.
        Task { @MainActor in
            self.checkForAuthResponse()
        }
    }
    
    @objc private func handleAuthResponseNotification() {
        print("📢 LASKO: Processing auth response notification")
        Task { @MainActor in
            // App Group `synchronize()` can lag the Darwin post; retry a few times quickly.
            let delaysNs: [UInt64] = [0, 50_000_000, 120_000_000, 250_000_000]
            for d in delaysNs {
                if d > 0 { try? await Task.sleep(nanoseconds: d) }
                self.checkForAuthResponse()
                if self.isAuthenticatedWithZeroa { break }
            }
        }
    }
    
    @objc private func handleSubscriptionPaymentResponseNotification() {
        print("📢 LASKO: Processing subscription payment response notification")
        // Check when notification arrives (with small delay to allow App Groups sync)
        Task { @MainActor in
            guard !self.subscriptionPaymentResolved else {
                print("⚠️ LASKO: Subscription payment already resolved, ignoring notification")
                return
            }
            
            // Small delay to allow App Groups to sync
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Check again if already resolved (race condition protection)
            guard !self.subscriptionPaymentResolved else {
                return
            }
            
            if let response = self.getSubscriptionPaymentResponse() {
                // Found response! Resume continuation if waiting
                if let continuation = self.subscriptionPaymentContinuation {
                    self.subscriptionPaymentResolved = true
                    self.stopSubscriptionPaymentObserver()
                    self.subscriptionPaymentContinuation = nil
                    
                    if response.success, let txid = response.txid, let tlsAddress = self.currentTLSAddress {
                        // Create subscription token
                        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                        let expiresAt = timestamp + Int64(SUBSCRIPTION_DURATION_DAYS * 24 * 60 * 60 * 1000)
                        
                        let token = SubscriptionToken(
                            txid: txid,
                            signature: response.signature,
                            userAddress: tlsAddress,
                            timestamp: timestamp,
                            expiresAt: expiresAt,
                            subscriptionAddress: SUBSCRIPTION_ADDRESS,
                            amount: SUBSCRIPTION_AMOUNT
                        )
                        
                        // Store token
                        self.saveSubscriptionToken(token)
                        print("✅ LASKO: Subscription token created and saved for \(tlsAddress)")
                        continuation.resume(returning: true)
                    } else {
                        print("❌ LASKO: Subscription payment failed: \(response.error ?? "unknown error")")
                        continuation.resume(returning: false)
                    }
                }
            } else {
                print("⚠️ LASKO: Notification received but response not found in App Groups yet - polling will continue")
            }
        }
    }
    
    private func stopSubscriptionPaymentObserver() {
        if isObservingSubscriptionPayment {
            let notificationName = "com.telestai.zeroa.subscription.payment.response" as CFString
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                CFNotificationName(notificationName),
                nil
            )
            isObservingSubscriptionPayment = false
        }
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("HandleSubscriptionPaymentResponse"), object: nil)
    }
    
    private func stopAuthPollingWindow() {
        isAuthPolling = false
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
    private func backendVerifySignature(address: String, message: String, signature: String, pubkeyCompressedHex: String? = nil) async -> Bool {
        // Try primary endpoint /auth/verify, allow alternate /halo/verify if first is missing
        let endpoints = ["auth/verify", "halo/verify"]
        for path in endpoints {
            guard let url = URL(string: "\(effectiveBaseURL)/\(path)") else { continue }
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let bundleId = Bundle.main.bundleIdentifier { req.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
                var body: [String: Any] = [
                    "address": address,
                    "message": message,
                    "signature": signature
                ]
                if let pubkeyCompressedHex, !pubkeyCompressedHex.isEmpty {
                    body["pubkey"] = pubkeyCompressedHex
                    body["signatureEncoding"] = "base64"
                }
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

    struct FeedAPIPost: Decodable {
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
        let broadcastCount: IntOrString?
        let tlsCount: IntOrString?
        let userRank: String?
        let profileName: String?
        let profileBio: String?
        let profileImage: String?
        let parentSequentialCode: String?
        let feedItemId: String?
        let announcedBy: String?
        let announcedByProfileName: String?
        let announcedAt: IntOrString?
    }

    private func mapFeedAPIPost(_ api: FeedAPIPost) -> Post {
        let parsedTimestamp = parseDate(isoString: api.createdAt, ts: api.timestamp, tsMs: api.timestampMs)
        let deep = api.deepRepliesCount?.asInt()
        let shallow = (api.repliesCount?.asInt()) ?? api.replies
        let repliesVal = (FeatureFlags.useDeepCountFromServer ? (deep ?? shallow) : shallow) ?? 0
        let userAddress = api.userAddress ?? api.address ?? api.author ?? ""
        let authorName = resolveAuthorDisplayName(
            profileName: api.profileName,
            userAddress: userAddress.isEmpty ? nil : userAddress
        )
        let isCurrentUser = !userAddress.isEmpty && userAddress == currentTLSAddress
        let avatarURL: String?
        if isCurrentUser, let appGroupsImage = appGroupsService.getProfileImage(for: currentTLSAddress),
           let imageData = appGroupsImage.jpegData(compressionQuality: 0.7) {
            avatarURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        } else if let profileImageBase64 = api.profileImage, !profileImageBase64.isEmpty {
            avatarURL = "data:image/jpeg;base64,\(profileImageBase64)"
        } else {
            avatarURL = nil
        }
        let parentRaw = api.parentSequentialCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentCode = (parentRaw?.isEmpty == false) ? parentRaw : nil
        let postId = api.sequentialCode ?? api.code ?? api.id ?? UUID().uuidString
        let announcedAt: Date? = {
            guard let raw = api.announcedAt?.asInt() else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(raw) / 1000.0)
        }()
        return Post(
            id: postId,
            content: api.content ?? "",
            author: authorName,
            timestamp: parsedTimestamp,
            likes: api.likesCount?.asInt() ?? api.likes ?? 0,
            replies: repliesVal,
            isLiked: false,
            userRank: api.userRank ?? "Bronze",
            avatarURL: avatarURL,
            parentCode: parentCode,
            tlsAddress: userAddress.isEmpty ? nil : userAddress,
            profileName: api.profileName,
            broadcastCount: api.broadcastCount?.asInt() ?? 0,
            tlsCount: api.tlsCount?.asInt() ?? 0,
            followerCount: 0,
            feedKey: api.feedItemId ?? postId,
            announcedBy: api.announcedBy,
            announcedByProfileName: api.announcedByProfileName,
            announcedAt: announcedAt
        )
    }

    /// Fetch a single user's profile feed: their own top-level posts plus posts they announced.
    /// The Halo indexer returns both when queried with `?userAddress=`.
    func fetchUserFeed(address: String) async -> [Post] {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addr.isEmpty else { return [] }
        let authAddr = currentTLSAddress ?? appGroupsService.getTLSAddress() ?? addr
        guard let token = await ensureTokenForAddress(authAddr, timeoutSeconds: 5.0) else {
            print("❌ LASKO: fetchUserFeed aborted - no Halo token for \(addr)")
            return []
        }
        guard let encoded = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(effectiveBaseURL)/posts?userAddress=\(encoded)&limit=100") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(currentTLSAddress ?? addr, forHTTPHeaderField: "X-TLS-Address")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let bundleId = Bundle.main.bundleIdentifier { request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("❌ LASKO: fetchUserFeed server error \(http.statusCode) for \(addr)")
                return []
            }
            struct Envelope: Decodable { let data: [FeedAPIPost]? }
            let decoder = JSONDecoder()
            var items: [FeedAPIPost] = []
            if let arr = try? decoder.decode([FeedAPIPost].self, from: data) {
                items = arr
            } else if let env = try? decoder.decode(Envelope.self, from: data), let arr = env.data {
                items = arr
            }
            // Keep top-level posts and announce reposts; drop ordinary replies.
            var mapped = items.map { mapFeedAPIPost($0) }.filter { Self.isMainFeedPost($0) }
            var seen = Set<String>()
            mapped = mapped.filter { seen.insert($0.feedKey).inserted }
            return mapped
        } catch {
            print("❌ LASKO: fetchUserFeed error for \(addr): \(error)")
            return []
        }
    }

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
        typealias APIPost = FeedAPIPost

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
            if let bodyStr = String(data: data, encoding: .utf8) {
                let previewLimit = 800
                let preview = String(bodyStr.prefix(previewLimit))
                let truncated = bodyStr.count > previewLimit
                print("🔍 LASKO: /posts response bytes=\(data.count) chars=\(bodyStr.count) preview=\(preview)\(truncated ? "…(truncated)" : "")")
            } else {
                print("🔍 LASKO: /posts response bytes=\(data.count) (non-utf8)")
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let body = String(data: data, encoding: .utf8) ?? ""
                let previewLimit = 800
                let preview = String(body.prefix(previewLimit))
                let truncated = body.count > previewLimit
                print("❌ LASKO: fetchPosts server error: \(http.statusCode) bodyPreview=\(preview)\(truncated ? "…(truncated)" : "")")
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
            var mapped: [Post] = items.map { mapFeedAPIPost($0) }

            mapped = mapped.filter { Self.isMainFeedPost($0) }

            // Override with cached deep counts if fresher
            for i in mapped.indices {
                if let cached = getCachedDeepCount(for: mapped[i].id), cached > mapped[i].replies {
                    mapped[i].replies = cached
                }
            }

            // Also fetch user's own posts to ensure previously created posts appear.
            // Halo serves this under /posts?userAddress=..., not /users/:address/posts.
            if let encodedTLS = tls.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let userURL = URL(string: "\(effectiveBaseURL)/posts?userAddress=\(encodedTLS)&limit=50") {
                var userReq = URLRequest(url: userURL)
                userReq.httpMethod = "GET"
                userReq.setValue("application/json", forHTTPHeaderField: "Accept")
                userReq.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
                userReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let bundleId = Bundle.main.bundleIdentifier { userReq.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
                if let (uData, uResp) = try? await URLSession.shared.data(for: userReq),
                   let http2 = uResp as? HTTPURLResponse, http2.statusCode < 400 {
                    if let arr = try? decoder.decode([APIPost].self, from: uData) {
                        let more = arr.map { mapFeedAPIPost($0) }
                            .filter { Self.isMainFeedPost($0) }
                        // Deduplicate by feedKey
                        let existingKeys = Set(mapped.map { $0.feedKey })
                        mapped.append(contentsOf: more.filter { !existingKeys.contains($0.feedKey) })
                    }
                }
            }

            // For now, use the replies count from the API response
            // The comment counts should be accurate from the server
            print("🔍 LASKO: Using reply counts from API response for \(mapped.count) posts")
            mapped = Self.dedupeAnnounceShadowPosts(mapped)
            syncUserActionsFromFeed(mapped)
            DispatchQueue.main.async {
                self.posts = mapped
                self.isLoading = false
            }
            lastFetchPostsMs = nowMs() - t0
            let libraryMonitorCount = mapped.filter { $0.tlsAddress == "Tf2N2xviA2b4eM8gabHxvKEGHiSpiKdbdY" }.count
            print("✅ LASKO: Loaded \(mapped.count) posts (\(lastFetchPostsMs)ms) cacheHits=\(cacheHits) cacheMisses=\(cacheMisses)")
            if libraryMonitorCount > 0 {
                print("📚 LIBRARY MONITOR: Found \(libraryMonitorCount) posts in mapped array")
            } else {
                print("⚠️ LIBRARY MONITOR: No Library Monitor posts found in mapped array!")
            }
            for (i, post) in mapped.enumerated() {
                let isLM = post.tlsAddress == "Tf2N2xviA2b4eM8gabHxvKEGHiSpiKdbdY"
                let prefix = isLM ? "📚 LM" : "🔍"
                print("\(prefix) LASKO: Post \(i): id=\(post.id), timestamp=\(post.timestamp), author=\(post.author), content=\(String(post.content.prefix(30)))")
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
        if inFlightCommentFetches.contains(code) {
            print("🔍 LASKO: fetchComments already in flight for \(code), skipping duplicate")
            return
        }
        inFlightCommentFetches.insert(code)
        defer { inFlightCommentFetches.remove(code) }
        
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
        let bundleId = Bundle.main.bundleIdentifier ?? "com.zeroa.lasko"
        let canonical = "LASKO_POST|\(contentHashHex)|\(timestampMs)|\(tlsAddress)|\(bundleId)|v1"
        let requestId = UUID().uuidString
        let createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let expiresAtMs = createdAtMs + 20_000
        
        await MainActor.run { self.needsOpenZeroaToSign = false }
        
        defaults.removeObject(forKey: "lasko_post_sign_response")
        defaults.synchronize()
        
        let requestDictionary: [String: Any] = [
            "requestId": requestId,
            "contentHashHex": contentHashHex,
            "timestamp": timestampMs,
            "createdAtMs": createdAtMs,
            "expiresAtMs": expiresAtMs,
            "tlsAddress": tlsAddress,
            "bundleId": bundleId,
            "canonical": canonical
        ]
        print("📤 LASKO: Writing post-sign request to App Groups...")
        print("   Key: lasko_post_sign_request")
        print("   Content hash: \(contentHashHex.prefix(16))...")
        print("   Timestamp: \(timestampMs)")
        print("   TLS Address: \(tlsAddress)")
        print("   Request ID: \(requestId.prefix(8))...")
        defaults.set(requestDictionary, forKey: "lasko_post_sign_request")
        let syncResult = defaults.synchronize()
        print("✅ LASKO: Post-sign request written, sync result: \(syncResult)")
        
        // Silent path only: Darwin wake. Do NOT auto-open Zeroa (see UX fallback on timeout).
        let notificationName = CFNotificationName("com.telestai.lasko.post.sign.request" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        print("📢 LASKO: Sent Darwin notification to Zeroa")
        
        if defaults.dictionary(forKey: "lasko_post_sign_request") != nil {
            print("✅ LASKO: Verified request exists in App Groups after write")
        } else {
            print("❌ LASKO: WARNING - Request NOT found in App Groups immediately after write!")
        }
        
        let responseNotificationName = "com.telestai.zeroa.post.sign.response" as CFString
        var isObserving = true
        
        let callback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (_, _, _, _, _) in
            print("📢 LASKO: Received Darwin notification for post-sign response")
            NotificationCenter.default.post(name: NSNotification.Name("HandlePostSignResponse"), object: nil)
        }
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            callback,
            responseNotificationName,
            nil,
            .deliverImmediately
        )
        
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HandlePostSignResponse"),
            object: nil,
            queue: .main
        ) { _ in }
        
        defer {
            NotificationCenter.default.removeObserver(observer)
            if isObserving {
                CFNotificationCenterRemoveObserver(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    nil,
                    CFNotificationName(responseNotificationName),
                    nil
                )
                isObserving = false
            }
        }
        
        // Fast silent window, then continue polling until overall timeout (request TTL is 20s).
        let fastPathSeconds: TimeInterval = 3.0
        let maxWaitTime: TimeInterval = 8.0
        let startTime = Date()
        var attempt = 0
        var offeredFallback = false
        
        print("🔐 LASKO: Waiting for Zeroa signature for content hash \(contentHashHex.prefix(12))…")
        
        func int64Value(_ value: Any?) -> Int64? {
            if let value = value as? Int64 { return value }
            if let value = value as? Int { return Int64(value) }
            if let value = value as? Double { return Int64(value) }
            if let value = value as? String { return Int64(value) }
            return nil
        }
        
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            let freshDefaults = UserDefaults(suiteName: "group.com.tls.zeroa-lasko")
            freshDefaults?.synchronize()
            defaults.synchronize()
            
            if let response = (freshDefaults?.dictionary(forKey: "lasko_post_sign_response") ?? defaults.dictionary(forKey: "lasko_post_sign_response")),
               let signature = response["signatureBase64"] as? String,
               let pubkey = response["pubkeyCompressedHex"] as? String {
                guard response["requestId"] as? String == requestId,
                      response["contentHashHex"] as? String == contentHashHex,
                      int64Value(response["timestamp"]) == Int64(timestampMs) else {
                    print("⚠️ LASKO: Ignoring stale/mismatched Zeroa signature response")
                    defaults.removeObject(forKey: "lasko_post_sign_response")
                    freshDefaults?.removeObject(forKey: "lasko_post_sign_response")
                    defaults.synchronize()
                    freshDefaults?.synchronize()
                    continue
                }
                print("✅ LASKO: Found Zeroa signature response!")
                print("   Signature length: \(signature.count) chars")
                print("   Public key: \(pubkey.prefix(16))...")
                defaults.removeObject(forKey: "lasko_post_sign_request")
                defaults.removeObject(forKey: "lasko_post_sign_response")
                freshDefaults?.removeObject(forKey: "lasko_post_sign_request")
                freshDefaults?.removeObject(forKey: "lasko_post_sign_response")
                defaults.synchronize()
                freshDefaults?.synchronize()
                await MainActor.run { self.needsOpenZeroaToSign = false }
                return ZeroaSignaturePayload(
                    signatureBase64: signature,
                    pubkeyCompressedHex: pubkey,
                    canonicalMessage: canonical
                )
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            // After the fast path, surface fallback UI while still polling briefly.
            if !offeredFallback, elapsed >= fastPathSeconds {
                offeredFallback = true
                await MainActor.run {
                    self.needsOpenZeroaToSign = true
                }
                print("⏳ LASKO: Silent sign fast-path elapsed — offering Open Zeroa fallback")
            }
            
            let delay = min(0.4, 0.05 * pow(2.0, Double(min(attempt, 3))))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            attempt += 1
            
            if attempt % 10 == 0 {
                print("🔍 LASKO: Still waiting... (\(String(format: "%.1f", elapsed))s elapsed)")
            }
        }
        
        // Leave the request in place until its own expiry so a user-driven Zeroa open can still sign it.
        defaults.removeObject(forKey: "lasko_post_sign_response")
        defaults.synchronize()
        let elapsed = Date().timeIntervalSince(startTime)
        print("❌ LASKO: Timed out waiting for Zeroa signature after \(String(format: "%.1f", elapsed))s")
        await MainActor.run {
            self.needsOpenZeroaToSign = true
        }
        return nil
    }
    
    func createComment(content: String, parentSequentialCode code: String, threadRootCode: String? = nil) async -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard appGroupsService.isProfileActive() else {
            print("❌ LASKO: Cannot create comment - Zeroa profile inactive")
            return false
        }
        guard await moderationPreflight(content: trimmed, parentSequentialCode: code) else { return false }
        // Ensure auth
        var tlsAddress = currentTLSAddress
        if !isAuthenticatedWithZeroa || (tlsAddress ?? "").isEmpty {
            if let addr = appGroupsService.getTLSAddress(), !addr.isEmpty,
               let _ = appGroupsService.sharedDefaults?.string(forKey: "halo_access_token") ?? appGroupsService.sharedDefaults?.string(forKey: "haloAccessToken") {
                self.isAuthenticatedWithZeroa = true
                self.currentTLSAddress = addr
                tlsAddress = addr
                loadUserActionSets(for: addr)
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
            guard let signaturePayload = await obtainPostSignature(content: trimmed, tlsAddress: tls, timestampMs: nowMs) else {
                print("❌ LASKO: Failed to obtain signature for comment")
                return false
            }
            // Note: Pre-verification is optional - the server will verify on post creation
            // The /halo/verify endpoint expects a nonce (for auth), not a message (for posts)
            // So we skip verification here and let the server handle it
            let verificationResult = await backendVerifySignature(
                address: tls,
                message: signaturePayload.canonicalMessage,
                signature: signaturePayload.signatureBase64,
                pubkeyCompressedHex: signaturePayload.pubkeyCompressedHex
            )
            if !verificationResult {
                print("⚠️ LASKO: Pre-verification failed, proceeding with comment creation")
            }
            body["signature"] = signaturePayload.signatureBase64
            body["pubkey"] = signaturePayload.pubkeyCompressedHex
            if let profileName = appGroupsService.getProfileDisplayName(for: tls), !profileName.isEmpty {
                body["profileName"] = profileName
            }
            // Include subscription token if available
            if let subscriptionToken = getSubscriptionToken() {
                let tokenDict: [String: Any] = [
                    "txid": subscriptionToken.txid,
                    "signature": subscriptionToken.signature ?? "",
                    "userAddress": subscriptionToken.userAddress,
                    "timestamp": subscriptionToken.timestamp,
                    "expiresAt": subscriptionToken.expiresAt,
                    "subscriptionAddress": subscriptionToken.subscriptionAddress,
                    "amount": subscriptionToken.amount
                ]
                body["subscriptionToken"] = tokenDict
            }
            print("🔗 LASKO: POST /posts (comment) parent=\(code) tls=\(tls) contentLen=\(trimmed.count)")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 && http.statusCode != 201 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                var errorMessage: String? = nil
                if let any = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    errorMessage = any["message"] as? String ?? any["error"] as? String
                }
                print("❌ LASKO: createComment server error: \(http.statusCode) \(bodyStr)")
                
                if http.statusCode == 422 {
                    await MainActor.run {
                        self.errorMessage = errorMessage ?? "Post does not meet Charter standards."
                    }
                    return false
                }
                if http.statusCode == 503 {
                    await MainActor.run {
                        self.errorMessage = errorMessage ?? "Review service unavailable. Try again."
                    }
                    return false
                }
                
                // Subscription is not enforced right now; surface any 403 as a generic auth error
                // rather than a misleading "subscription required" prompt.
                if http.statusCode == 403 {
                    await MainActor.run {
                        self.errorMessage = errorMessage ?? "Couldn't post. Reconnect Zeroa and try again."
                    }
                }
                return false
            }
            let feedRoot = resolvedThreadRootCode(forParent: code, explicitRoot: threadRootCode)
            markUserCommentedOnPost(feedRoot)
            // After posting a comment, refresh the main post's comments to show the new comment
            if let mainPostCode = getMainPostCode(forCommentCode: code) ?? (feedRoot == code ? code : nil) {
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

    /// Charter preflight before Zeroa signing. Fail closed on service errors.
    func moderationPreflight(content: String, parentSequentialCode: String? = nil) async -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isReviewingContent = true
        let reviewStart = Date()
        defer {
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(reviewStart)
                if elapsed < 0.7 {
                    try? await Task.sleep(nanoseconds: UInt64((0.7 - elapsed) * 1_000_000_000))
                }
                self.isReviewingContent = false
            }
        }

        guard let url = URL(string: "\(effectiveBaseURL)/moderation/check") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30
        if let bundleId = Bundle.main.bundleIdentifier { req.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
        let tls = currentTLSAddress ?? appGroupsService.getTLSAddress()
        if let tls, !tls.isEmpty { req.setValue(tls, forHTTPHeaderField: "X-TLS-Address") }
        if let tls, let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = ["content": trimmed, "postType": "free"]
        if let parent = parentSequentialCode, !parent.isEmpty {
            body["parentSequentialCode"] = parent
        }
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 422 {
                let tlsForLog = tls ?? "unknown"
                let kind = (parentSequentialCode?.isEmpty == false) ? "comment" : "post"
                print("🚫 LASKO: MODERATION_BLOCK \(kind) actor=\(tlsForLog) len=\(trimmed.count) preview=\"\(String(trimmed.prefix(60)))\"")
                self.errorMessage = "Post does not meet Charter standards."
                return false
            }
            if http.statusCode != 200 {
                var message = "Review service unavailable. Try again."
                if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    message = (any["message"] as? String) ?? (any["error"] as? String) ?? message
                }
                self.errorMessage = message
                return false
            }
            self.errorMessage = nil
            let kind = (parentSequentialCode?.isEmpty == false) ? "comment" : "post"
            print("✅ LASKO: MODERATION_PASS \(kind) len=\(trimmed.count) — proceeding to Zeroa signing")
            return true
        } catch {
            self.errorMessage = "Review service unavailable. Try again."
            return false
        }
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
                loadUserActionSets(for: addr)
                print("✅ LASKO: Recovered auth state from App Groups for posting")
            }
        }
        guard isAuthenticatedWithZeroa, let tlsAddress = tlsAddress else {
            print("❌ LASKO: Cannot create post - not authenticated with Zeroa. isAuth=\(isAuthenticatedWithZeroa), tls=\(tlsAddress ?? "nil")")
            return false
        }
        guard await moderationPreflight(content: trimmed) else { return false }
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
            if let profileName = appGroupsService.getProfileDisplayName(for: tlsAddress), !profileName.isEmpty {
                body["profileName"] = profileName
            }
            // Include profile image if available
            if let profileImage = appGroupsService.getProfileImage(for: tlsAddress),
               let imageData = profileImage.jpegData(compressionQuality: 0.7) {
                let base64String = imageData.base64EncodedString()
                body["profileImageBase64"] = base64String
            }
            // Include subscription token if available
            if let subscriptionToken = getSubscriptionToken() {
                let tokenDict: [String: Any] = [
                    "txid": subscriptionToken.txid,
                    "signature": subscriptionToken.signature ?? "",
                    "userAddress": subscriptionToken.userAddress,
                    "timestamp": subscriptionToken.timestamp,
                    "expiresAt": subscriptionToken.expiresAt,
                    "subscriptionAddress": subscriptionToken.subscriptionAddress,
                    "amount": subscriptionToken.amount
                ]
                body["subscriptionToken"] = tokenDict
                print("🔍 LASKO: Including subscription token in post request (optional; not enforced)")
            }
            // Subscription is not a required feature right now — posts are accepted without a token.
            // Note: Bio can be added later when we have a bio field in App Groups
            print("🔍 LASKO: Requesting signature from Zeroa for post")
            guard let signaturePayload = await obtainPostSignature(content: trimmed, tlsAddress: tlsAddress, timestampMs: nowMs) else {
                print("❌ LASKO: Failed to obtain signature for post")
                return false
            }
            // Note: Pre-verification is optional - the server will verify on post creation
            // The /halo/verify endpoint expects a nonce (for auth), not a message (for posts)
            // So we skip verification here and let the server handle it
            let verificationResult = await backendVerifySignature(
                address: tlsAddress,
                message: signaturePayload.canonicalMessage,
                signature: signaturePayload.signatureBase64,
                pubkeyCompressedHex: signaturePayload.pubkeyCompressedHex
            )
            if !verificationResult {
                print("⚠️ LASKO: Pre-verification failed, proceeding with post creation")
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
                var errorMessage: String? = nil
                if let any = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let parts = [any["error"], any["message"], any["reason"], any["code"]].compactMap { $0 as? String }
                    if !parts.isEmpty { detail = parts.joined(separator: " | ") }
                    errorMessage = any["message"] as? String ?? any["error"] as? String
                }
                print("❌ LASKO: createPost server error: status=\(http.statusCode) detail=\(detail)")
                
                if http.statusCode == 422 {
                    await MainActor.run {
                        self.errorMessage = errorMessage ?? "Post does not meet Charter standards."
                    }
                    return false
                }
                if http.statusCode == 503 {
                    await MainActor.run {
                        self.errorMessage = errorMessage ?? "Review service unavailable. Try again."
                    }
                    return false
                }
                
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
            // Success: extract id and insert optimistically.
            var createdId: String? = nil
            var createdProfileName: String? = nil
            if let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                createdId = obj["sequentialCode"] as? String
                if let dataObj = obj["data"] as? [String: Any] {
                    createdId = createdId ?? (dataObj["sequentialCode"] as? String) ?? (dataObj["id"] as? String)
                    createdProfileName = dataObj["profileName"] as? String
                }
            }
            if let createdId {
                print("✅ LASKO: Post created with LAS=\(createdId)")
            }
            DispatchQueue.main.async {
                let authorName = (createdProfileName?.isEmpty == false) ? createdProfileName! : self.username
                let profileName = createdProfileName ?? self.appGroupsService.getProfileDisplayName(for: tlsAddress)
                let newPost = Post(
                    id: createdId ?? UUID().uuidString,
                    content: trimmed,
                    author: authorName,
                    timestamp: Date(),
                    likes: 0,
                    replies: 0,
                    userRank: "Bronze",
                    avatarURL: nil,
                    parentCode: nil,
                    tlsAddress: tlsAddress,
                    profileName: profileName
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
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty else {
            print("❌ LASKO: likePost failed - no TLS address")
            return
        }
        guard !hasUserLikedPost(post.id) else { return }
        markUserLikedPost(post.id)

        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else {
            print("❌ LASKO: likePost failed - no token")
            unmarkUserLikedPost(post.id)
            return
        }

        do {
            guard let encodedPostId = post.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                unmarkUserLikedPost(post.id)
                return
            }
            let url = URL(string: "\(effectiveBaseURL)/posts/\(encodedPostId)/like")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
            if let bundleId = Bundle.main.bundleIdentifier {
                request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["userAddress": tls])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let likesCount = intValue(dataObj["likesCount"]) else {
                print("❌ LASKO: likePost server error")
                unmarkUserLikedPost(post.id)
                return
            }
            updateLocalPost(post.id, likesCount: likesCount)
            print("✅ LASKO: Liked post \(post.id) (count=\(likesCount))")
        } catch {
            print("❌ LASKO: likePost error: \(error)")
            unmarkUserLikedPost(post.id)
        }
    }

    func announcePost(_ post: Post) async {
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty else {
            print("❌ LASKO: announcePost failed - no TLS address")
            return
        }
        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else {
            print("❌ LASKO: announcePost failed - no token")
            return
        }

        let alreadyAnnounced = hasUserAnnouncedPost(post.id)

        do {
            guard let encodedPostId = post.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
            let url = URL(string: "\(effectiveBaseURL)/posts/\(encodedPostId)/announce")!
            var request = URLRequest(url: url)
            request.httpMethod = alreadyAnnounced ? "DELETE" : "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
            if let bundleId = Bundle.main.bundleIdentifier {
                request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["userAddress": tls])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let broadcastCount = intValue(dataObj["broadcastCount"]) else {
                print("❌ LASKO: announcePost server error")
                return
            }
            if alreadyAnnounced {
                unmarkUserAnnouncedPost(post.id)
                await MainActor.run {
                    self.removeAnnounceRepostsFromFeed(postId: post.id, announcedBy: tls)
                }
                print("✅ LASKO: Un-announced post \(post.id) (broadcastCount=\(broadcastCount))")
            } else {
                markUserAnnouncedPost(post.id)
                print("✅ LASKO: Announced post \(post.id) (broadcastCount=\(broadcastCount))")
            }
            updateLocalPost(post.id, broadcastCount: broadcastCount)
        } catch {
            print("❌ LASKO: announcePost error: \(error)")
        }
    }

    func reportPost(_ post: Post) async -> Bool {
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty else { return false }
        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else { return false }
        guard let encodedPostId = post.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return false }
        do {
            var request = URLRequest(url: URL(string: "\(effectiveBaseURL)/posts/\(encodedPostId)/report")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
            if let bundleId = Bundle.main.bundleIdentifier { request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["userAddress": tls], options: [])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            removeLocalPost(post.id)
            return true
        } catch {
            print("❌ LASKO: reportPost error: \(error)")
            await MainActor.run { self.errorMessage = "Failed to submit report." }
            return false
        }
    }

    func deletePost(_ post: Post) async -> Bool {
        guard let tls = (currentTLSAddress ?? appGroupsService.getTLSAddress()), !tls.isEmpty else { return false }
        guard post.tlsAddress == tls else {
            await MainActor.run { self.errorMessage = "Only your posts can be deleted." }
            return false
        }
        guard let token = await ensureTokenForAddress(tls, timeoutSeconds: 5.0) else { return false }
        guard let encodedPostId = post.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return false }
        do {
            var request = URLRequest(url: URL(string: "\(effectiveBaseURL)/posts/\(encodedPostId)")!)
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(tls, forHTTPHeaderField: "X-TLS-Address")
            if let bundleId = Bundle.main.bundleIdentifier { request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["userAddress": tls], options: [])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { self.errorMessage = "Failed to delete post." }
                return false
            }
            removeLocalPost(post.id)
            return true
        } catch {
            print("❌ LASKO: deletePost error: \(error)")
            await MainActor.run { self.errorMessage = "Failed to delete post." }
            return false
        }
    }

    private func removeLocalPost(_ postId: String) {
        DispatchQueue.main.async {
            self.posts.removeAll { $0.id == postId }
            self.repliesByCode.removeValue(forKey: postId)
            for key in self.repliesByCode.keys {
                self.repliesByCode[key]?.removeAll { $0.id == postId }
            }
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func updateLocalPost(_ postId: String, likesCount: Int? = nil, isLiked: Bool? = nil, broadcastCount: Int? = nil, tlsCount: Int? = nil) {
        let replace: (Post) -> Post = { post in
            Post(
                id: post.id,
                content: post.content,
                author: post.author,
                timestamp: post.timestamp,
                likes: likesCount ?? post.likes,
                replies: post.replies,
                isLiked: isLiked ?? post.isLiked,
                userRank: post.userRank,
                avatarURL: post.avatarURL,
                parentCode: post.parentCode,
                tlsAddress: post.tlsAddress,
                profileName: post.profileName,
                broadcastCount: broadcastCount ?? post.broadcastCount,
                tlsCount: tlsCount ?? post.tlsCount,
                followerCount: post.followerCount,
                feedKey: post.feedKey,
                announcedBy: post.announcedBy,
                announcedByProfileName: post.announcedByProfileName,
                announcedAt: post.announcedAt
            )
        }

        DispatchQueue.main.async {
            if let index = self.posts.firstIndex(where: { $0.id == postId }) {
                self.posts[index] = replace(self.posts[index])
            }
            for key in self.repliesByCode.keys {
                guard let index = self.repliesByCode[key]?.firstIndex(where: { $0.id == postId }),
                      let existing = self.repliesByCode[key]?[index] else {
                    continue
                }
                self.repliesByCode[key]?[index] = replace(existing)
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
                       let rewardId = dataObj["rewardId"] as? String,
                       let toAddress = dataObj["toAddress"] as? String {
                        print("⏳ LASKO: TLS reward pending; requesting Zeroa payment rewardId=\(rewardId)")

                        await requestZeroaTLSPayment(toAddress: toAddress, amount: amount, postId: post.id, rewardId: rewardId)
                        let payment = await waitForTLSPaymentResponse(postId: post.id, rewardId: rewardId, timeoutSeconds: 90)
                        let settled = await settleTLSReward(post: post, rewardId: rewardId, payment: payment, token: token, fromAddress: tls)
                        return settled
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
    
    private func requestZeroaTLSPayment(toAddress: String, amount: Double, postId: String, rewardId: String) async {
        guard let defaults = appGroupsService.sharedDefaults else {
            print("❌ LASKO: Cannot request TLS payment - App Groups unavailable")
            return
        }
        defaults.removeObject(forKey: "lasko_tls_payment_response")
        
        let request: [String: Any] = [
            "toAddress": toAddress,
            "amount": amount,
            "postId": postId,
            "rewardId": rewardId,
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

    private struct TLSPaymentResponse {
        let success: Bool
        let txid: String?
        let error: String?
    }

    private func waitForTLSPaymentResponse(postId: String, rewardId: String, timeoutSeconds: TimeInterval) async -> TLSPaymentResponse {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let response = getTLSPaymentResponse(postId: postId, rewardId: rewardId) {
                return response
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return TLSPaymentResponse(success: false, txid: nil, error: "Zeroa TLS payment timed out")
    }

    private func getTLSPaymentResponse(postId: String, rewardId: String) -> TLSPaymentResponse? {
        guard let defaults = appGroupsService.sharedDefaults else { return nil }
        defaults.synchronize()
        guard let responseData = defaults.dictionary(forKey: "lasko_tls_payment_response") else { return nil }
        guard responseData["postId"] as? String == postId,
              responseData["rewardId"] as? String == rewardId else {
            return nil
        }

        let success = responseData["success"] as? Bool ?? false
        let txid = responseData["txid"] as? String
        let error = responseData["error"] as? String
        defaults.removeObject(forKey: "lasko_tls_payment_response")
        defaults.synchronize()
        return TLSPaymentResponse(success: success, txid: txid?.isEmpty == false ? txid : nil, error: error?.isEmpty == false ? error : nil)
    }

    private func settleTLSReward(post: Post, rewardId: String, payment: TLSPaymentResponse, token: String, fromAddress: String) async -> Bool {
        do {
            guard let encodedPostId = post.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let encodedRewardId = rewardId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                return false
            }
            let url = URL(string: "\(effectiveBaseURL)/posts/\(encodedPostId)/reward/\(encodedRewardId)/settle")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(fromAddress, forHTTPHeaderField: "X-TLS-Address")
            if let bundleId = Bundle.main.bundleIdentifier {
                request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id")
            }
            let body: [String: Any] = [
                "fromAddress": fromAddress,
                "success": payment.success,
                "txid": payment.txid ?? "",
                "error": payment.error ?? ""
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any] else {
                print("❌ LASKO: settleTLSReward server error")
                return false
            }
            if payment.success, let tlsCount = intValue(dataObj["tlsCount"]) {
                print("✅ LASKO: TLS reward paid and settled, txid=\(payment.txid ?? "unknown")")
                self.updateLocalPost(post.id, tlsCount: tlsCount)
                return true
            }
            print("❌ LASKO: TLS reward failed: \(payment.error ?? "unknown error")")
            return false
        } catch {
            print("❌ LASKO: settleTLSReward error: \(error)")
            return false
        }
    }
    
    // MARK: - Subscription Management
    
    private let SUBSCRIPTION_ADDRESS = "TesBmcgLQsowvYEYPXpSHkkapoTbVV7Xfe"
    private let SUBSCRIPTION_AMOUNT = 10.0
    private let SUBSCRIPTION_DURATION_DAYS = 30
    
    func requestSubscriptionPayment() async -> Bool {
        guard let tlsAddress = currentTLSAddress else {
            print("❌ LASKO: Cannot request subscription payment - no TLS address")
            return false
        }
        
        guard let defaults = appGroupsService.sharedDefaults else {
            print("❌ LASKO: Cannot request subscription payment - App Groups unavailable")
            return false
        }
        
        let request: [String: Any] = [
            "toAddress": SUBSCRIPTION_ADDRESS,
            "amount": SUBSCRIPTION_AMOUNT,
            "purpose": "subscription",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        // Clear any previous response
        defaults.removeObject(forKey: "lasko_subscription_payment_response")
        defaults.synchronize()
        
        defaults.set(request, forKey: "lasko_subscription_payment_request")
        defaults.synchronize()
        
        print("📤 LASKO: Requested Zeroa to send subscription payment: \(SUBSCRIPTION_AMOUNT) TLS to \(SUBSCRIPTION_ADDRESS)")
        
        // Send Darwin notification to Zeroa
        let notificationName = CFNotificationName("com.telestai.lasko.subscription.payment.request" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        
        // Use continuation-based approach for immediate notification response
        subscriptionPaymentResolved = false // Reset flag
        return await withCheckedContinuation { continuation in
            // Store continuation so notification handler can resume it
            subscriptionPaymentContinuation = continuation
            
            // Set up Darwin notification observer for immediate response
            let responseNotificationName = "com.telestai.zeroa.subscription.payment.response" as CFString
            let callback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (center, observer, name, object, userInfo) in
                print("📢 LASKO: Received Darwin notification for subscription payment response")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("HandleSubscriptionPaymentResponse"), object: nil)
                }
            }
            
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                callback,
                responseNotificationName,
                nil,
                .deliverImmediately
            )
            isObservingSubscriptionPayment = true
            
            // Listen for the local notification
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSubscriptionPaymentResponseNotification),
                name: NSNotification.Name("HandleSubscriptionPaymentResponse"),
                object: nil
            )
            
            // Start polling task (will check immediately and then periodically)
            Task { @MainActor in
                let maxAttempts = 180 // 90 seconds max (increased to handle slow payment processing)
                for attempt in 1...maxAttempts {
                    // Check if already resolved by notification handler
                    guard !self.subscriptionPaymentResolved else {
                        print("🔍 LASKO: Subscription payment already resolved by notification handler")
                        return
                    }
                    
                    // Check immediately (notification may have arrived)
                    if let response = self.getSubscriptionPaymentResponse() {
                        // Clean up observer
                        self.subscriptionPaymentResolved = true
                        self.stopSubscriptionPaymentObserver()
                        let cont = self.subscriptionPaymentContinuation
                        self.subscriptionPaymentContinuation = nil
                        
                        if response.success, let txid = response.txid {
                            // Create subscription token
                            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                            let expiresAt = timestamp + Int64(SUBSCRIPTION_DURATION_DAYS * 24 * 60 * 60 * 1000)
                            
                            let token = SubscriptionToken(
                                txid: txid,
                                signature: response.signature,
                                userAddress: tlsAddress,
                                timestamp: timestamp,
                                expiresAt: expiresAt,
                                subscriptionAddress: SUBSCRIPTION_ADDRESS,
                                amount: SUBSCRIPTION_AMOUNT
                            )
                            
                            // Store token
                            self.saveSubscriptionToken(token)
                            print("✅ LASKO: Subscription token created and saved for \(tlsAddress)")
                            cont?.resume(returning: true)
                            return
                        } else {
                            print("❌ LASKO: Subscription payment failed: \(response.error ?? "unknown error")")
                            cont?.resume(returning: false)
                            return
                        }
                    }
                    
                    // Sleep only if no response yet
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                
                // Clean up observer on timeout
                guard !self.subscriptionPaymentResolved else {
                    return // Already resolved by notification handler
                }
                self.stopSubscriptionPaymentObserver()
                let cont = self.subscriptionPaymentContinuation
                self.subscriptionPaymentContinuation = nil
                print("❌ LASKO: Subscription payment timeout")
                cont?.resume(returning: false)
            }
        }
    }
    
    private func getSubscriptionPaymentResponse() -> SubscriptionPaymentResponse? {
        guard let defaults = appGroupsService.sharedDefaults else { return nil }
        defaults.synchronize()
        Thread.sleep(forTimeInterval: 0.05)
        
        guard let responseData = defaults.dictionary(forKey: "lasko_subscription_payment_response") else {
            return nil
        }
        
        let success = responseData["success"] as? Bool ?? false
        let txid = responseData["txid"] as? String
        let signature = responseData["signature"] as? String
        let error = responseData["error"] as? String
        
        return SubscriptionPaymentResponse(success: success, txid: txid, signature: signature, error: error)
    }
    
    func getSubscriptionToken() -> SubscriptionToken? {
        guard let tlsAddress = currentTLSAddress else { return nil }
        guard let defaults = appGroupsService.sharedDefaults else { return nil }
        
        guard let tokenData = defaults.data(forKey: "lasko_subscription_token_\(tlsAddress)") else {
            return nil
        }
        
        do {
            let token = try JSONDecoder().decode(SubscriptionToken.self, from: tokenData)
            if token.isValid {
                return token
            } else {
                // Expired, remove it
                defaults.removeObject(forKey: "lasko_subscription_token_\(tlsAddress)")
                return nil
            }
        } catch {
            print("❌ LASKO: Failed to decode subscription token: \(error)")
            return nil
        }
    }
    
    func hasActiveSubscription() -> Bool {
        return getSubscriptionToken() != nil
    }
    
    private func saveSubscriptionToken(_ token: SubscriptionToken) {
        guard let tlsAddress = currentTLSAddress else { return }
        guard let defaults = appGroupsService.sharedDefaults else { return }
        
        do {
            let tokenData = try JSONEncoder().encode(token)
            defaults.set(tokenData, forKey: "lasko_subscription_token_\(tlsAddress)")
            defaults.synchronize()
        } catch {
            print("❌ LASKO: Failed to save subscription token: \(error)")
        }
    }
    
    struct SubscriptionPaymentResponse {
        let success: Bool
        let txid: String?
        let signature: String?
        let error: String?
    }
    
    // Helper function to find the main post code for a given comment
    private func resolvedThreadRootCode(forParent code: String, explicitRoot: String?) -> String {
        if let explicitRoot, !explicitRoot.isEmpty { return explicitRoot }
        if posts.contains(where: { $0.id == code && !$0.isReply }) { return code }
        if let root = getMainPostCode(forCommentCode: code) { return root }
        return code
    }

    private func getMainPostCode(forCommentCode commentCode: String) -> String? {
        if posts.contains(where: { $0.id == commentCode && !$0.isReply }) {
            return commentCode
        }
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
    
    func verifyMessage(message: String, signature: String, address: String, pubkeyCompressedHex: String? = nil) async -> Bool {
        await backendVerifySignature(
            address: address,
            message: message,
            signature: signature,
            pubkeyCompressedHex: pubkeyCompressedHex
        )
    }
    
    // MARK: - Username Management
    
    private func addressBasedFallbackName(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return "User" }
        return "User\(String(trimmed.prefix(6)))"
    }
    
    private func cacheProfileName(_ name: String?, for address: String?) {
        guard let name, !name.isEmpty,
              let address, !address.isEmpty else { return }
        profileNameByAddress[address] = name
    }
    
    private func isUsableDisplayName(_ value: String?) -> Bool {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return false
        }
        let lower = trimmed.lowercased()
        return lower != "null" && lower != "undefined" && lower != "none" && lower != "unknown" && lower != "user"
    }

    private func resolveAuthorDisplayName(profileName: String?, userAddress: String?) -> String {
        if isUsableDisplayName(profileName), let profileName {
            cacheProfileName(profileName, for: userAddress)
            return profileName
        }
        guard let userAddress, !userAddress.isEmpty, userAddress != "Unknown" else {
            return "User"
        }
        if userAddress == currentTLSAddress {
            if let synced = appGroupsService.getProfileDisplayName(for: userAddress), !synced.isEmpty {
                return synced
            }
            return username
        }
        if let cached = profileNameByAddress[userAddress] {
            return cached
        }
        return addressBasedFallbackName(userAddress)
    }
    
    /// Name shown in feed cards — prefers Zeroa profileName, not TLS address.
    func feedDisplayName(for post: Post) -> String {
        if isUsableDisplayName(post.profileName), let profileName = post.profileName {
            return profileName
        }
        if let addr = post.tlsAddress {
            return getDisplayName(for: addr)
        }
        let author = post.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if author.isEmpty || author == "Unknown" || author.hasPrefix("T") && author.count > 20 {
            return "User"
        }
        return author
    }

    func announcerDisplayName(for post: Post) -> String {
        if let profileName = post.announcedByProfileName, !profileName.isEmpty {
            return profileName
        }
        if let address = post.announcedBy {
            return getDisplayName(for: address)
        }
        return "Someone"
    }

    /// Top-level posts and announced items belong in the main feed; ordinary replies stay in threads.
    private static func isMainFeedPost(_ post: Post) -> Bool {
        if post.isAnnounceRepost { return true }
        return !post.isReply
    }

    func threadRootCode(for post: Post) -> String {
        guard post.isReply else { return post.id }
        if let parent = post.parentCode, !parent.isEmpty,
           posts.contains(where: { $0.id == parent && !$0.isReply }) {
            return parent
        }
        if let main = getMainPostCode(forCommentCode: post.id) {
            return main
        }
        return post.parentCode ?? post.id
    }
    
    func getDisplayName(for address: String) -> String {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == "Unknown" {
            return "User"
        }
        if normalized == currentTLSAddress {
            if let synced = appGroupsService.getProfileDisplayName(for: normalized), !synced.isEmpty {
                return synced
            }
            return username
        }
        if let cached = profileNameByAddress[normalized] {
            return cached
        }
        if let match = posts.first(where: { $0.tlsAddress == normalized }),
           let profileName = match.profileName, !profileName.isEmpty {
            cacheProfileName(profileName, for: normalized)
            return profileName
        }
        return addressBasedFallbackName(normalized)
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

