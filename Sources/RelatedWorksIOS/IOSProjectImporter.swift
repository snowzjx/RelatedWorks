import Foundation

struct IOSProjectImporter {
    @discardableResult
    static func `import`(from source: URL, into store: Store) throws -> Project {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        try fm.unzipItem(at: source, to: tmpDir)

        let contents = try fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        guard let bundleDir = contents.first(where: { $0.lastPathComponent.hasSuffix(".relatedworks") }) else {
            throw ImportError.invalidBundle
        }

        let jsonData = try Data(contentsOf: bundleDir.appendingPathComponent("project.json"))
        var project = try JSONDecoder().decode(Project.self, from: jsonData)

        // Assign new UUID if a project with this ID already exists
        if store.projects.contains(where: { $0.id == project.id }) {
            project = Project(importing: project, newID: UUID())
        }

        let srcPDFs = bundleDir.appendingPathComponent("pdfs")
        let dstPDFs = store.pdfsDir(for: project.id)
        try fm.createDirectory(at: dstPDFs, withIntermediateDirectories: true)

        for i in 0..<project.papers.count {
            let src = srcPDFs.appendingPathComponent("\(project.papers[i].id).pdf")
            let dst = dstPDFs.appendingPathComponent("\(project.papers[i].id).pdf")
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

    enum ImportError: LocalizedError {
        case invalidBundle
        var errorDescription: String? { "Invalid .relatedworks file" }
    }
}
