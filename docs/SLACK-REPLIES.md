# Slack moments and reviewed replies

Product reference: [MORE](../MORE.md). Slack follows the same intended interaction as mail: read actual content, choose a message, express an intention, review the result, then give a separate instruction to send.

## Setup and execution

Apps & accounts → Slack offers a named channel picker. The account and workspace labels come from Slack identity verification. It lists bounded pages of joined, active, writable channels; private messages and group direct messages are excluded. Adding a channel creates an unapproved routine moment that explains the account, channel, latest-three-message read and separate send instruction. It does not approve or start the routine.

The approved read supplies the connection, channel and exact result provenance. Only ordinary human messages with verified timestamps and thread roots can become reply sources. A missing, unsupported or five-minute-old source cannot authorize a reply. “Refresh messages” performs only the approved read again. Repeat presents retained content without another provider execution.

The local model proposes body text only. It cannot select the account, channel, thread, provider tool or arguments. If local drafting is unavailable, the person can enter a body on screen and use the same review and send gates. A full review identifies workspace, sending account, channel, source message and proposed body. Any edit or interruption of that review revokes its authorization. Screen review is an explicit touch fallback, never acoustic evidence.

## Effect boundary

The client and server revalidate the account and destination. A dedicated server route compares Slack's subject tuple and an opaque grant revision immediately before dispatch. Missing metadata or a changed grant refuses the send. An older backend has no generic-send fallback.

The server fixes one plain-text section, thread, generated operation marker and disabled broadcasts/unfurls. The client accepts a receipt only when the actual response matches the selected account, channel, thread, body and operation marker. A generated request claim is durable before dispatch; a known receipt is recorded before narration. Unknown outcomes remain blocked across clearing the dialogue or restarting. There is currently no automatic reconciliation or retry of an uncertain Slack post. Confirmed and unconfirmed reply counts remain separate from completion of the reading moment.

Raw messages, provider identifiers and drafts are ephemeral. The local journal contains generated IDs and hashes; Forget includes this journal. Backgrounding and changing moments clear private source and draft content.

## Evidence and remaining gates

The shared package passes 1,499 tests (Health 4, Core 645, Apple 850), including 19 focused Slack conversation/transport tests. The server passes 38 tests, including 10 Worker/D1 tests for concurrent claims, account changes, restart and unknown outcomes. These use explicit synthetic providers.

Worker version `39a6c473-3541-445c-9701-6a281f900fad` is deployed. A live isolated installation verifies health, account listing, refusal when account identity is unavailable and rejection of unreviewed fields. This smoke check performs no provider write and does not establish access to a Slack account.

The native interface passes three French AccessibilityXXXL journeys: account absent/recovery (43.998 seconds), named paginated channels → unapproved routine → review without internal IDs (65.834 seconds), and selected message → editable reply → separate screen review/send → confirmed synthetic receipt → background privacy cleanup (54.053 seconds). These three pass in round4. The final build7 tightens only the display formatter's ID bounds; it compiles and its setup journey is rerun successfully (73.675 seconds). The earlier failures were a parent accessibility identifier masking children and a test scroll helper choosing the wrong direction for offscreen fields; both are recorded, repaired and rechecked. Captures were independently inspected. All fixture transports remain local and explicitly synthetic.

A real authorized Slack account, provider permissions, grant-revision stability, source reads, the exact returned message marker and a reviewed live effect remain unproved. The ordinary iPhone still runs the earlier signed build1532; this slice has not replaced it during the pending acoustic Gmail test. [Issue #173](https://github.com/gibouu/morning-operator/issues/173) retains these acceptance gates.
