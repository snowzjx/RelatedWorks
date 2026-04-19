import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject var store: Store
    @Binding private var tab: Tab

    enum Tab { case general, models, backends }

    init(tab: Binding<Tab> = .constant(.general)) {
        self._tab = tab
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView(settings: settings)
                .tabItem { Label(appLocalized("General"), systemImage: "gearshape") }
                .tag(Tab.general)

            ModelsSettingsView(settings: settings)
                .tabItem { Label(appLocalized("Models"), systemImage: "slider.horizontal.3") }
                .tag(Tab.models)

            BackendsSettingsView(settings: settings)
                .tabItem { Label(appLocalized("AI Backends"), systemImage: "cpu") }
                .tag(Tab.backends)
        }
        .padding(20)
        .frame(width: 540)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var store: Store
    @State private var migrationProgress: Double? = nil
    @State private var migrationLabel = ""
    @State private var migrationError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text(appLocalized("Font Size")).frame(width: 80, alignment: .leading)
                    Slider(value: $settings.fontSize, in: 11...20, step: 1)
                    Text(appLocalizedFormat("%lld pt", Int(settings.fontSize)))
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Text(appLocalized("Language")).frame(width: 80, alignment: .leading)
                    Picker("", selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(appLocalized("Changes apply immediately to the app interface."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text(appLocalized("Appearance")) }

            Section {
                Toggle(appLocalized("Sync via iCloud Drive"), isOn: Binding(
                    get: { settings.iCloudSyncEnabled },
                    set: { newValue in Task { await toggleICloud(newValue) } }
                ))
                .anchorPreference(key: FirstLaunchAnchorPreferenceKey.self, value: .bounds) { [.iCloudToggle: $0] }
                Text(appLocalized("Stores all projects and PDFs in iCloud Drive, synced across your Mac and iPhone."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress = migrationProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(migrationLabel).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: progress).progressViewStyle(.linear)
                    }
                }
            } header: { Text("iCloud") }
        }
        .formStyle(.grouped)
        .alert(appLocalized("Migration Failed"), isPresented: Binding(
            get: { migrationError != nil },
            set: { if !$0 { migrationError = nil } }
        )) {
            Button(appLocalized("OK")) { migrationError = nil }
        } message: { Text(migrationError ?? "") }
    }

    private func toggleICloud(_ enable: Bool) async {
        await MainActor.run {
            migrationProgress = 0
            migrationLabel = enable ? appLocalized("Copying to iCloud Drive…") : appLocalized("Copying to local storage…")
        }
        do {
            if enable {
                try await store.migrateToICloud { p in Task { @MainActor in migrationProgress = p } }
            } else {
                try await store.migrateToLocal { p in Task { @MainActor in migrationProgress = p } }
            }
            await MainActor.run {
                settings.iCloudSyncEnabled = enable
                migrationProgress = nil
                store.reload()
                NotificationCenter.default.post(name: .iCloudSyncChanged, object: nil)
            }
        } catch {
            await MainActor.run {
                migrationProgress = nil
                migrationError = error.localizedDescription
            }
        }
    }
}

// MARK: - Models (extraction + generation model selection per backend)

