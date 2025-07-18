import SwiftUI

struct HybridMessagingView: View {
    @StateObject private var p2pService = TLSLayer2MessagingService.shared
    @State private var selectedTab = 0
    @State private var messageText = ""
    @State private var selectedContact: P2PContact?
    @State private var showAddContact = false
    @State private var newContactAddress = ""
    @State private var newContactName = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Back Button
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                            Text("Back")
                                .font(DesignSystem.Typography.bodyMedium)
                        }
                        .foregroundColor(DesignSystem.Colors.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Switchboard")
                        .font(DesignSystem.Typography.titleMedium)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Spacer()
                    
                    // Connection Status
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Circle()
                            .fill(p2pService.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        
                        Text(p2pService.connectionStatus)
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.surface)
                
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
                        onSendMessage: sendMessage
                    )
                    .tag(0)
                    
                    // Contacts Tab
                    ContactsTabView(
                        contacts: p2pService.getContacts(),
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
    }
    
    private func sendMessage() {
        guard let contact = selectedContact else {
            alertMessage = "Please select a contact first"
            showAlert = true
            return
        }
        
        guard !messageText.isEmpty else { return }
        
        Task {
            let success = await p2pService.sendP2PMessage(
                to: contact.address,
                content: messageText
            )
            
            await MainActor.run {
                if success {
                    messageText = ""
                    alertMessage = "Message sent successfully!"
                } else {
                    alertMessage = "Failed to send message"
                }
                showAlert = true
            }
        }
    }
    
    private func addContact() {
        guard !newContactAddress.isEmpty && !newContactName.isEmpty else {
            alertMessage = "Please enter both address and name"
            showAlert = true
            return
        }
        
        Task {
            let success = await p2pService.addContact(
                address: newContactAddress,
                name: newContactName
            )
            
            await MainActor.run {
                if success {
                    newContactAddress = ""
                    newContactName = ""
                    showAddContact = false
                    alertMessage = "Contact added successfully!"
                } else {
                    alertMessage = "Failed to add contact. Please verify the address."
                }
                showAlert = true
            }
        }
    }
}

// MARK: - Conversations Tab View
struct ConversationsTabView: View {
    @Binding var conversations: [P2PConversation]
    @Binding var selectedContact: P2PContact?
    @Binding var messageText: String
    let onSendMessage: () -> Void
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if conversations.isEmpty {
                    // Empty State
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Image(systemName: "message.circle")
                            .font(.system(size: 60))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Text("No Conversations")
                            .font(DesignSystem.Typography.titleMedium)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        Text("Add contacts and start messaging to see conversations here")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(DesignSystem.Spacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Conversations List
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(conversations) { conversation in
                                ConversationRowView(conversation: conversation)
                                    .onTapGesture {
                                        // Select this conversation
                                        if let contact = getContact(for: conversation.participantAddress) {
                                            selectedContact = contact
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                    }
                }
                
                // Message Input (if contact selected)
                if selectedContact != nil {
                    HybridMessageInputView(
                        messageText: $messageText,
                        onSend: onSendMessage
                    )
                }
            }
        }
    }
    
    private func getContact(for address: String) -> P2PContact? {
        let contacts = TLSLayer2MessagingService.shared.getContacts()
        return contacts.first { $0.address == address }
    }
}

// MARK: - Conversation Row View
struct ConversationRowView: View {
    let conversation: P2PConversation
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Avatar
            Circle()
                .fill(DesignSystem.Colors.secondary)
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(conversation.participantAddress.prefix(2)))
                        .font(DesignSystem.Typography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(conversation.participantAddress)
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.text)
                
                Text(conversation.lastMessage)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
                Text(formatTime(conversation.lastMessageTime))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("\(conversation.messages.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
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
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
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