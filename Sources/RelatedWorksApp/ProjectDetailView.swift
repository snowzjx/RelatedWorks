import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject var store: Store
    @Binding var project: Project
    @Binding var externalPaperID: String?
    @State private var selectedPaperID: String?
    @State private var showingAddPaper = false
    @State private var editingPaper: Paper?

    var selectedIndex: Int? {
        project.papers.firstIndex(where: { $0.id == selectedPaperID })
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: paper list
            VStack(spacing: 0) {
                List(project.papers, selection: $selectedPaperID) { paper in
                    PaperRow(paper: paper)
                        .tag(paper.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .contextMenu {
                            Button("Edit Metadata") { editingPaper = paper }
                            Divider()
                            Button(role: .destructive) { deletePaper(paper) } label: {
                                Label("Remove Paper", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.plain)

                Divider()

                // Larger add button
                Button(action: { showingAddPaper = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Add Paper")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Add Paper (⌘⇧A)")
            }
            .frame(width: 260)

            Divider()

            // Right: paper detail
            if let idx = selectedIndex {
                PaperDetailView(paper: $project.papers[idx], project: project,
                                onSelectPaper: { id in selectedPaperID = id })
                    .id(project.papers[idx].id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Paper Selected",
                    message: "Add a paper or select one from the list."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(project.name)
        .navigationSubtitle(project.description.isEmpty ? "" : project.description)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                GenerateButton(project: $project)
            }
        }
        .sheet(isPresented: $showingAddPaper) {
            AddPaperSheet(project: $project, isPresented: $showingAddPaper) { newID in
                selectedPaperID = newID
            }
        }
        .sheet(item: $editingPaper) { paper in
            EditMetadataSheet(paper: paper, project: $project)
        }
        .onChange(of: externalPaperID) { id in
            if let id { selectedPaperID = id; externalPaperID = nil }
        }
    }

    private func deletePaper(_ paper: Paper) {
        if selectedPaperID == paper.id { selectedPaperID = nil }
        project.papers.removeAll { $0.id == paper.id }
        project.bibEntries.removeValue(forKey: paper.id)
        try? store.save(project)
        if let path = paper.pdfPath {
            store.cleanupPDFIfUnused(paperID: paper.id, pdfPath: path, excludingProjectID: project.id)
        }
    }
}

struct PaperRow: View {
    let paper: Paper
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("@\(paper.id)")
                    .font(.caption).fontWeight(.medium).foregroundStyle(.blue)
                if !paper.annotation.isEmpty {
                    Image(systemName: "note.text").font(.caption2).foregroundStyle(.secondary)
                }
                if paper.pdfPath != nil {
                    Image(systemName: "doc.fill").font(.caption2).foregroundStyle(.red.opacity(0.7))
                }
            }
            Text(paper.title).font(.callout).lineLimit(2)
            if let year = paper.year {
                let venuePrefix = paper.venue.map { "\($0) · " } ?? ""
                Text(venuePrefix + String(year))
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
                Text("Edit Metadata").font(.title3).fontWeight(.semibold)
                Spacer()
                Tag("@\(paper.id)", color: .blue)
                Text("ID cannot be changed").font(.caption2).foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 12) {
                field("Title", text: $title)
                field("Authors (comma separated)", text: $authors)
                HStack(spacing: 8) {
                    field("Year", text: $year).frame(width: 100)
                    field("Venue / Conference", text: $venue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abstract").font(.caption).foregroundStyle(.secondary)
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
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>) -> some View {
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
