import SwiftUI

/// Returns an AttributedString with all case-insensitive occurrences of `query` highlighted.
func highlighted(_ string: String, query: String) -> AttributedString {
    var result = AttributedString(string)
    let q = query.lowercased()
    guard !q.isEmpty else { return result }
    var searchStart = string.startIndex
    while searchStart < string.endIndex,
          let range = string.range(of: q, options: .caseInsensitive, range: searchStart ..< string.endIndex) {
        if let attrRange = Range(range, in: result) {
            result[attrRange].backgroundColor = .yellow.opacity(0.5)
        }
        searchStart = range.upperBound
    }
    return result
}

struct PaperDetailView: View {
    @Binding var paper: Paper
    let project: Project
    var onSelectPaper: (String) -> Void = { _ in }
    var highlight: String = ""
    var onClearSearch: (() -> Void)? = nil
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @State private var copiedLink = false

    var crossRefs: [Paper] { project.crossReferences(for: paper.id) }
    var otherPaperIDs: [String] { project.papers.filter { $0.id != paper.id }.map(\.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text(highlighted(paper.title, query: highlight))
                        .font(.system(size: settings.fontSize + 2)).fontWeight(.semibold)
                        .textSelection(.enabled)

                    if !paper.authors.isEmpty {
                        Text(highlighted(paper.authors.joined(separator: ", "), query: highlight))
                            .font(.system(size: settings.fontSize - 1)).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 6) {
                        Tag("@\(paper.id)", color: .blue, highlight: highlight)
                        if let venue = paper.venue { Tag(venue, highlight: highlight) }
                        if let year = paper.year { Tag(String(year), highlight: highlight) }
                        if let key = paper.dblpKey {
                            Link(destination: URL(string: "https://dblp.org/rec/\(key)")!) {
                                Tag("DBLP ↗", color: .green)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        if let path = paper.pdfPath {
                            Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: {
                                Label("Open PDF", systemImage: "doc.fill")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        } else {
                            Button(action: attachPDF) {
                                Label("Attach PDF", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                        Button(action: copyDeepLink) {
                            Label(copiedLink ? "Copied!" : "Copy Link",
                                  systemImage: copiedLink ? "checkmark" : "link")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(20)

                Divider()

                // ── Abstract ─────────────────────────────────────────
                if let abstract = paper.abstract, !abstract.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Abstract", systemImage: "text.quote")
                            .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                        Text(highlighted(abstract, query: highlight))
                            .font(.system(size: settings.fontSize - 1)).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                    Divider()
                }

                // ── Cross-references ─────────────────────────────────
                if !crossRefs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Cross-references", systemImage: "arrow.triangle.branch")
                            .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(crossRefs) { ref in
                                Button(action: { onSelectPaper(ref.id) }) {
                                    HStack(spacing: 6) {
                                        Tag("@\(ref.id)", color: .blue)
                                        Text(ref.title).font(.caption).lineLimit(1)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    Divider()
                }

                // ── Annotation ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Label("Annotation", systemImage: "note.text")
                        .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)

                    if highlight.isEmpty {
                        AnnotationEditor(text: $paper.annotation, paperIDs: otherPaperIDs)
                            .frame(minHeight: 200)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                    } else {
                        Text(highlighted(paper.annotation, query: highlight))
                            .font(.system(size: settings.fontSize - 1))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    onClearSearch?()
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .font(.caption)
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(.regularMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .help("Clear search to edit annotation")
                            }
                    }

                    Text("Tip: type @ to cross-reference other papers in this project")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(20)
            }
        }
        .onChange(of: paper.annotation) { _ in
            try? store.save(project)
        }
    }

    private func attachPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let stored = try? store.registerPDF(at: url, forID: paper.id, projectID: project.id) {
            paper.pdfPath = stored
            try? store.save(project)
        }
    }

    private func copyDeepLink() {
        let url = DeepLink.url(for: paper, in: project)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copiedLink = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { copiedLink = false }
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var highlight: String = ""
    init(_ text: String, color: Color = .secondary, highlight: String = "") {
        self.text = text; self.color = color; self.highlight = highlight
    }
    var body: some View {
        Text(highlighted(text, query: highlight))
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
