# AppleScript Support for RelatedWorks

This document defines the first version of AppleScript support for RelatedWorks.

The initial scope is intentionally small:

- Read-only access only
- No Inbox support yet
- Focus on `project` and `paper` data
- Command-based API that returns JSON text

The goal is to make RelatedWorks scriptable enough for tools like Codex to inspect a user's library, read annotations, and understand project context before we consider any write operations.

## Goals

- Let automation tools list projects and papers
- Let automation tools read project metadata and generated LaTeX
- Let automation tools read paper metadata, abstracts, and annotations
- Keep object identifiers stable so scripts remain reliable over time
- Keep the API narrow enough to be safe and easy to document

## Non-Goals for V1

- Creating, editing, or deleting projects
- Creating, editing, or deleting papers
- Triggering generation
- Inbox automation
- PDF import or export
- Full-text PDF extraction through AppleScript

## Commands

V1 uses verb-style AppleScript commands instead of a full AppleScript object model.

This keeps the implementation small and stable while still giving tools like Codex enough structured access to inspect the library.

Each command returns JSON text.

### `project summaries`

Returns a JSON array describing all projects in the library.

Example shape:

```json
[
  {
    "id": "PROJECT-UUID",
    "name": "My Paper",
    "description": "Paper description",
    "projectType": "researchPaper",
    "paperCount": 12,
    "createdAt": "2026-04-23T10:00:00Z"
  }
]
```

### `project details`

Takes a project UUID and returns a JSON object describing that project.

Example fields:

- `id`
- `name`
- `description`
- `projectType`
- `generationPrompt`
- `generatedLatex`
- `generationModel`
- `paperCount`
- `paperIDs`
- `createdAt`

### `paper summaries`

Takes a project UUID and returns a JSON array of papers in that project.

Example fields:

- `id`
- `title`
- `authors`
- `year`
- `venue`
- `hasPDF`
- `addedAt`

### `paper details`

Takes a paper semantic ID and a project UUID and returns a JSON object describing that paper.

Example fields:

- `projectID`
- `id`
- `title`
- `authors`
- `year`
- `venue`
- `dblpKey`
- `abstract`
- `annotation`
- `hasPDF`
- `pdfPath`
- `addedAt`
- `crossReferenceIDs`

## Read Path

This is enough for the first Codex-oriented read path:

1. Run `project summaries`
2. Resolve the target project UUID
3. Run `paper summaries` for that project
4. Run `paper details` only for the papers needed

## Identifier Rules

To keep scripts robust:

- Project identity should be based on UUID, not name
- Paper identity should be based on semantic ID within a project
- Names and titles may change, but IDs should remain stable

When both a human-readable field and an identifier are available, automation should resolve the identifier first and use it in later commands.

## Example Queries

The exact AppleScript syntax may vary depending on the final scripting implementation, but the intended usage should look roughly like this.

### List all projects

```applescript
tell application "RelatedWorks"
  project summaries
end tell
```

### Read one project in detail

```applescript
tell application "RelatedWorks"
  project details "PROJECT-UUID"
end tell
```

### List papers in a project

```applescript
tell application "RelatedWorks"
  paper summaries "PROJECT-UUID"
end tell
```

### Read one paper in detail

```applescript
tell application "RelatedWorks"
  paper details "Transformer" project id "PROJECT-UUID"
end tell
```

## Codex Usage Notes

This scripting surface is intended to support a future Codex skill.

The skill should prefer:

- Narrow reads over dumping the full library
- Resolving a project once, then reusing its UUID
- Resolving a paper once, then reusing its semantic ID
- Reading only the JSON payloads needed for the current task

The skill should avoid:

- Pulling every annotation in the library unless explicitly asked
- Assuming project names are unique
- Assuming paper IDs are globally unique across all projects

## Error Behavior

The scripting implementation should behave predictably when objects cannot be found.

Preferred behavior:

- Queries for unknown projects return a clear scripting error
- Queries for unknown papers return a clear scripting error
- Missing required parameters return a clear scripting error
- Optional JSON fields may be `null`

Examples of optional JSON fields:

- `year`
- `venue`
- `dblpKey`
- `abstract`
- `generatedLatex`
- `generationModel`
- `pdfPath`

## Implementation Notes

The AppleScript layer should map directly onto existing `RelatedWorksCore` models where possible:

- `Project` in [Models.swift](/Users/snow/Desktop/git/RelatedWorks/Sources/RelatedWorksCore/Models.swift)
- `Paper` in [Models.swift](/Users/snow/Desktop/git/RelatedWorks/Sources/RelatedWorksCore/Models.swift)
- persistence in [Store.swift](/Users/snow/Desktop/git/RelatedWorks/Sources/RelatedWorksCore/Store.swift)

The scripting dictionary currently lives in [RelatedWorks.sdef](/Users/snow/Desktop/git/RelatedWorks/Sources/RelatedWorksApp/RelatedWorks.sdef), and the command implementations live in [AppleScriptSupport.swift](/Users/snow/Desktop/git/RelatedWorks/Sources/RelatedWorksApp/AppleScriptSupport.swift).

The AppleScript interface should be treated as a compatibility surface. Once exposed, property names and identifier semantics should remain stable whenever possible.

## Future Extensions

Possible later additions:

- Write operations for projects and papers
- Generation commands
- Inbox access
- PDF import commands
- Export commands
- A machine-oriented helper command that returns a compact structured summary for one project

These should be added only after the read-only API is stable and documented.
