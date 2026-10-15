# Outlook — unread Inbox previews and a chosen message

[MORE](../MORE.md) remains the product reference. This slice reads an identified Outlook Inbox and one explicitly chosen message. It does not implement Outlook replies or sending.

## Choose and delegate

**Apps & accounts → Outlook** loads active accounts and verifies the selected profile. Review its name and returned mail identifier before adding the moment. Adding rechecks the identity and its five-minute age, then creates an unapproved draft. Ordinary routine review, approval and Start remain separate.

The reviewed operation presents up to three unread Inbox previews, including older unread messages. It does not claim an importance ranking or a complete mailbox reading. A missing account or failed profile check cannot become an empty Inbox.

## Read and choose

Each new read captures a current UTC cutoff and requests the three most recent unread Inbox messages no later than that cutoff. The saved routine contains the verified account, never fixed dates, message IDs or request arguments. The filter/order combination follows the [Microsoft Graph list-messages contract](https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0).

Sender, subject, date and a bounded preview are source data. Further pagination is disclosed without following the provider URL. Complete empty, partial empty, unread-body absence and read failure remain different states. Inbox access does not establish body access.

The person chooses a presented message by its visible ordinal, sender, subject and time, or a supported spoken ordinal. Only an exact message ID from that still-current snapshot can reach the detailed-read operation. Its identity and observed metadata are checked again; a changed or moved message requires a fresh Inbox reading. The detailed operation follows [Graph get-message](https://learn.microsoft.com/en-us/graph/api/message-get?view=graph-rest-1.0), while HTML is converted locally into inert text. Attachments, images, links and other remote resources are not opened.

The retained body and spoken excerpt are distinct. Missing content remains unknown; truncation is disclosed. The local model receives a bounded source excerpt rather than executable instructions. **Repeat** reuses the selected body, or the previews if no body was selected. **Refresh Outlook** performs a new bounded Inbox read and clears the previous selection. Neither operation sends, moves, deletes or marks a message as read.

## Freshness and privacy

The snapshot expires five minutes after its cutoff. Reading a body cannot renew that source window. A store-owned monitor checks freshness while the moment controls are closed. Context assembly uses current documents; an expired reading does not fall through to the generic cached result. Backgrounding, privacy cleanup and leaving the moment clear the source text. The recap retains outcomes rather than mail content.

Identity and active-connection checks surround provider reads. Requests share a forty-second deadline and respect cancellation. The dedicated client helper allows only the profile, Inbox-list and selected-message reads, using new request IDs without the effect journal. Another pending or uncertain action must settle before refreshing or choosing a message. No remote model fallback is enabled.

## Verification boundary

The shared contract checkpoint `32bfd29` passes sixteen targeted tests with intercepted HTTP, including identity changes, observed-message binding, cutoff/expiry, empty/partial/missing body, inert HTML, cancellation, deadlines and read-only allowlisting. Portable export drops the executable account selection; a restored local session preserves its reviewed target.

The app routing, controls and explicit **SYNTHETIC** fixture are subsequent work awaiting their iOS build and native UI tests. The fixture has a fixed `.invalid` host, in-memory tokens, no live transport fallback and no write operation. Its duplicate-header case checks that the second message remains distinguishable and bound to its own body. No real Outlook account, body read, spoken question or external effect is established by these tests. Results belong in the [acceptance ledger](ROUTINE-AUTOMATION-QA.md).
