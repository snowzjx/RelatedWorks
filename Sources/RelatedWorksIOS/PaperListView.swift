import SwiftUI

struct PaperListView: View {
    let projectID: UUID
    var autoRename: Bool = false
    @Binding var selectedPaper: PaperDestination?
    @EnvironmentObject var store: Store
    @State private var searchQuery = ""
    @State private var pendingDeleteOffsets: IndexSet?
    @State private var showRename = false
    @State private var editName = ""
    @State private var editDescription = ""

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
        List(filteredPapers, selection: $selectedPaper) { paper in
            let isSelected = selectedPaper?.paper.id == paper.id
            PaperRowView(paper: paper, isSelected: isSelected)
                .tag(PaperDestination(paper: paper, projectID: projectID))
                .swipeActions(edge: .trailing) {
                    Button {
                        pendingDeleteOffsets = IndexSet([filteredPapers.firstIndex(of: paper)!])
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
        }
        .navigationTitle(project?.name ?? "Papers")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchQuery, prompt: "Search papers…")
        .onAppear {
            if autoRename {
                editName = project?.name ?? ""
                editDescription = project?.description ?? ""
                showRename = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { 
                    guard let proj = project else { return }
                    editName = proj.name
                    editDescription = proj.description
                    showRename = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showRename) {
            NavigationStack {
                Form {
                    TextField("Name", text: $editName)
                    Section("Description") {
                        TextField("Description", text: $editDescription, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("Edit Project")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showRename = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard var proj = project,
                                  let idx = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
                            proj.name = editName.trimmingCharacters(in: .whitespaces)
                            proj.description = editDescription
                            store.projects[idx] = proj
                            try? store.save(proj)
                            showRename = false
                        }
                        .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  (editName == project?.name &&
                                   editDescription == project?.description))
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
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
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("@\(paper.id)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .white : .blue)
                if !paper.annotation.isEmpty {
                    Image(systemName: "note.text")
                        .font(.caption2)
                }
            }
            Text(paper.title)
                .font(.callout)
                .lineLimit(2)
            if let year = paper.year {
                let venueStr = paper.venue.map { "\($0) · " } ?? ""
                Text(venueStr + String(year))
                    .font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }
}
