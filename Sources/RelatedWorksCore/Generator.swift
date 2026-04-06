import Foundation

struct RelatedWorksGenerator {
    static func generate(for project: Project) async -> String {
        let prompt = buildPrompt(project)
        if let output = try? await callOllama(prompt: prompt) {
            return output
        }
        return templateDraft(project)
    }

    private static func buildPrompt(_ project: Project) -> String {
        var lines: [String] = []
        lines.append("You are an expert academic writer. Write a Related Works section for a paper titled: \"\(project.name)\".")
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
                lines.append("Abstract (excerpt): \(String(abstract.prefix(300)))")
            }
            lines.append("")
        }

        lines.append("Instructions:")
        lines.append("- Write 2-3 cohesive paragraphs in formal academic LaTeX style")
        lines.append("- Group related papers thematically, not just list them one by one")
        lines.append("- Incorporate the author notes naturally into the discussion")
        lines.append("- Cite papers using LaTeX \\cite{ID} where ID is the paper's semantic ID (e.g. \\cite{Transformer}, \\cite{BERT})")
        lines.append("- Do NOT include a section heading, just the paragraphs")
        lines.append("- Output only the LaTeX paragraph text, nothing else")

        return lines.joined(separator: "\n")
    }

    private static func callOllama(prompt: String) async throws -> String {
        let url = URL(string: "\(AppSettings.shared.ollamaBaseURL)/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let body: [String: Any] = ["model": AppSettings.shared.generationModel, "prompt": prompt, "stream": false,
                                    "options": ["temperature": 0.7]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            throw URLError(.cannotParseResponse)
        }
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

    static func templateDraft(_ project: Project) -> String {
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
