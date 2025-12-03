import SwiftUI
import Combine
import UIKit

// MARK: - Transaction History View
struct TransactionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var transactionService = MultiCoinTransactionService.shared
    @StateObject private var tlsService = TLSBlockchainService.shared
    @State private var selectedCoin: CoinType = .telestai
    @State private var selectedFilter: TransactionFilter = .all
    @State private var searchText = ""
    @State private var showTransactionDetail = false
    @State private var selectedTransaction: WalletTransaction?
    @State private var isLoading = false
    @State private var showCoinPicker = false
    @State private var availableCoins: [CoinType] = [.telestai]
    @State private var receiveAddresses: [(index: UInt32, address: String)] = []
    @State private var changeAddresses: [(index: UInt32, address: String)] = []
    @State private var showAddressManager = false
    @AppStorage("zeroa_reuse_primary_change") private var reusePrimaryChange = false
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case received = "Received"
        case pending = "Pending"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .sent: return "arrow.up"
            case .received: return "arrow.down"
            case .pending: return "clock"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Transaction History")
                        .font(DesignSystem.Typography.titleMedium)
                        .fontWeight(.bold)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Text("View your transaction history")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, DesignSystem.Spacing.lg)
                
                // Coin Selection
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Select Coin")
                        .font(DesignSystem.Typography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Button(action: {
                        showCoinPicker = true
                    }) {
                        HStack {
                            Image(selectedCoin.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedCoin.name)
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.text)
                                
                                Text(selectedCoin.symbol)
                                    .font(DesignSystem.Typography.bodySmall)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                    }
                }
                
                // Filter and Search
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Filter Picker
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(TransactionFilter.allCases, id: \.self) { filter in
                            HStack {
                                Image(systemName: filter.icon)
                                Text(filter.rawValue)
                            }
                            .tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        TextField("Search transactions", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                }
                
                if shouldShowTelestaiExtras {
                    Button(action: {
                        showAddressManager = true
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("View Telestai addresses")
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.Colors.text)
                                Text("See all receive/change paths tied to this wallet")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                    }
                }
                
                // Transaction List
                if isLoading {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.primary))
                        
                        Text("Loading transactions...")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredTransactions.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Text("No transactions found")
                            .font(DesignSystem.Typography.bodyLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        Text("Your transaction history will appear here")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(filteredTransactions, id: \.id) { transaction in
                                TransactionRowView(transaction: transaction) {
                                    selectedTransaction = transaction
                                    showTransactionDetail = true
                                }
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showCoinPicker) {
            CoinPickerView(selectedCoin: $selectedCoin, availableCoins: availableCoins)
        }
        .sheet(isPresented: $showTransactionDetail) {
            if let transaction = selectedTransaction {
                TransactionDetailView(transaction: transaction)
            }
        }
        .sheet(isPresented: $showAddressManager) {
            NavigationView {
                ScrollView {
                    telestaiAddressSection
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.vertical, DesignSystem.Spacing.md)
                }
                .background(DesignSystem.Colors.background)
                .navigationTitle("Telestai Addresses")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            showAddressManager = false
                        }
                    }
                }
            }
        }
        .onAppear {
            loadAvailableCoins()
            loadAddressLists()
            loadTransactions()
        }
        .onChange(of: selectedCoin) { _ in
            loadTransactions()
        }
        .onChange(of: selectedFilter) { _ in
            // Filter is applied automatically through computed property
        }
    }
    
    // MARK: - Computed Properties
    private var filteredTransactions: [WalletTransaction] {
        var transactions = telestaiWalletTransactions
        
        // Filter by type
        switch selectedFilter {
        case .all:
            break
        case .sent:
            transactions = transactions.filter { $0.type == .send }
        case .received:
            transactions = transactions.filter { $0.type == .receive }
        case .pending:
            transactions = transactions.filter { $0.status == .pending }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            transactions = transactions.filter { transaction in
                transaction.txid.localizedCaseInsensitiveContains(searchText) ||
                (transaction.fromAddress?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (transaction.toAddress?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Sort by date (newest first)
        return transactions.sorted { $0.timestamp > $1.timestamp }
    }
    
    private var shouldShowTelestaiExtras: Bool {
        selectedCoin == .telestai
    }
    
    private var telestaiWalletTransactions: [WalletTransaction] {
        tlsService.recentTransactions.map { mapTelestaiTransaction($0) }
    }
    
    // MARK: - Helper Methods
    private func loadAvailableCoins() {
        availableCoins = transactionService.supportedCoins
    }
    
    private func loadTransactions() {
        isLoading = tlsService.recentTransactions.isEmpty
        
        Task {
            await tlsService.refreshBalance()
            
            await MainActor.run {
                loadAddressLists()
                isLoading = false
            }
        }
    }
    
    private func loadAddressLists() {
        let manager = AddressManager.shared
        receiveAddresses = manager.getUsedReceiveAddressInfos()
        changeAddresses = manager.getUsedChangeAddressInfos()
    }
    
    @ViewBuilder
    private var telestaiAddressSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            CardView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Toggle("Reuse primary address for change outputs", isOn: $reusePrimaryChange)
                        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.secondary))
                    
                    Text(reusePrimaryChange
                         ? "Remaining funds will always return to your main wallet address. This is simpler but offers less privacy."
                         : "Zeroa rotates through change addresses so outgoing transactions stay private. Disable this if you prefer everything sent back to your main address.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            CardView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    Text("Active Wallet Addresses")
                        .font(DesignSystem.Typography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Text("Transactions below include every receive and change address derived from your seed (\(receiveAddresses.count + changeAddresses.count) total).")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    addressListCard(title: "Receive Addresses", addresses: receiveAddresses)
                    addressListCard(title: "Change Addresses", addresses: changeAddresses)
                }
            }
        }
    }
    
    @ViewBuilder
    private func addressListCard(title: String, addresses: [(index: UInt32, address: String)]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.text)
                Spacer()
                Text("\(addresses.count)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            if addresses.isEmpty {
                Text("No addresses have been derived yet.")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            } else {
                ForEach(Array(addresses.enumerated()), id: \.offset) { item in
                    let entry = item.element
                    HStack(spacing: DesignSystem.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(entry.index)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text(entry.address)
                                .font(DesignSystem.Typography.bodySmall)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(DesignSystem.Colors.text)
                        }
                        
                        Spacer()
                        
                        Button {
                            UIPasteboard.general.string = entry.address
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(DesignSystem.Colors.secondary)
                        }
                        .accessibilityLabel("Copy address #\(entry.index)")
                    }
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(DesignSystem.Colors.surface.opacity(0.5))
                    .cornerRadius(DesignSystem.CornerRadius.medium)
                }
            }
        }
    }
    
    private func mapTelestaiTransaction(_ transaction: TLSTransaction) -> WalletTransaction {
        let lowerType = transaction.type.lowercased()
        let txType: WalletTransaction.TransactionType = lowerType == "send" ? .send : .receive
        let amount = txType == .send ? -abs(transaction.amount) : abs(transaction.amount)
        let status: WalletTransaction.TransactionStatus = transaction.confirmations > 0 ? .confirmed : .pending
        let date = Date(timeIntervalSince1970: TimeInterval(transaction.timestamp))
        
        return WalletTransaction(
            coinType: .telestai,
            txid: transaction.txid,
            amount: amount,
            fee: transaction.fee,
            confirmations: transaction.confirmations,
            timestamp: date,
            type: txType,
            fromAddress: transaction.from,
            toAddress: transaction.to,
            blockHeight: nil,
            status: status
        )
    }
}

