import SwiftUI
import UIKit

struct ContentView: View {
    @State private var showingFeed = false
    @State private var showingProfile = false
    @EnvironmentObject var laskoService: LASKOService
    @EnvironmentObject private var authUIState: AuthUIState
    @StateObject private var themeManager = LASKThemeManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Force dark mode background for welcome screen
                Color(red: 0.15, green: 0.15, blue: 0.15) // Charcoal background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Modern header with gradient
                    VStack(spacing: 20) {
                        // Logo section with modern design
                        VStack(spacing: 20) {
                            // LASKO Logo
                            Image("LaskoLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 158.7, height: 158.7)
                                .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 15, x: 0, y: 8)
                        }
                        
                        // Modern tagline (thinner) - force white text
                        Text("Decentralized Social Media")
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .foregroundColor(.white.opacity(0.7)) // Force white with opacity
                            .tracking(0.4)
                        
                        // Authentication status
                        if laskoService.isAuthenticatedWithZeroa {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connected to Zeroa")
                                    .foregroundColor(.green)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(20)
                        } else if authUIState.step == .waiting {
                            HStack {
                                ProgressView()
                                    .tint(.orange)
                                Text("Waiting for Zeroa approval…")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(20)
                            .onAppear {
                                // Poll for response while waiting
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    laskoService.checkForAuthResponse()
                                }
                            }
                        } else if authUIState.step == .approved {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Approved")
                                    .foregroundColor(.green)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(20)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    showingFeed = true
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Not connected to Zeroa")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.8)) // Force dark background
                            .cornerRadius(20)
                        }
                    }
                    .padding(.top, 60)
                    .offset(y: -24)
                    
                    // Modern feature cards with glassmorphism - force dark mode colors
                    VStack(spacing: 16) {
                        ModernFeatureCard(
                            icon: "message.circle.fill",
                            title: "Decentralized Posts",
                            description: "Your content, your control",
                            gradient: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 1.0, green: 0.4, blue: 0.0)]
                        )
                        
                        ModernFeatureCard(
                            icon: "shield.checkered",
                            title: "Privacy First",
                            description: "No algorithms, no tracking",
                            gradient: [Color(red: 0.2, green: 0.8, blue: 0.6), Color(red: 0.1, green: 0.6, blue: 0.4)]
                        )
                        
                        ModernFeatureCard(
                            icon: "link.circle.fill",
                            title: "Blockchain Powered",
                            description: "Built on Telestai network",
                            gradient: [Color(red: 0.6, green: 0.4, blue: 1.0), Color(red: 0.4, green: 0.2, blue: 0.8)]
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .offset(y: -24)
                    
                    // Action + footer directly under feature cards
                    VStack(spacing: 12) {
                        // Primary action button
                        Button(action: {
                            print("Get Started button tapped")
                            if laskoService.isAuthenticatedWithZeroa || laskoService.restoreZeroaSessionFromAppGroups() {
                                showingFeed = true
                            } else {
                                DispatchQueue.main.async {
                                    authUIState.step = .waiting
                                }
                                laskoService.requestZeroaAuthentication()
                                if laskoService.isAuthenticatedWithZeroa {
                                    authUIState.step = .approved
                                    showingFeed = true
                                }
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: laskoService.isAuthenticatedWithZeroa ? "arrow.right.circle.fill" : (authUIState.step == .waiting ? "hourglass.circle.fill" : "lock.circle.fill"))
                                    .font(.system(size: 20, weight: .semibold))
                                
                            Text(laskoService.isAuthenticatedWithZeroa ? "Get Started" : (authUIState.step == .waiting ? "Waiting for Zeroa…" : "Log in via Zeroa"))
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
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
                            .cornerRadius(16)
                            .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(authUIState.step == .waiting)
                        
                        // Telestai footer - force white text
                        VStack(spacing: 6) {
                            Text("Part of the Telestai Ecosystem")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white.opacity(0.6)) // Force white with opacity
                                .multilineTextAlignment(.center)
                            Image("TelestaiLogo")
                                .resizable()
                                .renderingMode(.original)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                                .opacity(0.95)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showingFeed) {
                ModernFeedView()
                    .navigationTitle("LASKO Feed")
                    .navigationBarTitleDisplayMode(.large)
            }
            .navigationDestination(isPresented: $showingProfile) {
                ModernProfileView()
                    .navigationTitle("Profile")
                    .navigationBarTitleDisplayMode(.large)
            }
        }
        .onAppear {
            // If Zeroa isn't installed/running and button is tapped, the request will be stored.
            // No auto-connect here to ensure the user sees the prompt.
        }
        .onChange(of: laskoService.isAuthenticatedWithZeroa, initial: false) { _, isAuthed in
            if isAuthed {
                // When auth completes, mark approved and navigate to the feed
                DispatchQueue.main.async {
                    authUIState.step = .approved
                    showingFeed = true
                }
            }
        }
    }

}

// Modern feature card with glassmorphism effect
struct ModernFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let gradient: [Color]
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: gradient[0].opacity(0.25), radius: 6, x: 0, y: 3)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

    func formattedAddress(_ address: String) -> String {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 12 else { return trimmed }
    let prefix = trimmed.prefix(5)
    let suffix = trimmed.suffix(7)
    return "\(prefix)...\(suffix)"
}

@MainActor func resolvedTLSAddress(tlsAddress: String, laskoService: LASKOService) -> String {
    if tlsAddress.isEmpty {
        return laskoService.currentTLSAddress ?? ""
    }
    return tlsAddress
}

