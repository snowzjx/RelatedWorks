import Foundation
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chineseSimplified = "zh-Hans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:
            return appLocalized("Follow System")
        case .english:
            return appLocalized("English")
        case .chineseSimplified:
            return appLocalized("Chinese (Simplified)")
        }
    }

    public var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: rawValue)
        case .chineseSimplified:
            return Locale(identifier: rawValue)
        }
    }
}

public enum AIBackendType: String, CaseIterable {
    case none = "None"
    case ollama = "Ollama"
    case gemini = "Gemini"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"

    public var displayName: String {
        switch self {
        case .none:
            return appLocalized("None")
        case .ollama:
            return appLocalized("Ollama")
        case .gemini:
            return appLocalized("Gemini")
        case .openAI:
            return appLocalized("OpenAI")
        case .anthropic:
            return appLocalized("Anthropic")
        }
    }
}

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @Published public var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    @Published public var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            applyLanguagePreference()
        }
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
    @Published public var ollamaTimeoutSeconds: Int {
        didSet {
            let clamped = Self.clampOllamaTimeout(ollamaTimeoutSeconds)
            if clamped != ollamaTimeoutSeconds {
                ollamaTimeoutSeconds = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "ollamaTimeoutSeconds")
        }
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

    // OpenAI and compatible APIs
    @Published public var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: "openAIBaseURL") }
    }
    @Published public var openAIExtractionModel: String {
        didSet { UserDefaults.standard.set(openAIExtractionModel, forKey: "openAIExtractionModel") }
    }
    @Published public var openAIGenerationModel: String {
        didSet { UserDefaults.standard.set(openAIGenerationModel, forKey: "openAIGenerationModel") }
    }
    private var _openAIAPIKeyCache: String? = nil
    public var openAIAPIKey: String {
        get {
            if let cached = _openAIAPIKeyCache { return cached }
            return APIKeychain.load(for: "openai-api-key") ?? ""
        }
        set {
            _openAIAPIKeyCache = newValue
            if newValue.isEmpty { APIKeychain.delete(for: "openai-api-key") }
            else { APIKeychain.save(key: newValue, for: "openai-api-key") }
            objectWillChange.send()
        }
    }

    // Anthropic
    @Published public var anthropicExtractionModel: String {
        didSet { UserDefaults.standard.set(anthropicExtractionModel, forKey: "anthropicExtractionModel") }
    }
    @Published public var anthropicGenerationModel: String {
        didSet { UserDefaults.standard.set(anthropicGenerationModel, forKey: "anthropicGenerationModel") }
    }
    private var _anthropicAPIKeyCache: String? = nil
    public var anthropicAPIKey: String {
        get {
            if let cached = _anthropicAPIKeyCache { return cached }
            return APIKeychain.load(for: "anthropic-api-key") ?? ""
        }
        set {
            _anthropicAPIKeyCache = newValue
            if newValue.isEmpty { APIKeychain.delete(for: "anthropic-api-key") }
            else { APIKeychain.save(key: newValue, for: "anthropic-api-key") }
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

    public init(pollsOllama: Bool = true) {
        fontSize = UserDefaults.standard.double(forKey: "fontSize").nonZero ?? 14
        appLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        ollamaBaseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        extractionModel = UserDefaults.standard.string(forKey: "extractionModel") ?? ""
        generationModel = UserDefaults.standard.string(forKey: "generationModel") ?? ""
        ollamaTimeoutSeconds = Self.clampOllamaTimeout(
            UserDefaults.standard.object(forKey: "ollamaTimeoutSeconds") as? Int ?? 300
        )
        extractionBackend = AIBackendType(rawValue: UserDefaults.standard.string(forKey: "extractionBackend") ?? "") ?? .none
        generationBackend = AIBackendType(rawValue: UserDefaults.standard.string(forKey: "generationBackend") ?? "") ?? .none
        geminiExtractionModel = UserDefaults.standard.string(forKey: "geminiExtractionModel") ?? ""
        geminiGenerationModel = UserDefaults.standard.string(forKey: "geminiGenerationModel") ?? ""
        openAIBaseURL = UserDefaults.standard.string(forKey: "openAIBaseURL") ?? OpenAIBackend.defaultBaseURL
        openAIExtractionModel = UserDefaults.standard.string(forKey: "openAIExtractionModel") ?? ""
        openAIGenerationModel = UserDefaults.standard.string(forKey: "openAIGenerationModel") ?? ""
        anthropicExtractionModel = UserDefaults.standard.string(forKey: "anthropicExtractionModel") ?? ""
        anthropicGenerationModel = UserDefaults.standard.string(forKey: "anthropicGenerationModel") ?? ""
        generationPrompt = UserDefaults.standard.string(forKey: "generationPrompt") ?? AppSettings.defaultGenerationPrompt
        iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        applyLanguagePreference()
        if pollsOllama {
            startPolling()
        }
    }

    public var locale: Locale {
        appLanguage.locale
    }

    public var localizationBundle: Bundle {
        guard appLanguage != .system,
              let path = Bundle.main.path(forResource: appLanguage.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    public func localizedString(_ key: String, defaultValue: String? = nil) -> String {
        localizationBundle.localizedString(forKey: key, value: defaultValue ?? key, table: nil)
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
        case .ollama:
            return OllamaBackend(
                baseURL: ollamaBaseURL,
                model: extractionModel,
                timeoutInterval: TimeInterval(ollamaTimeoutSeconds)
            )
        case .gemini: return GeminiBackend(apiKey: geminiAPIKey, model: geminiExtractionModel)
        case .openAI:
            return OpenAIBackend(apiKey: openAIAPIKey, model: openAIExtractionModel, baseURL: openAIBaseURL)
        case .anthropic:
            return AnthropicBackend(apiKey: anthropicAPIKey, model: anthropicExtractionModel)
        }
    }

    public func generationBackendInstance() -> any AIBackend {
        switch generationBackend {
        case .none: return NoBackend()
        case .ollama:
            return OllamaBackend(
                baseURL: ollamaBaseURL,
                model: generationModel,
                timeoutInterval: TimeInterval(ollamaTimeoutSeconds)
            )
        case .gemini: return GeminiBackend(apiKey: geminiAPIKey, model: geminiGenerationModel)
        case .openAI:
            return OpenAIBackend(apiKey: openAIAPIKey, model: openAIGenerationModel, baseURL: openAIBaseURL)
        case .anthropic:
            return AnthropicBackend(apiKey: anthropicAPIKey, model: anthropicGenerationModel)
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
            ollamaReachable = reachable
        }
    }

    // MARK: - Convenience

    public var activeGenerationModelName: String {
        switch generationBackend {
        case .none: return ""
        case .ollama: return generationModel
        case .gemini: return geminiGenerationModel
        case .openAI: return openAIGenerationModel
        case .anthropic: return anthropicGenerationModel
        }
    }

    public var activeExtractionModelName: String {
        switch extractionBackend {
        case .none: return ""
        case .ollama: return extractionModel
        case .gemini: return geminiExtractionModel
        case .openAI: return openAIExtractionModel
        case .anthropic: return anthropicExtractionModel
        }
    }

    public var isGenerationConfigured: Bool {
        switch generationBackend {
        case .none: return false
        case .ollama: return !generationModel.isEmpty
        case .gemini: return !geminiAPIKey.isEmpty && !geminiGenerationModel.isEmpty
        case .openAI: return isOpenAIProviderConfigured && !openAIGenerationModel.isEmpty
        case .anthropic: return !anthropicAPIKey.isEmpty && !anthropicGenerationModel.isEmpty
        }
    }

    public var isExtractionConfigured: Bool {
        switch extractionBackend {
        case .none: return false
        case .ollama: return !extractionModel.isEmpty
        case .gemini: return !geminiAPIKey.isEmpty && !geminiExtractionModel.isEmpty
        case .openAI: return isOpenAIProviderConfigured && !openAIExtractionModel.isEmpty
        case .anthropic: return !anthropicAPIKey.isEmpty && !anthropicExtractionModel.isEmpty
        }
    }

    public var isOpenAIProviderConfigured: Bool {
        let configuredURL = openAIBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let defaultURL = OpenAIBackend.defaultBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        return !openAIAPIKey.isEmpty || configuredURL != defaultURL
    }

    public var shouldShowOllamaBanner: Bool {
        return !OllamaReachability.shared.reachable
            && (extractionBackend == .ollama || generationBackend == .ollama)
    }

    public func deleteGeminiConfig() {
        geminiAPIKey = ""
        _geminiAPIKeyCache = nil
        if extractionBackend == .gemini { extractionBackend = .none }
        if generationBackend == .gemini { generationBackend = .none }
        objectWillChange.send()
    }

    public func deleteOpenAIConfig() {
        openAIAPIKey = ""
        _openAIAPIKeyCache = nil
        openAIBaseURL = OpenAIBackend.defaultBaseURL
        if extractionBackend == .openAI { extractionBackend = .none }
        if generationBackend == .openAI { generationBackend = .none }
        objectWillChange.send()
    }

    public func deleteAnthropicConfig() {
        anthropicAPIKey = ""
        _anthropicAPIKeyCache = nil
        if extractionBackend == .anthropic { extractionBackend = .none }
        if generationBackend == .anthropic { generationBackend = .none }
        objectWillChange.send()
    }

    private func applyLanguagePreference() {
        switch appLanguage {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english, .chineseSimplified:
            UserDefaults.standard.set([appLanguage.rawValue], forKey: "AppleLanguages")
        }
    }

    private static func clampOllamaTimeout(_ value: Int) -> Int {
        min(1800, max(30, value))
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

public func appLocalized(_ key: String) -> String {
    AppSettings.shared.localizedString(key)
}

public func appLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(
        format: AppSettings.shared.localizedString(key),
        locale: AppSettings.shared.locale,
        arguments: arguments
    )
}
