import Foundation

/// Holds Ollama reachability state separately from AppSettings so that
/// polling updates do not trigger a full re-render of the main window tree.
public class OllamaReachability: ObservableObject {
    public static let shared = OllamaReachability()
    @Published public var reachable: Bool = true
}