@MainActor private func copyAddressToClipboard(tlsAddress: String, laskoService: LASKOService) {
    let address = resolvedTLSAddress(tlsAddress: tlsAddress, laskoService: laskoService)
    guard !address.isEmpty else { return }
    UIPasteboard.general.string = address
}

// Modern feed view inspired by X, Nostr, and Mastodon
struct ModernFeedView: View {
    @EnvironmentObject var laskoService: LASKOService
    @State private var showingPostComposer = false
    @State private var selectedPost: Post?
    @State private var promotedCommentInComments: Post? = nil
    @State private var showFluxDriveSheet = false
    @State private var showSubscriptionSheet = false
    @State private var showSettingsSheet = false
    @State private var showSupportSheet = false
    @State private var showSideMenu = false
    @State private var selectedProfileAddress: String? = nil
    @State private var feedMode: LASKOFeedMode = .following
    @State private var followingPosts: [Post] = []
    @State private var forYouPosts: [Post] = []
    @State private var isLoadingFollowing = false
    @State private var isLoadingForYou = false
    @State private var showActivity = false

    private var visiblePosts: [Post] {
        switch feedMode {
        case .global: return laskoService.posts
        case .following: return followingPosts
        case .forYou: return forYouPosts
        }
    }

    private var isInitialLoading: Bool {
        switch feedMode {
        case .global:
            return laskoService.isLoading && laskoService.posts.isEmpty
        case .following:
            return isLoadingFollowing && followingPosts.isEmpty
        case .forYou:
            return isLoadingForYou && forYouPosts.isEmpty
        }
    }
    
