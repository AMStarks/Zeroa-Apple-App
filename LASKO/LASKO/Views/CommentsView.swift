import SwiftUI

// Maximum comment nesting depth (0 = post, 1 = nest 1, 2 = nest 2)
// To change: update MAX_COMMENT_DEPTH constant below
private let MAX_COMMENT_DEPTH = 2

struct CommentsView: View {
    let postId: String
    let sequentialCode: String?
    @EnvironmentObject var laskoService: LASKOService
    @Environment(\.dismiss) private var dismiss
    @State private var replyText: String = ""
    @State private var isPosting: Bool = false
    @State private var showCommentErrorAlert = false
    @State private var showSubscriptionSheet = false
    @State private var replyingToComment: Post? = nil
    @State private var selectedPostID: String? = nil
    @State private var showSuccessMessage: Bool = false
    @State private var expandedComments: Set<String> = [] // Track which comments are expanded
    @State private var commentHistory: [Post] = [] // Track navigation history for promoted comments
    @State private var promotedComment: Post? = nil // Track which comment is promoted to top
    
    private func formatTimestamp(_ date: Date) -> String {
        // Guard against invalid dates
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        guard timeInterval.isFinite && !timeInterval.isNaN,
              date.timeIntervalSince1970.isFinite && !date.timeIntervalSince1970.isNaN else {
            return "now"
        }
        
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now)
    }

    private func expandVisibleCommentBranches(for code: String) {
        guard let replies = laskoService.repliesByCode[code], !replies.isEmpty else { return }
        let parentIdsWithChildren = Set(replies.compactMap { reply -> String? in
            guard let parentCode = reply.parentCode, parentCode != code else { return nil }
            return parentCode
        })
        expandedComments.formUnion(parentIdsWithChildren)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Original post or promoted comment at the top
                    if let promoted = promotedComment {
                        // Show promoted comment as the main post
                        VStack(alignment: .leading, spacing: 12) {
                            // Removed redundant "Back to post" button - navigation bar handles this
                            Spacer()
                            
                            // Promoted comment as main post
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(laskoService.feedDisplayName(for: promoted))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(LASKDesignSystem.Colors.text)
                                    Spacer()
                                    Text(formatTimestamp(promoted.timestamp))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                }
                                
                                Text(promoted.content)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(LASKDesignSystem.Colors.text)
                                    .multilineTextAlignment(.leading)
                                
                                // Action buttons for promoted comment (ensure full set of icons)
                                HStack(spacing: 12) {
                                    // Reply
                                    Button(action: {
                                        replyingToComment = promoted
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrowshape.turn.up.left")
                                                .font(.system(size: 12))
                                            Text("Reply")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    // Broadcast
                                    Button(action: {}) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "megaphone")
                                                .font(.system(size: 12))
                                                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                            Text("0")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    // Fire
                                    Button(action: {}) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "flame")
                                                .font(.system(size: 12))
                                                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                            Text("0")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    // TLS
                                    TelestaiRewardActionButton(post: promoted, laskoService: laskoService)
                                        .scaleEffect(0.8)

                                    Spacer()

                                    // Three dots button
                                    Button(action: {
                                        UIPasteboard.general.string = promoted.id
                                        selectedPostID = promoted.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            if selectedPostID == promoted.id {
                                                selectedPostID = nil
                                            }
                                        }
                                    }) {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 12))
                                            .foregroundColor(selectedPostID == promoted.id ? .orange : LASKDesignSystem.Colors.textSecondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(LASKDesignSystem.Colors.postSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(LASKDesignSystem.Colors.primary.opacity(0.8), lineWidth: 1)
                            )
                            .padding(.horizontal, 14)
                        }
                    } else if let originalPost = laskoService.posts.first(where: { $0.id == postId }) {
                        OriginalPostCard(post: originalPost)
                            .padding(.vertical, 16)
                    }
                    
                    // Success/Error messages
                    if showSuccessMessage {
                        Text("Comment posted successfully!")
                            .foregroundColor(.green)
                            .padding()
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showSuccessMessage = false
                                }
                            }
                    }
                    
                    if let code = sequentialCode, let replies = laskoService.repliesByCode[code], !replies.isEmpty {
                        if let promoted = promotedComment {
                            // Show replies to the promoted comment as top-level comments
                            // Ensure chronological ordering (oldest first like the post view)
                            // Enforce chronological ordering strictly (oldest first)
                            let threadReplies = laskoService.repliesByCode[code] ?? []
                            let promotedReplies = threadReplies
                                .filter { ($0.parentCode ?? "") == promoted.id }
                                .sorted { $0.timestamp < $1.timestamp }
                            
                            if !promotedReplies.isEmpty {
                                // Add gap between top post and first comment
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 16)
                                
                                ForEach(Array(promotedReplies.enumerated()), id: \.element.id) { index, reply in
                                    CommentRow(
                                        comment: reply,
                                        all: threadReplies,
                                        depth: 0, // Always top-level when promoted
                                        postId: postId,
                                        replyingToComment: $replyingToComment,
                                        selectedPostID: $selectedPostID,
                                        expandedComments: $expandedComments,
                                        promotedComment: $promotedComment,
                                        commentHistory: $commentHistory
                                    )
                                    .environmentObject(laskoService)
                                    
                                    // Add spacer gap between comments (except after the last one)
                                    if index < promotedReplies.count - 1 {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(height: 8)
                                    }
                                }
                            } else {
                                Text("No replies to this comment yet.")
                                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                    .padding()
                            }
                        } else {
                            // Show original post's top-level comments
                            // Ensure chronological ordering for top-level replies
                            let topLevel = replies.filter { reply in
                                let parentCode = reply.parentCode ?? ""
                                return parentCode.isEmpty || parentCode == code
                            }.sorted { $0.timestamp < $1.timestamp }
                            
                            if !topLevel.isEmpty {
                                HStack {
                                    Text("Replies")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                    Spacer()
                                    Text("\(replies.count) total")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 14)
                                
                                // Add gap between top post and first comment
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 16)
                                
                                ForEach(Array(topLevel.enumerated()), id: \.element.id) { index, reply in
                                    CommentRow(
                                        comment: reply, 
                                        all: replies, 
                                        depth: 0,
                                        postId: postId,
                                        replyingToComment: $replyingToComment,
                                        selectedPostID: $selectedPostID,
                                        expandedComments: $expandedComments,
                                        promotedComment: $promotedComment,
                                        commentHistory: $commentHistory
                                    )
                                    .environmentObject(laskoService)
                                    
                                    // Add spacer gap between comments (except after the last one)
                                    if index < topLevel.count - 1 {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(height: 8)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("No replies yet.")
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            .padding()
                    }
                }
                .padding(.bottom, 100) // Extra padding for composer
            }
            .background(LASKDesignSystem.Colors.background)
            // Subscription sheet removed - posting is now free

            // Composer at bottom
            VStack(spacing: 8) {
                if let replyingTo = replyingToComment {
                    HStack {
                        Text("Replying to \(replyingTo.author)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(LASKDesignSystem.Colors.primary)
                        Spacer()
                        Button("Cancel") {
                            replyingToComment = nil
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                }
                
                HStack(spacing: 8) {
                    TextField(replyingToComment != nil ? "Write a reply…" : "Write a comment…", text: $replyText)
                        .textFieldStyle(.roundedBorder)
                        .background(LASKDesignSystem.Colors.cardBackground.opacity(0.3))
                        .cornerRadius(8)
                        .disabled(isPosting || laskoService.isReviewingContent)
                    
                    Button(commentComposerButtonTitle) {
                        Task { await postReply() }
                    }
                    .disabled(isPosting || laskoService.isReviewingContent || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(LASKDesignSystem.Colors.primary)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(LASKDesignSystem.Colors.cardBackground)
        }
        .background(LASKDesignSystem.Colors.background)
        .overlay {
            if laskoService.isReviewingContent {
                ModerationReviewingOverlay()
            }
        }
        .alert("Reissue posting signature", isPresented: Binding(
            get: { showCommentErrorAlert && laskoService.needsOpenZeroaToSign },
            set: { if !$0 {
                showCommentErrorAlert = false
                laskoService.errorMessage = nil
                laskoService.needsOpenZeroaToSign = false
            } }
        )) {
            Button("Open Zeroa") {
                laskoService.openZeroaToFinishSigning()
                showCommentErrorAlert = false
                laskoService.errorMessage = nil
            }
            Button("Cancel", role: .cancel) {
                showCommentErrorAlert = false
                laskoService.errorMessage = nil
                laskoService.needsOpenZeroaToSign = false
            }
        } message: {
            Text(laskoService.errorMessage ?? "Your posting signature expired. Tap Open Zeroa to reissue for another hour.")
        }
        .alert("Unable to post", isPresented: Binding(
            get: { showCommentErrorAlert && !laskoService.needsOpenZeroaToSign },
            set: { if !$0 {
                showCommentErrorAlert = false
                laskoService.errorMessage = nil
            } }
        )) {
            Button("OK", role: .cancel) {
                showCommentErrorAlert = false
                laskoService.errorMessage = nil
            }
        } message: {
            Text(laskoService.errorMessage ?? "Failed to post reply")
        }
        .onAppear {
            if let code = sequentialCode {
                Task {
                    await laskoService.fetchComments(forSequentialCode: code)
                    await MainActor.run {
                        expandVisibleCommentBranches(for: code)
                    }
                }
            }
            // Initialize navigation history with the original post as the first level
            if let originalPost = laskoService.posts.first(where: { $0.id == postId }) {
                commentHistory = [originalPost]
            }
        }
    }

    private var commentComposerButtonTitle: String {
        if laskoService.isReviewingContent { return "Reviewing…" }
        if isPosting { return "Posting…" }
        return "Post"
    }

    private func postReply() async {
        guard !isPosting else { return }
        isPosting = true
        defer { isPosting = false }
        
        print("🔍 CommentsView: Starting to post reply")
        print("🔍 CommentsView: Reply text: '\(replyText)'")
        print("🔍 CommentsView: Replying to comment: \(replyingToComment?.id ?? "main post")")
        
        if let replyingTo = replyingToComment {
            // Reply to a specific comment
            print("🔍 CommentsView: Posting reply to comment \(replyingTo.id)")
            let ok = await laskoService.createComment(
                content: replyText,
                parentSequentialCode: replyingTo.id,
                threadRootCode: sequentialCode ?? postId
            )
            if ok { 
                print("✅ CommentsView: Reply posted successfully")
                await laskoService.fetchComments(forSequentialCode: sequentialCode ?? "")
                await MainActor.run {
                    expandVisibleCommentBranches(for: sequentialCode ?? "")
                }
                replyText = ""
                replyingToComment = nil
                laskoService.errorMessage = nil
                showSuccessMessage = true
            } else {
                print("❌ CommentsView: Failed to post reply")
                showCommentErrorAlert = true
            }
        } else if let code = sequentialCode {
            // Reply to the main post
            print("🔍 CommentsView: Posting reply to main post \(code)")
            let ok = await laskoService.createComment(content: replyText, parentSequentialCode: code, threadRootCode: code)
            if ok { 
                print("✅ CommentsView: Reply posted successfully")
                await laskoService.fetchComments(forSequentialCode: code)
                await MainActor.run {
                    expandVisibleCommentBranches(for: code)
                }
                replyText = ""
                laskoService.errorMessage = nil
                showSuccessMessage = true
            } else {
                print("❌ CommentsView: Failed to post reply")
                showCommentErrorAlert = true
            }
        }
    }
}

struct OriginalPostCard: View {
    let post: Post
    @EnvironmentObject var laskoService: LASKOService
    @State private var likesCount: Int = 0
    @State private var broadcastCount: Int = 0
    @State private var selectedPostID: String? = nil

    private var userLiked: Bool {
        _ = laskoService.userActionStateVersion
        return laskoService.hasUserLikedPost(post.id)
    }

    private var userAnnounced: Bool {
        _ = laskoService.userActionStateVersion
        return laskoService.hasUserAnnouncedPost(post.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post header
                HStack(spacing: 8) {
                    ThreadAvatar(post: post, size: 24)
                        .environmentObject(laskoService)
                Text(laskoService.feedDisplayName(for: post))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(LASKDesignSystem.Colors.text)
                Spacer()
                Text(formatTimestamp(post.timestamp))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
            }
            
            // Post content
            Text(post.content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(LASKDesignSystem.Colors.text)
                .multilineTextAlignment(.leading)
            
            // Action bar with functionality
            let _ = laskoService.userActionStateVersion
            HStack(spacing: 16) {
                // Comment button (non-functional in this view)
                HStack(spacing: 4) {
                    Image(systemName: "message")
                        .font(.system(size: 14))
                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    Text("\(post.replies)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                }
                
                // Broadcast button — tap again to un-announce
                Button(action: {
                    Task {
                        if userAnnounced {
                            if broadcastCount > 0 { broadcastCount -= 1 }
                        } else {
                            broadcastCount += 1
                        }
                        await laskoService.announcePost(post)
                        if let updated = laskoService.posts.first(where: { $0.id == post.id }) {
                            broadcastCount = updated.broadcastCount
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "megaphone")
                            .font(.system(size: 14))
                            .foregroundColor(userAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                        Text("\(broadcastCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(userAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Fire/like button
                Button(action: {
                    guard !userLiked else { return }
                    likesCount += 1
                    Task { await laskoService.likePost(post) }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: userLiked ? "flame.fill" : "flame")
                            .font(.system(size: 14))
                            .foregroundColor(userLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                        Text("\(likesCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(userLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // TLS button - using the proper component
                TelestaiRewardActionButton(post: post, laskoService: laskoService)
                
                Spacer()
                
                // Three dots button
                Button(action: {
                    UIPasteboard.general.string = post.id
                    selectedPostID = post.id
                    // Reset selection after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if selectedPostID == post.id {
                            selectedPostID = nil
                        }
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(selectedPostID == post.id ? .orange : LASKDesignSystem.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LASKDesignSystem.Colors.postSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(LASKDesignSystem.Colors.primary.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .onAppear {
            likesCount = post.likes
            broadcastCount = post.broadcastCount
        }
        .onChange(of: laskoService.userActionStateVersion, initial: false) { _, _ in
            likesCount = post.likes
            broadcastCount = post.broadcastCount
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        // Guard against invalid dates
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        guard timeInterval.isFinite && !timeInterval.isNaN,
              date.timeIntervalSince1970.isFinite && !date.timeIntervalSince1970.isNaN else {
            return "now"
        }
        
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now)
    }
}

struct CommentRow: View {
    let comment: Post
    let all: [Post]
    let depth: Int
    let postId: String
    @Binding var replyingToComment: Post?
    @Binding var selectedPostID: String?
    @Binding var expandedComments: Set<String>
    @Binding var promotedComment: Post?
    @Binding var commentHistory: [Post]
    @EnvironmentObject var laskoService: LASKOService
    @State private var likesCount: Int = 0
    @State private var broadcastCount: Int = 0

    private var userLiked: Bool {
        _ = laskoService.userActionStateVersion
        return laskoService.hasUserLikedPost(comment.id)
    }

    private var userAnnounced: Bool {
        _ = laskoService.userActionStateVersion
        return laskoService.hasUserAnnouncedPost(comment.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Vertical connection line for nested comments
                if depth > 0 {
                    Rectangle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 2)
                        .padding(.leading, CGFloat((depth - 1) * 8) + 4)
                        .offset(x: -4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Comment header with username and timestamp
                    HStack(spacing: 8) {
                        ThreadAvatar(post: comment, size: 22)
                            .environmentObject(laskoService)
                        Text(laskoService.feedDisplayName(for: comment))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                        Spacer()
                        Text(formatTimestamp(comment.timestamp))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    }
                    
                    // Comment content
                    Text(comment.content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(LASKDesignSystem.Colors.text)
                        .multilineTextAlignment(.leading)
                    
                    // Action buttons with functionality
                    let _ = laskoService.userActionStateVersion
                    HStack(spacing: 12) {
                        // Reply button
                        Button(action: {
                            replyingToComment = comment
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 12))
                                Text("Reply")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Broadcast button — tap again to un-announce
                        Button(action: {
                            Task {
                                if userAnnounced {
                                    if broadcastCount > 0 { broadcastCount -= 1 }
                                } else {
                                    broadcastCount += 1
                                }
                                await laskoService.announcePost(comment)
                                if let updated = laskoService.repliesByCode[postId]?.first(where: { $0.id == comment.id }) {
                                    broadcastCount = updated.broadcastCount
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "megaphone")
                                    .font(.system(size: 12))
                                    .foregroundColor(userAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                                Text("\(broadcastCount)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(userAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Fire/like button
                        Button(action: {
                            guard !userLiked else { return }
                            likesCount += 1
                            Task { await laskoService.likePost(comment) }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: userLiked ? "flame.fill" : "flame")
                                    .font(.system(size: 12))
                                    .foregroundColor(userLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                                Text("\(likesCount)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(userLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // TLS button - using the proper component
                        TelestaiRewardActionButton(post: comment, laskoService: laskoService)
                            .scaleEffect(0.8) // Make it smaller for comments
                        
                        // Expand nested replies from the flat thread list returned by Halo.
                        let children = all
                            .filter { ($0.parentCode ?? "") == comment.id }
                            .sorted { $0.timestamp < $1.timestamp }
                        let isExpanded = expandedComments.contains(comment.id)
                        if !children.isEmpty && depth < MAX_COMMENT_DEPTH {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if isExpanded {
                                        expandedComments.remove(comment.id)
                                    } else {
                                        expandedComments.insert(comment.id)
                                    }
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10))
                                    Text(isExpanded ? "hide \(children.count)" : "show \(children.count) replies")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if !children.isEmpty {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if let currentPromoted = promotedComment {
                                        commentHistory.append(currentPromoted)
                                    } else if let originalPost = laskoService.posts.first(where: { $0.id == postId }) {
                                        commentHistory.append(originalPost)
                                    }
                                    promotedComment = comment
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 10))
                                    Text("open thread")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                        
                        // Three dots button
                        Button(action: {
                            UIPasteboard.general.string = comment.id
                            selectedPostID = comment.id
                            // Reset selection after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if selectedPostID == comment.id {
                                    selectedPostID = nil
                                }
                            }
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .foregroundColor(selectedPostID == comment.id ? .orange : LASKDesignSystem.Colors.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.leading, CGFloat(depth * 8))
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(depth == 0 ? LASKDesignSystem.Colors.postSurface : LASKDesignSystem.Colors.nestedPostSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(LASKDesignSystem.Colors.primary.opacity(depth == 0 ? 0.75 : 0.55), lineWidth: 1)
            )
            .padding(.horizontal, depth == 0 ? 14 : 0)

            let nestedChildren = all
                .filter { ($0.parentCode ?? "") == comment.id }
                .sorted { $0.timestamp < $1.timestamp }
            if expandedComments.contains(comment.id) && depth < MAX_COMMENT_DEPTH {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(nestedChildren) { child in
                        CommentRow(
                            comment: child,
                            all: all,
                            depth: depth + 1,
                            postId: postId,
                            replyingToComment: $replyingToComment,
                            selectedPostID: $selectedPostID,
                            expandedComments: $expandedComments,
                            promotedComment: $promotedComment,
                            commentHistory: $commentHistory
                        )
                        .environmentObject(laskoService)
                    }
                }
                .padding(.leading, 8)
            }
        }
        .onAppear {
            likesCount = comment.likes
            broadcastCount = comment.broadcastCount
        }
        .onChange(of: laskoService.userActionStateVersion, initial: false) { _, _ in
            likesCount = comment.likes
            broadcastCount = comment.broadcastCount
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        // Guard against invalid dates
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        guard timeInterval.isFinite && !timeInterval.isNaN,
              date.timeIntervalSince1970.isFinite && !date.timeIntervalSince1970.isNaN else {
            return "now"
        }
        
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now)
    }
    

}

private struct ThreadAvatar: View {
    let post: Post
    let size: CGFloat
    @EnvironmentObject var laskoService: LASKOService

    var body: some View {
        Group {
            if let image = resolvedImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [LASKDesignSystem.Colors.primary, LASKDesignSystem.Colors.primaryDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(String(laskoService.feedDisplayName(for: post).prefix(1)).uppercased())
                        .font(.system(size: max(10, size * 0.42), weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func resolvedImage() -> UIImage? {
        if let postTLS = post.tlsAddress,
           let currentTLS = laskoService.currentTLSAddress,
           postTLS == currentTLS,
           let image = AppGroupsService.shared.getProfileImage(for: currentTLS) {
            return image
        }
        if let avatarURL = post.avatarURL,
           avatarURL.hasPrefix("data:image"),
           let base64 = avatarURL.components(separatedBy: ",").last,
           let data = Data(base64Encoded: base64),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}
