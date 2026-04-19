import Foundation

public enum InboxItemStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case processed

    public var displayName: String {
        switch self {
        case .pending:
            return String(localized: "Pending")
        case .processed:
            return String(localized: "Processed")
        }
    }
}

public enum InboxItemSource: String, Codable, CaseIterable, Hashable, Sendable {
    case shareExtension
    case macShareExtension
    case unknown

    public var displayName: String {
        switch self {
        case .shareExtension:
            return String(localized: "iOS Share Extension")
        case .macShareExtension:
            return String(localized: "mac Share Extension")
        case .unknown:
            return String(localized: "Unknown")
        }
    }
}

public struct CachedPDFMetadata: Codable, Hashable, Sendable {
    public var title: String
    public var authors: [String]
    public var abstract: String?
    public var suggestedID: String?

    public init(title: String = "", authors: [String] = [], abstract: String? = nil, suggestedID: String? = nil) {
        self.title = title
        self.authors = authors
        self.abstract = abstract
        self.suggestedID = suggestedID
    }
}

public struct InboxItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var originalFilename: String
    public var source: InboxItemSource
    public var createdAt: Date
    public var status: InboxItemStatus
    public var cachedMetadata: CachedPDFMetadata?
    public var contentHash: String?

    public init(
        id: UUID = UUID(),
        originalFilename: String,
        source: InboxItemSource = .unknown,
        createdAt: Date = Date(),
        status: InboxItemStatus = .pending,
        cachedMetadata: CachedPDFMetadata? = nil,
        contentHash: String? = nil
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.source = source
        self.createdAt = createdAt
        self.status = status
        self.cachedMetadata = cachedMetadata
        self.contentHash = contentHash
    }
}

public enum InboxHandleStore {
    public static let appGroupIdentifier = "group.me.snowzjx.relatedworks"
    private static let inboxBookmarkKey = "sharedInboxBookmark"

    public enum HandleError: LocalizedError {
        case notPublished

        public var errorDescription: String? {
            switch self {
            case .notPublished:
                return String(localized: "Open RelatedWorks once so it can publish the inbox location, then try sharing again.")
            }
        }
    }

    public static func publishInboxHandle(_ inboxURL: URL) throws {
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        let bookmark = try inboxURL.bookmarkData(
            options: URL.BookmarkCreationOptions.minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard let sharedDefaults else {
            log("Failed to publish inbox handle because shared defaults for \(appGroupIdentifier) are unavailable.")
            throw HandleError.notPublished
        }

        sharedDefaults.set(bookmark, forKey: inboxBookmarkKey)
        sharedDefaults.synchronize()
        log("Published inbox handle for path: \(inboxURL.path)")
    }

    public static func clearInboxHandle() {
        guard let sharedDefaults else {
            log("Failed to clear inbox handle because shared defaults for \(appGroupIdentifier) are unavailable.")
            return
        }

        sharedDefaults.removeObject(forKey: inboxBookmarkKey)
        sharedDefaults.synchronize()
        log("Cleared published inbox handle.")
    }

    public static func resolveInboxHandle() throws -> URL {
        guard let sharedDefaults else {
            log("Failed to resolve inbox handle because shared defaults for \(appGroupIdentifier) are unavailable.")
            throw HandleError.notPublished
        }

        guard let bookmark = sharedDefaults.data(forKey: inboxBookmarkKey) else {
            log("No published inbox handle was found in shared defaults.")
            throw HandleError.notPublished
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            let refreshed = try url.bookmarkData(
                options: URL.BookmarkCreationOptions.minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            sharedDefaults.set(refreshed, forKey: inboxBookmarkKey)
            sharedDefaults.synchronize()
            log("Refreshed stale inbox bookmark for path: \(url.path)")
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        log("Resolved inbox handle to path: \(url.path)")
        return url
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private static func log(_ message: String) {
        NSLog("[InboxHandleStore] %@", message)
    }
}

public enum ICloudHandleStore {
    private static let ubiquityContainerIdentifier = "iCloud.me.snowzjx.relatedworks"

    public enum HandleError: LocalizedError {
        case unavailable

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                return String(localized: "iCloud Drive is unavailable. Enable iCloud Drive and RelatedWorks iCloud access, then open the app again.")
            }
        }
    }

    public static func publishInboxHandle() throws {
        guard let inboxURL = FileManager.default
            .url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier)?
            .appendingPathComponent("Documents/inbox", isDirectory: true) else {
            InboxHandleStore.clearInboxHandle()
            throw HandleError.unavailable
        }
        try InboxHandleStore.publishInboxHandle(inboxURL)
    }

    public static func clearInboxHandle() {
        InboxHandleStore.clearInboxHandle()
    }

    public static func resolveInboxHandle() throws -> URL {
        try InboxHandleStore.resolveInboxHandle()
    }
}
