import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var tab: Tab = .general

    enum Tab: String, CaseIterable {
        case general = "General"
        case ai = "AI Backend"
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            AISettingsView(settings: settings)
                .tabItem { Label("AI Backend", systemImage: "cpu") }
                .tag(Tab.ai)
        }
        .padding(20)
        .frame(width: 500)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text("Font Size").frame(width: 80, alignment: .leading)
                    Slider(value: $settings.fontSize, in: 11...20, step: 1)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            } header: { Text("Appearance") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI Backend

struct AISettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var showingURLEditor = false

    enum ConnectionStatus { case idle, ok, failed }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text(settings.ollamaBaseURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Configure URL") { showingURLEditor = true }
                        .controlSize(.small)
                    Button("Refresh") { fetchModels() }
                        .disabled(isFetchingModels)
                        .controlSize(.small)
                }
                HStack(spacing: 6) {
                    if isFetchingModels {
                        ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        Text("Connecting…").font(.caption).foregroundStyle(.secondary)
                    } else if connectionStatus == .ok {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(availableModels.count) model(s) available").font(.caption).foregroundStyle(.secondary)
                    } else if connectionStatus == .failed {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("Cannot connect to Ollama").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            } header: { Text("Ollama") }

            Section {
                HStack(spacing: 8) {
                    Text("Extraction").frame(width: 80, alignment: .leading)
                    modelPicker(selection: $settings.extractionModel)
                    Text("PDF metadata").font(.caption).foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    Text("Generation").frame(width: 80, alignment: .leading)
                    modelPicker(selection: $settings.generationModel)
                    Text("Related Works").font(.caption).foregroundStyle(.tertiary)
                }
            } header: { Text("Models") }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $settings.generationPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                    Button("Reset to Default") {
                        settings.generationPrompt = AppSettings.defaultGenerationPrompt
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
                }
            } header: { Text("Generation Prompt Instructions") }
        }
        .formStyle(.grouped)
        .onAppear { fetchModels() }
        .sheet(isPresented: $showingURLEditor) {
            URLEditorSheet(url: $settings.ollamaBaseURL) { fetchModels() }
        }
    }

    @ViewBuilder
    private func modelPicker(selection: Binding<String>) -> some View {
        if availableModels.isEmpty {
            TextField("model name", text: selection)
                .textFieldStyle(.roundedBorder)
        } else {
            Picker("", selection: selection) {
                ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                if !availableModels.contains(selection.wrappedValue) {
                    Text(selection.wrappedValue).tag(selection.wrappedValue)
                }
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        connectionStatus = .idle
        Task {
            let urlStr = settings.ollamaBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
            guard let url = URL(string: "\(urlStr)/api/tags"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                await MainActor.run { connectionStatus = .failed; isFetchingModels = false }
                return
            }
            let names = models.compactMap { $0["name"] as? String }.sorted()
            await MainActor.run { availableModels = names; connectionStatus = .ok; isFetchingModels = false }
        }
    }
}

// MARK: - URL Editor Sheet

struct URLEditorSheet: View {
    @Binding var url: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure Ollama URL").font(.headline)
            TextField("http://localhost:11434", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Save") { url = draft; onSave(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { draft = url; focused = true }
    }
}
