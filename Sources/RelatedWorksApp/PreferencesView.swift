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
        .frame(width: 460)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $settings.fontSize, in: 11...20, step: 1)
                        .frame(width: 160)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Preview")
                    Spacer()
                    Text("The quick brown fox")
                        .font(.system(size: settings.fontSize))
                        .foregroundStyle(.secondary)
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

    enum ConnectionStatus { case idle, ok, failed }

    var body: some View {
        Form {
            Section {
                LabeledContent("Ollama URL") {
                    TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit { fetchModels() }
                }
                HStack {
                    Spacer()
                    if isFetchingModels {
                        HStack(spacing: 4) { ProgressView().scaleEffect(0.7); Text("Connecting…") }
                            .font(.caption).foregroundStyle(.secondary)
                    } else if connectionStatus == .ok {
                        Label("Connected — \(availableModels.count) model(s) available", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    } else if connectionStatus == .failed {
                        Label("Cannot connect to Ollama", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red).font(.caption)
                    }
                    Button("Refresh") { fetchModels() }
                        .disabled(isFetchingModels)
                }
            } header: { Text("Ollama") }

            Section {
                LabeledContent("Extraction Model") {
                    modelPicker(selection: $settings.extractionModel)
                }
                Text("Used for PDF metadata extraction (gemma3:4b recommended)")
                    .font(.caption).foregroundStyle(.secondary)

                LabeledContent("Generation Model") {
                    modelPicker(selection: $settings.generationModel)
                }
                Text("Used for Related Works generation (qwen3 recommended)")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Models") }
        }
        .formStyle(.grouped)
        .onAppear { fetchModels() }
    }

    @ViewBuilder
    private func modelPicker(selection: Binding<String>) -> some View {
        if availableModels.isEmpty {
            TextField("model name", text: selection)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        } else {
            Picker("", selection: selection) {
                ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                // Keep current value selectable even if not in list
                if !availableModels.contains(selection.wrappedValue) {
                    Text(selection.wrappedValue).tag(selection.wrappedValue)
                }
            }
            .frame(width: 240)
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
            await MainActor.run {
                availableModels = names
                connectionStatus = .ok
                isFetchingModels = false
            }
        }
    }
}
