import SwiftUI
import UIKit
import CoreFoundation

@main
struct ZeroaApp: App {
    @StateObject private var authManager = AuthManager()
    @State private var showingLASKOAuth = false
    @State private var laskoAuthRequest: LASKOAuthRequest?
    @StateObject private var authService = LASKOAuthService()
    @State private var laskoCheckTimer: Timer?
    @State private var didNotifyLASKO = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onAppear {
                    TLSRPCClient.shared.performLegacyOverrideMigrationIfNeeded()
                    // Restore Chief profile into the new App Group / sandbox after bundle rename.
                    ProfileLegacyMigration.runIfNeeded()
                    // Ensure profile is active if user is authenticated
                    if authManager.isAuthenticated {
                        AppGroupsService.shared.setProfileActive(true)
                    }
                    Task { await HaloService.shared.ensureToken() }
                    // Seed Flux address if not present (from user-provided address)
                    if AppGroupsService.shared.getFluxAddress() == nil {
                        AppGroupsService.shared.storeFluxAddress("t1fBrjkEro8DUfQ3c7nPuF96qmz3C3MVDNL")
                    }
                    // Seed TLS address into App Groups if present but missing
                    if AppGroupsService.shared.getTLSAddress() == nil,
                       let tls = WalletService.shared.loadAddress() {
                        AppGroupsService.shared.storeTLSAddress(tls)
                    }
                    // Persist compressed public key once at startup for LASKO reuse
                    if AppGroupsService.shared.sharedDefaults?.string(forKey: "zeroa_pubkey_compressed_hex") == nil,
                       let pubHex = CryptoService.shared.getCompressedPublicKeyHex(keychain: WalletService.shared.keychain) {
                        AppGroupsService.shared.sharedDefaults?.set(pubHex, forKey: "zeroa_pubkey_compressed_hex")
                        AppGroupsService.shared.sharedDefaults?.synchronize()
                    }
                }
                // Headless mode: no sheet presentation
                .onChange(of: authManager.isAuthenticated) { isAuthed in
                    print("🔍 Auth state changed: isAuthenticated=\(isAuthed)")
                    if isAuthed {
                        // Set profile to active when authentication state changes to true
                        AppGroupsService.shared.setProfileActive(true)
                        print("✅ Profile marked as active (auth state changed)")
                        if let pendingRequest = authService.checkForPendingAuthRequest() {
                            Task { await headlessApproveLASKO(request: pendingRequest) }
                        }
                    } else {
                        // Set profile to inactive when authentication state changes to false
                        AppGroupsService.shared.setProfileActive(false)
                    }
                }
                .onAppear {
                    checkForPendingLASKORequests()
                    startLASKORequestTimer()
                    setupDarwinNotifications()
                    // Do not reset didNotifyLASKO on appear to avoid re-opening LASKO on stale responses
                    // If a stored request is already present when coming to foreground for the first time, show immediately
                    if let pendingRequest = authService.checkForPendingAuthRequest() {
                        if authManager.isAuthenticated {
                            Task { await headlessApproveLASKO(request: pendingRequest) }
                            didNotifyLASKO = false
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task { await HaloService.shared.ensureToken() }
                    checkForPendingLASKORequests()
                    startLASKORequestTimer()
                    handleBackgroundHandshakes()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    stopLASKORequestTimer()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HandlePostSignRequest"))) { _ in
                    print("🔔 Zeroa: Received HandlePostSignRequest notification")
                    handleBackgroundHandshakes()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HandleTLSPaymentRequest"))) { _ in
                    print("🔔 Zeroa: Received HandleTLSPaymentRequest notification")
                    handleBackgroundHandshakes()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HandleTokenRefreshRequest"))) { _ in
                    print("🔔 Zeroa: Received HandleTokenRefreshRequest notification")
                    handleBackgroundHandshakes()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HandleLASKOAuthRequest"))) { _ in
                    print("🔔 Zeroa: Received HandleLASKOAuthRequest notification")
                    checkForPendingLASKORequests()
                }
        }
    }
    
