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
- **Deep link support** — every paper and project has a `relatedworks://` URI for integration with tools like Hookmark
- **CLI interface** — agent-friendly command line for LLM automation
- **Preferences panel** — configure font size, Ollama base URL, and choose extraction/generation models from a live model list

## Requirements

- macOS 13+
- [Ollama](https://ollama.com) running locally (configure models in Preferences)

## Building

Open `RelatedWorksApp.xcodeproj` in Xcode and build the `RelatedWorksApp` scheme, or:

```bash
xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksApp -configuration Release build
```

## Preferences

Open via **RelatedWorksApp → Settings…** (`⌘,`):

- **General** — font size slider with live preview
- **AI Backend** — Ollama base URL, extraction model (for PDF metadata), generation model (for Related Works); model lists are fetched live from Ollama. A status banner appears in the sidebar if Ollama is unreachable and auto-dismisses when it comes back online.

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
