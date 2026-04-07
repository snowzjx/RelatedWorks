import SwiftTUI
import RelatedWorksCore
import Foundation

// MARK: - Entry point

@main
struct RelatedWorksTUI {
    static func main() {
        let store = Store()
        let projects = (try? store.loadAll()) ?? []
        Application(rootView: RootView(projects: projects)).start()
    }
}

// MARK: - Identifiable wrappers for SwiftTUI ForEach

struct IndexedProject: Identifiable {
    let id: Int
    let project: Project
}

struct IndexedPaper: Identifiable {
    let id: Int
    let paper: Paper
}

// MARK: - Root

struct RootView: View {
    let projects: [Project]
    @State private var selectedIndex: Int? = nil

    var body: some View {
        if let idx = selectedIndex, idx < projects.count {
            ProjectView(project: projects[idx], onBack: { selectedIndex = nil })
        } else {
            ProjectListView(projects: projects, onSelect: { selectedIndex = $0 })
        }
    }
}

// MARK: - Project List

struct ProjectListView: View {
    let projects: [Project]
    var onSelect: (Int) -> Void

    var indexed: [IndexedProject] { projects.enumerated().map { IndexedProject(id: $0.offset, project: $0.element) } }

    var body: some View {
        VStack {
            Text("=== RelatedWorks ===")
            Text("")
            if projects.isEmpty {
                Text("No projects. Use: relatedworks project:create <name>")
            } else {
                ForEach(indexed) { item in
                    Button("  [\(item.project.id.uuidString.prefix(8))]  \(item.project.name)  (\(item.project.papers.count) papers)") {
                        onSelect(item.id)
                    }
                }
            }
            Text("")
            Text("  up/down: navigate   enter/space: select   ctrl+d: quit")
        }
        .padding()
    }
}

// MARK: - Project View

struct ProjectView: View {
    let project: Project
    var onBack: () -> Void
    @State private var selectedPaperIndex: Int? = nil
    @State private var showGenerated: Bool = false

    var indexed: [IndexedPaper] { project.papers.enumerated().map { IndexedPaper(id: $0.offset, paper: $0.element) } }

    var body: some View {
        if let idx = selectedPaperIndex, idx < project.papers.count {
            PaperView(paper: project.papers[idx], project: project, onBack: { selectedPaperIndex = nil })
        } else if showGenerated {
            GeneratingView(project: project, onBack: { showGenerated = false })
        } else {
            VStack {
                Text("=== \(project.name) ===")
                if !project.description.isEmpty {
                    Text("    \(project.description)")
                }
                Text("")
                if project.papers.isEmpty {
                    Text("  No papers yet.")
                } else {
                    ForEach(indexed) { item in
                        let p = item.paper
                        Button("  [@\(p.id)]  \(String(p.title.prefix(55)))  (\(p.year ?? 0))") {
                            selectedPaperIndex = item.id
                        }
                    }
                }
                Text("")
                Button("  [G] Generate Related Works") { showGenerated = true }
                Text("")
                Button("  [<] Back") { onBack() }
                Text("")
                Text("  up/down: navigate   enter/space: select   ctrl+d: quit")
            }
            .padding()
        }
    }
}

// MARK: - Paper View

struct IndexedRef: Identifiable {
    let id: Int
    let paper: Paper
}

struct PaperView: View {
    let paper: Paper
    let project: Project
    var onBack: () -> Void

    var refs: [IndexedRef] {
        project.crossReferences(for: paper.id).enumerated().map { IndexedRef(id: $0.offset, paper: $0.element) }
    }

    var body: some View {
        VStack {
            Text("=== \(String(paper.title.prefix(70))) ===")
            Text("")
            Text("  Authors : \(paper.authors.joined(separator: ", "))")
            Text("  Year    : \(paper.year.map(String.init) ?? "?")   Venue: \(paper.venue ?? "?")")
            Text("")
            if let abstract = paper.abstract, !abstract.isEmpty {
                Text("  -- Abstract --")
                Text("  \(String(abstract.prefix(400)))")
                Text("")
            }
            if !paper.annotation.isEmpty {
                Text("  -- Your Notes --")
                Text("  \(paper.annotation)")
                Text("")
            }
            if !refs.isEmpty {
                Text("  -- Cross-references --")
                ForEach(refs) { ref in
                    Text("    -> @\(ref.paper.id): \(String(ref.paper.title.prefix(50)))")
                }
                Text("")
            }
            Button("  [<] Back") { onBack() }
        }
        .padding()
    }
}

// MARK: - Generating View

struct GeneratingView: View {
    let project: Project
    var onBack: () -> Void
    @State private var result: String = ""
    @State private var done: Bool = false
    @State private var started: Bool = false

    var body: some View {
        VStack {
            Text("=== Generated Related Works: \(project.name) ===")
            Text("")
            if done {
                Text(result)
                Text("")
                Button("  [<] Back") { onBack() }
            } else {
                Text("  Press Enter on [Generate] to start generation...")
                Text("")
                Button("  [Generate]") {
                    if !started {
                        started = true
                        Task {
                            let r = await RelatedWorksGenerator.generate(for: project)
                            result = r
                            done = true
                        }
                    }
                }
                Button("  [<] Cancel") { onBack() }
            }
        }
        .padding()
    }
}
