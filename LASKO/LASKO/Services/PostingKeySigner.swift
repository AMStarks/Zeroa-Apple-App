import Foundation
import CryptoKit
#if canImport(P256K)
import P256K
typealias LaskoSecp = P256K
#elseif canImport(secp256k1)
import secp256k1
typealias LaskoSecp = secp256k1
#endif

/// Signs LASKO_POST messages with the hourly delegated posting key issued by Zeroa.
enum PostingKeySigner {
    struct Payload {
        let signatureBase64: String
        let pubkeyCompressedHex: String
        let canonicalMessage: String
    }

    static func loadValidKey(
        defaults: UserDefaults?,
        tlsAddress: String,
        bundleId: String,
        skewSeconds: Int64 = 30
    ) -> (privHex: String, pubHex: String, expiresAtMs: Int64)? {
        migrateLegacyAppGroupPrivateKeyIfNeeded(defaults: defaults)
        guard let defaults,
              let pub = defaults.string(forKey: "lasko_posting_pub_hex"), pub.count == 66,
              let storedTLS = defaults.string(forKey: "lasko_posting_tls_address"), storedTLS == tlsAddress,
              let storedBundle = defaults.string(forKey: "lasko_posting_bundle_id"), storedBundle == bundleId,
              let priv = SharedPostingKeychain.readPrivateKeyHex(), !priv.isEmpty
        else { return nil }

        let exp: Int64
        if let v = defaults.object(forKey: "lasko_posting_expires_at_ms") as? Int64 {
            exp = v
        } else if let v = defaults.object(forKey: "lasko_posting_expires_at_ms") as? Int {
            exp = Int64(v)
        } else {
            return nil
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard exp > now + (skewSeconds * 1000) else { return nil }
        return (priv, pub, exp)
    }

    static func signPost(
        content: String,
        tlsAddress: String,
        timestampMs: Int,
        bundleId: String,
        defaults: UserDefaults?
    ) -> Payload? {
        guard let key = loadValidKey(defaults: defaults, tlsAddress: tlsAddress, bundleId: bundleId) else {
            return nil
        }
        let contentHashHex = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
        let canonical = "LASKO_POST|\(contentHashHex)|\(timestampMs)|\(tlsAddress)|\(bundleId)|v1"
        guard let signature = signMessageBase64(canonical, privateKeyHex: key.privHex) else {
            return nil
        }
        return Payload(
            signatureBase64: signature,
            pubkeyCompressedHex: key.pubHex,
            canonicalMessage: canonical
        )
    }

    private static func migrateLegacyAppGroupPrivateKeyIfNeeded(defaults: UserDefaults?) {
        guard SharedPostingKeychain.readPrivateKeyHex() == nil,
              let defaults,
              let legacy = defaults.string(forKey: "lasko_posting_priv_hex"),
              !legacy.isEmpty else { return }
        if SharedPostingKeychain.savePrivateKeyHex(legacy) {
            defaults.removeObject(forKey: "lasko_posting_priv_hex")
            defaults.synchronize()
            print("✅ PostingKeySigner: Migrated posting private key from App Groups → shared Keychain")
        }
    }

    private static func signMessageBase64(_ message: String, privateKeyHex: String) -> String? {
        guard let messageData = message.data(using: .utf8),
              let privKeyData = Data(hexString: privateKeyHex),
              privKeyData.count == 32 else { return nil }
        do {
            let digest = SHA256.hash(data: messageData)
            let privateKey = try LaskoSecp.Signing.PrivateKey(dataRepresentation: privKeyData)
            let signature = try privateKey.signature(for: digest)
            let sigRaw = signature.dataRepresentation
            if sigRaw.count == 64 {
                var out = Data()
                out.append(Data(sigRaw.prefix(32).reversed()))
                out.append(Data(sigRaw.suffix(32).reversed()))
                return out.base64EncodedString()
            }
            return sigRaw.base64EncodedString()
        } catch {
            print("❌ PostingKeySigner: \(error)")
            return nil
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
        guard hex.count % 2 == 0 else { return nil }
        var newData = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard nextIndex <= hex.endIndex else { return nil }
            let byteString = hex[index..<nextIndex]
            guard let num = UInt8(byteString, radix: 16) else { return nil }
            newData.append(num)
            index = nextIndex
        }
        self = newData
    }
}
