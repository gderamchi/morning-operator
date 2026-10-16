# French and English in MORE

MORE has exactly two app languages: **Français** and **English**, selected in Settings → Language. The selection is persisted independently of routine/workspace data. The first system language determines the initial choice when it is French or English; any other language starts in French. There is no third “automatic” option.

`MorningCore.AppLanguage` is the common source for SwiftUI, Foundation string catalogs, date/number formatting, local model instructions, speech recognition, command interpretation and speech synthesis. SwiftUI receives its locale and observes the shared choice. Foundation strings select the matching catalog bundle explicitly so existing process bundle preferences cannot keep them in the previous language.

## Data and external boundaries

Changing the language never rewrites saved routine titles/details, personal notes, original recordings/OCR, mail or message contents, account/calendar names, provider names, website content, protocol identifiers, API argument values or provider documentation. New built-in examples use the selected language. Historical source labels and the structural serialization markers inside original learning evidence remain part of that evidence; they are not reinterpreted or migrated.

Provider pages and Apple-owned interface text follow their own language rules. MORE's permission descriptions live in `InfoPlist.xcstrings`; shortcut metadata and phrases live in `Localizable.xcstrings` and `AppShortcuts.xcstrings`. MORE saves its language as the app's bundle language for the next process launch, but cannot force another app, Siri's configured language or an external OAuth page. Runtime intent results and app-owned alarm labels use the selected language explicitly. Live Activity payloads carry a backwards-compatible language field so the widget does not infer the app preference from the extension's separate defaults.

Known connection-service error codes are mapped to app-controlled explanations. Raw provider diagnostic text is not displayed as interface copy. Framework errors without a typed app explanation use a localized fallback that does not expose private paths or request diagnostics.

## Speech and changing language

Installed voice choices are filtered by the app language, including search results. A saved unavailable or incompatible voice identifier is repaired to the automatic compatible choice. Speech never falls back to a voice in the other language. Recognition remains local and uses the same choice; command grammar and local model response instructions follow it too.

Changing language pauses an active morning, stops speech/listening, invalidates cached generated prose, refreshes local presentation and leaves source data, pending drafts, recipients, action receipts and uncertain-operation journals intact. It does not restart the routine, authorize an action, repeat a provider effect or request permission automatically. A partial dictation is retained for editable local review. Resuming remains an explicit user action.

## Integration baseline

The localization branch was created in a separate managed worktree from `2a6e3c1` on `guillaume/routine-automation`. This includes the current Home redesign, Google Calendar/Calendly/Outlook integration and learning work committed at creation. The owner checkout was never reset, stashed, modified or built. Committed integration updates through `753609c` were merged. To preserve the newer Home playback/caption layout and Screen Time selection work, a reviewed source-only snapshot of 21 Swift files was integrated from the unchanged owner checkout (2026-10-16 00:08:26 UTC, base `753609c`, SHA-256 `80f4edd26df8f849251d7cb292113605779f53d372497e8f3f51361ee4c841e3`). Private/config files, AGENTS and generated project files were excluded; the project was regenerated here. The snapshot was subsequently reconciled with the actual parent commits `9089ff0` (Screen Time) and `0334b89` (Home), including the latest caption anchors and exact-identity retention fix. Those commits are now ancestors of this branch. The physical phone, its existing routine, grants and authorized test draft were not controlled by this workstream.

The PR targets the routine integration branch to keep the localization change reviewable without replacing the recent connector work with an older main-branch UI.

## Verification

See the pull request for the final commands and observed results. Package tests are separate from Xcode builds and simulator journeys. Simulator synthetic fixtures do not prove physical speaker audibility, live speech recognition, Siri invocation, provider login, or external effects. A signed candidate, if available, is prepared locally without installing it on the reserved phone. Raw screenshots, test workspaces, signing configuration and result bundles stay outside Git.
