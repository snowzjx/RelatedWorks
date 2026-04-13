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
                    Button("Export…") {
                        exportProject(project)
                    }
                    Divider()
                    Button(role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = "Delete \"\(project.name)\"?"
                        alert.informativeText = "This will permanently delete the project and all its PDFs. This cannot be undone."
                        alert.addButton(withTitle: "Delete")
                        alert.addButton(withTitle: "Cancel")
                        alert.buttons[0].hasDestructiveAction = true
                        guard alert.runModal() == .alertFirstButtonReturn else { return }
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
                Button(action: { importProject() }) {
                    Label("Import Project", systemImage: "square.and.arrow.down")
                }
                .help("Import Project (⌘⇧I)")
            }
            ToolbarItem {
                Button(action: { showingNewProject = true }) {
                    Label("New Project", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Project (⌘N)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importProject)) { _ in
            importProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in
            showingNewProject = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportProject)) { _ in
            guard let id = selectedProjectID,
                  let project = store.projects.first(where: { $0.id == id }) else { return }
            exportProject(project)
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
                VStack(spacing: 12) {
                    Text("No projects yet")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Button("New Project") { showingNewProject = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Import Project…") { importProject() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func exportProject(_ project: Project) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = project.name
        panel.allowedContentTypes = [.init(filenameExtension: "relatedworks")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = normalizedExportURL(url)
        do {
            try ProjectExporter.export(project, pdfsDir: store.pdfsDir(for: project.id), to: destination)
        } catch {
            let alert = NSAlert(); alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }

    private func normalizedExportURL(_ url: URL) -> URL {
        var base = url
        while base.pathExtension.lowercased() == "relatedworks" {
            base = base.deletingPathExtension()
        }
        return base.appendingPathExtension("relatedworks")
    }

    private func importProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "relatedworks")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Peek at the project name before importing
            let project = try ProjectExporter.import(from: url, into: store)
            if store.projects.contains(where: { $0.name == project.name && $0.id != project.id }) {
                let alert = NSAlert()
                alert.messageText = "Duplicate Project"
                alert.informativeText = "A project named \"\(project.name)\" already exists. Please rename one of them to avoid confusion."
                alert.runModal()
            }
            selectedProjectID = project.id
        } catch {
            let alert = NSAlert(); alert.messageText = "Import Failed"
            alert.informativeText = error.localizedDescription; alert.runModal()
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
    @State private var projectType: ProjectType = .custom
    @State private var generationPrompt = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project").font(.title3).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 8) {
                Label("Project Name", systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Description (optional)", systemImage: "text.alignleft")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("What paper are you writing?", text: $description)
                    .textFieldStyle(.roundedBorder)
            }
            projectPromptFields
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.escape)
                Button("Save") {
                    var updated = project
                    updated.name = name.trimmingCharacters(in: .whitespaces)
                    updated.description = description.trimmingCharacters(in: .whitespaces)
                    updated.projectType = projectType
                    updated.generationPrompt = generationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? store.save(updated)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                          generationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 460)
        .onAppear {
            name = project.name
            description = project.description
            projectType = project.projectType
            generationPrompt = project.generationPrompt
            focused = true
        }
        .onChange(of: generationPrompt) { newValue in
            syncProjectTypeForPrompt(newValue)
        }
    }

    @ViewBuilder
    private var projectPromptFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Project Type", systemImage: "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Project Type", selection: $projectType) {
                ForEach(ProjectType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .onChange(of: projectType) { newValue in
                if let preset = newValue.presetPrompt {
                    generationPrompt = preset
                }
            }

            Label("Project Prompt", systemImage: "text.badge.star")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $generationPrompt)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 140)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

            HStack {
                Text(projectType == .custom ? "Custom prompt for this project." : "Prompt preset for \(projectType.displayName).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let preset = projectType.presetPrompt {
                    Button("Reset to Preset") { generationPrompt = preset }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
    }

    private func syncProjectTypeForPrompt(_ prompt: String) {
        guard projectType != .custom, let preset = projectType.presetPrompt else { return }
        if prompt != preset {
            projectType = .custom
        }
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject var store: Store
    @Binding var isPresented: Bool
    var onCreated: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var description = ""
    @State private var projectType: ProjectType = .researchPaper
    @State private var generationPrompt = ProjectType.researchPaper.presetPrompt ?? ""
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

            VStack(alignment: .leading, spacing: 8) {
                Label("Project Type", systemImage: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Project Type", selection: $projectType) {
                    ForEach(ProjectType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .onChange(of: projectType) { newValue in
                    if let preset = newValue.presetPrompt {
                        generationPrompt = preset
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Project Prompt", systemImage: "text.badge.star")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $generationPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 140)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                HStack {
                    Text(projectType == .custom ? "Custom prompt for this project." : "Prompt preset for \(projectType.displayName).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let preset = projectType.presetPrompt {
                        Button("Reset to Preset") { generationPrompt = preset }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              generationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { focused = true }
        .onChange(of: generationPrompt) { newValue in
            guard projectType != .custom, let preset = projectType.presetPrompt else { return }
            if newValue != preset {
                projectType = .custom
            }
        }
    }

    private func create() {
        let p = Project(
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            projectType: projectType,
            generationPrompt: generationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try? store.save(p)
        onCreated(p.id)
        isPresented = false
    }
}
