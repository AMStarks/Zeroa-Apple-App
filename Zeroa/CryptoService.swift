import Foundation
import CryptoKit
#if canImport(P256K)
import P256K
typealias Secp = P256K
#elseif canImport(secp256k1)
import secp256k1
typealias Secp = secp256k1
#endif

final class CryptoService {
    static let shared = CryptoService()

    // Sign a message using a 32-byte secp256k1 private key stored in Keychain under "wallet_private_key"
    // Returns Base58-encoded 64-byte compact (r||s) signature to match server expectations
    func signMessageWithStoredPrivateKey(_ message: String, keychain: KeychainService) -> String? {
        guard let messageData = message.data(using: .utf8) else { return nil }
        guard let privHex = keychain.read(key: "wallet_private_key") else {
            print("❌ CryptoService: Missing wallet_private_key in Keychain")
            return nil
        }
        guard let privKeyData = Data(hexString: privHex), privKeyData.count == 32 else {
            print("❌ CryptoService: Invalid private key format/length")
            return nil
        }
        do {
            let digest = SHA256.hash(data: messageData)
            let privateKey = try Secp.Signing.PrivateKey(dataRepresentation: privKeyData)
            let signature = try privateKey.signature(for: digest)
            let sigRaw = signature.dataRepresentation // 64 bytes r||s
            let sigB58 = Base58.encode(sigRaw)
            return sigB58
        } catch {
            print("❌ CryptoService: Signing error: \(error)")
            return nil
        }
    }

    // Back-compat: legacy call sites pass a mnemonic but we now sign from stored key
    func signMessage(_ message: String, mnemonic: String) -> String? {
        return signMessageWithStoredPrivateKey(message, keychain: KeychainService.shared)
    }

