import Foundation

public enum CitationMetadataError: LocalizedError {
    case workNotFound

    public var errorDescription: String? {
        switch self {
        case .workNotFound:
            return "No citation metadata was found for this paper."
        }
    }
}

public struct OpenAlexService {
    public static func fetchReferences(
        seed: CitationGraphPaperData,
        title: String? = nil,
        authors: [String] = [],
        year: Int? = nil,
        maxReferences: Int = 40
    ) async throws -> CitationGraphPaperData {
        let work = try await resolveWork(seed: seed, title: title, authors: authors, year: year)
        var updated = seed
        updated.openAlexID = work.shortOpenAlexID ?? seed.openAlexID
        updated.doi = seed.doi ?? work.ids?.doi?.normalizedDOI

        let referenceIDs = Array(work.referencedWorks.prefix(maxReferences))
        var references: [PaperReference] = []
        for id in referenceIDs {
            if let referenceWork = try? await fetchWork(id: id),
               let reference = referenceWork.asPaperReference {
                references.append(reference)
            }
        }

        updated.references = deduplicatedReferences(references)
        updated.referencesUpdatedAt = Date()
        return updated
    }

    private static func resolveWork(
        seed: CitationGraphPaperData,
        title: String?,
        authors: [String],
        year: Int?
    ) async throws -> OpenAlexWork {
        if let id = seed.openAlexID?.trimmedOpenAlexID {
            return try await fetchWork(id: id)
        }

        if let doi = seed.doi?.normalizedDOI,
           let work = try? await fetchWorkByDOI(doi) {
            return work
        }

        if let arxivID = seed.arxivID?.trimmingCharacters(in: .whitespacesAndNewlines), !arxivID.isEmpty,
           let work = try? await searchWork(filter: "locations.landing_page_url.search:https://arxiv.org/abs/\(arxivID)") {
            return work
        }

        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let work = try? await searchBestMatchingWork(title: title, authors: authors, year: year) {
            return work
        }

        throw CitationMetadataError.workNotFound
    }

