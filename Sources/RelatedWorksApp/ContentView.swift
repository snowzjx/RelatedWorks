import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
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
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let dest = DeepLink.parse(url) else { return }
        switch dest {
        case .project(let pid):
            selectedProjectID = pid
        case .paper(let pid, let paperID):
            selectedProjectID = pid
            selectedPaperID = paperID
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
