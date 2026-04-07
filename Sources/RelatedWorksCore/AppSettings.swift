import Foundation
import Combine

public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    @Published var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }
    @Published var extractionModel: String {
        didSet { UserDefaults.standard.set(extractionModel, forKey: "extractionModel") }
    }
    @Published public var generationModel: String {
        didSet { UserDefaults.standard.set(generationModel, forKey: "generationModel") }
    }
    @Published var generationPrompt: String {
        didSet { UserDefaults.standard.set(generationPrompt, forKey: "generationPrompt") }
    }
    @Published var ollamaReachable: Bool = true

    private var pollingTask: Task<Void, Never>?

    public init() {
        fontSize = UserDefaults.standard.double(forKey: "fontSize").nonZero ?? 14
        ollamaBaseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        extractionModel = UserDefaults.standard.string(forKey: "extractionModel") ?? "gemma3:4b"
        generationModel = UserDefaults.standard.string(forKey: "generationModel") ?? "qwen3:latest"
        generationPrompt = UserDefaults.standard.string(forKey: "generationPrompt") ?? AppSettings.defaultGenerationPrompt
        startPolling()
    }

    static let defaultGenerationPrompt = """
        Write 2-3 cohesive paragraphs in formal academic LaTeX style for the Related Works section.
        The paper title and description are provided above — tailor the discussion to highlight how the cited works relate to this specific paper.
        Group related papers thematically, not just list them one by one.
        Incorporate the author annotation notes naturally into the discussion.
        Cite papers using LaTeX \\cite{ID} where ID is the paper's semantic ID (e.g. \\cite{Transformer}, \\cite{BERT}).
        Do NOT include a section heading, just the paragraphs.
        Output only the LaTeX paragraph text, nothing else.
        """

    public func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await checkOllama()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    public func checkOllama() async {
        let urlStr = ollamaBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(urlStr)/api/tags") else { return }
        let reachable = (try? await URLSession.shared.data(from: url)) != nil
        await MainActor.run { ollamaReachable = reachable }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
