# MORE V2: Morning and Review

**Design contract — simulator verification in progress; physical V2 and owner walkthrough pending.** Work is on `codex/more-quiet-morning`. The last verified physical-phone source is `8a640ea`; those results do not validate this redesign. [Draft PR #26](https://github.com/gibouu/morning-operator/pull/26) is stacked on pending [PR #22](https://github.com/gibouu/morning-operator/pull/22). MORE is the product naming direction; the repository and bundle identity are unchanged.

## Two places, one morning

| Morning | Review |
|---|---|
| A date, a compact routine and one clear next action. No permanent weekday strip, large marketing header or observation-review panel. | Understand the selected week, open its days and inspect a day. Previous/next controls and swipes preserve a clear return path. |
| First use offers one visible learning action. Once approved, start the routine; supported operations advance on actual completion. Pause and Stop stay reachable. | Update the routine, approve a draft, correct evidence, restore/export, inspect saved thoughts, and open settings or integrations. |
| Ordinary portrait layout fits **up to ten moments without scrolling at default text size** on the target phone. Rows show an activity and a short, honestly labeled duration or metric. | Details are progressively disclosed. Empty, one-day, partial-week and enough-data states remain distinct; no wall of metric cards. |

Morning has no inline editing. “Update my morning” opens Review. More than ten moments must have an explicit route to the remainder; no step is deleted, implicitly approved or marked complete to fit the screen. Larger Dynamic Type, smaller heights and landscape use an accessible scrolling/detail fallback instead of clipping text, hiding Stop or shrinking controls below usable size. Verify the ordinary-size fit rather than assuming it from a screenshot.

Active recording status and Stop remain available; completed observations and corrections live in Review. Apple's consent/picker remains system UI. A wake-time entry point never substitutes for a new required recording choice.

Review now keeps saved observations across imports. Its day pages distinguish observations from routine runs; **Saved observations** reaches older entries and **Date needed** handles missing observed dates. Original extraction and corrected notes are separate, with explicit day/zone/origin assignment and scoped deletion. The compact Morning gains no archive controls or counters. Routine preferences also stay in Review: editing a moment can keep it in later suggestions or remember its planned minutes; removing a row distinguishes this draft from future exclusion. Saved choices can be cleared without changing the current morning. These are explicit choices, not inferred habits. These dated glimpses still do not establish comparable full mornings or observed-habit averages.

## Native presentation

Use SwiftUI's native tab bar and control styles. Apply Liquid Glass selectively to controls, leaving content readable; use `GlassEffectContainer` when custom glass controls should interact. Prefer system transitions over custom tab-bar offsets or imitation blur. [Apple's Liquid Glass guide](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer).

Review may use `.tabBarMinimizeBehavior(.onScrollDown)` on supported iPhone UI. Let the system control minimization and restoration; this API does not promise a particular left/right movement or equivalent behavior on other devices. [tabBarMinimizeBehavior(_:)](https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)), [TabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior).

Respect Reduce Motion and Reduce Transparency, meaningful VoiceOver labels, readable contrast and accessible period navigation. Reduced-transparency content should use an opaque treatment. [Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion), [Reduce Transparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency).

## What a number means

- **Planned minutes** belong to the approved routine or an unapproved proposal; they are estimates.
- **Recorded routine time** comes from Morning Operator's session events, excludes pauses where stated and becomes unknown after interrupted timing. It does not measure other apps or time saved.
- **Observed app activity** requires connected, timestamped evidence and its own coverage. Configured Shortcuts callbacks are partial entries/returns, not pickups, dwell time, reels or reading intent.
- **Typical observed morning** requires comparable evidence days and per-metric denominators. Until that collector/profile exists, show the plan or real run history with those names. Missing values stay unknown; samples remain outside personal averages.

The compact design does not complete multi-day learning. [#21](https://github.com/gibouu/morning-operator/issues/21) owns valid metrics and [#11](https://github.com/gibouu/morning-operator/issues/11) owns adaptive profiles.

## Completion and voice

There is no Notes destination. A saved completed morning offers **Speak**, **Write** and **Not now**. With read-aloud enabled, a brief spoken invitation can accompany that offer; it never starts the microphone. Speak explicitly opens one English or French dictation turn, while Write opens the existing editor. Not now dismisses the invitation without changing the completed run.

Dictation requires on-device recognition and allows up to **30 seconds of input plus three seconds for a final result**, bounded to 4,000 characters. Playback must release audio ownership before listening, and microphone ownership must release before the words enter review. The final text opens an editable thought/dream/reminder/calendar draft; nothing is saved or sent to an Apple app until the person explicitly saves that reviewed draft. Saved voice-origin captures show **Spoken with MORE** under **Review → Saved thoughts**. The app keeps no audio file; the unsaved transcript and review remain in memory.

Cancel, backgrounding or a changed completed session invalidates the listening attempt and its late callbacks. A canceled turn cannot later open review or save a thought. Permission failures retain the typed route, and unresolved microphone cleanup blocks new audio until released. This is one explicit dictation turn, separate from routine commands and foreground Siri capture; it does not provide an always-listening keyword or an open conversation. The three synthetic completion-flow checks pass, as does the existing command-entry check. Physical microphone, recognition and audio-route behavior remain unverified. The editor keyboard transition emits an unresolved layout warning; see [verification](PHASE-ONE.md).

Voice settings live under Review. The existing stored choice is an optional `voiceIdentifier`: **Automatic** when empty, or a selected installed Apple voice. Current source ranks Automatic by device locale/dialect, language and reported quality; unavailable selections fall back to Automatic. The chooser excludes Personal/Novelty and non-Apple providers. Preview/Stop and a genuinely paused Resume state are distinct. There is no stored rate, pitch or custom language preference; speech uses Apple's default rate. The current read-aloud and hands-free preferences remain separate from voice selection.

An explicit [push-to-listen command turn](VOICE.md) now has native source and simulator compilation. Real microphone recognition remains unverified. Custom voice enrollment, guaranteed Siri voice, a full conversational recap and audible HomePod output remain future work. The owner has not confirmed hearing the earlier phone checks. Unsupported routine operations still wait for a real user/adaptor outcome; speech finishing does not prove an external task was performed. [#4](https://github.com/gibouu/morning-operator/issues/4), [#6](https://github.com/gibouu/morning-operator/issues/6), [#20](https://github.com/gibouu/morning-operator/issues/20).

## Before calling V2 ready

Compare two concrete directions with the same states, then check first use; an approved ten-moment morning; active/paused/completed/stopped runs; empty and partial history; observation correction/relaunch; recording/error recovery; Review editing/approval/restoration; and completion capture. Verify default portrait fit, landscape, large text, VoiceOver, reduced motion/transparency and native tab-bar minimization. An owner walkthrough must find Start, Stop, the latest result and a correction without instruction.

Record actual source/build/device and outcomes in [PHASE-ONE](PHASE-ONE.md). The [default GitHub homepage](https://github.com/gibouu/morning-operator) now points to the current iPhone branch and its guides after the README-only update `4e610449c5de480344dcfaaf44b9413bf1b1bd3c`. App code on `main` remains the earlier scaffold; the current implementation is still under review in stacked [PR #26](https://github.com/gibouu/morning-operator/pull/26) and [PR #22](https://github.com/gibouu/morning-operator/pull/22). The prior phone baseline remains readable on the [earlier PR branch](https://github.com/gibouu/morning-operator/blob/codex/morning-timeline-iphone/docs/PHASE-ONE.md). This contract does not claim every GitHub issue is complete. [V2 issue #25](https://github.com/gibouu/morning-operator/issues/25).
