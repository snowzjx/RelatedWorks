# Version History

## v2.1.8

Released to make generation feel more responsive and improve app-to-website discovery.

- Related Works generation now streams output as it is produced instead of waiting for the full draft to finish.
- The macOS About window includes a link back to the RelatedWorks website.

## v2.1.7

Released to stabilize generation settings and polish localization.

- Preserves the selected Ollama backend across generation workflows.
- Decouples per-project prompt fallback behavior from shared settings.
- Avoids synchronous store loading in app flows.
- Standardizes annotation localization text.
- Unifies the Related Works generation implementation behind the refreshed behavior.

## v2.1.6

Released to deepen citation-awareness and external workflow integration.

- Adds a dedicated citation graph window for inspecting project references and shared outside references.
- Uses source-aware reference metadata when comparing citation relationships.
- Adds Hookmark scripting integration for linking RelatedWorks items into external knowledge workflows.

## v2.1.5

Released to improve automation and make Inbox triage faster.

- Adds a bulk Inbox import workflow for processing multiple captured PDFs.
- Adds read-only AppleScript support for inspecting projects, papers, and current selections from automation tools.

## v2.1.4

Released to smooth Finder-based project workflows.

- Supports opening exported `.relatedworks` projects directly from Finder.
- Deduplicates repeated Finder open requests so the same project is not opened multiple times.

## v2.1.3

Released to make PDF import more convenient during project work.

- Dragging a PDF onto the paper list now opens Add Paper with that PDF already loaded in the drop zone.
- Keeps the existing metadata extraction and semantic ID flow intact while removing an extra browsing step.

## v2.1.2

Released to improve generation failure handling and timeout clarity for Ollama workflows.

- Configurable Ollama request timeout in Settings.
- Friendlier timeout and failure messages during Related Works generation.
- Removed fallback template draft from error responses to keep failures explicit.
- Added missing localization entries for new timeout and backend status strings.

## v2.1.1

Released to refine the first-run experience and make long-running exports easier to follow.

- Guided first-launch onboarding with clearer step-by-step tutorial bubbles.
- Better tutorial copy and localization for the onboarding flow.
- Visible export progress feedback for project exports.
- Dedicated version history page to keep the home page focused.

## v2.1.0

Released to improve language support and iCloud PDF handling.

- Chinese (Simplified) localization for the macOS and iOS app interface.
- In-app language switcher on macOS for English, Chinese (Simplified), or Follow System.
- On-demand iCloud PDF download on macOS with automatic opening after sync.

## v2.0.0

Released to streamline capture and generation workflows.

- PDF Inbox via Share Extension on iOS and macOS for Safari and Files sharing.
- Per-project generation prompts with Survey, Research Paper, Tech Report, and Custom presets.
- Liquid Glass search box styling on macOS.
