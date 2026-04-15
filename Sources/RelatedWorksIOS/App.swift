import SwiftUI

@main
struct RelatedWorksIOSApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var store: Store
    @State private var pendingDeepLink: DeepLink.Destination?

    init() {
        let s = Store()
        // Import sample project on first launch
        let key = "sampleProjectImported"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            if s.projects.isEmpty,
               let url = Bundle.main.url(forResource: "SampleProject", withExtension: "relatedworks") {
                _ = try? IOSProjectImporter.import(from: url, into: s)
            }
        }
        _store = State(initialValue: s)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            _ = Store.iCloudProjectsDir()
            guard AppSettings.shared.iCloudSyncEnabled else { return }
            try? ICloudHandleStore.publishInboxHandle()
        }
        Task.detached(priority: .utility) {
            await Self.refreshSharedICloudHandle(using: AppSettings.shared.iCloudSyncEnabled)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(pendingDeepLink: $pendingDeepLink)
                .environmentObject(store)
                .environmentObject(settings)
                .onChange(of: settings.iCloudSyncEnabled) {
                    store = Store()
                    Task {
                        await Self.refreshSharedICloudHandle(using: settings.iCloudSyncEnabled)
                    }
                }
                .onOpenURL { url in
                    pendingDeepLink = DeepLink.parse(url)
                }
        }
    }

    private static func refreshSharedICloudHandle(using enabled: Bool) async {
        if enabled {
            try? ICloudHandleStore.publishInboxHandle()
        } else {
            ICloudHandleStore.clearInboxHandle()
        }
    }
}
