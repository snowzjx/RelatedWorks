import SwiftUI

@main
struct RelatedWorksIOSApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var store = Store()
    @State private var pendingDeepLink: DeepLink.Destination?

    init() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            _ = Store.iCloudProjectsDir()
        }
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView(pendingDeepLink: $pendingDeepLink)
                .environmentObject(store)
                .environmentObject(settings)
                .onChange(of: settings.iCloudSyncEnabled) {
                    store = Store()
                }
                .onOpenURL { url in
                    pendingDeepLink = DeepLink.parse(url)
                }
        }
    }
}
