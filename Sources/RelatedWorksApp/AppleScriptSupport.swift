import AppKit
import Foundation

final class RelatedWorksScriptBridge {
    static let shared = RelatedWorksScriptBridge()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let lock = NSLock()
    private var store: Store?

    private init() {}

    func setStore(_ store: Store?) {
        lock.lock()
        self.store = store
        lock.unlock()
    }

    func projectSummariesJSON() throws -> String {
        try withStore { store in
            let payload = store.projects.map { project in
                ProjectSummaryPayload(project: project)
            }
            return try self.encode(payload)
        }
    }

    func projectDetailsJSON(projectID rawProjectID: String) throws -> String {
        let projectID = try parseProjectID(rawProjectID)
        return try withStore { store in
            guard let project = store.projects.first(where: { $0.id == projectID }) else {
                throw RelatedWorksScriptError.projectNotFound(rawProjectID)
            }
            return try self.encode(ProjectDetailsPayload(project: project))
        }
    }

    func paperSummariesJSON(projectID rawProjectID: String) throws -> String {
        let projectID = try parseProjectID(rawProjectID)
        return try withStore { store in
            guard let project = store.projects.first(where: { $0.id == projectID }) else {
                throw RelatedWorksScriptError.projectNotFound(rawProjectID)
            }
            let payload = project.papers.map { paper in
                PaperSummaryPayload(paper: paper)
            }
            return try self.encode(payload)
        }
    }

    func paperDetailsJSON(projectID rawProjectID: String, paperID rawPaperID: String) throws -> String {
        let projectID = try parseProjectID(rawProjectID)
        let paperID = rawPaperID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !paperID.isEmpty else {
            throw RelatedWorksScriptError.invalidPaperID(rawPaperID)
        }

        return try withStore { store in
            guard let project = store.projects.first(where: { $0.id == projectID }) else {
                throw RelatedWorksScriptError.projectNotFound(rawProjectID)
            }
            guard let paper = project.paper(withID: paperID) else {
                throw RelatedWorksScriptError.paperNotFound(paperID, rawProjectID)
            }
            return try self.encode(PaperDetailsPayload(project: project, paper: paper))
        }
    }

    private func parseProjectID(_ rawProjectID: String) throws -> UUID {
        let trimmed = rawProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let projectID = UUID(uuidString: trimmed) else {
            throw RelatedWorksScriptError.invalidProjectID(rawProjectID)
        }
        return projectID
    }

    private func withStore<T>(_ body: (Store) throws -> T) throws -> T {
        if Thread.isMainThread {
            return try withStoreOnMain(body)
        }

        var result: Result<T, Error>!
        DispatchQueue.main.sync {
            result = Result { try self.withStoreOnMain(body) }
        }
        return try result.get()
    }

    private func withStoreOnMain<T>(_ body: (Store) throws -> T) throws -> T {
        lock.lock()
        let store = self.store
        lock.unlock()

        guard let store else {
            throw RelatedWorksScriptError.libraryUnavailable
        }

        return try body(store)
    }

    fileprivate func currentStore() throws -> Store {
        lock.lock()
        let store = self.store
        lock.unlock()

        guard let store else {
            throw RelatedWorksScriptError.libraryUnavailable
        }

        return store
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        do {
            let data = try encoder.encode(value)
            guard let json = String(data: data, encoding: .utf8) else {
                throw RelatedWorksScriptError.encodingFailed
            }
            return json
        } catch let error as RelatedWorksScriptError {
            throw error
        } catch {
            throw RelatedWorksScriptError.encodingFailed
        }
    }
}

private enum RelatedWorksScriptError: LocalizedError {
    case libraryUnavailable
    case invalidProjectID(String)
    case invalidPaperID(String)
    case projectNotFound(String)
    case paperNotFound(String, String)
    case missingParameter(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return "RelatedWorks is still loading the library. Try again after the app finishes launching."
        case .invalidProjectID(let rawProjectID):
            return "Invalid project UUID: \(rawProjectID)"
        case .invalidPaperID(let rawPaperID):
            return "Invalid paper ID: \(rawPaperID)"
        case .projectNotFound(let rawProjectID):
            return "Project not found for UUID: \(rawProjectID)"
        case .paperNotFound(let rawPaperID, let rawProjectID):
            return "Paper '\(rawPaperID)' was not found in project \(rawProjectID)"
        case .missingParameter(let name):
            return "Missing AppleScript parameter: \(name)"
        case .encodingFailed:
            return "RelatedWorks could not encode the scripting result as JSON."
        }
    }

    var number: Int {
        switch self {
        case .libraryUnavailable:
            return 1
        case .invalidProjectID:
            return 2
        case .invalidPaperID:
            return 3
        case .projectNotFound:
            return 4
        case .paperNotFound:
            return 5
        case .missingParameter:
            return 6
        case .encodingFailed:
            return 7
        }
    }
}

private struct ProjectSummaryPayload: Encodable {
    let id: String
    let name: String
    let description: String
    let projectType: String
    let paperCount: Int
    let createdAt: Date

