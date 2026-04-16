import SwiftUI
import UserNotifications

enum AppWindowID {
    static let main = "main"
    static let generate = "generate"
    static let inbox = "inbox"
}

@MainActor
final class InboxProcessingCoordinator: ObservableObject {
    private var inFlightItemIDs = Set<UUID>()
    private let notifier = InboxProcessingNotifier()

    func prepareNotifications() {
        notifier.prepareNotifications()
    }

    func scheduleProcessing(for store: Store) {
        let candidates = store.inboxItems.compactMap { item -> (InboxItem, URL)? in
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
            return (item, pdfURL)
        }

        for (item, pdfURL) in candidates {
            inFlightItemIDs.insert(item.id)
            Task.detached(priority: .utility) {
                let extracted = await PDFImporter.extractMetadata(from: pdfURL)
                let cached = CachedPDFMetadata(
                    title: extracted.title,
                    authors: extracted.authors,
                    abstract: extracted.abstract,
                    suggestedID: extracted.suggestedID
                )

                await MainActor.run {
                    defer { self.inFlightItemIDs.remove(item.id) }

                    do {
                        try store.updateInboxItemMetadata(item.id, metadata: cached)
                        try store.updateInboxItemStatus(item.id, status: .processed)
                        if item.status != .processed,
                           let updatedItem = store.inboxItems.first(where: { $0.id == item.id }) {
                            self.notifier.notifyProcessedInboxItem(updatedItem)
                        }
                    } catch {
                        return
                    }
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

@MainActor
private final class InboxProcessingNotifier: NSObject, UNUserNotificationCenterDelegate {
    private enum DefaultsKey {
        static let didDeferEnablingNotifications = "didDeferEnablingNotifications"
    }

    private let center = UNUserNotificationCenter.current()
    private var didPrepareNotifications = false
    private var didPromptToEnableNotifications = false

    override init() {
        super.init()
        center.delegate = self
    }

    func prepareNotifications() {
        guard !didPrepareNotifications else { return }
        didPrepareNotifications = true

        center.getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .notDetermined:
                    let granted = (try? await self.center.requestAuthorization(options: [.alert, .sound])) ?? false
                    if !granted {
                        self.promptToEnableNotifications()
                    }
                case .authorized, .provisional, .ephemeral:
                    self.clearDeferredNotificationPrompt()
                    break
                case .denied:
                    self.promptToEnableNotifications()
                @unknown default:
                    break
                }
            }
        }
    }

    func notifyProcessedInboxItem(_ item: InboxItem) {
        let semanticID = item.cachedMetadata?.suggestedID?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let semanticID, !semanticID.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Inbox Processing Complete"
        content.body = "\(semanticID) has been added in inbox, you can add it to a project via add paper."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "inbox-processed-\(item.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
    }

    private func promptToEnableNotifications() {
        guard !didPromptToEnableNotifications else { return }
        guard !didDeferEnablingNotifications else { return }
        didPromptToEnableNotifications = true

        let alert = NSAlert()
        alert.messageText = "Enable Notifications"
        alert.informativeText = "RelatedWorks notifications are turned off. Enable them in System Settings if you want inbox processing to notify you when a paper is ready to add."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        guard alert.runModal() == .alertFirstButtonReturn else {
            didDeferEnablingNotifications = true
            return
        }
        openNotificationSettings()
    }

    private var didDeferEnablingNotifications: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.didDeferEnablingNotifications) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.didDeferEnablingNotifications) }
    }

    private func clearDeferredNotificationPrompt() {
        guard didDeferEnablingNotifications else { return }
        didDeferEnablingNotifications = false
    }

    private func openNotificationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
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
                .onAppear {
                    inboxProcessingCoordinator.prepareNotifications()
                    inboxProcessingCoordinator.scheduleProcessing(for: store)
                }
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
