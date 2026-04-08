import SwiftUI
import UniformTypeIdentifiers

struct ProjectListView: View {
    @EnvironmentObject var store: Store
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingDeleteOffsets: IndexSet?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.projects) { project in
                    NavigationLink(destination: PaperListView(projectID: project.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.headline)
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(project.papers.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !project.description.isEmpty {
                                Text(project.description)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
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
