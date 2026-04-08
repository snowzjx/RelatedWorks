import SwiftUI

struct PaperListView: View {
    let projectID: UUID
    @EnvironmentObject var store: Store
    @State private var searchQuery = ""
    @State private var pendingDeleteOffsets: IndexSet?

    var project: Project? { store.projects.first(where: { $0.id == projectID }) }

    var filteredPapers: [Paper] {
        guard let project else { return [] }
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
        List {
            ForEach(filteredPapers) { paper in
                NavigationLink(destination: PaperDetailView(paper: paper, projectID: projectID)) {
                    PaperRowView(paper: paper)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        pendingDeleteOffsets = IndexSet([filteredPapers.firstIndex(of: paper)!])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .navigationTitle(project?.name ?? "Papers")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchQuery, prompt: "Search papers…")
        .alert("Delete Paper", isPresented: Binding(
            get: { pendingDeleteOffsets != nil },
            set: { if !$0 { pendingDeleteOffsets = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    performDelete(at: offsets)
                    pendingDeleteOffsets = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteOffsets = nil }
        } message: {
            Text("This paper will be permanently removed from the project.")
        }
    }

    private func performDelete(at offsets: IndexSet) {
        guard var proj = project,
              let storeIdx = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        let papersToDelete = offsets.map { filteredPapers[$0] }
        for paper in papersToDelete {
            proj.papers.removeAll { $0.id == paper.id }
            proj.bibEntries.removeValue(forKey: paper.id)
            store.cleanupPDF(paperID: paper.id, projectID: projectID)
        }
        store.projects[storeIdx] = proj
        try? store.save(proj)
    }
}

struct PaperRowView: View {
    let paper: Paper

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("@\(paper.id)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                if !paper.annotation.isEmpty {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(paper.title)
                .font(.callout)
                .lineLimit(2)
            if let year = paper.year {
                let venueStr = paper.venue.map { "\($0) · " } ?? ""
                Text(venueStr + String(year))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
