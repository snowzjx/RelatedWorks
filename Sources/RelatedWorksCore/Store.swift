import Foundation
import CryptoKit

public class Store: ObservableObject {
    public let projectsDir: URL
    public let inboxDir: URL
    @Published public var projects: [Project] = []
    @Published public var inboxItems: [InboxItem] = []

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
        inboxDir = Store.inboxDir(forProjectsDir: projectsDir)
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
        inboxItems = (try? loadAllInboxItems()) ?? []
        startMetadataQuery()
    }

    public init(projectsDir: URL) {
        self.projectsDir = projectsDir
        self.inboxDir = Store.inboxDir(forProjectsDir: projectsDir)
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
        inboxItems = (try? loadAllInboxItems()) ?? []
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

    public static func iCloudInboxDir() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.me.snowzjx.relatedworks")?
            .appendingPathComponent("Documents/inbox", isDirectory: true)
    }

    public static func localInboxDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("RelatedWorks/inbox", isDirectory: true)
    }

    private static func resolveProjectsDir() -> URL {
        let useICloud = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        if useICloud, let icloud = iCloudProjectsDir() { return icloud }
        return localProjectsDir()
    }

    private static func inboxDir(forProjectsDir projectsDir: URL) -> URL {
        if projectsDir.lastPathComponent == "projects" {
            return projectsDir.deletingLastPathComponent().appendingPathComponent("inbox", isDirectory: true)
        }
        return projectsDir.appendingPathComponent("inbox", isDirectory: true)
    }

    // MARK: - Per-project PDF directory

    public func pdfsDir(for projectID: UUID) -> URL {
        projectsDir.appendingPathComponent("\(projectID.uuidString)/pdfs", isDirectory: true)
    }

    public func pdfURL(for paperID: String, projectID: UUID) -> URL {
        pdfsDir(for: projectID).appendingPathComponent("\(paperID).pdf")
    }

    @discardableResult
    public func registerPDF(at sourceURL: URL, forID id: String, projectID: UUID) throws -> URL {
        let dir = pdfsDir(for: projectID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(id).pdf")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        }
        return dest
    }

    public func cleanupPDF(paperID: String, projectID: UUID) {
        let path = pdfsDir(for: projectID).appendingPathComponent("\(paperID).pdf").path
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Inbox

    public func inboxPDFURL(for itemID: UUID) -> URL {
        inboxDir.appendingPathComponent("\(itemID.uuidString).pdf")
    }

    public func inboxMetadataURL(for itemID: UUID) -> URL {
        inboxDir.appendingPathComponent("\(itemID.uuidString).json")
    }

    @discardableResult
    public func addToInbox(
        from sourceURL: URL,
        originalFilename: String? = nil,
        source: InboxItemSource = .unknown
    ) throws -> InboxItem {
        try FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        let contentHash = sha256(sourceURL)

        if let contentHash,
           let existing = inboxItems.first(where: { $0.contentHash == contentHash }) {
            return existing
        }

        let item = InboxItem(
            originalFilename: originalFilename ?? sourceURL.lastPathComponent,
            source: source,
            contentHash: contentHash
        )
        let destination = inboxPDFURL(for: item.id)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try saveInboxItem(item)
        return item
    }

    public func saveInboxItem(_ item: InboxItem) throws {
        let fileURL = inboxMetadataURL(for: item.id)
        let data = try JSONEncoder().encode(item)
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do { try data.write(to: url) } catch { writeError = error }
        }
        if let e = coordinatorError ?? writeError { throw e }
        if let idx = inboxItems.firstIndex(where: { $0.id == item.id }) {
            inboxItems[idx] = item
        } else {
            inboxItems.insert(item, at: 0)
        }
        inboxItems.sort { $0.createdAt > $1.createdAt }
    }

    public func loadAllInboxItems() throws -> [InboxItem] {
        let files = try FileManager.default.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.compactMap { fileURL -> InboxItem? in
            var result: InboxItem?
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatorError) { url in
                result = try? JSONDecoder().decode(InboxItem.self, from: Data(contentsOf: url))
            }
            return result
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func reloadInbox() {
        inboxItems = (try? loadAllInboxItems()) ?? []
    }

    public func deleteInboxItem(_ item: InboxItem) throws {
        let fileURL = inboxMetadataURL(for: item.id)
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinatorError) { url in
            try? FileManager.default.removeItem(at: url)
        }
        if let e = coordinatorError { throw e }
        try? FileManager.default.removeItem(at: inboxPDFURL(for: item.id))
        inboxItems.removeAll { $0.id == item.id }
    }

    public func updateInboxItemStatus(_ itemID: UUID, status: InboxItemStatus) throws {
        guard var item = inboxItems.first(where: { $0.id == itemID }) else { return }
        item.status = status
        try saveInboxItem(item)
    }

    public func updateInboxItemMetadata(_ itemID: UUID, metadata: CachedPDFMetadata?) throws {
        guard var item = inboxItems.first(where: { $0.id == itemID }) else { return }
        item.cachedMetadata = metadata
        try saveInboxItem(item)
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
                for paper in project.papers where paper.hasPDF {
                    let paperURL = pdfURL(for: paper.id, projectID: project.id)
                    if let h = sha256(paperURL), h == hash { return paper.id }
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
        inboxItems = (try? loadAllInboxItems()) ?? []
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

    // MARK: - Helpers

    private func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
