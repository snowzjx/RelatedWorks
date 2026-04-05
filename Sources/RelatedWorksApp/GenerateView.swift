import SwiftUI

struct GenerateButton: View {
    @Binding var project: Project
    @EnvironmentObject var store: Store
    @State private var showingSheet = false
    @State private var isGenerating = false

    var body: some View {
        Button(action: { showingSheet = true }) {
            Label("Related Works", systemImage: "text.badge.star")
        }
        .disabled(project.papers.isEmpty)
        .help("View or generate Related Works section")
        .sheet(isPresented: $showingSheet) {
            GeneratedOutputSheet(project: $project, isGenerating: $isGenerating) {
                regenerate()
            }
        }
    }

    private func regenerate() {
        isGenerating = true
        project.generatedLatex = nil
        try? store.save(project)
        Task {
            let output = await RelatedWorksGenerator.generate(for: project)
            await MainActor.run {
                project.generatedLatex = output
                try? store.save(project)
                isGenerating = false
            }
        }
    }
}

struct GeneratedOutputSheet: View {
    @Binding var project: Project
    @Binding var isGenerating: Bool
    let onRegenerate: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var tab: Tab = .latex
    @State private var copied = false

    enum Tab { case latex, bib }

    var bibContent: String {
        project.bibEntries.values.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ───────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Related Works").font(.title3).fontWeight(.semibold)
                    Text(project.name).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $tab) {
                    Text("LaTeX").tag(Tab.latex)
                    Text(".bib").tag(Tab.bib)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Button(action: copy) {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button(action: onRegenerate) {
                    Group {
                        if isGenerating {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                                Text("Generating…")
                            }
                        } else {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(20)

            Divider()

            // ── Content ──────────────────────────────────────────────
            if tab == .latex {
                if let latex = project.generatedLatex, !latex.isEmpty {
                    ScrollView {
                        Text(latex)
                            .font(.system(.body, design: .monospaced))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.badge.star").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text("No draft yet").font(.headline)
                        Text("Click Regenerate to generate a Related Works section.")
                            .foregroundStyle(.secondary)
                        Button("Generate Now", action: onRegenerate)
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
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
                        Text(bibContent)
                            .font(.system(.body, design: .monospaced))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .frame(width: 720, height: 540)
    }

    private func copy() {
        let content = tab == .latex ? (project.generatedLatex ?? "") : bibContent
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { copied = false }
        }
    }
}
