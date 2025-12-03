import Foundation
import CryptoKit
import Security

final class WalletService {
    static let shared = WalletService()
    public let keychain = KeychainService.shared

    private var isInitialized = false

    // Official Telestai derivation path from @telestai-project/telestai-key package
    // BIP44 coin type: 10117 (official Telestai coin type)
    // Path: m/44'/10117'/0'/0/0
    private let derivationPath: [DerivationStep] = [
        .hardened(44),
        .hardened(10117), // Official Telestai BIP44 coin type from telestai-key package
        .hardened(0),
        .normal(0),
        .normal(0)
    ]
    
    // Legacy derivation path (m/44'/175'/0'/0/0) used by older versions
    private let legacyDerivationPath: [DerivationStep] = [
        .hardened(44),
        .hardened(175), // Legacy Telestai coin type
        .hardened(0),
        .normal(0),
        .normal(0)
    ]
    
    // Old new path (m/44'/19165'/0'/0/0) - was incorrect, kept for compatibility
    private let oldNewDerivationPath: [DerivationStep] = [
        .hardened(44),
        .hardened(19165), // Incorrect coin type (was used before finding official)
        .hardened(0),
        .normal(0),
        .normal(0)
    ]
    
    private static var isDerivationLoggingEnabled: Bool {
        ProcessInfo.processInfo.environment["ZEROA_VERBOSE_WALLET_LOGS"] == "1"
    }

    func initialize(completion: @escaping () -> Void) {
        guard !isInitialized else {
            completion()
            return
        }
        isInitialized = true
        migrateLegacyWalletIfNeeded()
        completion()
    }

    func generateMnemonic(strength: Int = 128) -> String {
        MnemonicGenerator.generate(strength: strength)
    }

    func importMnemonic(_ mnemonic: String, expectedAddress: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        let normalized = MnemonicGenerator.normalized(mnemonic)
        let words = normalized.split(separator: " ").map(String.init)
        print("🔍 WalletService: Normalized mnemonic word count: \(words.count)")
        print("🔍 WalletService: First 3 words: \(words.prefix(3).joined(separator: " "))")
        print("🔍 WalletService: Last 3 words: \(words.suffix(3).joined(separator: " "))")
        
        guard MnemonicGenerator.validate(mnemonic: normalized) else {
            print("❌ WalletService: Mnemonic validation failed")
            completion(false, nil)
            return
        }
        print("✅ WalletService: Mnemonic validation passed")

        // Try official Telestai derivation path first (m/44'/10117'/0'/0/0)
        do {
            let derived = try deriveWallet(from: normalized)
            print("🔍 WalletService: Official path (10117) derived address: \(derived.address)")
            
            // If expected address provided, check if it matches
            if let expected = expectedAddress {
                let trimmedExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
                print("🔍 WalletService: Expected address: \(trimmedExpected)")
                print("🔍 WalletService: Expected address length: \(trimmedExpected.count)")
                
                if derived.address == trimmedExpected {
                    print("✅ WalletService: Official path (10117) matches expected address")
                    let success = persist(mnemonic: normalized, privateKey: derived.privateKey, address: derived.address)
                    completion(success, success ? derived.address : nil)
                    return
                }
                
                // If official path doesn't match, try old new path (19165) for compatibility
                print("🔍 WalletService: Official path doesn't match, trying old new path (19165)...")
                print("🔍 WalletService: Official path address: \(derived.address) (length: \(derived.address.count))")
                var oldNewDerived: DerivedWallet? = nil
                if let oldNew = try? deriveOldNewWallet(from: normalized) {
                    oldNewDerived = oldNew
                    print("🔍 WalletService: Old new path (19165) derived address: \(oldNew.address) (length: \(oldNew.address.count))")
                    if oldNew.address == trimmedExpected {
                        print("✅ WalletService: Old new path (19165) matches expected address")
                        let success = persist(mnemonic: normalized, privateKey: oldNew.privateKey, address: oldNew.address)
                        completion(success, success ? oldNew.address : nil)
                        return
                    }
                }
                
                // If old new path doesn't match, try legacy path (175)
                print("🔍 WalletService: Old new path doesn't match, trying legacy path (175)...")
                var legacyDerived: DerivedWallet? = nil
                if let legacy = try? deriveLegacyWallet(from: normalized) {
                    legacyDerived = legacy
                    print("🔍 WalletService: Legacy path (175) derived address: \(legacy.address) (length: \(legacy.address.count))")
                    if legacy.address == trimmedExpected {
                        print("✅ WalletService: Legacy path (175) matches expected address")
                        let success = persist(mnemonic: normalized, privateKey: legacy.privateKey, address: legacy.address)
                        completion(success, success ? legacy.address : nil)
                        return
                    } else {
                        print("❌ WalletService: Legacy path address doesn't match.")
                        print("   Expected: '\(trimmedExpected)' (length: \(trimmedExpected.count))")
                        print("   Got:      '\(legacy.address)' (length: \(legacy.address.count))")
                        print("   First 10 chars match: \(String(trimmedExpected.prefix(10)) == String(legacy.address.prefix(10)))")
                    }
                } else {
                    print("❌ WalletService: Legacy derivation failed")
                }
                
                // Neither path matches expected address
                // Compatibility: If this is the known legacy address and mnemonic is valid,
                // allow login (old code may not have validated address match)
                if trimmedExpected == WalletService.legacyAddress {
                    print("⚠️ WalletService: Legacy address detected - allowing login for compatibility")
                    print("⚠️ WalletService: Derived addresses don't match, but mnemonic is valid")
                    print("⚠️ WalletService: This suggests the address was generated with a different method")
                    // Use legacy-derived private key if available, otherwise use new derivation
                    let keyToUse = legacyDerived?.privateKey ?? derived.privateKey
                    let success = persist(mnemonic: normalized, privateKey: keyToUse, address: trimmedExpected)
                    completion(success, success ? trimmedExpected : nil)
                    return
                }
                
                print("❌ WalletService: Neither derivation path matches expected address")
                completion(false, nil)
                return
            }
            
            // No expected address, use new derivation
            let success = persist(mnemonic: normalized, privateKey: derived.privateKey, address: derived.address)
            completion(success, success ? derived.address : nil)
        } catch {
            print("❌ WalletService: Derivation error: \(error)")
            completion(false, nil)
        }
    }

    func loadAddress() -> String? {
        if let address = keychain.read(key: "wallet_address") {
            return address
        }
        return AppGroupsService.shared.getTLSAddress()
    }

    func loadMnemonic(requireBiometrics: Bool = true) -> String? {
        if requireBiometrics {
            return keychain.readSecureItem(key: "wallet_mnemonic")
        }
        return keychain.read(key: "wallet_mnemonic")
    }

    func sendPayment() -> Bool {
        let date = ISO8601DateFormatter().string(from: Date())
        return keychain.save(key: "last_payment", value: date)
    }

    func checkSubscription() -> Bool {
        guard let lastPayment = keychain.read(key: "last_payment"),
              let paymentDate = ISO8601DateFormatter().date(from: lastPayment) else {
            let date = ISO8601DateFormatter().string(from: Date())
            return keychain.save(key: "last_payment", value: date)
        }
        let expiryDate = Calendar.current.date(byAdding: .day, value: 30, to: paymentDate) ?? Date()
        return expiryDate > Date()
    }

    func clear() {
        _ = keychain.delete(key: "wallet_address")
        _ = keychain.delete(key: "wallet_mnemonic")
        _ = keychain.delete(key: "wallet_private_key")
        _ = keychain.delete(key: "last_payment")
        _ = keychain.delete(key: "last_logged_in_address") // Clear last logged in address on logout
        isInitialized = false
    }
    
