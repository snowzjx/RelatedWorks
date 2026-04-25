import Foundation
#if canImport(RelatedWorksCore)
import RelatedWorksCore
#endif

let args = CommandLine.arguments
let store: Store
if let idx = args.firstIndex(of: "--projects-dir"), idx + 1 < args.count {
    store = Store(projectsDir: URL(fileURLWithPath: args[idx + 1]))
} else {
    store = Store()
}

enableRaw()
defer { disableRaw(); cls() }

let projects = (try? store.loadAll()) ?? []
projectListScreen(projects: projects, store: store)
