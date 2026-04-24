import SwiftUI
import UniformTypeIdentifiers

struct LiquidGlassSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(LiquidGlassContainer())
    }
}

struct LiquidGlassContainer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: 14))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.18))
                }
        }
    }
}

struct ProjectDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @Binding var project: Project
    @Binding var selectedPaperID: String?
    @State private var showingAddPaper = false
    @State private var importedPDFURL: URL?
    @State private var isPDFDropTargeted = false
    @State private var editingPaper: Paper?
    @State private var searchQuery = ""

    var selectedIndex: Int? {
        project.papers.firstIndex(where: { $0.id == selectedPaperID })
    }

    var filteredPapers: [Paper] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return project.papers }
        return project.papers.filter { p in
            p.id.lowercased().contains(q) ||
            p.title.lowercased().contains(q) ||
            p.authors.joined(separator: " ").lowercased().contains(q) ||
            (p.venue?.lowercased().contains(q) ?? false) ||
            (p.year.map { String($0) }?.contains(q) ?? false) ||
            (p.abstract?.lowercased().contains(q) ?? false) ||
            p.annotation.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left: paper list
                VStack(spacing: 0) {
                    List(filteredPapers, selection: $selectedPaperID) { paper in
                        PaperRow(paper: paper, highlight: searchQuery.trimmingCharacters(in: .whitespaces))
                            .tag(paper.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .contextMenu {
                                Button(appLocalized("Edit Metadata")) { editingPaper = paper }
                                Divider()
                                Button(role: .destructive) { deletePaper(paper) } label: {
                                    Label(appLocalized("Remove Paper"), systemImage: "trash")
                                }
                            }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if isPDFDropTargeted {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.blue.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .padding(8)
                        }
                    }
                    .onDrop(of: [UTType.pdf], isTargeted: $isPDFDropTargeted) { providers in
                        handlePDFDrop(providers)
                    }

                    Divider()

                    // Larger add button
                    Button(action: { showingAddPaper = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text(appLocalized("Add Paper"))
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .help(appLocalized("Add Paper (⌘⇧A)"))
                    .anchorPreference(key: FirstLaunchAnchorPreferenceKey.self, value: .bounds) { [.addPaper: $0] }
                }
                .frame(width: 260)

                Divider()

                // Right: paper detail
                if let idx = selectedIndex {
                    PaperDetailView(paper: $project.papers[idx], project: $project,
                                    onSelectPaper: { id in selectedPaperID = id },
                                    highlight: searchQuery.trimmingCharacters(in: .whitespaces),
                                    onClearSearch: { searchQuery = "" })
                        .id(project.papers[idx].id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: LocalizedStringKey(appLocalized("No Paper Selected")),
                        message: LocalizedStringKey(appLocalized("Add a paper or select one from the list."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(project.name)
        .navigationSubtitle(projectSubtitle)
        .searchable(text: $searchQuery, prompt: appLocalized("Search papers…"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: AppWindowID.citationGraph, value: project.id)
                } label: {
                    Label(appLocalized("Citation Graph"), systemImage: "point.3.connected.trianglepath.dotted")
                }
                .help(appLocalized("Show citation graph"))
            }
            ToolbarItem(placement: .primaryAction) {
                GenerateButton(project: $project)
            }
        }
        .sheet(isPresented: $showingAddPaper) {
            AddPaperSheet(project: $project, isPresented: $showingAddPaper, initialPDFURL: importedPDFURL) { newID in
                selectedPaperID = newID
            }
            .onDisappear {
                importedPDFURL = nil
            }
        }
        .sheet(item: $editingPaper) { paper in
            EditMetadataSheet(paper: paper, project: $project)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addPaper)) { _ in
            showingAddPaper = true
        }
    }

    private func deletePaper(_ paper: Paper) {
        let alert = NSAlert()
        alert.messageText = appLocalizedFormat("Remove \"%@\"?", paper.title)
        alert.informativeText = appLocalized("This will remove the paper and its PDF from this project.")
        alert.addButton(withTitle: appLocalized("Remove"))
        alert.addButton(withTitle: appLocalized("Cancel"))
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if selectedPaperID == paper.id { selectedPaperID = nil }
        project.papers.removeAll { $0.id == paper.id }
        project.bibEntries.removeValue(forKey: paper.id)
        try? store.save(project)
        store.cleanupPDF(paperID: paper.id, projectID: project.id)
    }

    private func handlePDFDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) else {
            return false
        }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
            guard let url else { return }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: url, to: copy)
            DispatchQueue.main.async {
                importedPDFURL = copy
                showingAddPaper = true
            }
        }
        return true
    }

    private var projectSubtitle: String {
        let trimmedDescription = project.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDescription.isEmpty {
            return project.projectType.displayName
        }
        return "\(project.projectType.displayName) · \(trimmedDescription)"
    }
}

