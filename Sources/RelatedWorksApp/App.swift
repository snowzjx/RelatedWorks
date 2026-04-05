import SwiftUI

@main
struct RelatedWorksApp: App {
    @StateObject private var store = Store()
    @StateObject private var deepLinkHandler = DeepLinkHandler()

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkHandler: deepLinkHandler)
                .environmentObject(store)
                .onOpenURL { url in
                    deepLinkHandler.handle(url)
                }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

class DeepLinkHandler: ObservableObject {
    @Published var pending: DeepLink.Destination?

    func handle(_ url: URL) {
        pending = DeepLink.parse(url)
    }
}
