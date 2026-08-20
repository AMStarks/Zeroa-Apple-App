import SwiftUI
import UIKit

@main
struct LASKOApp: App {
    @StateObject private var laskoService = LASKOService()
    @StateObject private var authUIState = AuthUIState()
    @StateObject private var appLockController = LASKOAppLockController()
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(laskoService)
                    .environmentObject(authUIState)
                    .environmentObject(appLockController)

                if appLockController.isLocked {
                    LASKOAppLockOverlay(controller: appLockController)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appLockController.isLocked)
            .task {
                laskoService.prepareSessionForLaunch()
                laskoService.observePostingKeySignals()
                appLockController.prepareForLaunch()
                await laskoService.prewarmHaloTokenIfPossible()
                if laskoService.restoreZeroaSessionFromAppGroups() {
                    authUIState.step = .approved
                }
            }
            .onOpenURL { url in
                guard url.scheme?.lowercased() == "lasko" else { return }
                if url.host?.lowercased() == "auth", url.path.lowercased().contains("callback") {
                    laskoService.checkForAuthResponse()
                    if laskoService.isAuthenticatedWithZeroa {
                        DispatchQueue.main.async {
                            authUIState.step = .approved
                        }
                    }
                }
                if url.host?.lowercased() == "posting-key" {
                    DispatchQueue.main.async {
                        laskoService.needsOpenZeroaToSign = false
                        laskoService.errorMessage = nil
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                appLockController.lockIfEnabled()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    laskoService.syncIdentityWithAppGroups()
                    if laskoService.isAuthenticatedWithZeroa {
                        authUIState.step = .approved
                    } else {
                        laskoService.checkForAuthResponse()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                appLockController.lockIfEnabled()
            }
            .onChange(of: laskoService.isAuthPolling, initial: false) { _, polling in
                if !polling && !laskoService.isAuthenticatedWithZeroa {
                    authUIState.step = .idle
                }
            }
        }
    }
}

enum AuthUIStep {
    case idle
    case waiting
    case approved
}

final class AuthUIState: ObservableObject {
    @Published var step: AuthUIStep = .idle
}