struct PaperRow: View {
    let paper: Paper
    var highlight: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(highlighted("@\(paper.id)", query: highlight))
                    .font(.caption).fontWeight(.medium).foregroundStyle(.blue)
                if !paper.annotation.isEmpty {
                    Image(systemName: "note.text").font(.caption2).foregroundStyle(.secondary)
                }
                if paper.hasPDF {
                    Image(systemName: "doc.fill").font(.caption2).foregroundStyle(.red.opacity(0.7))
                }
            }
            Text(highlighted(paper.title, query: highlight)).font(.callout).lineLimit(2)
            if let year = paper.year {
                let venuePrefix = paper.venue.map { "\($0) · " } ?? ""
                Text(highlighted(venuePrefix + String(year), query: highlight))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Edit Metadata Sheet

struct EditMetadataSheet: View {
    @EnvironmentObject var store: Store
    let paper: Paper
    @Binding var project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var authors: String
    @State private var year: String
    @State private var venue: String
    @State private var abstract: String

    init(paper: Paper, project: Binding<Project>) {
        self.paper = paper
        self._project = project
        _title = State(initialValue: paper.title)
        _authors = State(initialValue: paper.authors.joined(separator: ", "))
        _year = State(initialValue: paper.year.map(String.init) ?? "")
        _venue = State(initialValue: paper.venue ?? "")
        _abstract = State(initialValue: paper.abstract ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(appLocalized("Edit Metadata")).font(.title3).fontWeight(.semibold)
                Spacer()
                Tag("@\(paper.id)", color: .blue)
                Text(appLocalized("ID cannot be changed")).font(.caption2).foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 12) {
                field(LocalizedStringKey(appLocalized("Title")), text: $title)
                field(LocalizedStringKey(appLocalized("Authors (comma separated)")), text: $authors)
                HStack(spacing: 8) {
                    field(LocalizedStringKey(appLocalized("Year")), text: $year).frame(width: 100)
                    field(LocalizedStringKey(appLocalized("Venue / Conference")), text: $venue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLocalized("Abstract")).font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $abstract)
                        .font(.callout)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                }
            }

            HStack {
                Spacer()
                Button(appLocalized("Cancel")) { dismiss() }.keyboardShortcut(.escape)
                Button(appLocalized("Save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .inactiveAwareProminentButtonForeground()
                    .keyboardShortcut(.return)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    @ViewBuilder
    private func field(_ label: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        guard let idx = project.papers.firstIndex(where: { $0.id == paper.id }) else { return }
        project.papers[idx].title = title.trimmingCharacters(in: .whitespaces)
        project.papers[idx].authors = authors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        project.papers[idx].year = Int(year.trimmingCharacters(in: .whitespaces))
        project.papers[idx].venue = venue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : venue.trimmingCharacters(in: .whitespaces)
        project.papers[idx].abstract = abstract.trimmingCharacters(in: .whitespaces).isEmpty ? nil : abstract.trimmingCharacters(in: .whitespaces)

        // Regenerate local bib only if no DBLP key (i.e. bib was generated locally)
        let updated = project.papers[idx]
        if updated.dblpKey == nil {
            project.bibEntries[paper.id] = generateBibtex(for: updated)
        }

        try? store.save(project)
        dismiss()
    }

    private func generateBibtex(for paper: Paper) -> String {
        let type = paper.venue?.lowercased().contains("arxiv") == true ? "misc" : "inproceedings"
        var lines = ["@\(type){\(paper.id),"]
        lines.append("  title     = {\(paper.title)},")
        if !paper.authors.isEmpty {
            lines.append("  author    = {\(paper.authors.joined(separator: " and "))},")
        }
        if let year = paper.year { lines.append("  year      = {\(year)},") }
        if let venue = paper.venue { lines.append("  booktitle = {\(venue)},") }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

struct ProjectTypeBadge: View {
    let type: ProjectType

    var body: some View {
        Text(type.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}