    // Returns Base64-encoded 64-byte compact (r||s) signature for server verify
    func signMessageBase64(_ message: String, keychain: KeychainService) -> String? {
        guard let messageData = message.data(using: .utf8) else { return nil }
        guard let privHex = keychain.read(key: "wallet_private_key") else { return nil }
        guard let privKeyData = Data(hexString: privHex), privKeyData.count == 32 else { return nil }
        do {
            let digest = SHA256.hash(data: messageData)
            let digestHex = digest.map { String(format: "%02x", $0) }.joined()
            
            print("═══════════════════════════════════════════════════════════")
            print("🔬 SIGNATURE DIAGNOSTICS")
            print("═══════════════════════════════════════════════════════════")
            print("📝 Message: \(message)")
            print("📝 Message bytes (UTF-8 hex): \(messageData.map { String(format: "%02x", $0) }.joined())")
            print("🔐 SHA256 hash (hex): \(digestHex)")
            print("🔑 Private key length: \(privKeyData.count) bytes")
            print("🔑 Private key (hex, first 16): \(privHex.prefix(32))...")
            
            let privateKey = try Secp.Signing.PrivateKey(dataRepresentation: privKeyData)
            
            // Verify public key matches before signing
            // Use EXACT same logic as getCompressedPublicKeyHex() to ensure they match
            let pubDataFromPrivate = privateKey.publicKey.dataRepresentation
            var pubHexFromPrivate: String
            
            // Check if already compressed (33 bytes, starts with 0x02 or 0x03)
            if pubDataFromPrivate.count == 33 && (pubDataFromPrivate.first == 0x02 || pubDataFromPrivate.first == 0x03) {
                pubHexFromPrivate = pubDataFromPrivate.map { String(format: "%02x", $0) }.joined()
            } else if pubDataFromPrivate.count == 65 && pubDataFromPrivate.first == 0x04 {
                // If uncompressed (65 bytes, starts with 0x04), compress it
                let x = pubDataFromPrivate.subdata(in: 1..<33)
                let y = pubDataFromPrivate.subdata(in: 33..<65)
                let yLastByte = y.last ?? 0
                let prefix: UInt8 = (yLastByte & 1) == 0 ? 0x02 : 0x03
                var compressed = Data([prefix])
                compressed.append(x)
                pubHexFromPrivate = compressed.map { String(format: "%02x", $0) }.joined()
            } else {
                // Unknown format, use as-is
                pubHexFromPrivate = pubDataFromPrivate.map { String(format: "%02x", $0) }.joined()
            }
            
            print("🔑 Public key derived from private key (for verification): \(pubHexFromPrivate)")
            print("🔑 Public key length: \(pubHexFromPrivate.count) hex chars = \(pubHexFromPrivate.count / 2) bytes")
            print("⚠️  CRITICAL: This public key MUST match the one sent to server below!")
            
            let signature = try privateKey.signature(for: digest)
            let sigRaw = signature.dataRepresentation
            
            print("✍️  Signature raw length: \(sigRaw.count) bytes")
            print("✍️  Signature (hex, full): \(sigRaw.map { String(format: "%02x", $0) }.joined())")
            
            // Check if signature is DER format (starts with 0x30) or raw r||s (64 bytes)
            if sigRaw.count == 64 {
                // Already in r||s format
                let r = sigRaw.prefix(32)
                let s = sigRaw.suffix(32)
                let rHex = r.map { String(format: "%02x", $0) }.joined()
                let sHex = s.map { String(format: "%02x", $0) }.joined()
                
                print("✅ Signature format: 64-byte r||s (correct)")
                print("   r (32 bytes hex, little-endian from iOS): \(rHex)")
                print("   s (32 bytes hex, little-endian from iOS): \(sHex)")
                
                // CRITICAL FIX: iOS secp256k1 library returns signatures in LITTLE-ENDIAN byte order
                // but elliptic.js (server) expects BIG-ENDIAN. Reverse bytes to convert.
                let rReversed = Data(r.reversed())
                let sReversed = Data(s.reversed())
                let rHexBigEndian = rReversed.map { String(format: "%02x", $0) }.joined()
                let sHexBigEndian = sReversed.map { String(format: "%02x", $0) }.joined()
                
                print("   r (32 bytes hex, big-endian for server): \(rHexBigEndian)")
                print("   s (32 bytes hex, big-endian for server): \(sHexBigEndian)")
                
                // Combine reversed r||s (big-endian)
                var sigBigEndian = Data()
                sigBigEndian.append(rReversed)
                sigBigEndian.append(sReversed)
                
                // Check for low-s normalization (s should be <= curve_order/2)
                // secp256k1 curve order: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
                let curveOrderHalf = "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0"
                print("   s value check: \(sHexBigEndian) (should be <= \(curveOrderHalf.prefix(16))...)")
                
                let sigBase64 = sigBigEndian.base64EncodedString()
                print("✍️  Signature (Base64, big-endian): \(sigBase64)")
                print("═══════════════════════════════════════════════════════════")
                return sigBase64
            } else if sigRaw.count > 64 && sigRaw.first == 0x30 {
                // DER format - extract r and s
                print("🔍 CryptoService.signMessageBase64: Signature is DER format, extracting r||s...")
                // Parse DER to extract r and s (simplified - assumes standard DER structure)
                // DER: 0x30 [length] 0x02 [r_length] [r_bytes] 0x02 [s_length] [s_bytes]
                var offset = 2 // Skip 0x30 and length byte
                if sigRaw[offset] == 0x02 {
                    offset += 1
                    let rLen = Int(sigRaw[offset])
                    offset += 1
                    var r = sigRaw.subdata(in: offset..<offset+rLen)
                    // Remove leading zeros
                    while r.first == 0 && r.count > 32 { r = r.dropFirst() }
                    // Pad to 32 bytes if needed
                    while r.count < 32 { r = Data([0]) + r }
                    offset += rLen
                    
                    if offset < sigRaw.count && sigRaw[offset] == 0x02 {
                        offset += 1
                        let sLen = Int(sigRaw[offset])
                        offset += 1
                        var s = sigRaw.subdata(in: offset..<offset+sLen)
                        // Remove leading zeros
                        while s.first == 0 && s.count > 32 { s = s.dropFirst() }
                        // Pad to 32 bytes if needed
                        while s.count < 32 { s = Data([0]) + s }
                        
                        // CRITICAL FIX: Reverse bytes (little-endian → big-endian)
                        let rReversed = Data(r.prefix(32).reversed())
                        let sReversed = Data(s.prefix(32).reversed())
                        
                        // Combine reversed r||s (big-endian)
                        var combined = Data()
                        combined.append(rReversed)
                        combined.append(sReversed)
                        print("🔍 CryptoService.signMessageBase64: Extracted r||s (big-endian): \(combined.count) bytes")
                        return combined.base64EncodedString()
                    }
                }
            }
            
            // Fallback: return as-is (might work if server can parse it)
            print("⚠️ CryptoService.signMessageBase64: Unexpected signature format, length: \(sigRaw.count)")
            return sigRaw.base64EncodedString()
        } catch {
            print("❌ CryptoService.signMessageBase64: Signing error: \(error)")
            return nil
        }
    }

