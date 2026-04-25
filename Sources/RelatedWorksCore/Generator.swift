import Foundation

public enum RelatedWorksGenerationEvent: Equatable {
    case thinking(Bool)
    case output(String)
}

public struct RelatedWorksGenerator {
    public static func generate(for project: Project) async -> String {
        let prompt = buildPrompt(project)
        do {
            return try await generateWithConfiguredBackend(prompt: prompt)
        } catch {
            return friendlyFailureMessage(for: error)
        }
    }

    public static func buildPrompt(_ project: Project) -> String {
        var lines: [String] = []
        lines.append("You are an expert academic writer.")
        lines.append("Write a Related Works section for a paper titled: \"\(project.name)\".")
        if !project.description.isEmpty {
            lines.append("Paper description: \(project.description)")
        }
        lines.append("")
        lines.append("Below are the papers to discuss, with author notes and cross-references between them:")
        lines.append("")

        for paper in project.papers {
            let authors = paper.authors.prefix(3).joined(separator: ", ")
            let suffix = paper.authors.count > 3 ? " et al." : ""
            let cite = "\(authors)\(suffix) (\(paper.year ?? 0))"
            lines.append("## \(paper.id)")
            lines.append("Title: \(paper.title)")
            lines.append("Citation: \(cite)\(paper.venue.map { ", \($0)" } ?? "")")
            if !paper.annotation.isEmpty {
                var annotation = paper.annotation
                for ref in project.papers where ref.id != paper.id {
                    annotation = annotation.replacingOccurrences(of: "@\(ref.id)", with: "\(ref.title) [\(ref.id)]")
                }
                lines.append("Notes: \(annotation)")
            }
            if let abstract = paper.abstract, !abstract.isEmpty {
                lines.append("Abstract: \(abstract)")
            }
            lines.append("")
        }

        lines.append("Instructions:")
        lines.append(project.generationPrompt)

        return lines.joined(separator: "\n")
    }

    public static func generate(for project: Project, using backend: any AIBackend) async -> String {
        let prompt = buildPrompt(project)
        do {
            let response = try await backend.generate(prompt: prompt)
            return cleanGeneratedText(response)
        } catch {
            return friendlyFailureMessage(for: error)
        }
    }

    public static func stream(for project: Project) -> AsyncStream<String> {
        stream(for: project, using: AppSettings.shared.generationBackendInstance())
    }

    public static func stream(for project: Project, using backend: any AIBackend) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                for await event in streamEvents(for: project, using: backend) {
                    guard case let .output(output) = event else { continue }
                    continuation.yield(output)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func streamEvents(for project: Project) -> AsyncStream<RelatedWorksGenerationEvent> {
        streamEvents(for: project, using: AppSettings.shared.generationBackendInstance())
    }

    public static func streamEvents(for project: Project, using backend: any AIBackend) -> AsyncStream<RelatedWorksGenerationEvent> {
        let prompt = buildPrompt(project)
        return AsyncStream { continuation in
            let task = Task {
                var rawOutput = ""
                var lastVisibleOutput = ""
                var wasThinking = false

                do {
                    for try await chunk in backend.stream(prompt: prompt) {
                        rawOutput += chunk
                        let isThinking = hasOpenThinkingBlock(rawOutput)
                        if isThinking != wasThinking {
                            wasThinking = isThinking
                            continuation.yield(.thinking(isThinking))
                        }

                        let visibleOutput = visibleGeneratedText(rawOutput)
                        guard visibleOutput != lastVisibleOutput else { continue }
                        lastVisibleOutput = visibleOutput
                        continuation.yield(.output(visibleOutput))
                    }

                    let finalOutput = cleanGeneratedText(rawOutput)
                    if wasThinking {
                        continuation.yield(.thinking(false))
                    }
                    if finalOutput != lastVisibleOutput {
                        continuation.yield(.output(finalOutput))
                    }
                    continuation.finish()
                } catch {
                    if wasThinking {
                        continuation.yield(.thinking(false))
                    }
                    continuation.yield(.output(friendlyFailureMessage(for: error)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func generateWithConfiguredBackend(prompt: String) async throws -> String {
        let backend = AppSettings.shared.generationBackendInstance()
        let response = try await backend.generate(prompt: prompt)
        return cleanGeneratedText(response)
    }

    private static func cleanGeneratedText(_ text: String) -> String {
        stripThinkingBlocks(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func visibleGeneratedText(_ text: String) -> String {
        stripThinkingBlocks(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripThinkingBlocks(_ text: String) -> String {
        var result = text
        while let openRange = result.range(of: "<think", options: .caseInsensitive) {
            guard let tagEnd = result.range(of: ">",
                                            range: openRange.upperBound..<result.endIndex) else {
                result.removeSubrange(openRange.lowerBound..<result.endIndex)
                break
            }

            guard let closeRange = result.range(of: "</think>",
                                                options: .caseInsensitive,
                                                range: tagEnd.upperBound..<result.endIndex) else {
                result.removeSubrange(openRange.lowerBound..<result.endIndex)
                break
            }

            result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }
        return result
    }

    private static func hasOpenThinkingBlock(_ text: String) -> Bool {
        guard let openRange = text.range(of: "<think", options: .caseInsensitive) else { return false }
        guard let tagEnd = text.range(of: ">",
                                      range: openRange.upperBound..<text.endIndex) else {
            return true
        }
        return text.range(of: "</think>",
                          options: .caseInsensitive,
                          range: tagEnd.upperBound..<text.endIndex) == nil
    }

    private static func friendlyFailureMessage(for error: Error) -> String {
        let nsErr = error as NSError
        let isTimeout = (error as? URLError)?.code == .timedOut || nsErr.code == NSURLErrorTimedOut
        let model = AppSettings.shared.activeGenerationModelName
        let modelText = model.isEmpty ? appLocalized("the selected model") : model

        if isTimeout {
            return [
                appLocalizedFormat("⚠️ Generation took too long and timed out with %@.", modelText),
                "",
                appLocalized("You did nothing wrong."),
                appLocalized("To reduce timeouts, try increasing Ollama timeout in Settings, using a smaller model, or simplifying the prompt.")
            ].joined(separator: "\n")
        }

        return [
            appLocalizedFormat("⚠️ I couldn't generate text this time [%@ %lld].", nsErr.domain, Int64(nsErr.code)),
            error.localizedDescription
        ].joined(separator: "\n")
    }
}
