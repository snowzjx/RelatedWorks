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

    @State private var phase: Phase = .idle
    @State private var semanticID = ""
    @State private var idConflict = false
    @State private var pdfAlreadyInProject = false
    @State private var pdfExistsElsewhere = false
    @State private var query = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchSource: SearchSource = .dblp
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedResult: SearchResult?
    @State private var pdfURL: URL?
    @State private var extractedMeta: ExtractedMetadata?

    // Manual input fields (shown when both DBLP and arXiv return nothing)
    @State private var manualTitle = ""
    @State private var manualAuthors = ""
    @State private var manualYear = ""
    @State private var manualVenue = ""

    @FocusState private var idFocused: Bool

    var showManualInput: Bool { searchSource == .manual }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Paper").font(.title3).fontWeight(.semibold)

            // ── PDF Drop Zone ────────────────────────────────────────
            PDFDropZone(pdfURL: $pdfURL, isExtracting: phase == .extracting) { url in
                importPDF(url)
            }

            if phase == .filling || phase == .idle {
                // ── Semantic ID ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Label("Semantic ID", systemImage: "tag")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Transformer, BERT, GPT4", text: $semanticID)
                        .textFieldStyle(.roundedBorder)
                        .focused($idFocused)
                        .disabled(pdfExistsElsewhere)
                        .onChange(of: semanticID) { _ in
                            idConflict = store.isIDTaken(semanticID.trimmingCharacters(in: .whitespaces))
                        }
                    if idConflict {
                        Label("This ID is already taken — choose a different one", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    } else if pdfAlreadyInProject {
                        Label("This PDF is already in this project", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    } else if pdfExistsElsewhere {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                            Text("This PDF is already in the system as \"\(semanticID)\" — it will be shared, not duplicated.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Short memorable name used for [@cross-references]")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                // ── Search ───────────────────────────────────────────
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
                    .disabled(pdfExistsElsewhere)
                } else {
                    // ── Manual Input ─────────────────────────────────
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
                    .disabled(pdfExistsElsewhere)
                }

                // ── Selected result preview ───────────────────────────
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
                        }.buttonStyle(.plain)
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
        .onAppear { idFocused = true }
    }

    private var isAddDisabled: Bool {
        let id = semanticID.trimmingCharacters(in: .whitespaces)
        if id.isEmpty || phase == .extracting || idConflict || pdfAlreadyInProject { return true }
        if showManualInput && manualTitle.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }

    // MARK: - Actions

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

    private func importPDF(_ url: URL) {
        pdfAlreadyInProject = false
        pdfExistsElsewhere = false
        phase = .extracting
        Task {
            let takenIDs = store.allPaperIDs
            let meta = await PDFImporter.extractMetadata(from: url, takenIDs: takenIDs)
            await MainActor.run {
                extractedMeta = meta
                if let existingID = store.existingID(forPDFAt: url, title: meta.title) {
                    if project.papers.contains(where: { $0.id.lowercased() == existingID.lowercased() }) {
                        pdfAlreadyInProject = true
                        semanticID = existingID
                    } else {
                        pdfExistsElsewhere = true
                        semanticID = existingID
                        if let existingPaper = store.projects.flatMap({ $0.papers }).first(where: { $0.id.lowercased() == existingID.lowercased() }) {
                            // Pre-fill metadata from the existing entry
                            selectedResult = nil
                            manualTitle = existingPaper.title
                            manualAuthors = existingPaper.authors.joined(separator: ", ")
                            manualYear = existingPaper.year.map(String.init) ?? ""
                            manualVenue = existingPaper.venue ?? ""
                            searchSource = .manual
                        }
                    }
                } else {
                    if semanticID.isEmpty { semanticID = meta.suggestedID }
                    idConflict = store.isIDTaken(semanticID.trimmingCharacters(in: .whitespaces))
                    if query.isEmpty { query = meta.title }
                }
                phase = .filling
                triggerSearch()
            }
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }

            var results: [SearchResult] = []
            if searchSource == .dblp {
                let dblp = (try? await DBLPService.search(query: q)) ?? []
                results = dblp.map { .dblp($0) }
                // Auto-fallback to arXiv if DBLP empty (without changing searchSource to avoid re-trigger)
                if results.isEmpty {
                    let arxiv = (try? await ArxivService.search(query: q)) ?? []
                    results = arxiv.map { .arxiv($0) }
                }
            } else if searchSource == .arxiv {
                let arxiv = (try? await ArxivService.search(query: q)) ?? []
                results = arxiv.map { .arxiv($0) }
            }

            await MainActor.run { searchResults = results; isSearching = false }
        }
    }

    private func addPaper() {
        let id = semanticID.trimmingCharacters(in: .whitespaces)
        var paper: Paper

        if let r = selectedResult {
            paper = Paper(id: id, title: r.title, authors: r.authors, year: r.year, venue: r.venue)
            paper.dblpKey = r.dblpKey
            // arXiv results have abstract; DBLP doesn't — prefer PDF extraction, then fetch from arXiv
            paper.abstract = r.abstract ?? extractedMeta?.abstract
        } else if showManualInput {
            let authors = manualAuthors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            paper = Paper(id: id, title: manualTitle.trimmingCharacters(in: .whitespaces),
                          authors: authors, year: Int(manualYear), venue: manualVenue.isEmpty ? nil : manualVenue)
            // If duplicate PDF, use the existing paper's abstract rather than re-extracted one
            if pdfExistsElsewhere {
                paper.abstract = store.projects.flatMap({ $0.papers }).first(where: { $0.id == id })?.abstract
            } else {
                paper.abstract = extractedMeta?.abstract
            }
        } else {
            let meta = extractedMeta
            paper = Paper(id: id,
                          title: meta?.title.isEmpty == false ? meta!.title : (query.isEmpty ? id : query),
                          authors: meta?.authors ?? [])
            paper.abstract = meta?.abstract
        }

        if let url = pdfURL {
            if (try? store.registerPDF(at: url, forID: id, projectID: project.id)) != nil {
                paper.hasPDF = true
            }
        }

        project.addPaper(paper)
        try? store.save(project)
        onAdded(id)
        isPresented = false

        let dblpKey = selectedResult?.dblpKey
        let projectID = project.id
        Task {
            if let key = dblpKey, let bib = await DBLPService.fetchBibtex(dblpKey: key) {
                // Use DBLP BibTeX
                let normalized = bib.replacingOccurrences(
                    of: #"@\w+\{[^,]+"#, with: "@article{\(id)", options: .regularExpression)
                await MainActor.run {
                    if let idx = store.projects.firstIndex(where: { $0.id == projectID }) {
                        store.projects[idx].bibEntries[id] = normalized
                        try? store.save(store.projects[idx])
                    }
                }
            } else {
                // Generate BibTeX from available info
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
                DispatchQueue.main.async { pdfURL = copy; onDrop(copy) }
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
