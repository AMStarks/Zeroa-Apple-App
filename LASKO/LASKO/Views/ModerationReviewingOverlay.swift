import SwiftUI

/// Shown while Charter preflight runs (posts and comments).
struct ModerationReviewingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                Text("Reviewing…")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text("Checking Charter standards")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.75)))
        }
    }
}
