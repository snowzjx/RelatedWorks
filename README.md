# RelatedWorks

> ⚠️ This project is purely vibe coded — built entirely through AI-assisted development without traditional planning or architecture review. Expect rough edges.

A native macOS academic literature manager purpose-built for Computer Science researchers. Streamlines organizing papers, taking interconnected notes, and automatically drafting Related Works sections.

## Features

- **Project-based workspaces** — organize literature per paper you're writing
- **PDF import with AI metadata extraction** — drop a PDF and let Ollama extract title, authors, and suggest a semantic ID
- **Global PDF deduplication** — same PDF shared across projects by content hash and title match, never duplicated
- **DBLP + arXiv search** — auto-fetches bibliographic metadata; falls back to arXiv if DBLP returns nothing, then to manual entry
- **Semantic IDs** — each paper gets a short memorable ID (e.g. `Transformer`, `BERT`) unique across the entire system
- **Cross-reference annotations** — use `@SemanticID` syntax in notes to link papers; cross-references rendered as clickable navigation
- **BibTeX management** — fetched from DBLP when available, auto-generated from metadata otherwise
- **Metadata editing** — right-click any paper to edit title, authors, year, venue, and abstract; local BibTeX regenerated automatically
- **Automated Related Works generation** — synthesizes your annotations and metadata into a LaTeX-ready draft via Ollama; shows which model was used
- **Terminal UI (TUI)** — full interactive TUI for keyboard-driven workflow and SSH/headless use
- **Deep link support** — every paper and project has a `relatedworks://` URI for integration with tools like Hookmark
- **Preferences panel** — configure font size, Ollama base URL, and choose extraction/generation models from a live model list

## Requirements

- macOS 13+
- [Ollama](https://ollama.com) running locally (configure models in Preferences)

## Usage

### 1. Create a Project

Each project represents a paper you're writing. Click the **+** button in the sidebar to create a new project and give it a name.

### 2. Add Papers

There are three ways to add papers to a project:

- **Import PDF** — drag a PDF onto the paper list or use the import button. Ollama will automatically extract the title, authors, year, and suggest a semantic ID.
- **Search DBLP / arXiv** — use the search bar to find a paper by title or keywords. Metadata is fetched automatically; if DBLP has no results it falls back to arXiv.
- **Manual entry** — enter metadata by hand if the paper isn't indexed online.

### 3. Assign a Semantic ID

Every paper gets a short memorable ID (e.g. `Transformer`, `BERT`, `GPT4`). This ID is unique across all projects and is used to cross-reference papers in your notes.

### 4. Take Notes & Cross-Reference

Open a paper and write your annotation notes in the editor. Use `@SemanticID` syntax to link to other papers — they render as clickable links for quick navigation.

### 5. Generate Related Works

Once you've annotated your papers, click **Generate Related Works** in the project view. RelatedWorks will synthesize your notes and paper metadata into a LaTeX-ready draft using Ollama. The model used is shown alongside the output.

### 6. Export BibTeX

BibTeX entries are fetched from DBLP automatically, or generated from metadata when unavailable. Copy individual entries from the paper detail view.

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
| `↑` / `↓` | Navigate items |
| `Enter` / `Space` | Select |
| `r` | Regenerate Related Works (in output view) |
| `q` / `Esc` | Go back |
| `Ctrl+D` | Quit |

The TUI shares the same data as the GUI — generated Related Works, annotations, and paper metadata are all in sync.

## Building

### GUI (macOS App)

Open `RelatedWorksApp.xcodeproj` in Xcode and build the `RelatedWorksApp` scheme, or:

```bash
xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksApp -configuration Release build
```

### TUI (Terminal)

```bash
swift build -c release --product RelatedWorks
```

## Preferences

Open via **RelatedWorksApp → Settings…** (`⌘,`):

- **General** — font size slider with live preview
- **AI Backend** — Ollama base URL, extraction model (for PDF metadata), generation model (for Related Works); model lists are fetched live from Ollama. A status banner appears in the sidebar if Ollama is unreachable and auto-dismisses when it comes back online. Custom generation prompt instructions can be edited here.

## Deep Links

Every project and paper has a `relatedworks://` URI. Copy it from the paper detail view via the "Copy Link" button.

```
relatedworks://open?project=<UUID>
relatedworks://open?project=<UUID>&paper=<SemanticID>
```

```bash
open "relatedworks://open?project=<UUID>&paper=BERT"
```

## Data Storage

All data is stored in `~/Library/Application Support/RelatedWorks/`:
- `projects/` — project JSON files
- `pdfs/` — deduplicated PDF library (named by semantic ID)
