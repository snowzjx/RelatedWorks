import Foundation

// MARK: - Core Models

struct Paper: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var authors: [String]
    var year: Int?
    var venue: String?
    var dblpKey: String?
    var abstract: String?
    var pdfPath: String?
    var annotation: String
    var addedAt: Date

    init(id: String, title: String, authors: [String] = [], year: Int? = nil,
                venue: String? = nil, annotation: String = "") {
        self.id = id
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.annotation = annotation
        self.addedAt = Date()
    }
}

struct Project: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var papers: [Paper]
    var createdAt: Date
    var generatedLatex: String?
    var generationModel: String?
    var bibEntries: [String: String]

    init(name: String, description: String = "") {
        self.id = UUID()
        self.name = name
        self.description = description
        self.papers = []
        self.createdAt = Date()
        self.generatedLatex = nil
        self.bibEntries = [:]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        papers = try c.decodeIfPresent([Paper].self, forKey: .papers) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        generatedLatex = try c.decodeIfPresent(String.self, forKey: .generatedLatex)
        generationModel = try c.decodeIfPresent(String.self, forKey: .generationModel)
        bibEntries = try c.decodeIfPresent([String: String].self, forKey: .bibEntries) ?? [:]
    }

    mutating func addPaper(_ paper: Paper) {
        papers.append(paper)
    }

    func paper(withID id: String) -> Paper? {
        papers.first { $0.id.lowercased() == id.lowercased() }
    }

    func crossReferences(for paperID: String) -> [Paper] {
        guard let source = paper(withID: paperID) else { return [] }
        let refs = extractRefs(from: source.annotation)
        var seen = Set<String>()
        return refs.compactMap { id -> Paper? in
            guard id.lowercased() != paperID.lowercased() else { return nil }
            guard seen.insert(id.lowercased()).inserted else { return nil }
            return paper(withID: id)
        }
    }

    func extractRefs(from text: String) -> [String] {
        let pattern = #"@([A-Za-z][A-Za-z0-9_\-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
