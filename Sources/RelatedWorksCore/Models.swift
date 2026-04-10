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
    public var hasPDF: Bool
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
        self.hasPDF = false
        self.addedAt = Date()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        authors = try c.decodeIfPresent([String].self, forKey: .authors) ?? []
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        venue = try c.decodeIfPresent(String.self, forKey: .venue)
        dblpKey = try c.decodeIfPresent(String.self, forKey: .dblpKey)
        abstract = try c.decodeIfPresent(String.self, forKey: .abstract)
        annotation = try c.decodeIfPresent(String.self, forKey: .annotation) ?? ""
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        // Migrate from old pdfPath field
        if let hasPDF = try c.decodeIfPresent(Bool.self, forKey: .hasPDF) {
            self.hasPDF = hasPDF
        } else {
            self.hasPDF = (try c.decodeIfPresent(String.self, forKey: .pdfPath)) != nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, authors, year, venue, dblpKey, abstract, hasPDF, pdfPath, annotation, addedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(authors, forKey: .authors)
        try c.encodeIfPresent(year, forKey: .year)
        try c.encodeIfPresent(venue, forKey: .venue)
        try c.encodeIfPresent(dblpKey, forKey: .dblpKey)
        try c.encodeIfPresent(abstract, forKey: .abstract)
        try c.encode(hasPDF, forKey: .hasPDF)
        try c.encode(annotation, forKey: .annotation)
        try c.encode(addedAt, forKey: .addedAt)
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
