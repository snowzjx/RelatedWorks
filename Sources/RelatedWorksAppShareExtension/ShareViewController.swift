import AppKit
import CryptoKit
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: String(localized: "Preparing PDF for RelatedWorks Inbox…"))
    private let closeButton = NSButton(title: String(localized: "Close"), target: nil, action: nil)
    private var didStart = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        preferredContentSize = NSSize(width: 420, height: 160)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.isSelectable = false
        statusLabel.isBezeled = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.cell?.wraps = true
        statusLabel.cell?.isScrollable = false
        statusLabel.cell?.lineBreakMode = .byWordWrapping
        statusLabel.font = .systemFont(ofSize: 13)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeButtonTapped)
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .regular
        closeButton.keyEquivalent = "\r"

        let stackView = NSStackView(views: [statusLabel, closeButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 18

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        Task {
            await handleShare()
        }
    }

    private func handleShare() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) else {
            finish(with: String(localized: "Only PDF files can be sent to RelatedWorks Inbox."), success: false)
            return
        }

        do {
            let sharedFile = try await loadPDF(from: provider)
            let inboxURL = try resolveInboxDirectory()
            let inboxItem = try buildInboxItem(from: sharedFile.url, originalFilename: sharedFile.originalFilename)

            if let existing = try existingInboxItem(in: inboxURL, matching: inboxItem.contentHash) {
                finish(with: String(format: String(localized: "\"%@\" is already in RelatedWorks Inbox."), existing.originalFilename), success: true)
                return
            }

            let pdfDestination = inboxURL.appendingPathComponent("\(inboxItem.id.uuidString).pdf")
            let metadataDestination = inboxURL.appendingPathComponent("\(inboxItem.id.uuidString).json")

            if FileManager.default.fileExists(atPath: pdfDestination.path) {
                try FileManager.default.removeItem(at: pdfDestination)
            }
            if FileManager.default.fileExists(atPath: metadataDestination.path) {
                try FileManager.default.removeItem(at: metadataDestination)
            }

            try FileManager.default.copyItem(at: sharedFile.url, to: pdfDestination)
            let data = try JSONEncoder().encode(inboxItem)
            try data.write(to: metadataDestination, options: .atomic)

            finish(with: String(localized: "Saved to RelatedWorks Inbox."), success: true)
        } catch {
            finish(with: error.localizedDescription, success: false)
        }
    }

    private func loadPDF(from provider: NSItemProvider) async throws -> SharedPDFFile {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let sharedFile = try await loadPDFFileURL(from: provider) {
            return sharedFile
        }

        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareError.noPDFFound)
                    return
                }

                let copiedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                do {
                    try FileManager.default.createDirectory(
                        at: copiedURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if FileManager.default.fileExists(atPath: copiedURL.path) {
                        try FileManager.default.removeItem(at: copiedURL)
                    }
                    try FileManager.default.copyItem(at: url, to: copiedURL)

                    let preferredFilename: String
                    let sourceFilename = url.deletingPathExtension().lastPathComponent.isEmpty ? nil : url.lastPathComponent
                    if let sourceFilename = sourceFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !sourceFilename.isEmpty {
                        preferredFilename = Self.normalizedPDFFilename(sourceFilename)
                    } else if let suggestedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !suggestedName.isEmpty {
                        preferredFilename = Self.normalizedPDFFilename(suggestedName)
                    } else {
                        preferredFilename = "Document.pdf"
                    }
                    continuation.resume(returning: SharedPDFFile(url: copiedURL, originalFilename: preferredFilename))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadPDFFileURL(from provider: NSItemProvider) async throws -> SharedPDFFile? {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sourceURL: URL?
                switch item {
                case let url as URL:
                    sourceURL = url
                case let data as Data:
                    sourceURL = URL(dataRepresentation: data, relativeTo: nil)
                case let nsURL as NSURL:
                    sourceURL = nsURL as URL
                default:
                    sourceURL = nil
                }

                guard let sourceURL else {
                    continuation.resume(returning: nil)
                    return
                }

                guard sourceURL.pathExtension.lowercased() == "pdf" else {
                    continuation.resume(returning: nil)
                    return
                }

                let copiedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")

                do {
                    try FileManager.default.createDirectory(
                        at: copiedURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if FileManager.default.fileExists(atPath: copiedURL.path) {
                        try FileManager.default.removeItem(at: copiedURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: copiedURL)

                    let originalFilename: String
                    let sourceName = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sourceName.isEmpty {
                        originalFilename = Self.normalizedPDFFilename(sourceName)
                    } else if let suggestedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !suggestedName.isEmpty {
                        originalFilename = Self.normalizedPDFFilename(suggestedName)
                    } else {
                        originalFilename = "Document.pdf"
                    }

                    continuation.resume(returning: SharedPDFFile(url: copiedURL, originalFilename: originalFilename))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func resolveInboxDirectory() throws -> URL {
        do {
            return try InboxHandleStore.resolveInboxHandle()
        } catch InboxHandleStore.HandleError.notPublished {
            throw ShareError.inboxUnavailable
        }
    }

    private func buildInboxItem(from url: URL, originalFilename: String) throws -> InboxItem {
        InboxItem(
            originalFilename: originalFilename,
            source: .macShareExtension,
            contentHash: sha256(url)
        )
    }

    private func existingInboxItem(in inboxURL: URL, matching hash: String?) throws -> InboxItem? {
        guard let hash else { return nil }
        let files = try FileManager.default.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)
        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let item = try? JSONDecoder().decode(InboxItem.self, from: data) else {
                continue
            }
            if item.contentHash == hash {
                return item
            }
        }
        return nil
    }

    private static func normalizedPDFFilename(_ filename: String?) -> String {
        let trimmed = filename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Document.pdf" }
        if trimmed.lowercased().hasSuffix(".pdf") {
            return trimmed
        }
        return "\(trimmed).pdf"
    }

    private func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func finish(with message: String, success: Bool) {
        DispatchQueue.main.async {
            self.statusLabel.stringValue = message
        }
    }

    @objc private func closeButtonTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct SharedPDFFile {
    let url: URL
    let originalFilename: String
}

private enum ShareError: LocalizedError {
    case noPDFFound
    case inboxUnavailable

    var errorDescription: String? {
        switch self {
        case .noPDFFound:
            return "No PDF attachment was found."
        case .inboxUnavailable:
            return "Open RelatedWorks once so it can publish the inbox location, then try sharing again."
        }
    }
}
