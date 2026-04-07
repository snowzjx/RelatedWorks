import Foundation
import RelatedWorksCore

// MARK: - Terminal

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

enum Key { case up, down, enter, esc, q, ctrlD, other }
func readKey() -> Key {
    var buf = [UInt8](repeating: 0, count: 4)
    let n = read(STDIN_FILENO, &buf, 4)
    if n == 1 {
        switch buf[0] {
        case 13, 10: return .enter
        case 27:     return .esc
        case 113:    return .q
        case 4:      return .ctrlD
        default:     return .other
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

// MARK: - Pager

func pager(title: String, lines: [String]) {
    var offset = 0
    while true {
        let (w, h) = termSize()
        let pageSize = max(1, h - 6)
        cls()
        var rows: [String] = []
        let slice = lines[offset ..< min(offset + pageSize, lines.count)]
        for line in slice {
            let vl = visibleLen(line)
            let inner = w - 4
            rows.append(vl > inner ? String(line.prefix(inner - 3)) + "..." : line)
        }
        while rows.count < pageSize { rows.append("") }
        let scrollInfo = lines.count > pageSize ? " [\(offset+1)-\(min(offset+pageSize, lines.count))/\(lines.count)]" : ""
        drawBox(title: title + scrollInfo, rows: rows, footer: "↑↓ scroll  q/Enter back", w: w)
        fflush(stdout)

        switch readKey() {
        case .up:          offset = max(0, offset - 1)
        case .down:        offset = min(max(0, lines.count - pageSize), offset + 1)
        case .q, .esc, .ctrlD, .enter: return
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
                "Create one with:",
                dim("  relatedworks project:create <name>")
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

func projectScreen(project: Project) {
    while true {
        var items: [(String, Bool)] = project.papers.map { p in
            let id = cyan("[@\(p.id)]")
            let title = String(p.title.prefix(50))
            let year = dim("(\(p.year ?? 0))")
            return ("\(id)  \(title)  \(year)", false)
        }
        let hasPapers = !project.papers.isEmpty
        items.append((yellow("⚡") + " Generate Related Works" + (hasPapers ? "" : dim("  (no papers)")), !hasPapers))

        guard let idx = menu(title: "\(bold(project.name))\(project.description.isEmpty ? "" : "  " + dim(project.description))", items: items) else { return }
        if idx == project.papers.count {
            generateScreen(project: project)
        } else {
            paperScreen(paper: project.papers[idx], project: project)
        }
    }
}

func paperScreen(paper: Paper, project: Project) {
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
        lines.append(blue("── Cross-references ──────────────────────"))
        for ref in refs {
            lines.append("  → " + cyan("@\(ref.id)") + ": " + String(ref.title.prefix(55)))
        }
    }
    pager(title: String(paper.title.prefix(55)), lines: lines)
}

func generateScreen(project: Project) {
    cls()
    print(bold(cyan("┌─────────────────────────────────────────┐")))
    print(bold(cyan("│ ")) + bold("Generating Related Works…") + bold(cyan("               │")))
    print(bold(cyan("│ ")) + dim("Calling Ollama, please wait…") + bold(cyan("            │")))
    print(bold(cyan("└─────────────────────────────────────────┘")))
    fflush(stdout)

    let sema = DispatchSemaphore(value: 0)
    var result = ""
    Task {
        result = await RelatedWorksGenerator.generate(for: project)
        sema.signal()
    }
    sema.wait()

    let lines = result.components(separatedBy: "\n")
    pager(title: yellow("⚡") + " Generated: \(project.name)", lines: lines.isEmpty ? [red("(no output)")] : lines)
}

// MARK: - Main

enableRaw()
defer { disableRaw(); cls() }

let store = Store()
let projects = (try? store.loadAll()) ?? []
projectListScreen(projects: projects)
