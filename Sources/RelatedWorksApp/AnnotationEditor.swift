import SwiftUI
import AppKit

struct AnnotationEditor: NSViewRepresentable {
    @Binding var text: String
    let paperIDs: [String]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = .systemFont(ofSize: NSFont.systemFontSize)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.string = text
        context.coordinator.textView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        let tv = scrollView.documentView as! NSTextView
        if tv.string != text { tv.string = text }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnnotationEditor
        weak var textView: NSTextView?
        var panel: NSPanel?
        var tableView: NSTableView?
        var currentItems: [String] = []
        var currentAtIndex = 0
        var currentTypedLength = 0
        var isEditing = false

        init(_ parent: AnnotationEditor) { self.parent = parent }

        func textDidBeginEditing(_ notification: Notification) { isEditing = true }
        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            if let tv = notification.object as? NSTextView { parent.text = tv.string }
            dismissPanel()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            checkForMention(in: tv)
        }

        // Intercept keys while panel is visible
        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard panel?.isVisible == true, let table = tableView else { return false }

            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                let row = table.selectedRow >= 0 ? table.selectedRow : 0
                guard row < currentItems.count else { return false }
                insertMention(currentItems[row], in: tv)
                dismissPanel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                let next = min(table.selectedRow + 1, currentItems.count - 1)
                table.selectRowIndexes([next], byExtendingSelection: false)
                return true
            case #selector(NSResponder.moveUp(_:)):
                let prev = max(table.selectedRow - 1, 0)
                table.selectRowIndexes([prev], byExtendingSelection: false)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                dismissPanel(); return true
            default:
                return false
            }
        }

        // MARK: - Mention detection

        private func checkForMention(in tv: NSTextView) {
            let str = tv.string as NSString
            let cursor = tv.selectedRange().location
            guard cursor > 0 else { dismissPanel(); return }

            var i = cursor - 1
            while i > 0 {
                let c = str.character(at: i)
                if c == "@".utf16.first! { break }
                if c == " ".utf16.first! || c == "\n".utf16.first! { dismissPanel(); return }
                i -= 1
            }
            guard str.character(at: i) == "@".utf16.first! else { dismissPanel(); return }

            let typed = str.substring(with: NSRange(location: i + 1, length: cursor - i - 1)).lowercased()
            let matches = parent.paperIDs.filter { typed.isEmpty || $0.lowercased().hasPrefix(typed) }
            guard !matches.isEmpty else { dismissPanel(); return }

            currentAtIndex = i
            currentTypedLength = cursor - i
            showPanel(matches: matches, in: tv)
        }

        private func showPanel(matches: [String], in tv: NSTextView) {
            currentItems = matches

            // Build panel once
            if panel == nil {
                let p = NSPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
                p.isFloatingPanel = true
                p.becomesKeyOnlyIfNeeded = true
                p.hasShadow = true
                p.backgroundColor = .controlBackgroundColor

                let table = NSTableView()
                let col = NSTableColumn(identifier: .init("id"))
                col.width = 196
                table.addTableColumn(col)
                table.headerView = nil
                table.rowHeight = 24
                table.dataSource = self
                table.delegate = self
                table.backgroundColor = .controlBackgroundColor
                table.selectionHighlightStyle = .regular
                table.target = self
                table.action = #selector(tableClicked)

                let sv = NSScrollView()
                sv.documentView = table
                sv.hasVerticalScroller = false
                sv.drawsBackground = false
                p.contentView = sv

                panel = p
                tableView = table
            }

            tableView?.reloadData()
            if !matches.isEmpty { tableView?.selectRowIndexes([0], byExtendingSelection: false) }

            // Position below the '@' character
            guard let lm = tv.layoutManager, let tc = tv.textContainer,
                  let window = tv.window else { return }

            let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: currentAtIndex, length: 1),
                                            actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            rect.origin.x += tv.textContainerOrigin.x
            rect.origin.y += tv.textContainerOrigin.y

            let inWindow = tv.convert(rect, to: nil)
            let inScreen = window.convertToScreen(inWindow)

            let rowH: CGFloat = 24
            let panelH = min(CGFloat(matches.count) * rowH + 4, 160)
            let panelW: CGFloat = 200
            let origin = NSPoint(x: inScreen.minX, y: inScreen.minY - panelH - 2)
            panel!.setFrame(NSRect(x: origin.x, y: origin.y, width: panelW, height: panelH), display: true)
            panel!.contentView?.frame = NSRect(origin: .zero, size: NSSize(width: panelW, height: panelH))

            if panel!.parent == nil { window.addChildWindow(panel!, ordered: .above) }
            panel!.orderFront(nil)
        }

        @objc private func tableClicked() {
            guard let table = tableView, table.clickedRow >= 0,
                  table.clickedRow < currentItems.count,
                  let tv = textView else { return }
            insertMention(currentItems[table.clickedRow], in: tv)
            dismissPanel()
        }

        private func insertMention(_ id: String, in tv: NSTextView) {
            let text = "@\(id) "
            tv.textStorage?.replaceCharacters(in: NSRange(location: currentAtIndex, length: currentTypedLength), with: text)
            tv.setSelectedRange(NSRange(location: currentAtIndex + text.count, length: 0))
            parent.text = tv.string
        }

        func dismissPanel() {
            if let p = panel, let parent = p.parent { parent.removeChildWindow(p) }
            panel?.orderOut(nil)
        }
    }
}

extension Coordinator: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { currentItems.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let f = NSTextField(labelWithString: "@\(currentItems[row])")
        f.font = .systemFont(ofSize: 13)
        f.textColor = .labelColor
        return f
    }
}

// Make Coordinator accessible for NSTableView extensions
typealias Coordinator = AnnotationEditor.Coordinator
