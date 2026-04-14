import Foundation

public struct RelatedWorksGenerator {
    public static func generate(for project: Project) async -> String {
        let prompt = buildPrompt(project)
        do {
            return try await callOllama(prompt: prompt)
        } catch {
            let nsErr = error as NSError
            return "⚠️ Generation failed [\(nsErr.domain) \(nsErr.code)]: \(error.localizedDescription)\n\n" + templateDraft(project)
        }
    }

    private static func buildPrompt(_ project: Project) -> String {
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

    private static func callOllama(prompt: String) async throws -> String {
        let backend = AppSettings.shared.generationBackendInstance()
        let response = try await backend.generate(prompt: prompt)
        return stripThinkingBlocks(response).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripThinkingBlocks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>",
                                                    options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(in: text,
                                               range: NSRange(text.startIndex..., in: text),
                                               withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func templateDraft(_ project: Project) -> String {
        project.papers.map { paper in
            let authors = paper.authors.prefix(2).joined(separator: " and ")
            let suffix = paper.authors.count > 2 ? " et al." : ""
            let year = paper.year.map { " (\($0))" } ?? ""
            var s = "\(authors)\(suffix)\(year) proposed \\cite{\(paper.id)}, \(paper.title.lowercased())."
            if !paper.annotation.isEmpty { s += " \(paper.annotation)" }
            return s
        }.joined(separator: "\n\n")
    }
}
