import Foundation
import CryptoKit

public class Store: ObservableObject {
    public let projectsDir: URL
    @Published public var projects: [Project] = []

    private var metadataQuery: NSMetadataQuery?

    // MARK: - Init

    public init() {
        let useICloud = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        if useICloud {
            var icloudURL: URL? = nil
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                icloudURL = Store.iCloudProjectsDir()
                sem.signal()
            }
            sem.wait()
            projectsDir = icloudURL ?? Store.localProjectsDir()
        } else {
            projectsDir = Store.localProjectsDir()
        }
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
        migrateGlobalPDFs()
        startMetadataQuery()
    }

    public init(projectsDir: URL) {
        self.projectsDir = projectsDir
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
    }

    // MARK: - iCloud URL resolution

    public static func iCloudProjectsDir() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.me.snowzjx.relatedworks")?
            .appendingPathComponent("Documents/projects", isDirectory: true)
    }

    public static func localProjectsDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("RelatedWorks/projects", isDirectory: true)
    }

    private static func resolveProjectsDir() -> URL {
        let useICloud = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        if useICloud, let icloud = iCloudProjectsDir() { return icloud }
        return localProjectsDir()
    }

    // MARK: - Per-project PDF directory

    public func pdfsDir(for projectID: UUID) -> URL {
        projectsDir.appendingPathComponent("\(projectID.uuidString)/pdfs", isDirectory: true)
    }

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

    public func cleanupPDF(paperID: String, projectID: UUID) {
        let path = pdfsDir(for: projectID).appendingPathComponent("\(paperID).pdf").path
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - ID Registry

    public var allPaperIDs: Set<String> {
        Set(projects.flatMap { $0.papers.map { $0.id.lowercased() } })
    }

    public func isIDTaken(_ id: String) -> Bool {
        allPaperIDs.contains(id.lowercased())
    }

    public func existingID(forPDFAt url: URL, title: String? = nil) -> String? {
        if let hash = sha256(url) {
            for project in projects {
                for paper in project.papers {
                    if let path = paper.pdfPath, let h = sha256(URL(fileURLWithPath: path)), h == hash {
                        return paper.id
                    }
                }
            }
        }
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !title.isEmpty {
            for project in projects {
                if let paper = project.papers.first(where: { $0.title.lowercased() == title }) {
                    return paper.id
                }
            }
        }
        return nil
    }

    // MARK: - Persistence (NSFileCoordinator-aware)

    private func url(for project: Project) -> URL {
        projectsDir.appendingPathComponent("\(project.id.uuidString).json")
    }

    public func save(_ project: Project) throws {
        try? FileManager.default.createDirectory(at: pdfsDir(for: project.id), withIntermediateDirectories: true)
        let fileURL = url(for: project)
        let data = try JSONEncoder().encode(project)
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do { try data.write(to: url) } catch { writeError = error }
        }
        if let e = coordinatorError ?? writeError { throw e }
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.insert(project, at: 0)
        }
    }

    public func loadAll() throws -> [Project] {
        let files = try FileManager.default.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.compactMap { fileURL -> Project? in
            var result: Project?
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatorError) { url in
                result = try? JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
            }
            return result
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ project: Project) throws {
        let fileURL = url(for: project)
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinatorError) { url in
            try? FileManager.default.removeItem(at: url)
        }
        if let e = coordinatorError { throw e }
        let projectFolder = projectsDir.appendingPathComponent(project.id.uuidString)
        try? FileManager.default.removeItem(at: projectFolder)
        projects.removeAll { $0.id == project.id }
    }

    // MARK: - Reload (called by metadata query on remote changes)

    public func reload() {
        projects = (try? loadAll()) ?? []
    }

    // MARK: - NSMetadataQuery (iCloud remote change detection)

    private func startMetadataQuery() {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidUpdate),
                                               name: .NSMetadataQueryDidUpdate, object: query)
        query.start()
        metadataQuery = query
    }

    @objc private func metadataQueryDidUpdate() {
        DispatchQueue.main.async { self.reload() }
    }

    // MARK: - Migration

    public func migrateToICloud(progress: @escaping (Double) -> Void) async throws {
        var icloudDir: URL?
        for _ in 0..<10 {
            icloudDir = await Task.detached(priority: .userInitiated) { Store.iCloudProjectsDir() }.value
            if icloudDir != nil { break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        guard let icloudDir else { throw MigrationError.iCloudUnavailable }
        let fm = FileManager.default
        try fm.createDirectory(at: icloudDir, withIntermediateDirectories: true)
        let localDir = Store.localProjectsDir()
        let items = (try? fm.contentsOfDirectory(at: localDir, includingPropertiesForKeys: nil)) ?? []
        for (i, item) in items.enumerated() {
            let dest = icloudDir.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try fm.copyItem(at: item, to: dest)
            try? fm.removeItem(at: item) // remove source after successful copy
            await MainActor.run { progress(Double(i + 1) / Double(items.count)) }
        }
    }

    public func migrateToLocal(progress: @escaping (Double) -> Void) async throws {
        guard let icloudDir = await Task.detached(priority: .userInitiated, operation: { Store.iCloudProjectsDir() }).value else { return }
        let fm = FileManager.default
        let localDir = Store.localProjectsDir()
        try fm.createDirectory(at: localDir, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(at: icloudDir, includingPropertiesForKeys: nil)) ?? []
        for (i, item) in items.enumerated() {
            let dest = localDir.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try? fm.removeItem(at: dest)
            }
            try fm.copyItem(at: item, to: dest)
            try? fm.removeItem(at: item) // remove source after successful copy
            await MainActor.run { progress(Double(i + 1) / Double(items.count)) }
        }
    }

    public enum MigrationError: LocalizedError {
        case iCloudUnavailable
        public var errorDescription: String? {
            "iCloud Drive is not available. Make sure you are signed in to iCloud and iCloud Drive is enabled."
        }
    }

    // MARK: - Legacy migration (global pdfs → per-project)

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
                if oldPath.contains(projects[i].id.uuidString) { continue }
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
