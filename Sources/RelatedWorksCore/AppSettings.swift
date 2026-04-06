import Foundation
import Combine

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    @Published var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: "ollamaBaseURL") }
    }
    @Published var extractionModel: String {
        didSet { UserDefaults.standard.set(extractionModel, forKey: "extractionModel") }
    }
    @Published var generationModel: String {
        didSet { UserDefaults.standard.set(generationModel, forKey: "generationModel") }
    }
    @Published var ollamaReachable: Bool = true

    private var pollingTask: Task<Void, Never>?

    init() {
        fontSize = UserDefaults.standard.double(forKey: "fontSize").nonZero ?? 14
        ollamaBaseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        extractionModel = UserDefaults.standard.string(forKey: "extractionModel") ?? "gemma3:4b"
        generationModel = UserDefaults.standard.string(forKey: "generationModel") ?? "qwen3:latest"
        startPolling()
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await checkOllama()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func checkOllama() async {
        let urlStr = ollamaBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(urlStr)/api/tags") else { return }
        let reachable = (try? await URLSession.shared.data(from: url)) != nil
        await MainActor.run { ollamaReachable = reachable }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
