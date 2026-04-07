import SwiftUI

@main
struct RelatedWorksIOSApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(store)
        }
    }
}
