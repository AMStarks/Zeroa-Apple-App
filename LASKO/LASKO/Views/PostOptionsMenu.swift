import SwiftUI

struct PostOptionsMenu: View {
    let post: Post
    @ObservedObject var laskoService: LASKOService

    @State private var showDeleteConfirm = false
    @State private var showCopiedConfirm = false
    @State private var showReportedConfirm = false
    @State private var showDeleteError = false

    private var isOwnPost: Bool {
        guard let postTLS = post.tlsAddress,
              let currentTLS = laskoService.currentTLSAddress else { return false }
        return postTLS == currentTLS
    }

    var body: some View {
        Menu {
            Button("Copy Post ID") {
                UIPasteboard.general.string = post.id
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCopiedConfirm = true
            }
            Button("Report") {
                Task {
                    let ok = await laskoService.reportPost(post)
                    await MainActor.run {
                        showReportedConfirm = ok
                        if !ok { showDeleteError = true }
                    }
                }
            }
            if isOwnPost {
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    let ok = await laskoService.deletePost(post)
                    if !ok {
                        await MainActor.run { showDeleteError = true }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Copied", isPresented: $showCopiedConfirm) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Post ID copied to clipboard.")
        }
        .alert("Report submitted", isPresented: Binding(
            get: { showReportedConfirm },
            set: { showReportedConfirm = $0 }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thank you. We'll review this post.")
        }
        .alert("Action failed", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {
                laskoService.errorMessage = nil
            }
        } message: {
            Text(laskoService.errorMessage ?? "Something went wrong. Try again.")
        }
    }
}
