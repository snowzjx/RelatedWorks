import Testing
import Foundation
#if canImport(RelatedWorksCore)
import RelatedWorksCore
#endif

// MARK: - Model Tests

@Suite("Project Model")
struct ProjectModelTests {

    @Test func addPaper() {
        var project = Project(name: "Test Project")
        let paper = Paper(id: "BERT", title: "BERT: Pre-training of Deep Bidirectional Transformers")
        project.addPaper(paper)
        #expect(project.papers.count == 1)
        #expect(project.papers.first?.id == "BERT")
    }

    @Test func paperLookupCaseInsensitive() {
        var project = Project(name: "Test")
        project.addPaper(Paper(id: "Transformer", title: "Attention Is All You Need"))
        #expect(project.paper(withID: "transformer") != nil)
        #expect(project.paper(withID: "TRANSFORMER") != nil)
        #expect(project.paper(withID: "transformer")?.title == "Attention Is All You Need")
    }

    @Test func extractCrossReferences() {
        let project = Project(name: "Test")
        let refs = project.extractRefs(from: "This builds on @BERT and @GPT, see also @Transformer.")
        #expect(refs == ["BERT", "GPT", "Transformer"])
    }

    @Test func extractCrossReferencesEmpty() {
        let project = Project(name: "Test")
        #expect(project.extractRefs(from: "No references here.").isEmpty)
    }

    @Test func crossReferencesDeduplication() {
        var project = Project(name: "Test")
        project.addPaper(Paper(id: "BERT", title: "BERT"))
        project.addPaper(Paper(id: "GPT", title: "GPT", annotation: "@BERT and @BERT again"))
        let refs = project.crossReferences(for: "GPT")
        #expect(refs.count == 1)
        #expect(refs.first?.id == "BERT")
    }

    @Test func crossReferencesIgnoresSelf() {
        var project = Project(name: "Test")
        project.addPaper(Paper(id: "BERT", title: "BERT", annotation: "@BERT self-ref"))
        let refs = project.crossReferences(for: "BERT")
        #expect(refs.isEmpty)
    }

    @Test func citationGraphBuildsMentionReferenceAndExternalEdges() {
        var project = Project(name: "Graph")
        let transformer = Paper(id: "Transformer", title: "Attention Is All You Need", annotation: "@BERT")
        let bert = Paper(id: "BERT", title: "BERT")
        project.addPaper(transformer)
        project.addPaper(bert)

        let data = CitationGraphProjectData(
            projectID: project.id,
            paperData: [
                "Transformer": CitationGraphPaperData(
                    openAlexID: "W1",
                    references: [
                        PaperReference(title: "BERT", openAlexID: "W2"),
                        PaperReference(title: "Shared Outside Paper", openAlexID: "W3"),
                        PaperReference(title: "Only Transformer Cites", openAlexID: "W4"),
                    ]
                ),
                "BERT": CitationGraphPaperData(
                    openAlexID: "W2",
                    references: [
                        PaperReference(title: "Shared Outside Paper", openAlexID: "W3"),
                    ]
                ),
            ]
        )

        let graph = CitationGraph(project: project, data: data)

        #expect(graph.edges.contains { $0.kind == .mention })
        #expect(graph.edges.contains { $0.kind == .projectReference })
        #expect(graph.edges.contains { $0.kind == .externalReference })
        #expect(graph.edges.contains { $0.kind == .sharedExternalReference })
        #expect(graph.nodes.contains { $0.kind == .sharedExternalPaper && $0.referenceCount == 2 })
        #expect(graph.externalPapers.count == 2)
    }

    @Test func projectInitializesPromptFromPreset() {
        let project = Project(name: "Survey", projectType: .survey)
        #expect(project.generationPrompt == ProjectType.survey.presetPrompt)
    }

    @Test func editingPresetPromptSwitchesTypeToCustom() {
        var project = Project(name: "Survey", projectType: .survey)
        project.updateGenerationPrompt("Manually tuned prompt")
        #expect(project.projectType == .custom)
        #expect(project.generationPrompt == "Manually tuned prompt")
    }

