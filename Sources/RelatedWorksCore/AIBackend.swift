import Foundation

// MARK: - AI Backend Protocol

public protocol AIBackend {
    func generate(prompt: String) async throws -> String
}

// MARK: - No Backend

public struct NoBackend: AIBackend {
    public init() {}
    public func generate(prompt: String) async throws -> String {
        throw NSError(domain: "AIBackend", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "No AI backend configured. Please configure one in Settings."])
    }
}

// MARK: - Ollama Backend

public struct OllamaBackend: AIBackend {
    public let baseURL: String
    public let model: String

    public init(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    public func generate(prompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false,
                                   "options": ["temperature": 0.7]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return response
    }
}

// MARK: - Gemini Backend

private let geminiSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 300
    config.timeoutIntervalForResource = 300
    return URLSession(configuration: config)
}()

public struct GeminiBackend: AIBackend {
    public let apiKey: String
    public let model: String
    public let baseURL: String

    public init(apiKey: String, model: String, baseURL: String = "https://generativelanguage.googleapis.com") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    public func generate(prompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1beta/models/\(model):generateContent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 300
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.7,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Use static session so it isn't deallocated mid-request
        let (data, response) = try await geminiSession.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: "Gemini", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "Gemini", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }
}

// MARK: - Keychain helper for API key

public enum APIKeychain {
    private static let service = "me.snowzjx.relatedworks"

    public static func save(key: String, for account: String) {
        let data = key.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func load(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
