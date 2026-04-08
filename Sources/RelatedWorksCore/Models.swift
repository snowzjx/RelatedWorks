import Foundation

// MARK: - Core Models

public struct Paper: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String?
    public var dblpKey: String?
    public var abstract: String?
    public var pdfPath: String?
    public var annotation: String
    public var addedAt: Date

    public init(id: String, title: String, authors: [String] = [], year: Int? = nil,
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

public struct Project: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var description: String
    public var papers: [Paper]
    public var createdAt: Date
    public var generatedLatex: String?
    public var generationModel: String?
    public var bibEntries: [String: String]

    public init(name: String, description: String = "") {
        self.id = UUID()
        self.name = name
        self.description = description
        self.papers = []
        self.createdAt = Date()
        self.generatedLatex = nil
        self.bibEntries = [:]
    }

    public init(from decoder: Decoder) throws {
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

    public mutating func addPaper(_ paper: Paper) {
        papers.append(paper)
    }

    public init(importing source: Project, newID: UUID) {
        self.id = newID
        self.name = source.name
        self.description = source.description
        self.papers = source.papers
        self.createdAt = Date()
        self.generatedLatex = source.generatedLatex
        self.generationModel = source.generationModel
        self.bibEntries = source.bibEntries
    }

    public func paper(withID id: String) -> Paper? {
        papers.first { $0.id.lowercased() == id.lowercased() }
    }

    public func crossReferences(for paperID: String) -> [Paper] {
        guard let source = paper(withID: paperID) else { return [] }
        let refs = extractRefs(from: source.annotation)
        var seen = Set<String>()
        return refs.compactMap { id -> Paper? in
            guard id.lowercased() != paperID.lowercased() else { return nil }
            guard seen.insert(id.lowercased()).inserted else { return nil }
            return paper(withID: id)
        }
    }

    public func extractRefs(from text: String) -> [String] {
        let pattern = #"@([A-Za-z][A-Za-z0-9_\-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
