import SwiftUI

private let citationHeaderControlHeight: CGFloat = 18

struct CitationGraphWindowView: View {
    @EnvironmentObject var store: Store
    let projectID: UUID?
    @Environment(\.openWindow) private var openWindow

    @State private var selectedNodeID: String?
    @State private var selectedExternalPaperID: String?
    @State private var isRefreshing = false
    @State private var refreshStatus: String?
    @State private var refreshCompletedCount = 0
    @State private var refreshTotalCount = 0
    @State private var citationData: CitationGraphProjectData?
    @State private var externalSearchQuery = ""
    @State private var showMentions = true
    @State private var showProjectReferences = true
    @State private var showSharedExternalReferences = true
    @State private var sharedExternalDisplayThreshold = 2

    private var project: Project? {
        guard let projectID else { return nil }
        return store.projects.first(where: { $0.id == projectID })
    }

    private var graph: CitationGraph? {
        guard let project, let citationData else { return nil }
        return CitationGraph(
            project: project,
            data: citationData,
            sharedExternalDisplayThreshold: sharedExternalDisplayThreshold
        )
    }

    private var visibleEdges: [CitationGraph.Edge] {
        guard let graph else { return [] }
        return graph.edges.filter { edge in
            switch edge.kind {
            case .mention: return showMentions
            case .projectReference: return showProjectReferences
            case .sharedExternalReference: return showSharedExternalReferences
            case .externalReference: return false
            }
        }
    }

    private var visibleNodes: [CitationGraph.Node] {
        guard let graph else { return [] }
        let connected = Set(visibleEdges.flatMap { [$0.sourceID, $0.targetID] })
        return graph.nodes.filter { node in
            node.kind == .projectPaper || connected.contains(node.id)
        }
    }

