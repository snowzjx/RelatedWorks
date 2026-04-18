import SwiftUI

@main
struct RelatedWorksIOSApp: App {
    @StateObject private var settings = AppSettings.shared
    @State private var store: Store
    @State private var pendingDeepLink: DeepLink.Destination?
    @State private var showWelcomeLanding: Bool
    private let welcomeLandingKey = "didShowIOSWelcomeLanding"

    init() {
        let s = Store()
        // Import sample project on first launch
        let key = "sampleProjectImported"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            if s.projects.isEmpty,
               let url = Bundle.main.url(forResource: "SampleProject", withExtension: "relatedworks") {
                _ = try? IOSProjectImporter.import(from: url, into: s)
            }
        }
        _store = State(initialValue: s)
        _showWelcomeLanding = State(initialValue: !UserDefaults.standard.bool(forKey: welcomeLandingKey))
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            _ = Store.iCloudProjectsDir()
            guard AppSettings.shared.iCloudSyncEnabled else { return }
            try? ICloudHandleStore.publishInboxHandle()
        }
        Task.detached(priority: .utility) {
            await Self.refreshSharedICloudHandle(using: AppSettings.shared.iCloudSyncEnabled)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(pendingDeepLink: $pendingDeepLink)
                .environmentObject(store)
                .environmentObject(settings)
                .environment(\.locale, settings.locale)
                .id(settings.appLanguage.rawValue)
                .onChange(of: settings.iCloudSyncEnabled) {
                    store = Store()
                    Task {
                        await Self.refreshSharedICloudHandle(using: settings.iCloudSyncEnabled)
                    }
                }
                .onOpenURL { url in
                    pendingDeepLink = DeepLink.parse(url)
                }
                .sheet(isPresented: $showWelcomeLanding) {
                    IOSWelcomeLandingView(onContinue: markWelcomeLandingShown)
                    .environment(\.locale, settings.locale)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
        }
    }

    private static func refreshSharedICloudHandle(using enabled: Bool) async {
        if enabled {
            try? ICloudHandleStore.publishInboxHandle()
        } else {
            ICloudHandleStore.clearInboxHandle()
        }
    }

    private func markWelcomeLandingShown() {
        UserDefaults.standard.set(true, forKey: welcomeLandingKey)
        showWelcomeLanding = false
    }
}

private struct IOSWelcomeLandingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 40) {
                Image("AppLogo")
                    .resizable()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(appLocalized("Welcome to RelatedWorks"))
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 80)
            .padding(.horizontal, 60)

            VStack(alignment: .leading, spacing: 40) {
                landingItem(
                    systemImage: "desktopcomputer",
                    text: appLocalized("macOS provides full functionality. On iPhone and iPad, RelatedWorks is designed for reading papers and writing annotations.")
                )
                landingItem(
                    systemImage: "icloud",
                    text: appLocalized("iCloud sync is available, so your library stays consistent across Mac, iPhone, and iPad.")
                )
                landingItem(
                    systemImage: "square.and.arrow.up",
                    text: appLocalized("When you find a PDF in Safari or Files on iPhone/iPad, share it to RelatedWorks to send it to the Inbox on your Mac.")
                )
            }
            .padding(.top, 30)
            .padding(.horizontal, 40)

            Spacer(minLength: 24)

            Button(action: onContinue) {
                Text(appLocalized("Continue"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.35, green: 0.37, blue: 0.95))
            .clipShape(Capsule(style: .continuous))
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func landingItem(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.37, blue: 0.95))
                .frame(width: 30, alignment: .center)
                .padding(.top, 2)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
