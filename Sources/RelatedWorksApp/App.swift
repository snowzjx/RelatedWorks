import SwiftUI

@main
struct RelatedWorksApp: App {
    @StateObject private var store = Store()
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @State private var showHelp = false

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkHandler: deepLinkHandler)
                .environmentObject(store)
                .environmentObject(AppSettings.shared)
                .onOpenURL { url in deepLinkHandler.handle(url) }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .sheet(isPresented: $showHelp) { HelpView() }
                .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in showHelp = true }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Import Project…") {
                    NotificationCenter.default.post(name: .importProject, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("RelatedWorks Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

extension Notification.Name {
    static let importProject = Notification.Name("importProject")
    static let showHelp = Notification.Name("showHelp")
}

// Globally accessible settings opener
func openAppSettings() {
    // Find and click the Settings menu item directly
    for item in NSApp.mainMenu?.items ?? [] {
        guard let submenu = item.submenu else { continue }
        for sub in submenu.items {
            let title = sub.title.lowercased()
            if title.contains("setting") || title.contains("preference") {
                sub.menu?.performActionForItem(at: submenu.items.firstIndex(of: sub)!)
                return
            }
        }
    }
}

class DeepLinkHandler: ObservableObject {
    @Published var pending: DeepLink.Destination?

    func handle(_ url: URL) {
        pending = DeepLink.parse(url)
    }
}
