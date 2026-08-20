import Foundation

@MainActor
final class HaloService: ObservableObject {
    static let shared = HaloService()

    @Published var isAuthenticated: Bool = false
    @Published var tokenExp: Int64 = 0

    private let api = HaloAPIService.shared
    private let wallet = WalletService.shared
    private let appGroups = AppGroupsService.shared

    func ensureToken(bundleId: String = "com.tls.Zeroa") async {
        let profileActive = appGroups.isProfileActive()
        guard profileActive else {
            print("❌ HaloService: Account marked inactive")
            return
        }
        
        guard let address = wallet.loadAddress() else {
            print("❌ HaloService: No TLS address loaded")
            return
        }
        
        let now = Int64(Date().timeIntervalSince1970)
        if let (_, exp) = api.storedToken() {
            let timeUntilExp = exp - now
            if timeUntilExp > 60 {
                self.isAuthenticated = true
                self.tokenExp = exp
                return
            }
        }
        
        do {
            let challenge = try await api.requestChallenge(address: address, bundleId: bundleId)
            // Build canonical per server: LASKO|<nonce>|<ttlSeconds>|<bundleId>
            let canonical = "LASKO|\(challenge.nonce)|\(challenge.ttlSeconds)|\(bundleId)"
            
            guard let signature = CryptoService.shared.signMessageBase64(canonical, keychain: wallet.keychain) else {
                print("❌ HaloService: Failed to create signature")
                throw URLError(.cannotCreateFile)
            }
            
            let pubHex = CryptoService.shared.getCompressedPublicKeyHex(keychain: wallet.keychain) ?? ""
            
            let verified = try await api.verify(address: address, bundleId: bundleId, nonce: challenge.nonce, signature: signature, pubkeyCompressedHex: pubHex)
            let expSeconds: Int64 = {
                if let e = verified.exp { return e }
                if let secs = verified.expiresIn { return Int64(Date().timeIntervalSince1970) + Int64(secs) }
                return Int64(Date().timeIntervalSince1970) + 600
            }()
            
            api.storeToken(verified.token, exp: expSeconds)
            self.isAuthenticated = true
            self.tokenExp = expSeconds
        } catch {
            self.isAuthenticated = false
            self.tokenExp = 0
            print("❌ HaloService: Token ensure failed - \(error.localizedDescription)")
        }
    }
    
    func handleAccountActiveChange(_ isActive: Bool) async {
        appGroups.setProfileActive(isActive)
        if isActive {
            await ensureToken()
        } else {
            api.clearToken()
            isAuthenticated = false
            tokenExp = 0
        }
        NotificationCenter.default.post(
            name: .zeroaAccountActivationChanged,
            object: nil,
            userInfo: ["isActive": isActive]
        )
    }
}


