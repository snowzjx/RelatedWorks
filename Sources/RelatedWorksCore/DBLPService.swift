import Foundation

public struct DBLPResult {
    public let title: String
    public let authors: [String]
    public let year: Int?
    public let venue: String?
    public let dblpKey: String?
    public let doi: String?
    public let arxivID: String?
}

public struct CitationSeed: Hashable, Sendable {
    public var dblpKey: String?
    public var doi: String?
    public var arxivID: String?

    public init(dblpKey: String? = nil, doi: String? = nil, arxivID: String? = nil) {
        self.dblpKey = dblpKey
        self.doi = doi
        self.arxivID = arxivID
    }
}

public struct DBLPService {
    public static func search(query: String) async throws -> [DBLPResult] {
        var components = URLComponents(string: "https://dblp.org/search/publ/api")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "h", value: "5"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try parse(data)
    }

    private static func parse(_ data: Data) throws -> [DBLPResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let hits = result["hits"] as? [String: Any],
              let hitList = hits["hit"] as? [[String: Any]] else { return [] }

        var seen = Set<String>()
        return hitList.compactMap { hit -> DBLPResult? in
            guard let info = hit["info"] as? [String: Any],
                  let title = info["title"] as? String else { return nil }

            let normalised = title.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard seen.insert(normalised).inserted else { return nil }

            let authors: [String]
            if let authorObj = info["authors"] as? [String: Any],
               let authorList = authorObj["author"] as? [[String: Any]] {
                authors = authorList.compactMap { $0["text"] as? String }
            } else if let authorObj = info["authors"] as? [String: Any],
                      let single = authorObj["author"] as? [String: Any] {
                authors = [single["text"] as? String].compactMap { $0 }
            } else {
                authors = []
            }

            return DBLPResult(
                title: title,
                authors: authors,
                year: (info["year"] as? String).flatMap(Int.init),
                venue: (info["venue"] as? String).map { $0.trimmingCharacters(in: .init(charactersIn: ", ")) },
                dblpKey: info["key"] as? String,
                doi: info["doi"] as? String,
                arxivID: extractArxivID(from: info)
            )
        }
    }

    /// Fetch BibTeX string for a DBLP key, e.g. "conf/nips/VaswaniSPUJGKP17"
    public static func fetchBibtex(dblpKey: String) async -> String? {
        let urlStr = "https://dblp.org/rec/\(dblpKey).bib"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let bib = String(data: data, encoding: .utf8) else { return nil }
        return bib
    }

    public static func findCitationSeed(
        title: String,
        authors: [String] = [],
        year: Int? = nil
    ) async -> CitationSeed? {
        guard let results = try? await search(query: title),
              let match = bestCitationMatch(for: title, authors: authors, year: year, in: results),
              let dblpKey = match.dblpKey else { return nil }

        let bibtex = await fetchBibtex(dblpKey: dblpKey)
        return CitationSeed(
            dblpKey: dblpKey,
            doi: match.doi ?? bibtex.flatMap { extractBibtexField(named: "doi", from: $0) },
            arxivID: match.arxivID ?? bibtex.flatMap { extractBibtexField(named: "eprint", from: $0) }
        )
    }

    private static func bestCitationMatch(
        for title: String,
        authors: [String],
        year: Int?,
        in results: [DBLPResult]
    ) -> DBLPResult? {
        let ranked = results
            .map { ($0, citationMatchScore(queryTitle: title, queryAuthors: authors, queryYear: year, candidate: $0)) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title.count < rhs.0.title.count
                }
                return lhs.1 > rhs.1
            }

        guard let (best, score) = ranked.first, score >= 0.72 else { return nil }
        return best
    }

    private static func citationMatchScore(
        queryTitle: String,
        queryAuthors: [String],
        queryYear: Int?,
        candidate: DBLPResult
    ) -> Double {
        let queryTokens = queryTitle.citationTitleTokens
        let candidateTokens = candidate.title.citationTitleTokens
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }

        if queryTokens == candidateTokens { return 1.0 }

        let intersection = queryTokens.intersection(candidateTokens)
        let union = queryTokens.union(candidateTokens)
        let jaccard = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
        let containment = Double(intersection.count) / Double(queryTokens.count)

        var score = max(jaccard, containment)

        if candidate.title.normalizedCitationTitle.contains(queryTitle.normalizedCitationTitle)
            || queryTitle.normalizedCitationTitle.contains(candidate.title.normalizedCitationTitle) {
            score += 0.08
        }

        if let queryYear, let candidateYear = candidate.year, queryYear == candidateYear {
            score += 0.08
        }

        if !queryAuthors.isEmpty {
            let queryAuthorTokens = Set(queryAuthors.map(\.citationAuthorToken))
            let candidateAuthorTokens = Set(candidate.authors.map(\.citationAuthorToken))
            let authorOverlap = queryAuthorTokens.intersection(candidateAuthorTokens)
            if !authorOverlap.isEmpty {
                score += min(0.12, Double(authorOverlap.count) * 0.06)
            }
        }

        return min(score, 1.0)
    }

    private static func extractBibtexField(named name: String, from bibtex: String) -> String? {
        let pattern = #"(?im)^\s*\#(name)\s*=\s*[\{\"]([^}\"]+)[\}\"]"#
            .replacingOccurrences(of: "#(name)", with: name)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(bibtex.startIndex..., in: bibtex)
        guard let match = regex.firstMatch(in: bibtex, range: range),
              let fieldRange = Range(match.range(at: 1), in: bibtex) else { return nil }
        return String(bibtex[fieldRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractArxivID(from info: [String: Any]) -> String? {
        func parse(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.contains("arxiv.org") {
                return URL(string: trimmed)?.lastPathComponent
            }
            return trimmed.lowercased().hasPrefix("arxiv:") ? String(trimmed.dropFirst("arxiv:".count)) : nil
        }

        if let ee = info["ee"] as? String {
            return parse(ee)
        }

        if let eeList = info["ee"] as? [String] {
            return eeList.compactMap(parse).first
        }

        return nil
    }
}

private extension String {
    var normalizedCitationTitle: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var citationTitleTokens: Set<String> {
        Set(
            normalizedCitationTitle
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isCitationStopword }
        )
    }

    var citationAuthorToken: String {
        normalizedCitationTitle
            .split(separator: " ")
            .last
            .map(String.init) ?? normalizedCitationTitle
    }

    var isCitationStopword: Bool {
        [
            "a", "an", "and", "for", "of", "on", "the", "to", "with",
            "using", "via", "from", "in", "by"
        ].contains(self)
    }
}
