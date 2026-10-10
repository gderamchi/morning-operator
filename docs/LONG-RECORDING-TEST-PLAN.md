# Long recordings: acceptance plan

This is a test plan, not a completed result. The next ingestion change must let a saved recording produce a bounded, reviewable suggestion without asking the person to trim thousands of extracted characters. Current physical-phone installation and long-recording inference still need separate verification. Use [PHASE-ONE](PHASE-ONE.md) for actual results and source revisions.

The acceptance journey is simple: explicitly record or select a recording, let MORE save the evidence, review what it understood, and request a routine update. The existing routine stays in place until approval. Large input must not become a giant error panel, silent data loss, or permission to invent the unsampled morning.

## Keep the limits distinct

| Boundary | What the test must establish |
|---|---|
| Recording/import | The selected file passes the supported duration and file-size limits. Test the actual configured boundary separately from prompt length. Current import permits up to 31 minutes and 512 MiB; the native recording choices are 5/10/20/30 minutes. |
| Source extraction | At most 24 sampled frames and the existing OCR/archive bounds remain explicit. A source beyond the OCR budget retains diagnostic samples and truncation warnings. No claim of exhaustive video understanding follows. |
| Saved evidence | The original bounded extraction, frame IDs, times, available recording provenance and source fingerprint survive save/relaunch. Selecting less text for analysis must not rewrite the saved original. |
| Inference | Each request and the total work stay within documented limits. Record submitted characters, calls, selected source ranges and omissions; do not send controller truth or expected activities to the model. |
| Output | A pending proposal has exact source citations, preserves explicit saved choices and remains unapproved. Planned minutes are not measured app time. |

The current source-linked proposal candidate uses requests of at most **1,500 Characters / 6,000 UTF-8 bytes**, at most **768 serial requests**, **512 citations per suggested moment**, **32,000 Characters per detail**, and **10 final moments**. Its exact chunks retain separators and source offsets; a single oversized grapheme is explicitly refused. These are workload limits, not a prediction that such a large request count is practical on the owner's phone. Verify progress/cancellation and report actual calls and latency. A large or fragmented output can still be refused without replacing the current routine. A larger prompt budget alone is not proof that the user journey works.

## Controlled sources

Use an isolated test workspace and synthetic content only. Keep the expected sequence outside the app's input.

1. **Long readable source:** text exceeding the old 8,000-character input ceiling but within the archive limit. Put distinct, ordinary activity evidence near the beginning, middle and end. Keep exact original bytes for comparison.
2. **Structured video evidence:** complete eligible frames across the full movie, including dense frames, repeated screens, one unknown/failed frame and a user-reviewed unknown. Include useful later evidence so prefix-only selection cannot pass.
3. **Long movie import:** a real encoded synthetic movie whose readable screen text exceeds the former ceiling. Include static holds and sparse changes. Import the actual file through the production loader; a manufactured evidence envelope does not substitute for this check.
4. **Native capture:** a separately authorized, bounded recording on the owner's iPhone, using non-sensitive test screens. This is a separate result from an encoded movie, simulator capture or synthetic text fixture.

At least one fixture should contain only setup/marketing/picker text; another should mix those screens with real task content. Long irrelevant text must not defeat the existing activity-evidence guard.

## Required checks

| Journey | Pass condition |
|---|---|
| Import and relaunch | The full bounded extraction is readable in Learn/original evidence after relaunch. Import alone performs no inference and leaves the approved routine unchanged. |
| Prepare a long source | No whole-input 8,000-character refusal for a supported saved acquisition. The preparation covers the intended parts of the source according to its documented selection policy, retains exact source offsets and discloses anything omitted. |
| Fair multi-source selection | Every selected eligible acquisition contributes according to the documented policy. The app does not silently drop a later source or silently change a human/sample or time-zone partition. |
| Exact grounding | Each accepted quote matches the correct original/correction/frame bytes and offsets. No quote crosses unrelated frames or acquires a fabricated app identity, tap, read or scroll count. |
| Unknowns and exclusions | Truncated/failed/explicitly unknown frames cannot support claims. Selection warnings distinguish unsupported evidence, source truncation and budget exclusion; omitted content is not represented as absent activity. |
| Local model unavailable | The saved observation remains readable. Unavailable means no result, not a successful empty routine or a synthetic fallback. Record model attempts separately from successful responses. |
| Cancel or source change | Cancel during preparation or generation, edit/delete/re-date a source, or forget local data. A late result cannot replace the routine, restore erased evidence or install stale citations. |
| Save failure/recovery | Fail the workspace save after extraction. The prior workspace remains intact and an owned recording remains available for Retry/Discard. Successful persisted extraction permits recovery cleanup; later inference failure does not erase saved text. |
| Pending review | A valid response opens or offers the exact pending proposal, with selected source dates and omissions. Dismiss/relaunch preserves the pending review. Only explicit approval replaces the current routine. |
| Short-source regression | Existing short observations, guarded setup-only input, source corrections, kept/excluded moments and planned-duration preferences retain their behavior. |

Shared deterministic tests should exercise the selection, exact citations, bounds and stale-result behavior without calling Apple models. Native UI tests should exercise the production saved-source path, persistence and review controls. A marked test response may test presentation, but must never be reported as model inference.

## Real inference and recording evidence

For a supported local model, report availability, attempted/responded/failed calls, source length, selected length and elapsed time. Compare the proposal with independently recorded ground truth: supported claims, unsupported claims, omissions and explicit unknowns. A model response or syntactically valid proposal alone is not an accuracy pass.

For the native recording check, record explicit system authorization, actual stop/finalization, import, saved-text review and relaunch as separate observations. If the system panel remains visible, document the required manual dismissal. A saved callback start time is not proof that media time zero is the first captured pixel; movie duration and sampled frame timestamps do not establish continuous context or phone-use duration.

Do not claim whole-morning duration, app opens, reels, reads, scrolling or comparable week averages from this test. Those need their own evidence and [metric definitions](OBSERVATION-METRICS.md).

Keep movies, source text, screenshots and detailed reports local in ignored test artifacts. Publish only the source revision, test boundaries, aggregate counts and results. Preserve failed attempts alongside corrected reruns; identify exact synthetic, simulator and physical-device evidence separately.
