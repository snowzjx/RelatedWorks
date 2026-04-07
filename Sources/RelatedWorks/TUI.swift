import Foundation
import RelatedWorksCore

// MARK: - Terminal helpers

func termSize() -> (w: Int, h: Int) {
    var ws = winsize()
    guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 else { return (80, 24) }
    return (Int(ws.ws_col), Int(ws.ws_row))
}

func enableRaw() {
    var t = termios()
    tcgetattr(STDIN_FILENO, &t)
    t.c_lflag &= ~UInt(ECHO | ICANON)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
}

func disableRaw() {
    var t = termios()
    tcgetattr(STDIN_FILENO, &t)
    t.c_lflag |= UInt(ECHO | ICANON)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
}

func cls() { print("\u{1b}[2J\u{1b}[H", terminator: "") }
func moveTo(_ row: Int, _ col: Int) { print("\u{1b}[\(row);\(col)H", terminator: "") }
func bold(_ s: String) -> String { "\u{1b}[1m\(s)\u{1b}[0m" }
func dim(_ s: String) -> String { "\u{1b}[2m\(s)\u{1b}[0m" }
func inv(_ s: String) -> String { "\u{1b}[7m\(s)\u{1b}[0m" }
func cyan(_ s: String) -> String { "\u{1b}[36m\(s)\u{1b}[0m" }
func yellow(_ s: String) -> String { "\u{1b}[33m\(s)\u{1b}[0m" }

func readKey() -> Key {
    var buf = [UInt8](repeating: 0, count: 4)
    let n = read(STDIN_FILENO, &buf, 4)
    if n == 1 {
        switch buf[0] {
        case 13, 10: return .enter
        case 27:     return .esc
        case 113:    return .q       // q
        case 4:      return .ctrlD
        default:     return .other(buf[0])
        }
    }
    if n >= 3 && buf[0] == 27 && buf[1] == 91 {
        switch buf[2] {
        case 65: return .up
        case 66: return .down
        case 67: return .right
        case 68: return .left
        default: return .other(0)
        }
    }
    return .other(0)
}

enum Key { case up, down, left, right, enter, esc, q, ctrlD, other(UInt8) }

// MARK: - Menu helper

func menu(title: String, items: [String], footer: String = "") -> Int? {
    var sel = 0
    while true {
        let (w, _) = termSize()
        cls()
        let bar = String(repeating: "─", count: w - 2)
        print(bold(cyan("┌\(bar)┐")))
        let pad = max(0, w - 4 - title.count)
        print(bold(cyan("│ ")) + bold(title) + String(repeating: " ", count: pad) + bold(cyan(" │")))
        print(bold(cyan("├\(bar)┤")))
        for (i, item) in items.enumerated() {
            let line = i == sel ? inv(" › \(item)") : "   \(item)"
            let visible = i == sel ? item.count + 4 : item.count + 3
            let pad2 = max(0, w - 2 - visible)
            print(bold(cyan("│")) + line + String(repeating: " ", count: pad2) + bold(cyan("│")))
        }
        print(bold(cyan("├\(bar)┤")))
        let hint = footer.isEmpty ? "↑↓ navigate  Enter select  q quit" : footer
        let hpad = max(0, w - 4 - hint.count)
        print(bold(cyan("│ ")) + dim(hint) + String(repeating: " ", count: hpad) + bold(cyan(" │")))
        print(bold(cyan("└\(bar)┘")))
        fflush(stdout)

        switch readKey() {
        case .up:    sel = max(0, sel - 1)
        case .down:  sel = min(items.count - 1, sel + 1)
        case .enter: return sel
        case .q, .ctrlD, .esc: return nil
        default: break
        }
    }
}