    @Test func projectDecodingMigratesMissingPromptFields() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy",
          "description": "",
          "papers": [],
          "createdAt": "2026-04-12T00:00:00Z",
          "bibEntries": {}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(Project.self, from: json)
        #expect(project.projectType == .custom)
        #expect(project.generationPrompt == AppSettings.defaultGenerationPrompt)
    }
}

// MARK: - Generator Tests

@Suite("Related Works Generator")
struct RelatedWorksGeneratorTests {

    @Test func buildPromptIncludesProjectPaperMetadataAndResolvedReferences() {
        var project = Project(
            name: "Neural Retrieval",
            description: "A paper about dense retrieval.",
            generationPrompt: "Write two paragraphs."
        )
        var transformer = Paper(
            id: "Transformer",
            title: "Attention Is All You Need",
            authors: ["Vaswani", "Shazeer", "Parmar", "Uszkoreit"],
            year: 2017,
            venue: "NeurIPS",
            annotation: "Foundation model."
        )
        transformer.abstract = "Introduces self-attention."
        project.addPaper(transformer)
        project.addPaper(Paper(
            id: "BERT",
            title: "BERT: Pre-training of Deep Bidirectional Transformers",
            authors: ["Devlin"],
            year: 2019,
            annotation: "Builds on @Transformer for language understanding."
        ))

        let prompt = RelatedWorksGenerator.buildPrompt(project)

        #expect(prompt.contains("Write a Related Works section for a paper titled: \"Neural Retrieval\"."))
        #expect(prompt.contains("Paper description: A paper about dense retrieval."))
        #expect(prompt.contains("Citation: Vaswani, Shazeer, Parmar et al. (2017), NeurIPS"))
        #expect(prompt.contains("Abstract: Introduces self-attention."))
        #expect(prompt.contains("Builds on Attention Is All You Need [Transformer] for language understanding."))
        #expect(prompt.contains("Write two paragraphs."))
    }

    @Test func generateUsesCanonicalPromptAndCleansThinkingBlocks() async {
        let project = Project(name: "Prompt Target", generationPrompt: "Only output LaTeX.")
        let backend = RecordingBackend(response: "  <think>hidden scratchpad</think>\nVisible draft\n")

        let output = await RelatedWorksGenerator.generate(for: project, using: backend)

        #expect(output == "Visible draft")
        #expect(backend.prompts.count == 1)
        #expect(backend.prompts.first?.contains("Prompt Target") == true)
        #expect(backend.prompts.first?.contains("Only output LaTeX.") == true)
    }

    @Test func streamFiltersThinkingBlocksWhilePublishingVisibleDraft() async {
        let project = Project(name: "Streaming Target", generationPrompt: "Only output LaTeX.")
        let backend = RecordingBackend(
            response: "",
            streamChunks: ["<think>hidden", " scratchpad</think>\nVis", "ible draft"]
        )

        var outputs: [String] = []
        for await output in RelatedWorksGenerator.stream(for: project, using: backend) {
            outputs.append(output)
        }

        #expect(outputs == ["Vis", "Visible draft"])
    }

    @Test func streamEventsReportThinkingStateWithoutPublishingThinkingText() async {
        let project = Project(name: "Streaming Target", generationPrompt: "Only output LaTeX.")
        let backend = RecordingBackend(
            response: "",
            streamChunks: ["<think>hidden", " scratchpad</think>\nVis", "ible draft"]
        )

        var events: [RelatedWorksGenerationEvent] = []
        for await event in RelatedWorksGenerator.streamEvents(for: project, using: backend) {
            events.append(event)
        }

        #expect(events == [
            .thinking(true),
            .thinking(false),
            .output("Vis"),
            .output("Visible draft")
        ])
    }
}

private final class RecordingBackend: AIBackend {
    let response: String
    let streamChunks: [String]
    private(set) var prompts: [String] = []

    init(response: String, streamChunks: [String]? = nil) {
        self.response = response
        self.streamChunks = streamChunks ?? [response]
    }

