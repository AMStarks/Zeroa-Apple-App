import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
    private let service = Bundle.main.bundleIdentifier ?? "com.telestai.zeroa"
    
    private let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword
    ]
    
    private func query(for key: String) -> [String: Any] {
        var query = baseQuery
        query[kSecAttrService as String] = service
        query[kSecAttrAccount as String] = key
        return query
    }
    
    private func dataQuery(for key: String) -> [String: Any] {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
    
    @discardableResult
    func save(key: String, value: String, access: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        var query = query(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = access
        query[kSecUseDataProtectionKeychain as String] = true
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("❌ Keychain save failed for \(key): \(status)")
        }
        return status == errSecSuccess
    }
    
    func read(key: String) -> String? {
        let query = dataQuery(for: key)
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    func readSecureItem(key: String) -> String? {
        var query = dataQuery(for: key)
        query[kSecUseOperationPrompt as String] = "Authenticate to view sensitive data"
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            if status != errSecUserCanceled {
                print("❌ Keychain secure read failed for \(key): \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    @discardableResult
    func delete(key: String) -> Bool {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    @discardableResult
    func deleteAll() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
