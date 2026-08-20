import Foundation
import UIKit

class AppGroupsService {
    static let shared = AppGroupsService()
    
    // App Group identifier - both apps will use this
    private let appGroupIdentifier = "group.com.tls.zeroa-lasko"
    private let profileAccountActiveKey = "profile_account_active"
    let sharedDefaults: UserDefaults?
    
    init() {
        sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
    }
    
    // MARK: - Shared Addresses
    func getTLSAddress() -> String? {
        sharedDefaults?.synchronize()
        return sharedDefaults?.string(forKey: "tls_wallet_address")
    }

    // MARK: - Profile Sync
    private func scopedProfileKey(_ base: String, tlsAddress: String?) -> String {
        let resolvedTLS = (tlsAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? tlsAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
            : getTLSAddress()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tls = resolvedTLS, !tls.isEmpty else { return base }
        return "\(base)_\(tls)"
    }

    func getProfileDisplayName(for tlsAddress: String? = nil) -> String? {
        sharedDefaults?.synchronize()
        migrateLegacyGlobalsIfNeeded(tlsAddress: tlsAddress)
        let scopedKey = scopedProfileKey("profile_display_name", tlsAddress: tlsAddress)
        guard scopedKey != "profile_display_name" else { return nil }
        if let value = sharedDefaults?.string(forKey: scopedKey), !value.isEmpty {
            return value
        }
        return nil
    }
    
    func getProfileImage(for tlsAddress: String? = nil) -> UIImage? {
        sharedDefaults?.synchronize()
        migrateLegacyGlobalsIfNeeded(tlsAddress: tlsAddress)
        let scopedKey = scopedProfileKey("profile_image_data", tlsAddress: tlsAddress)
        guard scopedKey != "profile_image_data" else { return nil }
        if let data = sharedDefaults?.data(forKey: scopedKey) {
            return UIImage(data: data)
        }
        return nil
    }

    /// Copy leftover unscoped name/photo onto this wallet, then drop the shared slot.
    func migrateLegacyGlobalsIfNeeded(tlsAddress: String? = nil) {
        let tls = (tlsAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? tlsAddress!.trimmingCharacters(in: .whitespacesAndNewlines)
            : getTLSAddress()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tls, !tls.isEmpty, let defaults = sharedDefaults else { return }

        let scopedNameKey = "profile_display_name_\(tls)"
        let scopedImageKey = "profile_image_data_\(tls)"
        if (defaults.string(forKey: scopedNameKey) ?? "").isEmpty,
           let globalName = defaults.string(forKey: "profile_display_name"),
           !globalName.isEmpty {
            defaults.set(globalName, forKey: scopedNameKey)
        }
        if defaults.data(forKey: scopedImageKey) == nil,
           let globalImage = defaults.data(forKey: "profile_image_data") {
            defaults.set(globalImage, forKey: scopedImageKey)
        }
        // Keep globals populated so Zeroa UI (which also reads them) stays in sync.
        defaults.synchronize()
    }

    func clearLegacyGlobalProfileKeys() {
        migrateLegacyGlobalsIfNeeded()
    }

    // MARK: - LASKO Authentication Request
    
    func storeLASKOAuthRequest(_ request: LASKOAuthRequest) {
        let nonce = UUID().uuidString
        let issuedAt = Date().timeIntervalSince1970
        let expiresAt = issuedAt + 300
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
        
        // Write to App Groups (write full dict first, then nonce/timestamp)
        sharedDefaults?.removeObject(forKey: "lasko_auth_response")
        sharedDefaults?.removeObject(forKey: "lasko_auth_in_flight_nonce")
        sharedDefaults?.removeObject(forKey: "lasko_auth_last_processed_nonce")
        sharedDefaults?.set(requestData, forKey: "lasko_auth_request")
        sharedDefaults?.set(nonce, forKey: "lasko_auth_request_nonce")
        sharedDefaults?.set(issuedAt, forKey: "lasko_auth_request_timestamp")
        sharedDefaults?.synchronize()
        
        // No file fallback in headless mode
    }
    
    func getLASKOAuthRequest() -> LASKOAuthRequest? {
        // First try App Groups
        if let defaults = sharedDefaults {
            defaults.synchronize()
        }
        if let requestData = sharedDefaults?.dictionary(forKey: "lasko_auth_request") {
            guard let appName = requestData["appName"] as? String,
                  let appId = requestData["appId"] as? String,
                  let permissions = requestData["permissions"] as? [String],
                  let callbackURL = requestData["callbackURL"] as? String else {
                return nil
            }
            
            // whitelist callback
            guard isAllowedCallback(callbackURL) else {
                return nil
            }
            // TTL
            let now = Date().timeIntervalSince1970
            if let exp = requestData["expiresAt"] as? Double, now > exp {
                clearAuthRequest()
                return nil
            }

            return LASKOAuthRequest(
                appName: appName,
                appId: appId,
                permissions: permissions,
                callbackURL: callbackURL,
                username: requestData["username"] as? String,
                nonce: requestData["nonce"] as? String
            )
        }
        
        return nil
    }
    
    // MARK: - LASKO Authentication Response
    
    func storeLASKOAuthResponse(_ session: LASKOAuthSession) {
        let responseData: [String: Any] = [
            "tlsAddress": session.tlsAddress,
            "sessionToken": session.sessionToken,
            "signature": session.signature,
            "timestamp": session.timestamp,
            "expiresAt": session.expiresAt,
            "permissions": session.permissions,
            "responseTimestamp": Date().timeIntervalSince1970
        ]
        
        // Write to App Groups
        sharedDefaults?.set(responseData, forKey: "lasko_auth_response")
        sharedDefaults?.synchronize()
        
        // No file fallback in headless mode
    }
    
    func getLASKOAuthResponse() -> LASKOAuthSession? {
        // CRITICAL: Force refresh by creating a new UserDefaults instance
        // This ensures we get the latest data from the shared container
        let freshDefaults = UserDefaults(suiteName: appGroupIdentifier)
        freshDefaults?.synchronize()
        
        // Small delay to allow cross-process sync
        Thread.sleep(forTimeInterval: 0.05)
        
        print("🔍 AppGroupsService.getLASKOAuthResponse: Checking for 'lasko_auth_response' key...")
        if let responseData = freshDefaults?.dictionary(forKey: "lasko_auth_response") ?? sharedDefaults?.dictionary(forKey: "lasko_auth_response") {
            print("✅ AppGroupsService.getLASKOAuthResponse: Found response!")
            guard let tlsAddress = responseData["tlsAddress"] as? String,
                  let sessionToken = responseData["sessionToken"] as? String,
                  let signature = responseData["signature"] as? String,
                  let timestamp = responseData["timestamp"] as? Int64,
                  let expiresAt = responseData["expiresAt"] as? Int64,
                  let permissions = responseData["permissions"] as? [String] else {
                print("❌ AppGroupsService.getLASKOAuthResponse: Response data incomplete or invalid")
                return nil
            }
            // TTL enforcement for responses
            let now = Int64(Date().timeIntervalSince1970)
            if now > expiresAt {
                print("❌ AppGroupsService.getLASKOAuthResponse: Response expired (now=\(now), expiresAt=\(expiresAt))")
                clearAuthResponse()
                return nil
            }
            
            print("✅ AppGroupsService.getLASKOAuthResponse: Returning valid session for \(tlsAddress)")
            return LASKOAuthSession(
                tlsAddress: tlsAddress,
                sessionToken: sessionToken,
                signature: signature,
                canonicalMessage: responseData["canonicalMessage"] as? String,
                signatureBase64: responseData["signatureBase64"] as? String,
                pubkeyCompressedHex: responseData["pubkeyCompressedHex"] as? String,
                requestNonce: responseData["requestNonce"] as? String,
                timestamp: timestamp,
                expiresAt: expiresAt,
                permissions: permissions
            )
        } else {
            // Debug: Check what keys exist in App Groups
            if let allKeys = freshDefaults?.dictionaryRepresentation().keys {
                let authKeys = allKeys.filter { $0.contains("lasko") || $0.contains("auth") || $0.contains("response") }
                print("🔍 AppGroupsService.getLASKOAuthResponse: Key not found. Related keys in App Groups: \(Array(authKeys))")
            } else {
                print("❌ AppGroupsService.getLASKOAuthResponse: freshDefaults is nil!")
            }
        }
        
        return nil
    }
    
    // MARK: - Cleanup
    
    func clearAuthRequest() {
        sharedDefaults?.removeObject(forKey: "lasko_auth_request")
        sharedDefaults?.removeObject(forKey: "lasko_auth_request_nonce")
        sharedDefaults?.removeObject(forKey: "lasko_auth_request_timestamp")
        sharedDefaults?.synchronize()
    }
    
    func clearAuthResponse() {
        sharedDefaults?.removeObject(forKey: "lasko_auth_response")
        sharedDefaults?.synchronize()
    }
    
    func clearAll() {
        clearAuthRequest()
        clearAuthResponse()
    }
    
    func clearHaloToken() {
        sharedDefaults?.removeObject(forKey: "halo_access_token")
        sharedDefaults?.removeObject(forKey: "haloAccessToken")
        sharedDefaults?.removeObject(forKey: "halo_token_expires_at")
        sharedDefaults?.synchronize()
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
        guard isAllowedCallback(callbackURL) else { return nil }
        let now = Date().timeIntervalSince1970
        if let exp = data["expiresAt"] as? Double, now > exp { clearAuthRequest(); return nil }

        return LASKOAuthRequest(
            appName: appName,
            appId: appId,
            permissions: permissions,
            callbackURL: callbackURL,
            username: data["username"] as? String,
            nonce: data["nonce"] as? String
        )
    }

    private func isAllowedCallback(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme?.lowercased() == "lasko" && url.host?.lowercased() == "auth" && url.path == "/callback"
    }
    
    // MARK: - Status Checking
    
    func hasPendingAuthRequest() -> Bool {
        let appGroupsHasRequest = sharedDefaults?.object(forKey: "lasko_auth_request") != nil
        print("🔍 LASKO: Auth request check - App Groups: \(appGroupsHasRequest)")
        return appGroupsHasRequest
    }
    
    func hasAuthResponse() -> Bool {
        let appGroupsHasResponse = sharedDefaults?.object(forKey: "lasko_auth_response") != nil
        print("🔍 LASKO: Auth response check - App Groups: \(appGroupsHasResponse)")
        return appGroupsHasResponse
    }
    
    func isProfileActive() -> Bool {
        guard let defaults = sharedDefaults else { return true }
        if defaults.object(forKey: profileAccountActiveKey) == nil {
            return true
        }
        return defaults.bool(forKey: profileAccountActiveKey)
    }
    
    func setProfileActive(_ isActive: Bool) {
        sharedDefaults?.set(isActive, forKey: profileAccountActiveKey)
        sharedDefaults?.synchronize()
    }
} 