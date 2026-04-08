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

struct ProjectNavDestination: Hashable {
    let projectID: UUID
    var autoRename: Bool = false
}

struct ImportConfirmSheet: View {
    @Binding var name: String
    @Binding var description: String
    let paperCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("Title", text: $name)
                    TextField("Description", text: $description)
                }
                Section {
                    Label("\(paperCount) paper\(paperCount == 1 ? "" : "s")", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: onConfirm).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct ProjectListView: View {
    @EnvironmentObject var store: Store
    @Binding var pendingDeepLink: DeepLink.Destination?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var navPath = NavigationPath()
    @State private var duplicateProjectID: UUID? = nil

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                ForEach(store.projects) { project in
                    NavigationLink(value: ProjectNavDestination(projectID: project.id)) {
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
            .navigationDestination(for: ProjectNavDestination.self) { dest in
                PaperListView(projectID: dest.projectID, autoRename: dest.autoRename)
            }
            .navigationDestination(for: PaperDestination.self) { dest in
                PaperDetailView(paper: dest.paper, projectID: dest.projectID)
            }
            .onChange(of: pendingDeepLink) {
                guard let link = pendingDeepLink else { return }
                navPath.removeLast(navPath.count)
                switch link {
                case .project(let id):
                    navPath.append(ProjectNavDestination(projectID: id))
                case .paper(let projectID, let paperID):
                    navPath.append(ProjectNavDestination(projectID: projectID))
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
                        Label("Import", systemImage: "tray.and.arrow.down")
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
            .alert("Duplicate Project", isPresented: Binding(
                get: { duplicateProjectID != nil },
                set: { if !$0 { duplicateProjectID = nil } }
            )) {
                Button("Rename") {
                    if let id = duplicateProjectID {
                        navPath.append(ProjectNavDestination(projectID: id, autoRename: true))
                    }
                    duplicateProjectID = nil
                }
                Button("OK", role: .cancel) { duplicateProjectID = nil }
            } message: {
                Text("A project with the same name already exists. Please rename one of them to avoid confusion.")
            }
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
                let project = try IOSProjectImporter.import(from: url, into: store)
                if store.projects.filter({ $0.name == project.name }).count > 1 {
                    duplicateProjectID = project.id
                }
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
                Text(project.description).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
