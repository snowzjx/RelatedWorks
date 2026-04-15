import Foundation

// MARK: - Deep URI  (relatedworks://open?project=<uuid>&paper=<id>)

public struct DeepLink {
    public enum Destination {
        case project(UUID)
        case paper(projectID: UUID, paperID: String)
        case settings
    }

    public static func url(for project: Project) -> URL {
        URL(string: "relatedworks://open?project=\(project.id.uuidString)")!
    }

    public static func url(for paper: Paper, in project: Project) -> URL {
        URL(string: "relatedworks://open?project=\(project.id.uuidString)&paper=\(paper.id)")!
    }

    public static func settingsURL() -> URL {
        URL(string: "relatedworks://settings")!
    }

    public static func parse(_ url: URL) -> Destination? {
        guard url.scheme == "relatedworks",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        if components.host == "settings" {
            return .settings
        }

        guard let projectStr = components.queryItems?.first(where: { $0.name == "project" })?.value,
              let projectID = UUID(uuidString: projectStr) else { return nil }

        if let paperID = components.queryItems?.first(where: { $0.name == "paper" })?.value {
            return .paper(projectID: projectID, paperID: paperID)
        }
        return .project(projectID)
    }
}
