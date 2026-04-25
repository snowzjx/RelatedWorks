import Foundation
#if canImport(RelatedWorksCore)
import RelatedWorksCore
#endif

let args = CommandLine.arguments
let store: Store
if let idx = args.firstIndex(of: "--projects-dir"), idx + 1 < args.count {
    store = Store(synchronouslyLoadingFrom: URL(fileURLWithPath: args[idx + 1]))
} else {
    let snapshot = await Store.prepareStartupSnapshot()
    store = Store(startupSnapshot: snapshot)
}

enableRaw()
defer { disableRaw(); cls() }

let projects = (try? store.loadAll()) ?? []
projectListScreen(projects: projects, store: store)