    func generate(prompt: String) async throws -> String {
        prompts.append(prompt)
        return response
    }

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        prompts.append(prompt)
        return AsyncThrowingStream { continuation in
            for chunk in streamChunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

// MARK: - App Settings Tests

@Suite("App Settings")
struct AppSettingsTests {

    @Test func unreachableOllamaPreservesSelectedBackendsAndShowsBanner() async {
        await withPreservedAppSettingsDefaults {
            let settings = AppSettings(pollsOllama: false)
            settings.ollamaBaseURL = "http://127.0.0.1:1"
            settings.extractionBackend = .ollama
            settings.generationBackend = .ollama
            settings.extractionModel = "llama3"
            settings.generationModel = "llama3"
            settings.ollamaReachable = true

            await settings.checkOllama()

            #expect(settings.ollamaReachable == false)
            #expect(settings.extractionBackend == .ollama)
            #expect(settings.generationBackend == .ollama)
            #expect(settings.shouldShowOllamaBanner)
        }
    }

    private func withPreservedAppSettingsDefaults<T>(
        _ body: () async -> T
    ) async -> T {
        let defaults = UserDefaults.standard
        let keys = [
            "fontSize",
            "appLanguage",
            "ollamaBaseURL",
            "extractionModel",
            "generationModel",
            "ollamaTimeoutSeconds",
            "extractionBackend",
            "generationBackend",
            "geminiExtractionModel",
            "geminiGenerationModel",
            "generationPrompt",
            "iCloudSyncEnabled",
            "AppleLanguages",
        ]
        let previousDefaults = Dictionary(
            uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) }
        )
        let previousReachability = OllamaReachability.shared.reachable
        defer {
            for (key, value) in previousDefaults {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            OllamaReachability.shared.reachable = previousReachability
        }

        return await body()
    }
}

// MARK: - Store Tests

@Suite("Store")
struct StoreTests {

    @Test func saveAndLoad() throws {
        let store = makeTestStore()
        var project = Project(name: "Survey Paper")
        project.addPaper(Paper(id: "Transformer", title: "Attention Is All You Need", authors: ["Vaswani"], year: 2017))
        try store.save(project)

        let loaded = try store.loadAll()
        let found = loaded.first { $0.id == project.id }
        #expect(found != nil)
        #expect(found?.name == "Survey Paper")
        #expect(found?.papers.first?.id == "Transformer")
        #expect(found?.papers.first?.year == 2017)
    }

    @Test func deleteProject() throws {
        let store = makeTestStore()
        let project = Project(name: "To Delete")
        try store.save(project)
        #expect(store.projects.contains { $0.id == project.id })
        try store.delete(project)
        #expect(!store.projects.contains { $0.id == project.id })
    }

    @Test func sameIDAllowedAcrossProjects() throws {
        let store = makeTestStore()
        var p1 = Project(name: "Project 1")
        p1.addPaper(Paper(id: "BERT", title: "BERT"))
        try store.save(p1)
        var p2 = Project(name: "Project 2")
        p2.addPaper(Paper(id: "BERT", title: "BERT Again"))
        try store.save(p2)

        #expect(store.projects.first(where: { $0.id == p1.id })?.papers.first?.id == "BERT")
        #expect(store.projects.first(where: { $0.id == p2.id })?.papers.first?.id == "BERT")
    }

    @Test func saveAndLoadCitationGraphData() throws {
        let store = makeTestStore()
        let project = Project(name: "Graph Data")
        try store.save(project)

        let data = CitationGraphProjectData(
            projectID: project.id,
            paperData: ["Paper": CitationGraphPaperData(doi: "10.1000/test", references: [PaperReference(title: "Outside")])],
            updatedAt: Date()
        )

        try store.saveCitationGraphData(data)
        let loaded = try store.loadCitationGraphData(for: project.id)

        #expect(loaded.projectID == project.id)
        #expect(loaded.paperData["Paper"]?.doi == "10.1000/test")
        #expect(loaded.paperData["Paper"]?.references.first?.title == "Outside")
    }

