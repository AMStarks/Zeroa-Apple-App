import Foundation
import CoreFoundation

class AppGroupsService {
    static let shared = AppGroupsService()
    
    // App Group identifier - both apps will use this
    private let appGroupIdentifier = "group.com.tls.zeroa-lasko"
    private let profileAccountActiveKey = "profile_account_active"
    let sharedDefaults: UserDefaults?
    
    init() {
        sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
    }
    
    // MARK: - LASKO Authentication Request
    
    func storeLASKOAuthRequest(_ request: LASKOAuthRequest) {
        // Generate a nonce for CSRF mitigation and set expiry
        let nonce = UUID().uuidString
        let issuedAt = Date().timeIntervalSince1970
        let expiresAt = issuedAt + 120 // 2 minutes
        var requestData: [String: Any] = [
            "appName": request.appName,
            "appId": request.appId,
            "permissions": request.permissions,
            "callbackURL": request.callbackURL,
            "timestamp": issuedAt,
            "nonce": nonce,
            "expiresAt": expiresAt
        ]
        if let username = request.username { requestData["username"] = username }
        
        print("🔍 LASKO: Storing auth request to App Groups with nonce: \(nonce)")
        
        // Write to App Groups
        sharedDefaults?.set(requestData, forKey: "lasko_auth_request")
        // CRITICAL: Force immediate synchronization to ensure Zeroa can read it
        let syncResult = sharedDefaults?.synchronize() ?? false
        print("🔍 LASKO: App Groups sync result: \(syncResult)")
        
        // Also write individual keys as fallback
        sharedDefaults?.set(nonce, forKey: "lasko_auth_request_nonce")
        sharedDefaults?.set(issuedAt, forKey: "lasko_auth_request_timestamp")
        sharedDefaults?.synchronize()
        
        print("✅ LASKO: Auth request stored in App Groups")
    }
    
    func getLASKOAuthRequest() -> LASKOAuthRequest? {
        // Recreate suite each read to avoid stale cross-process cache
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        // CRITICAL: Force synchronization before reading to ensure we get latest data
        defaults?.synchronize()
        
        // Add small delay to ensure cross-process sync completes
        // This is necessary because UserDefaults synchronization is asynchronous
        Thread.sleep(forTimeInterval: 0.05)
        
        // Try full request dictionary first
        if let requestData = defaults?.dictionary(forKey: "lasko_auth_request") {
            print("🔍 Zeroa: Found LASKO auth request data in App Groups")
            guard let appName = requestData["appName"] as? String,
                  let appId = requestData["appId"] as? String,
                  let permissions = requestData["permissions"] as? [String],
                  let callbackURL = requestData["callbackURL"] as? String else {
                return nil
            }

            // Basic callback whitelist: only allow lasko://auth/callback
            guard isAllowedCallback(callbackURL) else {
                return nil
            }

            if let expiresAt = requestData["expiresAt"] as? Double {
                let now = Date().timeIntervalSince1970
                guard now <= expiresAt else {
                    clearAuthRequest()
                    return nil
                }
            }

            guard let nonce = requestData["nonce"] as? String else {
                clearAuthRequest()
                return nil
            }

            return LASKOAuthRequest(
                appName: appName,
                appId: appId,
                permissions: permissions,
                callbackURL: callbackURL,
                username: requestData["username"] as? String,
                nonce: nonce
            )
        }
        
        // Fallback: reconstruct from nonce/timestamp keys if present
        if let nonce = defaults?.string(forKey: "lasko_auth_request_nonce") {
            let appName = "LASKO"
            let appId = "com.telestai.LASKO"
            let permissions = ["post", "read"]
            let callbackURL = "lasko://auth/callback"
            guard isAllowedCallback(callbackURL) else {
                return nil
            }
            if let issued = defaults?.double(forKey: "lasko_auth_request_timestamp"), issued > 0 {
                let expiresAt = issued + 120
                if Date().timeIntervalSince1970 > expiresAt {
                    clearAuthRequest()
                    return nil
                }
            }
            return LASKOAuthRequest(
                appName: appName,
                appId: appId,
                permissions: permissions,
                callbackURL: callbackURL,
                username: nil,
                nonce: nonce
            )
        }
        
        return nil
    }
    