    init(project: Project) {
        id = project.id.uuidString
        name = project.name
        description = project.description
        projectType = project.projectType.rawValue
        paperCount = project.papers.count
        createdAt = project.createdAt
    }

    init(_ project: Project) {
        self.init(project: project)
    }
}

private struct ProjectDetailsPayload: Encodable {
    let id: String
    let name: String
    let description: String
    let projectType: String
    let generationPrompt: String
    let generatedLatex: String?
    let generationModel: String?
    let paperCount: Int
    let paperIDs: [String]
    let createdAt: Date

    init(project: Project) {
        id = project.id.uuidString
        name = project.name
        description = project.description
        projectType = project.projectType.rawValue
        generationPrompt = project.generationPrompt
        generatedLatex = project.generatedLatex
        generationModel = project.generationModel
        paperCount = project.papers.count
        paperIDs = project.papers.map(\.id)
        createdAt = project.createdAt
    }
}

private struct PaperSummaryPayload: Encodable {
    let id: String
    let title: String
    let authors: [String]
    let year: Int?
    let venue: String?
    let hasPDF: Bool
    let addedAt: Date

    init(paper: Paper) {
        id = paper.id
        title = paper.title
        authors = paper.authors
        year = paper.year
        venue = paper.venue
        hasPDF = paper.hasPDF
        addedAt = paper.addedAt
    }

    init(_ paper: Paper) {
        self.init(paper: paper)
    }
}

private struct PaperDetailsPayload: Encodable {
    let projectID: String
    let id: String
    let title: String
    let authors: [String]
    let year: Int?
    let venue: String?
    let dblpKey: String?
    let abstract: String?
    let annotation: String
    let hasPDF: Bool
    let pdfPath: String?
    let addedAt: Date
    let crossReferenceIDs: [String]

    init(project: Project, paper: Paper) {
        let store = try? RelatedWorksScriptBridge.shared.currentStore()
        projectID = project.id.uuidString
        id = paper.id
        title = paper.title
        authors = paper.authors
        year = paper.year
        venue = paper.venue
        dblpKey = paper.dblpKey
        abstract = paper.abstract
        annotation = paper.annotation
        hasPDF = paper.hasPDF
        if paper.hasPDF, let store {
            let pdfURL = store.pdfURL(for: paper.id, projectID: project.id)
            pdfPath = FileManager.default.fileExists(atPath: pdfURL.path) ? pdfURL.path : nil
        } else {
            pdfPath = nil
        }
        addedAt = paper.addedAt
        crossReferenceIDs = project.crossReferences(for: paper.id).map(\.id)
    }
}

@objc(RWBaseScriptCommand)
class RWBaseScriptCommand: NSScriptCommand {
    func stringParameter(named name: String) throws -> String {
        let arguments = evaluatedArguments
        guard let value = arguments?[name] as? String else {
            throw RelatedWorksScriptError.missingParameter(name)
        }
        return value
    }

    func resolve(_ work: () throws -> String) -> Any? {
        do {
            return try work()
        } catch let error as RelatedWorksScriptError {
            scriptErrorNumber = error.number
            scriptErrorString = error.localizedDescription
            return nil
        } catch {
            scriptErrorNumber = -1
            scriptErrorString = error.localizedDescription
            return nil
        }
    }
}

@objc(RWProjectSummariesScriptCommand)
final class RWProjectSummariesScriptCommand: RWBaseScriptCommand {
    override func performDefaultImplementation() -> Any? {
        resolve {
            try RelatedWorksScriptBridge.shared.projectSummariesJSON()
        }
    }
}

@objc(RWProjectDetailsScriptCommand)
final class RWProjectDetailsScriptCommand: RWBaseScriptCommand {
    override func performDefaultImplementation() -> Any? {
        resolve {
            guard let projectID = directParameter as? String else {
                throw RelatedWorksScriptError.missingParameter("direct parameter")
            }
            return try RelatedWorksScriptBridge.shared.projectDetailsJSON(projectID: projectID)
        }
    }
}

@objc(RWPaperSummariesScriptCommand)
final class RWPaperSummariesScriptCommand: RWBaseScriptCommand {
    override func performDefaultImplementation() -> Any? {
        resolve {
            guard let projectID = directParameter as? String else {
                throw RelatedWorksScriptError.missingParameter("direct parameter")
            }
            return try RelatedWorksScriptBridge.shared.paperSummariesJSON(projectID: projectID)
        }
    }
}

@objc(RWPaperDetailsScriptCommand)
final class RWPaperDetailsScriptCommand: RWBaseScriptCommand {
    override func performDefaultImplementation() -> Any? {
        resolve {
            guard let paperID = directParameter as? String else {
                throw RelatedWorksScriptError.missingParameter("direct parameter")
            }
            let projectID = try stringParameter(named: "projectID")
            return try RelatedWorksScriptBridge.shared.paperDetailsJSON(projectID: projectID, paperID: paperID)
        }
    }
}
