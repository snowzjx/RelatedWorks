import SwiftUI
import UniformTypeIdentifiers

// MARK: - Unified Search Result

enum SearchResult: Identifiable, Hashable {
    case dblp(DBLPResult)
    case arxiv(ArxivResult)

    var id: String {
        switch self {
        case .dblp(let r): return "dblp:\(r.title)"
        case .arxiv(let r): return "arxiv:\(r.title)"
        }
    }
    var title: String {
        switch self { case .dblp(let r): return r.title; case .arxiv(let r): return r.title }
    }
    var authors: [String] {
        switch self { case .dblp(let r): return r.authors; case .arxiv(let r): return r.authors }
    }
    var year: Int? {
        switch self { case .dblp(let r): return r.year; case .arxiv(let r): return r.year }
    }
    var venue: String? {
        switch self { case .dblp(let r): return r.venue; case .arxiv: return "arXiv" }
    }
    var source: String {
        switch self { case .dblp: return "DBLP"; case .arxiv: return "arXiv" }
    }
    var dblpKey: String? {
        if case .dblp(let r) = self { return r.dblpKey }
        return nil
    }
    var abstract: String? {
        if case .arxiv(let r) = self { return r.abstract }
        return nil
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - AddPaperSheet

struct AddPaperSheet: View {
    @EnvironmentObject var store: Store
    @Binding var project: Project
    @Binding var isPresented: Bool
    var onAdded: (String) -> Void = { _ in }

    enum Phase { case idle, extracting, filling }
    enum SearchSource { case dblp, arxiv, manual }
    enum SourceMode: String, CaseIterable, Identifiable {
        case importPDF = "Import PDF"
        case inbox = "Inbox"

        var id: String { rawValue }
    }

    @State private var phase: Phase = .idle
    @State private var sourceMode: SourceMode = .importPDF
    @State private var semanticID = ""
    @State private var idConflict = false
    @State private var query = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchSource: SearchSource = .dblp
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedResult: SearchResult?
    @State private var pdfURL: URL?
    @State private var extractedMeta: ExtractedMetadata?
    @State private var selectedInboxItemID: UUID?
    @State private var removeInboxItemAfterAdding = true

    @State private var manualTitle = ""
    @State private var manualAuthors = ""
    @State private var manualYear = ""
    @State private var manualVenue = ""

    @FocusState private var idFocused: Bool

    var showManualInput: Bool { searchSource == .manual }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Paper").font(.title3).fontWeight(.semibold)

            if !store.inboxItems.isEmpty {
                Picker("Source", selection: $sourceMode) {
                    ForEach(SourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if sourceMode == .importPDF {
                PDFDropZone(pdfURL: $pdfURL, isExtracting: phase == .extracting) { url in
                    selectImportedPDF(url)
                }
            } else {
                inboxSection
            }

            if phase == .filling || phase == .idle {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Semantic ID", systemImage: "tag")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Transformer, BERT, GPT4", text: $semanticID)
                        .textFieldStyle(.roundedBorder)
                        .focused($idFocused)
                        .onChange(of: semanticID) { _ in
                            idConflict = project.paper(withID: semanticID.trimmingCharacters(in: .whitespaces)) != nil
                        }
                    if idConflict {
                        Label("This ID is already taken — choose a different one", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    } else {
                        Text("Short memorable name used for [@cross-references]")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                if !showManualInput {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Search \(searchSource == .dblp ? "DBLP" : "arXiv")", systemImage: "magnifyingglass")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if searchSource == .arxiv {
                                Text("DBLP returned no results").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        HStack {
                            LiquidGlassSearchField(prompt: "Paper title or keywords", text: $query)
                                .onChange(of: query) { _ in triggerSearch() }
                            if isSearching { ProgressView().scaleEffect(0.7).frame(width: 20) }
                        }

                        if !searchResults.isEmpty {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(searchResults) { result in
                                        UnifiedResultRow(result: result, isSelected: selectedResult == result)
                                            .onTapGesture { selectedResult = result }
                                        Divider()
                                    }
                                }
                            }
                            .frame(height: 180)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                        } else if !query.isEmpty && !isSearching {
                            HStack {
                                Text("No results from \(searchSource == .dblp ? "DBLP" : "arXiv")")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button(searchSource == .dblp ? "Try arXiv" : "Enter manually") {
                                    if searchSource == .dblp {
                                        searchSource = .arxiv
                                        triggerSearch()
                                    } else {
                                        searchSource = .manual
                                        manualTitle = query
                                    }
                                }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Manual Entry", systemImage: "pencil")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Try search again") {
                                searchSource = .dblp
                                searchResults = []
                                triggerSearch()
                            }
                            .font(.caption2).buttonStyle(.borderless).foregroundStyle(.blue)
                        }
                        TextField("Title *", text: $manualTitle).textFieldStyle(.roundedBorder)
                        TextField("Authors (comma separated)", text: $manualAuthors).textFieldStyle(.roundedBorder)
                        HStack(spacing: 8) {
                            TextField("Year", text: $manualYear).textFieldStyle(.roundedBorder).frame(width: 80)
                            TextField("Venue / Conference", text: $manualVenue).textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if let r = selectedResult {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.caption).fontWeight(.medium).lineLimit(1)
                            Text("\(r.authors.prefix(2).joined(separator: ", ")) · \(r.venue ?? "") · \(r.year.map(String.init) ?? "") · \(r.source)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { selectedResult = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.escape)
                Button("Add Paper") { addPaper() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(isAddDisabled)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            if store.inboxItems.isEmpty {
                sourceMode = .importPDF
            } else if pdfURL == nil && selectedInboxItemID == nil {
                sourceMode = .inbox
                selectedInboxItemID = store.inboxItems.first?.id
                if let item = store.inboxItems.first {
                    // Let the sheet appear first before running inbox prefill work.
                    Task { @MainActor in
                        await Task.yield()
                        guard isPresented,
                              sourceMode == .inbox,
                              selectedInboxItemID == item.id else { return }
                        selectInboxItem(item)
                    }
                }
            }
            idFocused = true
        }
        .onChange(of: sourceMode) { mode in
            if mode == .importPDF {
                selectedInboxItemID = nil
                removeInboxItemAfterAdding = true
                resetEditorState(keepingPDF: false)
            } else if let selectedInboxItemID,
                      let item = store.inboxItems.first(where: { $0.id == selectedInboxItemID }) {
                selectInboxItem(item)
            } else if let first = store.inboxItems.first {
                selectedInboxItemID = first.id
                selectInboxItem(first)
            } else {
                resetEditorState(keepingPDF: false)
            }
        }
        .onChange(of: selectedInboxItemID) { itemID in
            guard sourceMode == .inbox else { return }
            guard let itemID,
                  let item = store.inboxItems.first(where: { $0.id == itemID }) else {
                resetEditorState(keepingPDF: false)
                return
            }
            selectInboxItem(item)
        }
    }

    private var isAddDisabled: Bool {
        let id = semanticID.trimmingCharacters(in: .whitespaces)
        if id.isEmpty || phase == .extracting || idConflict { return true }
        if sourceMode == .inbox && selectedInboxItemID == nil { return true }
        if showManualInput && manualTitle.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Inbox", systemImage: "tray.full")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.inboxItems.count) item\(store.inboxItems.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if store.inboxItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Inbox is Empty")
                        .font(.headline)
                    Text("Shared PDFs will appear here when they sync in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                List(store.inboxItems, selection: $selectedInboxItemID) { item in
                    InboxItemRow(item: item, isSelected: selectedInboxItemID == item.id)
                        .tag(item.id)
                }
                .frame(height: 180)
                .listStyle(.plain)

                Toggle("Remove from Inbox after adding", isOn: $removeInboxItemAfterAdding)
                    .font(.caption)
            }
        }
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

    private func resetEditorState(keepingPDF: Bool, clearIdentityFields: Bool = true) {
        phase = .idle
        if clearIdentityFields {
            semanticID = ""
            idConflict = false
            query = ""
        } else {
            idConflict = false
        }
        searchResults = []
        searchSource = .dblp
        isSearching = false
        selectedResult = nil
        extractedMeta = nil
        manualTitle = ""
        manualAuthors = ""
        manualYear = ""
        manualVenue = ""
        if !keepingPDF {
            pdfURL = nil
        }
    }

    private func applyMetadataToEditor(
        pdfURL: URL,
        title: String,
        authors: [String],
        abstract: String?,
        suggestedID: String
    ) {
        resetEditorState(keepingPDF: true, clearIdentityFields: false)
        self.pdfURL = pdfURL
        extractedMeta = ExtractedMetadata(
            title: title,
            authors: authors,
            abstract: abstract,
            suggestedID: suggestedID.isEmpty ? "Paper" : suggestedID
        )

        semanticID = suggestedID.isEmpty ? "Paper" : suggestedID
        idConflict = project.paper(withID: semanticID.trimmingCharacters(in: .whitespaces)) != nil
        query = title

        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manualTitle = title
        }
        if !authors.isEmpty {
            manualAuthors = authors.joined(separator: ", ")
        }

        phase = .filling
        triggerSearch()
    }

    private func selectImportedPDF(_ url: URL) {
        phase = .extracting
        Task {
            let takenIDs = Set(project.papers.map { $0.id.lowercased() })
            let meta = await PDFImporter.extractMetadata(from: url, takenIDs: takenIDs)
            await MainActor.run {
                applyMetadataToEditor(
                    pdfURL: url,
                    title: meta.title,
                    authors: meta.authors,
                    abstract: meta.abstract,
                    suggestedID: meta.suggestedID
                )
            }
        }
    }

    private func selectInboxItem(_ item: InboxItem) {
        let url = store.inboxPDFURL(for: item.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            resetEditorState(keepingPDF: false)
            return
        }

        let cached = item.cachedMetadata
        applyMetadataToEditor(
            pdfURL: url,
            title: cached?.title ?? "",
            authors: cached?.authors ?? [],
            abstract: cached?.abstract,
            suggestedID: cached?.suggestedID ?? "Paper"
        )
    }

    private func triggerSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }

            var results: [SearchResult] = []
            var defaultSelection: SearchResult?
            if searchSource == .dblp {
                let dblp = (try? await DBLPService.search(query: q)) ?? []
                results = dblp.map { .dblp($0) }
                defaultSelection = results.first
                if results.isEmpty {
                    let arxiv = (try? await ArxivService.search(query: q)) ?? []
                    results = arxiv.map { .arxiv($0) }
                }
            } else if searchSource == .arxiv {
                let arxiv = (try? await ArxivService.search(query: q)) ?? []
                results = arxiv.map { .arxiv($0) }
            }

            await MainActor.run {
                searchResults = results
                selectedResult = defaultSelection
                isSearching = false
            }
        }
    }

    private func addPaper() {
        let id = semanticID.trimmingCharacters(in: .whitespaces)
        var paper: Paper

        if let r = selectedResult {
            paper = Paper(id: id, title: r.title, authors: r.authors, year: r.year, venue: r.venue)
            paper.dblpKey = r.dblpKey
            paper.abstract = r.abstract ?? extractedMeta?.abstract
        } else if showManualInput {
            let authors = manualAuthors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            paper = Paper(
                id: id,
                title: manualTitle.trimmingCharacters(in: .whitespaces),
                authors: authors,
                year: Int(manualYear),
                venue: manualVenue.isEmpty ? nil : manualVenue
            )
            paper.abstract = extractedMeta?.abstract
        } else {
            let meta = extractedMeta
            paper = Paper(
                id: id,
                title: meta?.title.isEmpty == false ? meta!.title : (query.isEmpty ? id : query),
                authors: meta?.authors ?? []
            )
            paper.abstract = meta?.abstract
        }

        if let url = pdfURL,
           (try? store.registerPDF(at: url, forID: id, projectID: project.id)) != nil {
            paper.hasPDF = true
        }

        project.addPaper(paper)
        try? store.save(project)

        if let selectedInboxItemID,
           let inboxItem = store.inboxItems.first(where: { $0.id == selectedInboxItemID }) {
            if removeInboxItemAfterAdding {
                try? store.deleteInboxItem(inboxItem)
            } else {
                try? store.updateInboxItemStatus(inboxItem.id, status: .processed)
            }
        }

        onAdded(id)
        isPresented = false

        let dblpKey = selectedResult?.dblpKey
        let projectID = project.id
        Task {
            if let key = dblpKey, let bib = await DBLPService.fetchBibtex(dblpKey: key) {
                let normalized = bib.replacingOccurrences(
                    of: #"@\w+\{[^,]+"#,
                    with: "@article{\(id)",
                    options: .regularExpression
                )
                await MainActor.run {
                    if let idx = store.projects.firstIndex(where: { $0.id == projectID }) {
                        store.projects[idx].bibEntries[id] = normalized
                        try? store.save(store.projects[idx])
                    }
                }
            } else {
                let generated = generateBibtex(for: paper)
                await MainActor.run {
                    if let idx = store.projects.firstIndex(where: { $0.id == projectID }) {
                        store.projects[idx].bibEntries[id] = generated
                        try? store.save(store.projects[idx])
                    }
                }
            }
        }
    }
}

// MARK: - PDF Drop Zone

struct PDFDropZone: View {
    @Binding var pdfURL: URL?
    let isExtracting: Bool
    let onDrop: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.blue : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 2, dash: [6]))
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(isTargeted ? Color.blue.opacity(0.05) : Color.clear))

            if isExtracting {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extracting metadata with AI…")
                        Text("Using \(AppSettings.shared.activeExtractionModelName) via \(AppSettings.shared.extractionBackend.rawValue)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
            } else if !AppSettings.shared.isExtractionConfigured {
                Label("No AI extraction model configured — open Settings to configure one. PDF metadata will not be extracted automatically.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let url = pdfURL {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill").foregroundStyle(.red)
                    Text(url.lastPathComponent).lineLimit(1)
                    Spacer()
                    Button { pdfURL = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.secondary)
                    Text("Drop PDF here or click to browse")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 80)
        .contentShape(Rectangle())
        .onTapGesture { browse() }
        .onDrop(of: [UTType.pdf], isTargeted: $isTargeted) { providers in
            providers.first?.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                guard let url else { return }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: copy)
                DispatchQueue.main.async {
                    pdfURL = copy
                    onDrop(copy)
                }
            }
            return true
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pdfURL = url
            onDrop(url)
        }
    }
}

