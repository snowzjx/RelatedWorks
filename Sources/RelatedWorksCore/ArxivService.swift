import Foundation

public struct ArxivResult {
    public let title: String
    public let authors: [String]
    public let year: Int?
    public let abstract: String?
    public let arxivID: String?
}

public struct ArxivService {
    public static func search(query: String) async throws -> [ArxivResult] {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "all:\(query)"),
            URLQueryItem(name: "max_results", value: "5"),
            URLQueryItem(name: "sortBy", value: "relevance"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return parse(data)
    }

    private static func parse(_ data: Data) -> [ArxivResult] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        // Simple regex-based extraction of entry blocks
        let entryPattern = #"<entry>([\s\S]*?)</entry>"#
        guard let entryRegex = try? NSRegularExpression(pattern: entryPattern) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = entryRegex.matches(in: xml, range: range)

        return matches.compactMap { match -> ArxivResult? in
            guard let r = Range(match.range(at: 1), in: xml) else { return nil }
            let entry = String(xml[r])

            let title = extractTag("title", from: entry)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { return nil }

            let authors = extractAllTags("name", from: entry)
            let published = extractTag("published", from: entry)
            let year = published.flatMap { Int($0.prefix(4)) }
            let abstract = extractTag("summary", from: entry)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = extractTag("id", from: entry).flatMap { URL(string: $0)?.lastPathComponent }

            return ArxivResult(title: title, authors: authors, year: year, abstract: abstract, arxivID: id)
        }
    }

    private static func extractTag(_ tag: String, from xml: String) -> String? {
        guard let r = xml.range(of: "<\(tag)"),
              let start = xml[r.upperBound...].range(of: ">"),
              let end = xml.range(of: "</\(tag)>") else { return nil }
        let content = xml[start.upperBound..<end.lowerBound]
        return String(content)
    }

    private static func extractAllTags(_ tag: String, from xml: String) -> [String] {
        let pattern = "<\(tag)>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.matches(in: xml, range: range).compactMap {
            Range($0.range(at: 1), in: xml).map { String(xml[$0]) }
        }
    }

    public static func findMatchingPaper(title: String) async -> ArxivResult? {
        (try? await search(query: title))?.first(where: { $0.title.matchesCitationTitle(title) })
    }
}

private extension String {
    func matchesCitationTitle(_ candidate: String) -> Bool {
        normalizedCitationTitle == candidate.normalizedCitationTitle
    }

    var normalizedCitationTitle: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var normalizedDOI: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "http://doi.org/", with: "", options: [.caseInsensitive])
            .lowercased()
    }

    var trimmedOpenAlexID: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://openalex.org/", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "http://openalex.org/", with: "", options: [.caseInsensitive])
    }

    var lastPathComponentString: String {
        URL(string: self)?.lastPathComponent ?? self.components(separatedBy: "/").last ?? self
    }
}