    private func startLASKORequestTimer() {
        stopLASKORequestTimer() // Stop any existing timer
        
        // Add a timer to actively check for LASKO requests and background handshakes (token refresh, post-sign)
        laskoCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkForPendingLASKORequests()
            handleBackgroundHandshakes()
        }
    }
    
    private func stopLASKORequestTimer() {
        laskoCheckTimer?.invalidate()
        laskoCheckTimer = nil
    }
    
    // MARK: - Darwin Notifications (cross-process communication)
    private func setupDarwinNotifications() {
        // Register for post-sign requests
        let postSignNotificationName = "com.telestai.lasko.post.sign.request" as CFString
        let postSignCallback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (center, observer, name, object, userInfo) in
            print("📢 Zeroa: Received Darwin notification for post-sign request")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("HandlePostSignRequest"), object: nil)
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            postSignCallback,
            postSignNotificationName,
            nil,
            .deliverImmediately
        )
        
        // Register for token refresh requests
        let tokenRefreshNotificationName = "com.telestai.lasko.token.refresh.request" as CFString
        let tokenRefreshCallback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (center, observer, name, object, userInfo) in
            print("📢 Zeroa: Received Darwin notification for token refresh request")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("HandleTokenRefreshRequest"), object: nil)
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            tokenRefreshCallback,
            tokenRefreshNotificationName,
            nil,
            .deliverImmediately
        )

        // Register for LASKO login / identity auth requests
        let authRequestNotificationName = "com.telestai.lasko.auth.request" as CFString
        let authRequestCallback: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { (center, observer, name, object, userInfo) in
            print("📢 Zeroa: Received Darwin notification for LASKO auth request")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("HandleLASKOAuthRequest"), object: nil)
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            authRequestCallback,
            authRequestNotificationName,
            nil,
            .deliverImmediately
        )
        
        print("✅ Zeroa: Darwin notification listeners set up")
    }
    
    private func checkForPendingLASKORequests() {
        // CRITICAL: Force App Groups synchronization before checking
        // This ensures we get the latest data from LASKO
        if let defaults = AppGroupsService.shared.sharedDefaults {
            defaults.synchronize()
            // Small delay to ensure cross-process sync
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        // Check for pending auth request (App Groups only)
        if let pendingRequest = authService.checkForPendingAuthRequest() {
            print("📥 Found pending LASKO auth request: \(pendingRequest.appName)")
            
            // Headless: if logged in, sign and respond silently; otherwise do nothing
            if authManager.isAuthenticated {
                print("✅ Zeroa is logged in - performing headless approval")
                Task { await headlessApproveLASKO(request: pendingRequest) }
            } else {
                print("❌ Zeroa is not logged in - deferring headless approval until login")
            }
            return
        }
        
        // Check for completed auth response (App Groups only)
        if let authResponse = authService.getAuthResponseFromZeroa() {
            // Headless: do not app-switch; simply leave response for LASKO to consume
            return
        }
        
        // Debug: Check if the key exists but parsing failed
        if let defaults = AppGroupsService.shared.sharedDefaults,
           defaults.object(forKey: "lasko_auth_request") != nil {
            print("⚠️ Zeroa: Found 'lasko_auth_request' key but parsing failed - checking raw data...")
            if let rawData = defaults.dictionary(forKey: "lasko_auth_request") {
                print("⚠️ Zeroa: Raw request data: \(rawData)")
            }
        }
    }

    // MARK: - Background handshakes (post-sign + token refresh)
    private func handleBackgroundHandshakes() {
        // Token refresh request from LASKO
        if AppGroupsService.shared.hasTokenRefreshRequest() {
            Task {
                // Force token refresh by clearing the stored token first
                // This ensures we always get a fresh token when LASKO requests it
                HaloAPIService.shared.clearToken()
                
                // Check if token refresh was successful by verifying a token was stored
                await HaloService.shared.ensureToken()
                
                // Verify that a token was actually stored before marking as refreshed
                if let (token, _) = HaloAPIService.shared.storedToken(), !token.isEmpty {
                    AppGroupsService.shared.markTokenRefreshed()
                    AppGroupsService.shared.clearTokenRefreshRequest()
                } else {
                    print("❌ ZeroaApp: Token refresh FAILED - no token stored. LASKO will need to retry.")
                    // Don't mark as refreshed or clear the request - let LASKO retry
                }
            }
        }
        
        // Post-sign request
        if let req = AppGroupsService.shared.getPostSignRequest() {
            guard authManager.isAuthenticated else {
                return
            }
            
            let contentHash = req["contentHashHex"] as? String ?? ""
            let timestampMs = (req["timestamp"] as? Int64) ?? Int64(Date().timeIntervalSince1970 * 1000)
            let userAddress = WalletService.shared.loadAddress() ?? ""
            // Use the bundle ID from the request (LASKO's bundle ID), not Zeroa's
            let bundleId = req["bundleId"] as? String ?? Bundle.main.bundleIdentifier ?? ""
            let canonical = "LASKO_POST|\(contentHash)|\(timestampMs)|\(userAddress)|\(bundleId)|v1"
            
            if let sigB64 = CryptoService.shared.signMessageBase64(canonical, keychain: WalletService.shared.keychain),
               let pubHex = CryptoService.shared.getCompressedPublicKeyHex(keychain: WalletService.shared.keychain) {
                AppGroupsService.shared.storePostSignResponse(signatureBase64: sigB64, pubkeyCompressedHex: pubHex, timestampMs: timestampMs)
                AppGroupsService.shared.clearPostSignRequest()
            } else {
                print("❌ ZeroaApp: Failed to create signature or get public key for post-sign")
            }
        }
        
        // TLS payment request from LASKO
        if let req = AppGroupsService.shared.getTLSPaymentRequest() {
            guard authManager.isAuthenticated else {
                return
            }
            
            let toAddress = req["toAddress"] as? String ?? ""
            let amount = req["amount"] as? Double ?? 10.0
            let postId = req["postId"] as? String ?? ""
            
            Task {
                let tlsService = TLSBlockchainService.shared
                let message = "LASKO Post Reward: \(postId)"
                let response = await tlsService.sendPayment(
                    toAddress: toAddress,
                    amount: amount,
                    message: message,
                    messageType: "payment"
                )
                
                if response.success {
                    print("✅ ZeroaApp: TLS payment sent successfully, txid: \(response.txid?.prefix(16) ?? "unknown")...")
                    AppGroupsService.shared.storeTLSPaymentResponse(success: true, txid: response.txid, error: nil)
                } else {
                    print("❌ ZeroaApp: TLS payment failed: \(response.error ?? "unknown error")")
                    AppGroupsService.shared.storeTLSPaymentResponse(success: false, txid: nil, error: response.error)
                }
                AppGroupsService.shared.clearTLSPaymentRequest()
            }
        }
    }
    
    private func headlessApproveLASKO(request: LASKOAuthRequest) async {
        do {
            print("✍️ Zeroa: Creating session and signature for LASKO headlessly…")
            let session = try await authService.createLASKOAuthSession(permissions: request.permissions)
            authService.sendAuthResponseToLASKO(session)
            print("✅ Zeroa: Auth response written to App Groups for LASKO")
        } catch {
            print("❌ Zeroa: Failed to create/send LASKO auth response: \(error)")
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "zeroa" else { return }
        if url.host == "backup" {
            print("🔗 Zeroa: Opening seed security from zeroa://backup")
            AppGroupsService.shared.setPendingOpenSeedSecurity(true)
            NotificationCenter.default.post(name: .zeroaOpenSeedSecurity, object: nil)
            return
        }
        handleLASKORequest(url)
    }

    private func handleLASKORequest(_ url: URL) {
        print("🔗 Received URL scheme request: \(url)")
        
        // Custom scheme only: zeroa://auth
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard url.scheme == "zeroa", url.host == "auth" else {
            print("❌ Invalid URL for LASKO request: \(url)")
            return
        }
        
        // Extract parameters
        let queryItems = components?.queryItems ?? []
        
        var requestData: [String: String] = [:]
        for item in queryItems {
            requestData[item.name] = item.value
        }
        
        // Extract LASKO's request
        let appName = requestData["app"] ?? "LASKO"
        let appId = requestData["appId"] ?? "com.telestai.LASKO"
        let permissions = requestData["permissions"]?.components(separatedBy: ",") ?? ["post", "read"]
        let callbackURL = requestData["callback"] ?? "lasko://auth/callback"
        let username = requestData["username"]
        
        print("📥 Processing LASKO request via URL scheme: \(appName)")
        
        // Create auth request object
        let authRequest = LASKOAuthRequest(
            appName: appName,
            appId: appId,
            permissions: permissions,
            callbackURL: callbackURL,
            username: username,
            nonce: requestData["nonce"]
        )
        
        // ALWAYS show manual approval - NEVER auto-process
        if authManager.isAuthenticated {
            print("✅ Zeroa is logged in - showing authentication UI")
            laskoAuthRequest = authRequest
            showingLASKOAuth = true
        } else {
            print("❌ Zeroa is not logged in - cannot authenticate LASKO")
        }
    }
}

// MARK: - Authentication Manager
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    
    init() {
        checkAuthenticationStatus()
    }
    
    func checkAuthenticationStatus() {
        print("🔍 Checking authentication status...")
        isLoading = true
        
        // CRITICAL: Only auto-login if saved address matches the last address that was logged in with
        guard let savedAddress = WalletService.shared.loadAddress(),
              let lastLoggedInAddress = WalletService.shared.getLastLoggedInAddress(),
              savedAddress == lastLoggedInAddress else {
            print("❌ Auto-login blocked: saved address doesn't match last logged in address")
            print("   Saved: \(WalletService.shared.loadAddress() ?? "nil")")
            print("   Last logged in: \(WalletService.shared.getLastLoggedInAddress() ?? "nil")")
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.isLoading = false
            }
            return
        }
        
        print("📋 Found saved address: \(savedAddress)")
        print("✅ Saved address matches last logged in address")
        
        if let savedMnemonic = WalletService.shared.keychain.read(key: "wallet_mnemonic") {
            print("🔑 Found saved mnemonic in keychain")
            
            // CRITICAL: Always pass the saved address as expectedAddress to prevent wrong derivation
            WalletService.shared.importMnemonic(savedMnemonic, expectedAddress: savedAddress) { success, derivedAddress in
                DispatchQueue.main.async {
                    print("🔍 Mnemonic import result: success=\(success), derivedAddress=\(derivedAddress ?? "nil")")
                    print("🔍 Address comparison: saved=\(savedAddress), derived=\(derivedAddress ?? "nil"), match=\(savedAddress == (derivedAddress ?? ""))")
                    
                    self.isAuthenticated = success && derivedAddress == savedAddress
                    if !self.isAuthenticated {
                        print("❌ Authentication failed: address mismatch or import failed")
                    } else {
                        // Set profile to active when authentication succeeds
                        AppGroupsService.shared.setProfileActive(true)
                        print("✅ Profile marked as active")
                    }
                    print("✅ Authentication status set to: \(self.isAuthenticated)")
                    self.isLoading = false
                }
            }
        } else {
            print("❌ No mnemonic found in keychain")
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.isLoading = false
            }
        }
    }
    
    func signIn(address: String, mnemonic: String, completion: @escaping (Bool, String?) -> Void) {
        isLoading = true
        
        WalletService.shared.importMnemonic(mnemonic, expectedAddress: address) { success, derivedAddress in
            DispatchQueue.main.async {
                if success && derivedAddress == address {
                    self.isAuthenticated = true
                    // Set profile to active when sign in succeeds
                    AppGroupsService.shared.setProfileActive(true)
                    print("✅ Profile marked as active after sign in")
                    completion(true, nil)
                } else {
                    completion(false, "Invalid address or mnemonic")
                }
                self.isLoading = false
            }
        }
    }
    
    func signUp(address: String, mnemonic: String, completion: @escaping (Bool, String?) -> Void) {
        isLoading = true
        
        // For sign up, we'll use the provided mnemonic directly
        WalletService.shared.importMnemonic(mnemonic, expectedAddress: address) { success, derivedAddress in
            DispatchQueue.main.async {
                if success && derivedAddress == address {
                    self.isAuthenticated = true
                    // Set profile to active when sign in succeeds
                    AppGroupsService.shared.setProfileActive(true)
                    print("✅ Profile marked as active after sign in")
                    completion(true, nil)
                } else {
                    completion(false, "Invalid address or mnemonic")
                }
                self.isLoading = false
            }
        }
    }
    
    func signOut() {
        isAuthenticated = false
        // Set profile to inactive when signing out
        AppGroupsService.shared.setProfileActive(false)
        // Clear saved credentials
        WalletService.shared.keychain.delete(key: "wallet_mnemonic")
        UserDefaults.standard.removeObject(forKey: "wallet_address")
    }
}
