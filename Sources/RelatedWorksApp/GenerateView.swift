import SwiftUI

private enum GeneratedOutputTab: Hashable {
    case draft
    case bibtex
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
    @State private var tab: GeneratedOutputTab = .draft
    @State private var copied = false
    @State private var isGenerating = false

    private var project: Project? {
        guard let id = projectID else { return nil }
        return store.projects.first { $0.id == id }
    }

    var body: some View {
        Group {
            if var proj = project {
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
                            Button(action: { copyContent(proj) }) {
                                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }

                            Button(action: { regenerate(&proj) }) {
                                if isGenerating {
                                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                                } else {
                                    Label("Regenerate", systemImage: "sparkles")
                                }
                            }
                            .disabled(isGenerating)
                        }
                    }
            } else {
                Text("Project not found").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func contentView(proj: Project) -> some View {
        let bibContent = proj.bibEntries.values.joined(separator: "\n\n")
        switch tab {
        case .draft:
            if let latex = proj.generatedLatex, !latex.isEmpty {
                ScrollView {
                    Text(highlightedLatex(latex))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.star").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No draft yet").font(.headline)
                    Text("Click Regenerate to generate a Related Works section.")
                        .foregroundStyle(.secondary)
                    Button("Generate Now") {
                        var p = proj
                        regenerate(&p)
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

    private func regenerate(_ proj: inout Project) {
        isGenerating = true
        proj.generatedLatex = nil
        proj.generationModel = nil
        try? store.save(proj)
        let snapshot = proj
        Task {
            let output = await RelatedWorksGenerator.generate(for: snapshot)
            await MainActor.run {
                guard var updated = store.projects.first(where: { $0.id == snapshot.id }) else { return }
                updated.generatedLatex = output
                updated.generationModel = AppSettings.shared.activeGenerationModelName
                try? store.save(updated)
                isGenerating = false
            }
        }
    }

    private func copyContent(_ proj: Project) {
        let bibContent = proj.bibEntries.values.joined(separator: "\n\n")
        let content = tab == .draft ? (proj.generatedLatex ?? "") : bibContent
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { copied = false }
        }
    }
}
