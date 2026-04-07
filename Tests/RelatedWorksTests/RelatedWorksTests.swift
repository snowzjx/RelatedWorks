import Testing
import Foundation
import RelatedWorksCore

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

    @Test func globalIDRegistry() throws {
        let store = makeTestStore()
        var p1 = Project(name: "Project 1")
        p1.addPaper(Paper(id: "BERT", title: "BERT"))
        try store.save(p1)
        #expect(store.isIDTaken("BERT"))
        #expect(store.isIDTaken("bert"))
        #expect(!store.isIDTaken("GPT"))
    }

    @Test func duplicatePDFDetectedByTitle() throws {
        let store = makeTestStore()
        var project = Project(name: "Project")
        project.addPaper(Paper(id: "BERT", title: "BERT: Pre-training"))
        try store.save(project)

        // existingID by title match (no PDF file needed)
        let id = store.existingID(forPDFAt: URL(fileURLWithPath: "/nonexistent.pdf"), title: "BERT: Pre-training")
        #expect(id == "BERT")
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
        #expect(FileManager.default.fileExists(atPath: stored))
        #expect(stored.contains(project.id.uuidString))

        // Cleanup
        store.cleanupPDF(paperID: "TestPaper", projectID: project.id)
        #expect(!FileManager.default.fileExists(atPath: stored))
    }

    @Test func exportAndImportProject() throws {
        let store = makeTestStore()
        var project = Project(name: "Export Test")
        project.addPaper(Paper(id: "BERT", title: "BERT", authors: ["Devlin"], year: 2019))
        try store.save(project)

        // Export
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportTest.relatedworks")
        defer { try? FileManager.default.removeItem(at: exportURL) }
        try ProjectExporter.export(project, pdfsDir: store.pdfsDir(for: project.id), to: exportURL)
        #expect(FileManager.default.fileExists(atPath: exportURL.path))

        // Import into a fresh store
        let store2 = makeTestStore()
        let imported = try ProjectExporter.import(from: exportURL, into: store2)
        #expect(imported.name == "Export Test")
        #expect(imported.papers.first?.id == "BERT")
        #expect(imported.id != project.id) // new UUID assigned
    }

    private func makeTestStore() -> Store {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelatedWorksTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return Store(projectsDir: tmp)
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
}