private struct InboxItemRow: View {
    let item: InboxItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.status == .processed ? "tray.full.fill" : "tray")
                .foregroundStyle(item.status == .processed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.callout)
                    .lineLimit(2)
                Text(itemSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var displayTitle: String {
        let title = item.cachedMetadata?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? item.originalFilename : title
    }

    private var itemSubtitle: String {
        let authors = item.cachedMetadata?.authors.prefix(2).joined(separator: ", ")
        let prefix = (authors?.isEmpty == false) ? "\(authors!) · " : ""
        return "\(prefix)\(item.source.displayName) · \(item.status.rawValue)"
    }
}

// MARK: - Result Row

struct UnifiedResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title).font(.callout).lineLimit(2)
                Text("\(result.authors.prefix(2).joined(separator: ", ")) · \(result.venue ?? "?") · \(result.year.map(String.init) ?? "?")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(result.source).font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            if isSelected { Image(systemName: "checkmark").foregroundStyle(.blue) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}

extension DBLPResult: Hashable {
    public static func == (lhs: DBLPResult, rhs: DBLPResult) -> Bool { lhs.title == rhs.title }
    public func hash(into hasher: inout Hasher) { hasher.combine(title) }
}

extension ArxivResult: Hashable {
    public static func == (lhs: ArxivResult, rhs: ArxivResult) -> Bool { lhs.title == rhs.title }
    public func hash(into hasher: inout Hasher) { hasher.combine(title) }
}
