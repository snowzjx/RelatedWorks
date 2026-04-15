import SwiftUI
import UniformTypeIdentifiers

extension DeepLink.Destination: Equatable {
    public static func == (lhs: DeepLink.Destination, rhs: DeepLink.Destination) -> Bool {
        switch (lhs, rhs) {
        case (.project(let a), .project(let b)): return a == b
        case (.paper(let a1, let a2), .paper(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.settings, .settings): return true
        default: return false
        }
    }
}

// MARK: - Root (NavigationSplitView for iPad, NavigationStack for iPhone)

struct RootView: View {
    @EnvironmentObject var store: Store
    @Binding var pendingDeepLink: DeepLink.Destination?
    @State private var selectedProjectID: UUID?
    @State private var selectedPaper: PaperDestination?
    @State private var showSettings = false

    var selectedProject: Project? {
        store.projects.first(where: { $0.id == selectedProjectID })
    }

    var body: some View {
        NavigationSplitView {
            ProjectListView(
                pendingDeepLink: $pendingDeepLink,
                selectedProjectID: $selectedProjectID,
                showSettings: $showSettings
            )
        } content: {
            if let id = selectedProjectID {
                PaperListView(projectID: id, selectedPaper: $selectedPaper)
            } else {
                ContentUnavailableView("Select a Project", systemImage: "folder")
            }
        } detail: {
            if let dest = selectedPaper {
                NavigationStack {
                    PaperDetailView(paper: dest.paper, projectID: dest.projectID)
                }
                .id(dest.paper.id)
            } else {
                ContentUnavailableView("Select a Paper", systemImage: "doc.text")
            }
        }
        .onChange(of: selectedProjectID) {
            selectedPaper = nil
        }
        .onChange(of: pendingDeepLink) {
            guard let link = pendingDeepLink else { return }
            switch link {
            case .project(let id):
                selectedProjectID = id
                selectedPaper = nil
            case .paper(let projectID, let paperID):
                selectedProjectID = projectID
                if let project = store.projects.first(where: { $0.id == projectID }),
                   let paper = project.paper(withID: paperID) {
                    selectedPaper = PaperDestination(paper: paper, projectID: projectID)
                }
            case .settings:
                showSettings = true
            }
            pendingDeepLink = nil
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
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
    @Binding var selectedProjectID: UUID?
    @Binding var showSettings: Bool
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var duplicateProjectID: UUID? = nil

    var body: some View {
        List(store.projects, selection: $selectedProjectID) { project in
            ProjectRowView(project: project)
                .tag(project.id)
                .swipeActions(edge: .trailing) {
                    Button {
                        pendingDeleteOffsets = IndexSet([store.projects.firstIndex(of: project)!])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gear")
                }
                Spacer()
                Button { showImporter = true } label: {
                    Label("Import", systemImage: "tray.and.arrow.down")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "relatedworks") ?? .data]
        ) { result in handleImport(result) }
        .alert("Import Failed", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
        .alert("Duplicate Project", isPresented: Binding(
            get: { duplicateProjectID != nil },
            set: { if !$0 { duplicateProjectID = nil } }
        )) {
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
        } message: { Text("This project and all its papers will be permanently deleted.") }
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
            Text(project.name).font(.headline).foregroundStyle(.blue)
            HStack(spacing: 4) {
                Image(systemName: "doc.text").font(.caption).foregroundStyle(Color(uiColor: .label))
                Text("\(project.papers.count)").font(.caption).foregroundStyle(Color(uiColor: .label))
            }
            if !project.description.isEmpty {
                Text(project.description).font(.caption).foregroundStyle(Color(uiColor: .label))
            }
        }
        .padding(.vertical, 2)
    }
}
