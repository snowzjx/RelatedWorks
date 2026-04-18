# AGENTS.md

This file gives repository-specific guidance to coding agents working in this project.

## Repo Overview

- `Sources/RelatedWorksCore`: shared models, storage, services, and logic used by the app and TUI.
- `Sources/RelatedWorksTUI`: Swift package executable target for the terminal UI.
- `RelatedWorksApp.xcodeproj`: Xcode project for the macOS and iOS apps.
- `Sources/RelatedWorksShareExtension`: share extension target used by the iOS/macOS PDF inbox flow.
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
- Keep version history in one canonical source on `main` as `version.md`.
- Publish the public release notes page on `gh-pages` as `version.html`.
- When updating a release, trim `README.md` and `index.html` to short summaries plus links instead of duplicating the full version history in both places.
- If version history changes, update the source note on `main` first, then regenerate or mirror the public HTML page on `gh-pages`.

## Editing Conventions

- Keep changes scoped. Avoid broad refactors unless the task requires them.
- Prefer updating tests to match current public APIs rather than preserving stale expectations.
- When touching export/import behavior, verify whether the code lives in `RelatedWorksCore`, app-only code, or iOS-specific code before changing tests.
- Preserve the existing visual language when editing the GitHub Pages site.

## Icon Update Checklist

When the app icon is updated, check all of the following instead of updating only the primary app icon source:

- App icon source files under `AppIcon.icon/`.
- Root README/site icon exports on `main`: `icon-dark.png` and `icon-light.png`.
- iOS About panel asset: `Sources/RelatedWorksIOS/Assets.xcassets/AppLogo.imageset/AppLogo-light.png` and `AppLogo-dark.png`.
- Any macOS/iOS asset catalogs that intentionally reuse the icon artwork.
- GitHub Pages assets on `gh-pages`: `icon-dark.png`, `icon-light.png`, and fallback `icon.png`.
- GitHub Pages showcase screenshots that visibly include the app icon, especially `assets/screenshots/title-page.jpg`.

Branch expectations for icon work:

- App/source/README changes belong on `main`.
- Website icons, screenshots, and page HTML belong on `gh-pages`.
- Do not leave icon-related website updates only in a `gh-pages` worktree; confirm they are committed on `gh-pages` and pushed.

Verification steps for icon work:

- Compare hashes or dimensions when replacing PNG exports so reused assets really changed.
- Check `git status --short` on both `main` and the `gh-pages` worktree before finishing.
- If the icon appears inside a screenshot, verify the composition and scale rather than only swapping the raw icon file.

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
