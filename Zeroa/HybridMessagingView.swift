import SwiftUI
// import WebRTC  // Temporarily disabled for simulator testing

struct HybridMessagingView: View {
    var showsBackButton: Bool = true
    var onBack: (() -> Void)?
    @StateObject private var p2pService = TLSLayer2MessagingService.shared
    // @StateObject private var webRTCManager = WebRTCConnectionManager.shared  // Temporarily disabled
    @State private var selectedTab = 0
    @State private var messageText = ""
    @State private var selectedContact: P2PContact?
    @State private var showAddContact = false
    @State private var newContactAddress = ""
    @State private var newContactName = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showConversationDetail = false
    @State private var selectedConversation: P2PConversation?
    @State private var isTyping = false
    @State private var showMediaOptions = false
    @State private var conversationDetailIsTyping = false
    @State private var conversationDetailShowMediaOptions = false
    @State private var showP2PConnectionStatus = false
    @Environment(\.dismiss) private var dismiss
    
    private func handleBack() {
        if let onBack = onBack {
            onBack()
        } else {
            dismiss()
            NotificationCenter.default.post(name: .zeroaNavigateToProfile, object: nil)
        }
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HeaderBar(
                    title: "Switchboard",
                    leading: {
                        if showsBackButton {
                            Button(action: handleBack) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .medium))
                                    Text("Back")
                                        .font(DesignSystem.Typography.bodyMedium)
                                }
                                .foregroundColor(DesignSystem.Colors.secondary)
                            }
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 44)
                        }
                    },
                    trailing: {
                        Circle()
                            .fill(p2pService.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                            .padding(.leading, DesignSystem.Spacing.sm)
                            .padding(.trailing, DesignSystem.Spacing.xs)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showP2PConnectionStatus = true
                            }
                    }
                )
                
                // Tab Selector
                CustomSegmentedPicker(selection: $selectedTab)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.md)
                
                // Content
                TabView(selection: $selectedTab) {
                    // Conversations Tab
                    ConversationsTabView(
                        conversations: $p2pService.conversations,
                        selectedContact: $selectedContact,
                        messageText: $messageText,
                        selectedConversation: $selectedConversation,
                        showConversationDetail: $showConversationDetail,
                        onSendMessage: sendMessage
                    )
                    .tag(0)
                    
                    // Contacts Tab
                    ContactsTabView(
                        contacts: p2pService.contacts,
                        selectedContact: $selectedContact,
                        showAddContact: $showAddContact,
                        newContactAddress: $newContactAddress,
                        newContactName: $newContactName,
                        onAddContact: addContact
                    )
                    .tag(1)
                    
                    // Settings Tab
                    P2PSettingsView(p2pService: p2pService)
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
        .navigationBarHidden(true)
        .alert("Message", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showAddContact) {
            AddContactView(
                address: $newContactAddress,
                name: $newContactName,
                onAdd: addContact
            )
        }
        .sheet(isPresented: $showP2PConnectionStatus) {
            // P2PConnectionStatusView(webRTCManager: webRTCManager)  // Temporarily disabled
        }
        // .onReceive(NotificationCenter.default.publisher(for: .webRTCMessageReceived)) { notification in  // Temporarily disabled
        //     if let message = notification.userInfo?["message"] as? String {
        //         handleP2PMessage(message)
        //     }
        // }
    }
    
    private func sendMessage() {
        guard let contact = selectedContact else {
            alertMessage = "Please select a contact first"
            showAlert = true
            return
        }
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = messageText
        messageText = ""
        p2pService.sendP2PMessage(to: contact.address, content: text)
    }
    
    private func addContact() {
        guard !newContactAddress.isEmpty && !newContactName.isEmpty else {
            alertMessage = "Please enter both address and name"
            showAlert = true
            return
        }
        p2pService.addContact(
            name: newContactName,
            address: newContactAddress,
            publicKey: nil
        )
        newContactAddress = ""
        newContactName = ""
        showAddContact = false
        alertMessage = "Contact added — pubkey will sync when they are online on Halo"
        showAlert = true
    }
}

// MARK: - Conversations Tab View
struct ConversationsTabView: View {
    @Binding var conversations: [P2PConversation]
    @Binding var selectedContact: P2PContact?
    @Binding var messageText: String
    @Binding var selectedConversation: P2PConversation?
    @Binding var showConversationDetail: Bool
    let onSendMessage: () -> Void
    @State private var searchText = ""
    @State private var showNewMessage = false
    @State private var conversationDetailIsTyping = false
    @State private var conversationDetailShowMediaOptions = false
    
