import Foundation
#if canImport(RelatedWorksCore)
import RelatedWorksCore
#endif

// MARK: - Terminal

class ResultBox { var value: String = "" }

func termSize() -> (w: Int, h: Int) {
    var ws = winsize()
    guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 else { return (80, 24) }
    return (Int(ws.ws_col), Int(ws.ws_row))
}
func enableRaw()  { var t = termios(); tcgetattr(STDIN_FILENO, &t); t.c_lflag &= ~UInt(ECHO | ICANON); tcsetattr(STDIN_FILENO, TCSAFLUSH, &t) }
func disableRaw() { var t = termios(); tcgetattr(STDIN_FILENO, &t); t.c_lflag |=  UInt(ECHO | ICANON); tcsetattr(STDIN_FILENO, TCSAFLUSH, &t) }
func cls() { print("\u{1b}[2J\u{1b}[H", terminator: "") }

// ANSI helpers — visibleLen strips escape codes for width calculation
func ansi(_ code: String, _ s: String) -> String { "\u{1b}[\(code)m\(s)\u{1b}[0m" }
func bold(_ s: String)   -> String { ansi("1", s) }
func dim(_ s: String)    -> String { ansi("2", s) }
func inv(_ s: String)    -> String { ansi("7", s) }
func cyan(_ s: String)   -> String { ansi("36", s) }
func blue(_ s: String)   -> String { ansi("34", s) }
func green(_ s: String)  -> String { ansi("32", s) }
func yellow(_ s: String) -> String { ansi("33", s) }
func magenta(_ s: String)-> String { ansi("35", s) }
func red(_ s: String)    -> String { ansi("31", s) }

func visibleLen(_ s: String) -> Int {
    // strip all ESC[...m sequences
    var result = 0
    var i = s.startIndex
    while i < s.endIndex {
        if s[i] == "\u{1b}", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex, s[next] == "[" {
            i = s.index(next, offsetBy: 1, limitedBy: s.endIndex) ?? s.endIndex
            while i < s.endIndex && s[i] != "m" { i = s.index(after: i) }
            if i < s.endIndex { i = s.index(after: i) }
        } else {
            result += 1
            i = s.index(after: i)
        }
    }
    return result
}

func pad(_ s: String, to width: Int) -> String {
    let extra = max(0, width - visibleLen(s))
    return s + String(repeating: " ", count: extra)
}

// MARK: - Input

enum Key { case up, down, enter, esc, q, ctrlD, r, slash, backspace, char(Character), other }
func readKey() -> Key {
    var buf = [UInt8](repeating: 0, count: 4)
    let n = read(STDIN_FILENO, &buf, 4)
    if n == 1 {
        switch buf[0] {
        case 13, 10: return .enter
        case 27:     return .esc
        case 113:    return .q
        case 114:    return .r
        case 4:      return .ctrlD
        case 47:     return .slash
        case 127:    return .backspace
        default:
            if buf[0] >= 32 && buf[0] < 127 { return .char(Character(UnicodeScalar(buf[0]))) }
            return .other
        }
    }
    if n >= 3 && buf[0] == 27 && buf[1] == 91 {
        switch buf[2] {
        case 65: return .up
        case 66: return .down
        default: return .other
        }
    }
    return .other
}

// MARK: - Box drawing

func drawBox(title: String, rows: [String], footer: String, w: Int) {
    let inner = w - 4  // space between "│ " and " │"
    let bar = String(repeating: "─", count: w - 2)
    let sep = String(repeating: "─", count: w - 2)

    func row(_ content: String) {
        print(bold(cyan("│ ")) + pad(content, to: inner) + bold(cyan(" │")))
    }

    print(bold(cyan("┌\(bar)┐")))
    row(bold(blue(title)))
    print(bold(cyan("├\(sep)┤")))
    for r in rows { row(r) }
    print(bold(cyan("├\(sep)┤")))
    row(dim(footer))
    print(bold(cyan("└\(bar)┘")))
}

// MARK: - Menu

func menu(title: String, items: [(label: String, disabled: Bool)], footer: String = "↑↓ navigate  Enter select  q back") -> Int? {
    var sel = items.firstIndex(where: { !$0.disabled }) ?? 0
    while true {
        let (w, _) = termSize()
        cls()
        var rows: [String] = []
        for (i, item) in items.enumerated() {
            if item.disabled {
                rows.append(dim("   \(item.label)"))
            } else if i == sel {
                rows.append(inv(bold(" › ")) + inv(" \(item.label) "))
            } else {
                rows.append("   \(item.label)")
            }
        }
        drawBox(title: title, rows: rows, footer: footer, w: w)
        fflush(stdout)

        switch readKey() {
        case .up:
            var next = sel - 1
            while next >= 0 && items[next].disabled { next -= 1 }
            if next >= 0 { sel = next }
        case .down:
            var next = sel + 1
            while next < items.count && items[next].disabled { next += 1 }
            if next < items.count { sel = next }
        case .enter:
            return items[sel].disabled ? nil : sel
        case .q, .esc, .ctrlD:
            return nil
        default: break
        }
    }
}

