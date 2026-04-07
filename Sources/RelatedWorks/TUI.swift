import SwiftTUI
import RelatedWorksCore
import Foundation

// MARK: - Entry point

@main
struct RelatedWorksTUI {
    static func main() {
        let store = Store()
        let projects = (try? store.loadAll()) ?? []
        Application(rootView: AppView(projects: projects)).start()
    }
}

// MARK: - Single flat view with all buttons always in tree

struct AppView: View {
    let projects: [Project]
    @State private var projectIdx: Int? = nil
    @State private var paperIdx: Int? = nil
    @State private var showGenerated: Bool = false
    @State private var generated: String = ""
    @State private var generating: Bool = false

    var selectedProject: Project? { projectIdx.map { projects[$0] } }
    var selectedPaper: Paper? { paperIdx.flatMap { selectedProject?.papers[$0] } }

    var body: some View {
        VStack {
            // ── Header ──────────────────────────────────────────────
            if let paper = selectedPaper {
                Text("  \(String(paper.title.prefix(72)))")
            } else if let project = selectedProject {
                Text("  \(project.name)\(project.description.isEmpty ? "" : " — \(project.description)")")
            } else {
                Text("  RelatedWorks")
            }
            Text("")

            // ── Project list ─────────────────────────────────────────
            if projectIdx == nil {
                ForEach(projects.enumerated().map { IndexedProject(id: $0.offset, project: $0.element) }) { item in
                    Button("  [\(item.project.id.uuidString.prefix(8))]  \(item.project.name)  (\(item.project.papers.count) papers)") {
                        projectIdx = item.id
                        paperIdx = nil
                        showGenerated = false
                    }
                }
                if projects.isEmpty {
                    Text("  No projects. Use: relatedworks project:create <name>")
                }
            }

            // ── Paper list ───────────────────────────────────────────
            if let project = selectedProject, paperIdx == nil, !showGenerated {
                ForEach(project.papers.enumerated().map { IndexedPaper(id: $0.offset, paper: $0.element) }) { item in
                    let p = item.paper
                    Button("  [@\(p.id)]  \(String(p.title.prefix(55)))  (\(p.year ?? 0))") {
                        paperIdx = item.id
                    }
                }
                if project.papers.isEmpty {
                    Text("  No papers yet.")
                }
                Text("")
                Button("  [G] Generate Related Works") {
                    showGenerated = true
                    generating = true
                    Task {
                        generated = await RelatedWorksGenerator.generate(for: project)
                        generating = false
                    }
                }
            }

            // ── Paper detail ─────────────────────────────────────────
            if let paper = selectedPaper, let project = selectedProject {
                Text("  Authors : \(paper.authors.joined(separator: ", "))")
                Text("  Year    : \(paper.year.map(String.init) ?? "?")   Venue: \(paper.venue ?? "?")")
                if let abstract = paper.abstract, !abstract.isEmpty {
                    Text("")
                    Text("  -- Abstract --")
                    Text("  \(String(abstract.prefix(400)))")
                }
                if !paper.annotation.isEmpty {
                    Text("")
                    Text("  -- Notes --")
                    Text("  \(paper.annotation)")
                }
                let refs = project.crossReferences(for: paper.id)
                if !refs.isEmpty {
                    Text("")
                    Text("  -- Cross-references --")
                    ForEach(refs.enumerated().map { IndexedRef(id: $0.offset, paper: $0.element) }) { ref in
                        Text("    -> @\(ref.paper.id): \(String(ref.paper.title.prefix(50)))")
                    }
                }
            }

            // ── Generated output ─────────────────────────────────────
            if showGenerated {
                if generating {
                    Text("  Generating, please wait...")
                } else {
                    Text(generated)
                }
            }

            // ── Navigation buttons (always present) ──────────────────
            Text("")
            if paperIdx != nil {
                Button("  [<] Back to project") { paperIdx = nil }
            } else if showGenerated {
                Button("  [<] Back to project") { showGenerated = false }
            } else if projectIdx != nil {
                Button("  [<] Back to projects") { projectIdx = nil }
            }

            Text("")
            Text("  up/down: navigate   enter/space: select   ctrl+d: quit")
        }
        .padding()
    }
}

// MARK: - Helpers

struct IndexedProject: Identifiable {
    let id: Int
    let project: Project
}

struct IndexedPaper: Identifiable {
    let id: Int
    let paper: Paper
}

struct IndexedRef: Identifiable {
    let id: Int
    let paper: Paper
}
