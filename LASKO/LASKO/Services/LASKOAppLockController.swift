import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
final class LASKOAppLockController: ObservableObject {
    @Published private(set) var isLocked = false
    @Published var errorMessage: String?

    var isEnabled: Bool {
        get { LASKOSecurityPreferences.appLockEnabled }
        set {
            LASKOSecurityPreferences.appLockEnabled = newValue
            if !newValue {
                isLocked = false
                errorMessage = nil
            }
            objectWillChange.send()
        }
    }

    var biometryLabel: String {
        let context = LAContext()
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Device passcode"
        }
    }

    var unlockSystemImage: String {
        let context = LAContext()
        switch context.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "lock.open.fill"
        }
    }

    func deviceAuthenticationAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func lockIfEnabled() {
        guard isEnabled else { return }
        isLocked = true
    }

    func prepareForLaunch() {
        guard isEnabled else {
            isLocked = false
            return
        }
        isLocked = true
    }

    func enableAppLock(completion: @escaping (Bool) -> Void) {
        guard deviceAuthenticationAvailable() else {
            errorMessage = "Device authentication is unavailable on this device."
            completion(false)
            return
        }

        authenticate(reason: "Enable app lock for LASKO") { [weak self] success in
            guard let self else {
                completion(false)
                return
            }
            if success {
                self.isEnabled = true
                self.isLocked = false
                self.errorMessage = nil
            }
            completion(success)
        }
    }

    func unlock() {
        guard isEnabled, isLocked else { return }
        authenticate(reason: "Unlock LASKO") { [weak self] success in
            guard let self else { return }
            if success {
                self.isLocked = false
                self.errorMessage = nil
            }
        }
    }

    private func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            errorMessage = authError?.localizedDescription ?? "Device authentication is unavailable."
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evaluationError in
            Task { @MainActor in
                if success {
                    completion(true)
                } else {
                    self.errorMessage = evaluationError?.localizedDescription ?? "Authentication failed."
                    completion(false)
                }
            }
        }
    }
}
