# Routine automation acceptance

Product reference: [MORE](../MORE.md). This ledger separates implemented behavior, observed evidence and gates that remain open. Screenshots, recordings, private service results and credentials are local-only and are not committed.

| MORE requirement | Current evidence | Remaining acceptance |
| --- | --- | --- |
| Review what MORE will do, then delegate in the interface | Explicit operation/service/duration review; approval and Start are separate. Simulator delegation test passes. | Final large-text editing rerun after the stronger row-visibility check. |
| Convert learned observations into reviewable operations | Exact Screen Time app identities and reviewed video context produce bounded suggested operations. Combined provenance/learning/browser component run: 119 tests pass. | Common semantic browser learning and real multi-morning source coverage. |
| Execute browsing rather than just open a page | Real public Reddit test observes at least two contents, extends by two minutes, pauses, resumes and reopens the same moment. Real Le Monde privacy wall pauses without reporting content read. Both simulator tests pass. | Retain viewport/counts across reopening; authenticated social videos, stories and approved likes need real-account proof. |
| Persist one coherent session and its budget | Synthetic two-moment run previously completed without Next and restored its recap. Stop/pause preserve uncertain effects; timers do not certify provider success. | Final simulator rerun on the integrated source. |
| Interrupt speech without opening a turn for every utterance | Continuous on-device recognition and shared voice-processing PCM output; deterministic voice/playback/ownership tests pass. | Ordinary-iPhone acoustic barge-in, latency, echo and microphone-release observation. Typed command tests are not acoustic evidence. |
| Read, discuss, revise and send mail on request | Injected Gmail tests cover explicit sending, local drafting/Q&A, source-bound recipient, disconnect/replacement, payload-bound receipts and uncertain-send reconciliation. | One authorized self-addressed live test remains unrun: this checkout has no native Google iOS OAuth configuration. No mail was sent through another app as a substitute. |
| Use all present connections meaningfully | Schema-bound local argument proposals and complete readable approval; source-backed result narration/Q&A/repeat stays in the moment; confirmed effects are not replayed on resume. 23 connected-result/adapter/review tests pass. | Real accounts, permissions and each service's useful operations. Generic Q&A does not implement contextual follow-up writes for every service. Saved query values/dates remain fixed and are disclosed. |
| Respect privacy and personal corrections | Raw source/result/voice data remains local; private dialogue/results clear on background/forget. Source changes never silently approve actions or likes. | Full package and final integrated build must pass after all changes; own-interface wording exclusions are checked against current UI copy. |

The final acceptance routine in MORE §10 has **not** passed. [Issue #173](https://github.com/gibouu/morning-operator/issues/173) tracks the remaining provider, source-learning and physical-device gates. No simulator success certifies all listed services or an actual voice-directed send.

## Reproducing local checks

Use the full installed Xcode toolchain, not the standalone Command Line Tools:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --jobs 2
```

For native UI checks, build for testing, then run `MorningOperatorUITests/RoutineAutomationJourneyTests` against a dedicated simulator using its generated `.xctestrun`. Keep build and runtime phases separate. On the installed Xcode 27, an empty `UITargetAppCommandLineArguments` entry intermittently suppressed per-test launch arguments; removing that empty entry in a local copy restored the isolated fixture and language flags. The test assertions are unchanged. The tests label synthetic routines explicitly and use live public pages only for the browser checks.
