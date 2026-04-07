import Foundation

public struct DBLPResult {
    public let title: String
    public let authors: [String]
    public let year: Int?
    public let venue: String?
    public let dblpKey: String?
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
                dblpKey: info["key"] as? String
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
}