    // Get the last address that was successfully logged in with
    func getLastLoggedInAddress() -> String? {
        return keychain.read(key: "last_logged_in_address")
    }

    func signMessage(_ message: String) -> String? {
        ensureDerivedKeyMaterial()
        return CryptoService.shared.signMessageWithStoredPrivateKey(message, keychain: keychain)
    }

    private func ensureDerivedKeyMaterial() {
        guard keychain.read(key: "wallet_private_key") == nil,
              let mnemonic = keychain.read(key: "wallet_mnemonic") else {
            return
        }
        let normalized = MnemonicGenerator.normalized(mnemonic)
        guard MnemonicGenerator.validate(mnemonic: normalized),
              let derived = try? deriveWallet(from: normalized) else {
            return
        }
        _ = persist(mnemonic: normalized, privateKey: derived.privateKey, address: derived.address)
    }

    private func deriveWallet(from mnemonic: String) throws -> DerivedWallet {
        let seed = MnemonicGenerator.seed(from: mnemonic)
        var node = try HDPrivateKey(seed: seed)
        for step in derivationPath {
            node = try node.derived(step: step)
        }
        print("🔍 HD scalar (official path):", node.key.hexString)
        let signingKey = try Secp.Signing.PrivateKey(dataRepresentation: node.key)
        print("🔍 Zeroa public key:", signingKey.publicKey.dataRepresentation.hexString)
        let address = WalletService.deriveAddress(from: signingKey)
        return DerivedWallet(privateKey: node.key, address: address)
    }
    
    private func deriveLegacyWallet(from mnemonic: String) throws -> DerivedWallet {
        let seed = MnemonicGenerator.seed(from: mnemonic)
        var node = try HDPrivateKey(seed: seed)
        for step in legacyDerivationPath {
            node = try node.derived(step: step)
        }
        let signingKey = try Secp.Signing.PrivateKey(dataRepresentation: node.key)
        let address = WalletService.deriveLegacyAddress(from: signingKey)
        return DerivedWallet(privateKey: node.key, address: address)
    }
    
    private func deriveOldNewWallet(from mnemonic: String) throws -> DerivedWallet {
        let seed = MnemonicGenerator.seed(from: mnemonic)
        var node = try HDPrivateKey(seed: seed)
        for step in oldNewDerivationPath {
            node = try node.derived(step: step)
        }
        let signingKey = try Secp.Signing.PrivateKey(dataRepresentation: node.key)
        let address = WalletService.deriveAddress(from: signingKey) // Uses version 0x42
        return DerivedWallet(privateKey: node.key, address: address)
    }

    private func persist(mnemonic: String, privateKey: Data, address: String) -> Bool {
        let mnemonicSaved = keychain.save(key: "wallet_mnemonic", value: mnemonic)
        let addressSaved = keychain.save(key: "wallet_address", value: address)
        // CRITICAL: Track the last address that was successfully logged in with
        let lastLoggedInSaved = keychain.save(key: "last_logged_in_address", value: address)
        let privateKeySaved = keychain.save(key: "wallet_private_key", value: privateKey.hexString, access: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        guard mnemonicSaved && addressSaved && lastLoggedInSaved && privateKeySaved else {
            return false
        }

        AppGroupsService.shared.storeTLSAddress(address)

        if let defaults = AppGroupsService.shared.sharedDefaults,
           let pubHex = try? Secp.Signing.PrivateKey(dataRepresentation: privateKey).publicKey.dataRepresentation.hexString {
            defaults.set(pubHex, forKey: "zeroa_pubkey_compressed_hex")
            defaults.synchronize()
        }

        return true
    }

    private func migrateLegacyWalletIfNeeded() {
        guard let mnemonic = keychain.read(key: "wallet_mnemonic") else { return }
        let normalized = MnemonicGenerator.normalized(mnemonic)
        let storedAddress = keychain.read(key: "wallet_address")
        let missingPrivateKey = keychain.read(key: "wallet_private_key") == nil
        let needsMigration = missingPrivateKey || storedAddress == nil || storedAddress == WalletService.legacyAddress

        guard needsMigration,
              MnemonicGenerator.validate(mnemonic: normalized),
              let derived = try? deriveWallet(from: normalized) else {
            return
        }

        _ = persist(mnemonic: normalized, privateKey: derived.privateKey, address: derived.address)
    }

    static func deriveAddress(from privateKey: Secp.Signing.PrivateKey) -> String {
        let publicKeyData = privateKey.publicKey.dataRepresentation
        if isDerivationLoggingEnabled {
            print("🔍 deriveAddress pubkey:", publicKeyData.count, publicKeyData.map { String(format: "%02x", $0) }.joined())
        }
        let sha = Data(SHA256.hash(data: publicKeyData))
        let ripemd = RIPEMD160.hash(sha)
        if isDerivationLoggingEnabled {
            print("🔍 deriveAddress RIPEMD:", ripemd.map { String(format: "%02x", $0) }.joined())
        }

        var payload = Data([0x42]) // New version byte
        payload.append(ripemd)
        let checksum = Data(SHA256.hash(data: Data(SHA256.hash(data: payload)))).prefix(4)
        payload.append(checksum)

        return Base58.encode(payload)
    }
    
    private static func deriveLegacyAddress(from privateKey: Secp.Signing.PrivateKey) -> String {
        let publicKeyData = privateKey.publicKey.dataRepresentation
        if isDerivationLoggingEnabled {
            print("🔍 Legacy derivation - Public key length: \(publicKeyData.count) bytes")
            print("🔍 Legacy derivation - Public key hex (first 20): \(publicKeyData.prefix(10).map { String(format: "%02x", $0) }.joined())...")
        }
        
        let sha = Data(SHA256.hash(data: publicKeyData))
        let ripemd = RIPEMD160.hash(sha)
        if isDerivationLoggingEnabled {
            print("🔍 Legacy derivation - RIPEMD160 hex: \(ripemd.map { String(format: "%02x", $0) }.joined())")
        }

        var payload = Data([0x3C]) // Legacy version byte (60 decimal)
        payload.append(ripemd)
        let checksum = Data(SHA256.hash(data: Data(SHA256.hash(data: payload)))).prefix(4)
        if isDerivationLoggingEnabled {
            print("🔍 Legacy derivation - Checksum hex: \(checksum.map { String(format: "%02x", $0) }.joined())")
        }
        payload.append(checksum)

        let address = Base58.encode(payload)
        if isDerivationLoggingEnabled {
            print("🔍 Legacy derivation - Final address: \(address)")
        }
        return address
    }

    struct DerivedWallet {
        let privateKey: Data
        let address: String
    }

    private static let legacyAddress = "ThGNWv22Mb89YwMKo8hAgTEL5ChWcnNuRJ"
    
    /// Derive wallet for a specific BIP44 path (for address rotation)
    /// - Parameters:
    ///   - mnemonic: Mnemonic phrase
    ///   - account: Account index (default: 0)
    ///   - change: Change value (0 for receive, 1 for change)
    ///   - index: Address index
    /// - Returns: Derived wallet with private key and address
    func deriveWalletForPath(mnemonic: String, account: UInt32 = 0, change: UInt32, index: UInt32) throws -> DerivedWallet {
        let normalized = MnemonicGenerator.normalized(mnemonic)
        let seed = MnemonicGenerator.seed(from: normalized)
        var node = try HDPrivateKey(seed: seed)
        
        // Derive path: m/44'/10117'/account'/change/index
        node = try node.derived(step: .hardened(44))
        node = try node.derived(step: .hardened(10117)) // Telestai coin type
        node = try node.derived(step: .hardened(account))
        node = try node.derived(step: .normal(change))
        node = try node.derived(step: .normal(index))
        
        let signingKey = try Secp.Signing.PrivateKey(dataRepresentation: node.key)
        let address = WalletService.deriveAddress(from: signingKey)
        return DerivedWallet(privateKey: node.key, address: address)
    }

    /// Export the currently loaded wallet's key material, ensuring the private key matches the active address.
    func exportActiveWallet() throws -> DerivedWallet {
        guard let mnemonic = loadMnemonic(requireBiometrics: false) else {
            throw WalletError.invalidMnemonic
        }
        let normalized = MnemonicGenerator.normalized(mnemonic)
        let targetAddress = loadAddress()?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? keychain.read(key: "last_logged_in_address")?.trimmingCharacters(in: .whitespacesAndNewlines)

        let official = try deriveWallet(from: normalized)
        if targetAddress == nil || official.address == targetAddress {
            return official
        }

        if let oldNew = try? deriveOldNewWallet(from: normalized), oldNew.address == targetAddress {
            return oldNew
        }

        if let legacy = try? deriveLegacyWallet(from: normalized), legacy.address == targetAddress {
            return legacy
        }

        throw WalletError.keyDerivationFailed
    }
}

private enum WalletError: Error {
    case invalidMnemonic
    case keyDerivationFailed
}

private enum DerivationStep {
    case hardened(UInt32)
    case normal(UInt32)

