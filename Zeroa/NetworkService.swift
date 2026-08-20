import Foundation

class NetworkService {
    static let shared = NetworkService()
    private let apiUrl = "https://api.x.ai/v1/chat/completions"
    
    // Load API key from environment or configuration
    private var apiKey: String {
        // First try to get from environment variable
        if let envKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] {
            print("🔑 API Key loaded from environment variable: \(String(envKey.prefix(10)))...")
            return envKey
        }
        
        // Try to get from keychain (user-entered)
        if let keychainKey = WalletService.shared.keychain.read(key: "xai_api_key") {
            print("🔑 API Key loaded from keychain: \(String(keychainKey.prefix(10)))...")
            return keychainKey
        }
        
        // Fallback to a local config file (not tracked in git)
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let key = config["XAI_API_KEY"] as? String,
           key != "REPLACE_WITH_YOUR_ACTUAL_XAI_API_KEY_HERE" {
            print("🔑 API Key loaded from Config.plist: \(String(key.prefix(10)))...")
            return key
        }
        
        // Return empty string if not found (will cause auth error)
        print("❌ No API key found in environment, keychain, or config file!")
        print("💡 Please configure your xAI API key in Config.plist")
        return ""
    }

    func getGrokResponse(input: String, completion: @escaping (Result<String, Error>) -> Void) {
#if DEBUG
        print("🌐 Making API request to: \(apiUrl)")
        print("📝 Input: \(input)")
#endif
        
        // Check if API key is available
        guard !apiKey.isEmpty else {
            print("❌ No API key available")
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No API key configured. Please enter your xAI API key in Profile & Settings."])))
            return
        }
        
        guard let url = URL(string: apiUrl) else { 
            print("❌ Invalid URL")
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": "grok-3",
            "messages": [["role": "user", "content": input]],
            "max_tokens": 500,
            "temperature": 0.7
        ]
        
#if DEBUG
        print("🔑 Authorization header: Bearer \(String(apiKey.prefix(10)))...")
#endif
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
#if DEBUG
                print("📡 HTTP Status Code: \(httpResponse.statusCode)")
                print("📡 HTTP Headers: \(httpResponse.allHeaderFields)")
#endif
            }
            
            if let data = data {
#if DEBUG
                print("📦 Response data length: \(data.count) bytes")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📦 Response body: \(responseString)")
                }
#endif
            }
            
            guard let data = data else {
                print("❌ No response data")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response data"])))
                return
            }
            
            // Check for API key error first
            if let responseString = String(data: data, encoding: .utf8),
               responseString.contains("Incorrect API key") {
                print("❌ Invalid API key")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid API key. Please check your xAI API key in Profile & Settings."])))
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                print("❌ Failed to parse response JSON")
#if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📦 Raw response: \(responseString)")
                }
#endif
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                return
            }
            
            print("✅ Successfully parsed response")
#if DEBUG
            print("📄 Content: \(content)")
#endif
            completion(.success(content))
        }.resume()
    }
} 