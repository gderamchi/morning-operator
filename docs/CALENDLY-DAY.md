# Calendly — appointments starting today

[MORE](../MORE.md) remains the product reference. This slice presents scheduled appointments for one verified Calendly user. It reads appointments that **start today**; it does not replace the full calendar overlap reading described in [Google Calendar day](GOOGLE-CALENDAR-DAY.md).

## Choose and delegate

**Apps & accounts → Calendly** offers the active accounts and verifies the selected user's name with Calendly. The screen explains the current-day scope, phone time zone, twenty-five-appointment limit and partial-reading notice. Provider identifiers, user URIs and email fields are not used as setup labels.

**Add this Calendly moment** checks the account and provider identity again, compares the exact source identity/name with the selected choice and requires that choice to be no more than five minutes old. It creates an unapproved routine draft. The ordinary review, editing, explicit approval and Start controls remain the delegation path. Choosing an account cannot approve or start a morning.

## Read and interact

Every run calculates the current day from the iPhone’s time zone, including daylight-saving boundaries. The approved routine saves the selected user, not fixed dates or a fixed zone. The provider identity is verified before and after the appointment read; a changed identity or name requires account review.

Only active appointments belonging to that verified user and starting in the half-open phone day are retained. An appointment beginning today may end tomorrow; the presentation keeps that date explicit. An appointment that started yesterday is outside this slice, even if it continues today. The provider’s strict lower-bound query is widened by one second, then filtered locally, so an appointment starting exactly at midnight is retained.

The reading contains at most twenty-five appointments in start order. Its summary presents the first three and discloses additional retained items, abbreviated names, partial pagination and omitted cancelled/outside-day results. A partial page with no appointments is distinct from a complete empty result. Local contextual answers receive a bounded source excerpt with explicit truncation.

**Repeat** presents the retained reading. **Actualise mes rendez-vous** / **refresh my bookings** explicitly performs a new bounded read, while respecting another pending or uncertain action. A reading older than five minutes, a changed day or a changed phone zone becomes unavailable for current answers. The same moment pauses with an explanation and Refresh, Next and Stop choices. Refresh does not create, reschedule or cancel a booking.

The source result is recorded before narration. If speech cannot finish, the reading remains available for Repeat and the moment pauses; audio recovery does not repeat the provider read. The session’s existing budget, pause, resume and extension controls continue to apply. An unavailable read remains distinct from a successful reading in the recap.

## Data and provider boundary

The fixed non-deprecated provider reads are `CALENDLY_WHO_AM_I` and `CALENDLY_LIST_SCHEDULED_EVENTS` from pin `20260929_00`. There is no invitee lookup, scheduling, cancellation or arbitrary provider-URL fetch. A further page token or page URL marks the reading as partial; MORE does not follow it automatically.

Calendly may return native contact, location or meeting fields in the transient HTTP response. The projection into MORE’s document, display, voice and model context discards structured guests, contacts, notes, phone numbers, meeting links and credentials. It retains the appointment name, start/end and a location category such as video or in person. Names are bounded source text, never execution instructions. There is no remote-model fallback.

The selected source is saved with the routine. The appointment text and local context are transient, cleared on background, privacy cleanup or leaving the moment. The backend retains execution metadata rather than raw result bodies. An active account alone does not prove that a reading succeeded.

## Verification boundary

Contract tests cover identity changes, exact URI validation, midnight/daylight-saving boundaries, partial and empty reads, cancellation, expired context and pruned private fields. Native setup, large text, Repeat/Refresh and recovery checks are still tracked separately in [ROUTINE-AUTOMATION-QA](ROUTINE-AUTOMATION-QA.md); this document does not assert that they have passed.

The DEBUG fixture uses a fixed `.invalid` host, in-memory tokens and the two read operations only. Every source is labelled **SYNTHETIC**. Its events come from the requested day, and its counter distinguishes another presentation from another event read. It has no live transport fallback or provider write. A real authorized Calendly account, the provider’s actual returned identity/results and ordinary-iPhone spoken questions remain acceptance gates until observed.
