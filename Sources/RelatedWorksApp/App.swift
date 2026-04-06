import SwiftUI

@main
struct RelatedWorksApp: App {
    @StateObject private var store = Store()
    @StateObject private var deepLinkHandler = DeepLinkHandler()

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkHandler: deepLinkHandler)
                .environmentObject(store)
                .environmentObject(AppSettings.shared)
                .onOpenURL { url in deepLinkHandler.handle(url) }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            PreferencesView()
        }
    }
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
