import Foundation
import Combine

public enum AIBackendType: String, CaseIterable {
    case none = "None"
    case ollama = "Ollama"
    case gemini = "Gemini"
}

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @Published public var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    // Ollama
    @Published public var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }
    @Published public var extractionModel: String {
        didSet { UserDefaults.standard.set(extractionModel, forKey: "extractionModel") }
    }
    @Published public var generationModel: String {
        didSet { UserDefaults.standard.set(generationModel, forKey: "generationModel") }
    }

    // Backend selection
    @Published public var extractionBackend: AIBackendType {
        didSet { UserDefaults.standard.set(extractionBackend.rawValue, forKey: "extractionBackend") }
    }
    @Published public var generationBackend: AIBackendType {
        didSet { UserDefaults.standard.set(generationBackend.rawValue, forKey: "generationBackend") }
    }

    // Gemini
    @Published public var geminiExtractionModel: String {
        didSet { UserDefaults.standard.set(geminiExtractionModel, forKey: "geminiExtractionModel") }
    }
    @Published public var geminiGenerationModel: String {
        didSet { UserDefaults.standard.set(geminiGenerationModel, forKey: "geminiGenerationModel") }
    }

    // Gemini API key — cached in memory, persisted in Keychain
    private var _geminiAPIKeyCache: String? = nil
    public var geminiAPIKey: String {
        get {
            if let cached = _geminiAPIKeyCache { return cached }
            return APIKeychain.load(for: "gemini-api-key") ?? ""
        }
        set {
            _geminiAPIKeyCache = newValue
            if newValue.isEmpty { APIKeychain.delete(for: "gemini-api-key") }
            else { APIKeychain.save(key: newValue, for: "gemini-api-key") }
            objectWillChange.send()
        }
    }

    // Legacy global generation prompt, kept only to migrate older project JSON.
    @Published public var generationPrompt: String {
        didSet { UserDefaults.standard.set(generationPrompt, forKey: "generationPrompt") }
    }

    @Published public var iCloudSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled") }
    }

    public var ollamaReachable: Bool {
        get { OllamaReachability.shared.reachable }
        set { OllamaReachability.shared.reachable = newValue }
    }
    private var pollingTask: Task<Void, Never>?

    public init() {
        fontSize = UserDefaults.standard.double(forKey: "fontSize").nonZero ?? 14
        ollamaBaseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        extractionModel = UserDefaults.standard.string(forKey: "extractionModel") ?? ""
        generationModel = UserDefaults.standard.string(forKey: "generationModel") ?? ""
        extractionBackend = AIBackendType(rawValue: UserDefaults.standard.string(forKey: "extractionBackend") ?? "") ?? .none
        generationBackend = AIBackendType(rawValue: UserDefaults.standard.string(forKey: "generationBackend") ?? "") ?? .none
        geminiExtractionModel = UserDefaults.standard.string(forKey: "geminiExtractionModel") ?? ""
        geminiGenerationModel = UserDefaults.standard.string(forKey: "geminiGenerationModel") ?? ""
        generationPrompt = UserDefaults.standard.string(forKey: "generationPrompt") ?? AppSettings.defaultGenerationPrompt
        iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        startPolling()
    }

    public static let incompatibleGeminiModels: Set<String> = {
        guard let url = Bundle.main.url(forResource: "BlacklistedModels", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let list = dict["gemini"] as? [String] else {
            // Fallback if plist not found
            return ["gemini-2.5-pro", "gemini-2.5-pro-preview-tts", "gemini-2.5-flash-preview-tts"]
        }
        return Set(list)
    }()

    public static let defaultGenerationPrompt = """
        Write 2-3 cohesive paragraphs in formal academic LaTeX style for the Related Works section.
        The paper title and description are provided above — tailor the discussion to highlight how the cited works relate to this specific paper.
        Group related papers thematically, not just list them one by one.
        Incorporate the author annotation notes naturally into the discussion.
        Cite papers using LaTeX \\cite{ID} where ID is the paper's semantic ID (e.g. \\cite{Transformer}, \\cite{BERT}).
        Do NOT include a section heading, just the paragraphs.
        Output only the LaTeX paragraph text, nothing else.
        """

    public func extractionBackendInstance() -> any AIBackend {
        switch extractionBackend {
        case .none: return NoBackend()
        case .ollama: return OllamaBackend(baseURL: ollamaBaseURL, model: extractionModel)
        case .gemini: return GeminiBackend(apiKey: geminiAPIKey, model: geminiExtractionModel)
        }
    }

    public func generationBackendInstance() -> any AIBackend {
        switch generationBackend {
        case .none: return NoBackend()
        case .ollama: return OllamaBackend(baseURL: ollamaBaseURL, model: generationModel)
        case .gemini: return GeminiBackend(apiKey: geminiAPIKey, model: geminiGenerationModel)
        }
    }

    public func startPolling() {
        #if !os(iOS)
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await checkOllama()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        #endif
    }

    public func checkOllama() async {
        let urlStr = ollamaBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(urlStr)/api/tags") else { return }
        let reachable = (try? await URLSession.shared.data(from: url)) != nil
        await MainActor.run {
            let wasReachable = ollamaReachable
            ollamaReachable = reachable
            if !reachable && wasReachable {
                if extractionBackend == .ollama { extractionBackend = .none }
                if generationBackend == .ollama { generationBackend = .none }
            }
        }
    }

    // MARK: - Convenience

    public var activeGenerationModelName: String {
        switch generationBackend {
        case .none: return ""
        case .ollama: return generationModel
        case .gemini: return geminiGenerationModel
        }
    }

    public var activeExtractionModelName: String {
        switch extractionBackend {
        case .none: return ""
        case .ollama: return extractionModel
        case .gemini: return geminiExtractionModel
        }
    }

    public var isGenerationConfigured: Bool {
        switch generationBackend {
        case .none: return false
        case .ollama: return !generationModel.isEmpty
        case .gemini: return !geminiAPIKey.isEmpty && !geminiGenerationModel.isEmpty
        }
    }

    public var isExtractionConfigured: Bool {
        switch extractionBackend {
        case .none: return false
        case .ollama: return !extractionModel.isEmpty
        case .gemini: return !geminiAPIKey.isEmpty && !geminiExtractionModel.isEmpty
        }
    }

    public var shouldShowOllamaBanner: Bool {
        let geminiOk = !geminiAPIKey.isEmpty
        return !geminiOk && !OllamaReachability.shared.reachable
            && (extractionBackend == .ollama || generationBackend == .ollama)
    }

    public func deleteGeminiConfig() {
        geminiAPIKey = ""
        _geminiAPIKeyCache = nil
        if extractionBackend == .gemini { extractionBackend = .none }
        if generationBackend == .gemini { generationBackend = .none }
        objectWillChange.send()
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