    var body: some View {
        ZStack {
            // Theme-aware background
            LASKDesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with logo, profile and menu
                HStack(spacing: 8) {
                    // Profile image (36x36) - top left + posting-key status light
                    HStack(spacing: 6) {
                        NavigationLink(destination: ModernProfileView()) {
                            if let syncedImage = AppGroupsService.shared.getProfileImage(for: laskoService.currentTLSAddress) {
                                Image(uiImage: syncedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                    .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 8, x: 0, y: 4)
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 1.0, green: 0.6, blue: 0.0),
                                                Color(red: 1.0, green: 0.4, blue: 0.0)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(laskoService.username.prefix(1).uppercased())
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                    .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                        }
                        LASKOPostingKeyStatusDot()
                    }

                    Spacer()
                    
                    // Logo (36x36) - center top (SVG)
                    Image("LaskoFullLogo")
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        
                    Spacer()

                    Button(action: { showActivity = true }) {
                        Image(systemName: "bell")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                    }
                    .padding(.trailing, 12)
                        
                    // Hamburger menu (top right) - opens slide-out menu
                    Button(action: { withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = true } }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .sheet(isPresented: $showFluxDriveSheet) { FluxDriveView() }
                .sheet(isPresented: $showSubscriptionSheet) { SubscriptionSheetView() }
                .sheet(isPresented: $showSettingsSheet) { LASKOSettingsView() }
                .sheet(isPresented: $showSupportSheet) { LASKOSupportView() }

                // X-style underline channel tabs
                LASKOFeedChannelTabs(selection: $feedMode)
                    .onChange(of: feedMode) { _, mode in
                        Task { await reloadChannelIfNeeded(mode) }
                    }
                
                // Posts feed
                // Only show the full-screen spinner on the very first load (empty feed).
                // On refresh/after posting, keep the existing feed on screen to avoid a
                // jarring blank flash — pull-to-refresh shows its own indicator.
                if isInitialLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: LASKDesignSystem.Colors.primary))
                        .scaleEffect(1.5)
                    Spacer()
                } else if feedMode == .following && followingPosts.isEmpty && !isLoadingFollowing {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("No posts from people you follow")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                        Text("Open a profile and tap Follow to build this feed.")
                            .font(.system(size: 13))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    Spacer()
                } else if feedMode == .forYou && forYouPosts.isEmpty && !isLoadingForYou {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("Nothing in For You yet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                        Text("Pull to refresh, or check Global while the network warms up.")
                            .font(.system(size: 13))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visiblePosts, id: \.feedKey) { post in
                                ModernPostCard(post: post, onProfileTap: {
                                    if let address = post.tlsAddress {
                                        selectedProfileAddress = address
                                    }
                                }) {
                                    selectedPost = post
                                }
                            }
                        }
                        .padding(.bottom, 100) // Extra padding for floating button
                    }
                    .refreshable {
                        await refreshCurrentChannel()
                    }
                    .navigationDestination(isPresented: Binding(
                        get: { selectedPost != nil },
                        set: { active in
                            if !active {
                                selectedPost = nil
                                promotedCommentInComments = nil
                            }
                        }
                    )) {
                        if let post = selectedPost {
                            let threadCode = laskoService.threadRootCode(for: post)
                            CommentsView(postId: threadCode, sequentialCode: threadCode)
                                .navigationTitle("Comments")
                                .navigationBarTitleDisplayMode(.inline)
                                .environmentObject(laskoService)
                        }
                    }
                    .navigationDestination(isPresented: Binding(
                        get: { selectedProfileAddress != nil },
                        set: { active in
                            if !active {
                                selectedProfileAddress = nil
                            }
                        }
                    )) {
                        ModernProfileView(viewingAddress: selectedProfileAddress)
                            .navigationTitle("Profile")
                            .navigationBarTitleDisplayMode(.inline)
                            .environmentObject(laskoService)
                    }
                    .navigationDestination(isPresented: $showActivity) {
                        LASKOActivityInboxView()
                            .environmentObject(laskoService)
                    }
                    // If unauthenticated, show a small inline banner but still show feed
                    if !laskoService.isAuthenticatedWithZeroa {
                        HStack(spacing: 10) {
                            Image(systemName: "link.circle.fill").foregroundColor(.orange)
                            Text("Connect to Zeroa to post and comment")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Button("Connect") { laskoService.requestZeroaAuthentication() }
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    }
                }
            }
            
            // Slide-out side menu overlay
            if showSideMenu {
                // Dimmed backdrop
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = false } }
                // Panel
                LASKOSideMenuView(close: {
                    withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = false }
                }, openFluxDrive: {
                    withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = false }
                    showFluxDriveSheet = true
                }, openSubscription: {
                    withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = false }
                    showSubscriptionSheet = true
                }, openSettings: {
                    withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = false }
                    showSettingsSheet = true
                }, openSupport: {
                    withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = false }
                    showSupportSheet = true
                })
                .transition(.move(edge: .trailing))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }

            // Floating create post button (only show if authenticated)
            if laskoService.isAuthenticatedWithZeroa {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showingPostComposer = true
                        }) {
                            Image(systemName: "pencil.and.outline")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 1.0, green: 0.6, blue: 0.0),
                                                    Color(red: 1.0, green: 0.4, blue: 0.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.4), radius: 12, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingPostComposer) {
            ModernPostComposerView()
                .environmentObject(laskoService)
        }
        .onAppear {
            Task {
                await laskoService.refreshFollowedAddresses()
                if followingPosts.isEmpty {
                    await reloadFollowing()
                }
                if laskoService.posts.isEmpty {
                    await laskoService.fetchPosts()
                }
            }
        }
    }

    private func reloadChannelIfNeeded(_ mode: LASKOFeedMode) async {
        switch mode {
        case .following:
            if followingPosts.isEmpty { await reloadFollowing() }
        case .forYou:
            if forYouPosts.isEmpty { await reloadForYou() }
        case .global:
            if laskoService.posts.isEmpty { await laskoService.fetchPosts() }
        }
    }

    private func refreshCurrentChannel() async {
        switch feedMode {
        case .global:
            await laskoService.fetchPosts()
        case .following:
            await reloadFollowing()
        case .forYou:
            await reloadForYou(forceRefreshSources: true)
        }
    }

    private func reloadFollowing() async {
        isLoadingFollowing = true
        let posts = await laskoService.loadFollowingFeed()
        await MainActor.run {
            followingPosts = posts
            isLoadingFollowing = false
        }
    }

    /// For You: engagement-ranked mix — boost posts from people you follow,
    /// then score by likes/replies/announces + freshness.
    private func reloadForYou(forceRefreshSources: Bool = false) async {
        isLoadingForYou = true
        if forceRefreshSources || laskoService.posts.isEmpty {
            await laskoService.fetchPosts()
        }
        if forceRefreshSources || followingPosts.isEmpty {
            let following = await laskoService.loadFollowingFeed()
            await MainActor.run { followingPosts = following }
        }
        let followingAddresses = Set(followingPosts.compactMap { $0.tlsAddress }.filter { !$0.isEmpty })
        let merged = mergeUnique(followingPosts + laskoService.posts)
        let ranked = merged.sorted { a, b in
            score(a, followingBoost: followingAddresses) > score(b, followingBoost: followingAddresses)
        }
        await MainActor.run {
            forYouPosts = ranked
            isLoadingFollowing = false
            isLoadingForYou = false
        }
    }

    private func mergeUnique(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        var out: [Post] = []
        for p in posts {
            if seen.insert(p.feedKey).inserted {
                out.append(p)
            }
        }
        return out
    }

    private func score(_ post: Post, followingBoost: Set<String>) -> Double {
        let engagement = Double(post.likes) + Double(post.replies) * 1.5 + Double(post.broadcastCount) * 2.0
        let ageHours = max(0.25, Date().timeIntervalSince(post.timestamp) / 3600.0)
        let freshness = 12.0 / ageHours
        let boost = (post.tlsAddress.map { followingBoost.contains($0) } ?? false) ? 8.0 : 0.0
        return engagement + freshness + boost
    }
}

/// X-style text tabs with underline on the selected channel.
private enum LASKOFeedMode: String, CaseIterable, Identifiable {
    case following = "Following"
    case global = "Global"
    case forYou = "For You"
    var id: String { rawValue }
}

private struct LASKOFeedChannelTabs: View {
    @Binding var selection: LASKOFeedMode

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(LASKOFeedMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selection = mode
                        }
                    } label: {
                        VStack(spacing: 10) {
                            Text(mode.rawValue)
                                .font(.system(size: 15, weight: selection == mode ? .bold : .medium))
                                .foregroundColor(
                                    selection == mode
                                    ? LASKDesignSystem.Colors.text
                                    : LASKDesignSystem.Colors.textSecondary
                                )
                            Rectangle()
                                .fill(selection == mode ? Color(red: 1.0, green: 0.6, blue: 0.0) : Color.clear)
                                .frame(height: 3)
                                .cornerRadius(1.5)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .padding(.bottom, 8)
    }
}

