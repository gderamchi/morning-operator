# Routine execution — 15 October 2026

[MORE.md](../MORE.md) remains the acceptance reference. This implementation closes several runtime gaps; its presence is not evidence that all services meet the product promise.

## The user journey

Review each moment's actual operation, service, time and optional likes. The explicit **Let MORE take care of my morning** button approves that version. **Start my morning** starts it later; it cannot approve a draft. A running session retains its approved snapshot while future edits remain drafts.

Saved observations can be selected together in Learn. A sourced suggestion can be approved directly or opened with **Adjust this suggestion** in the ordinary editor. Saving those adjustments leaves a draft; it does not delegate the routine. The previous approved version remains restorable until the new version is explicitly approved.

Browser moments have a reviewed behavior: feed, videos, stories, headlines or visible unread information, constrained to supported site routes. Likes are a separate, visible choice, limited to three per moment. Previously saved browser moments remain manual until edited; existing approval cannot silently authorize new gestures.

MORE observes the page, performs the reviewed operation, checks the result and continues at the selected pace. Loading, sign-in, occluding dialogs, changed layouts, empty content and an unknown like outcome are distinct states. Page text never authorizes actions. A budget ending can end observed browsing; it cannot prove an external effect. An effect being verified defers the transition. Pauses stop the same session's clock and browser. Resuming reopens that moment; relaunch pauses browser execution.

Personal timed moments let a person get ready while MORE keeps the allotted time and moves on automatically. Spoken calendar/briefing/saved-note operations continue on their actual completion. A manual app handoff is described as manual; opening another iOS app cannot certify work inside it.

## Voice and mail

An active hands-free morning owns continuous on-device recognition and duplex speech. Local speech recognition, echo cancellation, context at speech onset and cancellation guard the current moment. Pause keeps listening for Resume. Next, Stop, Repeat and +2 minutes share the session and timer. Broader questions use Apple's local model with current source context. Unsupported hardware/model/language is surfaced; no cloud fallback is enabled.

After an informational answer, an interrupted read-only/timed moment or a retained confirmed browser/account result can resume once after the answer actually finishes. An explicit Pause, replacement turn, changed moment, privacy transition or pending action invalidates that continuation. Resuming a confirmed account result does not execute its operation again. An unavailable native source pauses the same moment and explains Resume, Next and Stop; the recap retains the unavailable result.

An expired Calendar/briefing reading can be explicitly replaced with **actualise ce briefing** / **refresh this briefing**. Repeat continues to refer to the pinned reading and does not silently fetch a new one. The refresh command is unavailable during another prepared or uncertain action.

Gmail can request an optional **read and send** grant from its visible connection screen. Existing readonly grants stay readonly. A mail moment reads up to five unread messages, chooses up to three with an explicit urgency heuristic, quotes source excerpts and explains selection. It supports yes/no, message selection, reply intention, local drafting, corrections, read-back and explicit **send**. The model writes body text only; the observed message determines the recipient/thread. “Yes” does not send. Local generation unavailable still permits declining or continuing.

An explicit self-note request can prepare a new message to the connected account's own profile address, including when its Inbox is empty. Subject and body can be edited in the moment. Review and Send are separate actions; editing invalidates the prepared send. This is a new self-addressed message, not a fabricated reply thread. Entering an Apple action retains a mail draft but revokes its send review, so a later Send first reads the draft again.

The Gmail moment uses the session's persistent time budget and extension control. Its deadline waits for reading, generation, speech and sending work to settle. A verified reading with no unfinished intention can continue to the next moment; an unfinished draft or uncertain send pauses with the dialogue retained. Extending that deadline resumes the same dialogue and budget without fetching the Inbox or sending again. A new successful reading never overwrites an older uncertain send outcome.

Sending claims a durable operation before POST, with a stable generated Message-ID. A timeout or crash checks Sent for that identity and never retransmits merely because search found nothing. The journal holds hashed identities/status, not mail text. Volatile mail clears on background; the session and content-free journal retain safe recovery. Forget stops microphone/workers and removes both browser and mail journals.

Connected account actions use local argument proposals and an explicit human-readable review before execution. Their results are composed from provider data for display/speech; JSON is not the routine's output. The provider adapter, scope, permissions and account capabilities still determine actual coverage.

## Contextual Apple actions

During an active morning, an explicit voice or interface request can prepare an Apple reminder or calendar event. The writable list/calendar and account are resolved from EventKit before review. MORE reads the title, destination and date/time details, then requires a separate action-specific confirmation. A small set of relative date forms is supported; other dates require clarification or the editable fields. MORE does not infer that an unsupported correction succeeded.

The person can also ask for upcoming reminders, choose one of the at most five observed items and explicitly mark it complete. The exact reminder, list, account and current fields are checked again before the write. A content-free durable claim precedes each write; only its observed receipt increments the session's confirmed Apple-action count. An uncertain write remains blocked rather than being repeated automatically. The current moment stays paused until Resume or Next, and a confirmed Apple action does not mark the unrelated moment complete.

Drafts and reminder content clear on background, privacy cleanup and a changed moment. Confirmed factual details remain available to local questions only in the same foreground moment. Calendar rescheduling, attendees, recurrence, and contextual follow-up writes for the other connected services remain to be implemented and verified.

The same action panel is available inside the routine browser, including when a spoken date needs interface correction. It presents over the retained page while that moment is paused. Closing the request leaves the same browser content and budget ready to resume.

## Verification boundaries

Package tests establish deterministic policy, encoding, stale-result/cancellation and injected-provider behavior. Simulator tests establish visible navigation, explicit delegation, clock/session transitions, recap persistence and actual public-page behavior where observed. Synthetic command injection is never microphone recognition. A loaded web page is never successful browsing.

Screen Time, reviewed video context and structured browser sequences now feed the common proposal while preserving citations and personal choices. The final MORE acceptance still needs real multi-morning source coverage, connected accounts and an ordinary iPhone: acoustic barge-in, local-model latency, social stories/video/likes, all provider operations and actual voice-directed mail sending. These gates remain open until individually observed.

## Acceptance tracking

Remaining real-provider, voice, complete-source-learning and full-service acceptance is tracked in [#173](https://github.com/gibouu/morning-operator/issues/173). Runtime work is pushed on `guillaume/routine-automation`; a WIP checkpoint is not a product acceptance pass. The native/synthetic test report is kept separate from authenticated provider results.