    // MARK: - LASKO Authentication Response
    
    func storeLASKOAuthResponse(_ session: LASKOAuthSession) {
        var responseData: [String: Any] = [
            "tlsAddress": session.tlsAddress,
            "sessionToken": session.sessionToken,
            "signature": session.signature,
            "timestamp": session.timestamp,
            "expiresAt": session.expiresAt,
            "permissions": session.permissions,
            "responseTimestamp": Date().timeIntervalSince1970
        ]
        // Also persist compressed public key for reuse by LASKO when posting
        if let pubHex = CryptoService.shared.getCompressedPublicKeyHex(keychain: WalletService.shared.keychain) {
            responseData["zeroa_pubkey_compressed_hex"] = pubHex
            sharedDefaults?.set(pubHex, forKey: "zeroa_pubkey_compressed_hex")
        }
        
        // Write to App Groups
        sharedDefaults?.set(responseData, forKey: "lasko_auth_response")
        sharedDefaults?.synchronize()
        if let defaults = sharedDefaults, defaults.object(forKey: "lasko_auth_request") != nil {
            defaults.removeObject(forKey: "lasko_auth_request")
            defaults.synchronize()
        }
        
        // CRITICAL: Notify LASKO that auth response is ready (bidirectional notification)
        let notificationName = CFNotificationName("com.telestai.zeroa.auth.response" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        print("📢 Zeroa: Sent Darwin notification to LASKO (auth response ready)")
        
        // No file fallback in headless mode
    }
    
    func getLASKOAuthResponse() -> LASKOAuthSession? {
        // First try App Groups
        if let responseData = sharedDefaults?.dictionary(forKey: "lasko_auth_response") {
            guard let tlsAddress = responseData["tlsAddress"] as? String,
                  let sessionToken = responseData["sessionToken"] as? String,
                  let signature = responseData["signature"] as? String,
                  let timestamp = responseData["timestamp"] as? Int64,
                  let expiresAt = responseData["expiresAt"] as? Int64,
                  let permissions = responseData["permissions"] as? [String] else {
                return nil
            }
            // TTL enforcement for responses: ignore and clear expired entries
            let now = Int64(Date().timeIntervalSince1970)
            if now > expiresAt {
                clearAuthResponse()
                return nil
            }
            
            return LASKOAuthSession(
                tlsAddress: tlsAddress,
                sessionToken: sessionToken,
                signature: signature,
                timestamp: timestamp,
                expiresAt: expiresAt,
                permissions: permissions
            )
        }
        
        return nil
    }

    // MARK: - Post Sign Handshake

    func getPostSignRequest() -> [String: Any]? {
        // CRITICAL: Force refresh by creating a new UserDefaults instance
        // This ensures we get the latest data from the shared container
        let freshDefaults = UserDefaults(suiteName: appGroupIdentifier)
        freshDefaults?.synchronize()
        
        // Small delay to allow cross-process sync
        Thread.sleep(forTimeInterval: 0.05)
        
        if let req = freshDefaults?.dictionary(forKey: "lasko_post_sign_request") {
            return req
        }
        return nil
    }

    func storePostSignResponse(signatureBase64: String, pubkeyCompressedHex: String, timestampMs: Int64) {
        var data: [String: Any] = [
            "signatureBase64": signatureBase64,
            "pubkeyCompressedHex": pubkeyCompressedHex,
            "timestamp": timestampMs,
            "responseTimestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let existingPub = sharedDefaults?.string(forKey: "zeroa_pubkey_compressed_hex"), existingPub.count == 66 {
            data["pubkeyCompressedHex"] = existingPub
        }
        sharedDefaults?.set(data, forKey: "lasko_post_sign_response")
        sharedDefaults?.synchronize()
        
        // CRITICAL: Notify LASKO that signature is ready (bidirectional notification)
        let notificationName = CFNotificationName("com.telestai.zeroa.post.sign.response" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }

    func clearPostSignRequest() {
        sharedDefaults?.removeObject(forKey: "lasko_post_sign_request")
    }
    
    // MARK: - TLS Payment Request (LASKO → Zeroa)
    func getTLSPaymentRequest() -> [String: Any]? {
        let freshDefaults = UserDefaults(suiteName: appGroupIdentifier)
        freshDefaults?.synchronize()
        Thread.sleep(forTimeInterval: 0.05)
        
        if let req = freshDefaults?.dictionary(forKey: "lasko_tls_payment_request") {
            return req
        }
        return nil
    }
    
    func storeTLSPaymentResponse(success: Bool, txid: String?, error: String?) {
        let data: [String: Any] = [
            "success": success,
            "txid": txid ?? "",
            "error": error ?? "",
            "responseTimestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        sharedDefaults?.set(data, forKey: "lasko_tls_payment_response")
        sharedDefaults?.synchronize()
        
        // Notify LASKO that payment is complete
        let notificationName = CFNotificationName("com.telestai.zeroa.tls.payment.response" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
        print("📢 Zeroa: Sent Darwin notification to LASKO (TLS payment complete)")
    }
    
    func clearTLSPaymentRequest() {
        sharedDefaults?.removeObject(forKey: "lasko_tls_payment_request")
    }

    func clearPostSignResponse() {
        sharedDefaults?.removeObject(forKey: "lasko_post_sign_response")
    }

    // MARK: - Token Refresh Flags
    func hasTokenRefreshRequest() -> Bool {
        // CRITICAL: Force refresh by creating a new UserDefaults instance
        // This ensures we get the latest data from the shared container
        let freshDefaults = UserDefaults(suiteName: appGroupIdentifier)
        freshDefaults?.synchronize()
        
        // Small delay to allow cross-process sync
        Thread.sleep(forTimeInterval: 0.05)
        
        if freshDefaults?.object(forKey: "halo_token_refresh_request") ?? sharedDefaults?.object(forKey: "halo_token_refresh_request") != nil {
            return true
        }
        return false
    }

    func clearTokenRefreshRequest() {
        sharedDefaults?.removeObject(forKey: "halo_token_refresh_request")
        sharedDefaults?.synchronize()
    }

    func clearHaloToken() {
        sharedDefaults?.removeObject(forKey: "halo_access_token")
        sharedDefaults?.removeObject(forKey: "haloAccessToken")
        sharedDefaults?.removeObject(forKey: "halo_token_expires_at")
        sharedDefaults?.synchronize()
    }
    
    func markTokenRefreshed() {
        sharedDefaults?.set(Int64(Date().timeIntervalSince1970 * 1000), forKey: "halo_token_refreshed_at")
        sharedDefaults?.synchronize()
    }
    
    // MARK: - Cleanup
    
    func clearAuthRequest() {
        sharedDefaults?.removeObject(forKey: "lasko_auth_request")
    }
    
    func clearAuthResponse() {
        sharedDefaults?.removeObject(forKey: "lasko_auth_response")
    }
    
    func clearAll() {
        clearAuthRequest()
        clearAuthResponse()
    }
    
    // MARK: - File-Based Communication
    
    private func writeToSharedFile(key: String, data: [String: Any]) -> Bool {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        
        let sharedDirectory = documentsPath.appendingPathComponent("Shared")
        
        // Create shared directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        } catch {
            return false
        }
        
        let fileURL = sharedDirectory.appendingPathComponent("\(key).json")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
            try jsonData.write(to: fileURL)
            return true
        } catch {
            return false
        }
    }
    
    private func readFromSharedFile(key: String) -> [String: Any]? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let sharedDirectory = documentsPath.appendingPathComponent("Shared")
        let fileURL = sharedDirectory.appendingPathComponent("\(key).json")
        
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let data = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            return data
        } catch {
            return nil
        }
    }
    