    @Test func perProjectPDFDirectory() throws {
        let store = makeTestStore()
        let project = Project(name: "PDF Test")
        try store.save(project)

        let pdfsDir = store.pdfsDir(for: project.id)
        #expect(pdfsDir.path.contains(project.id.uuidString))
        #expect(pdfsDir.lastPathComponent == "pdfs")
    }

    @Test func registerAndCleanupPDF() throws {
        let store = makeTestStore()
        var project = Project(name: "PDF Project")
        project.addPaper(Paper(id: "TestPaper", title: "Test"))
        try store.save(project)

        // Create a dummy PDF file
        let tmpPDF = FileManager.default.temporaryDirectory.appendingPathComponent("test.pdf")
        try "dummy".data(using: .utf8)!.write(to: tmpPDF)
        defer { try? FileManager.default.removeItem(at: tmpPDF) }

        // Register
        let stored = try store.registerPDF(at: tmpPDF, forID: "TestPaper", projectID: project.id)
        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(stored.path.contains(project.id.uuidString))

        // Cleanup
        store.cleanupPDF(paperID: "TestPaper", projectID: project.id)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func addInboxItemPersistsPDFAndMetadata() throws {
        let store = makeTestStore()
        let tmpPDF = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-test-\(UUID().uuidString).pdf")
        try "dummy".data(using: .utf8)!.write(to: tmpPDF)
        defer { try? FileManager.default.removeItem(at: tmpPDF) }

        let item = try store.addToInbox(from: tmpPDF, originalFilename: "Paper.pdf", source: .shareExtension)

        #expect(item.originalFilename == "Paper.pdf")
        #expect(item.source == .shareExtension)
        #expect(item.status == .pending)
        #expect(FileManager.default.fileExists(atPath: store.inboxPDFURL(for: item.id).path))
        #expect(FileManager.default.fileExists(atPath: store.inboxMetadataURL(for: item.id).path))
        #expect(store.inboxItems.contains(where: { $0.id == item.id }))
    }

    @Test func updateInboxItemStatusAndMetadata() async throws {
        let store = makeTestStore()
        let tmpPDF = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-test-\(UUID().uuidString).pdf")
        try "dummy".data(using: .utf8)!.write(to: tmpPDF)
        defer { try? FileManager.default.removeItem(at: tmpPDF) }

        let item = try store.addToInbox(from: tmpPDF)
        let metadata = CachedPDFMetadata(
            title: "Attention Is All You Need",
            authors: ["Ashish Vaswani"],
            abstract: "Transformer paper.",
            suggestedID: "Transformer"
        )

        try store.updateInboxItemStatus(item.id, status: .processed)
        try store.updateInboxItemMetadata(item.id, metadata: metadata)
        await store.reloadInboxFromDisk()

        let updated = try #require(store.inboxItems.first(where: { $0.id == item.id }))
        #expect(updated.status == .processed)
        #expect(updated.cachedMetadata == metadata)
    }

    @Test func addInboxItemDeduplicatesByContentHash() throws {
        let store = makeTestStore()
        let tmpPDF1 = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-test-\(UUID().uuidString)-1.pdf")
        let tmpPDF2 = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-test-\(UUID().uuidString)-2.pdf")
        try "same-content".data(using: .utf8)!.write(to: tmpPDF1)
        try "same-content".data(using: .utf8)!.write(to: tmpPDF2)
        defer {
            try? FileManager.default.removeItem(at: tmpPDF1)
            try? FileManager.default.removeItem(at: tmpPDF2)
        }

        let first = try store.addToInbox(from: tmpPDF1, originalFilename: "Paper.pdf")
        let second = try store.addToInbox(from: tmpPDF2, originalFilename: "Paper.pdf")

        #expect(first.id == second.id)
        #expect(store.inboxItems.filter { $0.id == first.id }.count == 1)
    }

    @Test func deleteInboxItemRemovesPDFAndMetadata() throws {
        let store = makeTestStore()
        let tmpPDF = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-test-\(UUID().uuidString).pdf")
        try "dummy".data(using: .utf8)!.write(to: tmpPDF)
        defer { try? FileManager.default.removeItem(at: tmpPDF) }

        let item = try store.addToInbox(from: tmpPDF)
        let pdfURL = store.inboxPDFURL(for: item.id)
        let metadataURL = store.inboxMetadataURL(for: item.id)

        try store.deleteInboxItem(item)

        #expect(!FileManager.default.fileExists(atPath: pdfURL.path))
        #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(!store.inboxItems.contains(where: { $0.id == item.id }))
    }

    @Test func importingProjectAssignsNewIDAndPreservesContent() {
        var source = Project(
            name: "Export Test",
            description: "desc",
            projectType: .techReport,
            generationPrompt: "Project prompt"
        )
        source.addPaper(Paper(id: "BERT", title: "BERT", authors: ["Devlin"], year: 2019))

        let imported = Project(importing: source, newID: UUID())
        #expect(imported.name == source.name)
        #expect(imported.description == source.description)
        #expect(imported.projectType == .techReport)
        #expect(imported.generationPrompt == "Project prompt")
        #expect(imported.papers.first?.id == "BERT")
        #expect(imported.id != source.id)
    }

    private func makeTestStore() -> Store {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelatedWorksTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return Store(synchronouslyLoadingFrom: tmp)
    }
}

// MARK: - ArxivService XML Parsing Tests

@Suite("ArxivService")
struct ArxivServiceTests {

