# RelatedWorks

<p align="center">
  <img src="icon.svg" width="120" alt="RelatedWorks icon"/>
</p>

> ⚠️ This project is purely vibe coded — built entirely through AI-assisted development without traditional planning or architecture review. Expect rough edges.

A native macOS & iOS academic literature manager for Computer Science researchers. Organize papers, take interconnected notes, and automatically draft Related Works sections.

## Features

- **Project-based workspaces** — organize literature per paper you're writing
- **PDF import with AI metadata extraction** — drop a PDF and let AI extract title, authors, and suggest a semantic ID
- **DBLP + arXiv search** — auto-fetches bibliographic metadata
- **Semantic IDs** — each paper gets a short memorable ID (e.g. `Transformer`, `BERT`)
- **Cross-reference annotations** — use `@SemanticID` syntax in notes to link papers
- **BibTeX management** — fetched from DBLP when available, auto-generated otherwise
- **Automated Related Works generation** — synthesizes annotations into a LaTeX-ready draft via AI
- **Multiple AI backends** — Ollama (local) and Google Gemini
- **Project export/import** — `.relatedworks` file containing papers, PDFs, and annotations
- **iCloud Drive sync** — sync projects across your Mac and iPhone
- **iOS companion app** — browse, search, and annotate your library on iPhone/iPad
- **Terminal UI (TUI)** — keyboard-driven workflow for SSH/headless use
- **Deep link support** — `relatedworks://` URIs for every paper and project

## Requirements

### macOS App
- macOS 13+
- At least one AI backend:
  - [Ollama](https://ollama.com) running locally, **or**
  - [Google Gemini API key](https://aistudio.google.com/apikey)

### iOS App
- iOS 17+
- No AI backend required — the iOS app is focused on reading and annotating

## Quick Start

1. **Create a project** — each project represents a paper you're writing
2. **Add papers** — import a PDF, search DBLP/arXiv, or enter manually
3. **Annotate** — write notes using `@SemanticID` to cross-reference papers
4. **Generate** — click **Generate Related Works** for a LaTeX-ready draft
5. **Export BibTeX** — fetched from DBLP or auto-generated from metadata

## iCloud Sync

Enable in **Settings → General → Sync via iCloud Drive** (macOS) or **Settings → iCloud** (iOS).

- On **macOS**: existing local data is migrated to iCloud Drive
- On **iOS**: the app switches to reading from iCloud Drive; local data is not moved

## iOS App

Browse projects, read and edit annotations, view PDFs, and navigate via deep links. Shares the same iCloud library as the macOS app when sync is enabled.

```bash
xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksIOS \
  -destination 'generic/platform=iOS' -configuration Release build
```

## Terminal UI (TUI)

```bash
# Build and run
swift run RelatedWorks

# Or use the bundled binary
./relatedworks-tui
```

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate |
| `Enter` | Select |
| `/` | Search |
| `Esc` | Back |
| `r` | Regenerate (output view) |
| `Ctrl+D` | Quit |

## Building

```bash
# macOS app
xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksApp \
  -configuration Release build

# TUI
swift build -c release --product RelatedWorks
```

## AI Backends

| Backend | Setup |
|---------|-------|
| Ollama | Install from [ollama.com](https://ollama.com), run locally |
| Gemini | API key from [Google AI Studio](https://aistudio.google.com/apikey) |

Configure in **Settings → AI Backends** and **Settings → Models**.

## Deep Links

```
relatedworks://open?project=<UUID>
relatedworks://open?project=<UUID>&paper=<SemanticID>
```

Works on both macOS and iOS.

## Data Storage

| Mode | Location |
|------|----------|
| Local | `~/Library/Application Support/RelatedWorks/projects/` |
| iCloud | `~/Library/Mobile Documents/iCloud~me~snowzjx~relatedworks/Documents/projects/` |
