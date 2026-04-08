import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("Sync via iCloud Drive", isOn: Binding(
                    get: { settings.iCloudSyncEnabled },
                    set: { newValue in Task { await toggleICloud(newValue) } }
                ))
                Text("When enabled, projects are read from iCloud Drive and synced across your devices. Existing local data is not moved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RelatedWorks")
                            .font(.headline)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("© 2026 Junxue ZHANG")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Link("Website", destination: URL(string: "https://snowzjx.me/RelatedWorks/")!)
            }
        }
        .navigationTitle("Settings")
    }

    private func toggleICloud(_ enable: Bool) async {
        // On iOS, just switch the setting — store reinitializes via onChange in App.swift
        await MainActor.run { settings.iCloudSyncEnabled = enable }
    }
}
