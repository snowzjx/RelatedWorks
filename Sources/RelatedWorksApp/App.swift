import SwiftUI

enum AppWindowID {
    static let main = "main"
    static let generate = "generate"
    static let inbox = "inbox"
}

@MainActor
final class InboxProcessingCoordinator: ObservableObject {
    private var inFlightItemIDs = Set<UUID>()

    func scheduleProcessing(for store: Store) {
        let candidates = store.inboxItems.compactMap { item -> (UUID, URL, Set<String>)? in
            guard !inFlightItemIDs.contains(item.id) else { return nil }

            let pdfURL = store.inboxPDFURL(for: item.id)
            guard FileManager.default.fileExists(atPath: pdfURL.path) else { return nil }

            let cached = item.cachedMetadata
            let needsMetadata = item.status == .pending ||
                cached == nil ||
                (
                    cached?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true &&
                    cached?.authors.isEmpty != false
                )

            guard needsMetadata else { return nil }
            return (item.id, pdfURL, store.allPaperIDs)
        }

        for (itemID, pdfURL, takenIDs) in candidates {
            inFlightItemIDs.insert(itemID)
            Task.detached(priority: .utility) {
                let extracted = await PDFImporter.extractMetadata(from: pdfURL, takenIDs: takenIDs)
                let cached = CachedPDFMetadata(
                    title: extracted.title,
                    authors: extracted.authors,
                    abstract: extracted.abstract,
                    suggestedID: extracted.suggestedID
                )

                await MainActor.run {
                    defer { self.inFlightItemIDs.remove(itemID) }
                    try? store.updateInboxItemMetadata(itemID, metadata: cached)
                    try? store.updateInboxItemStatus(itemID, status: .processed)
                }
            }
        }
    }

    func requestReprocess(_ itemID: UUID, in store: Store) {
        inFlightItemIDs.remove(itemID)
        try? store.updateInboxItemMetadata(itemID, metadata: nil)
        try? store.updateInboxItemStatus(itemID, status: .pending)
        scheduleProcessing(for: store)
    }
}

@main
struct RelatedWorksApp: App {
    @State private var store = Store()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @StateObject private var inboxProcessingCoordinator = InboxProcessingCoordinator()
    @State private var showHelp = false

    var body: some Scene {
        Window("Main Window", id: AppWindowID.main) {
            ContentView(deepLinkHandler: deepLinkHandler)
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(inboxProcessingCoordinator)
                .onOpenURL { url in deepLinkHandler.handle(url) }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .sheet(isPresented: $showHelp) { HelpView() }
                .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in showHelp = true }
                .onReceive(NotificationCenter.default.publisher(for: .iCloudSyncChanged)) { _ in
                    store = Store()
                    inboxProcessingCoordinator.scheduleProcessing(for: store)
                }
                .onAppear { inboxProcessingCoordinator.scheduleProcessing(for: store) }
                .onReceive(store.$inboxItems) { _ in
                    inboxProcessingCoordinator.scheduleProcessing(for: store)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    NotificationCenter.default.post(name: .newProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                AddPaperMenuButton()
                OpenInboxWindowButton()

                Button("Import Project…") {
                    NotificationCenter.default.post(name: .importProject, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                ExportMenuButton()
            }
            CommandGroup(replacing: .help) {
                Button("User Guide") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(store)
        }

        WindowGroup(id: AppWindowID.generate, for: UUID.self) { $projectID in
            GenerateWindowView(projectID: projectID)
                .environmentObject(store)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 720, height: 540)

        Window("Inbox", id: AppWindowID.inbox) {
            InboxManagementView()
                .environmentObject(store)
                .environmentObject(inboxProcessingCoordinator)
                .onAppear { inboxProcessingCoordinator.scheduleProcessing(for: store) }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 920, height: 620)
    }
}

// Focused value for selected project
struct SelectedProjectKey: FocusedValueKey {
    typealias Value = UUID
}

extension FocusedValues {
    var selectedProjectID: UUID? {
        get { self[SelectedProjectKey.self] }
        set { self[SelectedProjectKey.self] = newValue }
    }
}

struct ExportMenuButton: View {
    @FocusedValue(\.selectedProjectID) var selectedProjectID
    var body: some View {
        Button("Export Project…") {
            NotificationCenter.default.post(name: .exportProject, object: nil)
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(selectedProjectID == nil)
    }
}

struct AddPaperMenuButton: View {
    @FocusedValue(\.selectedProjectID) var selectedProjectID

    var body: some View {
        Button("Add Paper…") {
            NotificationCenter.default.post(name: .addPaper, object: nil)
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .disabled(selectedProjectID == nil)
    }
}

struct OpenInboxWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Inbox") {
            openWindow(id: AppWindowID.inbox)
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])
    }
}

extension Notification.Name {
    static let newProject = Notification.Name("newProject")
    static let addPaper = Notification.Name("addPaper")
    static let importProject = Notification.Name("importProject")
    static let exportProject = Notification.Name("exportProject")
    static let showHelp = Notification.Name("showHelp")
    static let iCloudSyncChanged = Notification.Name("iCloudSyncChanged")
}

class DeepLinkHandler: ObservableObject {
    @Published var pending: DeepLink.Destination?

    func handle(_ url: URL) {
        pending = DeepLink.parse(url)
    }
}
