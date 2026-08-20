import Foundation
import UIKit
import CryptoKit

enum LogLevel: String, Codable {
    case error = "error"
    case warn = "warn"
    case info = "info"
    case debug = "debug"
}

struct LogEntry: Codable {
    let timestamp: Int64
    let level: LogLevel
    let message: String
    let device: DeviceInfo
    let context: LogContext?
    let metadata: [String: String]?
}

struct DeviceInfo: Codable {
    let type: String
    let osVersion: String
    let appVersion: String
    let deviceId: String
}

struct LogContext: Codable {
    let function: String?
    let file: String?
    let line: Int?
    let userId: String? // Truncated to first 10 chars
}

@MainActor
class RemoteLoggingService: ObservableObject {
    static let shared = RemoteLoggingService()
    
    private let baseURL = "https://halo.telestai.io/api/logs"
    private var logBuffer: [LogEntry] = []
    private let maxBufferSize = 1000
    private let batchSize = 50
    private let batchInterval: TimeInterval = 30.0 // 30 seconds
    private var batchTimer: Timer?
    private var isSending = false
    
    private init() {
        startBatchTimer()
    }
    
    // MARK: - Public Logging Methods
    
    func log(level: LogLevel, message: String, function: String? = nil, file: String? = nil, line: Int? = nil, metadata: [String: String]? = nil) {
        let entry = createLogEntry(level: level, message: message, function: function, file: file, line: line, metadata: metadata)
        addToBuffer(entry)
    }
    
    func error(_ message: String, function: String = #function, file: String = #file, line: Int = #line, metadata: [String: String]? = nil) {
        log(level: .error, message: message, function: function, file: file, line: line, metadata: metadata)
    }
    
    func warn(_ message: String, function: String = #function, file: String = #file, line: Int = #line, metadata: [String: String]? = nil) {
        log(level: .warn, message: message, function: function, file: file, line: line, metadata: metadata)
    }
    
    func info(_ message: String, function: String = #function, file: String = #file, line: Int = #line, metadata: [String: String]? = nil) {
        log(level: .info, message: message, function: function, file: file, line: line, metadata: metadata)
    }
    
    #if DEBUG
    func debug(_ message: String, function: String = #function, file: String = #file, line: Int = #line, metadata: [String: String]? = nil) {
        log(level: .debug, message: message, function: function, file: file, line: line, metadata: metadata)
    }
    #else
    func debug(_ message: String, function: String = #function, file: String = #file, line: Int = #line, metadata: [String: String]? = nil) {
        // Debug logs only in debug builds
    }
    #endif
    
    // MARK: - Private Methods
    
    private func createLogEntry(level: LogLevel, message: String, function: String?, file: String?, line: Int?, metadata: [String: String]?) -> LogEntry {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000) // milliseconds
        
        // Get device info
        let deviceInfo = DeviceInfo(
            type: "ios",
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            deviceId: getDeviceId()
        )
        
        // Get user ID (truncated)
        let userId: String? = {
            // Try to get from AppGroupsService
            if let tlsAddress = AppGroupsService.shared.getTLSAddress(), !tlsAddress.isEmpty {
                return String(tlsAddress.prefix(10)) + "..."
            }
            return nil
        }()
        
        let context = LogContext(
            function: function,
            file: file?.components(separatedBy: "/").last,
            line: line,
            userId: userId
        )
        
        // Sanitize metadata
        let sanitizedMetadata = sanitizeMetadata(metadata)
        
        return LogEntry(
            timestamp: timestamp,
            level: level,
            message: message,
            device: deviceInfo,
            context: context,
            metadata: sanitizedMetadata
        )
    }
    
    private func sanitizeMetadata(_ metadata: [String: String]?) -> [String: String]? {
        guard var metadata = metadata else { return nil }
        
        // Truncate tokens
        if let token = metadata["token"], token.count > 8 {
            let prefix = String(token.prefix(4))
            let suffix = String(token.suffix(4))
            metadata["token"] = "\(prefix)...\(suffix)"
        }
        
        // Truncate content
        if let content = metadata["content"], content.count > 50 {
            metadata["content"] = String(content.prefix(50)) + "..."
        }
        
        return metadata
    }
    
    private func getDeviceId() -> String {
        // Use identifierForVendor for device ID
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        // Fallback to a random ID stored in UserDefaults
        let defaults = UserDefaults.standard
        if let storedId = defaults.string(forKey: "lasko_device_id") {
            return storedId
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: "lasko_device_id")
        return newId
    }
    
    private func addToBuffer(_ entry: LogEntry) {
        logBuffer.append(entry)
        
        // Drop oldest if buffer exceeds max size
        if logBuffer.count > maxBufferSize {
            logBuffer.removeFirst(logBuffer.count - maxBufferSize)
        }
        
        // Send immediately if batch size reached
        if logBuffer.count >= batchSize {
            sendBatch()
        }
    }
    
    private func startBatchTimer() {
        batchTimer = Timer.scheduledTimer(withTimeInterval: batchInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendBatch()
            }
        }
    }
    
    private func sendBatch() {
        guard !isSending, !logBuffer.isEmpty else { return }
        
        isSending = true
        let batch = Array(logBuffer.prefix(batchSize))
        logBuffer.removeFirst(min(batchSize, logBuffer.count))
        
        Task {
            await sendLogs(batch)
            await MainActor.run {
                isSending = false
            }
        }
    }
    
    private func sendLogs(_ logs: [LogEntry]) async {
        guard let url = URL(string: baseURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(logs)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 400 {
                    print("⚠️ RemoteLogging: Failed to send logs: \(httpResponse.statusCode)")
                    // Re-add logs to buffer on failure (but limit retries)
                    await MainActor.run {
                        logBuffer.insert(contentsOf: logs, at: 0)
                        if logBuffer.count > maxBufferSize {
                            logBuffer = Array(logBuffer.prefix(maxBufferSize))
                        }
                    }
                }
            }
        } catch {
            print("⚠️ RemoteLogging: Error sending logs: \(error.localizedDescription)")
            // Re-add logs to buffer on failure
            await MainActor.run {
                logBuffer.insert(contentsOf: logs, at: 0)
                if logBuffer.count > maxBufferSize {
                    logBuffer = Array(logBuffer.prefix(maxBufferSize))
                }
            }
        }
    }
    
    // Force send all buffered logs (useful for app termination)
    func flush() {
        sendBatch()
    }
}

