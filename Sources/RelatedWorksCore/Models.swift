import Foundation

// MARK: - Core Models

public enum ProjectType: String, Codable, CaseIterable, Hashable, Sendable {
    case survey
    case researchPaper
    case techReport
    case custom

    public var displayName: String {
        switch self {
        case .survey: return "Survey"
        case .researchPaper: return "Research Paper"
        case .techReport: return "Tech Report"
        case .custom: return "Custom"
        }
    }

    public var presetPrompt: String? {
        switch self {
        case .survey:
            return """
                Write 3-4 cohesive paragraphs in formal academic LaTeX style for the Related Works section of a survey paper.
                The paper title and description are provided above — use them to define the survey scope and organize the literature landscape.
                Group papers into broad themes, methodological families, or problem settings instead of discussing them one by one.
                Emphasize how the cited works connect to each other, what subareas they cover, and where the overall landscape still has open questions or fragmentation.
                Incorporate the author annotation notes naturally into the discussion.
                Cite papers using LaTeX \\cite{ID} where ID is the paper's semantic ID (e.g. \\cite{Transformer}, \\cite{BERT}).
                Do NOT include a section heading, just the paragraphs.
                Output only the LaTeX paragraph text, nothing else.
                """
        case .researchPaper:
            return """
                Write 2-3 cohesive paragraphs in formal academic LaTeX style for the Related Works section of a research paper.
                The paper title and description are provided above — tailor the discussion to position this paper against the most relevant prior work.
                Group related papers thematically instead of listing them one by one.
                Highlight key differences, limitations, or gaps in prior work that motivate the current paper.
                Incorporate the author annotation notes naturally into the discussion.
                Cite papers using LaTeX \\cite{ID} where ID is the paper's semantic ID (e.g. \\cite{Transformer}, \\cite{BERT}).
                Do NOT include a section heading, just the paragraphs.
                Output only the LaTeX paragraph text, nothing else.
                """
        case .techReport:
            return """
                Write 2-3 cohesive paragraphs in clear formal LaTeX style for the Related Works section of a technical report.
                The paper title and description are provided above — focus on practical system context, prior approaches, and implementation tradeoffs relevant to this report.
                Group papers by technical approach, deployment setting, or system constraint instead of listing them one by one.
                Make the comparison concrete, emphasizing design decisions, empirical tradeoffs, and operational lessons from prior work.
                Incorporate the author annotation notes naturally into the discussion.
                Cite papers using LaTeX \\cite{ID} where ID is the paper's semantic ID (e.g. \\cite{Transformer}, \\cite{BERT}).
                Do NOT include a section heading, just the paragraphs.
                Output only the LaTeX paragraph text, nothing else.
                """
        case .custom:
            return nil
        }
    }
}

public struct Paper: Codable, Identifiable, Hashable, Sendable {
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

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var projectType: ProjectType
    public var generationPrompt: String
    public var papers: [Paper]
    public var createdAt: Date
    public var generatedLatex: String?
    public var generationModel: String?
    public var bibEntries: [String: String]

    public init(name: String, description: String = "", projectType: ProjectType = .researchPaper,
                generationPrompt: String? = nil) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.projectType = projectType
        self.generationPrompt = Self.resolveInitialPrompt(projectType: projectType, generationPrompt: generationPrompt)
        self.papers = []
        self.createdAt = Date()
        self.generatedLatex = nil
        self.bibEntries = [:]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        projectType = try c.decodeIfPresent(ProjectType.self, forKey: .projectType) ?? .custom
        if let storedPrompt = (try c.decodeIfPresent(String.self, forKey: .generationPrompt))?.trimmedNilIfEmpty {
            generationPrompt = storedPrompt
        } else if let legacyOverride = (try legacy.decodeIfPresent(String.self, forKey: .generationPromptOverride))?.trimmedNilIfEmpty {
            generationPrompt = legacyOverride
        } else {
            generationPrompt = AppSettings.shared.generationPrompt
        }
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
        self.projectType = source.projectType
        self.generationPrompt = source.generationPrompt
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

    public mutating func applyPreset(for type: ProjectType) {
        projectType = type
        if let preset = type.presetPrompt {
            generationPrompt = preset
        }
    }

    public mutating func updateGenerationPrompt(_ prompt: String) {
        generationPrompt = prompt.trimmedNilIfEmpty ?? generationPrompt
        if projectType != .custom, let preset = projectType.presetPrompt, prompt != preset {
            projectType = .custom
        }
    }

    public func usesPresetPrompt() -> Bool {
        guard let preset = projectType.presetPrompt else { return false }
        return generationPrompt == preset
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, projectType, generationPrompt, papers, createdAt, generatedLatex, generationModel, bibEntries
    }

    enum LegacyCodingKeys: String, CodingKey {
        case generationPromptOverride
    }

    private static func resolveInitialPrompt(projectType: ProjectType, generationPrompt: String?) -> String {
        if let prompt = generationPrompt?.trimmedNilIfEmpty {
            return prompt
        }
        if let preset = projectType.presetPrompt {
            return preset
        }
        return AppSettings.shared.generationPrompt
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
