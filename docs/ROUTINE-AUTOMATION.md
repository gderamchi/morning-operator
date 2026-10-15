# Routine execution — 15 October 2026

[MORE.md](../MORE.md) remains the acceptance reference. This implementation closes several runtime gaps; its presence is not evidence that all services meet the product promise.

## The user journey

Review each moment's actual operation, service, time and optional likes. The explicit **Let MORE take care of my morning** button approves that version. **Start my morning** starts it later; it cannot approve a draft. A running session retains its approved snapshot while future edits remain drafts.

Browser moments have a reviewed behavior: feed, videos, stories, headlines or visible unread information, constrained to supported site routes. Likes are a separate, visible choice, limited to three per moment. Previously saved browser moments remain manual until edited; existing approval cannot silently authorize new gestures.

MORE observes the page, performs the reviewed operation, checks the result and continues at the selected pace. Loading, sign-in, occluding dialogs, changed layouts, empty content and an unknown like outcome are distinct states. Page text never authorizes actions. A budget ending can end observed browsing; it cannot prove an external effect. An effect being verified defers the transition. Pauses stop the same session's clock and browser. Resuming reopens that moment; relaunch pauses browser execution.

Personal timed moments let a person get ready while MORE keeps the allotted time and moves on automatically. Spoken calendar/briefing/saved-note operations continue on their actual completion. A manual app handoff is described as manual; opening another iOS app cannot certify work inside it.

## Voice and mail

An active hands-free morning owns continuous on-device recognition and duplex speech. Local speech recognition, echo cancellation, context at speech onset and cancellation guard the current moment. Pause keeps listening for Resume. Next, Stop, Repeat and +2 minutes share the session and timer. Broader questions use Apple's local model with current source context. Unsupported hardware/model/language is surfaced; no cloud fallback is enabled.

Gmail can request an optional **read and send** grant from its visible connection screen. Existing readonly grants stay readonly. A mail moment reads up to five unread messages, chooses up to three with an explicit urgency heuristic, quotes source excerpts and explains selection. It supports yes/no, message selection, reply intention, local drafting, corrections, read-back and explicit **send**. The model writes body text only; the observed message determines the recipient/thread. “Yes” does not send. Local generation unavailable still permits declining or continuing.

Sending claims a durable operation before POST, with a stable generated Message-ID. A timeout or crash checks Sent for that identity and never retransmits merely because search found nothing. The journal holds hashed identities/status, not mail text. Volatile mail clears on background; the session and content-free journal retain safe recovery. Forget stops microphone/workers and removes both browser and mail journals.

Connected account actions use local argument proposals and an explicit human-readable review before execution. Their results are composed from provider data for display/speech; JSON is not the routine's output. The provider adapter, scope, permissions and account capabilities still determine actual coverage.

## Verification boundaries

Package tests establish deterministic policy, encoding, stale-result/cancellation and injected-provider behavior. Simulator tests establish visible navigation, explicit delegation, clock/session transitions, recap persistence and actual public-page behavior where observed. Synthetic command injection is never microphone recognition. A loaded web page is never successful browsing.

The final MORE acceptance also needs real connected accounts and an ordinary iPhone: acoustic barge-in, local-model latency, social stories/video/likes, all provider operations and actual voice-directed mail sending. These gates remain open until individually observed. Screen Time, video and semantic browser learning must also be reconciled into the common proposal; this runtime work does not by itself complete that learning pipeline.

## Acceptance tracking

Remaining real-provider, voice, complete-source-learning and full-service acceptance is tracked in [#173](https://github.com/gibouu/morning-operator/issues/173). Runtime work is pushed on `guillaume/routine-automation`; a WIP checkpoint is not a product acceptance pass. The native/synthetic test report is kept separate from authenticated provider results.
