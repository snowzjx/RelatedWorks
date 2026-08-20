import Foundation

// MARK: - AI Backend Protocol

public protocol AIBackend {
    func generate(prompt: String) async throws -> String
    func stream(prompt: String) -> AsyncThrowingStream<String, Error>
}

public extension AIBackend {
    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await generate(prompt: prompt))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - No Backend

public struct NoBackend: AIBackend {
    public init() {}
    public func generate(prompt: String) async throws -> String {
        throw NSError(domain: "AIBackend", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: appLocalized("No AI backend configured. Please configure one in Settings.")])
    }
}

// MARK: - Ollama Backend

public struct OllamaBackend: AIBackend {
    public let baseURL: String
    public let model: String
    public let timeoutInterval: TimeInterval

    public init(baseURL: String, model: String, timeoutInterval: TimeInterval = 300) {
        self.baseURL = baseURL
        self.model = model
        self.timeoutInterval = max(30, timeoutInterval)
    }

    public func generate(prompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeoutInterval
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.7]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let message = parseOllamaErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                throw NSError(
                    domain: "Ollama",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = json["response"] as? String else {
                throw URLError(.cannotParseResponse)
            }
            return response
        } catch {
            let nsError = error as NSError
            let isTimeout = (error as? URLError)?.code == .timedOut
                || nsError.code == NSURLErrorTimedOut
            if isTimeout {
                print("[RelatedWorks] Ollama request timed out for model '\(model)' with timeout \(Int(timeoutInterval))s.")
                throw NSError(
                    domain: "Ollama",
                    code: NSURLErrorTimedOut,
                    userInfo: [
                        NSUnderlyingErrorKey: nsError,
                        NSLocalizedDescriptionKey: appLocalizedFormat(
                            "Ollama timed out after %lld second(s) using model \"%@\". Try increasing timeout in Settings, reducing prompt complexity, or using a smaller model.",
                            Int64(timeoutInterval),
                            model
                        )
                    ]
                )
            }
            throw error
        }
    }

    public func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(baseURL)/api/generate")!
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = timeoutInterval
                    let body: [String: Any] = [
                        "model": model,
                        "prompt": prompt,
                        "stream": true,
                        "options": ["temperature": 0.7]
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        let message = parseOllamaErrorMessage(from: errorData) ?? "HTTP \(http.statusCode)"
                        throw NSError(
                            domain: "Ollama",
                            code: http.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: message]
                        )
                    }

                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        if let response = json["response"] as? String, !response.isEmpty {
                            continuation.yield(response)
                        }
                        if (json["done"] as? Bool) == true {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    let nsError = error as NSError
                    let isTimeout = (error as? URLError)?.code == .timedOut
                        || nsError.code == NSURLErrorTimedOut
                    if isTimeout {
                        print("[RelatedWorks] Ollama stream timed out for model '\(model)' with timeout \(Int(timeoutInterval))s.")
                        continuation.finish(throwing: NSError(
                            domain: "Ollama",
                            code: NSURLErrorTimedOut,
                            userInfo: [
                                NSUnderlyingErrorKey: nsError,
                                NSLocalizedDescriptionKey: appLocalizedFormat(
                                    "Ollama timed out after %lld second(s) using model \"%@\". Try increasing timeout in Settings, reducing prompt complexity, or using a smaller model.",
                                    Int64(timeoutInterval),
                                    model
                                )
                            ]
                        ))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func parseOllamaErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String,
              !error.isEmpty else {
            return nil
        }
        return error
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

    public func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(baseURL)/v1beta/models/\(model):streamGenerateContent?alt=sse")!
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

                    let (bytes, response) = try await geminiSession.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        if let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                           let error = json["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            throw NSError(domain: "Gemini", code: http.statusCode,
                                          userInfo: [NSLocalizedDescriptionKey: message])
                        }
                        throw NSError(domain: "Gemini", code: http.statusCode,
                                      userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                    }

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]",
                              let data = payload.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]] else {
                            continue
                        }
                        for part in parts {
                            if let text = part["text"] as? String, !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI-Compatible Backend

private let cloudAIBackendSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 300
    config.timeoutIntervalForResource = 300
    return URLSession(configuration: config)
}()

