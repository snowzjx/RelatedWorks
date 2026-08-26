import SwiftUI

private enum GeneratedOutputTab: Hashable {
    case draft
    case bibtex
}

@MainActor
final class GenerationLogCoordinator: ObservableObject {
    @Published private var activeLogs: [UUID: GenerationLog] = [:]

    func log(for projectID: UUID) -> GenerationLog? {
        activeLogs[projectID]
    }

    func setLog(_ log: GenerationLog, for projectID: UUID) {
        activeLogs[projectID] = log
    }

    func updateResponse(_ response: String, for projectID: UUID) {
        guard var log = activeLogs[projectID] else { return }
        log.response = response
        activeLogs[projectID] = log
    }
}

// MARK: - Syntax Highlighting

private func applyHighlights(to source: String, rules: [(pattern: String, color: Color, options: NSRegularExpression.Options)]) -> AttributedString {
    var a = AttributedString(source)
    a.foregroundColor = .primary
    a.font = .system(.body, design: .monospaced)

    for rule in rules {
        guard let re = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
        let nsRange = NSRange(source.startIndex..., in: source)
        for match in re.matches(in: source, range: nsRange) {
            guard let range = Range(match.range, in: source) else { continue }
            let lower = AttributedString.Index(range.lowerBound, within: a)
            let upper = AttributedString.Index(range.upperBound, within: a)
            if let l = lower, let u = upper {
                a[l..<u].foregroundColor = rule.color
            }
        }
    }
    return a
}

