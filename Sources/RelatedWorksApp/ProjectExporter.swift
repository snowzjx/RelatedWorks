import Foundation

struct ProjectExporter {

    static func export(
        _ project: Project,
        pdfsDir: URL,
        to destination: URL,
        progress: (@Sendable (_ message: String, _ fractionCompleted: Double?) -> Void)? = nil
    ) throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleDir = tmpDir.appendingPathComponent("\(project.name).relatedworks")
        let bundlePDFs = bundleDir.appendingPathComponent("pdfs")
        try fm.createDirectory(at: bundlePDFs, withIntermediateDirectories: true)

        let report = progress ?? { _, _ in }
        report(appLocalized("Preparing export…"), 0.1)

        let data = try JSONEncoder().encode(project)
        try data.write(to: bundleDir.appendingPathComponent("project.json"))
        report(appLocalized("Preparing export…"), 0.25)

        let citationGraphSidecarURL = pdfsDir.deletingLastPathComponent().appendingPathComponent("citation-graph.json")
        if fm.fileExists(atPath: citationGraphSidecarURL.path) {
            let citationData = try Data(contentsOf: citationGraphSidecarURL)
            try citationData.write(to: bundleDir.appendingPathComponent("citation-graph.json"))
        }

        let pdfPapers = project.papers.filter(\.hasPDF)
        if pdfPapers.isEmpty {
            report(appLocalized("Creating archive…"), 0.8)
        }
        for (index, paper) in pdfPapers.enumerated() {
            let src = pdfsDir.appendingPathComponent("\(paper.id).pdf")
            let dst = bundlePDFs.appendingPathComponent("\(paper.id).pdf")
            if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
            let base = 0.25
            let span = 0.55
            let fraction = base + span * Double(index + 1) / Double(max(pdfPapers.count, 1))
            report(appLocalized("Copying PDFs…"), min(fraction, 0.8))
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        report(appLocalized("Creating archive…"), 0.9)
        try fm.zipItem(at: bundleDir, to: destination)
        report(appLocalized("Finishing…"), 1.0)
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
        let citationGraphURL = bundleDir.appendingPathComponent("citation-graph.json")
        if fm.fileExists(atPath: citationGraphURL.path) {
            let citationData = try Data(contentsOf: citationGraphURL)
            var graphData = try JSONDecoder().decode(CitationGraphProjectData.self, from: citationData)
            graphData.projectID = project.id
            try? store.saveCitationGraphData(graphData)
        }
        return project
    }

    enum ImportError: LocalizedError {
        case invalidBundle
        var errorDescription: String? { "Invalid .relatedworks file" }
    }
}
