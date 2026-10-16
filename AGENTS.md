# Morning Operator

Read `MORE.md` at the repository root before product, UX or architecture work. It is the product reference; older demo scopes describe implementation checkpoints, not the limit of MORE's value.

Personal Apple development prototype. Shared setup, priorities and verified results are in `docs/ONBOARDING.md`, `docs/ROADMAP.md` and `docs/PHASE-ONE.md`. An optional owner-only product brief may exist at `docs/PROJECT-BRIEF.md`; it is ignored by Git and is not required for a fresh clone. Do not upload or copy it into shared documentation.

- Build real, inspectable behavior; label fixtures and unavailable capabilities.
- Keep XCTest phone control in the UI-test target, never in the ordinary app target.
- Keep inference and raw screen recordings local by default. A future Apple Private Cloud Compute route needs explicit selected-input consent, supported public APIs, a granted entitlement and the gates in `docs/APPLE-MODEL-PLAN.md`. No silent remote-model fallback; no cloud upload is enabled by this plan.
- Do not commit recordings, screenshots, inbox content, tokens, pairing secrets or signing credentials.
- The first useful slice is teach → review/edit → approve → run with local speech.
- Model output proposes actions; validated application policy decides execution.
- An ambiguous external effect must be reconciled before retrying it.
- Use Swift Package Manager tests for shared logic. Xcode/device checks are separate; do not claim they passed when only package tests ran.
- Preserve user edits and distinguish retained semantic learning from expiring raw media.
- Every new or changed feature must include French and English for app-owned UI, accessibility labels and runtime messages. Complete both catalog translations with matching interpolation and plural placeholders in the same change.
- Use `MorningCore.AppLanguage` for the chosen language, localized Foundation bundles, formatting and speech/recognition behavior. Preserve personal text and provider content in their original language.
- Verify affected behavior in both languages with checks proportionate to the change; include language switching and persistence when relevant.
- Do not modify the parent project's read-only `sources/` directory.
- Commit and push work in progress to a named remote branch after each meaningful step, even unfinished (`WIP:` commits are fine). Never end a session, or hit a usage limit, with work only on one machine. Record remaining work as GitHub issues, not only in a chat handoff.

# Task delivery

- Use a dedicated Git worktree and a named `guillaume/` branch for every task. Reuse a worktree already dedicated to that same task; otherwise create one from freshly fetched `origin/main` before editing. Preserve unrelated work in other checkouts.
- At the end of every task, commit and push all in-scope source, tests and documentation, integrate the task into `main`, resolve merge conflicts while preserving both intended behaviors, and push `main` to `origin`. A pushed task branch alone is not completed delivery.
- Fetch current `main` before integration, run checks appropriate to the combined result, and verify the remote `main` contains the delivered commit. Use a pull request when branch protection requires it. Never force-push `main` or bypass required checks.
- If access, required checks or an unresolved conflict prevent integration, keep the task branch pushed, record the precise blocker and remaining work in a GitHub issue, and report that `main` is not yet updated. Never include secrets, raw recordings or unrelated local changes in a delivery.

# Project Context

- Google configuration: `~/.config/google-cli/accounts.ini`, section `[morning-operator]`.
- Public configuration keys: `account`, `project_id`, `ios_client_id`, `callback_scheme`, `bundle_id`.
- Local Xcode overrides: `MORE_GOOGLE_CLIENT_ID` and `MORE_GOOGLE_CALLBACK_SCHEME`.
- Native iOS OAuth needs no client secret. Keep actual configuration values outside this repository.