struct ModelsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var reachability = OllamaReachability.shared
    @State private var ollamaModels: [String] = []
    @State private var geminiModels: [String] = []

    var availableBackends: [AIBackendType] {
        var backends: [AIBackendType] = [.none]
        if reachability.reachable { backends.append(.ollama) }
        if !settings.geminiAPIKey.isEmpty { backends.append(.gemini) }
        return backends
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text(appLocalized("Backend")).frame(width: 80, alignment: .leading)
                    Picker("", selection: $settings.extractionBackend) {
                        ForEach(availableBackends, id: \.self) { Text($0.displayName).tag($0) }
                    }.frame(width: 110)
                    if settings.extractionBackend == .ollama {
                        modelPicker(models: ollamaModels, selection: $settings.extractionModel, placeholder: appLocalized("model name"))
                    } else if settings.extractionBackend == .gemini {
                        modelPicker(models: geminiModels, selection: $settings.geminiExtractionModel, placeholder: appLocalized("gemini-2.5-flash"), isGemini: true)
                    }
                }
            } header: { Text(appLocalized("PDF Extraction")) }

            Section {
                HStack(spacing: 8) {
                    Text(appLocalized("Backend")).frame(width: 80, alignment: .leading)
                    Picker("", selection: $settings.generationBackend) {
                        ForEach(availableBackends, id: \.self) { Text($0.displayName).tag($0) }
                    }.frame(width: 110)
                    if settings.generationBackend == .ollama {
                        modelPicker(models: ollamaModels, selection: $settings.generationModel, placeholder: appLocalized("model name"))
                    } else if settings.generationBackend == .gemini {
                        modelPicker(models: geminiModels, selection: $settings.geminiGenerationModel, placeholder: appLocalized("gemini-2.5-flash"), isGemini: true)
                    }
                }
            } header: { Text(appLocalized("Related Works Generation")) }

        }
        .formStyle(.grouped)
        .onAppear { fetchModels() }
    }

    @ViewBuilder
    private func modelPicker(models: [String], selection: Binding<String>, placeholder: String, isGemini: Bool = false) -> some View {
        if models.isEmpty {
            Text(selection.wrappedValue.isEmpty ? appLocalized("No models available") : selection.wrappedValue)
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            Picker("", selection: selection) {
                Text(appLocalized("Select model…")).tag("").foregroundStyle(.secondary)
                ForEach(models, id: \.self) { model in
                    let incompatible = isGemini && AppSettings.incompatibleGeminiModels.contains(model)
                    if incompatible {
                        Text(model).strikethrough().foregroundStyle(.secondary).tag(model)
                    } else {
                        Text(model).tag(model)
                    }
                }
                if !selection.wrappedValue.isEmpty && !models.contains(selection.wrappedValue) {
                    Text(selection.wrappedValue).tag(selection.wrappedValue)
                }
            }
            .onChange(of: selection.wrappedValue) { _, newVal in
                if isGemini && AppSettings.incompatibleGeminiModels.contains(newVal) {
                    // Revert to first compatible model
                    if let first = models.first(where: { !AppSettings.incompatibleGeminiModels.contains($0) }) {
                        selection.wrappedValue = first
                    }
                }
            }
        }
    }

    private func fetchModels() {
        fetchOllamaModels()
        fetchGeminiModels()
    }

    private func fetchOllamaModels() {
        Task {
            let urlStr = settings.ollamaBaseURL.trimmingCharacters(in: .init(charactersIn: "/"))
            guard let url = URL(string: "\(urlStr)/api/tags"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                await MainActor.run { settings.ollamaReachable = false }
                return
            }
            let names = models.compactMap { $0["name"] as? String }.sorted()
            await MainActor.run { ollamaModels = names; settings.ollamaReachable = true }
        }
    }

    private func fetchGeminiModels() {
        let key = settings.geminiAPIKey
        guard !key.isEmpty else { return }
        Task {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return }
            var req = URLRequest(url: url)
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }
            let names = models.compactMap { m -> String? in
                guard let name = m["name"] as? String,
                      let methods = m["supportedGenerationMethods"] as? [String],
                      methods.contains("generateContent") else { return nil }
                return name.replacingOccurrences(of: "models/", with: "")
            }.sorted()
            await MainActor.run { geminiModels = names }
        }
    }
}

// MARK: - AI Backends (Ollama + Gemini config)

