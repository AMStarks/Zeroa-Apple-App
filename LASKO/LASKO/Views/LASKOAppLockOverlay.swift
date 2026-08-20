import SwiftUI

struct LASKOAppLockOverlay: View {
    @ObservedObject var controller: LASKOAppLockController

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.12, blue: 0.12)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))

                VStack(spacing: 8) {
                    Text("LASKO is Locked")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Use \(controller.biometryLabel) or your device passcode to continue.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if let errorMessage = controller.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: { controller.unlock() }) {
                    HStack(spacing: 10) {
                        Image(systemName: controller.unlockSystemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text("Unlock")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.6, blue: 0.0),
                                Color(red: 1.0, green: 0.4, blue: 0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        }
        .onAppear {
            controller.unlock()
        }
    }
}
