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
        } detail: {
            if let idx = selectedIndex {
                ProjectDetailView(project: $store.projects[idx], externalPaperID: $selectedPaperID)
                    .id(store.projects[idx].id)
            } else {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Project Selected",
                    message: "Create a project to start organizing your literature."
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 620)
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
            }
            deepLinkHandler.pending = nil
        }
    }
}

struct OllamaBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Ollama not running")
                .font(.caption).foregroundStyle(.primary)
            Spacer()
            Button("Settings") { openAppSettings() }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

extension DeepLink.Destination: Equatable {
    static func == (lhs: DeepLink.Destination, rhs: DeepLink.Destination) -> Bool {
        switch (lhs, rhs) {
        case (.project(let a), .project(let b)): return a == b
        case (.paper(let a, let b), .paper(let c, let d)): return a == c && b == d
        default: return false
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