func wordWrap(_ text: String, width: Int) -> [String] {
    var result: [String] = []
    for paragraph in text.components(separatedBy: "\n") {
        if paragraph.trimmingCharacters(in: .whitespaces).isEmpty { result.append(""); continue }
        var line = ""
        for word in paragraph.components(separatedBy: " ") {
            if line.isEmpty {
                line = word
            } else if line.count + 1 + word.count <= width {
                line += " " + word
            } else {
                result.append(line)
                line = word
            }
        }
        if !line.isEmpty { result.append(line) }
    }
    return result
}

func pager(title: String, lines: [String], footer: String = "\u{2191}\u{2193} scroll  q/Enter back") {
    _ = pagerWithKey(title: title, lines: lines, showRegenerate: false, footer: footer)
}

@discardableResult
func pagerWithKey(title: String, lines: [String], showRegenerate: Bool = false, footer: String? = nil) -> Key {
    let defaultFooter = showRegenerate ? "\u{2191}\u{2193} scroll  r regenerate  q/Enter back" : "\u{2191}\u{2193} scroll  q/Enter back"
    let resolvedFooter = footer ?? defaultFooter
    var offset = 0
    while true {
        let (w, h) = termSize()
        let pageSize = max(1, h - 6)
        let inner = w - 4
        let wrapped = lines.flatMap { wordWrap($0, width: inner) }
        cls()
        var rows: [String] = []
        let slice = wrapped[offset ..< min(offset + pageSize, wrapped.count)]
        for line in slice { rows.append(line) }
        while rows.count < pageSize { rows.append("") }
        let scrollInfo = wrapped.count > pageSize ? " [\(offset+1)-\(min(offset+pageSize, wrapped.count))/\(wrapped.count)]" : ""
        drawBox(title: title + scrollInfo, rows: rows, footer: resolvedFooter, w: w)
        fflush(stdout)

        let k = readKey()
        switch k {
        case .up:   offset = max(0, offset - 1)
        case .down: offset = min(max(0, wrapped.count - pageSize), offset + 1)
        case .q, .esc, .ctrlD, .enter: return k
        case .r where showRegenerate: return .r
        default: break
        }
    }
}

// MARK: - Screens

func projectListScreen(projects: [Project]) {
    while true {
        if projects.isEmpty {
            pager(title: "RelatedWorks", lines: [
                yellow("No projects found."), "",
                "Create a project in the macOS app first."
            ])
            return
        }
        let items = projects.map { p -> (String, Bool) in
            let tag = dim("[\(p.id.uuidString.prefix(8))]")
            let name = bold(p.name)
            let count = green("  \(p.papers.count) paper\(p.papers.count == 1 ? "" : "s")")
            return ("\(tag)  \(name)\(count)", false)
        }
        guard let idx = menu(title: "RelatedWorks — Projects", items: items, footer: "↑↓ navigate  Enter select  q quit") else { return }
        projectScreen(project: projects[idx])
    }
}

func filterPapers(_ papers: [Paper], query: String) -> [Paper] {
    let q = query.lowercased()
    guard !q.isEmpty else { return papers }
    return papers.filter { p in
        p.id.lowercased().contains(q) ||
        p.title.lowercased().contains(q) ||
        p.authors.joined(separator: " ").lowercased().contains(q) ||
        (p.venue?.lowercased().contains(q) ?? false) ||
        (p.year.map { String($0) }?.contains(q) ?? false) ||
        (p.abstract?.lowercased().contains(q) ?? false) ||
        p.annotation.lowercased().contains(q)
    }
}