    var filteredConversations: [P2PConversation] {
        if searchText.isEmpty {
            return conversations
        } else {
            return conversations.filter { conversation in
                conversation.contactName.localizedCaseInsensitiveContains(searchText) ||
                conversation.participantAddress.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(DesignSystem.Typography.bodyMedium)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                
                if filteredConversations.isEmpty {
                    // Empty State
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Image(systemName: "message.circle")
                            .font(.system(size: 60))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Text(searchText.isEmpty ? "No Conversations" : "No Results")
                            .font(DesignSystem.Typography.titleMedium)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        Text(searchText.isEmpty ? "Add contacts and start messaging to see conversations here" : "Try a different search term")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(DesignSystem.Spacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Conversations List
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.xs) {
                            ForEach(filteredConversations) { conversation in
                                ConversationRowView(conversation: conversation)
                                    .onTapGesture {
                                        // Show conversation detail
                                        selectedConversation = conversation
                                        let contacts = TLSLayer2MessagingService.shared.contacts
                                        if let contact = contacts.first(where: { $0.address == conversation.participantAddress || $0.address == conversation.contactId }) {
                                            selectedContact = contact
                                        } else {
                                            selectedContact = P2PContact(
                                                id: conversation.contactId,
                                                name: conversation.contactName,
                                                address: conversation.contactId,
                                                publicKey: ""
                                            )
                                        }
                                        showConversationDetail = true
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            // TODO: Implement delete conversation
                                            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                                                conversations.remove(at: index)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(.red)
                                    }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.sm)
                    }
                }
                
                // Message Input removed from main list - only appears in conversation detail
            }
            
            // New Message Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showNewMessage = true
                    }) {
                        Image(systemName: "headphones")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(DesignSystem.Colors.secondary)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.lg)
                }
            }
        }
        .sheet(isPresented: $showNewMessage) {
            NewMessageView()
        }
        .sheet(isPresented: $showConversationDetail) {
            if let contact = selectedContact {
                SwitchboardConversationDetailView(
                    contact: contact,
                    conversation: selectedConversation,
                    messageText: $messageText,
                    isTyping: $conversationDetailIsTyping,
                    showMediaOptions: $conversationDetailShowMediaOptions,
                    selectedContact: $selectedContact
                )
            }
        }
    }
}

// MARK: - Switchboard Conversation Detail View
struct SwitchboardConversationDetailView: View {
    let contact: P2PContact
    let conversation: P2PConversation?
    @Binding var messageText: String
    @Binding var isTyping: Bool
    @Binding var showMediaOptions: Bool
    @Binding var selectedContact: P2PContact?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var messages: [P2PMessage] = []
    @State private var typingTimer: Timer?
    @FocusState private var isTextFieldFocused: Bool
    
    private let p2pService = TLSLayer2MessagingService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        messageText = ""
                        selectedContact = nil
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.secondary)
                    }
                    
                    // Contact Info
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Circle()
                            .fill(DesignSystem.Colors.secondary)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(String(contact.name.prefix(1)))
                                    .font(DesignSystem.Typography.bodySmall)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.Colors.text)
                            
                            Text(contact.isOnline ? "Online" : "Offline")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(contact.isOnline ? .green : DesignSystem.Colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    // More options button
                    Menu {
                        Button(action: {
                            // TODO: Implement block contact
                        }) {
                            Label("Block Contact", systemImage: "slash.circle")
                        }
                        
                        Button(role: .destructive, action: {
                            // TODO: Implement delete chat
                        }) {
                            Label("Delete Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surface)
                
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(messages) { message in
                                MessageBubbleView(
                                    message: message,
                                    isFromCurrentUser: message.senderId == (WalletService.shared.loadAddress() ?? "")
                                )
                            }
                            
                            // Typing indicator
                            if isTyping {
                                TypingIndicatorView()
                                    .id("typing")
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                    }
                    .onChange(of: messages.count) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(messages.last?.id ?? "typing", anchor: .bottom)
                        }
                    }
                    .onChange(of: isTyping) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
                
                // Enhanced Message Input
                SwitchboardEnhancedMessageInputView(
                    messageText: $messageText,
                    isTyping: $isTyping,
                    showMediaOptions: $showMediaOptions,
                    onSend: sendMessage
                )
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadMessages()
        }
        .onReceive(p2pService.$messages) { _ in
            loadMessages()
        }
    }
    
    private func loadMessages() {
        messages = p2pService.getMessages(for: contact.address)
        p2pService.markAsRead(contactAddress: contact.address)
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = messageText
        messageText = ""
        p2pService.sendP2PMessage(to: contact.address, content: text)
        loadMessages()
    }
}

