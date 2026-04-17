import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Group {
                    Text(appLocalized("Getting Started")).font(.title2).bold()

                    VStack(alignment: .leading, spacing: 8) {
                        HelpStep(number: "1", title: appLocalized("Create a Project"),
                            detail: appLocalized("Each project represents a paper you're writing. Click the + button in the sidebar or press ⌘N to create one."))
                        HelpStep(number: "2", title: appLocalized("Add Papers"),
                            detail: appLocalized("Import a PDF, drag one onto the paper list, search DBLP or arXiv, or enter metadata manually. Use Add Paper or press ⌘⇧A."))
                        HelpStep(number: "3", title: appLocalized("Assign a Semantic ID"),
                            detail: appLocalized("Every paper gets a short memorable ID (e.g. Transformer, BERT, GPT4) used to cross-reference papers in notes."))
                        HelpStep(number: "4", title: appLocalized("Take Notes & Cross-Reference"),
                            detail: appLocalized("Write annotation notes in the editor. Use @SemanticID syntax to link to other papers — they render as clickable links."))
                        HelpStep(number: "5", title: appLocalized("Generate Related Works"),
                            detail: appLocalized("Click Generate Related Works in the project view. RelatedWorks synthesizes your notes and paper metadata into a LaTeX-ready draft."))
                        HelpStep(number: "6", title: appLocalized("Export BibTeX"),
                            detail: appLocalized("BibTeX entries are fetched from DBLP automatically, or generated from metadata when unavailable."))
                        HelpStep(number: "7", title: appLocalized("Export / Import Project"),
                            detail: appLocalized("Right-click a project → Export… to save a .relatedworks file. Use File → Import Project… (⌘⇧I) to import on any machine."))
                    }
                }

                Divider()

                Group {
                    Text(appLocalized("AI Backends")).font(.title2).bold()
                    Text(appLocalized("Configure AI providers and models in Settings."))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Label(appLocalized("Ollama — runs locally, private, no API key needed. Install from ollama.com."), systemImage: "desktopcomputer")
                        Label(appLocalized("Gemini — cloud-based. Get an API key from Google AI Studio (aistudio.google.com/apikey). Recommended model: gemini-2.5-flash."), systemImage: "cloud")
                    }
                    .font(.callout)
                }

                Divider()

                Group {
                    Text(appLocalized("Keyboard Shortcuts")).font(.title2).bold()

                    VStack(alignment: .leading, spacing: 6) {
                        HelpShortcut(key: "⌘N", action: appLocalized("New Project"))
                        HelpShortcut(key: "⌘⇧A", action: appLocalized("Add Paper"))
                        HelpShortcut(key: "⌘,", action: appLocalized("Open Settings"))
                        HelpShortcut(key: "⌘⇧I", action: appLocalized("Import Project"))
                        HelpShortcut(key: "⌘E", action: appLocalized("Export Selected Project"))
                    }
                    .font(.callout)
                }

                Divider()

                Group {
                    Text(appLocalized("Deep Links")).font(.title2).bold()
                    Text(appLocalized("Every paper and project has a relatedworks:// URI for integration with tools like Hookmark."))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("relatedworks://open?project=<UUID>").monospaced().font(.callout)
                        Text("relatedworks://open?project=<UUID>&paper=<SemanticID>").monospaced().font(.callout)
                        Text("relatedworks://settings").monospaced().font(.callout)
                    }
                }

                Divider()

                Group {
                    Text(appLocalized("Data Storage")).font(.title2).bold()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appLocalized("With local storage, projects and PDFs are stored under:"))
                        Text("~/Library/Application Support/RelatedWorks/projects/")
                            .font(.callout).monospaced()
                        Text(appLocalized("With iCloud sync enabled in Settings, projects and PDFs are stored in the app's iCloud Drive container and sync across your devices."))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 520)
        .safeAreaInset(edge: .bottom) {
            Button(appLocalized("Close")) { dismiss() }
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