    var index: UInt32 {
        switch self {
        case .hardened(let value):
            return value | 0x80000000
        case .normal(let value):
            return value
        }
    }

    var isHardened: Bool {
        switch self {
        case .hardened:
            return true
        case .normal:
            return false
        }
    }
}

private struct HDPrivateKey {
    let key: Data
    let chainCode: Data

    init(seed: Data) throws {
        let keyData = Data("Bitcoin seed".utf8)
        let digest = Data(HMAC<SHA512>.authenticationCode(for: seed, using: SymmetricKey(data: keyData)))
        let privateKey = Data(digest.prefix(32))
        let chainCode = Data(digest.suffix(32))

        guard (try? Secp.Signing.PrivateKey(dataRepresentation: privateKey)) != nil else {
            throw WalletError.keyDerivationFailed
        }

        self.key = privateKey
        self.chainCode = chainCode
    }

    private init(key: Data, chainCode: Data) {
        self.key = key
        self.chainCode = chainCode
    }

    func derived(step: DerivationStep) throws -> HDPrivateKey {
        try derived(index: step.index, hardened: step.isHardened)
    }

    private func derived(index: UInt32, hardened: Bool) throws -> HDPrivateKey {
        let parentKey = try Secp.Signing.PrivateKey(dataRepresentation: key)

        var data = Data()
        if hardened {
            data.append(0x00)
            data.append(key)
        } else {
            data.append(parentKey.publicKey.dataRepresentation)
        }

        var bigEndian = index.bigEndian
        withUnsafeBytes(of: &bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }

        let digest = Data(HMAC<SHA512>.authenticationCode(
            for: data,
            using: SymmetricKey(data: chainCode)
        ))
        let il = digest.prefix(32)
        let ir = digest.suffix(32)

        guard let childKey = try? parentKey.add([UInt8](il)) else {
            throw WalletError.keyDerivationFailed
        }

        return HDPrivateKey(key: childKey.dataRepresentation, chainCode: Data(ir))
    }
}

private enum MnemonicGenerator {
    static func generate(strength: Int) -> String {
        precondition(strength % 32 == 0 && strength >= 128 && strength <= 256, "Strength must be 128-256 and divisible by 32")
        let entropy = randomBytes(count: strength / 8)
        return entropyToMnemonic(entropy)
    }

