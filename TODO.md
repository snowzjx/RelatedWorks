# TODO

## TUI: Per-project paper search (live filter)

**File:** `Sources/RelatedWorks/TUI.swift`  
**Function:** `projectScreen(project:)`

### Behaviour
- Press `/` in the project paper list to enter search mode
- Search filters papers live as the user types (character-by-character input loop in raw mode)
- Matches against: `id`, `title`, `authors`, `venue`, `year`, `abstract`, `annotation` (same fields as GUI)
- Matching is case-insensitive substring
- Press `Esc` or `Backspace` to clear/exit search; empty query shows all papers
- Footer hint: `/ search  ↑↓ navigate  Enter select  q back`
- When a filter is active, show the query in the box title, e.g. `ProjectName  [filter: bert]`

### Implementation sketch

```swift
// New key cases needed in `Key` enum:
case slash       // 47
case backspace   // 127
case char(Character)

// New helper: read a single printable char or control key
// (extend readKey() or add readKeyExtended())

// In projectScreen, add a `var filterQuery = ""` local var.
// On `.slash`, enter a search input loop:
//   - render the menu with current filterQuery applied
//   - on printable char: append to filterQuery, re-render
//   - on backspace: remove last char, re-render
//   - on esc: clear filterQuery, exit search mode
//   - on enter/up/down: exit search input mode, resume normal navigation with filter applied

// filteredPapers helper (mirrors GUI logic):
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
```

### Notes
- Keep the existing `menu()` helper intact; the search loop is a separate input mode layered on top
- The "Generate Related Works" item should always appear regardless of filter (it's not a paper)
- Selection index must be remapped from filtered index → original `project.papers` index before navigating to `paperScreen`
