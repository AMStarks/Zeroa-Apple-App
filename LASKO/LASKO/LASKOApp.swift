import SwiftUI
import UIKit

@main
struct LASKOApp: App {
    @StateObject private var laskoService = LASKOService()
    @StateObject private var authUIState = AuthUIState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(laskoService)
                .environmentObject(authUIState)
                .task {
                    // Pre-warm Halo token to reduce latency for upcoming fetches
                    await laskoService.prewarmHaloTokenIfPossible()
                }
                // Re-enabled deep link callback and foreground listeners
                .onOpenURL { url in
                    // Expecting: lasko://auth/callback
                    guard url.scheme?.lowercased() == "lasko" else { return }
                    if url.host?.lowercased() == "auth", url.path.lowercased().contains("callback") {
                        // Consume any pending response and update UI
                        laskoService.checkForAuthResponse()
                        if laskoService.isAuthenticatedWithZeroa {
                            DispatchQueue.main.async {
                                authUIState.step = .approved
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // When returning from Zeroa, check App Groups for a response
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        laskoService.checkForAuthResponse()
                        if laskoService.isAuthenticatedWithZeroa {
                            authUIState.step = .approved
                        }
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