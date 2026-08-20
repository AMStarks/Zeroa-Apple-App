import Foundation
import UIKit

/// Restore Chief display name + photo into `group.com.tls.zeroa-lasko`
/// after the bundle/App Group rename from `group.com.telestai.zeroa-lasko`.
enum ProfileLegacyMigration {
    /// Bump when re-seeding is required after a failed/partial migrate.
    private static let didRunKey = "zeroa_profile_legacy_migration_v3"
    private static let legacyAppGroup = "group.com.telestai.zeroa-lasko"
    private static let nameKey = "profile_display_name"
    private static let imageKey = "profile_image_data"
    /// Halo-known Chief TLS address (profile source of truth for this restore).
    private static let chiefTLSAddress = "TuQmbKBaw4xFCRoR6eNNXGqy2C76uMEWS9"
    private static let chiefDisplayName = "Chief"

    static func runIfNeeded() {
        let flagStore = UserDefaults.standard
        if flagStore.bool(forKey: didRunKey) { return }

        guard let dest = AppGroupsService.shared.sharedDefaults else {
            print("⚠️ Profile migration: new App Group unavailable")
            return
        }
        dest.synchronize()

        var name = dest.string(forKey: nameKey) ?? ""
        var imageData = dest.data(forKey: imageKey)

        // Best-effort read from legacy App Group (only works if still entitled).
        if let legacy = UserDefaults(suiteName: legacyAppGroup) {
            legacy.synchronize()
            if name.isEmpty || name == "PAAI User",
               let legacyName = legacy.string(forKey: nameKey), !legacyName.isEmpty {
                name = legacyName
                print("✅ Profile migration: name from legacy App Group → \(legacyName)")
            }
            if imageData == nil || imageData?.isEmpty == true,
               let data = legacy.data(forKey: imageKey), !data.isEmpty {
                imageData = data
                print("✅ Profile migration: photo from legacy App Group (\(data.count) bytes)")
            }
            let scopedNameKey = "\(nameKey)_\(chiefTLSAddress)"
            let scopedImageKey = "\(imageKey)_\(chiefTLSAddress)"
            if (name.isEmpty || name == "PAAI User"),
               let scoped = legacy.string(forKey: scopedNameKey), !scoped.isEmpty {
                name = scoped
            }
            if imageData == nil || imageData?.isEmpty == true,
               let scoped = legacy.data(forKey: scopedImageKey), !scoped.isEmpty {
                imageData = scoped
            }
        }

        // Seed from bundled Chief photo when legacy group is inaccessible.
        if name.isEmpty || name == "PAAI User" {
            name = chiefDisplayName
        }
        if imageData == nil || imageData?.isEmpty == true {
            if let url = Bundle.main.url(forResource: "ChiefProfileSeed", withExtension: "jpg"),
               let data = try? Data(contentsOf: url), !data.isEmpty {
                imageData = data
                print("✅ Profile migration: seeded Chief photo (\(data.count) bytes)")
            } else {
                print("⚠️ Profile migration: ChiefProfileSeed.jpg not found in bundle")
            }
        }

        // Write global + TLS-scoped keys so Zeroa UI and LASKO both see them.
        var tlsTargets = Set<String>([chiefTLSAddress])
        if let live = WalletService.shared.loadAddress()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !live.isEmpty {
            tlsTargets.insert(live)
        }
        if let shared = AppGroupsService.shared.getTLSAddress()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shared.isEmpty {
            tlsTargets.insert(shared)
        }

        dest.set(name, forKey: nameKey)
        if let imageData, !imageData.isEmpty {
            dest.set(imageData, forKey: imageKey)
        }
        for tls in tlsTargets {
            dest.set(name, forKey: "\(nameKey)_\(tls)")
            if let imageData, !imageData.isEmpty {
                dest.set(imageData, forKey: "\(imageKey)_\(tls)")
            }
        }

        if AppGroupsService.shared.getTLSAddress() == nil {
            AppGroupsService.shared.storeTLSAddress(chiefTLSAddress)
        }

        dest.synchronize()
        flagStore.set(true, forKey: didRunKey)
        print("✅ Profile migration: wrote \"\(name)\" + photo into group.com.tls.zeroa-lasko for \(tlsTargets.sorted())")
    }
}
