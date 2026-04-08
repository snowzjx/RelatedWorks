import SwiftUI
import UniformTypeIdentifiers

extension DeepLink.Destination: Equatable {
    public static func == (lhs: DeepLink.Destination, rhs: DeepLink.Destination) -> Bool {
        switch (lhs, rhs) {
        case (.project(let a), .project(let b)): return a == b
        case (.paper(let a1, let a2), .paper(let b1, let b2)): return a1 == b1 && a2 == b2
        default: return false
        }
    }
}

struct PaperDestination: Hashable {
    let paper: Paper
    let projectID: UUID
}

struct ProjectListView: View {
    @EnvironmentObject var store: Store
    @Binding var pendingDeepLink: DeepLink.Destination?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                ForEach(store.projects) { project in
                    NavigationLink(value: project.id) {
                        ProjectRowView(project: project)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            pendingDeleteOffsets = IndexSet([store.projects.firstIndex(of: project)!])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: UUID.self) { projectID in
                PaperListView(projectID: projectID)
            }
            .navigationDestination(for: PaperDestination.self) { dest in
                PaperDetailView(paper: dest.paper, projectID: dest.projectID)
            }
            .onChange(of: pendingDeepLink) {
                guard let link = pendingDeepLink else { return }
                navPath.removeLast(navPath.count)
                switch link {
                case .project(let id):
                    navPath.append(id)
                case .paper(let projectID, let paperID):
                    navPath.append(projectID)
                    if let project = store.projects.first(where: { $0.id == projectID }),
                       let paper = project.paper(withID: paperID) {
                        navPath.append(PaperDestination(paper: paper, projectID: projectID))
                    }
                }
                pendingDeepLink = nil
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "relatedworks") ?? .data]
            ) { result in
                handleImport(result)
            }
            .alert("Import Failed", isPresented: .constant(importError != nil), actions: {
                Button("OK") { importError = nil }
            }, message: {
                Text(importError ?? "")
            })
            .alert("Delete Project", isPresented: Binding(
                get: { pendingDeleteOffsets != nil },
                set: { if !$0 { pendingDeleteOffsets = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let offsets = pendingDeleteOffsets {
                        for index in offsets { try? store.delete(store.projects[index]) }
                        pendingDeleteOffsets = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingDeleteOffsets = nil }
            } message: {
                Text("This project and all its papers will be permanently deleted.")
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try IOSProjectImporter.import(from: url, into: store)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

struct ProjectRowView: View {
    let project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name).font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                Text("\(project.papers.count)").font(.caption).foregroundStyle(.secondary)
            }
            if !project.description.isEmpty {
                Text(project.description).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
