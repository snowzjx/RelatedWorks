import SwiftUI

struct ProjectSidebar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @Binding var selectedProjectID: UUID?
    @State private var showingNewProject = false
    @State private var renameTarget: Project?

    var body: some View {
        List(store.projects, selection: $selectedProjectID) { project in
            ProjectRow(project: project)
                .tag(project.id)
                .contextMenu {
                    Button("Edit") {
                        renameTarget = project
                    }
                    Divider()
                    Button(role: .destructive) {
                        if selectedProjectID == project.id { selectedProjectID = nil }
                        try? store.delete(project)
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                }
        }
        .navigationTitle("RelatedWorks")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !settings.isGenerationConfigured && !settings.isExtractionConfigured {
                NoModelBanner()
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showingNewProject = true }) {
                    Label("New Project", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Project (⌘N)")
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet(isPresented: $showingNewProject, onCreated: { id in
                selectedProjectID = id
            })
        }
        .sheet(item: $renameTarget) { project in
            RenameProjectSheet(project: project, isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            ))
        }
        .overlay {
            if store.projects.isEmpty {
                VStack(spacing: 8) {
                    Text("No projects yet")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Button("New Project") { showingNewProject = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name).fontWeight(.medium).lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "doc.text").font(.caption2)
                Text("\(project.papers.count) paper\(project.papers.count == 1 ? "" : "s")").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RenameProjectSheet: View {
    @EnvironmentObject var store: Store
    let project: Project
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var description = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project").font(.title3).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextField("What paper are you writing?", text: $description)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.escape)
                Button("Save") {
                    var updated = project
                    updated.name = name.trimmingCharacters(in: .whitespaces)
                    updated.description = description.trimmingCharacters(in: .whitespaces)
                    try? store.save(updated)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 360)
        .onAppear { name = project.name; description = project.description; focused = true }
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject var store: Store
    @Binding var isPresented: Bool
    var onCreated: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var description = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Project")
                .font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Label("Project Name", systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Attention Mechanisms Survey", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Description (optional)", systemImage: "text.alignleft")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("What paper are you writing?", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private func create() {
        let p = Project(name: name.trimmingCharacters(in: .whitespaces), description: description)
        try? store.save(p)
        onCreated(p.id)
        isPresented = false
    }
}
