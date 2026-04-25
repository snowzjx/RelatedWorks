import Foundation

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

    private static func generateWithConfiguredBackend(prompt: String) async throws -> String {
        let backend = AppSettings.shared.generationBackendInstance()
        let response = try await backend.generate(prompt: prompt)
        return cleanGeneratedText(response)
    }

    private static func cleanGeneratedText(_ text: String) -> String {
        stripThinkingBlocks(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripThinkingBlocks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>",
                                                    options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(in: text,
                                               range: NSRange(text.startIndex..., in: text),
                                               withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
