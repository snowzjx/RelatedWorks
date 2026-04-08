import Foundation

#if os(macOS)

public struct ProjectExporter {

    /// Exports a project to a .relatedworks zip file at the given destination URL.
    public static func export(_ project: Project, pdfsDir: URL, to destination: URL) throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleDir = tmpDir.appendingPathComponent("\(project.name).relatedworks")
        let bundlePDFs = bundleDir.appendingPathComponent("pdfs")
        try fm.createDirectory(at: bundlePDFs, withIntermediateDirectories: true)

        // Write project.json
        let data = try JSONEncoder().encode(project)
        try data.write(to: bundleDir.appendingPathComponent("project.json"))

        // Copy PDFs
        for paper in project.papers {
            if let path = paper.pdfPath {
                let src = URL(fileURLWithPath: path)
                let dst = bundlePDFs.appendingPathComponent("\(paper.id).pdf")
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }

        // Zip using system zip command
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.arguments = ["-r", destination.path, bundleDir.lastPathComponent]
        zipProc.currentDirectoryURL = tmpDir
        try zipProc.run(); zipProc.waitUntilExit()
        guard zipProc.terminationStatus == 0 else { throw ExportError.zipFailed }
        try? fm.removeItem(at: tmpDir)
    }

    /// Imports a project from a .relatedworks zip file. Returns the imported Project.
    public static func `import`(from source: URL, into store: Store) throws -> Project {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        // Unzip using system unzip command
        let unzipProc = Process()
        unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProc.arguments = ["-q", source.path, "-d", tmpDir.path]
        try unzipProc.run(); unzipProc.waitUntilExit()

        // Find the .relatedworks bundle dir
        let contents = try fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        guard let bundleDir = contents.first(where: { $0.lastPathComponent.hasSuffix(".relatedworks") }) else {
            throw ImportError.invalidBundle
        }

        // Decode project
        let jsonData = try Data(contentsOf: bundleDir.appendingPathComponent("project.json"))
        var project = try JSONDecoder().decode(Project.self, from: jsonData)

        // Assign new UUID to avoid collision
        project = Project(importing: project, newID: UUID())

        // Copy PDFs to new project folder
        let srcPDFs = bundleDir.appendingPathComponent("pdfs")
        let dstPDFs = store.pdfsDir(for: project.id)
        try fm.createDirectory(at: dstPDFs, withIntermediateDirectories: true)

        for i in 0 ..< project.papers.count {
            let paper = project.papers[i]
            let src = srcPDFs.appendingPathComponent("\(paper.id).pdf")
            let dst = dstPDFs.appendingPathComponent("\(paper.id).pdf")
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dst)
                project.papers[i].pdfPath = dst.path
            } else {
                project.papers[i].pdfPath = nil
            }
        }

        try store.save(project)
        return project
    }

    public enum ImportError: LocalizedError {
        case invalidBundle
        public var errorDescription: String? { "Invalid .relatedworks file" }
    }

    public enum ExportError: LocalizedError {
        case zipFailed
        public var errorDescription: String? { "Failed to create zip archive" }
    }
}

#endif // os(macOS)

extension Project {
    public init(importing source: Project, newID: UUID) {
        self.id = newID
        self.name = source.name
        self.description = source.description
        self.papers = source.papers
        self.createdAt = Date()
        self.generatedLatex = source.generatedLatex
        self.generationModel = source.generationModel
        self.bibEntries = source.bibEntries
    }
}