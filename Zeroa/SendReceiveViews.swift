import SwiftUI
import Combine
import AVFoundation

// MARK: - Send/Receive Models
struct SendTransactionData {
    var toAddress: String = ""
    var amount: String = ""
    var fee: String = ""
    var priority: SendTransactionRequest.TransactionPriority = .medium
    var message: String = ""
    var coinType: CoinType = .telestai
    var isProcessing: Bool = false
    var errorMessage: String = ""
    var successMessage: String = ""
    var fiatAmount: String = ""
    var selectedCurrency: String = "USD"
    var showFiatInput: Bool = false
}

struct ReceiveData {
    var address: String = ""
    var qrCodeData: Data?
    var coinType: CoinType = .telestai
    var shareEnabled: Bool = false
}

// MARK: - Send Transaction View
struct SendTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    private let walletService = WalletService.shared
    @State private var transactionData = SendTransactionData()
    @State private var showConfirmation = false
    @State private var showCoinPicker = false
    @State private var availableCoins: [CoinType] = []
    @State private var isLoading = false
    @State private var showSuccessToast = false
    @State private var estimatedFee: Double = 0.0
    @State private var showQRScanner = false
    @State private var selectedCurrency: String = "USD"
    @State private var availableCurrencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD"]
    @State private var coinPrice: Double = 0.0
    @State private var currentBalance: Double = 0.0
    @StateObject private var tlsService = TLSBlockchainService.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        // Header
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Text("Send")
                                .font(DesignSystem.Typography.titleMedium)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.text)
                            
                            Text("Send cryptocurrency to another address")
                                .font(DesignSystem.Typography.bodyMedium)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, DesignSystem.Spacing.xl)
                        .padding(.bottom, DesignSystem.Spacing.lg)
                    
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
                                Image(transactionData.coinType.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(transactionData.coinType.name)
                                        .font(DesignSystem.Typography.bodyMedium)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignSystem.Colors.text)
                                    
                                    Text(transactionData.coinType.symbol)
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
                            .shadow(color: DesignSystem.Shadows.small, radius: 4, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Recipient Address
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Recipient Address")
                            .font(DesignSystem.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        HStack {
                            TextField("Enter address", text: $transactionData.toAddress)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(DesignSystem.Typography.bodyMedium)
                                .onChange(of: transactionData.toAddress) { _, _ in
                                    validateAddress()
                                    updateFeeEstimate()
                                }
                            
                            Button(action: {
                                showQRScanner = true
                            }) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 20))
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Amount Input
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Amount")
                            .font(DesignSystem.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        HStack {
                            TextField(transactionData.showFiatInput ? "0.00" : "0.00000000", text: transactionData.showFiatInput ? $transactionData.fiatAmount : $transactionData.amount)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                                .font(DesignSystem.Typography.bodyMedium)
                                .onChange(of: transactionData.showFiatInput ? transactionData.fiatAmount : transactionData.amount) { _, _ in
                                    if transactionData.showFiatInput {
                                        updateCryptoAmount()
                                    } else {
                                        validateAmount()
                                        updateFiatAmount()
                                    }
                                    updateFeeEstimate()
                                }
                            
                            Text(transactionData.showFiatInput ? selectedCurrency : transactionData.coinType.symbol)
                                .font(DesignSystem.Typography.bodyMedium)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        // Conversion Display
                        if !transactionData.fiatAmount.isEmpty && !transactionData.showFiatInput {
                            Text("≈ \(selectedCurrency) \(transactionData.fiatAmount)")
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        } else if !transactionData.amount.isEmpty && transactionData.showFiatInput {
                            Text("≈ \(transactionData.amount) \(transactionData.coinType.symbol)")
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        // Currency Toggle
                        Button(action: {
                            toggleCurrencyInput()
                        }) {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 12))
                                Text(transactionData.showFiatInput ? "Show Crypto Amount" : "Show Fiat Amount")
                            }
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundColor(DesignSystem.Colors.secondary)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Fee Display (automatically calculated)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Transaction Fee")
                            .font(DesignSystem.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        if estimatedFee > 0 {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.secondary)
                                
                                Text("Fee: \(String(format: "%.8f", estimatedFee)) \(transactionData.coinType.symbol)")
                                    .font(DesignSystem.Typography.bodySmall)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(DesignSystem.CornerRadius.small)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(DesignSystem.CornerRadius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Message (Optional)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text("Message (Optional)")
                            .font(DesignSystem.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.Colors.text)
                        
                        TextField("Add a message", text: $transactionData.message)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(DesignSystem.Typography.bodyMedium)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Error Message
                    if !transactionData.errorMessage.isEmpty {
                        Text(transactionData.errorMessage)
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundColor(.red)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    // Success Message
                    if !transactionData.successMessage.isEmpty {
                        Text(transactionData.successMessage)
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundColor(.green)
                            .padding(.horizontal, DesignSystem.Spacing.lg)
                    }
                    
                    // Send Button at Bottom
                    Button(action: {
                        showConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Send")
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.secondary)
                        .cornerRadius(DesignSystem.CornerRadius.medium)
                    }
                    .disabled(!isFormValid() || isLoading)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.md)
                    
                    Spacer()
                }
            }
            if showSuccessToast {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 24, weight: .bold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transaction Sent!")
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            if !transactionData.successMessage.isEmpty {
                                Text(transactionData.successMessage)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                        Button("OK") {
                            showSuccessToast = false
                            dismiss()
                        }
                        .font(DesignSystem.Typography.bodySmall)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(DesignSystem.CornerRadius.small)
                    }
                    .padding()
                    .background(LinearGradient(colors: [DesignSystem.Colors.secondary, DesignSystem.Colors.primary], startPoint: .leading, endPoint: .trailing).opacity(0.95))
                    .cornerRadius(DesignSystem.CornerRadius.large)
                    .padding()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSuccessToast)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadAvailableCoins()
            loadSettings()
            loadCoinPrice()
            updateFeeEstimate()
            loadBalance()
        }
        .onChange(of: transactionData.coinType) { _, _ in
            loadBalance()
            updateFeeEstimate()
        }
        .sheet(isPresented: $showCoinPicker) {
            CoinPickerView(selectedCoin: $transactionData.coinType, availableCoins: availableCoins)
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { scannedAddress in
                transactionData.toAddress = scannedAddress
            }
        }
        .alert("Confirm Transaction", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Send", role: .destructive) {
                sendTransaction()
            }
        } message: {
            Text("Are you sure you want to send \(transactionData.amount) \(transactionData.coinType.symbol) to \(transactionData.toAddress)?")
        }
    }
    
    // MARK: - Helper Methods
    private func loadAvailableCoins() {
        // Only show TLS (Telestai) coin
        availableCoins = [.telestai]
    }
    
    private func loadSettings() {
        selectedCurrency = UserDefaults.standard.string(forKey: "user_currency") ?? "USD"
    }
    
    private func loadCoinPrice() {
        // Load coin price for currency conversion
        Task {
            let price = await getCoinPrice()
            await MainActor.run {
                coinPrice = price
                updateFiatAmount()
            }
        }
    }
    
    private func getCoinPrice() async -> Double {
        // Mock price - in real implementation, get from price service
        switch transactionData.coinType {
        case .telestai: return 0.00058144
        case .bitcoin: return 45000.0
        case .flux: return 0.85
        case .litecoin: return 120.0
        case .kaspa: return 0.12
        case .usdt: return 1.0
        case .usdc: return 1.0
        }
    }
    
    private func updateFiatAmount() {
        guard let amount = Double(transactionData.amount), amount > 0 else {
            transactionData.fiatAmount = ""
            return
        }
        
        let fiatValue = amount * coinPrice
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        if let formattedValue = formatter.string(from: NSNumber(value: fiatValue)) {
            transactionData.fiatAmount = formattedValue
        }
    }
    
    private func updateCryptoAmount() {
        guard let fiatAmount = Double(transactionData.fiatAmount), fiatAmount > 0 else {
            transactionData.amount = ""
            return
        }
        
        let cryptoValue = fiatAmount / coinPrice
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        
        if let formattedValue = formatter.string(from: NSNumber(value: cryptoValue)) {
            transactionData.amount = formattedValue
        }
    }
    
    private func convertFiatToCrypto() {
        updateCryptoAmount()
    }
    
    private func toggleCurrencyInput() {
        transactionData.showFiatInput.toggle()
        if transactionData.showFiatInput {
            // Convert crypto amount to fiat
            updateFiatAmount()
        } else {
            // Convert fiat amount back to crypto
            convertFiatToCrypto()
        }
    }
    
    private func toggleCurrencyConversion() {
        // Toggle between showing fiat and crypto amount
        // This could be expanded to allow users to input fiat amount
    }
    
    private func getCoinBalance() -> Double? {
        // Get actual balance from the wallet service for the selected coin
        switch transactionData.coinType {
        case .telestai:
            // Return the real balance from TLSBlockchainService
            return currentBalance
        case .bitcoin: return 0.00123456
        case .litecoin: return 0.56789012
        case .flux: return 123.456789
        case .kaspa: return 45.67890123
        case .usdt: return 1000.0
        case .usdc: return 500.0
        }
    }
    
    private func loadBalance() {
        Task {
            if transactionData.coinType == .telestai {
                if let address = WalletService.shared.loadAddress() {
                    if let addressInfo = await tlsService.getAddressInfo(address: address) {
                        await MainActor.run {
                            currentBalance = addressInfo.balance
                            print("✅ SendTransactionView: Balance updated to \(currentBalance) TLS")
                        }
                    } else {
                        await MainActor.run {
                            currentBalance = 0.0
                            print("⚠️ SendTransactionView: Failed to load balance, using 0.0")
                        }
                    }
                } else {
                    print("❌ SendTransactionView: No wallet address found")
                }
            }
        }
    }
    
    private func validateAddress() {
        // Address validation logic
        transactionData.errorMessage = ""
    }
    
    private func validateAmount() {
        guard let amount = Double(transactionData.amount), amount > 0 else {
            transactionData.errorMessage = "Please enter a valid amount"
            return
        }
        
        // Account for transaction fee when checking balance
        let totalNeeded = amount + estimatedFee
        
        if let balance = getCoinBalance() {
            if totalNeeded > balance {
                transactionData.errorMessage = "Insufficient balance. Available: \(String(format: "%.8f", balance)) TLS, Needed: \(String(format: "%.8f", totalNeeded)) TLS"
                return
            }
        } else {
            transactionData.errorMessage = "Could not retrieve balance"
            return
        }
        
        transactionData.errorMessage = ""
    }
    
    private func updateFeeEstimate() {
        Task {
            let fee = await getNetworkFeeEstimate()
            await MainActor.run {
                estimatedFee = fee
            }
        }
    }
    
    private func getNetworkFeeEstimate() async -> Double {
        // Get fee estimate from the specific coin's network
        switch transactionData.coinType {
        case .telestai:
            return await getTelestaiFeeEstimate()
        case .bitcoin:
            return await getBitcoinFeeEstimate()
        case .litecoin:
            return await getLitecoinFeeEstimate()
        case .flux:
            return await getFluxFeeEstimate()
        case .kaspa:
            return await getKaspaFeeEstimate()
        case .usdt:
            return await getUSDTFeeEstimate()
        case .usdc:
            return await getUSDCFeeEstimate()
        }
    }
    
    private func getTelestaiFeeEstimate() async -> Double {
        // Telestai network fee estimation - automatically calculated based on transaction size
        // Estimate a typical transaction size (1 input, 2 outputs = ~250 bytes)
        let typicalSize = FeeEstimationService.shared.estimateTransactionSize(inputCount: 1, outputCount: 2)
        return await FeeEstimationService.shared.estimateFee(transactionSizeBytes: typicalSize)
    }
    
    private func getBitcoinFeeEstimate() async -> Double {
        // Bitcoin network fee estimation
        switch transactionData.priority {
        case .low: return 0.00001
        case .medium: return 0.00002
        case .high: return 0.00005
        }
    }
    
    private func getLitecoinFeeEstimate() async -> Double {
        // Litecoin network fee estimation
        switch transactionData.priority {
        case .low: return 0.0001
        case .medium: return 0.0002
        case .high: return 0.0005
        }
    }
    
    private func getFluxFeeEstimate() async -> Double {
        // Flux network fee estimation
        switch transactionData.priority {
        case .low: return 0.001
        case .medium: return 0.002
        case .high: return 0.005
        }
    }
    
    private func getKaspaFeeEstimate() async -> Double {
        // Kaspa network fee estimation
        switch transactionData.priority {
        case .low: return 0.0001
        case .medium: return 0.0002
        case .high: return 0.0005
        }
    }
    
    private func getUSDTFeeEstimate() async -> Double {
        // USDT network fee estimation
        switch transactionData.priority {
        case .low: return 0.00001
        case .medium: return 0.00002
        case .high: return 0.00005
        }
    }
    
    private func getUSDCFeeEstimate() async -> Double {
        // USDC network fee estimation
        switch transactionData.priority {
        case .low: return 0.00001
        case .medium: return 0.00002
        case .high: return 0.00005
        }
    }
    
    private func isFormValid() -> Bool {
        return !transactionData.toAddress.isEmpty &&
               !transactionData.amount.isEmpty &&
               transactionData.errorMessage.isEmpty
    }
    
    private func sendTransaction() {
        guard let amount = Double(transactionData.amount), amount > 0 else {
            transactionData.errorMessage = "Please enter a valid amount"
            return
        }
        
        guard !transactionData.toAddress.isEmpty else {
            transactionData.errorMessage = "Please enter a recipient address"
            return
        }
        
        isLoading = true
        transactionData.errorMessage = ""
        transactionData.successMessage = ""
        
        Task {
            // Use real TLS transaction service
            if transactionData.coinType == .telestai {
                let response = await TLSBlockchainService.shared.sendPayment(
                    toAddress: transactionData.toAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: amount,
                    message: transactionData.message.isEmpty ? nil : transactionData.message,
                    messageType: transactionData.message.isEmpty ? nil : "text"
                )
                
                await MainActor.run {
                    isLoading = false
                    
                    if response.success {
                        transactionData.successMessage = "Transaction sent successfully! TXID: \(response.txid?.prefix(16) ?? "unknown")..."
                        showSuccessToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            dismiss()
                        }
                    } else {
                        transactionData.errorMessage = response.error ?? "Transaction failed"
                    }
                }
            } else {
                // For other coins, use MultiCoinTransactionService (currently mocked)
                // This will be implemented when other coins are re-enabled
                await MainActor.run {
                    isLoading = false
                    transactionData.errorMessage = "Only TLS (Telestai) transactions are currently supported"
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getPriorityColor(_ priority: SendTransactionRequest.TransactionPriority) -> Color {
        switch priority {
        case .low:
            return Color.green
        case .medium:
            return Color.orange
        case .high:
            return Color.red
        }
    }
    

}

// MARK: - Receive Transaction View
struct ReceiveTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    private let walletService = WalletService.shared
    @State private var receiveData = ReceiveData()
    @State private var showCoinPicker = false
    @State private var availableCoins: [CoinType] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                DesignSystem.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.xl) {
                        // Header
                        VStack(spacing: DesignSystem.Spacing.md) {
                            Text("Receive")
                                .font(DesignSystem.Typography.titleMedium)
                                .fontWeight(.bold)
                                .foregroundColor(DesignSystem.Colors.text)
                            
                            Text("Receive cryptocurrency from another address")
                                .font(DesignSystem.Typography.bodyMedium)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, DesignSystem.Spacing.xl)
                    
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
                                Image(receiveData.coinType.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(receiveData.coinType.name)
                                        .font(DesignSystem.Typography.bodyMedium)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignSystem.Colors.text)
                                    
                                    Text(receiveData.coinType.symbol)
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
                            .shadow(color: DesignSystem.Shadows.small, radius: 4, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // QR Code Display
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        if let qrCodeData = receiveData.qrCodeData,
                           let uiImage = UIImage(data: qrCodeData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 200, height: 200)
                                .padding(DesignSystem.Spacing.lg)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.medium)
                        } else {
                            Rectangle()
                                .fill(DesignSystem.Colors.surface)
                                .frame(width: 200, height: 200)
                                .cornerRadius(DesignSystem.CornerRadius.medium)
                                .overlay(
                                    Text("QR Code")
                                        .font(DesignSystem.Typography.bodyMedium)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                )
                        }
                        
                        // Address Display
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            Text("Your Address")
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.Colors.text)
                            
                            Button(action: {
                                copyAddressToClipboard()
                            }) {
                                VStack(spacing: DesignSystem.Spacing.sm) {
                                    Text(receiveData.address)
                                        .font(DesignSystem.Typography.bodySmall)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(3)
                                        .minimumScaleFactor(0.8)
                                    
                                    HStack(spacing: DesignSystem.Spacing.xs) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                        Text("Tap to copy")
                                            .font(DesignSystem.Typography.bodySmall)
                                    }
                                    .foregroundColor(DesignSystem.Colors.secondary)
                                }
                                .padding(DesignSystem.Spacing.md)
                                .frame(maxWidth: .infinity)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(DesignSystem.CornerRadius.medium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    
                    // Share Button
                    Button(action: {
                        shareAddress()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Share Address")
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.secondary)
                        .cornerRadius(DesignSystem.CornerRadius.medium)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.md)
                    
                    Spacer()
                }
            }
        }
        .navigationTitle("Receive")
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadAvailableCoins()
            generateReceiveAddress()
        }
        .onChange(of: receiveData.coinType) { _, _ in
            generateReceiveAddress()
        }
        .sheet(isPresented: $showCoinPicker) {
            CoinPickerView(selectedCoin: $receiveData.coinType, availableCoins: availableCoins)
        }
    }
    
    private func loadAvailableCoins() {
        // Only show TLS (Telestai) coin
        availableCoins = [.telestai]
    }
    
    private func generateReceiveAddress() {
        switch receiveData.coinType {
        case .telestai:
            // Use AddressManager to get next receive address (address rotation)
            if let addr = AddressManager.shared.getNextReceiveAddress() {
                receiveData.address = addr
            } else if let addr = walletService.loadAddress() {
                receiveData.address = addr
            } else {
                receiveData.address = ""
            }
        case .flux:
            receiveData.address = AppGroupsService.shared.getFluxAddress() ?? ""
        default:
            receiveData.address = ""
        }
        generateQRCode()
    }
    
    private func generateQRCode() {
        // Generate QR code for the address
        let qrCodeString = receiveData.address
        if let qrCodeData = generateQRCodeData(from: qrCodeString) {
            receiveData.qrCodeData = qrCodeData
        }
    }
    
    private func generateQRCodeData(from string: String) -> Data? {
        // Simple QR code generation - in real app, use a proper QR library
        guard let data = string.data(using: .utf8) else { return nil }
        return data
    }
    
    private func copyAddressToClipboard() {
        UIPasteboard.general.string = receiveData.address
    }
    
    private func shareAddress() {
        // Create a formatted message for sharing
        let shareMessage = """
        My \(receiveData.coinType.name) address:
        \(receiveData.address)
        
        Sent from PAAI Wallet
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [shareMessage],
            applicationActivities: nil
        )
        
        // Exclude specific activity types that aren't useful for address sharing
        activityVC.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks,
            .markupAsPDF
        ]
        
        // Prevent iPad from showing as popover
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = nil
            popover.sourceRect = CGRect.zero
            popover.permittedArrowDirections = []
        }
        
        // Find the topmost view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            var topController = window.rootViewController
            while let presentedController = topController?.presentedViewController {
                topController = presentedController
            }
            topController?.present(activityVC, animated: true)
        }
    }
}

// MARK: - Supporting Views
struct CoinPickerView: View {
    @Binding var selectedCoin: CoinType
    let availableCoins: [CoinType]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(availableCoins, id: \.self) { coin in
                        Button(action: {
                            selectedCoin = coin
                            dismiss()
                        }) {
                            HStack(spacing: DesignSystem.Spacing.md) {
                                // Coin Icon
                                Image(coin.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                                    .padding(DesignSystem.Spacing.sm)
                                    .background(
                                        Circle()
                                            .fill(DesignSystem.Colors.surface)
                                            .frame(width: 48, height: 48)
                                    )
                                
                                // Coin Details
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(coin.name)
                                        .font(DesignSystem.Typography.bodyMedium)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DesignSystem.Colors.text)
                                    
                                    Text(coin.symbol)
                                        .font(DesignSystem.Typography.bodySmall)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                // Selection Indicator
                                if selectedCoin == coin {
                                    ZStack {
                                        Circle()
                                            .fill(DesignSystem.Colors.secondary)
                                            .frame(width: 24, height: 24)
                                        
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                } else {
                                    Circle()
                                        .stroke(DesignSystem.Colors.border, lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .padding(DesignSystem.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                    .fill(DesignSystem.Colors.surface)
                                    .shadow(color: DesignSystem.Shadows.small, radius: 2, x: 0, y: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                    .stroke(selectedCoin == coin ? DesignSystem.Colors.secondary : DesignSystem.Colors.border, lineWidth: selectedCoin == coin ? 2 : 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Select Coin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.secondary)
                }
            }
        }
        .background(DesignSystem.Colors.background)
    }
}

struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = false
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Scan QR Code")
                    .font(DesignSystem.Typography.titleMedium)
                    .padding()
                
                // Placeholder for QR scanner
                Rectangle()
                    .fill(DesignSystem.Colors.surface)
                    .frame(height: 300)
                    .overlay(
                        Text("QR Scanner Placeholder")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    )
                
                Button("Cancel") {
                    dismiss()
                }
                .padding()
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
