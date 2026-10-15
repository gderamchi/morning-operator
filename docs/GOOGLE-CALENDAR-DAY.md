# Google Calendar — the current day

[MORE](../MORE.md) is the product reference. This slice adds a named, read-only calendar moment to the ordinary routine review. It does not establish that every Calendar operation is available.

## Choose and delegate

Open **Apps & accounts → Google Calendar**, choose an active account, then choose a named calendar. Calendars are loaded in pages of fifty, up to five hundred. Hidden, deleted, nameless and free/busy-only calendars cannot become choices. Account and calendar identifiers stay out of the picker.

The screen explains the scope before **Add this calendar moment**: read the current day in this iPhone’s time zone, at most twenty-five events, announce a partial reading, and make no event changes. Adding creates an unapproved draft. The ordinary routine editor, approval and Start controls remain the delegation path; adding a source cannot approve or start it.

The selected calendar is checked again before adding, using its originating page and a choice less than five minutes old. Its verified primary-calendar label follows it into the reviewed routine and summary. Non-primary selection waits until all bounded pages are loaded, so a later homonym cannot silently change the meaning of the choice. Indistinguishable visible names are unavailable for delegation with a rename-and-refresh explanation. A newly discovered duplicate clears the old selection.

The approved moment retains its connection, exact calendar identifier, name and the reviewed primary status. Each run verifies that this named calendar is still readable and its saved primary status still matches. A missing, renamed or changed source requires a new selection; MORE does not silently substitute the primary calendar. Older saved routines without primary status remain compatible and do not gain that label implicitly.

## Read and interact

Each execution or explicit refresh calculates that day’s boundaries from the iPhone’s current time zone. Dates and a fixed time zone are not saved into the routine. Calendar arithmetic preserves daylight-saving days of twenty-three or twenty-five hours. Events overlapping the day are included, including an event that began earlier. Timed events are presented in the phone’s zone; overnight dates remain explicit. All-day dates retain the source calendar’s date semantics and exclusive end date.

The read returns at most twenty-five events in start order. A further page token is disclosed as a partial reading; MORE does not describe it as the whole day. The summary presents the first three events, with long titles or locations explicitly abbreviated. Local contextual questions use bounded retained event details; truncation is marked in their source. A complete empty result is distinct from an empty page of a partial result. Cancelled events are omitted and counted.

**Repeat** presents the retained reading without another provider call. **Actualise ce calendrier** / **refresh this calendar** explicitly replaces it with a new bounded read. A reading expires after five minutes, a change of phone time zone or a change of day. Expiry and unavailable sources pause the same moment with an explanation and the choices to refresh, go Next or Stop. Refresh does not bypass another prepared or uncertain action. The moment participates in the existing pause, resume, extension and budget transitions.

A received reading and a finished spoken presentation are distinct. If narration fails, the source remains available for Repeat and the session pauses; the provider operation is not repeated to repair audio. Event titles and locations are source data for answers, never instructions or permission to write. Local model unavailability remains visible; there is no remote model fallback.

## Data and provider boundary

The fixed provider operations are `GOOGLECALENDAR_LIST_CALENDARS` and `GOOGLECALENDAR_EVENTS_LIST` from the pinned Google Calendar catalogue. The event projection contains identifiers, status, title, start, end and location, plus bounded result metadata. Descriptions, attendees and attachments are not requested. No event creation, modification, deletion or new authorization occurs in this read path.

Source text is transient and bounded. Backgrounding, privacy cleanup and leaving the moment clear it. The saved routine retains the selected source and approved behavior, while the session recap retains the execution outcome. A connection being active does not prove that its events were read successfully.

## Verification boundary

Shared tests cover day windows, source validation, pagination, empty and partial results, cancellation, stale dates and bounded local context. The DEBUG HTTP fixture is explicitly labelled **SYNTHETIC**, intercepts only its fixed local routes, uses in-memory tokens and has no network fallback or write operation. Its events are derived from the requested window; it does not supply a real Google account.

Native navigation, large text and recovery checks are recorded separately in [ROUTINE-AUTOMATION-QA](ROUTINE-AUTOMATION-QA.md). A real authorized Google Calendar read, actual provider behavior and spoken contextual questions on an ordinary iPhone remain acceptance gates until observed. Synthetic results and a successful build do not close them.
