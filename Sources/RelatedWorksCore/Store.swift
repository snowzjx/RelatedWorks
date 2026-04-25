import Foundation
import CryptoKit

public class Store: ObservableObject {
    public let projectsDir: URL
    public let inboxDir: URL
    @Published public var projects: [Project] = []
    @Published public var inboxItems: [InboxItem] = []

    private var metadataQuery: NSMetadataQuery?
    @MainActor private var reloadTask: Task<Void, Never>?

    public struct StartupProgress: Sendable {
        public let completedUnitCount: Int
        public let totalUnitCount: Int
        public let message: String

        public var fractionCompleted: Double {
            guard totalUnitCount > 0 else { return 0 }
            return Double(completedUnitCount) / Double(totalUnitCount)
        }
    }

    public struct StartupSnapshot: Sendable {
        let projectsDir: URL
        let inboxDir: URL
        let projects: [Project]
        let inboxItems: [InboxItem]
        let shouldStartMetadataQuery: Bool
    }

    // MARK: - Init

    @available(*, deprecated, message: "Performs synchronous file I/O. App startup should await Store.prepareStartupSnapshot and then use Store(startupSnapshot:).")
    public convenience init() {
        self.init(synchronouslyLoadingFromDefaultLocation: ())
    }

    @available(*, deprecated, message: "Performs synchronous file I/O. Prefer Store(synchronouslyLoadingFrom:) only in CLI/test contexts, or prepareStartupSnapshot for app startup.")
    public convenience init(projectsDir: URL) {
        self.init(synchronouslyLoadingFrom: projectsDir)
    }

    private convenience init(synchronouslyLoadingFromDefaultLocation _: Void) {
        let useICloud = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        let resolvedProjectsDir = useICloud ? (Store.iCloudProjectsDir() ?? Store.localProjectsDir()) : Store.localProjectsDir()
        self.init(synchronouslyLoadingFrom: resolvedProjectsDir)
        if useICloud {
            startMetadataQuery()
        }
    }

    public init(synchronouslyLoadingFrom projectsDir: URL) {
        self.projectsDir = projectsDir
        self.inboxDir = Store.inboxDir(forProjectsDir: projectsDir)
        try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        projects = (try? loadAll()) ?? []
        inboxItems = (try? loadAllInboxItems()) ?? []
    }

    public init(startupSnapshot: StartupSnapshot) {
        self.projectsDir = startupSnapshot.projectsDir
        self.inboxDir = startupSnapshot.inboxDir
        self.projects = startupSnapshot.projects
        self.inboxItems = startupSnapshot.inboxItems
        if startupSnapshot.shouldStartMetadataQuery {
            startMetadataQuery()
        }
    }

    public static func prepareStartupSnapshot(
        progress: (@Sendable (StartupProgress) -> Void)? = nil
    ) async -> StartupSnapshot {
        await Task.detached(priority: .userInitiated) {
            let useICloud = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
            let totalSteps = 4
            var completedSteps = 0

            func report(_ message: String) {
                completedSteps += 1
                progress?(StartupProgress(
                    completedUnitCount: completedSteps,
                    totalUnitCount: totalSteps,
                    message: message
                ))
            }

            let projectsDir: URL
            if useICloud {
                projectsDir = Store.iCloudProjectsDir() ?? Store.localProjectsDir()
            } else {
                projectsDir = Store.localProjectsDir()
            }
            let inboxDir = Store.inboxDir(forProjectsDir: projectsDir)
            report(useICloud ? "Resolving iCloud storage" : "Resolving local storage")

            try? FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
            report("Preparing project folders")

            let projects = (try? Store.loadAll(from: projectsDir)) ?? []
            report("Loading projects")

            let inboxItems = (try? Store.loadAllInboxItems(from: inboxDir)) ?? []
            report("Loading inbox")

            return StartupSnapshot(
                projectsDir: projectsDir,
                inboxDir: inboxDir,
                projects: projects,
                inboxItems: inboxItems,
                shouldStartMetadataQuery: useICloud
            )
        }.value
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

    public func citationGraphDataURL(for projectID: UUID) -> URL {
        projectsDir.appendingPathComponent("\(projectID.uuidString)/citation-graph.json")
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
        try Self.loadAllInboxItems(from: inboxDir)
    }

    @available(*, deprecated, message: "Performs synchronous file I/O. App code should await reloadInboxFromDisk().")
    public func reloadInbox() {
        inboxItems = (try? loadAllInboxItems()) ?? []
    }

    @MainActor
    public func reloadInboxFromDisk() async {
        let inboxDir = inboxDir
        let inboxItems = await Task.detached(priority: .userInitiated) {
            (try? Store.loadAllInboxItems(from: inboxDir)) ?? []
        }.value
        guard !Task.isCancelled else { return }
        self.inboxItems = inboxItems
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

    public func loadCitationGraphData(for projectID: UUID) throws -> CitationGraphProjectData {
        let fileURL = citationGraphDataURL(for: projectID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CitationGraphProjectData(projectID: projectID)
        }

        var result: CitationGraphProjectData?
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatorError) { url in
            result = try? JSONDecoder().decode(CitationGraphProjectData.self, from: Data(contentsOf: url))
        }
        if let error = coordinatorError { throw error }
        return result ?? CitationGraphProjectData(projectID: projectID)
    }

    public func saveCitationGraphData(_ data: CitationGraphProjectData) throws {
        let folder = projectsDir.appendingPathComponent(data.projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = citationGraphDataURL(for: data.projectID)
        let payload = try JSONEncoder().encode(data)
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
            do { try payload.write(to: url) } catch { writeError = error }
        }
        if let error = coordinatorError ?? writeError { throw error }
    }

    public func loadAll() throws -> [Project] {
        try Self.loadAll(from: projectsDir)
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

    @available(*, deprecated, message: "Performs synchronous file I/O. App code should await reloadFromDisk().")
    public func reload() {
        projects = (try? loadAll()) ?? []
        inboxItems = (try? loadAllInboxItems()) ?? []
    }

    @MainActor
    public func reloadFromDisk() async {
        let projectsDir = projectsDir
        let inboxDir = inboxDir
        let snapshot = await Task.detached(priority: .userInitiated) {
            (
                projects: (try? Store.loadAll(from: projectsDir)) ?? [],
                inboxItems: (try? Store.loadAllInboxItems(from: inboxDir)) ?? []
            )
        }.value
        guard !Task.isCancelled else { return }
        projects = snapshot.projects
        inboxItems = snapshot.inboxItems
    }

    @MainActor
    private func scheduleReloadFromDisk() {
        reloadTask?.cancel()
        reloadTask = Task {
            await reloadFromDisk()
            reloadTask = nil
        }
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
        Task { @MainActor in
            self.scheduleReloadFromDisk()
        }
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

    private static func loadAll(from projectsDir: URL) throws -> [Project] {
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

    private static func loadAllInboxItems(from inboxDir: URL) throws -> [InboxItem] {
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
}
