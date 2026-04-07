import Foundation
import CryptoKit

public class Store: ObservableObject {
    public let projectsDir: URL
    public let pdfsDir: URL
    @Published var projects: [Project] = []

    // Global registry: paperID -> pdfPath, pdfHash -> paperID
    private(set) var idToPDFPath: [String: String] = [:]
    private(set) var pdfHashToID: [String: String] = [:]

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        projectsDir = appSupport.appendingPathComponent("RelatedWorks/projects", isDirectory: true)
        pdfsDir = appSupport.appendingPathComponent("RelatedWorks/pdfs", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: pdfsDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
        rebuildRegistry()
    }

    /// Initializer for testing with a custom directory.
    public init(projectsDir: URL) {
        self.projectsDir = projectsDir
        self.pdfsDir = projectsDir.appendingPathComponent("pdfs")
        try? FileManager.default.createDirectory(at: self.pdfsDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
        rebuildRegistry()
    }    // MARK: - Global ID / PDF Registry

    /// All paper IDs in use across all projects (case-insensitive lookup)
    public var allPaperIDs: Set<String> {
        Set(projects.flatMap { $0.papers.map { $0.id.lowercased() } })
    }

    public func isIDTaken(_ id: String) -> Bool {
        allPaperIDs.contains(id.lowercased())
    }

    /// Returns existing paperID if this PDF matches by content hash OR by title (case-insensitive).
    public func existingID(forPDFAt url: URL, title: String? = nil) -> String? {
        // 1. Hash match (most reliable)
        if let hash = sha256(url), let id = pdfHashToID[hash] { return id }
        // 2. Title match fallback
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !title.isEmpty {
            for project in projects {
                if let paper = project.papers.first(where: { $0.title.lowercased() == title }) {
                    return paper.id
                }
            }
        }
        return nil
    }

    /// Returns the stored PDF path for a given paperID, if any.
    public func pdfPath(forID id: String) -> String? {
        idToPDFPath[id.lowercased()]
    }

    /// Registers a PDF for a paperID. Copies file only if not already stored.
    /// Returns the stored path.
    @discardableResult
    public func registerPDF(at sourceURL: URL, forID id: String) throws -> String {
        let dest = pdfsDir.appendingPathComponent("\(id).pdf")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        }
        let path = dest.path
        idToPDFPath[id.lowercased()] = path
        if let hash = sha256(dest) { pdfHashToID[hash] = id }
        return path
    }

    private func rebuildRegistry() {
        idToPDFPath = [:]
        pdfHashToID = [:]
        for project in projects {
            for paper in project.papers {
                if let path = paper.pdfPath {
                    idToPDFPath[paper.id.lowercased()] = path
                    let url = URL(fileURLWithPath: path)
                    if let hash = sha256(url) { pdfHashToID[hash] = paper.id }
                }
            }
        }
    }

    private func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    private func url(for project: Project) -> URL {
        projectsDir.appendingPathComponent("\(project.id.uuidString).json")
    }

    public func save(_ project: Project) throws {
        let data = try JSONEncoder().encode(project)
        try data.write(to: url(for: project))
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.insert(project, at: 0)
        }
        rebuildRegistry()
    }

    public func loadAll() throws -> [Project] {
        let files = try FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.compactMap {
            try? JSONDecoder().decode(Project.self, from: Data(contentsOf: $0))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ project: Project) throws {
        try FileManager.default.removeItem(at: url(for: project))
        projects.removeAll { $0.id == project.id }
        rebuildRegistry()
    }

    /// Removes the PDF file for a paper if no other paper across all projects references it.
    public func cleanupPDFIfUnused(paperID: String, pdfPath: String, excludingProjectID: UUID) {
        let inUse = projects
            .filter { $0.id != excludingProjectID }
            .flatMap { $0.papers }
            .contains { $0.pdfPath == pdfPath }
        || projects
            .first { $0.id == excludingProjectID }
            .map { $0.papers.contains { $0.id != paperID && $0.pdfPath == pdfPath } } ?? false

        if !inUse {
            try? FileManager.default.removeItem(atPath: pdfPath)
            idToPDFPath.removeValue(forKey: paperID.lowercased())
            pdfHashToID = pdfHashToID.filter { $0.value.lowercased() != paperID.lowercased() }
        }
    }
}
