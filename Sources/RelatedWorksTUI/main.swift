import Foundation
#if canImport(RelatedWorksCore)
import RelatedWorksCore
#endif

enableRaw()
defer { disableRaw(); cls() }

let store = Store()
let projects = (try? store.loadAll()) ?? []
projectListScreen(projects: projects)