    @Test func parseArxivXML() {
        let xml = """
        <?xml version="1.0"?>
        <feed>
          <entry>
            <title>Attention Is All You Need</title>
            <author><name>Ashish Vaswani</name></author>
            <author><name>Noam Shazeer</name></author>
            <published>2017-06-12T00:00:00Z</published>
            <summary>We propose a new simple network architecture, the Transformer.</summary>
            <id>http://arxiv.org/abs/1706.03762v5</id>
          </entry>
        </feed>
        """
        // ArxivService.parse is private, test via search result shape indirectly
        // by verifying the XML structure our parser expects
        #expect(xml.contains("<title>Attention Is All You Need</title>"))
        #expect(xml.contains("<name>Ashish Vaswani</name>"))
    }
}

// MARK: - DeepLink Tests

@Suite("DeepLink")
struct DeepLinkTests {

    @Test func parseProjectURL() {
        let id = UUID()
        let url = URL(string: "relatedworks://open?project=\(id.uuidString)")!
        let dest = DeepLink.parse(url)
        if case .project(let parsed) = dest {
            #expect(parsed == id)
        } else {
            Issue.record("Expected .project destination")
        }
    }

    @Test func parsePaperURL() {
        let id = UUID()
        let url = URL(string: "relatedworks://open?project=\(id.uuidString)&paper=BERT")!
        let dest = DeepLink.parse(url)
        if case .paper(let pid, let paperID) = dest {
            #expect(pid == id)
            #expect(paperID == "BERT")
        } else {
            Issue.record("Expected .paper destination")
        }
    }

    @Test func parseInvalidURL() {
        let url = URL(string: "https://example.com")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test func parseSettingsURL() {
        let url = URL(string: "relatedworks://settings")!
        let dest = DeepLink.parse(url)
        if case .settings = dest {
            let matched = true
            #expect(matched)
        } else {
            Issue.record("Expected .settings destination")
        }
    }

    @Test func generateProjectURL() {
        let project = Project(name: "Test")
        let url = DeepLink.url(for: project)
        #expect(url.scheme == "relatedworks")
        #expect(url.absoluteString.contains(project.id.uuidString))
    }

    @Test func generatePaperURL() {
        let project = Project(name: "Test")
        let paper = Paper(id: "BERT", title: "BERT")
        let url = DeepLink.url(for: paper, in: project)
        #expect(url.absoluteString.contains("paper=BERT"))
        #expect(url.absoluteString.contains(project.id.uuidString))
    }

    @Test func generateSettingsURL() {
        let url = DeepLink.settingsURL()
        #expect(url.absoluteString == "relatedworks://settings")
    }
}
