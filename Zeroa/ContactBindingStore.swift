import Foundation
import CryptoKit
import Security

/// Device-local contact binding (LASKO Identity v0 / Phase A).
/// Stores provider + hashed subject only — never seed, never raw email by default.
final class ContactBindingStore {
    static let shared = ContactBindingStore()

    private let defaultsKey = "zeroa_contact_binding_v1"
    private let keychain = KeychainService.shared

    struct Binding: Codable, Equatable {
        let provider: String       // apple | google
        let subjectHash: String    // hex SHA256
        let tlsAddress: String
        let boundAt: TimeInterval
        let displayLabel: String   // "Apple ID" / "Google" — not email
    }

    private init() {}

    func currentBinding() -> Binding? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Binding.self, from: data)
    }

    func isBound() -> Bool { currentBinding() != nil }

    /// Hash stable IdP subject. Never persist the raw subject or email in Phase A defaults.
    static func subjectHash(provider: String, stableSubjectId: String) -> String {
        let material = "zeroa-contact-v1|\(provider)|\(stableSubjectId)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func bind(provider: String, stableSubjectId: String, tlsAddress: String, displayLabel: String) throws {
        let binding = Binding(
            provider: provider,
            subjectHash: Self.subjectHash(provider: provider, stableSubjectId: stableSubjectId),
            tlsAddress: tlsAddress,
            boundAt: Date().timeIntervalSince1970,
            displayLabel: displayLabel
        )
        let data = try JSONEncoder().encode(binding)
        UserDefaults.standard.set(data, forKey: defaultsKey)
        // Mirror flag in keychain for slightly harder casual wipe of defaults alone
        _ = keychain.save(key: "contact_binding_provider", value: provider)
        _ = keychain.save(key: "contact_binding_hash", value: binding.subjectHash)
    }

    func unbind() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        _ = keychain.delete(key: "contact_binding_provider")
        _ = keychain.delete(key: "contact_binding_hash")
    }
}

/// Tracks deferred seed backup (Identity §3). Full Hub-gated ladder comes later.
enum BackupStatusStore {
    private static let incompleteKey = "zeroa_backup_incomplete_v1"
    private static let dismissCountKey = "zeroa_backup_dismiss_count_v1"
    private static let activatedAtKey = "zeroa_backup_prompt_activated_at_v1"

    static var isIncomplete: Bool {
        get { UserDefaults.standard.bool(forKey: incompleteKey) }
        set { UserDefaults.standard.set(newValue, forKey: incompleteKey) }
    }

    static func markCreatedWithoutCeremony() {
        isIncomplete = true
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: activatedAtKey)
        UserDefaults.standard.set(0, forKey: dismissCountKey)
    }

    static func markCeremonyComplete() {
        isIncomplete = false
        UserDefaults.standard.removeObject(forKey: activatedAtKey)
        UserDefaults.standard.set(0, forKey: dismissCountKey)
    }
}