    private var filteredExternalPapers: [CitationGraph.ExternalPaper] {
        guard let graph else { return [] }
        let query = externalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return graph.externalPapers }
        return graph.externalPapers.filter {
            $0.title.lowercased().contains(query) ||
            $0.referencingPaperIDs.joined(separator: " ").lowercased().contains(query)
        }
    }

    private var selectedNode: CitationGraph.Node? {
        guard let selectedNodeID, let graph else { return nil }
        return graph.nodes.first { $0.id == selectedNodeID }
    }

    private var selectedExternalPaper: CitationGraph.ExternalPaper? {
        guard let selectedExternalPaperID, let graph else { return nil }
        return graph.externalPapers.first { $0.id == selectedExternalPaperID }
    }

    private var selectedNodeExternalPaper: CitationGraph.ExternalPaper? {
        guard let selectedNodeID, let graph else { return nil }
        return graph.externalPapers.first { $0.id == selectedNodeID }
    }

    private var windowTitle: String {
        project?.name ?? appLocalized("Citation Graph")
    }

    var body: some View {
        Group {
            if let project {
                HSplitView {
                    VStack(spacing: 0) {
                        header(project: project)
                        Divider()
                        ZStack(alignment: .bottomTrailing) {
                            CitationGraphCanvas(
                                nodes: visibleNodes,
                                edges: visibleEdges,
                                selectedNodeID: $selectedNodeID,
                                onOpenProjectPaper: openProjectPaper
                            )

                            if showSharedExternalReferences {
                                sharedThresholdControl
                                    .padding(16)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        externalList
                        Divider()
                        inspector(project: project)
                    }
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                }
            } else {
                EmptyStateView(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: LocalizedStringKey(appLocalized("No Project Selected")),
                    message: LocalizedStringKey(appLocalized("Open the citation graph from a project to inspect its paper relationships."))
                )
            }
        }
        .task(id: projectID) {
            await loadCitationData()
        }
        .onChange(of: selectedNodeID) { _, newValue in
            guard newValue != nil else { return }
            selectedExternalPaperID = nil
        }
        .onChange(of: selectedExternalPaperID) { _, newValue in
            guard newValue != nil else { return }
            selectedNodeID = nil
        }
        .onChange(of: sharedExternalDisplayThreshold) { _, _ in
            guard let selectedNodeID else { return }
            let visibleNodeIDs = Set(visibleNodes.map(\.id))
            if !visibleNodeIDs.contains(selectedNodeID) {
                self.selectedNodeID = nil
            }
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(appLocalized("Citation Graph"))
        .frame(minWidth: 1180, minHeight: 760)
    }

    private func header(project: Project) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 8) {
                Label(appLocalized("Citation Graph"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(project.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    refreshReferences(for: project)
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .frame(width: 12, height: 12)
                        Text(appLocalized("Refresh References"))
                            .lineLimit(1)
                    }
                    .frame(height: citationHeaderControlHeight)
                }
                .controlSize(.small)
                .disabled(isRefreshing)
            }

            HStack(spacing: 2) {
                Toggle(isOn: $showMentions) {
                    citationFilterLabel(title: appLocalized("Mentions"), systemImage: "at")
                }
                Toggle(isOn: $showProjectReferences) {
                    citationFilterLabel(title: appLocalized("In Project"), systemImage: "doc.on.doc")
                }
                Toggle(isOn: $showSharedExternalReferences) {
                    citationFilterLabel(title: appLocalized("Shared Outside"), systemImage: "point.3.filled.connected.trianglepath.dotted")
                }
                Spacer()
                ProgressView(value: Double(refreshCompletedCount), total: max(Double(refreshTotalCount), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 132)
                    .opacity(isRefreshing && refreshTotalCount > 0 ? 1 : 0)
                    .accessibilityHidden(!(isRefreshing && refreshTotalCount > 0))
                if let refreshStatus {
                    Text(refreshStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.button)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func citationFilterLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 12, height: 12)
            Text(title)
                .lineLimit(1)
        }
        .frame(height: citationHeaderControlHeight)
    }

    private var maxSharedExternalThreshold: Int {
        max(2, graph?.externalPapers.map(\.referenceCount).max() ?? 2)
    }

    private var sharedThresholdControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalizedFormat("Show if shared by %d+ papers", sharedExternalDisplayThreshold))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if maxSharedExternalThreshold > 2 {
                Slider(
                    value: Binding(
                        get: { Double(sharedExternalDisplayThreshold) },
                        set: { sharedExternalDisplayThreshold = max(2, Int($0.rounded())) }
                    ),
                    in: 2...Double(maxSharedExternalThreshold),
                    step: 1
                )
                .frame(width: 140)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var externalList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appLocalized("External Papers"))
                    .font(.headline)
                Spacer()
                if let graph {
                    Text("\(graph.externalPapers.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LiquidGlassSearchField(prompt: LocalizedStringKey(appLocalized("Search external papers…")), text: $externalSearchQuery)
            List(filteredExternalPapers, selection: $selectedExternalPaperID) { paper in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: paper.isShared ? "point.3.filled.connected.trianglepath.dotted" : "link")
                            .foregroundStyle(paper.isShared ? .orange : .secondary)
                        Text(paper.title)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    Text(paper.referencingPaperIDs.map { "@\($0)" }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(paper.id)
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 8)
    }

    private func inspector(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appLocalized("Details"))
                .font(.headline)

            if let selectedNode {
                CitationSelectionInspector(
                    title: selectedNode.title,
                    subtitle: selectedNode.paperID.map { "@\($0)" } ?? (selectedNodeExternalPaper?.isShared == true ? appLocalized("Shared external reference") : appLocalized("External reference")),
                    linkedPaperIDs: selectedNode.paperID.map { linkedProjectPaperIDs(for: $0, in: project) } ?? selectedNode.referencingPaperIDs,
                    mentionPaperIDs: selectedNode.paperID.map { mentionPaperIDs(for: $0, in: project) } ?? [],
                    externalLinkTitle: selectedNodeExternalPaper.map { externalPaperOpenLabel(for: $0.reference) },
                    externalURL: selectedNodeExternalPaper.flatMap { externalPaperURL(for: $0.reference) },
                    onOpenProjectPaper: openProjectPaper
                )
            } else if let selectedExternalPaper {
                CitationSelectionInspector(
                    title: selectedExternalPaper.title,
                    subtitle: selectedExternalPaper.isShared ? appLocalized("Shared external reference") : appLocalized("External reference"),
                    linkedPaperIDs: selectedExternalPaper.referencingPaperIDs,
                    mentionPaperIDs: [],
                    externalLinkTitle: externalPaperLinkTitle(for: selectedExternalPaper.reference),
                    externalURL: externalPaperURL(for: selectedExternalPaper.reference),
                    onOpenProjectPaper: openProjectPaper
                )
            } else {
                Text(appLocalized("Select a node in the graph or a paper in the external list."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(appLocalized("Legend"))
                    .font(.headline)
                legendNodeRow(color: .blue, icon: "doc.text.fill", title: appLocalized("Project paper"))
                legendNodeRow(color: .orange, icon: "point.3.filled.connected.trianglepath.dotted", title: appLocalized("Shared outside paper"))
                legendEdgeRow(color: .teal, title: appLocalized("Mention connection"), dash: [5, 4], lineWidth: 1.4)
                legendEdgeRow(color: .indigo, title: appLocalized("Reference within project"), dash: [], lineWidth: 1.8)
                legendEdgeRow(color: .orange, title: appLocalized("Shared outside reference"), dash: [], lineWidth: 2.2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized("Sources"))
                    .font(.headline)
                Text(appLocalized("Reference metadata is matched with DBLP first, then arXiv. External reference lists come from OpenAlex."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
    }

    private func legendNodeRow(color: Color, icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                        .overlay {
                            Image(systemName: icon)
                                .font(.caption)
                                .foregroundStyle(color)
                        }
                }
                .frame(width: 22, height: 18)
            Text(title)
            Spacer()
        }
        .font(.caption)
    }

    private func legendEdgeRow(color: Color, title: String, dash: [CGFloat], lineWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 1, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, dash: dash))
            }
            .frame(width: 22, height: 10)
            Text(title)
            Spacer()
        }
        .font(.caption)
    }

    private func openProjectPaper(_ paperID: String) {
        guard let projectID else { return }
        openWindow(id: AppWindowID.main)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .openCitationGraphPaper,
                object: nil,
                userInfo: ["projectID": projectID, "paperID": paperID]
            )
        }
    }

    private func linkedProjectPaperIDs(for selectedPaperID: String, in project: Project) -> [String] {
        guard let graph else { return [] }
        let sourceNodeID = "project:\(selectedPaperID.lowercased())"
        let outgoingTargets = graph.edges
            .filter { $0.kind == .projectReference && $0.sourceID == sourceNodeID }
            .compactMap { edge in
                graph.nodes.first(where: { $0.id == edge.targetID })?.paperID
            }
        let incomingSources = graph.edges
            .filter { $0.kind == .projectReference && $0.targetID == sourceNodeID }
            .compactMap { edge in
                graph.nodes.first(where: { $0.id == edge.sourceID })?.paperID
            }
        return Array(Set(outgoingTargets + incomingSources)).sorted()
    }

    private func mentionPaperIDs(for selectedPaperID: String, in project: Project) -> [String] {
        guard let paper = project.paper(withID: selectedPaperID) else { return [] }
        return Array(Set(project.extractRefs(from: paper.annotation)))
            .filter { $0.lowercased() != selectedPaperID.lowercased() && project.paper(withID: $0) != nil }
            .sorted()
    }

    private func externalPaperURL(for reference: PaperReference) -> URL? {
        if let arxivID = reference.arxivID?.trimmingCharacters(in: .whitespacesAndNewlines), !arxivID.isEmpty {
            return URL(string: "https://arxiv.org/abs/\(arxivID)")
        }

        let query = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://dblp.org/search?q=\(encoded)")
    }

    private func externalPaperLinkTitle(for reference: PaperReference) -> String {
        if let arxivID = reference.arxivID?.trimmingCharacters(in: .whitespacesAndNewlines), !arxivID.isEmpty {
            return appLocalized("arXiv")
        }
        return appLocalized("DBLP")
    }

    private func externalPaperOpenLabel(for reference: PaperReference) -> String {
        appLocalizedFormat("Open in %@", externalPaperLinkTitle(for: reference))
    }

    private func loadCitationData() async {
        guard let projectID else { return }
        citationData = (try? store.loadCitationGraphData(for: projectID)) ?? CitationGraphProjectData(projectID: projectID)
        selectedNodeID = nil
        selectedExternalPaperID = nil
    }

    private func refreshReferences(for project: Project) {
        guard !project.papers.isEmpty else {
            refreshStatus = appLocalized("No papers to refresh.")
            return
        }

        isRefreshing = true
        refreshStatus = appLocalized("Looking up citation metadata...")
        refreshCompletedCount = 0
        refreshTotalCount = project.papers.count
        let existingData = citationData ?? CitationGraphProjectData(projectID: project.id)

        Task {
            var updatedData = existingData
            var successCount = 0
            var failureCount = 0

            for paper in project.papers {
                do {
                    var paperData = updatedData.paperData[paper.id] ?? CitationGraphPaperData()

                    if let seed = await DBLPService.findCitationSeed(
                        title: paper.title,
                        authors: paper.authors,
                        year: paper.year
                    ) {
                        paperData.dblpKey = seed.dblpKey ?? paperData.dblpKey
                        paperData.doi = seed.doi ?? paperData.doi
                        paperData.arxivID = seed.arxivID ?? paperData.arxivID
                    }

                    if paperData.arxivID == nil,
                       let arxiv = await ArxivService.findMatchingPaper(title: paper.title) {
                        paperData.arxivID = arxiv.arxivID
                    }

                    paperData = try await OpenAlexService.fetchReferences(
                        seed: paperData,
                        title: paper.title,
                        authors: paper.authors,
                        year: paper.year
                    )
                    updatedData.paperData[paper.id] = paperData
                    updatedData.updatedAt = Date()
                    successCount += 1
                } catch {
                    failureCount += 1
                }

                let completedCount = successCount + failureCount
                let status = appLocalizedFormat("Updated %d of %d papers", completedCount, project.papers.count)
                await MainActor.run {
                    refreshCompletedCount = completedCount
                    refreshStatus = status
                }
            }

            await MainActor.run {
                citationData = updatedData
                try? store.saveCitationGraphData(updatedData)
                isRefreshing = false
                refreshCompletedCount = refreshTotalCount
                refreshStatus = failureCount == 0
                    ? appLocalizedFormat("Updated references for %d papers.", successCount)
                    : appLocalizedFormat("Updated %d papers. %d lookups failed.", successCount, failureCount)
            }
        }
    }
}