// MARK: - Message Bubble View
struct MessageBubbleView: View {
    let message: P2PMessage
    let isFromCurrentUser: Bool
    @State private var showMessageMenu = false
    
    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundColor(isFromCurrentUser ? .white : DesignSystem.Colors.text)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        isFromCurrentUser ? 
                        DesignSystem.Colors.secondary : 
                        DesignSystem.Colors.surface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                
                Text(formatMessageTime(message.timestamp))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
            }
            .contextMenu {
                Button(action: {
                    UIPasteboard.general.string = message.content
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                
                Button(action: {
                    // TODO: Implement forward message
                }) {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
                
                Button(role: .destructive, action: {
                    // TODO: Implement delete message
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
            
            if !isFromCurrentUser {
                Spacer()
            }
        }
    }
    
    private func formatMessageTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Switchboard Enhanced Message Input View
struct SwitchboardEnhancedMessageInputView: View {
    @Binding var messageText: String
    @Binding var isTyping: Bool
    @Binding var showMediaOptions: Bool
    let onSend: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                .focused($isTextFieldFocused)
                .lineLimit(1...4)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? DesignSystem.Colors.textSecondary
                        : DesignSystem.Colors.secondary
                    )
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Switchboard Media Options View
struct SwitchboardMediaOptionsView: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            SwitchboardMediaOptionButton(
                icon: "photo",
                title: "Photo",
                action: {
                    // TODO: Implement photo picker
                }
            )
            
            SwitchboardMediaOptionButton(
                icon: "camera",
                title: "Camera",
                action: {
                    // TODO: Implement camera
                }
            )
            
            SwitchboardMediaOptionButton(
                icon: "doc",
                title: "Document",
                action: {
                    // TODO: Implement document picker
                }
            )
            
            SwitchboardMediaOptionButton(
                icon: "location",
                title: "Location",
                action: {
                    // TODO: Implement location sharing
                }
            )
            
            SwitchboardMediaOptionButton(
                icon: "headphones",
                title: "Audio",
                action: {
                    // TODO: Implement audio recording
                }
            )
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Switchboard Media Option Button
struct SwitchboardMediaOptionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .frame(width: 44, height: 44)
                    .background(DesignSystem.Colors.secondary.opacity(0.1))
                    .clipShape(Circle())
                
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }
}

// MARK: - Typing Indicator View
struct TypingIndicatorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .scaleEffect(animationOffset == CGFloat(index) ? 1.2 : 0.8)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: animationOffset
                            )
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                
                Text("typing...")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
            }
            
            Spacer()
        }
        .onAppear {
            animationOffset = 1
        }
    }
}

// MARK: - Switchboard Message Input View
struct SwitchboardMessageInputView: View {
    @Binding var messageText: String
    @Binding var isTyping: Bool
    @Binding var showMediaOptions: Bool
    let onSend: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Media options (when expanded)
            if showMediaOptions {
                MediaOptionsView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Message input bar
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Media button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showMediaOptions.toggle()
                    }
                }) {
                    Image(systemName: showMediaOptions ? "chevron.down" : "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.secondary)
                        .frame(width: 32, height: 32)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(Circle())
                }
                
                // Text field
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(DesignSystem.Typography.bodyMedium)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                    .focused($isTextFieldFocused)
                    .onChange(of: messageText) {
                        // Handle typing indicator
                        if !messageText.isEmpty {
                            isTyping = true
                        }
                    }
                
                // Send button
                Button(action: {
                    onSend()
                    isTextFieldFocused = false
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                       DesignSystem.Colors.textSecondary : 
                                       DesignSystem.Colors.secondary)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.background)
        }
    }
}

// MARK: - Media Options View
struct MediaOptionsView: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            MediaOptionButton(
                icon: "photo",
                title: "Photo",
                action: { /* Photo picker */ }
            )
            
            MediaOptionButton(
                icon: "gif",
                title: "GIF",
                action: { /* GIF picker */ }
            )
            
            MediaOptionButton(
                icon: "camera",
                title: "Camera",
                action: { /* Camera */ }
            )
            
            MediaOptionButton(
                icon: "doc",
                title: "Document",
                action: { /* Document picker */ }
            )
            
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Media Option Button
struct MediaOptionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.Colors.secondary.opacity(0.1))
                    .clipShape(Circle())
                
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }
}