func projectScreen(project: Project) {
    var filterQuery = ""
    var searching = false
    var sel = 0

    while true {
        let filtered = filterPapers(project.papers, query: filterQuery)

        // Build menu items from filtered papers
        let items: [(String, Bool)] = filtered.map { p in
            let id = cyan("[@\(p.id)]")
            let title = String(p.title.prefix(50))
            let year = dim("(\(p.year ?? 0))")
            return ("\(id)  \(title)  \(year)", false)
        }

        // Clamp selection
        sel = min(sel, items.count - 1)
        if sel < 0 { sel = 0 }
        // Skip disabled
        if sel < items.count && items[sel].1 {
            sel = items.firstIndex(where: { !$0.1 }) ?? sel
        }

        // Render
        let (w, _) = termSize()
        cls()
        let filterSuffix = filterQuery.isEmpty ? "" : "  " + yellow("[/\(filterQuery)_]")
        let titleStr = "\(bold(project.name))\(project.description.isEmpty ? "" : "  " + dim(project.description))\(filterSuffix)"
        let footer = searching
            ? "type to filter  Esc clear  Enter/↑↓ navigate"
            : "↑↓ navigate  Enter select  / search  q back"
        var rows: [String] = []
        for (i, item) in items.enumerated() {
            if item.1 {
                rows.append(dim("   \(item.0)"))
            } else if i == sel {
                rows.append(inv(bold(" › ")) + inv(" \(item.0) "))
            } else {
                rows.append("   \(item.0)")
            }
        }
        drawBox(title: titleStr, rows: rows, footer: footer, w: w)
        fflush(stdout)

        let key = readKey()

        if searching {
            switch key {
            case .char(let c):
                filterQuery.append(c)
                sel = 0
            case .backspace:
                if filterQuery.isEmpty {
                    searching = false
                } else {
                    filterQuery.removeLast()
                    sel = 0
                }
            case .esc:
                filterQuery = ""
                searching = false
            case .up:
                var next = sel - 1
                while next >= 0 && items[next].1 { next -= 1 }
                if next >= 0 { sel = next }
            case .down:
                var next = sel + 1
                while next < items.count && items[next].1 { next += 1 }
                if next < items.count { sel = next }
            case .enter:
                searching = false
                fallthrough
            default: break
            }
            continue
        }

        // Normal navigation
        switch key {
        case .slash:
            searching = true
        case .up:
            var next = sel - 1
            while next >= 0 && items[next].1 { next -= 1 }
            if next >= 0 { sel = next }
        case .down:
            var next = sel + 1
            while next < items.count && items[next].1 { next += 1 }
            if next < items.count { sel = next }
        case .enter:
            if sel < filtered.count {
                paperScreen(paper: filtered[sel], project: project)
            }
        case .q, .esc, .ctrlD:
            return
        default: break
        }
    }
}

func paperScreen(paper: Paper, project: Project) {
    while true {
        var lines: [String] = []
        lines.append(bold("Authors: ") + green(paper.authors.joined(separator: ", ")))
        lines.append(bold("Year: ") + cyan(paper.year.map(String.init) ?? "?") + "   " + bold("Venue: ") + cyan(paper.venue ?? "?"))
        if let dblpKey = paper.dblpKey {
            lines.append(bold("DBLP: ") + dim(dblpKey))
        }
        if let abstract = paper.abstract, !abstract.isEmpty {
            lines.append("")
            lines.append(yellow("── Abstract ──────────────────────────────"))
            var rem = abstract
            while !rem.isEmpty {
                lines.append(String(rem.prefix(76)))
                rem = String(rem.dropFirst(min(76, rem.count)))
            }
        }
        if !paper.annotation.isEmpty {
            lines.append("")
            lines.append(magenta("── Your Notes ────────────────────────────"))
            lines.append(paper.annotation)
        }
        let refs = project.crossReferences(for: paper.id)
        if !refs.isEmpty {
            lines.append("")
            lines.append(blue("── Cross-references (press Enter to navigate) ──"))
            for ref in refs {
                lines.append("  → " + cyan("@\(ref.id)") + ": " + String(ref.title.prefix(55)))
            }
        }
        let hasRefs = !refs.isEmpty
        pager(title: String(paper.title.prefix(55)), lines: lines,
              footer: hasRefs ? "\u{2191}\u{2193} scroll  Enter navigate refs  q back" : "\u{2191}\u{2193} scroll  q back")

        // After pager, offer cross-ref navigation if any exist
        guard hasRefs else { return }
        let refItems = refs.map { ref -> (String, Bool) in
            ("\(cyan("@\(ref.id)"))  \(String(ref.title.prefix(55)))  \(dim("(\(ref.year ?? 0))"))", false)
        }
        guard let refIdx = menu(
            title: "Navigate to cross-reference from @\(paper.id)",
            items: refItems,
            footer: "↑↓ navigate  Enter select  q back"
        ) else { return }
        paperScreen(paper: refs[refIdx], project: project)
    }
}

func generateScreen(project: Project) {
}

// MARK: - Main

