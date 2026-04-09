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
        importSampleProjectIfNeeded()
    }

    private func importSampleProjectIfNeeded() {
        let key = "sampleProjectImported"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard store.projects.isEmpty,
              let url = Bundle.main.url(forResource: "SampleProject", withExtension: "relatedworks") else { return }
        _ = try? IOSProjectImporter.import(from: url, into: store)
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