// MARK: - New Message View
struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedContact: P2PContact?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    TextField("Search by name or TLS address...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(DesignSystem.Typography.bodyMedium)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.sm)
                
                // Contact List
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xs) {
                        ForEach(TLSLayer2MessagingService.shared.contacts.filter { contact in
                            searchText.isEmpty || 
                            contact.name.localizedCaseInsensitiveContains(searchText) ||
                            contact.address.localizedCaseInsensitiveContains(searchText)
                        }) { contact in
                            ContactRowView(contact: contact)
                                .onTapGesture {
                                    selectedContact = contact
                                    dismiss()
                                }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                }
                
                Spacer()
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func getContact(for address: String) -> P2PContact? {
        let contacts = TLSLayer2MessagingService.shared.contacts
        return contacts.first { $0.address == address }
    }
}

// MARK: - Conversation Row View
struct ConversationRowView: View {
    let conversation: P2PConversation
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Avatar
            Circle()
                .fill(DesignSystem.Colors.secondary)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(conversation.contactName.prefix(1)))
                        .font(DesignSystem.Typography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.contactName)
                        .font(DesignSystem.Typography.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Spacer()
                    
                    Text(formatTime(conversation.timestamp))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                HStack {
                    Text(conversation.lastMessage)
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(DesignSystem.Colors.secondary)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Contacts Tab View
struct ContactsTabView: View {
    let contacts: [P2PContact]
    @Binding var selectedContact: P2PContact?
    @Binding var showAddContact: Bool
    @Binding var newContactAddress: String
    @Binding var newContactName: String
    let onAddContact: () -> Void
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if contacts.isEmpty {
                    // Empty State
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Text("No Contacts")
                            .font(DesignSystem.Typography.titleMedium)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        Text("Add contacts to start Switchboard messaging")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        PrimaryButton("Add Contact") {
                            showAddContact = true
                        }
                    }
                    .padding(DesignSystem.Spacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Contacts List
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(contacts) { contact in
                                ContactRowView(contact: contact)
                                    .onTapGesture {
                                        selectedContact = contact
                                    }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                    }
                }
            }
        }
    }
}

// MARK: - Contact Row View
struct ContactRowView: View {
    let contact: P2PContact
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Avatar
            Circle()
                .fill(DesignSystem.Colors.secondary)
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(contact.name.prefix(2)))
                        .font(DesignSystem.Typography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(contact.name)
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.text)
                
                Text(contact.address)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
}

// MARK: - Message Input View
struct HybridMessageInputView: View {
    @Binding var messageText: String
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            TextField("Type a message...", text: $messageText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(DesignSystem.Typography.bodyMedium)
                .onSubmit {
                    onSend()
                }
            
            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.Colors.secondary)
                    .clipShape(Circle())
            }
            .disabled(messageText.isEmpty)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Add Contact View
