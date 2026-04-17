import UIKit
import UniformTypeIdentifiers
import CryptoKit

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private var didStart = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = String(localized: "Preparing PDF for RelatedWorks Inbox…")

        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        Task { await handleShare() }
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
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SharedPDFFile, Error>) in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
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
                    try data.write(to: copiedURL, options: .atomic)
                    let preferredFilename: String
                    if let suggestedName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !suggestedName.isEmpty {
                        preferredFilename = self.normalizedPDFFilename(suggestedName)
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

    private func resolveInboxDirectory() throws -> URL {
        try ICloudHandleStore.resolveInboxHandle()
    }

    private func buildInboxItem(from url: URL, originalFilename: String) throws -> InboxItem {
        InboxItem(
            originalFilename: originalFilename,
            source: .shareExtension,
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

    private func normalizedPDFFilename(_ filename: String?) -> String {
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
            self.statusLabel.text = message
            guard success else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}

private struct SharedPDFFile {
    let url: URL
    let originalFilename: String
}

private enum ShareError: LocalizedError {
    case noPDFFound

    var errorDescription: String? {
        switch self {
        case .noPDFFound:
            return "No PDF attachment was found."
        }
    }
}
