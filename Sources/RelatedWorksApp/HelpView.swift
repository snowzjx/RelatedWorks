import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Group {
                    Text("Getting Started").font(.title2).bold()

                    VStack(alignment: .leading, spacing: 8) {
                        HelpStep(number: "1", title: "Create a Project",
                            detail: "Each project represents a paper you're writing. Click the + button in the sidebar to create a new project.")
                        HelpStep(number: "2", title: "Add Papers",
                            detail: "Import a PDF (drag onto the paper list), search DBLP/arXiv via the search bar, or enter metadata manually.")
                        HelpStep(number: "3", title: "Assign a Semantic ID",
                            detail: "Every paper gets a short memorable ID (e.g. Transformer, BERT, GPT4) used to cross-reference papers in notes.")
                        HelpStep(number: "4", title: "Take Notes & Cross-Reference",
                            detail: "Write annotation notes in the editor. Use @SemanticID syntax to link to other papers — they render as clickable links.")
                        HelpStep(number: "5", title: "Generate Related Works",
                            detail: "Click Generate Related Works in the project view. RelatedWorks synthesizes your notes and paper metadata into a LaTeX-ready draft.")
                        HelpStep(number: "6", title: "Export BibTeX",
                            detail: "BibTeX entries are fetched from DBLP automatically, or generated from metadata when unavailable.")
                        HelpStep(number: "7", title: "Export / Import Project",
                            detail: "Right-click a project → Export… to save a .relatedworks file. Use File → Import Project… (⌘⇧I) to import on any machine.")
                    }
                }

                Divider()

                Group {
                    Text("AI Backends").font(.title2).bold()
                    Text("Configure in Settings → AI Backends and Settings → Models.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Ollama — runs locally, private, no API key needed. Install from ollama.com.", systemImage: "desktopcomputer")
                        Label("Gemini — cloud-based. Get an API key from Google AI Studio (aistudio.google.com/apikey). Recommended model: gemini-2.5-flash.", systemImage: "cloud")
                    }
                    .font(.callout)
                }

                Divider()

                Group {
                    Text("Keyboard Shortcuts").font(.title2).bold()

                    VStack(alignment: .leading, spacing: 6) {
                        HelpShortcut(key: "⌘,", action: "Open Settings")
                        HelpShortcut(key: "⌘⇧I", action: "Import Project")
                    }
                    .font(.callout)
                }

                Divider()

                Group {
                    Text("Deep Links").font(.title2).bold()
                    Text("Every paper and project has a relatedworks:// URI for integration with tools like Hookmark.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("relatedworks://open?project=<UUID>").monospaced().font(.callout)
                        Text("relatedworks://open?project=<UUID>&paper=<SemanticID>").monospaced().font(.callout)
                    }
                }

                Divider()

                Group {
                    Text("Data Storage").font(.title2).bold()
                    Text("All data is stored in ~/Library/Application Support/RelatedWorks/")
                        .font(.callout).monospaced()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 520)
        .safeAreaInset(edge: .bottom) {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct HelpShortcut: View {
    let key: String
    let action: String
    var body: some View {
        HStack(spacing: 16) {
            Text(key).monospaced().frame(width: 48, alignment: .leading)
            Text(action).foregroundStyle(.secondary)
        }
    }
}

private struct HelpStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.callout).bold()
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).bold()
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
