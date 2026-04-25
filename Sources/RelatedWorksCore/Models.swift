import Foundation

// MARK: - Core Models

public enum ProjectType: String, Codable, CaseIterable, Hashable, Sendable {
    case survey
    case researchPaper
    case techReport
    case custom

    public var displayName: String {
        switch self {
        case .survey:
            return appLocalized("Survey")
        case .researchPaper:
            return appLocalized("Research Paper")
        case .techReport:
            return appLocalized("Tech Report")
        case .custom:
            return appLocalized("Custom")
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

public struct PaperReference: Codable, Identifiable, Hashable, Sendable {
    public var id: String { openAlexID ?? doi ?? arxivID ?? normalizedTitle }
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String?
    public var doi: String?
    public var arxivID: String?
    public var openAlexID: String?

    public init(
        title: String,
        authors: [String] = [],
        year: Int? = nil,
        venue: String? = nil,
        doi: String? = nil,
        arxivID: String? = nil,
        openAlexID: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.doi = doi
        self.arxivID = arxivID
        self.openAlexID = openAlexID
    }

    private var normalizedTitle: String {
        title.normalizedPaperTitle
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
            generationPrompt = AppSettings.defaultGenerationPrompt
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
        return AppSettings.defaultGenerationPrompt
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedPaperTitle: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct CitationGraph: Hashable, Sendable {
    public enum NodeKind: String, Hashable, Sendable {
        case projectPaper
        case externalPaper
        case sharedExternalPaper
    }

    public enum EdgeKind: String, Hashable, Sendable {
        case mention
        case projectReference
        case externalReference
        case sharedExternalReference
    }

    public struct Node: Identifiable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var paperID: String?
        public var kind: NodeKind
        public var referenceCount: Int
        public var referencingPaperIDs: [String]
    }

    public struct Edge: Identifiable, Hashable, Sendable {
        public var id: String
        public var sourceID: String
        public var targetID: String
        public var kind: EdgeKind
    }

    public var nodes: [Node]
    public var edges: [Edge]
    public var externalPapers: [ExternalPaper]

    public struct ExternalPaper: Identifiable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var referenceCount: Int
        public var referencingPaperIDs: [String]
        public var reference: PaperReference
        public var isShared: Bool
    }

    public init(project: Project, data: CitationGraphProjectData, sharedExternalDisplayThreshold: Int = 2) {
        let sharedThreshold = max(2, sharedExternalDisplayThreshold)
        var nodesByID: [String: Node] = [:]
        var edgesByID: [String: Edge] = [:]
        let projectNodeIDs = Dictionary(uniqueKeysWithValues: project.papers.map { ($0.id.lowercased(), "project:\($0.id.lowercased())") })
        let canonicalPaperIDs = Dictionary(uniqueKeysWithValues: project.papers.map { ($0.id.lowercased(), $0.id) })
        func resolveReferencingPaperIDs(_ sourceIDs: Set<String>) -> [String] {
            sourceIDs.reduce(into: [String]()) { result, sourceID in
                guard let lowercasedID = sourceID.split(separator: ":").last.map(String.init),
                      let canonicalPaperID = canonicalPaperIDs[lowercasedID] else { return }
                result.append(canonicalPaperID)
            }
            .sorted()
        }

        for paper in project.papers {
            let nodeID = "project:\(paper.id.lowercased())"
            nodesByID[nodeID] = Node(id: nodeID, title: paper.title, paperID: paper.id, kind: .projectPaper, referenceCount: 0, referencingPaperIDs: [])
        }

        for paper in project.papers {
            let sourceID = "project:\(paper.id.lowercased())"
            for mention in project.extractRefs(from: paper.annotation) {
                guard let targetID = projectNodeIDs[mention.lowercased()], targetID != sourceID else { continue }
                let edgeID = "mention:\(sourceID):\(targetID)"
                edgesByID[edgeID] = Edge(id: edgeID, sourceID: sourceID, targetID: targetID, kind: .mention)
            }
        }

        var externalReferenceSources: [String: Set<String>] = [:]
        var externalReferences: [String: PaperReference] = [:]
        var pendingReferenceEdges: [(sourceID: String, referenceKey: String, internalTargetID: String?)] = []
        let projectLookup = ProjectPaperLookup(papers: project.papers, citationData: data)

        for paper in project.papers {
            let sourceID = "project:\(paper.id.lowercased())"
            for reference in data.paperData[paper.id]?.references ?? [] {
                if let targetPaper = projectLookup.paper(matching: reference), targetPaper.id.lowercased() != paper.id.lowercased() {
                    pendingReferenceEdges.append((sourceID, "", "project:\(targetPaper.id.lowercased())"))
                } else {
                    let referenceKey = CitationGraph.externalNodeID(for: reference)
                    externalReferences[referenceKey] = reference
                    externalReferenceSources[referenceKey, default: []].insert(sourceID)
                    pendingReferenceEdges.append((sourceID, referenceKey, nil))
                }
            }
        }

        for (referenceKey, reference) in externalReferences {
            let referencingPaperIDs = resolveReferencingPaperIDs(externalReferenceSources[referenceKey] ?? [])
            let count = referencingPaperIDs.count
            if count >= sharedThreshold {
                nodesByID[referenceKey] = Node(
                    id: referenceKey,
                    title: reference.title,
                    paperID: nil,
                    kind: .sharedExternalPaper,
                    referenceCount: count,
                    referencingPaperIDs: referencingPaperIDs
                )
            }
        }

        for pending in pendingReferenceEdges {
            if let targetID = pending.internalTargetID {
                let edgeID = "projectReference:\(pending.sourceID):\(targetID)"
                edgesByID[edgeID] = Edge(id: edgeID, sourceID: pending.sourceID, targetID: targetID, kind: .projectReference)
            } else {
                let kind: EdgeKind = nodesByID[pending.referenceKey] != nil ? .sharedExternalReference : .externalReference
                guard kind == .sharedExternalReference || externalReferences[pending.referenceKey] != nil else { continue }
                let edgeID = "\(kind.rawValue):\(pending.sourceID):\(pending.referenceKey)"
                edgesByID[edgeID] = Edge(id: edgeID, sourceID: pending.sourceID, targetID: pending.referenceKey, kind: kind)
            }
        }

        nodes = nodesByID.values.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        edges = edgesByID.values.sorted { $0.id < $1.id }
        var resolvedExternalPapers: [ExternalPaper] = []
        for (referenceKey, reference) in externalReferences {
            let referencingPaperIDs = resolveReferencingPaperIDs(externalReferenceSources[referenceKey] ?? [])
            resolvedExternalPapers.append(ExternalPaper(
                id: referenceKey,
                title: reference.title,
                referenceCount: referencingPaperIDs.count,
                referencingPaperIDs: referencingPaperIDs,
                reference: reference,
                isShared: referencingPaperIDs.count > 1
            ))
        }
        externalPapers = resolvedExternalPapers.sorted {
            if $0.isShared != $1.isShared { return $0.isShared && !$1.isShared }
            if $0.referenceCount != $1.referenceCount { return $0.referenceCount > $1.referenceCount }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func externalNodeID(for reference: PaperReference) -> String {
        if let openAlexID = reference.openAlexID?.trimmingCharacters(in: .whitespacesAndNewlines), !openAlexID.isEmpty {
            return "external:openalex:\(openAlexID.lowercased())"
        }
        if let doi = reference.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty {
            return "external:doi:\(doi.lowercased())"
        }
        if let arxivID = reference.arxivID?.trimmingCharacters(in: .whitespacesAndNewlines), !arxivID.isEmpty {
            return "external:arxiv:\(arxivID.lowercased())"
        }
        return "external:title:\(reference.title.normalizedPaperTitle)"
    }

}

private struct ProjectPaperLookup {
    private let byDOI: [String: Paper]
    private let byArxivID: [String: Paper]
    private let byOpenAlexID: [String: Paper]
    private let byTitle: [String: Paper]

    init(papers: [Paper], citationData: CitationGraphProjectData) {
        byDOI = Dictionary(papers.compactMap {
            guard let doi = citationData.paperData[$0.id]?.doi?.lowercased(), !doi.isEmpty else { return nil }
            return (doi, $0)
        }, uniquingKeysWith: { first, _ in first })
        byArxivID = Dictionary(papers.compactMap {
            guard let arxivID = citationData.paperData[$0.id]?.arxivID?.lowercased(), !arxivID.isEmpty else { return nil }
            return (arxivID, $0)
        }, uniquingKeysWith: { first, _ in first })
        byOpenAlexID = Dictionary(papers.compactMap {
            guard let openAlexID = citationData.paperData[$0.id]?.openAlexID?.lowercased(), !openAlexID.isEmpty else { return nil }
            return (openAlexID, $0)
        }, uniquingKeysWith: { first, _ in first })
        byTitle = Dictionary(papers.map { ($0.title.normalizedPaperTitle, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func paper(matching reference: PaperReference) -> Paper? {
        if let doi = reference.doi?.lowercased(), let paper = byDOI[doi] { return paper }
        if let arxivID = reference.arxivID?.lowercased(), let paper = byArxivID[arxivID] { return paper }
        if let openAlexID = reference.openAlexID?.lowercased(), let paper = byOpenAlexID[openAlexID] { return paper }
        return byTitle[reference.title.normalizedPaperTitle]
    }
}

public struct CitationGraphProjectData: Codable, Hashable, Sendable {
    public var projectID: UUID
    public var paperData: [String: CitationGraphPaperData]
    public var updatedAt: Date?

    public init(projectID: UUID, paperData: [String: CitationGraphPaperData] = [:], updatedAt: Date? = nil) {
        self.projectID = projectID
        self.paperData = paperData
        self.updatedAt = updatedAt
    }
}

public struct CitationGraphPaperData: Codable, Hashable, Sendable {
    public var dblpKey: String?
    public var doi: String?
    public var arxivID: String?
    public var openAlexID: String?
    public var references: [PaperReference]
    public var referencesUpdatedAt: Date?

    public init(
        dblpKey: String? = nil,
        doi: String? = nil,
        arxivID: String? = nil,
        openAlexID: String? = nil,
        references: [PaperReference] = [],
        referencesUpdatedAt: Date? = nil
    ) {
        self.dblpKey = dblpKey
        self.doi = doi
        self.arxivID = arxivID
        self.openAlexID = openAlexID
        self.references = references
        self.referencesUpdatedAt = referencesUpdatedAt
    }
}