private struct CitationSelectionInspector: View {
    let title: String
    let subtitle: String?
    let linkedPaperIDs: [String]
    let mentionPaperIDs: [String]
    let externalLinkTitle: String?
    let externalURL: URL?
    var onOpenProjectPaper: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let externalURL, let externalLinkTitle {
                Link(destination: externalURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                        Text(externalLinkTitle)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if linkedPaperIDs.isEmpty && mentionPaperIDs.isEmpty {
                Text(appLocalized("No project papers linked here yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !linkedPaperIDs.isEmpty {
                Text(appLocalized("Linked project papers"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                paperLinkList(linkedPaperIDs)
            }

            if !mentionPaperIDs.isEmpty {
                Text(appLocalized("Mentions"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                paperLinkList(mentionPaperIDs)
            }
        }
    }

    @ViewBuilder
    private func paperLinkList(_ paperIDs: [String]) -> some View {
        ForEach(paperIDs, id: \.self) { paperID in
            Button {
                onOpenProjectPaper(paperID)
            } label: {
                HStack {
                    Tag("@\(paperID)", color: .blue)
                    Spacer()
                    Image(systemName: "arrow.right.circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CitationGraphCanvas: View {
    let nodes: [CitationGraph.Node]
    let edges: [CitationGraph.Edge]
    @Binding var selectedNodeID: String?
    var onOpenProjectPaper: (String) -> Void

    @State private var nodeFrames: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { proxy in
            let layout = CitationGraphLayout(nodes: nodes, size: proxy.size)
            ZStack {
                Canvas { context, _ in
                    for edge in edges {
                        guard let start = layout.positions[edge.sourceID],
                              let end = layout.positions[edge.targetID] else { continue }
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        context.stroke(path, with: .color(edge.color), style: StrokeStyle(lineWidth: edge.lineWidth, dash: edge.dash))
                    }
                }

                ForEach(nodes) { node in
                    CitationGraphNodeView(node: node, isSelected: selectedNodeID == node.id)
                        .position(layout.positions[node.id] ?? .zero)
                        .background(
                            GeometryReader { nodeProxy in
                                Color.clear.preference(
                                    key: CitationGraphNodeFrameKey.self,
                                    value: [node.id: nodeProxy.frame(in: .named("CitationGraphCanvas"))]
                                )
                            }
                        )
                        .onTapGesture {
                            selectedNodeID = node.id
                        }
                        .onTapGesture(count: 2) {
                            if let paperID = node.paperID {
                                onOpenProjectPaper(paperID)
                            }
                        }
                }
            }
            .coordinateSpace(name: "CitationGraphCanvas")
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard !nodeFrames.values.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(location) }) else { return }
                selectedNodeID = nil
            }
            .onPreferenceChange(CitationGraphNodeFrameKey.self) { nodeFrames = $0 }
        }
    }
}

private struct CitationGraphNodeView: View {
    let node: CitationGraph.Node
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: node.icon)
                .font(.system(size: node.kind == .projectPaper ? 18 : 14, weight: .semibold))
            Text(node.paperID.map { "@\($0)" } ?? node.title)
                .font(node.kind == .projectPaper ? .caption.weight(.medium) : .caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: node.kind == .projectPaper ? 110 : 96)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(node.color.opacity(node.kind == .projectPaper ? 0.14 : 0.10))
        .foregroundStyle(node.color)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : node.color.opacity(0.25), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.15 : 0.06), radius: isSelected ? 8 : 3, y: 2)
    }
}

private struct CitationGraphLayout {
    let positions: [String: CGPoint]

    init(nodes: [CitationGraph.Node], size: CGSize) {
        let projectNodes = nodes.filter { $0.kind == .projectPaper }
        let sharedNodes = nodes.filter { $0.kind == .sharedExternalPaper }
        let externalNodes = nodes.filter { $0.kind == .externalPaper }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = max(120, min(size.width, size.height) * 0.30)
        let outer = max(base + 90, min(size.width, size.height) * 0.43)
        var positions: [String: CGPoint] = [:]

        Self.place(projectNodes, radius: base, center: center, startAngle: -.pi / 2, into: &positions)
        Self.place(sharedNodes, radius: outer, center: center, startAngle: -.pi / 2, into: &positions)
        Self.place(externalNodes, radius: outer, center: center, startAngle: .pi / 2, into: &positions)

        self.positions = positions
    }

    private static func place(_ nodes: [CitationGraph.Node], radius: CGFloat, center: CGPoint, startAngle: CGFloat, into positions: inout [String: CGPoint]) {
        guard !nodes.isEmpty else { return }
        if nodes.count == 1 {
            positions[nodes[0].id] = CGPoint(x: center.x, y: center.y - radius)
            return
        }
        for (index, node) in nodes.enumerated() {
            let angle = startAngle + (CGFloat(index) / CGFloat(nodes.count)) * 2 * .pi
            positions[node.id] = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }
}

private struct CitationGraphNodeFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension CitationGraph.Node {
    var color: Color {
        switch kind {
        case .projectPaper: return .blue
        case .externalPaper: return .secondary
        case .sharedExternalPaper: return .orange
        }
    }

    var icon: String {
        switch kind {
        case .projectPaper: return "doc.text.fill"
        case .externalPaper: return "link"
        case .sharedExternalPaper: return "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

private extension CitationGraph.Edge {
    var color: Color {
        switch kind {
        case .mention: return .teal
        case .projectReference: return .indigo
        case .externalReference: return .secondary.opacity(0.65)
        case .sharedExternalReference: return .orange
        }
    }

    var lineWidth: CGFloat {
        switch kind {
        case .sharedExternalReference: return 2.2
        case .projectReference: return 1.8
        default: return 1.4
        }
    }

    var dash: [CGFloat] {
        switch kind {
        case .mention: return [5, 4]
        case .externalReference: return [3, 4]
        default: return []
        }
    }
}