    private func parseAuthRequest(_ data: [String: Any]) -> LASKOAuthRequest? {
        guard let appName = data["appName"] as? String,
              let appId = data["appId"] as? String,
              let permissions = data["permissions"] as? [String],
              let callbackURL = data["callbackURL"] as? String else {
            return nil
        }

        guard isAllowedCallback(callbackURL) else {
            return nil
        }

        // TTL check on file data as well
        let now = Date().timeIntervalSince1970
        if let exp = data["expiresAt"] as? Double, now > exp {
            clearAuthRequest()
            return nil
        }
        
        return LASKOAuthRequest(
            appName: appName,
            appId: appId,
            permissions: permissions,
            callbackURL: callbackURL,
            username: data["username"] as? String,
            nonce: data["nonce"] as? String
        )
    }

    // Allowlist only lasko://auth/callback
    private func isAllowedCallback(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        if url.scheme?.lowercased() == "lasko" && url.host?.lowercased() == "auth" && url.path == "/callback" {
            return true
        }
        return false
    }
    
    // MARK: - Status Checking
    
    func hasPendingAuthRequest() -> Bool {
        let appGroupsHasRequest = sharedDefaults?.object(forKey: "lasko_auth_request") != nil
        print("🔍 Zeroa: Auth request check - App Groups: \(appGroupsHasRequest)")
        return appGroupsHasRequest
    }
    
