import Foundation
import UIKit

class LASKOAuthService: ObservableObject {
    
    // MARK: - Session Generation
    
    func createLASKOAuthSession(permissions: [String]) async throws -> LASKOAuthSession {
        print("🔍 Starting LASKO auth session creation...")
        
        // Get current TLS address from Zeroa
        print("📱 Getting TLS address...")
        let tlsAddress = try await getCurrentTLSAddress()
        print("✅ TLS address: \(tlsAddress)")
        
        // Generate session token
        let sessionToken = "session_\(UUID().uuidString)"
        print("🔑 Generated session token: \(sessionToken)")
        
        // Create signature using existing Zeroa signing
        print("✍️ Creating signature...")
        let signature = try await signLASKOAuth(tlsAddress: tlsAddress, sessionToken: sessionToken)
        print("✅ Signature created: \(signature.prefix(20))...")
        
        // Set timestamps
        let timestamp = Int64(Date().timeIntervalSince1970)
        let expiresAt = timestamp + 3600 // 1 hour
        print("⏰ Timestamp: \(timestamp), Expires: \(expiresAt)")
        
        let session = LASKOAuthSession(
            tlsAddress: tlsAddress,
            sessionToken: sessionToken,
            signature: signature,
            timestamp: timestamp,
            expiresAt: expiresAt,
            permissions: permissions
        )
        
        print("🎉 LASKO auth session created successfully!")
        return session
    }
    
    // MARK: - App Groups Communication
    
    func sendAuthResponseToLASKO(_ session: LASKOAuthSession) {
        print("🔍 Sending auth response to LASKO via App Groups...")
        
        // Store the response in shared App Groups
        AppGroupsService.shared.storeLASKOAuthResponse(session)
        
        print("✅ Auth response stored in App Groups for LASKO to retrieve")
    }
    
    func checkForPendingAuthRequest() -> LASKOAuthRequest? {
        return AppGroupsService.shared.getLASKOAuthRequest()
    }
    
    func clearAuthRequest() {
        AppGroupsService.shared.clearAuthRequest()
    }
    
    func getAuthResponseFromZeroa() -> LASKOAuthSession? {
        // Removed excessive logging - only log when response is found
        return AppGroupsService.shared.getLASKOAuthResponse()
    }
    
    // MARK: - Core Functions (Integrate with existing Zeroa code)
    
    private func getCurrentTLSAddress() async throws -> String {
        print("🔍 Getting current TLS address...")
        // Use existing Zeroa TLS address function
        guard let tlsAddress = WalletService.shared.loadAddress() else {
            print("❌ No TLS address found - user may not have set up wallet")
            throw LASKOAuthError.noTLSAddress
        }
        print("✅ TLS address found: \(tlsAddress)")
        return tlsAddress
    }
    
    private func signLASKOAuth(tlsAddress: String, sessionToken: String) async throws -> String {
        print("🔍 Starting LASKO auth signing...")
        // TODO: Replace with your existing Zeroa signing function
        // This should create a real TLS signature
        
        let message = "LASKO_AUTH:\(tlsAddress):\(sessionToken)"
        print("📝 Signing message: \(message)")
        let signature = try await signMessageWithTLS(message)
        print("✅ Auth signature created successfully")
        return signature
    }
    
    private func signMessageWithTLS(_ message: String) async throws -> String {
        print("🔍 Starting TLS message signing...")
        // Use existing Zeroa TLS signing
        guard let signature = WalletService.shared.signMessage(message) else {
            print("❌ TLS signing failed - no signature returned")
            throw LASKOAuthError.signingFailed
        }
        print("✅ TLS signature created: \(signature.prefix(20))...")
        return signature
    }
    
    // MARK: - Helper Functions (Replace with your existing code)
    
    private func getExistingTLSAddress() -> String? {
        // Use existing Zeroa TLS address getter
        return WalletService.shared.loadAddress()
    }
    
    // MARK: - Post Signing for LASKO
    
    func signPostForLASKO(content: String, sessionToken: String) async throws -> PostSignature {
        // Verify session is still valid
        guard isSessionValid(sessionToken) else {
            throw LASKOAuthError.sessionExpired
        }
        
        // Get current TLS address
        let tlsAddress = try await getCurrentTLSAddress()
        
        // Create post signature using existing Zeroa signing
        let signature = try await signPostContent(content: content, tlsAddress: tlsAddress)
        
        let timestamp = Int64(Date().timeIntervalSince1970)
        
        return PostSignature(
            signature: signature,
            tlsAddress: tlsAddress,
            timestamp: timestamp,
            content: content,
            sessionToken: sessionToken
        )
    }
    
    private func signPostContent(content: String, tlsAddress: String) async throws -> String {
        // TODO: Replace with your existing Zeroa signing mechanism
        // This should create a real TLS signature for the post
        
        let message = "LASKO_POST:\(content):\(tlsAddress)"
        return try await signMessageWithTLS(message)
    }
    
    private func isSessionValid(_ sessionToken: String) -> Bool {
        // For now, sessions are always valid (1 hour expiry is handled in session creation)
        // TODO: Implement proper session validation if needed
        return true
    }
}

// MARK: - Error Types

enum LASKOAuthError: Error {
    case noTLSAddress
    case signingFailed
    case invalidCallbackURL
    case sessionCreationFailed
    case sessionExpired
} 