// MARK: - Transaction Row View
struct TransactionRowView: View {
    let transaction: WalletTransaction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Transaction Icon
                ZStack {
                    Circle()
                        .fill(transaction.type == .send ? DesignSystem.Colors.error : DesignSystem.Colors.success)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: transaction.type == .send ? "arrow.up" : "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Transaction Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(transaction.type == .send ? "Sent" : "Received")
                            .font(DesignSystem.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        Spacer()
                        
                        Text("\(transaction.formattedAmount) \(transaction.coinType.symbol)")
                            .font(DesignSystem.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(transaction.type == .send ? DesignSystem.Colors.error : DesignSystem.Colors.success)
                    }
                    
                    HStack {
                        Text(formatDate(transaction.timestamp))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text(transaction.status.rawValue.capitalized)
                            .font(DesignSystem.Typography.bodySmall)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.1))
                            .cornerRadius(DesignSystem.CornerRadius.small)
                    }
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.medium)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .confirmed:
            return DesignSystem.Colors.success
        case .pending:
            return DesignSystem.Colors.warning
        case .failed:
            return DesignSystem.Colors.error
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Transaction Detail View
struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let transaction: WalletTransaction
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(transaction.type == .send ? DesignSystem.Colors.error : DesignSystem.Colors.success)
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: transaction.type == .send ? "arrow.up" : "arrow.down")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text(transaction.type == .send ? "Sent" : "Received")
                            .font(DesignSystem.Typography.titleMedium)
                            .fontWeight(.bold)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        Text("\(transaction.formattedAmount) \(transaction.coinType.symbol)")
                            .font(DesignSystem.Typography.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(transaction.type == .send ? DesignSystem.Colors.error : DesignSystem.Colors.success)
                    }
                    .padding(.top, DesignSystem.Spacing.lg)
                    
                    // Transaction Details
                    VStack(spacing: DesignSystem.Spacing.md) {
                        // Transaction Details
                        VStack(spacing: DesignSystem.Spacing.md) {
                            TransactionDetailRow(title: "Transaction ID", value: transaction.txid)
                            TransactionDetailRow(title: "Amount", value: "\(String(format: "%.8f", abs(transaction.amount))) \(transaction.coinType.symbol)")
                            TransactionDetailRow(title: "Fee", value: "\(String(format: "%.8f", transaction.fee)) \(transaction.coinType.symbol)")
                            TransactionDetailRow(title: "Status", value: transaction.status.rawValue.capitalized)
                            TransactionDetailRow(title: "Confirmations", value: "\(transaction.confirmations)")
                            TransactionDetailRow(title: "Date", value: formatDate(transaction.timestamp))
                            
                            if let fromAddress = transaction.fromAddress {
                                TransactionDetailRow(title: "From", value: fromAddress)
                            }
                            
                            if let toAddress = transaction.toAddress {
                                TransactionDetailRow(title: "To", value: toAddress)
                            }
                        }
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(DesignSystem.CornerRadius.medium)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Transaction Detail Row
struct TransactionDetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundColor(DesignSystem.Colors.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
} 