    func hasAuthResponse() -> Bool {
        sharedDefaults?.object(forKey: "lasko_auth_response") != nil
    }

    // MARK: - TLS Address Storage
    func storeTLSAddress(_ address: String) {
        sharedDefaults?.set(address, forKey: "tls_wallet_address")
        sharedDefaults?.synchronize()
    }
    
    func getTLSAddress() -> String? {
        return sharedDefaults?.string(forKey: "tls_wallet_address")
    }

    // MARK: - Profile display name (shared with Switchboard)
    private let profileDisplayNameKey = "profile_display_name"

    func profileDisplayName(tls: String?) -> String {
        let defaults = sharedDefaults ?? .standard
        defaults.synchronize()
        let trimmedTLS = tls?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTLS.isEmpty,
           let scoped = defaults.string(forKey: "\(profileDisplayNameKey)_\(trimmedTLS)"),
           !scoped.isEmpty {
            return scoped
        }
        if let global = defaults.string(forKey: profileDisplayNameKey), !global.isEmpty {
            return global
        }
        return ""
    }

    func setProfileDisplayName(_ name: String, tls: String?) {
        let defaults = sharedDefaults ?? .standard
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTLS = tls?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existing = profileDisplayName(tls: trimmedTLS.isEmpty ? nil : trimmedTLS)
        if existing == trimmed { return }
        defaults.set(trimmed, forKey: profileDisplayNameKey)
        if !trimmedTLS.isEmpty {
            defaults.set(trimmed, forKey: "\(profileDisplayNameKey)_\(trimmedTLS)")
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: .zeroaDisplayNameDidChange, object: trimmed)
    }

    // MARK: - Flux Address Storage
    func storeFluxAddress(_ address: String) {
        sharedDefaults?.set(address, forKey: "flux_wallet_address")
        sharedDefaults?.synchronize()
    }
    
    func getFluxAddress() -> String? {
        sharedDefaults?.string(forKey: "flux_wallet_address")
    }
    
    // MARK: - Account Activation
    func isProfileActive() -> Bool {
        guard let defaults = sharedDefaults else {
            return true
        }
        defaults.synchronize() // Ensure we have latest value
        // Default to true (active) if key doesn't exist - only inactive if explicitly set to false
        if defaults.object(forKey: profileAccountActiveKey) == nil {
            return true
        }
        return defaults.bool(forKey: profileAccountActiveKey)
    }
    
    func setProfileActive(_ isActive: Bool) {
        sharedDefaults?.set(isActive, forKey: profileAccountActiveKey)
        sharedDefaults?.synchronize()
    }

    private let openSeedSecurityPendingKey = "zeroa_open_seed_security_pending"

    func setPendingOpenSeedSecurity(_ pending: Bool) {
        sharedDefaults?.set(pending, forKey: openSeedSecurityPendingKey)
        sharedDefaults?.synchronize()
    }

    func consumePendingOpenSeedSecurity() -> Bool {
        guard sharedDefaults?.bool(forKey: openSeedSecurityPendingKey) == true else { return false }
        sharedDefaults?.set(false, forKey: openSeedSecurityPendingKey)
        sharedDefaults?.synchronize()
        return true
    }
}