private func highlightedLatex(_ source: String) -> AttributedString {
    applyHighlights(to: source, rules: [
        (#"%.*$"#,          .init(nsColor: .systemGreen),  .anchorsMatchLines),
        (#"\\[a-zA-Z@]+"#, .init(nsColor: .systemBlue),   []),
        (#"[{}]"#,          .init(nsColor: .systemOrange), []),
        (#"\[[^\]]*\]"#,    .init(nsColor: .systemPurple), []),
    ])
}

private func highlightedBibtex(_ source: String) -> AttributedString {
    applyHighlights(to: source, rules: [
        (#"@[a-zA-Z]+"#,          .init(nsColor: .systemBlue),   []),
        (#"^\s*\w+\s*="#,         .init(nsColor: .systemPurple), .anchorsMatchLines),
        (#"\{[^{}]*\}|"[^"]*""#,  .init(nsColor: .systemOrange), []),
        (#"\b\d{4}\b"#,           .init(nsColor: .systemTeal),   []),
    ])
}

// MARK: - GenerateButton

struct GenerateButton: View {
    @Binding var project: Project
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: { openWindow(id: "generate", value: project.id) }) {
            Label("Related Works", systemImage: "text.badge.star")
        }
        .disabled(project.papers.isEmpty || !AppSettings.shared.isGenerationConfigured)
        .anchorPreference(key: FirstLaunchAnchorPreferenceKey.self, value: .bounds) { [.generateButton: $0] }
        .help(project.papers.isEmpty ? "Add papers first" : (!AppSettings.shared.isGenerationConfigured ? "Configure an AI model in Settings" : "View or generate Related Works section"))
    }
}

// MARK: - GenerateWindowView

struct GenerateWindowView: View {
    let projectID: UUID?
    @EnvironmentObject var store: Store
    @EnvironmentObject private var generationLogCoordinator: GenerationLogCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var tab: GeneratedOutputTab = .draft
    @State private var copied = false
    @State private var isGenerating = false
    @State private var streamingLatex: String?
    @State private var isThinking = false
    @State private var generationTask: Task<Void, Never>?

    private var project: Project? {
        guard let id = projectID else { return nil }
        return store.projects.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let proj = project {
                contentView(proj: proj)
                    .navigationTitle(proj.name)
                    .navigationSubtitle(proj.generationModel.map { "⚙ \($0)" } ?? "")
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("Output", selection: $tab) {
                                Text("Draft").tag(GeneratedOutputTab.draft)
                                Text("BibTeX").tag(GeneratedOutputTab.bibtex)
                            }
                            .pickerStyle(.segmented)
//                            .frame(width: 180)
                        }

                        ToolbarItemGroup(placement: .primaryAction) {
                            Button(action: { openWindow(id: AppWindowID.generationLog, value: proj.id) }) {
                                Label("Log", systemImage: "text.alignleft")
                            }
                            .disabled(generationLogCoordinator.log(for: proj.id) == nil && proj.generationLog == nil)

                            Button(action: { copyContent(proj) }) {
                                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }

                            if isGenerating {
                                Button(action: cancelGeneration) {
                                    Label("Cancel", systemImage: "stop.circle")
                                }
                            } else {
                                Button(action: { regenerate(proj) }) {
                                    Label("Regenerate", systemImage: "sparkles")
                                }
                            }
                        }
                    }
            } else {
                Text("Project not found").foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }

    @ViewBuilder
    private func contentView(proj: Project) -> some View {
        let bibContent = proj.bibEntries.values.joined(separator: "\n\n")
        let draftLatex = streamingLatex ?? proj.generatedLatex
        switch tab {
        case .draft:
            if let latex = draftLatex, !latex.isEmpty || isGenerating {
                ZStack(alignment: .topLeading) {
                    ScrollView {
                        Text(highlightedLatex(latex))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }

                    if isGenerating && latex.isEmpty {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(isThinking ? "Thinking..." : "Generating...")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.star").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No draft yet").font(.headline)
                    Text("Click Regenerate to generate a Related Works section.")
                        .foregroundStyle(.secondary)
                    Button("Generate Now") {
                        regenerate(proj)
                    }
                    .buttonStyle(.borderedProminent)
                    .inactiveAwareProminentButtonForeground()
                    .disabled(isGenerating)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .bibtex:
            if bibContent.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No BibTeX entries yet").font(.headline)
                    Text("BibTeX is fetched from DBLP when you add papers with a DBLP match.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(highlightedBibtex(bibContent))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func regenerate(_ proj: Project) {
        generationTask?.cancel()

        let prompt = RelatedWorksGenerator.buildPrompt(proj)
        let modelName = AppSettings.shared.activeGenerationModelName
        let startedLog = GenerationLog(prompt: prompt, model: modelName)

        isGenerating = true
        isThinking = false
        streamingLatex = ""
        generationLogCoordinator.setLog(startedLog, for: proj.id)

        var snapshot = proj
        snapshot.generatedLatex = nil
        snapshot.generationModel = nil
        snapshot.generationLog = startedLog
        try? store.save(snapshot)

        generationTask = Task {
            var output = ""
            var failed = false
            var receivedCancellation = false

            for await event in RelatedWorksGenerator.streamEvents(for: snapshot) {
                switch event {
                case let .thinking(thinking):
                    await MainActor.run {
                        isThinking = thinking
                    }
                case let .output(partialOutput):
                    output = partialOutput
                    await MainActor.run {
                        streamingLatex = partialOutput
                        generationLogCoordinator.updateResponse(partialOutput, for: snapshot.id)
                    }
                case let .failed(message):
                    failed = true
                    output = message
                    await MainActor.run {
                        streamingLatex = message
                        generationLogCoordinator.updateResponse(message, for: snapshot.id)
                    }
                case .cancelled:
                    receivedCancellation = true
                }
            }

            let wasCancelled = Task.isCancelled || receivedCancellation
            await MainActor.run {
                guard var updated = store.projects.first(where: { $0.id == snapshot.id }) else {
                    streamingLatex = nil
                    isThinking = false
                    isGenerating = false
                    generationTask = nil
                    return
                }

                var completedLog = startedLog
                completedLog.response = output
                completedLog.completedAt = Date()
                completedLog.status = wasCancelled ? .cancelled : (failed ? .failed : .completed)

                updated.generatedLatex = output.isEmpty ? nil : output
                updated.generationModel = output.isEmpty ? nil : modelName
                updated.generationLog = completedLog
                try? store.save(updated)
                generationLogCoordinator.setLog(completedLog, for: snapshot.id)
                streamingLatex = nil
                isThinking = false
                isGenerating = false
                generationTask = nil
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
    }

    private func copyContent(_ proj: Project) {
        let bibContent = proj.bibEntries.values.joined(separator: "\n\n")
        let content = tab == .draft ? (streamingLatex ?? proj.generatedLatex ?? "") : bibContent
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { copied = false }
        }
    }
}

struct GenerationLogWindowView: View {
    let projectID: UUID?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var generationLogCoordinator: GenerationLogCoordinator

    private var log: GenerationLog? {
        guard let projectID else { return nil }
        return generationLogCoordinator.log(for: projectID)
            ?? store.projects.first(where: { $0.id == projectID })?.generationLog
    }

    var body: some View {
        if let log {
            GenerationLogView(log: log)
        } else {
            ContentUnavailableView(
                "No Generation Log",
                systemImage: "text.alignleft",
                description: Text("Generate a Related Works draft to create a conversation log.")
            )
        }
    }
}

private struct GenerationLogView: View {
    let log: GenerationLog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                        Text(statusText)
                            .font(.headline)
                        Spacer()
                        if !log.model.isEmpty {
                            Text(log.model)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(log.startedAt.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    transcriptSection(title: "User", text: log.prompt)
                    transcriptSection(
                        title: "Assistant",
                        text: log.response.isEmpty ? emptyResponseText : log.response
                    )
                }
                .padding(20)
            }
            .navigationTitle("Generation Log")
        }
    }

    private func transcriptSection(title: LocalizedStringKey, text: String) -> some View {
        GroupBox {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } label: {
            Text(title)
                .font(.headline)
        }
    }

    private var statusText: LocalizedStringKey {
        switch log.status {
        case .inProgress: "Generating..."
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }

    private var statusIcon: String {
        switch log.status {
        case .inProgress: "ellipsis.circle"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch log.status {
        case .inProgress: .accentColor
        case .completed: .green
        case .cancelled: .orange
        case .failed: .red
        }
    }

    private var emptyResponseText: String {
        switch log.status {
        case .inProgress: appLocalized("Waiting for the model to respond…")
        case .cancelled: appLocalized("Generation was cancelled before the model returned any text.")
        case .completed, .failed: appLocalized("No response was returned.")
        }
    }
}