struct AddContactView: View {
    @Binding var address: String
    @Binding var name: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.secondary)
                    
                    Spacer()
                    
                    Text("Add Contact")
                        .font(DesignSystem.Typography.titleMedium)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Spacer()
                    
                    Button("Add") {
                        onAdd()
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .disabled(address.isEmpty || name.isEmpty)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.lg)
                
                VStack(spacing: DesignSystem.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("TLS Address")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        InputField("Enter TLS wallet address", text: $address)
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Contact Name")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        InputField("Enter contact name", text: $name)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - P2P Settings View
struct P2PSettingsView: View {
    @ObservedObject var p2pService: TLSLayer2MessagingService
    @State private var userName = ""
    @State private var tlsAddress = ""
    @State private var showCopiedAlert = false
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Profile Settings
                    CardView {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            HStack {
                                Text("Profile Settings")
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.text)
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                                // Name Field
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                    Text("Display Name")
                                        .font(DesignSystem.Typography.bodySmall)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    
                                    Text(userName.isEmpty ? "Not set" : userName)
                                        .font(DesignSystem.Typography.bodyMedium)
                                        .foregroundColor(DesignSystem.Colors.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // TLS Address Field
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                    Text("TLS Address")
                                        .font(DesignSystem.Typography.bodySmall)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    
                                    HStack {
                                        TextField("Your TLS address", text: $tlsAddress)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .font(DesignSystem.Typography.bodyMedium)
                                            .disabled(true)
                                        
                                        Button(action: {
                                            UIPasteboard.general.string = tlsAddress
                                            showCopiedAlert = true
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .foregroundColor(DesignSystem.Colors.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Connection Status
                    CardView {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            HStack {
                                Text("Connection Status")
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.text)
                                
                                Spacer()
                                
                                HStack(spacing: DesignSystem.Spacing.sm) {
                                    Circle()
                                        .fill(p2pService.isConnected ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    
                                    Text(p2pService.connectionStatus)
                                        .font(DesignSystem.Typography.bodySmall)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                            }
                            
                            if p2pService.isConnected {
                                Text("✅ Switchboard network active - Messages will be sent instantly")
                                    .font(DesignSystem.Typography.bodySmall)
                                    .foregroundColor(.green)
                            } else {
                                Text("⚠️ Switchboard network unavailable - Messages will use blockchain fallback")
                                    .font(DesignSystem.Typography.bodySmall)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Security Info
                    CardView {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            HStack {
                                Text("Security Features")
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.text)
                                
                                Spacer()
                            }
                            
                            VStack(spacing: DesignSystem.Spacing.sm) {
                                SecurityFeatureRow(
                                    icon: "lock.shield",
                                    title: "End-to-End Encryption",
                                    description: "Messages encrypted with recipient's public key"
                                )
                                
                                SecurityFeatureRow(
                                    icon: "signature",
                                    title: "Digital Signatures",
                                    description: "All messages signed with sender's private key"
                                )
                                
                                SecurityFeatureRow(
                                    icon: "network",
                                    title: "Switchboard Network",
                                    description: "Direct peer-to-peer connections, no central servers"
                                )
                                
                                SecurityFeatureRow(
                                    icon: "blockchain",
                                    title: "Blockchain Identity",
                                    description: "Contact verification through TLS blockchain"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
                .padding(.top, DesignSystem.Spacing.lg)
            }
        }
        .onAppear {
            tlsAddress = WalletService.shared.loadAddress()
                ?? AppGroupsService.shared.getTLSAddress()
                ?? ""
            userName = AppGroupsService.shared.profileDisplayName(tls: tlsAddress)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zeroaDisplayNameDidChange)) { note in
            if let name = note.object as? String {
                userName = name
            }
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK") { }
        } message: {
            Text("TLS address copied to clipboard")
        }
    }
}

// MARK: - Security Feature Row
struct SecurityFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.bodySmall)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.Colors.text)
                
                Text(description)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Custom Segmented Picker
struct CustomSegmentedPicker: View {
    @Binding var selection: Int
    private let options = ["Conversations", "Contacts", "Settings"]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = index
                    }
                }) {
                    Text(options[index])
                        .font(DesignSystem.Typography.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundColor(selection == index ? .white : DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .fill(selection == index ? DesignSystem.Colors.secondary : DesignSystem.Colors.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                if index < options.count - 1 {
                    Spacer()
                        .frame(width: 8)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                .fill(DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                        .stroke(DesignSystem.Colors.secondary.opacity(0.3), lineWidth: 1)
                )
        )
    }
} 

// MARK: - P2P Connection Status View

// Temporarily disabled for simulator testing
/*
struct P2PConnectionStatusView: View {
    @ObservedObject var webRTCManager: WebRTCConnectionManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundColor(webRTCManager.isConnected ? .blue : .gray)
                    
                    Text("P2P Connection Status")
                        .font(DesignSystem.Typography.titleLarge)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Text(webRTCManager.connectionStatus)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.top, DesignSystem.Spacing.xl)
                
                // Connection Details
                VStack(spacing: DesignSystem.Spacing.md) {
                    ConnectionStatusRow(
                        title: "P2P Status",
                        status: webRTCManager.isConnected ? "Connected" : "Disconnected",
                        color: webRTCManager.isConnected ? .green : .red
                    )
                    
                    ConnectionStatusRow(
                        title: "Active Connections",
                        status: "\(webRTCManager.activeConnections.count)",
                        color: .blue
                    )
                    
                    ConnectionStatusRow(
                        title: "STUN Server",
                        status: "stun.l.google.com:19302",
                        color: .blue
                    )
                    
                    ConnectionStatusRow(
                        title: "TURN Server",
                        status: "43.224.35.187:3478",
                        color: .blue
                    )
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: DesignSystem.Spacing.md) {
                    Button(action: {
                        webRTCManager.disconnectAll()
                    }) {
                        Text("Disconnect All")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Close")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationBarHidden(true)
        }
    }
}
*/

struct ConnectionStatusRow: View {
    let title: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.text)
            
            Spacer()
            
            Text(status)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(color)
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