func pager(title: String, lines: [String]) {
    let (w, h) = termSize()
    let pageSize = h - 6
    var offset = 0
    while true {
        cls()
        let bar = String(repeating: "─", count: w - 2)
        print(bold(cyan("┌\(bar)┐")))
        let tpad = max(0, w - 4 - title.count)
        print(bold(cyan("│ ")) + bold(title) + String(repeating: " ", count: tpad) + bold(cyan(" │")))
        print(bold(cyan("├\(bar)┤")))
        let visible = lines[offset ..< min(offset + pageSize, lines.count)]
        for line in visible {
            let truncated = line.count > w - 4 ? String(line.prefix(w - 7)) + "..." : line
            let lpad = max(0, w - 4 - truncated.count)
            print(bold(cyan("│ ")) + truncated + String(repeating: " ", count: lpad) + bold(cyan(" │")))
        }
        // fill empty rows
        let empty = pageSize - visible.count
        for _ in 0 ..< empty {
            print(bold(cyan("│")) + String(repeating: " ", count: w - 2) + bold(cyan("│")))
        }
        print(bold(cyan("├\(bar)┤")))
        let hint = "↑↓ scroll  q back"
        let hpad = max(0, w - 4 - hint.count)
        print(bold(cyan("│ ")) + dim(hint) + String(repeating: " ", count: hpad) + bold(cyan(" │")))
        print(bold(cyan("└\(bar)┘")))
        fflush(stdout)

        switch readKey() {
        case .up:   offset = max(0, offset - 1)
        case .down: offset = min(max(0, lines.count - pageSize), offset + 1)
        case .q, .esc, .ctrlD, .enter: return
        default: break
        }
    }
}

// MARK: - Screens

func projectListScreen(projects: [Project]) {
    while true {
        if projects.isEmpty {
            pager(title: "RelatedWorks", lines: ["No projects found.", "", "Create one with:", "  relatedworks project:create <name>"])
            return
        }
        let items = projects.map { "[\($0.id.uuidString.prefix(8))]  \($0.name)  (\($0.papers.count) paper\($0.papers.count == 1 ? "" : "s"))" }
        guard let idx = menu(title: "RelatedWorks — Projects", items: items) else { return }
        projectScreen(project: projects[idx])
    }
}

func projectScreen(project: Project) {
    while true {
        var items = project.papers.map { "[@\($0.id)]  \(String($0.title.prefix(55)))  (\($0.year ?? 0))" }
        items.append("⚡ Generate Related Works")
        guard let idx = menu(title: project.name, items: items, footer: "↑↓ navigate  Enter select  q back") else { return }
        if idx == project.papers.count {
            generateScreen(project: project)
        } else {
            paperScreen(paper: project.papers[idx], project: project)
        }
    }
}

func paperScreen(paper: Paper, project: Project) {
    var lines: [String] = []
    lines.append(bold("Authors:") + " \(paper.authors.joined(separator: ", "))")
    lines.append(bold("Year:") + " \(paper.year.map(String.init) ?? "?")   " + bold("Venue:") + " \(paper.venue ?? "?")")
    if let abstract = paper.abstract, !abstract.isEmpty {
        lines.append("")
        lines.append(yellow("── Abstract ──"))
        // wrap at 76 chars
        var remaining = abstract
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(76))
            lines.append(chunk)
            remaining = String(remaining.dropFirst(chunk.count))
        }
    }
    if !paper.annotation.isEmpty {
        lines.append("")
        lines.append(yellow("── Your Notes ──"))
        lines.append(paper.annotation)
    }
    let refs = project.crossReferences(for: paper.id)
    if !refs.isEmpty {
        lines.append("")
        lines.append(yellow("── Cross-references ──"))
        for ref in refs { lines.append("  → @\(ref.id): \(String(ref.title.prefix(60)))") }
    }
    pager(title: String(paper.title.prefix(60)), lines: lines)
}

func generateScreen(project: Project) {
    cls()
    print(bold(cyan("Generating Related Works for '\(project.name)'...")))
    print(dim("Please wait..."))
    fflush(stdout)

    let sema = DispatchSemaphore(value: 0)
    var result = ""
    Task {
        result = await RelatedWorksGenerator.generate(for: project)
        sema.signal()
    }
    sema.wait()

    var lines = result.components(separatedBy: "\n")
    pager(title: "Generated: \(project.name)", lines: lines.isEmpty ? ["(no output)"] : lines)
}

// MARK: - Main

enableRaw()
defer { disableRaw(); cls() }

let store = Store()
let projects = (try? store.loadAll()) ?? []
projectListScreen(projects: projects)
