# Your observed mornings

A recording gives MORE a few saved glimpses of your morning. Review lets you inspect those moments and see which screen labels appear across days, without adding controls to the Morning page.

**Available in the V2 source branch.** This does not yet measure a complete morning, time in other apps, scrolls or messages read. The installed phone remains on the earlier build; see [verification](PHASE-ONE.md) for current device status.

## Start with one morning

1. Record with Apple's explicit screen-sharing choice, or select a video to import in Learn. Return to MORE after stopping so processing can finish.
2. Open **Review → Saved observations**. Each import keeps its own original extraction; corrections are stored separately.
3. Check its observed day, time zone and origin. An imported file's date is not guessed from its name or import time. Leave unknown information unknown.
4. If you want screen labels, use **Edit in Learn → See sampled screens → Recognize sampled screens** on an eligible uncorrected recording. This explicitly requests the on-device model. Importing and opening Review do not call it.
5. Return to the observation's **Recording evidence**. Open **View sampled screens**, then a moment, to inspect the original text, accepted quotation and requested/actual frame times.

An unavailable model or unresolved screen still leaves the saved samples visible. A recognized label is a proposal about visible text; “Inbox” does not prove Mail was open, and a message on screen does not prove you read it. Separate samples at the same timestamp remain inspectable, but MORE does not invent their order.

## Look across days

Choose a seven-day period in Review, then **From your observations**. **Observed mornings** separates each saved time zone and origin. It shows days with labeled samples, observed days with no labels, and dates without an observation. Notes-only sources remain visible without acquiring fictional screen samples.

A label seen on two of three labeled days means just that: its quoted evidence appeared on two distinct dates among the three dates that supplied at least one accepted label. Two recordings on one date still count as one date. It does not mean two complete mornings, a measured frequency of app launches, or a two-thirds habit probability.

Open a label, then a quotation, to reach its current source moment directly. **The seven days** reveals separate clips and missing dates. Different movies are never concatenated into one activity timeline. Samples, automated activity and uncertain origins remain separate from personal mornings.

| You see | What it means |
|---|---|
| A → B → A in one clip | The samples establish at least one visible return to label A. More activity may lie in the gaps. |
| A → unknown → A | A return is not established. The unknown moment remains visible. |
| Several requests at one frame time | Several source samples, one effective moment. Conflicting labels make that moment unresolved. |
| No labeled samples | Evidence may be unclassified, ambiguous, corrected, limited, or affected by a model failure. It is not zero activity. |
| No observation | No saved source for that date and partition. It is not a zero-minute morning. |
| Invalid time order | Original samples stay available in extraction order; sequence and return claims are withheld. |

## Correct something

Use **Edit in Learn** to correct the observation's notes. This removes its earlier screen interpretation while keeping the original extracted text and sampled evidence. Day and weekly views immediately derive their results from the current source, including after relaunch. Changing a day/origin or deleting an observation also changes the derived review; no separate hidden analytics copy is saved.

A correction is not yet a per-frame replacement label. Review a proposed routine separately before approving it. The [learning guide](ROUTINE-LEARNING.md) explains how accepted source observations can support that draft.

## What still needs to be built

Reliable app identities, actions and comparable morning windows need more than sparse screen samples. Current video import retains at most 24 requested frames, which can miss many transitions in a long clip. Continuous capture coverage is unknown, so review does not turn the first/last frame into time spent. Exact scroll counts, reads, likes, pickups, full habit averages and continuing adaptation remain open work in [#21](https://github.com/gibouu/morning-operator/issues/21) and [#11](https://github.com/gibouu/morning-operator/issues/11).

The new review stores no additional media, sends no data and does not train a model. [Observation metrics](OBSERVATION-METRICS.md) covers the evidence contract; [architecture](ARCHITECTURE.md) describes local persistence and inference; [privacy](PRIVACY.md) explains removal and separate copies.
