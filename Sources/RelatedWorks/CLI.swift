import ArgumentParser
import Foundation
import RelatedWorksCore

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "relatedworks",
        abstract: "RelatedWorks — CS literature manager",
        subcommands: [
            ProjectCreate.self, ProjectList.self,
            PaperAdd.self, PaperList.self, PaperAnnotate.self,
            Search.self, Generate.self,
        ]
    )
}

let store = Store()

// MARK: - Project Commands

struct ProjectCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "project:create")
    @Argument var name: String
    @Option(name: .shortAndLong) var description: String = ""

    func run() async throws {
        let project = Project(name: name, description: description)
        try store.save(project)
        print("✓ Created project '\(name)' [\(project.id)]")
    }
}

struct ProjectList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "project:list")

    func run() async throws {
        let projects = try store.loadAll()
        if projects.isEmpty { print("No projects yet. Use project:create <name>"); return }
        for p in projects {
            print("[\(p.id.uuidString.prefix(8))] \(p.name) — \(p.papers.count) paper(s)")
        }
    }
}

// MARK: - Paper Commands

struct PaperAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "paper:add")
    @Argument var projectID: String
    @Argument var semanticID: String          // e.g. "Transformer"
    @Option(name: .shortAndLong) var title: String = ""
    @Flag(name: .long) var dblp: Bool = false // fetch from DBLP

    func run() async throws {
        var projects = try store.loadAll()
        guard let idx = projects.firstIndex(where: { $0.id.uuidString.hasPrefix(projectID) }) else {
            print("Project not found"); return
        }

        var paper = Paper(id: semanticID, title: title)

        if dblp {
            print("Searching DBLP for '\(title.isEmpty ? semanticID : title)'...")
            let query = title.isEmpty ? semanticID : title
            let results = try await DBLPService.search(query: query)
            if let top = results.first {
                paper.title = top.title
                paper.authors = top.authors
                paper.year = top.year
                paper.venue = top.venue
                paper.dblpKey = top.dblpKey
                print("  Found: \(top.title) (\(top.year ?? 0)) — \(top.venue ?? "unknown venue")")
            } else {
                print("  No DBLP results found, using provided info.")
            }
        }

        projects[idx].addPaper(paper)
        try store.save(projects[idx])
        print("✓ Added paper [\(semanticID)] to '\(projects[idx].name)'")
    }
}

struct PaperList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "paper:list")
    @Argument var projectID: String

    func run() async throws {
        let projects = try store.loadAll()
        guard let project = projects.first(where: { $0.id.uuidString.hasPrefix(projectID) }) else {
            print("Project not found"); return
        }
        if project.papers.isEmpty { print("No papers yet."); return }
        for p in project.papers {
            let authors = p.authors.prefix(2).joined(separator: ", ")
            print("[\(p.id)] \(p.title) — \(authors) (\(p.year ?? 0))")
            if !p.annotation.isEmpty { print("  📝 \(p.annotation)") }
        }
    }
}

struct PaperAnnotate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "paper:annotate")
    @Argument var projectID: String
    @Argument var paperID: String
    @Argument var annotation: String

    func run() async throws {
        var projects = try store.loadAll()
        guard let pIdx = projects.firstIndex(where: { $0.id.uuidString.hasPrefix(projectID) }) else {
            print("Project not found"); return
        }
        guard let rIdx = projects[pIdx].papers.firstIndex(where: { $0.id.lowercased() == paperID.lowercased() }) else {
            print("Paper not found"); return
        }
        projects[pIdx].papers[rIdx].annotation = annotation
        try store.save(projects[pIdx])
        print("✓ Annotation saved for [\(paperID)]")
    }
}

// MARK: - DBLP Search

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search")
    @Argument var query: String

    func run() async throws {
        print("Searching DBLP for '\(query)'...")
        let results = try await DBLPService.search(query: query)
        if results.isEmpty { print("No results."); return }
        for r in results {
            let authors = r.authors.prefix(2).joined(separator: ", ")
            print("• \(r.title)")
            print("  \(authors) | \(r.venue ?? "?") | \(r.year ?? 0)")
        }
    }
}

// MARK: - Generate Related Works

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "generate")
    @Argument var projectID: String

    func run() async throws {
        let projects = try store.loadAll()
        guard let project = projects.first(where: { $0.id.uuidString.hasPrefix(projectID) }) else {
            print("Project not found"); return
        }
        print("Generating Related Works for '\(project.name)'...\n")
        let output = await RelatedWorksGenerator.generate(for: project)
        print(output)
    }
}
