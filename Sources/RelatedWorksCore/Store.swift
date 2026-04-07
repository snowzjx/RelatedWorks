import Foundation
import CryptoKit

public class Store: ObservableObject {
    public let projectsDir: URL
    @Published public var projects: [Project] = []

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        projectsDir = appSupport.appendingPathComponent("RelatedWorks/projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
        migrateGlobalPDFs()
    }

    public init(projectsDir: URL) {
        self.projectsDir = projectsDir
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
    }

    // MARK: - Per-project PDF directory

    public func pdfsDir(for projectID: UUID) -> URL {
        projectsDir.appendingPathComponent("\(projectID.uuidString)/pdfs", isDirectory: true)
    }

    /// Registers a PDF for a paper in a specific project. Copies to project's pdfs folder.
    @discardableResult
    public func registerPDF(at sourceURL: URL, forID id: String, projectID: UUID) throws -> String {
        let dir = pdfsDir(for: projectID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(id).pdf")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        }
        return dest.path
    }

    /// Removes the PDF file for a paper when it's deleted from a project.
    public func cleanupPDF(paperID: String, projectID: UUID) {
        let path = pdfsDir(for: projectID).appendingPathComponent("\(paperID).pdf").path
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - ID Registry (cross-project, for deduplication)

    public var allPaperIDs: Set<String> {
        Set(projects.flatMap { $0.papers.map { $0.id.lowercased() } })
    }

    public func isIDTaken(_ id: String) -> Bool {
        allPaperIDs.contains(id.lowercased())
    }

    /// Returns existing paperID if this PDF matches by title within any project.
    public func existingID(forPDFAt url: URL, title: String? = nil) -> String? {
        // Hash match
        if let hash = sha256(url) {
            for project in projects {
                for paper in project.papers {
                    if let path = paper.pdfPath, let h = sha256(URL(fileURLWithPath: path)), h == hash {
                        return paper.id
                    }
                }
            }
        }
        // Title match fallback
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !title.isEmpty {
            for project in projects {
                if let paper = project.papers.first(where: { $0.title.lowercased() == title }) {
                    return paper.id
                }
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func url(for project: Project) -> URL {
        projectsDir.appendingPathComponent("\(project.id.uuidString).json")
    }

    public func save(_ project: Project) throws {
        // Ensure project pdfs dir exists
        try? FileManager.default.createDirectory(at: pdfsDir(for: project.id), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(project)
        try data.write(to: url(for: project))
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.insert(project, at: 0)
        }
    }

    public func loadAll() throws -> [Project] {
        let files = try FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.compactMap {
            try? JSONDecoder().decode(Project.self, from: Data(contentsOf: $0))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ project: Project) throws {
        // Delete project JSON
        try FileManager.default.removeItem(at: url(for: project))
        // Delete project folder (PDFs + anything else)
        let projectFolder = projectsDir.appendingPathComponent(project.id.uuidString)
        try? FileManager.default.removeItem(at: projectFolder)
        projects.removeAll { $0.id == project.id }
    }

    // MARK: - Migration from global pdfs/ to per-project

    private func migrateGlobalPDFs() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let globalPDFsDir = appSupport.appendingPathComponent("RelatedWorks/pdfs")
        guard FileManager.default.fileExists(atPath: globalPDFsDir.path) else { return }

        var changed = false
        for i in 0 ..< projects.count {
            for j in 0 ..< projects[i].papers.count {
                let paper = projects[i].papers[j]
                guard let oldPath = paper.pdfPath else { continue }
                let oldURL = URL(fileURLWithPath: oldPath)
                // Already in project folder?
                if oldPath.contains(projects[i].id.uuidString) { continue }
                // Migrate
                let newDir = pdfsDir(for: projects[i].id)
                try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
                let newURL = newDir.appendingPathComponent("\(paper.id).pdf")
                if FileManager.default.fileExists(atPath: oldURL.path) && !FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.copyItem(at: oldURL, to: newURL)
                }
                if FileManager.default.fileExists(atPath: newURL.path) {
                    projects[i].papers[j].pdfPath = newURL.path
                    changed = true
                }
            }
            if changed { try? save(projects[i]) }
        }
    }

    // MARK: - Helpers

    private func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