// Modern post card design inspired by X, Nostr, and Mastodon
struct ModernPostCard: View {
    let post: Post
    let onProfileTap: () -> Void
    let onTap: () -> Void
    @EnvironmentObject var laskoService: LASKOService
    @State private var likesCount: Int = 0
    @State private var broadcastCount: Int = 0
    @State private var showReplies: Bool = false
    @State private var inlineReplyText: String = ""
    @State private var isSubmittingInlineReply: Bool = false
    @State private var showInlineReplyErrorAlert = false

    private var userLiked: Bool {
        _ = laskoService.userActionStateVersion
        return laskoService.hasUserLikedPost(post.id)
    }

    private var userAnnounced: Bool {
        _ = laskoService.userActionStateVersion
        return laskoService.hasUserAnnouncedPost(post.id)
    }

    private var userCommented: Bool {
        _ = laskoService.userActionStateVersion
        return laskoService.hasUserCommentedOnPost(post.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if post.isAnnounceRepost {
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                    Text("\(laskoService.announcerDisplayName(for: post)) announced")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    Spacer()
                    if let announcedAt = post.announcedAt {
                        Text(timeAgoString(from: announcedAt))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            // Profile section - tappable to go to profile
            HStack(spacing: 12) {
                // User avatar - tappable
                Button(action: onProfileTap) {
                    // Always prioritize App Groups profile image for current user's posts
                    Group {
                    if let postTLS = post.tlsAddress,
                       let currentTLS = laskoService.currentTLSAddress,
                       postTLS == currentTLS {
                        // Current user's post - check App Groups first
                        if let userAvatar = AppGroupsService.shared.getProfileImage(for: laskoService.currentTLSAddress) {
                            // Current user's avatar from App Groups
                            Image(uiImage: userAvatar)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 29, height: 29)
                                .clipShape(Circle())
                                .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 8, x: 0, y: 4)
                        } else {
                            // Fallback for current user if no profile image in App Groups
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 1.0, green: 0.6, blue: 0.0),
                                                Color(red: 1.0, green: 0.4, blue: 0.0)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 29, height: 29)
                                Text(String(laskoService.feedDisplayName(for: post).prefix(1)))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    } else if let urlStr = post.avatarURL {
                        // Other user's avatar from URL or data URL
                        if urlStr.hasPrefix("data:image") {
                            // Handle base64 data URL
                            if let base64String = urlStr.components(separatedBy: ",").last,
                               let imageData = Data(base64Encoded: base64String),
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 29, height: 29)
                                    .clipShape(Circle())
                            } else {
                                // Fallback if base64 decode fails
                                Circle()
                                    .fill(LASKDesignSystem.Colors.cardBackground.opacity(0.3))
                                    .frame(width: 29, height: 29)
                            }
                        } else if let url = URL(string: urlStr) {
                            // Handle regular URL
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(LASKDesignSystem.Colors.cardBackground.opacity(0.3))
                            }
                            .frame(width: 29, height: 29)
                            .clipShape(Circle())
                        } else {
                            // Invalid URL format
                            Circle()
                                .fill(LASKDesignSystem.Colors.cardBackground.opacity(0.3))
                                .frame(width: 29, height: 29)
                        }
                    } else {
                        // Fallback: gradient circle with initial
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.6, blue: 0.0),
                                            Color(red: 1.0, green: 0.4, blue: 0.0)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 29, height: 29)
                            Text(String(laskoService.feedDisplayName(for: post).prefix(1)))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(
                                (post.tlsAddress != laskoService.currentTLSAddress && laskoService.isFollowing(post.tlsAddress))
                                ? Color.green
                                : Color.clear,
                                lineWidth: 2
                            )
                            .frame(width: 33, height: 33)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Username and time - tappable
                Button(action: onProfileTap) {
                    HStack(spacing: 8) {
                        Text(laskoService.feedDisplayName(for: post))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                        Text(timeAgoString(from: post.timestamp))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // TLS address formatted as first 5 + "..." + last 7
                if let tlsAddr = post.tlsAddress {
                    Text(laskoService.formatTLSAddress(tlsAddr))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                }
                
                // Rank icon based on user rank
                if let rankImageName = getRankImageName(for: post.userRank) {
                    Image(systemName: rankImageName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0)) // Orange theme color
                        .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.6), radius: 8, x: 0, y: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(
                Rectangle()
                    .fill(Color.white.opacity(0.05))
            )
            
            // Rest of post - body opens thread; action buttons remain independent.
            VStack(alignment: .leading, spacing: 16) {
                    if post.isReply {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Reply")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    }

                    // Post content
                    Text(post.content)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(LASKDesignSystem.Colors.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap() }

                    
                    // Post actions (evenly spaced across the card) - WITHOUT THREE DOTS
                    let _ = laskoService.userActionStateVersion
                    HStack(spacing: 0) {
                        // Message (comment) first
                        Button(action: {
                            withAnimation { showReplies.toggle() }
                            Task { await laskoService.fetchComments(forSequentialCode: post.id) }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "message")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(userCommented ? Color(red: 0.35, green: 0.75, blue: 1.0) : LASKDesignSystem.Colors.textSecondary)
                                Text("\(max(laskoService.repliesByCode[post.id]?.count ?? 0, post.replies))")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(userCommented ? Color(red: 0.35, green: 0.75, blue: 1.0) : LASKDesignSystem.Colors.text)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()

                        // Broadcast (share) — tap again to un-announce
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(userAnnounced ? .green : LASKDesignSystem.Colors.textSecondary)
                                Text("\(broadcastCount)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(userAnnounced ? .green : LASKDesignSystem.Colors.text)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()

                        // Fire (like)
                        Button(action: {
                            guard !userLiked else { return }
                            likesCount += 1
                            Task { await laskoService.likePost(post) }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: userLiked ? "flame.fill" : "flame")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(userLiked ? .red : LASKDesignSystem.Colors.textSecondary)
                                Text("\(likesCount)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(userLiked ? .red : LASKDesignSystem.Colors.text)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()
                        
                        // Telestai reward button with transient +10 TLS
                        TelestaiRewardActionButton(post: post, laskoService: laskoService)
                        
                        Spacer()

                        PostOptionsMenu(post: post, laskoService: laskoService)
                    }
                
                    // Inline replies section
                    if showReplies {
                        VStack(alignment: .leading, spacing: 8) {
                            if let replies = laskoService.repliesByCode[post.id], !replies.isEmpty {
                                let topLevelReplies = replies.filter { ($0.parentCode ?? "").isEmpty || $0.parentCode == post.id }
                                let topReplies = getTopThreeComments(from: topLevelReplies)
                                ForEach(topReplies) { r in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(r.author)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(LASKDesignSystem.Colors.text)
                                            Spacer()
                                            Text(timeAgoString(from: r.timestamp))
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                        }
                                        Text(r.content)
                                            .font(.system(size: 14))
                                            .foregroundColor(LASKDesignSystem.Colors.text)
                                    }
                                    .padding(10)
                                    .background(LASKDesignSystem.Colors.cardBackground.opacity(0.3))
                                    .cornerRadius(10)
                                }
                                
                                // Show "Show more" if there are more than 3 comments
                                if replies.count > 3 || replies.contains(where: { !($0.parentCode ?? "").isEmpty && $0.parentCode != post.id }) {
                                    Button(action: onTap) {
                                        Text("Open full thread")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.orange)
                                            .padding(.top, 4)
                                            .padding(.leading, 10)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            } else {
                                Text("No replies yet.")
                                    .font(.system(size: 12))
                                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            }
                            // Inline reply composer
                            HStack(spacing: 8) {
                                TextField("Write a reply…", text: $inlineReplyText)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(isSubmittingInlineReply || laskoService.isReviewingContent)
                                Button(inlineReplyButtonTitle) {
                                    let text = inlineReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !text.isEmpty else { return }
                                    Task {
                                        isSubmittingInlineReply = true
                                        defer { isSubmittingInlineReply = false }
                                        let ok = await laskoService.createComment(
                                            content: text,
                                            parentSequentialCode: post.id,
                                            threadRootCode: post.id
                                        )
                                        if ok {
                                            inlineReplyText = ""
                                            laskoService.errorMessage = nil
                                            await laskoService.fetchComments(forSequentialCode: post.id)
                                        } else {
                                            showInlineReplyErrorAlert = true
                                        }
                                    }
                                }
                                .disabled(
                                    isSubmittingInlineReply
                                    || laskoService.isReviewingContent
                                    || inlineReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )
                            }
                            .padding(.top, 4)
                        }
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                Rectangle()
                    .fill(Color.white.opacity(0.05))
            )
            .onAppear {
                likesCount = post.likes
                broadcastCount = post.broadcastCount
                if laskoService.repliesByCode[post.id] == nil && post.replies > 0 {
                    Task { await laskoService.fetchComments(forSequentialCode: post.id) }
                }
            }
            .onChange(of: post.likes, initial: false) { _, newValue in
                likesCount = newValue
            }
            .onChange(of: post.broadcastCount, initial: false) { _, newValue in
                broadcastCount = newValue
            }
            .onChange(of: laskoService.userActionStateVersion, initial: false) { _, _ in
                if let updated = laskoService.posts.first(where: { $0.feedKey == post.feedKey }) {
                    likesCount = updated.likes
                    broadcastCount = updated.broadcastCount
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LASKDesignSystem.Colors.postSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(LASKDesignSystem.Colors.primary.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .overlay {
            if isSubmittingInlineReply && laskoService.isReviewingContent {
                ModerationReviewingOverlay()
            }
        }
        .alert("Unable to post", isPresented: $showInlineReplyErrorAlert) {
            Button("OK", role: .cancel) { laskoService.errorMessage = nil }
        } message: {
            Text(laskoService.errorMessage ?? "Failed to post reply")
        }
    }
    
    private var inlineReplyButtonTitle: String {
        if laskoService.isReviewingContent && isSubmittingInlineReply { return "Reviewing…" }
        if isSubmittingInlineReply { return "Posting…" }
        return "Reply"
    }
    
    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        // Guard against invalid dates or NaN
        guard timeInterval.isFinite && !timeInterval.isNaN,
              date.timeIntervalSince1970.isFinite && !date.timeIntervalSince1970.isNaN else {
            return "now"
        }
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        }
    }
}

// Telestai reward button component
struct TelestaiRewardActionButton: View {
    let post: Post
    @ObservedObject var laskoService: LASKOService
    @State private var showReward = false
    @State private var isRewarding = false
    private let gold = Color(red: 156/255, green: 152/255, blue: 118/255) // #9C9876
    @State private var isActive = false
    private let inactiveColor = LASKDesignSystem.Colors.textSecondary
    
    var body: some View {
        HStack(spacing: 6) {
            Button(action: {
                guard !isRewarding else { return }
                
                isRewarding = true
                
                // Reward the post
                Task {
                    let success = await laskoService.rewardPost(post, amount: 10.0)
                    if success {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showReward = true
                        }
                        isActive = true
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showReward = false
                        }
                        isRewarding = false
                        // Let it stay gold; remove next line if we want it to return to gray
                        // isActive = false
                    }
                }
            }) {
                // Use TelestaiLogo set to template mode for tint control
                Image("TelestaiLogo")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundColor(isActive ? gold : inactiveColor)
                    .scaleEffect(showReward ? 1.12 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isRewarding)
            
            // Show TLS count or +10 TLS animation
            if showReward {
                Text("+10 TLS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(gold)
                    .frame(width: 54, alignment: .leading)
                    .opacity(showReward ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showReward)
            } else if post.tlsCount > 0 {
                Text("\(post.tlsCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(gold)
                    .frame(width: 54, alignment: .leading)
            } else {
                Text("")
                    .frame(width: 54, alignment: .leading)
            }
        }
    }
}

// Modern profile view
struct ModernProfileView: View {
    let viewingAddress: String? // Optional: if nil, shows current user; if set, shows that user's profile
    @EnvironmentObject var laskoService: LASKOService
    @Environment(\.dismiss) private var dismiss
    @State private var showingImagePicker = false
    @State private var showingBannerImagePicker = false
    @State private var showingNameEditor = false
    @State private var showingBioEditor = false
    @State private var profileImage: UIImage?
    @State private var bannerImage: UIImage?
    // Username is now managed by LASKOService
    @State private var bio = "Building the future of decentralized social media on LASKO"
    @State private var tlsAddress = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var profilePosts: [Post] = []
    @State private var didLoadProfilePosts = false
    @State private var socialStatus: LASKOSocialStatus?
    @State private var followBusy = false
    
    init(viewingAddress: String? = nil) {
        self.viewingAddress = viewingAddress
    }
    
    // Check if viewing own profile
    private var isViewingOwnProfile: Bool {
        guard let viewing = viewingAddress else { return true } // No address = own profile
        return viewing == laskoService.currentTLSAddress
    }
    
    // Resolved address to display
    private var resolvedAddress: String {
        if let viewing = viewingAddress {
            return viewing
        }
        return laskoService.currentTLSAddress ?? (tlsAddress.isEmpty ? "" : tlsAddress)
    }
    
    // Profile shows the user's own posts plus posts they announced.
    // Prefer the dedicated backend fetch; fall back to the in-memory feed until it loads.
    private var userPosts: [Post] {
        let addr = resolvedAddress
        guard !addr.isEmpty else { return [] }
        if !profilePosts.isEmpty { return profilePosts }
        // Fallback: an announce repost carries the ORIGINAL author's tlsAddress but announcedBy == addr,
        // so match on either to include both "posts made" and "posts announced".
        return laskoService.posts.filter { p in
            p.tlsAddress == addr || p.announcedBy == addr
        }
    }

    private func loadProfilePosts() async {
        let addr = resolvedAddress
        guard !addr.isEmpty else { return }
        let fetched = await laskoService.fetchUserFeed(address: addr)
        await MainActor.run {
            self.profilePosts = fetched
            self.didLoadProfilePosts = true
        }
    }
    
    var body: some View {
        ZStack {
            LASKDesignSystem.Colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Clear Banner (no image)
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 120)
                        
                        // Banner image picker button (only show for own profile)
                        if isViewingOwnProfile {
                            Button(action: {
                                showingBannerImagePicker = true
                            }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(LASKDesignSystem.Colors.text)
                                    .frame(width: 32, height: 32)
                                    .background(LASKDesignSystem.Colors.cardBackground.opacity(0.8))
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    
                    // Profile content
                    VStack(spacing: 16) {
                        // Profile picture and name section - TOP LEFT layout
                        HStack(alignment: .top, spacing: 16) {
                            // Profile picture - smaller and top left
                            ZStack(alignment: .bottomTrailing) {
                                if let profileImage = profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    (!isViewingOwnProfile && (socialStatus?.isFollowing == true || laskoService.isFollowing(resolvedAddress)))
                                                    ? Color.green
                                                    : Color.clear,
                                                    lineWidth: 2.5
                                                )
                                        )
                                        .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 8, x: 0, y: 4)
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 1.0, green: 0.6, blue: 0.0),
                                                    Color(red: 1.0, green: 0.4, blue: 0.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    (!isViewingOwnProfile && (socialStatus?.isFollowing == true || laskoService.isFollowing(resolvedAddress)))
                                                    ? Color.green
                                                    : Color.clear,
                                                    lineWidth: 2.5
                                                )
                                        )
                                        .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 8, x: 0, y: 4)
                                    
                                    Text("U")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(LASKDesignSystem.Colors.text)
                                }
                                
                                // Profile image picker button (only show for own profile)
                                if isViewingOwnProfile {
                                    Button(action: {
                                        showingImagePicker = true
                                    }) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(LASKDesignSystem.Colors.text)
                                            .frame(width: 20, height: 20)
                                            .background(LASKDesignSystem.Colors.cardBackground.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            
                            // Name and TLS address - VERTICAL layout
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(isViewingOwnProfile ? laskoService.username : laskoService.getDisplayName(for: resolvedAddress))
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(LASKDesignSystem.Colors.text)
                                    
                                    // Edit name button (only show for own profile)
                                    if isViewingOwnProfile {
                                        Button(action: {
                                            showingNameEditor = true
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                        }
                                    }
                                    
                                    // User rank badge
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                                        .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.4), radius: 3, x: 0, y: 2)
                                }
                                
                                Button(action: copyAddressToClipboard) {
                                    HStack(spacing: 4) {
                                        Text(formattedAddress(resolvedAddress))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(LASKDesignSystem.Colors.textSecondary.opacity(0.85))
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, -40) // Overlap with banner
                        
                        // Bio
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Bio")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(LASKDesignSystem.Colors.text)
                                
                                Spacer()
                                
                                // Edit bio button (only show for own profile)
                                if isViewingOwnProfile {
                                    Button(action: {
                                        showingBioEditor = true
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                    }
                                }
                            }
                            
                            Text(bio)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 20)
                        
                        // Compact stats (Twitter-style) - smaller and tucked
                        HStack(spacing: 20) {
                            HStack(spacing: 4) {
                                Text("\(userPosts.count)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(LASKDesignSystem.Colors.text)
                                Text("Posts")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            }
                            
                            HStack(spacing: 4) {
                                Text("\(socialStatus?.followingCount ?? 0)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(LASKDesignSystem.Colors.text)
                                Text("Following")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            }
                            
                            HStack(spacing: 4) {
                                Text("\(socialStatus?.followerCount ?? 0)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(LASKDesignSystem.Colors.text)
                                Text("Followers")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                            }

                            Spacer(minLength: 0)

                            if !isViewingOwnProfile, laskoService.isAuthenticatedWithZeroa {
                                let isFollowing = socialStatus?.isFollowing == true || laskoService.isFollowing(resolvedAddress)
                                Button {
                                    Task {
                                        followBusy = true
                                        let addr = resolvedAddress
                                        let ok: Bool
                                        if isFollowing {
                                            ok = await laskoService.unfollow(address: addr)
                                        } else {
                                            ok = await laskoService.follow(address: addr)
                                        }
                                        if ok, let refreshed = await laskoService.fetchSocialStatus(for: addr) {
                                            socialStatus = refreshed
                                        }
                                        followBusy = false
                                    }
                                } label: {
                                    if isFollowing {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.green)
                                    } else {
                                        Text("+ Follow")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(followBusy || resolvedAddress.isEmpty)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // White page break
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        
                        // User's posts section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Posts")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                            
                            // User's posts only
                            LazyVStack(spacing: 0) {
                                ForEach(userPosts, id: \.feedKey) { post in
                                    ModernPostCard(post: post, onProfileTap: {
                                        // Profile tap handled by navigation
                                    }) {
                                        // Post tap - could navigate to comments if needed
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $profileImage)
        }
        .sheet(isPresented: $showingBannerImagePicker) {
            ImagePicker(selectedImage: $bannerImage)
        }
        .sheet(isPresented: $showingNameEditor) {
            NameEditorView(username: $laskoService.username)
        }
        .sheet(isPresented: $showingBioEditor) {
            BioEditorView(bio: $bio)
        }
        .onAppear {
            // Only load current user's profile data when viewing own profile
            if isViewingOwnProfile {
                if profileImage == nil {
                    profileImage = AppGroupsService.shared.getProfileImage(for: resolvedAddress)
                }
                if let syncedName = AppGroupsService.shared.getProfileDisplayName(for: resolvedAddress), !syncedName.isEmpty {
                    laskoService.username = syncedName
                }
                if tlsAddress.isEmpty {
                    tlsAddress = laskoService.currentTLSAddress ?? tlsAddress
                }
            } else {
                // When viewing another user, set the address from viewingAddress
                if let viewing = viewingAddress {
                    tlsAddress = viewing
                }
            }
        }
        .task(id: resolvedAddress) {
            profileImage = isViewingOwnProfile
                ? AppGroupsService.shared.getProfileImage(for: resolvedAddress)
                : nil
            await loadProfilePosts()
            if !resolvedAddress.isEmpty {
                socialStatus = await laskoService.fetchSocialStatus(for: resolvedAddress)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Only update profile data when viewing own profile
            if isViewingOwnProfile {
                profileImage = AppGroupsService.shared.getProfileImage(for: resolvedAddress)
                if let syncedName = AppGroupsService.shared.getProfileDisplayName(for: resolvedAddress), !syncedName.isEmpty {
                    laskoService.username = syncedName
                }
            }
        }
    }
    
    func formattedAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else { return trimmed }
        let prefix = trimmed.prefix(5)
        let suffix = trimmed.suffix(7)
        return "\(prefix)...\(suffix)"
    }
    
    func copyAddressToClipboard() {
        guard !resolvedAddress.isEmpty else { return }
        UIPasteboard.general.string = resolvedAddress
    }
}

// Name editor view
struct NameEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var username: String
    @State private var tempUsername: String
    
    init(username: Binding<String>) {
        self._username = username
        self._tempUsername = State(initialValue: username.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Edit Username")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(LASKDesignSystem.Colors.text)
                
                TextField("Username", text: $tempUsername)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 20)
                
                Button("Save") {
                    username = tempUsername
                    dismiss()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(LASKDesignSystem.Colors.primary)
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .background(LASKDesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(LASKDesignSystem.Colors.primary)
                }
            }
        }
    }
}

// Bio editor view
struct BioEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var bio: String
    @State private var tempBio: String
    
    init(bio: Binding<String>) {
        self._bio = bio
        self._tempBio = State(initialValue: bio.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Edit Bio")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(LASKDesignSystem.Colors.text)
                
                TextEditor(text: $tempBio)
                    .frame(height: 100)
                    .padding(8)
                    .background(LASKDesignSystem.Colors.cardBackground.opacity(0.3))
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                
                Button("Save") {
                    bio = tempBio
                    dismiss()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(LASKDesignSystem.Colors.primary)
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .background(Color(red: 0.15, green: 0.15, blue: 0.15))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }
}

// Composer moved to separate file

// MARK: - Lightweight Formatting Toolbar & Preview
struct FormattingToolbar: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { surround(with: "**") }) { Text("B").fontWeight(.bold) }
            Button(action: { surround(with: "*") })  { Text("I").italic() }
            Button(action: { surround(with: "`") })  { Text("Code").font(.caption) }
            Button(action: { text.append("\n\n• ") }) { Text("• List").font(.caption) }
            Spacer()
            Text("\(text.count)/1000")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .foregroundColor(.black)
    }
    private func surround(with token: String) {
        text = token + text + token
    }
}

struct RichPreview: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundColor(.black)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Poll Maker & Scheduler Sheets (basic stubs to satisfy compiler)
struct PollMakerSheet: View {
    @Binding var options: [String]
    @Binding var durationHours: Int
    @Environment(\.dismiss) private var dismiss
    @State private var newOption: String = ""
    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                HStack {
                    TextField("Add option", text: $newOption)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if !newOption.trimmingCharacters(in: .whitespaces).isEmpty {
                            options.append(newOption)
                            newOption = ""
                        }
                    }
                }
                .padding(.horizontal)
                Stepper("Duration: \(durationHours)h", value: $durationHours, in: 1...168)
                    .padding(.horizontal)
                List {
                    ForEach(options.indices, id: \.self) { i in
                        Text(options[i])
                    }
                    .onDelete { idx in options.remove(atOffsets: idx) }
                }
                Button("Done") { dismiss() }
                    .padding(.bottom)
            }
            .navigationTitle("Create Poll")
        }
    }
}

struct SchedulerSheet: View {
    @Binding var scheduledDate: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var tempDate: Date = Date().addingTimeInterval(3600)
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                DatePicker("Schedule", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
                HStack {
                    Button("Clear") { scheduledDate = nil; dismiss() }
                    Spacer()
                    Button("Set") { scheduledDate = tempDate; dismiss() }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Schedule Post")
        }
    }
}

// MARK: - Styled toolbar elements
private struct ToolbarIcon: View {
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.black.opacity(0.06))
                    .frame(width: 32, height: 32)
                Image(systemName: system)
                    .foregroundColor(.black)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ToolbarDivider: View {
    var body: some View { Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1, height: 22) }
}

// Helper function to get rank image name
func getRankImageName(for rank: String) -> String? {
    switch rank {
    case "Bronze":
        return "medal.fill"
    case "Silver":
        return "medal.fill"
    case "Gold":
        return "medal.fill"
    case "Platinum":
        return "crown.fill"
    case "Diamond":
        return "diamond.fill"
    default:
        return nil
    }
}

// Helper function to get top three comments by points, follower count, or chronological order
func getTopThreeComments(from replies: [Post]) -> [Post] {
    let sortedReplies = replies.sorted { (r1, r2) -> Bool in
        // Prioritize comments with more points
        if r1.points != r2.points {
            return r1.points > r2.points
        }
        // Then prioritize comments from users with more followers
        if r1.followerCount != r2.followerCount {
            return r1.followerCount > r2.followerCount
        }
        // Finally, sort by chronological order
        return r1.timestamp < r2.timestamp
    }
    return Array(sortedReplies.prefix(3))
}

// Slide-out side menu
struct LASKOSideMenuView: View {
    let close: () -> Void
    let openFluxDrive: () -> Void
    let openSubscription: () -> Void
    let openSettings: () -> Void
    let openSupport: () -> Void
    @StateObject private var themeManager = LASKThemeManager.shared

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Menu")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(LASKDesignSystem.Colors.text)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(LASKDesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(LASKDesignSystem.Colors.border)

                Group {
                    sideRow(title: "Storage", systemImage: "externaldrive.fill", action: openFluxDrive)
                    // Subscription menu item ghosted out (posting is now free)
                    sideRow(title: "Subscription", systemImage: "lock.shield", action: {})
                        .opacity(0.3)
                        .disabled(true)
                    sideRow(title: "Settings", systemImage: "gearshape.fill", action: openSettings)
                    sideRow(title: "Support & Help", systemImage: "questionmark.circle.fill", action: openSupport)
                    sideRow(title: "Theme: \(themeManager.currentTheme)", systemImage: "paintbrush.fill", action: {
                        themeManager.currentTheme = themeManager.currentTheme == "Light" ? "Dark" : "Light"
                    })
                }
                .padding(.top, 6)

                Spacer()
            }
            .frame(width: 280)
            .background(LASKDesignSystem.Colors.background)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(LASKDesignSystem.Colors.border, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func sideRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(LASKDesignSystem.Colors.primary)
                Text(title)
                    .foregroundColor(LASKDesignSystem.Colors.text)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func sideRowAsset(title: String, assetName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text(title)
                    .foregroundColor(LASKDesignSystem.Colors.text)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(LASKDesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
    }
}



#Preview {
    ContentView()
}
