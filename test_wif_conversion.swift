#!/usr/bin/env swift

import Foundation
import CryptoKit

// Test WIF conversion
func testWIFConversion() {
    // Test with a known private key (32 bytes = 64 hex chars)
    let testPrivateKeyHex = "c89242705fa1770a6fbe72c70b11b7300000000000000000000000000000000"
    // Ensure it's exactly 64 characters (32 bytes)
    let paddedHex = String(testPrivateKeyHex.prefix(64))
    guard let privateKeyData = Data(hexString: paddedHex) else {
        print("❌ Failed to create Data from hex")
        return
    }
    
    print("🔍 Testing WIF conversion...")
    print("   Private key (hex): \(testPrivateKeyHex)")
    print("   Private key length: \(privateKeyData.count) bytes")
    
    // Convert to WIF
    let wif = privateKeyToWIF(privateKey: privateKeyData)
    print("   WIF: \(wif)")
    print("   WIF length: \(wif.count) characters")
    
    // Validate WIF format (should be base58, typically 51-52 chars for compressed)
    if wif.count >= 50 && wif.count <= 52 {
        print("✅ WIF length looks correct")
    } else {
        print("⚠️  WIF length unexpected: \(wif.count) (expected 50-52)")
    }
    
    // Check if it's base58 (only contains base58 characters)
    let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    if wif.unicodeScalars.allSatisfy({ base58Chars.contains($0) }) {
        print("✅ WIF contains only base58 characters")
    } else {
        print("❌ WIF contains invalid characters")
    }
}

func privateKeyToWIF(privateKey: Data) -> String {
    let versionByte: UInt8 = 0x80
    let compressionFlag: UInt8 = 0x01
    
    var payload = Data()
    payload.append(versionByte)
    payload.append(privateKey)
    payload.append(compressionFlag)
    
    let hash = Data(SHA256.hash(data: Data(SHA256.hash(data: payload))))
    let checksum = hash.prefix(4)
    payload.append(checksum)
    
    return Base58.encode(payload)
}

// Base58 implementation (simplified)
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

testWIFConversion()