public struct OpenAIBackend: AIBackend {
    public static let defaultBaseURL = "https://api.openai.com/v1"

    public let apiKey: String
    public let model: String
    public let baseURL: String
    private let session: URLSession

    public init(
        apiKey: String,
        model: String,
        baseURL: String = OpenAIBackend.defaultBaseURL,
        session: URLSession? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session ?? cloudAIBackendSession
    }

    public func generate(prompt: String) async throws -> String {
        var request = try makeRequest(path: "chat/completions")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
        ])

        let (data, response) = try await session.data(for: request)
        try validateCloudResponse(data: data, response: response, domain: "OpenAI")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return text
    }

    public func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(path: "chat/completions")
                    request.httpMethod = "POST"
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "messages": [["role": "user", "content": prompt]],
                        "stream": true,
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        try validateCloudResponse(data: data, response: response, domain: "OpenAI")
                    }

                    for try await line in bytes.lines {
                        let payload = ssePayload(from: line)
                        guard let payload, payload != "[DONE]",
                              let data = payload.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String,
                              !text.isEmpty else {
                            continue
                        }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func availableModels() async throws -> [String] {
        let request = try makeRequest(path: "models")
        let (data, response) = try await session.data(for: request)
        try validateCloudResponse(data: data, response: response, domain: "OpenAI")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    private func makeRequest(path: String) throws -> URLRequest {
        let root = baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(root)/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 300
        return request
    }
}

// MARK: - Anthropic Backend

public struct AnthropicBackend: AIBackend {
    public static let defaultBaseURL = "https://api.anthropic.com/v1"

    public let apiKey: String
    public let model: String
    public let baseURL: String
    private let session: URLSession

    public init(
        apiKey: String,
        model: String,
        baseURL: String = AnthropicBackend.defaultBaseURL,
        session: URLSession? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session ?? cloudAIBackendSession
    }

    public func generate(prompt: String) async throws -> String {
        var request = try makeRequest(path: "messages")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
        ])

        let (data, response) = try await session.data(for: request)
        try validateCloudResponse(data: data, response: response, domain: "Anthropic")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        let text = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        guard !text.isEmpty else { throw URLError(.cannotParseResponse) }
        return text
    }

    public func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(path: "messages")
                    request.httpMethod = "POST"
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "max_tokens": 4096,
                        "messages": [["role": "user", "content": prompt]],
                        "stream": true,
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        try validateCloudResponse(data: data, response: response, domain: "Anthropic")
                    }

                    for try await line in bytes.lines {
                        guard let payload = ssePayload(from: line),
                              let data = payload.data(using: .utf8),
                              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              json["type"] as? String == "content_block_delta",
                              let delta = json["delta"] as? [String: Any],
                              delta["type"] as? String == "text_delta",
                              let text = delta["text"] as? String,
                              !text.isEmpty else {
                            continue
                        }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func availableModels() async throws -> [String] {
        let request = try makeRequest(path: "models")
        let (data, response) = try await session.data(for: request)
        try validateCloudResponse(data: data, response: response, domain: "Anthropic")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    private func makeRequest(path: String) throws -> URLRequest {
        let root = baseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(root)/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 300
        return request
    }
}

private func ssePayload(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("data:") else { return nil }
    return String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
}

private func validateCloudResponse(data: Data, response: URLResponse, domain: String) throws {
    guard let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) else { return }
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    let message = (json?["error"] as? [String: Any])?["message"] as? String
        ?? appLocalizedFormat("HTTP %lld", Int64(http.statusCode))
    throw NSError(
        domain: domain,
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
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
