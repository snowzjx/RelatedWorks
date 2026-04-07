# RelatedWorks

<p align="center">
  <img src="icon.svg" width="120" alt="RelatedWorks icon"/>
</p>

> ⚠️ This project is purely vibe coded — built entirely through AI-assisted development without traditional planning or architecture review. Expect rough edges.

A native macOS academic literature manager purpose-built for Computer Science researchers. Streamlines organizing papers, taking interconnected notes, and automatically drafting Related Works sections.

## Features

- **Project-based workspaces** — organize literature per paper you're writing
- **PDF import with AI metadata extraction** — drop a PDF and let AI extract title, authors, and suggest a semantic ID
- **Global PDF deduplication** — same PDF shared across projects by content hash and title match, never duplicated
- **DBLP + arXiv search** — auto-fetches bibliographic metadata; falls back to arXiv if DBLP returns nothing, then to manual entry
- **Semantic IDs** — each paper gets a short memorable ID (e.g. `Transformer`, `BERT`) unique across the entire system
- **Cross-reference annotations** — use `@SemanticID` syntax in notes to link papers; cross-references rendered as clickable navigation
- **BibTeX management** — fetched from DBLP when available, auto-generated from metadata otherwise
- **Metadata editing** — right-click any paper to edit title, authors, year, venue, and abstract
- **Automated Related Works generation** — synthesizes your annotations and metadata into a LaTeX-ready draft via AI
- **Multiple AI backends** — supports Ollama (local) and Google Gemini; configure per operation
- **Project export/import** — export a project (papers, PDFs, annotations) as a `.relatedworks` file; import on any machine
- **Terminal UI (TUI)** — full interactive TUI for keyboard-driven workflow and SSH/headless use
- **Live search / filter** — search papers by ID, title, authors, venue, year, abstract, or annotation with match highlighting (GUI + TUI)
- **Deep link support** — every paper and project has a `relatedworks://` URI for integration with tools like Hookmark
- **Preferences panel** — configure font size, AI backends, models, and generation prompt

## Requirements

- macOS 13+
- At least one AI backend configured:
  - [Ollama](https://ollama.com) running locally (recommended for privacy), **or**
  - [Google Gemini API key](https://aistudio.google.com/apikey)

## Usage

### 1. Create a Project

Each project represents a paper you're writing. Click the **+** button in the sidebar to create a new project and give it a name.

### 2. Add Papers

- **Import PDF** — drag a PDF onto the paper list. AI will automatically extract title, authors, year, and suggest a semantic ID.
- **Search DBLP / arXiv** — use the search bar to find a paper by title or keywords.
- **Manual entry** — enter metadata by hand if the paper isn't indexed online.

### 3. Assign a Semantic ID

Every paper gets a short memorable ID (e.g. `Transformer`, `BERT`, `GPT4`), used to cross-reference papers in your notes.

### 4. Take Notes & Cross-Reference

Write annotation notes in the editor. Use `@SemanticID` syntax to link to other papers — they render as clickable links.

### 5. Generate Related Works

Click **Generate Related Works** in the project view. RelatedWorks synthesizes your notes and paper metadata into a LaTeX-ready draft using your configured AI backend.

### 6. Export BibTeX

BibTeX entries are fetched from DBLP automatically, or generated from metadata when unavailable.

### 7. Export / Import Project

Right-click a project in the sidebar → **Export…** to save a `.relatedworks` file containing all papers, PDFs, annotations and generated output. Use **File → Import Project…** (`⌘⇧I`) to import on any machine.

## Terminal UI (TUI)

RelatedWorks ships a full interactive TUI — useful for keyboard-driven workflows, SSH sessions, or when you prefer staying in the terminal.

### Launch

```bash
# GUI app
open RelatedWorks.app

# TUI (bundled binary in release zip)
./relatedworks-tui

# Or build from source
swift run RelatedWorks
```

### Navigation

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate items / scroll |
| `Enter` | Select / navigate to cross-referenced paper |
| `/` | Enter live search/filter mode (in project view) |
| `Esc` | Clear search / go back |
| `r` | Regenerate Related Works (in output view only) |
| `q` / `Esc` | Go back |
| `Ctrl+D` | Quit |

The TUI shares the same data as the GUI — generated Related Works, annotations, and paper metadata are all in sync.

## AI Backends

Configure in **Settings → AI Backends** and **Settings → Models**.

| Backend | Setup | Notes |
|---------|-------|-------|
| Ollama | Install from [ollama.com](https://ollama.com), run locally | Private, no API key needed |
| Gemini | Get API key from [Google AI Studio](https://aistudio.google.com/apikey) | Cloud-based, use `gemini-2.5-flash` |

You can configure different backends for PDF extraction and Related Works generation independently.

## Building

### GUI (macOS App)

```bash
xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksApp -configuration Release build
```

### TUI (Terminal)

```bash
swift build -c release --product RelatedWorks
```

## Preferences

Open via **RelatedWorksApp → Settings…** (`⌘,`):

- **General** — font size
- **Models** — choose backend (Ollama/Gemini/None) and model per operation; edit generation prompt
- **AI Backends** — configure Ollama URL and Gemini API key; test connections

## Deep Links

```
relatedworks://open?project=<UUID>
relatedworks://open?project=<UUID>&paper=<SemanticID>
```

## Data Storage

All data is stored in `~/Library/Application Support/RelatedWorks/`:
- `projects/` — project JSON files
- `pdfs/` — deduplicated PDF library
