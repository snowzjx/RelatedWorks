#if os(macOS)
import Foundation
import PDFKit

// MARK: - PDF Import & AI Extraction

public struct PDFImporter {

    /// Extracts metadata using Ollama LLM, falls back to heuristics.
    public static func extractMetadata(from pdfURL: URL, takenIDs: Set<String> = []) async -> ExtractedMetadata {
        guard let doc = PDFDocument(url: pdfURL) else { return .empty }

        // Extract first ~3 pages of text
        var rawText = ""
        for i in 0..<min(3, doc.pageCount) {
            rawText += doc.page(at: i)?.string ?? ""
        }

        // Only send title + abstract region to AI (stop before Introduction)
        let focusedText = extractTitleAndAbstractRegion(from: rawText)

        // Try AI extraction first
        if let meta = try? await extractWithAI(text: focusedText, takenIDs: takenIDs) {
            return meta
        }
        // Fallback to heuristics
        return extractHeuristic(from: rawText, pdfDoc: doc)
    }

    /// Extracts just the title+abstract region, stopping at Introduction or body text.
    private static func extractTitleAndAbstractRegion(from text: String) -> String {
        let stopPattern = #"(?i)\n\s*\d*\.?\s*(1\.?\s+introduction|introduction\n|related work|ccs concepts|keywords\n)"#
        if let stopRange = text.range(of: stopPattern, options: .regularExpression) {
            return String(text[..<stopRange.lowerBound])
        }
        return String(text.prefix(2000))
    }

    // MARK: - AI Extraction via Ollama

    private static func extractWithAI(text: String, takenIDs: Set<String> = []) async throws -> ExtractedMetadata {
        let takenNote = takenIDs.isEmpty ? "" : "\nThese IDs are already taken, do NOT use them: \(takenIDs.sorted().joined(separator: ", "))"
        let prompt = """
        Extract metadata from this academic paper text. Reply with ONLY valid JSON, no explanation.

        JSON format:
        {
          "title": "full paper title",
          "authors": ["Author One", "Author Two"],
          "abstract": "abstract text only, no figure captions or body text, max 3 sentences",
          "suggestedID": "short memorable name (e.g. acronym or system name like BERT, Transformer, ResNet)"
        }
        \(takenNote)

        Paper text:
        \(text)
        """

        let backend = AppSettings.shared.extractionBackendInstance()
        let response = try await backend.generate(prompt: prompt)

        return try parseAIResponse(response)
    }

    private static func parseAIResponse(_ response: String) throws -> ExtractedMetadata {
        // Extract JSON block from response (model may wrap it in markdown)
        let jsonString: String
        if let start = response.range(of: "{"), let end = response.range(of: "}", options: .backwards) {
            jsonString = String(response[start.lowerBound...end.lowerBound])
        } else {
            jsonString = response
        }

        guard let data = jsonString.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        let title = obj["title"] as? String ?? ""
        let authors = obj["authors"] as? [String] ?? []
        let abstract = obj["abstract"] as? String
        let suggestedID = obj["suggestedID"] as? String ?? suggestID(from: title)

        return ExtractedMetadata(title: title, authors: authors, abstract: abstract, suggestedID: suggestedID)
    }

    // MARK: - Heuristic Fallback

    private static func extractHeuristic(from text: String, pdfDoc: PDFDocument) -> ExtractedMetadata {
        let attrs = pdfDoc.documentAttributes ?? [:]
        let metaTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String
        let metaAuthor = attrs[PDFDocumentAttribute.authorAttribute] as? String

        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let title = metaTitle ?? lines.first(where: { $0.count > 10 && $0.count < 200 }) ?? ""
        let authors: [String] = metaAuthor.map { [$0] } ?? []
        let abstract = extractAbstract(from: text)

        return ExtractedMetadata(title: title, authors: authors, abstract: abstract, suggestedID: suggestID(from: title))
    }

    private static func extractAbstract(from text: String) -> String? {
        let lower = text.lowercased()
        guard let start = lower.range(of: "abstract") else { return nil }
        let after = String(text[start.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Stop at next section header
        let sectionPattern = #"(?i)\n\s*\d*\.?\s*(introduction|related work|background|conclusion|references|acknowledgement|1\s+introduction)"#
        if let stopRange = after.range(of: sectionPattern, options: .regularExpression) {
            return String(after[..<stopRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback: cap at 1500 chars
        let cutoff = after.index(after.startIndex, offsetBy: min(1500, after.count))
        return String(after[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func suggestID(from title: String) -> String {
        let stop: Set<String> = ["a","an","the","of","in","on","for","with","and","or","to",
                                  "is","are","via","using","based","towards","learning","deep",
                                  "neural","network","networks","model","models","large","language"]
        let words = title.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stop.contains($0.lowercased()) }
        if let acronym = words.first(where: { $0 == $0.uppercased() && $0.count >= 2 && $0.count <= 8 }) {
            return acronym
        }
        return words.first ?? "Paper"
    }
}

public struct ExtractedMetadata {
    public let title: String
    public let authors: [String]
    public let abstract: String?
    public let suggestedID: String

    static let empty = ExtractedMetadata(title: "", authors: [], abstract: nil, suggestedID: "Paper")
}
#endif // os(macOS)