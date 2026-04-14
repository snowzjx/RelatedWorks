import SwiftUI

private enum AppWindowID {
    static let main = "main"
    static let generate = "generate"
}

@main
struct RelatedWorksApp: App {
    @State private var store = Store()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @State private var showHelp = false

    var body: some Scene {
        Window("Main Window", id: AppWindowID.main) {
            ContentView(deepLinkHandler: deepLinkHandler)
                .environmentObject(store)
                .environmentObject(settings)
                .onOpenURL { url in deepLinkHandler.handle(url) }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .sheet(isPresented: $showHelp) { HelpView() }
                .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in showHelp = true }
                .onReceive(NotificationCenter.default.publisher(for: .iCloudSyncChanged)) { _ in
                    store = Store()
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