    private static func fetchWork(id: String) async throws -> OpenAlexWork {
        let cleanID = id.trimmedOpenAlexID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id.trimmedOpenAlexID
        guard let url = URL(string: "https://api.openalex.org/works/\(cleanID)?select=id,doi,display_name,publication_year,authorships,primary_location,referenced_works,ids,is_paratext,type") else {
            throw CitationMetadataError.workNotFound
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(OpenAlexWork.self, from: data)
    }

    private static func fetchWorkByDOI(_ doi: String) async throws -> OpenAlexWork {
        var components = URLComponents(string: "https://api.openalex.org/works")!
        components.queryItems = [
            URLQueryItem(name: "filter", value: "doi:\(doi)"),
            URLQueryItem(name: "per-page", value: "1"),
            URLQueryItem(name: "select", value: "id,doi,display_name,publication_year,authorships,primary_location,referenced_works,ids,is_paratext,type"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let page = try JSONDecoder().decode(OpenAlexWorksPage.self, from: data)
        guard let work = page.results.first else { throw CitationMetadataError.workNotFound }
        return work
    }

    private static func searchWork(filter: String) async throws -> OpenAlexWork {
        var components = URLComponents(string: "https://api.openalex.org/works")!
        components.queryItems = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "per-page", value: "1"),
            URLQueryItem(name: "select", value: "id,doi,display_name,publication_year,authorships,primary_location,referenced_works,ids,is_paratext,type"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let page = try JSONDecoder().decode(OpenAlexWorksPage.self, from: data)
        guard let work = page.results.first else { throw CitationMetadataError.workNotFound }
        return work
    }

    private static func searchBestMatchingWork(title: String, authors: [String], year: Int?) async throws -> OpenAlexWork {
        var components = URLComponents(string: "https://api.openalex.org/works")!
        components.queryItems = [
            URLQueryItem(name: "search", value: title),
            URLQueryItem(name: "per-page", value: "5"),
            URLQueryItem(name: "select", value: "id,doi,display_name,publication_year,authorships,primary_location,referenced_works,ids,is_paratext,type"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let page = try JSONDecoder().decode(OpenAlexWorksPage.self, from: data)
        guard let best = page.results
            .map({ ($0, $0.matchScore(title: title, authors: authors, year: year)) })
            .filter({ $0.1 >= 0.72 })
            .sorted(by: { lhs, rhs in lhs.1 > rhs.1 })
            .first?.0 else {
            throw CitationMetadataError.workNotFound
        }
        return best
    }

    private static func deduplicatedReferences(_ references: [PaperReference]) -> [PaperReference] {
        var seen = Set<String>()
        return references.filter { reference in
            seen.insert(reference.id.lowercased()).inserted
        }
    }
}

private struct OpenAlexWorksPage: Decodable {
    let results: [OpenAlexWork]
}

private struct OpenAlexWork: Decodable {
    let id: String?
    let doi: String?
    let displayName: String
    let publicationYear: Int?
    let authorships: [OpenAlexAuthorship]
    let primaryLocation: OpenAlexLocation?
    let referencedWorks: [String]
    let ids: OpenAlexIDs?
    let isParatext: Bool?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, doi, authorships, ids, type
        case displayName = "display_name"
        case publicationYear = "publication_year"
        case primaryLocation = "primary_location"
        case referencedWorks = "referenced_works"
        case isParatext = "is_paratext"
    }

    var shortOpenAlexID: String? {
        id?.trimmedOpenAlexID
    }

    var asPaperReference: PaperReference? {
        guard CitationReferenceQuality.isLikelyReference(
            title: displayName,
            authors: authorships.compactMap { $0.author.displayName },
            venue: primaryLocation?.source?.displayName,
            isParatext: isParatext == true,
            type: type,
            year: publicationYear
        ) else {
            return nil
        }

        return PaperReference(
            title: displayName,
            authors: authorships.compactMap { $0.author.displayName },
            year: publicationYear,
            venue: primaryLocation?.source?.displayName,
            doi: doi?.normalizedDOI ?? ids?.doi?.normalizedDOI,
            arxivID: ids?.arxiv?.lastPathComponentString,
            openAlexID: shortOpenAlexID
        )
    }

    func matchScore(title: String, authors: [String], year: Int?) -> Double {
        let queryTokens = title.citationTitleTokens
        let candidateTokens = displayName.citationTitleTokens
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }

        let intersection = queryTokens.intersection(candidateTokens)
        let union = queryTokens.union(candidateTokens)
        let jaccard = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
        let containment = Double(intersection.count) / Double(queryTokens.count)
        var score = max(jaccard, containment)

        if displayName.normalizedCitationTitle == title.normalizedCitationTitle {
            score += 0.12
        }

        if let year, let publicationYear, year == publicationYear {
            score += 0.08
        }

        if !authors.isEmpty {
            let queryAuthorTokens = Set(authors.map(\.citationAuthorToken))
            let candidateAuthorTokens = Set(authorships.compactMap { $0.author.displayName }.map(\.citationAuthorToken))
            let overlap = queryAuthorTokens.intersection(candidateAuthorTokens)
            if !overlap.isEmpty {
                score += min(0.12, Double(overlap.count) * 0.06)
            }
        }

        return min(score, 1.0)
    }
}

private struct OpenAlexAuthorship: Decodable {
    let author: OpenAlexAuthor
}

private struct OpenAlexAuthor: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct OpenAlexLocation: Decodable {
    let source: OpenAlexSource?
}

private struct OpenAlexSource: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct OpenAlexIDs: Decodable {
    let doi: String?
    let openalex: String?
    let arxiv: String?
}

private enum CitationReferenceQuality {
    static func isLikelyReference(
        title: String,
        authors: [String],
        venue: String?,
        isParatext: Bool,
        type: String?,
        year: Int?
    ) -> Bool {
        if isParatext { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        let lowercaseTitle = trimmedTitle.lowercased()
        let normalizedVenue = venue?.normalizedCitationTitle
        if lowercaseTitle.hasPrefix("proceedings of")
            || lowercaseTitle.hasPrefix("findings of")
            || lowercaseTitle.hasPrefix("transactions of")
            || lowercaseTitle.contains("annual technical conference")
            || lowercaseTitle.contains("symposium on")
            || lowercaseTitle.contains("workshop on")
            || lowercaseTitle.contains("conference on")
            || lowercaseTitle.contains("conference record")
            || lowercaseTitle.contains("conference companion") {
            return false
        }

        if let type = type?.lowercased(),
           type == "paratext" || type == "proceedings-article" || type == "editorial" {
            return false
        }

        if trimmedTitle.range(of: #"^\d{4}\b.*\b(conference|symposium|workshop|meeting)\b"#, options: .regularExpression) != nil {
            return false
        }

        if let normalizedVenue,
           trimmedTitle.normalizedCitationTitle == normalizedVenue {
            return false
        }

        if trimmedTitle.range(of: #"^[A-Z][A-Z0-9\-]{1,5}$"#, options: .regularExpression) != nil {
            if authors.count <= 1 || year == nil || normalizedVenue != nil {
                return false
            }
        }

        if trimmedTitle.range(of: #"^[A-Z0-9\-]{2,6}$"#, options: .regularExpression) != nil,
           authors.isEmpty || venue == nil {
            return false
        }

        return true
    }
}

private extension String {
    var trimmedOpenAlexID: String {
        if let range = range(of: "openalex.org/", options: .caseInsensitive) {
            return String(self[range.upperBound...])
        }
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDOI: String {
        lowercased()
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "doi:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var lastPathComponentString: String? {
        if let url = URL(string: self), let host = url.host, !host.isEmpty {
            let candidate = url.lastPathComponent
            return candidate.isEmpty ? nil : candidate
        }
        let candidate = trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
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

    var normalizedCitationTitle: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var isCitationStopword: Bool {
        [
            "a", "an", "and", "for", "of", "on", "the", "to", "with",
            "using", "via", "from", "in", "by"
        ].contains(self)
    }
}
