import SwiftUI

struct LASKOSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var laskoService: LASKOService
    @EnvironmentObject private var appLockController: LASKOAppLockController
    @EnvironmentObject private var authUIState: AuthUIState

    @AppStorage(LASKOSecurityPreferences.appLockEnabledKey) private var appLockEnabled = false
    @AppStorage(LASKOSecurityPreferences.requireZeroaEachLaunchKey) private var requireZeroaEachLaunch = false
    @AppStorage("lasko_push_enabled") private var pushEnabled = true
    @AppStorage("lasko_safe_mode") private var safeMode = true
    @AppStorage("lasko_auto_play_media") private var autoPlayMedia = false

    @State private var showAppLockUnavailableAlert = false
    @State private var isEnablingAppLock = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.15, blue: 0.15)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            Text("Settings")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)

                            Spacer()

                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        sectionHeader("Security")

                        settingsRow(
                            title: "App Lock",
                            subtitle: "Require \(appLockController.biometryLabel) or passcode to open LASKO",
                            isOn: Binding(
                                get: { appLockEnabled },
                                set: { newValue in
                                    if newValue {
                                        enableAppLock()
                                    } else {
                                        appLockEnabled = false
                                        appLockController.isEnabled = false
                                    }
                                }
                            ),
                            isDisabled: isEnablingAppLock
                        )

                        settingsRow(
                            title: "Require Zeroa Each Launch",
                            subtitle: "Do not restore your session automatically when LASKO opens",
                            isOn: $requireZeroaEachLaunch
                        )

                        sectionHeader("General")

                        settingsRow(
                            title: "Push Notifications",
                            subtitle: "Mentions and replies",
                            isOn: $pushEnabled
                        )

                        settingsRow(
                            title: "Safe Mode",
                            subtitle: "Hide sensitive media by default",
                            isOn: $safeMode
                        )

                        settingsRow(
                            title: "Auto-play Media",
                            subtitle: "Play videos and GIFs automatically",
                            isOn: $autoPlayMedia
                        )
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .alert("App Lock Unavailable", isPresented: $showAppLockUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device does not support Face ID, Touch ID, or a device passcode.")
            }
            .onChange(of: requireZeroaEachLaunch, initial: false) { _, enabled in
                guard enabled else { return }
                laskoService.enforceRequireZeroaEachLaunch()
                authUIState.step = .idle
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    private func enableAppLock() {
        guard appLockController.deviceAuthenticationAvailable() else {
            appLockEnabled = false
            showAppLockUnavailableAlert = true
            return
        }

        isEnablingAppLock = true
        appLockController.enableAppLock { success in
            isEnablingAppLock = false
            appLockEnabled = success
            if !success {
                appLockController.isEnabled = false
            }
        }
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                    Text(subtitle)
                        .foregroundColor(.white.opacity(0.75))
                        .font(.system(size: 13))
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .disabled(isDisabled)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(14)
        .padding(.horizontal, 20)
    }
}
