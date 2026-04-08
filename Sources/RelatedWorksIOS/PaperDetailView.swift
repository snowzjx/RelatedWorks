import SwiftUI
import SwiftUI
import PDFKit

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct PDFViewer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

struct PaperDetailView: View {
    let paper: Paper
    let projectID: UUID
    @EnvironmentObject var store: Store
    @State private var annotation: String
    @State private var pdfURL: URL?

    var project: Project? { store.projects.first(where: { $0.id == projectID }) }

    init(paper: Paper, projectID: UUID) {
        self.paper = paper
        self.projectID = projectID
        _annotation = State(initialValue: paper.annotation)
    }

    var crossRefs: [Paper] { project?.crossReferences(for: paper.id) ?? [] }
    var otherPaperIDs: [String] { project?.papers.filter { $0.id != paper.id }.map(\.id) ?? [] }

    /// Resolves the PDF path dynamically — handles cases where the stored absolute path
    /// is stale (e.g. after simulator reset) by looking up the file in the current pdfs dir.
    var resolvedPDFURL: URL? {
        guard let path = paper.pdfPath else { return nil }
        let stored = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: stored.path) { return stored }
        // Fall back: look in current pdfs dir by paper ID
        let fallback = store.pdfsDir(for: projectID).appendingPathComponent("\(paper.id).pdf")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Header card
                VStack(alignment: .leading, spacing: 8) {
                    Text(paper.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)

                    if !paper.authors.isEmpty {
                        Text(paper.authors.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            TagChip("@\(paper.id)", color: .blue)
                            if let venue = paper.venue { TagChip(venue) }
                            if let year = paper.year { TagChip(String(year)) }
                            if let key = paper.dblpKey {
                                Link(destination: URL(string: "https://dblp.org/rec/\(key)")!) {
                                    TagChip("DBLP ↗", color: .green)
                                }
                            }
                            if paper.pdfPath != nil {
                                Button {
                                    pdfURL = resolvedPDFURL
                                } label: {
                                    TagChip("PDF ↗", color: .red)
                                }
                                .buttonStyle(.plain)
                                .opacity(resolvedPDFURL != nil ? 1 : 0.4)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 16))

                // Abstract
                if let abstract = paper.abstract, !abstract.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Abstract", systemImage: "text.quote")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text(abstract)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))
                }

                // Cross-references
                if !crossRefs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Cross-references", systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        ForEach(crossRefs) { ref in
                            NavigationLink(destination: PaperDetailView(paper: ref, projectID: projectID)) {
                                HStack(spacing: 8) {
                                    TagChip("@\(ref.id)", color: .blue)
                                    Text(ref.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))
                }

                // Annotation editor
                VStack(alignment: .leading, spacing: 8) {
                    Label("Annotation", systemImage: "note.text")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    AnnotationEditor(text: $annotation, paperIDs: otherPaperIDs)
                        .frame(minHeight: 180)

                    Text("Type @ to cross-reference other papers")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .glassEffect(in: .rect(cornerRadius: 16))
            }
            .padding()
        }
        .navigationTitle(paper.id)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pdfURL) { url in
            NavigationStack {
                PDFViewer(url: url)
                    .ignoresSafeArea()
                    .navigationTitle(paper.id)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { pdfURL = nil }
                        }
                    }
            }
        }
        .onChange(of: annotation) { _, newValue in
            saveAnnotation(newValue)
        }
    }

    private func saveAnnotation(_ newValue: String) {
        guard var proj = store.projects.first(where: { $0.id == projectID }),
              let idx = proj.papers.firstIndex(where: { $0.id == paper.id }) else { return }
        proj.papers[idx].annotation = newValue
        try? store.save(proj)
    }
}

struct TagChip: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
