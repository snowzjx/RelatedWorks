import SwiftUI

struct ICloudMigrationSheet: View {
    let progress: Double
    let label: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .padding(.horizontal)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .presentationDetents([.height(120)])
        .interactiveDismissDisabled()
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @State private var migrationProgress: Double? = nil
    @State private var migrationLabel = ""
    @State private var migrationError: String?

    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("Sync via iCloud Drive", isOn: Binding(
                    get: { settings.iCloudSyncEnabled },
                    set: { newValue in Task { await toggleICloud(newValue) } }
                ))
                Text("When enabled, all projects and PDFs are stored in iCloud Drive and synced across your devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: Binding(
            get: { migrationProgress != nil },
            set: { _ in }
        )) {
            ICloudMigrationSheet(progress: migrationProgress ?? 0, label: migrationLabel)
        }
        .alert("Migration Failed", isPresented: Binding(
            get: { migrationError != nil },
            set: { if !$0 { migrationError = nil } }
        )) {
            Button("OK") { migrationError = nil }
        } message: {
            Text(migrationError ?? "")
        }
    }

    private func toggleICloud(_ enable: Bool) async {
        await MainActor.run {
            migrationProgress = 0
            migrationLabel = enable ? "Copying to iCloud Drive…" : "Copying to local storage…"
        }
        do {
            if enable {
                try await store.migrateToICloud { p in
                    Task { @MainActor in migrationProgress = p }
                }
            } else {
                try await store.migrateToLocal { p in
                    Task { @MainActor in migrationProgress = p }
                }
            }
            await MainActor.run {
                settings.iCloudSyncEnabled = enable
                migrationProgress = nil
                store.reload()
            }
        } catch {
            await MainActor.run { migrationProgress = nil }
            try? await Task.sleep(nanoseconds: 400_000_000) // let sheet dismiss before alert
            await MainActor.run { migrationError = error.localizedDescription }
        }
    }
}