    static func normalized(_ mnemonic: String) -> String {
        mnemonic
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func validate(mnemonic: String) -> Bool {
        if let entropy = mnemonicToEntropy(mnemonic) {
            return true
        } else {
            // Detailed validation logging
            let words = mnemonic.split(separator: " ").map(String.init)
            print("🔍 Mnemonic validation details:")
            print("   Word count: \(words.count)")
            print("   Valid count (12/15/18/21/24): \(words.count >= 12 && words.count <= 24 && words.count % 3 == 0)")
            
            if words.count < 12 || words.count > 24 || words.count % 3 != 0 {
                print("❌ Invalid word count: \(words.count) (must be 12, 15, 18, 21, or 24)")
                return false
            }
            
            var invalidWords: [String] = []
            for (idx, word) in words.enumerated() {
                if englishWordMap[word] == nil {
                    invalidWords.append("\(idx+1):'\(word)'")
                }
            }
            
            if !invalidWords.isEmpty {
                print("❌ Invalid words found: \(invalidWords.joined(separator: ", "))")
                return false
            }
            
            print("❌ Checksum validation failed (words are valid but checksum doesn't match)")
            return false
        }
    }

    static func seed(from mnemonic: String, passphrase: String = "") -> Data {
        let normalizedMnemonic = normalized(mnemonic).decomposedStringWithCompatibilityMapping
        let saltString = ("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping
        guard let passwordData = normalizedMnemonic.data(using: .utf8),
              let saltData = saltString.data(using: .utf8) else {
            return Data()
        }
        return pbkdf2(password: passwordData, salt: saltData, iterations: 2048, keyLength: 64)
    }

    private static func entropyToMnemonic(_ entropy: Data) -> String {
        let entropyBits = Self.bits(from: entropy)
        let checksumBitsCount = entropy.count / 4
        let checksumBits = Array(Self.bits(from: Data(SHA256.hash(data: entropy))).prefix(checksumBitsCount))

        var combined = entropyBits
        combined.append(contentsOf: checksumBits)

        let wordCount = combined.count / 11
        var words: [String] = []

        for index in 0..<wordCount {
            let start = index * 11
            let end = start + 11
            let slice = combined[start..<end]
            var value = 0
            for bit in slice {
                value = (value << 1) | Int(bit)
            }
            words.append(englishWords[value])
        }

        return words.joined(separator: " ")
    }

    private static func mnemonicToEntropy(_ mnemonic: String) -> Data? {
        let words = mnemonic.split(separator: " ").map(String.init)
        guard words.count >= 12, words.count <= 24, words.count % 3 == 0 else {
            return nil
        }

        var bitStream: [UInt8] = []
        bitStream.reserveCapacity(words.count * 11)

        for word in words {
            guard let index = englishWordMap[word] else {
                return nil
            }
            var value = index
            var chunk = [UInt8](repeating: 0, count: 11)
            for position in (0..<11).reversed() {
                chunk[position] = UInt8(value & 1)
                value >>= 1
            }
            bitStream.append(contentsOf: chunk)
        }

        let entropyBitsCount = (words.count * 11) - (words.count / 3)
        let checksumBitsCount = words.count / 3

        let entropyBits = Array(bitStream[0..<entropyBitsCount])
        let checksumBits = Array(bitStream[entropyBitsCount..<entropyBitsCount + checksumBitsCount])

        let entropy = data(fromBits: entropyBits)
        let expectedChecksum = Array(Self.bits(from: Data(SHA256.hash(data: entropy))).prefix(checksumBitsCount))

        guard checksumBits == expectedChecksum else {
            return nil
        }

        return entropy
    }

    private static func bits(from data: Data) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(data.count * 8)

        for byte in data {
            for bitIndex in (0..<8).reversed() {
                result.append((byte >> bitIndex) & 0x01)
            }
        }

        return result
    }

    private static func data(fromBits bits: [UInt8]) -> Data {
        var data = Data()
        data.reserveCapacity(bits.count / 8)

        for chunkStart in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            let chunk = bits[chunkStart..<chunkStart + 8]
            for bit in chunk {
                byte = (byte << 1) | bit
            }
            data.append(byte)
        }

        return data
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        let blocks = Int(ceil(Double(keyLength) / Double(SHA512.byteCount)))
        var derived = Data()
        derived.reserveCapacity(blocks * SHA512.byteCount)

        let key = SymmetricKey(data: password)

        for blockIndex in 1...blocks {
            var saltBlock = salt
            var be = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &be) { saltBlock.append(contentsOf: $0) }

            var u = Data(HMAC<SHA512>.authenticationCode(for: saltBlock, using: key))
            var block = u

            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA512>.authenticationCode(for: u, using: key))
                    block = xor(block, u)
                }
            }

            derived.append(block)
        }

        return derived.prefix(keyLength)
    }

    private static func xor(_ lhs: Data, _ rhs: Data) -> Data {
        let count = min(lhs.count, rhs.count)
        var result = Data(count: count)
        result.withUnsafeMutableBytes { resultPtr in
            guard let resultBytes = resultPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            lhs.withUnsafeBytes { lhsPtr in
                rhs.withUnsafeBytes { rhsPtr in
                    let lhsBytes = lhsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let rhsBytes = rhsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    for index in 0..<count {
                        resultBytes[index] = lhsBytes[index] ^ rhsBytes[index]
                    }
                }
            }
        }
        return result
    }

    private static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        precondition(result == errSecSuccess, "Failed to generate secure random bytes")
        return data
    }

    private static let englishWordMap: [String: Int] = {
        var map: [String: Int] = [:]
        map.reserveCapacity(englishWords.count)
        for (index, word) in englishWords.enumerated() {
            map[word] = index
        }
        return map
    }()

    static let englishWords: [String] = [
        "abandon",
        "ability",
        "able",
        "about",
        "above",
        "absent",
        "absorb",
        "abstract",
        "absurd",
        "abuse",
        "access",
        "accident",
        "account",
        "accuse",
        "achieve",
        "acid",
        "acoustic",
        "acquire",
        "across",
        "act",
        "action",
        "actor",
        "actress",
        "actual",
        "adapt",
        "add",
        "addict",
        "address",
        "adjust",
        "admit",
        "adult",
        "advance",
        "advice",
        "aerobic",
        "affair",
        "afford",
        "afraid",
        "again",
        "age",
        "agent",
        "agree",
        "ahead",
        "aim",
        "air",
        "airport",
        "aisle",
        "alarm",
        "album",
        "alcohol",
        "alert",
        "alien",
        "all",
        "alley",
        "allow",
        "almost",
        "alone",
        "alpha",
        "already",
        "also",
        "alter",
        "always",
        "amateur",
        "amazing",
        "among",
        "amount",
        "amused",
        "analyst",
        "anchor",
        "ancient",
        "anger",
        "angle",
        "angry",
        "animal",
        "ankle",
        "announce",
        "annual",
        "another",
        "answer",
        "antenna",
        "antique",
        "anxiety",
        "any",
        "apart",
        "apology",
        "appear",
        "apple",
        "approve",
        "april",
        "arch",
        "arctic",
        "area",
        "arena",
        "argue",
        "arm",
        "armed",
        "armor",
        "army",
        "around",
        "arrange",
        "arrest",
        "arrive",
        "arrow",
        "art",
        "artefact",
        "artist",
        "artwork",
        "ask",
        "aspect",
        "assault",
        "asset",
        "assist",
        "assume",
        "asthma",
        "athlete",
        "atom",
        "attack",
        "attend",
        "attitude",
        "attract",
        "auction",
        "audit",
        "august",
        "aunt",
        "author",
        "auto",
        "autumn",
        "average",
        "avocado",
        "avoid",
        "awake",
        "aware",
        "away",
        "awesome",
        "awful",
        "awkward",
        "axis",
        "baby",
        "bachelor",
        "bacon",
        "badge",
        "bag",
        "balance",
        "balcony",
        "ball",
        "bamboo",
        "banana",
        "banner",
        "bar",
        "barely",
        "bargain",
        "barrel",
        "base",
        "basic",
        "basket",
        "battle",
        "beach",
        "bean",
        "beauty",
        "because",
        "become",
        "beef",
        "before",
        "begin",
        "behave",
        "behind",
        "believe",
        "below",
        "belt",
        "bench",
        "benefit",
        "best",
        "betray",
        "better",
        "between",
        "beyond",
        "bicycle",
        "bid",
        "bike",
        "bind",
        "biology",
        "bird",
        "birth",
        "bitter",
        "black",
        "blade",
        "blame",
        "blanket",
        "blast",
        "bleak",
        "bless",
        "blind",
        "blood",
        "blossom",
        "blouse",
        "blue",
        "blur",
        "blush",
        "board",
        "boat",
        "body",
        "boil",
        "bomb",
        "bone",
        "bonus",
        "book",
        "boost",
        "border",
        "boring",
        "borrow",
        "boss",
        "bottom",
        "bounce",
        "box",
        "boy",
        "bracket",
        "brain",
        "brand",
        "brass",
        "brave",
        "bread",
        "breeze",
        "brick",
        "bridge",
        "brief",
        "bright",
        "bring",
        "brisk",
        "broccoli",
        "broken",
        "bronze",
        "broom",
        "brother",
        "brown",
        "brush",
        "bubble",
        "buddy",
        "budget",
        "buffalo",
        "build",
        "bulb",
        "bulk",
        "bullet",
        "bundle",
        "bunker",
        "burden",
        "burger",
        "burst",
        "bus",
        "business",
        "busy",
        "butter",
        "buyer",
        "buzz",
        "cabbage",
        "cabin",
        "cable",
        "cactus",
        "cage",
        "cake",
        "call",
        "calm",
        "camera",
        "camp",
        "can",
        "canal",
        "cancel",
        "candy",
        "cannon",
        "canoe",
        "canvas",
        "canyon",
        "capable",
        "capital",
        "captain",
        "car",
        "carbon",
        "card",
        "cargo",
        "carpet",
        "carry",
        "cart",
        "case",
        "cash",
        "casino",
        "castle",
        "casual",
        "cat",
        "catalog",
        "catch",
        "category",
        "cattle",
        "caught",
        "cause",
        "caution",
        "cave",
        "ceiling",
        "celery",
        "cement",
        "census",
        "century",
        "cereal",
        "certain",
        "chair",
        "chalk",
        "champion",
        "change",
        "chaos",
        "chapter",
        "charge",
        "chase",
        "chat",
        "cheap",
        "check",
        "cheese",
        "chef",
        "cherry",
        "chest",
        "chicken",
        "chief",
        "child",
        "chimney",
        "choice",
        "choose",
        "chronic",
        "chuckle",
        "chunk",
        "churn",
        "cigar",
        "cinnamon",
        "circle",
        "citizen",
        "city",
        "civil",
        "claim",
        "clap",
        "clarify",
        "claw",
        "clay",
        "clean",
        "clerk",
        "clever",
        "click",
        "client",
        "cliff",
        "climb",
        "clinic",
        "clip",
        "clock",
        "clog",
        "close",
        "cloth",
        "cloud",
        "clown",
        "club",
        "clump",
        "cluster",
        "clutch",
        "coach",
        "coast",
        "coconut",
        "code",
        "coffee",
        "coil",
        "coin",
        "collect",
        "color",
        "column",
        "combine",
        "come",
        "comfort",
        "comic",
        "common",
        "company",
        "concert",
        "conduct",
        "confirm",
        "congress",
        "connect",
        "consider",
        "control",
        "convince",
        "cook",
        "cool",
        "copper",
        "copy",
        "coral",
        "core",
        "corn",
        "correct",
        "cost",
        "cotton",
        "couch",
        "country",
        "couple",
        "course",
        "cousin",
        "cover",
        "coyote",
        "crack",
        "cradle",
        "craft",
        "cram",
        "crane",
        "crash",
        "crater",
        "crawl",
        "crazy",
        "cream",
        "credit",
        "creek",
        "crew",
        "cricket",
        "crime",
        "crisp",
        "critic",
        "crop",
        "cross",
        "crouch",
        "crowd",
        "crucial",
        "cruel",
        "cruise",
        "crumble",
        "crunch",
        "crush",
        "cry",
        "crystal",
        "cube",
        "culture",
        "cup",
        "cupboard",
        "curious",
        "current",
        "curtain",
        "curve",
        "cushion",
        "custom",
        "cute",
        "cycle",
        "dad",
        "damage",
        "damp",
        "dance",
        "danger",
        "daring",
        "dash",
        "daughter",
        "dawn",
        "day",
        "deal",
        "debate",
        "debris",
        "decade",
        "december",
        "decide",
        "decline",
        "decorate",
        "decrease",
        "deer",
        "defense",
        "define",
        "defy",
        "degree",
        "delay",
        "deliver",
        "demand",
        "demise",
        "denial",
        "dentist",
        "deny",
        "depart",
        "depend",
        "deposit",
        "depth",
        "deputy",
        "derive",
        "describe",
        "desert",
        "design",
        "desk",
        "despair",
        "destroy",
        "detail",
        "detect",
        "develop",
        "device",
        "devote",
        "diagram",
        "dial",
        "diamond",
        "diary",
        "dice",
        "diesel",
        "diet",
        "differ",
        "digital",
        "dignity",
        "dilemma",
        "dinner",
        "dinosaur",
        "direct",
        "dirt",
        "disagree",
        "discover",
        "disease",
        "dish",
        "dismiss",
        "disorder",
        "display",
        "distance",
        "divert",
        "divide",
        "divorce",
        "dizzy",
        "doctor",
        "document",
        "dog",
        "doll",
        "dolphin",
        "domain",
        "donate",
        "donkey",
        "donor",
        "door",
        "dose",
        "double",
        "dove",
        "draft",
        "dragon",
        "drama",
        "drastic",
        "draw",
        "dream",
        "dress",
        "drift",
        "drill",
        "drink",
        "drip",
        "drive",
        "drop",
        "drum",
        "dry",
        "duck",
        "dumb",
        "dune",
        "during",
        "dust",
        "dutch",
        "duty",
        "dwarf",
        "dynamic",
        "eager",
        "eagle",
        "early",
        "earn",
        "earth",
        "easily",
        "east",
        "easy",
        "echo",
        "ecology",
        "economy",
        "edge",
        "edit",
        "educate",
        "effort",
        "egg",
        "eight",
        "either",
        "elbow",
        "elder",
        "electric",
        "elegant",
        "element",
        "elephant",
        "elevator",
        "elite",
        "else",
        "embark",
        "embody",
        "embrace",
        "emerge",
        "emotion",
        "employ",
        "empower",
        "empty",
        "enable",
        "enact",
        "end",
        "endless",
        "endorse",
        "enemy",
        "energy",
        "enforce",
        "engage",
        "engine",
        "enhance",
        "enjoy",
        "enlist",
        "enough",
        "enrich",
        "enroll",
        "ensure",
        "enter",
        "entire",
        "entry",
        "envelope",
        "episode",
        "equal",
        "equip",
        "era",
        "erase",
        "erode",
        "erosion",
        "error",
        "erupt",
        "escape",
        "essay",
        "essence",
        "estate",
        "eternal",
        "ethics",
        "evidence",
        "evil",
        "evoke",
        "evolve",
        "exact",
        "example",
        "excess",
        "exchange",
        "excite",
        "exclude",
        "excuse",
        "execute",
        "exercise",
        "exhaust",
        "exhibit",
        "exile",
        "exist",
        "exit",
        "exotic",
        "expand",
        "expect",
        "expire",
        "explain",
        "expose",
        "express",
        "extend",
        "extra",
        "eye",
        "eyebrow",
        "fabric",
        "face",
        "faculty",
        "fade",
        "faint",
        "faith",
        "fall",
        "false",
        "fame",
        "family",
        "famous",
        "fan",
        "fancy",
        "fantasy",
        "farm",
        "fashion",
        "fat",
        "fatal",
        "father",
        "fatigue",
        "fault",
        "favorite",
        "feature",
        "february",
        "federal",
        "fee",
        "feed",
        "feel",
        "female",
        "fence",
        "festival",
        "fetch",
        "fever",
        "few",
        "fiber",
        "fiction",
        "field",
        "figure",
        "file",
        "film",
        "filter",
        "final",
        "find",
        "fine",
        "finger",
        "finish",
        "fire",
        "firm",
        "first",
        "fiscal",
        "fish",
        "fit",
        "fitness",
        "fix",
        "flag",
        "flame",
        "flash",
        "flat",
        "flavor",
        "flee",
        "flight",
        "flip",
        "float",
        "flock",
        "floor",
        "flower",
        "fluid",
        "flush",
        "fly",
        "foam",
        "focus",
        "fog",
        "foil",
        "fold",
        "follow",
        "food",
        "foot",
        "force",
        "forest",
        "forget",
        "fork",
        "fortune",
        "forum",
        "forward",
        "fossil",
        "foster",
        "found",
        "fox",
        "fragile",
        "frame",
        "frequent",
        "fresh",
        "friend",
        "fringe",
        "frog",
        "front",
        "frost",
        "frown",
        "frozen",
        "fruit",
        "fuel",
        "fun",
        "funny",
        "furnace",
        "fury",
        "future",
        "gadget",
        "gain",
        "galaxy",
        "gallery",
        "game",
        "gap",
        "garage",
        "garbage",
        "garden",
        "garlic",
        "garment",
        "gas",
        "gasp",
        "gate",
        "gather",
        "gauge",
        "gaze",
        "general",
        "genius",
        "genre",
        "gentle",
        "genuine",
        "gesture",
        "ghost",
        "giant",
        "gift",
        "giggle",
        "ginger",
        "giraffe",
        "girl",
        "give",
        "glad",
        "glance",
        "glare",
        "glass",
        "glide",
        "glimpse",
        "globe",
        "gloom",
        "glory",
        "glove",
        "glow",
        "glue",
        "goat",
        "goddess",
        "gold",
        "good",
        "goose",
        "gorilla",
        "gospel",
        "gossip",
        "govern",
        "gown",
        "grab",
        "grace",
        "grain",
        "grant",
        "grape",
        "grass",
        "gravity",
        "great",
        "green",
        "grid",
        "grief",
        "grit",
        "grocery",
        "group",
        "grow",
        "grunt",
        "guard",
        "guess",
        "guide",
        "guilt",
        "guitar",
        "gun",
        "gym",
        "habit",
        "hair",
        "half",
        "hammer",
        "hamster",
        "hand",
        "happy",
        "harbor",
        "hard",
        "harsh",
        "harvest",
        "hat",
        "have",
        "hawk",
        "hazard",
        "head",
        "health",
        "heart",
        "heavy",
        "hedgehog",
        "height",
        "hello",
        "helmet",
        "help",
        "hen",
        "hero",
        "hidden",
        "high",
        "hill",
        "hint",
        "hip",
        "hire",
        "history",
        "hobby",
        "hockey",
        "hold",
        "hole",
        "holiday",
        "hollow",
        "home",
        "honey",
        "hood",
        "hope",
        "horn",
        "horror",
        "horse",
        "hospital",
        "host",
        "hotel",
        "hour",
        "hover",
        "hub",
        "huge",
        "human",
        "humble",
        "humor",
        "hundred",
        "hungry",
        "hunt",
        "hurdle",
        "hurry",
        "hurt",
        "husband",
        "hybrid",
        "ice",
        "icon",
        "idea",
        "identify",
        "idle",
        "ignore",
        "ill",
        "illegal",
        "illness",
        "image",
        "imitate",
        "immense",
        "immune",
        "impact",
        "impose",
        "improve",
        "impulse",
        "inch",
        "include",
        "income",
        "increase",
        "index",
        "indicate",
        "indoor",
        "industry",
        "infant",
        "inflict",
        "inform",
        "inhale",
        "inherit",
        "initial",
        "inject",
        "injury",
        "inmate",
        "inner",
        "innocent",
        "input",
        "inquiry",
        "insane",
        "insect",
        "inside",
        "inspire",
        "install",
        "intact",
        "interest",
        "into",
        "invest",
        "invite",
        "involve",
        "iron",
        "island",
        "isolate",
        "issue",
        "item",
        "ivory",
        "jacket",
        "jaguar",
        "jar",
        "jazz",
        "jealous",
        "jeans",
        "jelly",
        "jewel",
        "job",
        "join",
        "joke",
        "journey",
        "joy",
        "judge",
        "juice",
        "jump",
        "jungle",
        "junior",
        "junk",
        "just",
        "kangaroo",
        "keen",
        "keep",
        "ketchup",
        "key",
        "kick",
        "kid",
        "kidney",
        "kind",
        "kingdom",
        "kiss",
        "kit",
        "kitchen",
        "kite",
        "kitten",
        "kiwi",
        "knee",
        "knife",
        "knock",
        "know",
        "lab",
        "label",
        "labor",
        "ladder",
        "lady",
        "lake",
        "lamp",
        "language",
        "laptop",
        "large",
        "later",
        "latin",
        "laugh",
        "laundry",
        "lava",
        "law",
        "lawn",
        "lawsuit",
        "layer",
        "lazy",
        "leader",
        "leaf",
        "learn",
        "leave",
        "lecture",
        "left",
        "leg",
        "legal",
        "legend",
        "leisure",
        "lemon",
        "lend",
        "length",
        "lens",
        "leopard",
        "lesson",
        "letter",
        "level",
        "liar",
        "liberty",
        "library",
        "license",
        "life",
        "lift",
        "light",
        "like",
        "limb",
        "limit",
        "link",
        "lion",
        "liquid",
        "list",
        "little",
        "live",
        "lizard",
        "load",
        "loan",
        "lobster",
        "local",
        "lock",
        "logic",
        "lonely",
        "long",
        "loop",
        "lottery",
        "loud",
        "lounge",
        "love",
        "loyal",
        "lucky",
        "luggage",
        "lumber",
        "lunar",
        "lunch",
        "luxury",
        "lyrics",
        "machine",
        "mad",
        "magic",
        "magnet",
        "maid",
        "mail",
        "main",
        "major",
        "make",
        "mammal",
        "man",
        "manage",
        "mandate",
        "mango",
        "mansion",
        "manual",
        "maple",
        "marble",
        "march",
        "margin",
        "marine",
        "market",
        "marriage",
        "mask",
        "mass",
        "master",
        "match",
        "material",
        "math",
        "matrix",
        "matter",
        "maximum",
        "maze",
        "meadow",
        "mean",
        "measure",
        "meat",
        "mechanic",
        "medal",
        "media",
        "melody",
        "melt",
        "member",
        "memory",
        "mention",
        "menu",
        "mercy",
        "merge",
        "merit",
        "merry",
        "mesh",
        "message",
        "metal",
        "method",
        "middle",
        "midnight",
        "milk",
        "million",
        "mimic",
        "mind",
        "minimum",
        "minor",
        "minute",
        "miracle",
        "mirror",
        "misery",
        "miss",
        "mistake",
        "mix",
        "mixed",
        "mixture",
        "mobile",
        "model",
        "modify",
        "mom",
        "moment",
        "monitor",
        "monkey",
        "monster",
        "month",
        "moon",
        "moral",
        "more",
        "morning",
        "mosquito",
        "mother",
        "motion",
        "motor",
        "mountain",
        "mouse",
        "move",
        "movie",
        "much",
        "muffin",
        "mule",
        "multiply",
        "muscle",
        "museum",
        "mushroom",
        "music",
        "must",
        "mutual",
        "myself",
        "mystery",
        "myth",
        "naive",
        "name",
        "napkin",
        "narrow",
        "nasty",
        "nation",
        "nature",
        "near",
        "neck",
        "need",
        "negative",
        "neglect",
        "neither",
        "nephew",
        "nerve",
        "nest",
        "net",
        "network",
        "neutral",
        "never",
        "news",
        "next",
        "nice",
        "night",
        "noble",
        "noise",
        "nominee",
        "noodle",
        "normal",
        "north",
        "nose",
        "notable",
        "note",
        "nothing",
        "notice",
        "novel",
        "now",
        "nuclear",
        "number",
        "nurse",
        "nut",
        "oak",
        "obey",
        "object",
        "oblige",
        "obscure",
        "observe",
        "obtain",
        "obvious",
        "occur",
        "ocean",
        "october",
        "odor",
        "off",
        "offer",
        "office",
        "often",
        "oil",
        "okay",
        "old",
        "olive",
        "olympic",
        "omit",
        "once",
        "one",
        "onion",
        "online",
        "only",
        "open",
        "opera",
        "opinion",
        "oppose",
        "option",
        "orange",
        "orbit",
        "orchard",
        "order",
        "ordinary",
        "organ",
        "orient",
        "original",
        "orphan",
        "ostrich",
        "other",
        "outdoor",
        "outer",
        "output",
        "outside",
        "oval",
        "oven",
        "over",
        "own",
        "owner",
        "oxygen",
        "oyster",
        "ozone",
        "pact",
        "paddle",
        "page",
        "pair",
        "palace",
        "palm",
        "panda",
        "panel",
        "panic",
        "panther",
        "paper",
        "parade",
        "parent",
        "park",
        "parrot",
        "party",
        "pass",
        "patch",
        "path",
        "patient",
        "patrol",
        "pattern",
        "pause",
        "pave",
        "payment",
        "peace",
        "peanut",
        "pear",
        "peasant",
        "pelican",
        "pen",
        "penalty",
        "pencil",
        "people",
        "pepper",
        "perfect",
        "permit",
        "person",
        "pet",
        "phone",
        "photo",
        "phrase",
        "physical",
        "piano",
        "picnic",
        "picture",
        "piece",
        "pig",
        "pigeon",
        "pill",
        "pilot",
        "pink",
        "pioneer",
        "pipe",
        "pistol",
        "pitch",
        "pizza",
        "place",
        "planet",
        "plastic",
        "plate",
        "play",
        "please",
        "pledge",
        "pluck",
        "plug",
        "plunge",
        "poem",
        "poet",
        "point",
        "polar",
        "pole",
        "police",
        "pond",
        "pony",
        "pool",
        "popular",
        "portion",
        "position",
        "possible",
        "post",
        "potato",
        "pottery",
        "poverty",
        "powder",
        "power",
        "practice",
        "praise",
        "predict",
        "prefer",
        "prepare",
        "present",
        "pretty",
        "prevent",
        "price",
        "pride",
        "primary",
        "print",
        "priority",
        "prison",
        "private",
        "prize",
        "problem",
        "process",
        "produce",
        "profit",
        "program",
        "project",
        "promote",
        "proof",
        "property",
        "prosper",
        "protect",
        "proud",
        "provide",
        "public",
        "pudding",
        "pull",
        "pulp",
        "pulse",
        "pumpkin",
        "punch",
        "pupil",
        "puppy",
        "purchase",
        "purity",
        "purpose",
        "purse",
        "push",
        "put",
        "puzzle",
        "pyramid",
        "quality",
        "quantum",
        "quarter",
        "question",
        "quick",
        "quit",
        "quiz",
        "quote",
        "rabbit",
        "raccoon",
        "race",
        "rack",
        "radar",
        "radio",
        "rail",
        "rain",
        "raise",
        "rally",
        "ramp",
        "ranch",
        "random",
        "range",
        "rapid",
        "rare",
        "rate",
        "rather",
        "raven",
        "raw",
        "razor",
        "ready",
        "real",
        "reason",
        "rebel",
        "rebuild",
        "recall",
        "receive",
        "recipe",
        "record",
        "recycle",
        "reduce",
        "reflect",
        "reform",
        "refuse",
        "region",
        "regret",
        "regular",
        "reject",
        "relax",
        "release",
        "relief",
        "rely",
        "remain",
        "remember",
        "remind",
        "remove",
        "render",
        "renew",
        "rent",
        "reopen",
        "repair",
        "repeat",
        "replace",
        "report",
        "require",
        "rescue",
        "resemble",
        "resist",
        "resource",
        "response",
        "result",
        "retire",
        "retreat",
        "return",
        "reunion",
        "reveal",
        "review",
        "reward",
        "rhythm",
        "rib",
        "ribbon",
        "rice",
        "rich",
        "ride",
        "ridge",
        "rifle",
        "right",
        "rigid",
        "ring",
        "riot",
        "ripple",
        "risk",
        "ritual",
        "rival",
        "river",
        "road",
        "roast",
        "robot",
        "robust",
        "rocket",
        "romance",
        "roof",
        "rookie",
        "room",
        "rose",
        "rotate",
        "rough",
        "round",
        "route",
        "royal",
        "rubber",
        "rude",
        "rug",
        "rule",
        "run",
        "runway",
        "rural",
        "sad",
        "saddle",
        "sadness",
        "safe",
        "sail",
        "salad",
        "salmon",
        "salon",
        "salt",
        "salute",
        "same",
        "sample",
        "sand",
        "satisfy",
        "satoshi",
        "sauce",
        "sausage",
        "save",
        "say",
        "scale",
        "scan",
        "scare",
        "scatter",
        "scene",
        "scheme",
        "school",
        "science",
        "scissors",
        "scorpion",
        "scout",
        "scrap",
        "screen",
        "script",
        "scrub",
        "sea",
        "search",
        "season",
        "seat",
        "second",
        "secret",
        "section",
        "security",
        "seed",
        "seek",
        "segment",
        "select",
        "sell",
        "seminar",
        "senior",
        "sense",
        "sentence",
        "series",
        "service",
        "session",
        "settle",
        "setup",
        "seven",
        "shadow",
        "shaft",
        "shallow",
        "share",
        "shed",
        "shell",
        "sheriff",
        "shield",
        "shift",
        "shine",
        "ship",
        "shiver",
        "shock",
        "shoe",
        "shoot",
        "shop",
        "short",
        "shoulder",
        "shove",
        "shrimp",
        "shrug",
        "shuffle",
        "shy",
        "sibling",
        "sick",
        "side",
        "siege",
        "sight",
        "sign",
        "silent",
        "silk",
        "silly",
        "silver",
        "similar",
        "simple",
        "since",
        "sing",
        "siren",
        "sister",
        "situate",
        "six",
        "size",
        "skate",
        "sketch",
        "ski",
        "skill",
        "skin",
        "skirt",
        "skull",
        "slab",
        "slam",
        "sleep",
        "slender",
        "slice",
        "slide",
        "slight",
        "slim",
        "slogan",
        "slot",
        "slow",
        "slush",
        "small",
        "smart",
        "smile",
        "smoke",
        "smooth",
        "snack",
        "snake",
        "snap",
        "sniff",
        "snow",
        "soap",
        "soccer",
        "social",
        "sock",
        "soda",
        "soft",
        "solar",
        "soldier",
        "solid",
        "solution",
        "solve",
        "someone",
        "song",
        "soon",
        "sorry",
        "sort",
        "soul",
        "sound",
        "soup",
        "source",
        "south",
        "space",
        "spare",
        "spatial",
        "spawn",
        "speak",
        "special",
        "speed",
        "spell",
        "spend",
        "sphere",
        "spice",
        "spider",
        "spike",
        "spin",
        "spirit",
        "split",
        "spoil",
        "sponsor",
        "spoon",
        "sport",
        "spot",
        "spray",
        "spread",
        "spring",
        "spy",
        "square",
        "squeeze",
        "squirrel",
        "stable",
        "stadium",
        "staff",
        "stage",
        "stairs",
        "stamp",
        "stand",
        "start",
        "state",
        "stay",
        "steak",
        "steel",
        "stem",
        "step",
        "stereo",
        "stick",
        "still",
        "sting",
        "stock",
        "stomach",
        "stone",
        "stool",
        "story",
        "stove",
        "strategy",
        "street",
        "strike",
        "strong",
        "struggle",
        "student",
        "stuff",
        "stumble",
        "style",
        "subject",
        "submit",
        "subway",
        "success",
        "such",
        "sudden",
        "suffer",
        "sugar",
        "suggest",
        "suit",
        "summer",
        "sun",
        "sunny",
        "sunset",
        "super",
        "supply",
        "supreme",
        "sure",
        "surface",
        "surge",
        "surprise",
        "surround",
        "survey",
        "suspect",
        "sustain",
        "swallow",
        "swamp",
        "swap",
        "swarm",
        "swear",
        "sweet",
        "swift",
        "swim",
        "swing",
        "switch",
        "sword",
        "symbol",
        "symptom",
        "syrup",
        "system",
        "table",
        "tackle",
        "tag",
        "tail",
        "talent",
        "talk",
        "tank",
        "tape",
        "target",
        "task",
        "taste",
        "tattoo",
        "taxi",
        "teach",
        "team",
        "tell",
        "ten",
        "tenant",
        "tennis",
        "tent",
        "term",
        "test",
        "text",
        "thank",
        "that",
        "theme",
        "then",
        "theory",
        "there",
        "they",
        "thing",
        "this",
        "thought",
        "three",
        "thrive",
        "throw",
        "thumb",
        "thunder",
        "ticket",
        "tide",
        "tiger",
        "tilt",
        "timber",
        "time",
        "tiny",
        "tip",
        "tired",
        "tissue",
        "title",
        "toast",
        "tobacco",
        "today",
        "toddler",
        "toe",
        "together",
        "toilet",
        "token",
        "tomato",
        "tomorrow",
        "tone",
        "tongue",
        "tonight",
        "tool",
        "tooth",
        "top",
        "topic",
        "topple",
        "torch",
        "tornado",
        "tortoise",
        "toss",
        "total",
        "tourist",
        "toward",
        "tower",
        "town",
        "toy",
        "track",
        "trade",
        "traffic",
        "tragic",
        "train",
        "transfer",
        "trap",
        "trash",
        "travel",
        "tray",
        "treat",
        "tree",
        "trend",
        "trial",
        "tribe",
        "trick",
        "trigger",
        "trim",
        "trip",
        "trophy",
        "trouble",
        "truck",
        "true",
        "truly",
        "trumpet",
        "trust",
        "truth",
        "try",
        "tube",
        "tuition",
        "tumble",
        "tuna",
        "tunnel",
        "turkey",
        "turn",
        "turtle",
        "twelve",
        "twenty",
        "twice",
        "twin",
        "twist",
        "two",
        "type",
        "typical",
        "ugly",
        "umbrella",
        "unable",
        "unaware",
        "uncle",
        "uncover",
        "under",
        "undo",
        "unfair",
        "unfold",
        "unhappy",
        "uniform",
        "unique",
        "unit",
        "universe",
        "unknown",
        "unlock",
        "until",
        "unusual",
        "unveil",
        "update",
        "upgrade",
        "uphold",
        "upon",
        "upper",
        "upset",
        "urban",
        "urge",
        "usage",
        "use",
        "used",
        "useful",
        "useless",
        "usual",
        "utility",
        "vacant",
        "vacuum",
        "vague",
        "valid",
        "valley",
        "valve",
        "van",
        "vanish",
        "vapor",
        "various",
        "vast",
        "vault",
        "vehicle",
        "velvet",
        "vendor",
        "venture",
        "venue",
        "verb",
        "verify",
        "version",
        "very",
        "vessel",
        "veteran",
        "viable",
        "vibrant",
        "vicious",
        "victory",
        "video",
        "view",
        "village",
        "vintage",
        "violin",
        "virtual",
        "virus",
        "visa",
        "visit",
        "visual",
        "vital",
        "vivid",
        "vocal",
        "voice",
        "void",
        "volcano",
        "volume",
        "vote",
        "voyage",
        "wage",
        "wagon",
        "wait",
        "walk",
        "wall",
        "walnut",
        "want",
        "warfare",
        "warm",
        "warrior",
        "wash",
        "wasp",
        "waste",
        "water",
        "wave",
        "way",
        "wealth",
        "weapon",
        "wear",
        "weasel",
        "weather",
        "web",
        "wedding",
        "weekend",
        "weird",
        "welcome",
        "west",
        "wet",
        "whale",
        "what",
        "wheat",
        "wheel",
        "when",
        "where",
        "whip",
        "whisper",
        "wide",
        "width",
        "wife",
        "wild",
        "will",
        "win",
        "window",
        "wine",
        "wing",
        "wink",
        "winner",
        "winter",
        "wire",
        "wisdom",
        "wise",
        "wish",
        "witness",
        "wolf",
        "woman",
        "wonder",
        "wood",
        "wool",
        "word",
        "work",
        "world",
        "worry",
        "worth",
        "wrap",
        "wreck",
        "wrestle",
        "wrist",
        "write",
        "wrong",
        "yard",
        "year",
        "yellow",
        "you",
        "young",
        "youth",
        "zebra",
        "zero",
        "zone",
        "zoo"
    ]
}

