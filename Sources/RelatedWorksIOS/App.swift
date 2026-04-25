import SwiftUI

@MainActor
final class IOSAppLaunchCoordinator: ObservableObject {
    @Published private(set) var store: Store?
    @Published private(set) var progress = Store.StartupProgress(
        completedUnitCount: 0,
        totalUnitCount: 4,
        message: appLocalized("Starting RelatedWorks")
    )
    private var launchTask: Task<Void, Never>?

    private enum DefaultsKey {
        static let sampleProjectImported = "sampleProjectImported"
    }

    func launch() {
        guard store == nil else { return }
        guard launchTask == nil else { return }

        launchTask = Task {
            defer { launchTask = nil }
            let snapshot = await Store.prepareStartupSnapshot { progress in
                Task { @MainActor in
                    self.progress = progress
                }
            }
            guard !Task.isCancelled else { return }
            let loadedStore = Store(startupSnapshot: snapshot)
            importSampleProjectIfNeeded(into: loadedStore)
            self.store = loadedStore
        }
    }

    func reload() {
        launchTask?.cancel()
        launchTask = nil
        store = nil
        progress = Store.StartupProgress(
            completedUnitCount: 0,
            totalUnitCount: 4,
            message: appLocalized("Reloading library")
        )
        launch()
    }

    private func importSampleProjectIfNeeded(into store: Store) {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.sampleProjectImported) else { return }

        UserDefaults.standard.set(true, forKey: DefaultsKey.sampleProjectImported)
        guard store.projects.isEmpty,
              let url = Bundle.main.url(forResource: "SampleProject", withExtension: "relatedworks") else {
            return
        }

        _ = try? IOSProjectImporter.import(from: url, into: store)
    }
}

@main
struct RelatedWorksIOSApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var launchCoordinator = IOSAppLaunchCoordinator()
    @State private var pendingDeepLink: DeepLink.Destination?
    @State private var showWelcomeLanding: Bool
    private let welcomeLandingKey = "didShowIOSWelcomeLanding"

    init() {
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
            Group {
                if let store = launchCoordinator.store {
                    RootView(pendingDeepLink: $pendingDeepLink)
                        .environmentObject(store)
                } else {
                    IOSAppLaunchView(coordinator: launchCoordinator)
                }
            }
                .environmentObject(settings)
                .environment(\.locale, settings.locale)
                .id(settings.appLanguage.rawValue)
                .onChange(of: settings.iCloudSyncEnabled) {
                    launchCoordinator.reload()
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
                .task {
                    launchCoordinator.launch()
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

private struct IOSAppLaunchView: View {
    @ObservedObject var coordinator: IOSAppLaunchCoordinator

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text(appLocalized("Loading Library"))
                    .font(.headline)
                Text(coordinator.progress.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: coordinator.progress.fractionCompleted)
                .progressViewStyle(.linear)
                .frame(width: 260)

            Text(String(
                format: appLocalized("%lld of %lld"),
                coordinator.progress.completedUnitCount,
                coordinator.progress.totalUnitCount
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