struct BackendsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var reachability = OllamaReachability.shared
    @State private var ollamaModelCount: Int = 0
    @State private var showingURLEditor = false
    @State private var showingGeminiKeyEditor = false
    @State private var geminiTestStatus: TestStatus = .idle
    @State private var geminiModels: [String] = []
    @State private var isFetchingGemini = false

    enum TestStatus { case idle, testing, ok, failed(String) }

    var body: some View {
        Form {
            // ── Ollama ───────────────────────────────────────────────
            Section {
                HStack(spacing: 8) {
                    Text(settings.ollamaBaseURL).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(appLocalized("Configure")) { showingURLEditor = true }
                        .controlSize(.small)
                        .anchorPreference(key: FirstLaunchAnchorPreferenceKey.self, value: .bounds) { [.aiBackend: $0] }
                    Button(appLocalized("Refresh")) { Task { await settings.checkOllama() } }.controlSize(.small)
                }
                HStack(spacing: 6) {
                    if reachability.reachable {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(appLocalized("Ollama is running")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(appLocalized("Cannot connect to Ollama")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $settings.ollamaTimeoutSeconds, in: 30...1800, step: 30) {
                    HStack {
                        Text(appLocalized("Request timeout"))
                        Spacer()
                        Text(appLocalizedFormat("%lld seconds", settings.ollamaTimeoutSeconds))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(appLocalized("For large models, increase timeout if generation often times out."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: { Text(appLocalized("Ollama")) }

            // ── Gemini ───────────────────────────────────────────────
            Section {
                HStack(spacing: 8) {
                    Text(settings.geminiAPIKey.isEmpty ? appLocalized("No API key set") : "••••••••••••••••")
                        .foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(appLocalized("Configure")) { showingGeminiKeyEditor = true }.controlSize(.small)
                    Button(appLocalized("Refresh")) { fetchGeminiModels() }
                        .disabled(settings.geminiAPIKey.isEmpty)
                        .controlSize(.small)
                    Button(appLocalized("Delete"), role: .destructive) { settings.deleteGeminiConfig() }
                        .controlSize(.small).foregroundStyle(.red)
                }
                if !settings.geminiAPIKey.isEmpty {
                    Label(appLocalized("API key stored in Keychain"), systemImage: "lock.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if isFetchingGemini {
                        ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        Text(appLocalized("Fetching models…")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        switch geminiTestStatus {
                        case .idle: EmptyView()
                        case .testing:
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            Text(appLocalized("Testing…")).font(.caption).foregroundStyle(.secondary)
                        case .ok:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(appLocalizedFormat("%lld model(s) available", geminiModels.count)).font(.caption).foregroundStyle(.secondary)
                        case .failed(let msg):
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            Text(msg).font(.caption).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                }
            } header: { Text(appLocalized("Gemini")) }
        }
        .formStyle(.grouped)
        .onAppear { Task { await settings.checkOllama() }; fetchGeminiModels() }
        .sheet(isPresented: $showingURLEditor) {
            URLEditorSheet(url: $settings.ollamaBaseURL) { Task { await settings.checkOllama() } }
        }
        .sheet(isPresented: $showingGeminiKeyEditor) {
            GeminiKeyEditorSheet(settings: settings) { fetchGeminiModels() }
        }
    }


    private func fetchGeminiModels() {
        let key = settings.geminiAPIKey
        guard !key.isEmpty else { return }
        isFetchingGemini = true
        geminiTestStatus = .idle
        Task {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
                await MainActor.run { isFetchingGemini = false; geminiTestStatus = .failed(appLocalized("Network error")) }
                return
            }
            var geminiReq = URLRequest(url: url)
            geminiReq.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            guard let (data, response) = try? await URLSession.shared.data(for: geminiReq) else {
                await MainActor.run { isFetchingGemini = false; geminiTestStatus = .failed(appLocalized("Network error")) }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                    ?? appLocalizedFormat("HTTP %lld", Int64(http.statusCode))
                await MainActor.run { isFetchingGemini = false; geminiTestStatus = .failed(msg) }
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                await MainActor.run { isFetchingGemini = false; geminiTestStatus = .failed(appLocalized("Could not parse response")) }
                return
            }
            // Only include models that support generateContent
            let names = models.compactMap { m -> String? in
                guard let name = m["name"] as? String,
                      let methods = m["supportedGenerationMethods"] as? [String],
                      methods.contains("generateContent") else { return nil }
                return name.replacingOccurrences(of: "models/", with: "")
            }.sorted()
            await MainActor.run {
                geminiModels = names
                isFetchingGemini = false
                geminiTestStatus = .ok
            }
        }
    }
}

// MARK: - Gemini Key Editor Sheet

struct GeminiKeyEditorSheet: View {
    let settings: AppSettings
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appLocalized("Configure Gemini API Key")).font(.headline)
            SecureField(appLocalized("AIza..."), text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack {
                Spacer()
                Button(appLocalized("Cancel")) { dismiss() }.keyboardShortcut(.escape)
                Button(appLocalized("Save")) { settings.geminiAPIKey = draft; onSave(); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return)
                    .inactiveAwareProminentButtonForeground()
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 400)
        .onAppear { draft = settings.geminiAPIKey; focused = true }
    }
}

struct URLEditorSheet: View {
    @Binding var url: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appLocalized("Configure Ollama URL")).font(.headline)
            TextField(appLocalized("http://localhost:11434"), text: $draft).textFieldStyle(.roundedBorder).focused($focused)
            HStack {
                Spacer()
                Button(appLocalized("Cancel")) { dismiss() }.keyboardShortcut(.escape)
                Button(appLocalized("Save")) { url = draft; onSave(); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return)
                    .inactiveAwareProminentButtonForeground()
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 360)
        .onAppear { draft = url; focused = true }
    }
}
