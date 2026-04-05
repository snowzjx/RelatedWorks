# RelatedWorks

> ⚠️ This project is purely vibe coded — built entirely through AI-assisted development without traditional planning or architecture review. Expect rough edges.

A native macOS academic literature manager purpose-built for Computer Science researchers. Streamlines organizing papers, taking interconnected notes, and automatically drafting Related Works sections.

## Features

- **Project-based workspaces** — organize literature per paper you're writing
- **PDF import with AI metadata extraction** — drop a PDF and let Ollama (gemma3:4b) extract title, authors, and suggest a semantic ID
- **Global PDF deduplication** — same PDF shared across projects by content hash and title match, never duplicated
- **DBLP + arXiv search** — auto-fetches bibliographic metadata; falls back to arXiv if DBLP returns nothing, then to manual entry
- **Semantic IDs** — each paper gets a short memorable ID (e.g. `Transformer`, `BERT`) unique across the entire system
- **Cross-reference annotations** — use `@SemanticID` syntax in notes to link papers; cross-references rendered as clickable navigation
- **BibTeX management** — fetched from DBLP when available, auto-generated from metadata otherwise
- **Automated Related Works generation** — synthesizes your annotations and metadata into a LaTeX-ready draft via Ollama (qwen3)
- **Deep link support** — every paper and project has a `relatedworks://` URI for integration with tools like Hookmark
- **CLI interface** — agent-friendly command line for LLM automation

## Requirements

- macOS 13+
- [Ollama](https://ollama.com) running locally with `gemma3:4b` and `qwen3` models (for AI features)

## Building

Open `RelatedWorksApp.xcodeproj` in Xcode and build the `RelatedWorksApp` scheme, or:

```bash
xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksApp -configuration Release build
```

## Data Storage

All data is stored in `~/Library/Application Support/RelatedWorks/`:
- `projects/` — project JSON files
- `pdfs/` — deduplicated PDF library (named by semantic ID)