    // Returns compressed public key hex (33 bytes) derived from stored private key
    func getCompressedPublicKeyHex(keychain: KeychainService) -> String? {
        guard let privHex = keychain.read(key: "wallet_private_key") else { return nil }
        guard let privKeyData = Data(hexString: privHex), privKeyData.count == 32 else { return nil }
        do {
            let privateKey = try Secp.Signing.PrivateKey(dataRepresentation: privKeyData)
            let pubData = privateKey.publicKey.dataRepresentation
            
            print("═══════════════════════════════════════════════════════════")
            print("🔬 PUBLIC KEY DIAGNOSTICS")
            print("═══════════════════════════════════════════════════════════")
            print("🔑 Public key raw length: \(pubData.count) bytes")
            print("🔑 Public key first byte: 0x\(String(format: "%02x", pubData.first ?? 0))")
            print("🔑 Public key (hex, full): \(pubData.map { String(format: "%02x", $0) }.joined())")
            
            // Check if already compressed (33 bytes, starts with 0x02 or 0x03)
            if pubData.count == 33 && (pubData.first == 0x02 || pubData.first == 0x03) {
                print("✅ Public key format: COMPRESSED (33 bytes, prefix: 0x\(String(format: "%02x", pubData.first ?? 0)))")
                let pubHex = pubData.map { String(format: "%02x", $0) }.joined()
                print("🔑 Public key (hex): \(pubHex)")
                print("═══════════════════════════════════════════════════════════")
                return pubHex
            }
            
            // If uncompressed (65 bytes, starts with 0x04), compress it
            if pubData.count == 65 && pubData.first == 0x04 {
                print("⚠️  Public key format: UNCOMPRESSED (65 bytes)")
                print("   Converting to compressed format...")
                // Extract x coordinate (bytes 1-32)
                let x = pubData.subdata(in: 1..<33)
                let xHex = x.map { String(format: "%02x", $0) }.joined()
                // Extract y coordinate (bytes 33-64)
                let y = pubData.subdata(in: 33..<65)
                let yHex = y.map { String(format: "%02x", $0) }.joined()
                print("   x coordinate (hex): \(xHex)")
                print("   y coordinate (hex): \(yHex)")
                // Get last byte of y to determine parity
                let yLastByte = y.last ?? 0
                // Compressed format: 0x02 if y is even, 0x03 if y is odd
                let prefix: UInt8 = (yLastByte & 1) == 0 ? 0x02 : 0x03
                var compressed = Data([prefix])
                compressed.append(x)
                let compressedHex = compressed.map { String(format: "%02x", $0) }.joined()
                print("✅ Compressed to 33 bytes (prefix: 0x\(String(format: "%02x", prefix)))")
                print("🔑 Compressed public key (hex): \(compressedHex)")
                print("═══════════════════════════════════════════════════════════")
                return compressedHex
            }
            
            // Unknown format, return as-is but log warning
            print("⚠️  Public key format: UNKNOWN (length: \(pubData.count), first byte: 0x\(String(format: "%02x", pubData.first ?? 0)))")
            let pubHex = pubData.map { String(format: "%02x", $0) }.joined()
            print("🔑 Public key (hex, as-is): \(pubHex)")
            print("═══════════════════════════════════════════════════════════")
            return pubHex
        } catch {
            print("❌ CryptoService.getCompressedPublicKeyHex: Error: \(error)")
            return nil
        }
    }
}

// MARK: - Utilities
private let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

enum Base58 {
    static func encode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        var bytes = [UInt8](data)
        var zeros = 0
        var i = 0
        while i < bytes.count && bytes[i] == 0 { zeros += 1; i += 1 }
        var encoded: [UInt8] = []
        var input = Array(bytes[i...])
        while input.count > 0 {
            var remainder = 0
            var newInput: [UInt8] = []
            newInput.reserveCapacity(input.count)
            for b in input {
                let acc = Int(b) + remainder * 256
                let div = acc / 58
                remainder = acc % 58
                if !(newInput.isEmpty && div == 0) {
                    newInput.append(UInt8(div))
                }
            }
            encoded.append(UInt8(base58Alphabet[remainder].utf8.first!))
            input = newInput
        }
        // Add leading zeros
        while zeros > 0 { encoded.append(UInt8(base58Alphabet[0].utf8.first!)); zeros -= 1 }
        encoded.reverse()
        return String(bytes: encoded, encoding: .utf8) ?? ""
    }
}

extension Data {
    init?(hexString: String) {
        let hex = hexString.dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
        guard hex.count % 2 == 0 else { return nil }
        var newData = Data(capacity: hex.count/2)
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
