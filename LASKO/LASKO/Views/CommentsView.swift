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
    @State private var error: String?
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
                                    Text(laskoService.getDisplayName(for: promoted.author))
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
                            // Lighter grey for top promoted card to reinforce hierarchy (exactly match post view)
                            .background(Color.white.opacity(0.05))
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
                    
                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    if let code = sequentialCode, let replies = laskoService.repliesByCode[code], !replies.isEmpty {
                        if let promoted = promotedComment {
                            // Show replies to the promoted comment as top-level comments
                            // Ensure chronological ordering (oldest first like the post view)
                            // Enforce chronological ordering strictly (oldest first)
                            let promotedReplies = (laskoService.repliesByCode[promoted.id] ?? []).sorted { $0.timestamp < $1.timestamp }
                            
                            if !promotedReplies.isEmpty {
                                // Add gap between top post and first comment
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 16)
                                
                                ForEach(Array(promotedReplies.enumerated()), id: \.element.id) { index, reply in
                                    CommentRow(
                                        comment: reply,
                                        all: promotedReplies,
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

            // Composer at bottom
            VStack(spacing: 8) {
                if let replyingTo = replyingToComment {
                    HStack {
                        Text("Replying to \(laskoService.getDisplayName(for: replyingTo.author))")
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
                    
                    Button(isPosting ? "Posting…" : "Post") {
                        Task { await postReply() }
                    }
                    .disabled(isPosting || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .onAppear {
            if let code = sequentialCode {
                Task { await laskoService.fetchComments(forSequentialCode: code) }
            }
            // Initialize navigation history with the original post as the first level
            if let originalPost = laskoService.posts.first(where: { $0.id == postId }) {
                commentHistory = [originalPost]
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("< Back") {
                    if promotedComment != nil {
                        // We're currently viewing a promoted comment, go back to previous level
                        if !commentHistory.isEmpty {
                            promotedComment = commentHistory.removeLast()
                        } else {
                            // No more history, go back to main feed
                            dismiss()
                        }
                    } else {
                        // We're viewing the original post, go back to main feed
                        dismiss()
                    }
                }
                .foregroundColor(LASKDesignSystem.Colors.primary)
            }
        }
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
            let ok = await laskoService.createComment(content: replyText, parentSequentialCode: replyingTo.id)
            if ok { 
                print("✅ CommentsView: Reply posted successfully")
                await laskoService.fetchComments(forSequentialCode: sequentialCode ?? "")
                replyText = ""
                replyingToComment = nil
                error = nil
                showSuccessMessage = true
            } else { 
                print("❌ CommentsView: Failed to post reply")
                error = "Failed to post reply" 
            }
        } else if let code = sequentialCode {
            // Reply to the main post
            print("🔍 CommentsView: Posting reply to main post \(code)")
            let ok = await laskoService.createComment(content: replyText, parentSequentialCode: code)
            if ok { 
                print("✅ CommentsView: Reply posted successfully")
                await laskoService.fetchComments(forSequentialCode: code)
                replyText = ""
                error = nil
                showSuccessMessage = true
            } else { 
                print("❌ CommentsView: Failed to post reply")
                error = "Failed to post reply" 
            }
        }
    }
}

struct OriginalPostCard: View {
    let post: Post
    @EnvironmentObject var laskoService: LASKOService
    @State private var isLiked: Bool = false
    @State private var isAnnounced: Bool = false
    @State private var likesCount: Int = 0
    @State private var broadcastCount: Int = 0
    @State private var selectedPostID: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post header
            HStack {
                Text(laskoService.getDisplayName(for: post.author))
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
                
                // Broadcast button
                Button(action: { 
                    isAnnounced.toggle()
                    if isAnnounced {
                        broadcastCount += 1
                    } else {
                        broadcastCount = max(0, broadcastCount - 1)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "megaphone")
                            .font(.system(size: 14))
                            .foregroundColor(isAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                        Text("\(broadcastCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Fire/like button
                Button(action: {
                    isLiked.toggle()
                    likesCount += isLiked ? 1 : -1
                    Task { await laskoService.likePost(post) }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "flame.fill" : "flame")
                            .font(.system(size: 14))
                            .foregroundColor(isLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                        Text("\(likesCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isLiked ? .red : LASKDesignSystem.Colors.textSecondary)
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
        .background(Color.white.opacity(0.05))
        .onAppear {
            likesCount = post.likes
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
    @State private var isLiked: Bool = false
    @State private var isAnnounced: Bool = false
    @State private var likesCount: Int = 0
    @State private var broadcastCount: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Vertical connection line for nested comments
                if depth > 0 {
                    Rectangle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 2)
                        .padding(.leading, CGFloat((depth - 1) * 16) + 8)
                        .offset(x: -8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Comment header with username and timestamp
                    HStack {
                        Text(laskoService.getDisplayName(for: comment.author))
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
                        
                        // Broadcast button
                        Button(action: { 
                            isAnnounced.toggle()
                            if isAnnounced {
                                broadcastCount += 1
                            } else {
                                broadcastCount = max(0, broadcastCount - 1)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "megaphone")
                                    .font(.system(size: 12))
                                    .foregroundColor(isAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                                Text("\(broadcastCount)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(isAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Fire/like button
                        Button(action: {
                            isLiked.toggle()
                            likesCount += isLiked ? 1 : -1
                            Task { await laskoService.likePost(comment) }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "flame.fill" : "flame")
                                    .font(.system(size: 12))
                                    .foregroundColor(isLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                                Text("\(likesCount)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(isLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // TLS button - using the proper component
                        TelestaiRewardActionButton(post: comment, laskoService: laskoService)
                            .scaleEffect(0.8) // Make it smaller for comments
                        
                        // See more button for nested comments (only show if there are children and depth < MAX_COMMENT_DEPTH)
                        let childrenCount = (laskoService.repliesByCode[comment.id] ?? []).count
                        if childrenCount > 0 && depth < MAX_COMMENT_DEPTH {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    // Add current promoted comment to history before promoting new one
                                    if let currentPromoted = promotedComment {
                                        commentHistory.append(currentPromoted)
                                    } else {
                                        // We're promoting from the original post, add it to history
                                        if let originalPost = laskoService.posts.first(where: { $0.id == postId }) {
                                            commentHistory.append(originalPost)
                                        }
                                    }
                                    promotedComment = comment
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                    Text("see \(childrenCount) more")
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
            .padding(.leading, CGFloat(depth * 16))
            .padding(16)
            .background(LASKDesignSystem.Colors.cardBackground.opacity(0.1))

            // No longer showing children inline - they'll be shown when comment is promoted
        }
        .onAppear {
            likesCount = comment.likes
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
