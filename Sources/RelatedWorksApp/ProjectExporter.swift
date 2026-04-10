import Foundation

struct ProjectExporter {

    static func export(_ project: Project, pdfsDir: URL, to destination: URL) throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleDir = tmpDir.appendingPathComponent("\(project.name).relatedworks")
        let bundlePDFs = bundleDir.appendingPathComponent("pdfs")
        try fm.createDirectory(at: bundlePDFs, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(project)
        try data.write(to: bundleDir.appendingPathComponent("project.json"))

        for paper in project.papers where paper.hasPDF {
            let src = pdfsDir.appendingPathComponent("\(paper.id).pdf")
            let dst = bundlePDFs.appendingPathComponent("\(paper.id).pdf")
            if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.zipItem(at: bundleDir, to: destination)
        try? fm.removeItem(at: tmpDir)
    }

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
        project = Project(importing: project, newID: UUID())

        let srcPDFs = bundleDir.appendingPathComponent("pdfs")
        let dstPDFs = store.pdfsDir(for: project.id)
        try fm.createDirectory(at: dstPDFs, withIntermediateDirectories: true)

        for i in 0 ..< project.papers.count {
            let src = srcPDFs.appendingPathComponent("\(project.papers[i].id).pdf")
            let dst = dstPDFs.appendingPathComponent("\(project.papers[i].id).pdf")
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dst)
                project.papers[i].hasPDF = true
            } else {
                project.papers[i].hasPDF = false
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
