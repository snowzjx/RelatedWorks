# AGENT.md

This file gives repository-specific guidance to coding agents working in this project.

## Repo Overview

- `Sources/RelatedWorksCore`: shared models, storage, services, and logic used by the app and TUI.
- `Sources/RelatedWorksTUI`: Swift package executable target for the terminal UI.
- `RelatedWorksApp.xcodeproj`: Xcode project for the macOS and iOS apps.
- `Tests/RelatedWorksTests`: Swift Testing suite for `RelatedWorksCore`.

## Build And Test

Prefer the smallest command that validates the change you made.

- Core tests: `swift test`
- TUI build: `swift build -c release --product RelatedWorksTUI`
- macOS app build: `xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksApp -configuration Release build`
- iOS app build: `xcodebuild -project RelatedWorksApp.xcodeproj -scheme RelatedWorksIOS -destination 'generic/platform=iOS' -configuration Release build`

Notes:

- `swift test` exercises only the Swift package targets. It does not cover app-only code under `Sources/RelatedWorksApp`.
- Some tests and builds may require running outside a sandbox because Swift/Xcode writes caches under the user library.
- Do not run multiple `xcodebuild` commands in parallel against the same default derived data location. Xcode can fail with a locked build database.

## Branch And Release Workflow

- Treat `main` as the application source branch.
- Treat `gh-pages` as the GitHub Pages branch.
- Do not put GitHub Pages site changes on `main`.
- Website updates such as `index.html`, `privacy.html`, page assets, and screenshot galleries belong on `gh-pages`.

## Editing Conventions

- Keep changes scoped. Avoid broad refactors unless the task requires them.
- Prefer updating tests to match current public APIs rather than preserving stale expectations.
- When touching export/import behavior, verify whether the code lives in `RelatedWorksCore`, app-only code, or iOS-specific code before changing tests.
- Preserve the existing visual language when editing the GitHub Pages site.

## Commit Style

Recent history uses conventional commit prefixes:

- `fix:`
- `feat:`
- `docs:`
- `refactor:`

Match that style for new commits. Keep messages concise and focused on the user-visible or code-level outcome.

## Practical Reminders

- Check `git status --short` before committing so you do not accidentally include generated files.
- The working tree may contain Xcode or SwiftPM build artifacts; stage only the files relevant to the task.
- If a task involves screenshots for the GitHub Pages site, use optimized web-sized assets rather than shipping full-resolution source PNGs.
