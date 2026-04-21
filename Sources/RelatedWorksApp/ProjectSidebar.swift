import SwiftUI

struct ProjectSidebar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var reachability = OllamaReachability.shared
    @Binding var selectedProjectID: UUID?
    @State private var showingNewProject = false
    @State private var renameTarget: Project?
    @State private var isExportingProject = false
    @State private var exportStatus = ""
    @State private var exportProgress: Double?

    var body: some View {
        List(store.projects, selection: $selectedProjectID) { project in
            ProjectRow(project: project)
                .tag(project.id)
                .anchorPreference(key: FirstLaunchAnchorPreferenceKey.self, value: .bounds) { project.id == selectedProjectID ? [.projectSelection: $0] : [:] }
                .contextMenu {
                    Button(appLocalized("Edit")) {
                        renameTarget = project
                    }
                    Button(appLocalized("Export…")) {
                        exportProject(project)
                    }
                    Divider()
                    Button(role: .destructive) {
                        let alert = NSAlert()
                        alert.messageText = appLocalizedFormat("Delete \"%@\"?", project.name)
                        alert.informativeText = appLocalized("This will permanently delete the project and all its PDFs. This cannot be undone.")
                        alert.addButton(withTitle: appLocalized("Delete"))
                        alert.addButton(withTitle: appLocalized("Cancel"))
                        alert.buttons[0].hasDestructiveAction = true
                        guard alert.runModal() == .alertFirstButtonReturn else { return }
                        if selectedProjectID == project.id { selectedProjectID = nil }
                        try? store.delete(project)
                    } label: {
                        Label(appLocalized("Delete Project"), systemImage: "trash")
                    }
                }
        }
        .navigationTitle("RelatedWorks")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let ollamaDown = !reachability.reachable
                && (settings.extractionBackend == .ollama || settings.generationBackend == .ollama)
            if !settings.isGenerationConfigured && !settings.isExtractionConfigured || ollamaDown {
                NoModelBanner()
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: { openWindow(id: AppWindowID.inbox) }) {
                    Label(appLocalized("Inbox"), systemImage: "tray.full")
                }
                .help(appLocalized("Inbox (⌘⇧B)"))
            }
            ToolbarItem {
                Button(action: { importProject() }) {
                    Label(appLocalized("Import Project"), systemImage: "square.and.arrow.down")
                }
                .help(appLocalized("Import Project (⌘⇧I)"))
            }
            ToolbarItem {
                Button(action: { showingNewProject = true }) {
                    Label(appLocalized("New Project"), systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help(appLocalized("New Project (⌘N)"))
                .anchorPreference(key: FirstLaunchAnchorPreferenceKey.self, value: .bounds) { [.projectCreateToolbar: $0] }
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
                    Text(appLocalized("No projects yet"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Button(appLocalized("New Project")) { showingNewProject = true }
                        .buttonStyle(.borderedProminent)
                        .inactiveAwareProminentButtonForeground()
                        .controlSize(.small)
                        .anchorPreference(key: FirstLaunchAnchorPreferenceKey.self, value: .bounds) { [.projectCreateEmpty: $0] }
                    Button(appLocalized("Import Project")) { importProject() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .overlay {
            if isExportingProject {
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        ExportProgressOverlay(status: exportStatus, progress: exportProgress)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 16)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
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
        let pdfsDir = store.pdfsDir(for: project.id)
        isExportingProject = true
        exportStatus = appLocalized("Preparing export…")
        exportProgress = nil

        Task.detached(priority: .userInitiated) {
            do {
                try ProjectExporter.export(
                    project,
                    pdfsDir: pdfsDir,
                    to: destination
                ) { message, fraction in
                    Task { @MainActor in
                        exportStatus = message
                        exportProgress = fraction
                    }
                }
                await MainActor.run {
                    isExportingProject = false
                    exportProgress = nil
                }
            } catch {
                await MainActor.run {
                    isExportingProject = false
                    exportProgress = nil
                    let alert = NSAlert()
                    alert.messageText = appLocalized("Export Failed")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
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
            let project = try ProjectExporter.import(from: url, into: store)
            if store.projects.contains(where: { $0.name == project.name && $0.id != project.id }) {
                let alert = NSAlert()
                alert.messageText = appLocalized("Duplicate Project")
                alert.informativeText = appLocalizedFormat("A project named \"%@\" already exists. Please rename one of them to avoid confusion.", project.name)
                alert.runModal()
            }
            selectedProjectID = project.id
        } catch {
            let alert = NSAlert(); alert.messageText = appLocalized("Import Failed")
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
}

private struct ExportProgressOverlay: View {
    let status: String
    let progress: Double?

    var body: some View {
        HStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            } else {
                ProgressView()
                    .frame(width: 120)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appLocalized("Exporting Project"))
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
        .frame(width: 320)
    }
}

struct InboxManagementView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var inboxProcessingCoordinator: InboxProcessingCoordinator
    @State private var selectedItemID: UUID?

    private var selectedItem: InboxItem? {
        store.inboxItems.first(where: { $0.id == selectedItemID })
    }

    var body: some View {
        NavigationSplitView {
            List(store.inboxItems, selection: $selectedItemID) { item in
                InboxManagementRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        Button("Open PDF") { openPDF(for: item) }
                        Button("Reveal in Finder") { revealInFinder(for: item) }
                        Button(role: .destructive) { delete(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .navigationTitle("Inbox")
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            if let item = selectedItem {
                InboxDetailView(
                    item: item,
                    onDelete: { delete(item) }
                )
            } else {
                EmptyStateView(
                    icon: "tray",
                    title: "No Inbox Item Selected",
                    message: "Select a synced PDF to inspect or manage it."
                )
            }
        }
        .onAppear {
            if selectedItemID == nil {
                selectedItemID = store.inboxItems.first?.id
            }
            inboxProcessingCoordinator.scheduleProcessing(for: store)
        }
        .onChange(of: store.inboxItems) { _, items in
            if let selectedItemID, items.contains(where: { $0.id == selectedItemID }) {
                return
            }
            self.selectedItemID = items.first?.id
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if let item = selectedItem {
                        openPDF(for: item)
                    }
                } label: {
                    Label("Open PDF", systemImage: "doc.text")
                }
                .disabled(selectedItem == nil)

                Button {
                    if let item = selectedItem {
                        revealInFinder(for: item)
                    }
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .disabled(selectedItem == nil)
                Button(role: .destructive) {
                    if let item = selectedItem {
                        delete(item)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedItem == nil)
            }
        }
    }

    private func openPDF(for item: InboxItem) {
        NSWorkspace.shared.open(store.inboxPDFURL(for: item.id))
    }

    private func revealInFinder(for item: InboxItem) {
        NSWorkspace.shared.activateFileViewerSelecting([store.inboxPDFURL(for: item.id)])
    }

    private func delete(_ item: InboxItem) {
        let alert = NSAlert()
        alert.messageText = appLocalizedFormat("Delete \"%@\"?", item.originalFilename)
        alert.informativeText = appLocalized("This removes the inbox PDF and its cached metadata.")
        alert.addButton(withTitle: appLocalized("Delete"))
        alert.addButton(withTitle: appLocalized("Cancel"))
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? store.deleteInboxItem(item)
    }
}

private struct InboxManagementRow: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.status == .processed ? "tray.full.fill" : "tray")
                    .foregroundStyle(item.status == .processed ? .green : .secondary)
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            Text("\(item.source.displayName) · \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if false { EmptyView() }
            if let authors, !authors.isEmpty {
                Text(authors)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var title: String {
        let cachedTitle = item.cachedMetadata?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cachedTitle.isEmpty ? item.originalFilename : cachedTitle
    }

    private var authors: String? {
        let list = item.cachedMetadata?.authors ?? []
        guard !list.isEmpty else { return nil }
        return list.joined(separator: ", ")
    }
}

private struct InboxDetailView: View {
    let item: InboxItem
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(item.originalFilename)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    InboxStatusTag(label: item.status.displayName, color: item.status == .processed ? .green : .orange)
                    InboxStatusTag(label: item.source.displayName, color: .blue)
                    if item.cachedMetadata != nil {
                        InboxStatusTag(label: appLocalized("Metadata Cached"), color: .secondary)
                    }
                }

                HStack(spacing: 24) {
                    detailBlock("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let authors = item.cachedMetadata?.authors, !authors.isEmpty {
                    detailBlock("Authors", value: authors.joined(separator: ", "))
                }

                if let suggestedID = item.cachedMetadata?.suggestedID, !suggestedID.isEmpty {
                    detailBlock("Suggested ID", value: suggestedID)
                }

                if let abstract = item.cachedMetadata?.abstract, !abstract.isEmpty {
                    detailBlock("Abstract", value: abstract)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var title: String {
        let cachedTitle = item.cachedMetadata?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cachedTitle.isEmpty ? appLocalized("Untitled Inbox Item") : cachedTitle
    }

    @ViewBuilder
    private func detailBlock(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct InboxStatusTag: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name).fontWeight(.medium).lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "doc.text").font(.caption2)
                Text(String(
                    format: appLocalized("%lld paper"),
                    project.papers.count
                )).font(.caption)
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
            Text(appLocalized("Edit Project")).font(.title3).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 8) {
                Label(appLocalized("Project Name"), systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
                TextField(appLocalized("Project Name"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(appLocalized("Description (optional)"), systemImage: "text.alignleft")
                    .font(.caption).foregroundStyle(.secondary)
                TextField(appLocalized("What paper are you writing?"), text: $description)
                    .textFieldStyle(.roundedBorder)
            }
            projectPromptFields
            HStack {
                Spacer()
                Button(appLocalized("Cancel")) { isPresented = false }.keyboardShortcut(.escape)
                Button(appLocalized("Save")) {
                    var updated = project
                    updated.name = name.trimmingCharacters(in: .whitespaces)
                    updated.description = description.trimmingCharacters(in: .whitespaces)
                    updated.projectType = projectType
                    updated.generationPrompt = generationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? store.save(updated)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()
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
        .onChange(of: generationPrompt) { _, newValue in
            syncProjectTypeForPrompt(newValue)
        }
    }

    @ViewBuilder
    private var projectPromptFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(appLocalized("Project Type"), systemImage: "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(appLocalized("Project Type"), selection: $projectType) {
                ForEach(ProjectType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .onChange(of: projectType) { _, newValue in
                if let preset = newValue.presetPrompt {
                    generationPrompt = preset
                }
            }

            Label(appLocalized("Project Prompt"), systemImage: "text.badge.star")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $generationPrompt)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 140)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

            HStack {
                Text(projectType == .custom
                    ? appLocalized("Custom prompt for this project.")
                    : appLocalizedFormat("Prompt preset for %@.", projectType.displayName))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let preset = projectType.presetPrompt {
                    Button(appLocalized("Reset to Preset")) { generationPrompt = preset }
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
            Text(appLocalized("New Project"))
                .font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Label(appLocalized("Project Name"), systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
                TextField(appLocalized("e.g. Attention Mechanisms Survey"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(appLocalized("Description (optional)"), systemImage: "text.alignleft")
                    .font(.caption).foregroundStyle(.secondary)
                TextField(appLocalized("What paper are you writing?"), text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(appLocalized("Project Type"), systemImage: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(appLocalized("Project Type"), selection: $projectType) {
                    ForEach(ProjectType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .onChange(of: projectType) { _, newValue in
                    if let preset = newValue.presetPrompt {
                        generationPrompt = preset
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(appLocalized("Project Prompt"), systemImage: "text.badge.star")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $generationPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 140)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                HStack {
                    Text(projectType == .custom
                        ? appLocalized("Custom prompt for this project.")
                        : appLocalizedFormat("Prompt preset for %@.", projectType.displayName))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let preset = projectType.presetPrompt {
                        Button(appLocalized("Reset to Preset")) { generationPrompt = preset }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
            }

            HStack {
                Spacer()
                Button(appLocalized("Cancel")) { isPresented = false }
                    .keyboardShortcut(.escape)
                Button(appLocalized("Create")) { create() }
                    .buttonStyle(.borderedProminent)
                    .inactiveAwareProminentButtonForeground()
                    .keyboardShortcut(.return)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              generationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { focused = true }
        .onChange(of: generationPrompt) { _, newValue in
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
