import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var deepLinkHandler: DeepLinkHandler
    @State private var selectedProjectID: UUID?
    @State private var selectedPaperID: String?

    var selectedIndex: Int? {
        store.projects.firstIndex(where: { $0.id == selectedProjectID })
    }

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(selectedProjectID: $selectedProjectID)
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
        } detail: {
            if let idx = selectedIndex {
                ProjectDetailView(project: $store.projects[idx], externalPaperID: $selectedPaperID)
                    .id(store.projects[idx].id)
            } else {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Project Selected",
                    message: "Select or create a project to start organizing your literature."
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 620)
        .focusedValue(\.selectedProjectID, selectedProjectID)
        .onChange(of: deepLinkHandler.pending) { dest in
            guard let dest else { return }
            switch dest {
            case .project(let pid):
                selectedProjectID = pid
            case .paper(let pid, let paperID):
                selectedProjectID = pid
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    selectedPaperID = paperID
                }
            case .settings:
                break
            }
            deepLinkHandler.pending = nil
        }
    }
}

struct NoModelBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(.red).font(.caption)
            Text("No AI model configured")
                .font(.caption).foregroundStyle(.primary)
            Spacer()
            if #available(macOS 14, *) {
                NoModelBannerSettingsButton()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

@available(macOS 14, *)
private struct NoModelBannerSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button("Settings") { openSettings() }
            .font(.caption).buttonStyle(.borderless).foregroundStyle(.blue)
    }
}

extension DeepLink.Destination: Equatable {
    public static func == (lhs: DeepLink.Destination, rhs: DeepLink.Destination) -> Bool {
        switch (lhs, rhs) {
        case (.project(let a), .project(let b)): return a == b
        case (.paper(let a, let b), .paper(let c, let d)): return a == c && b == d
        case (.settings, .settings): return true
        default: return false
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
