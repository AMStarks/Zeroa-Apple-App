import Foundation

enum LASKOSecurityPreferences {
    static let appLockEnabledKey = "lasko_app_lock_enabled"
    static let requireZeroaEachLaunchKey = "lasko_require_zeroa_each_launch"

    static var appLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: appLockEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: appLockEnabledKey) }
    }

    static var requireZeroaEachLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: requireZeroaEachLaunchKey) }
        set { UserDefaults.standard.set(newValue, forKey: requireZeroaEachLaunchKey) }
    }
}
