import Foundation

public enum InboxItemStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case processed
}

public enum InboxItemSource: String, Codable, CaseIterable, Hashable, Sendable {
    case appImport
    case shareExtension
    case unknown

    public var displayName: String {
        switch self {
        case .appImport:
            return "App Import"
        case .shareExtension:
            return "iOS Share Extension"
        case .unknown:
            return "Unknown"
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

public enum ICloudHandleStore {
    public static let appGroupIdentifier = "group.me.snowzjx.relatedworks"
    private static let inboxBookmarkKey = "iCloudInboxBookmark"
    private static let ubiquityContainerIdentifier = "iCloud.me.snowzjx.relatedworks"

    public enum HandleError: LocalizedError {
        case unavailable
        case notPublished

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                return "iCloud Drive is unavailable. Enable iCloud Drive and RelatedWorks iCloud access, then open the app again."
            case .notPublished:
                return "Open RelatedWorks, enable iCloud sync in Settings if needed, wait a moment for setup to finish, and then try sharing again."
            }
        }
    }

    public static func publishInboxHandle() throws {
        guard let inboxURL = FileManager.default
            .url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier)?
            .appendingPathComponent("Documents/inbox", isDirectory: true) else {
            clearInboxHandle()
            throw HandleError.unavailable
        }

        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        let bookmark = try inboxURL.bookmarkData(
            options: URL.BookmarkCreationOptions.minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        sharedDefaults?.set(bookmark, forKey: inboxBookmarkKey)
    }

    public static func clearInboxHandle() {
        sharedDefaults?.removeObject(forKey: inboxBookmarkKey)
    }

    public static func resolveInboxHandle() throws -> URL {
        guard let bookmark = sharedDefaults?.data(forKey: inboxBookmarkKey) else {
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
            sharedDefaults?.set(refreshed, forKey: inboxBookmarkKey)
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