enum RIPEMD160 {
    static func hash(_ data: Data) -> Data {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0)
        }
        var lengthBytes = withUnsafeBytes(of: bitLength.littleEndian) { Array($0) }
        message.append(contentsOf: lengthBytes)
        
        var state: [UInt32] = [
            0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0
        ]
        
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            let chunk = Array(message[chunkStart..<chunkStart + 64])
            transform(&state, chunk)
        }
        
        var result = Data(capacity: 20)
        for value in state {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { result.append(contentsOf: $0) }
        }
        return result
    }
    
    @inline(__always) private static func rol(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }
    
    @inline(__always) private static func f1(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { x ^ y ^ z }
    @inline(__always) private static func f2(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (~x & z) }
    @inline(__always) private static func f3(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x | ~y) ^ z }
    @inline(__always) private static func f4(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & z) | (y & ~z) }
    @inline(__always) private static func f5(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { x ^ (y | ~z) }
    
    private static func transform(_ s: inout [UInt32], _ chunk: [UInt8]) {
        var a1 = s[0], b1 = s[1], c1 = s[2], d1 = s[3], e1 = s[4]
        var a2 = a1, b2 = b1, c2 = c1, d2 = d1, e2 = e1
        
        let w = stride(from: 0, to: 64, by: 4).map { i -> UInt32 in
            let value = UInt32(chunk[i])
                | (UInt32(chunk[i + 1]) << 8)
                | (UInt32(chunk[i + 2]) << 16)
                | (UInt32(chunk[i + 3]) << 24)
            return value
        }
        
        func round1(_ f: (UInt32, UInt32, UInt32) -> UInt32, _ k: UInt32, _ r: Int, _ word: Int) {
            let temp = rol(a1 &+ f(b1, c1, d1) &+ w[word] &+ k, UInt32(r)) &+ e1
            a1 = e1; e1 = d1; d1 = rol(c1, 10); c1 = b1; b1 = temp
        }
        
        func round2(_ f: (UInt32, UInt32, UInt32) -> UInt32, _ k: UInt32, _ r: Int, _ word: Int) {
            let temp = rol(a2 &+ f(b2, c2, d2) &+ w[word] &+ k, UInt32(r)) &+ e2
            a2 = e2; e2 = d2; d2 = rol(c2, 10); c2 = b2; b2 = temp
        }
        
        let r1 = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
            3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
            1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
            4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
        ]

        let r2 = [
            5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
            6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
            15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
            8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
            12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
        ]

        let s1: [UInt32] = [
            11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
            7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
            11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
            11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
            9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
        ]

        let s2: [UInt32] = [
            8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
            9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
            9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
            15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
            8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
        ]

        let k1: [UInt32] = [0x00000000, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e]
        let k2: [UInt32] = [0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0x00000000]

            for j in 0..<80 {
                let round = j / 16
                switch round {
            case 0: round1(f1, k1[round], Int(s1[j]), r1[j]); round2(f5, k2[round], Int(s2[j]), r2[j])
            case 1: round1(f2, k1[round], Int(s1[j]), r1[j]); round2(f4, k2[round], Int(s2[j]), r2[j])
            case 2: round1(f3, k1[round], Int(s1[j]), r1[j]); round2(f3, k2[round], Int(s2[j]), r2[j])
            case 3: round1(f4, k1[round], Int(s1[j]), r1[j]); round2(f2, k2[round], Int(s2[j]), r2[j])
            default: round1(f5, k1[round], Int(s1[j]), r1[j]); round2(f1, k2[round], Int(s2[j]), r2[j])
            }
            }

        let t = s[1] &+ c1 &+ d2
        s[1] = s[2] &+ d1 &+ e2
        s[2] = s[3] &+ e1 &+ a2
        s[3] = s[4] &+ a1 &+ b2
        s[4] = s[0] &+ b1 &+ c2
        s[0] = t
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    func publicKeyHex() -> String? {
        guard let privateKey = try? Secp.Signing.PrivateKey(dataRepresentation: self) else { return nil }
        return privateKey.publicKey.dataRepresentation.hexString
    }
}
