# Horizon — design spec for MORE

A side exploration. The current look on `main` stays as it is. This spec describes the recommended direction shown in `design/gallery/index.html`, so it can be built as a separate appearance when the owner decides.

## The idea in one paragraph

One line divides sky from ground. What is still to come lives in the sky; what is done has sunk into the grass. As the morning advances the line moves down and a pixel sun climbs over it. Before dawn the sky is night and the horizon glows through a dithered band that widens as the morning goes. No cards, no glass, no icons. Paper, grass, one orange, two typefaces, and pixels only where the two meet.

## Palette tokens

| Token | Light / sky | Role |
|---|---|---|
| `grass` | `#07250C` | Ground, primary fill, text on `clayLift` |
| `bone` | `#F2EDE3` | Sky (daytime), text on grass |
| `boneDim` | `bone` at 62 % | Secondary text on grass (6.3:1) |
| `ink` | `#14211A` | Text on bone (14.9:1) |
| `inkDim` | `#596860` | Secondary text on bone (5.4:1) |
| `inkLine` | `ink` at 14 % | Hairlines on bone |
| `grassLine` | `bone` at 18 % | Hairlines on grass |
| `clay` | `#C4653F` | Emphasis in display sizes only (3.6:1 on bone, so never below 24 pt regular / 19 pt semibold) |
| `clayLift` | `#D8764D` | Primary control fill; text on it is `grass` (5.2:1) |
| `clayGlow` | `#E8895D` | Sun rim, the dawn band's warmest row, danger outline on grass |
| `night` | `#0B1420` | Sky before dawn (dark appearance) |
| dawn stops | `#0B1420 → #1F2238 → #3A2A3A → #6B3A3A → #8A4A3A` | The dithered band above the horizon at night; `bone` stays ≥ 6.9:1 on every stop |

Rule: `clay` is never the only carrier of meaning and never used for body text. Emphasis in body text (the weather sentence) uses `clay` at 17 pt mono only in the mockups; in the app use `ink` and let the sentence structure carry it, or raise the emphasised span to a display size.

Light appearance = bone sky. Dark appearance = night sky. The ground is always grass; the controls do not change between appearances. Reduce Transparency: drop the grain overlay on the grass (it is `soft-light` at 35 %, purely decorative). Increase Contrast: `inkDim` → `ink`, `boneDim` → `bone`, hairlines to 28 %.

## Type

Both faces are SIL Open Font License and can be bundled in the app.

- **Fraunces** (variable; `opsz`, `wght`, `SOFT`) for display: greeting, countdown, moment title, recap lead, section titles. Weight 300, `SOFT` 70 at opsz 120; the italic accent word uses `SOFT` 100 at opsz 144. Minimum 24 pt.
- **IBM Plex Mono** 300/400/500 for everything else: dates, lists, body, labels, controls. Labels and controls are uppercase 11 pt with 0.18 em tracking; lists 17 pt; body 17 pt at 1.6 line height; secondary 12–13 pt.
- Dynamic Type: map Fraunces sizes with `@ScaledMetric` relative to `.largeTitle`/`.title`, Plex Mono relative to `.body`/`.caption`. At accessibility sizes the sky list scrolls inside the sky and the ground shows only the last completed moment plus the controls; nothing is clipped by the horizon. The greeting may wrap to two lines; the countdown drops from 124 pt to 72 pt at AX3 and above.
- SwiftUI proof uses `.serif` and `.monospaced` system designs as stand-ins until the fonts are bundled.

## Pixel and dither rules

- The pixel cell is **4 pt** (`@ScaledMetric` so it grows with text; it never grows past 6 pt). At 393 pt that is 98 cells across.
- Only **Bayer 4×4 ordered dither** is used, ever. No noise, no Floyd–Steinberg, no blur.
- Pixels appear in exactly three places: the **join** (6 cell rows, bone→grass, or at night `clayGlow`→grass), the **sun** (an 18-cell disc, `clayLift` core, `clayGlow` rim on alternate cells, only the half above the line is shown), and the **dawn band** (night only; 30–35 rows above the horizon, the five dawn stops dithered into each other).
- The grain on the grass is an SVG `feTurbulence` overlay at 35 % `soft-light`, the same recipe as lowcortisol.dev. It is not a pixel element and is dropped under Reduce Transparency.
- Nothing else is pixelated: type, hairlines and controls are vector.

## Layout and spacing

- Side gutters 28 pt. Date label at 62 pt from the top (under the status bar), heading at 82 pt.
- The horizon position is `groundMin + (groundMax − groundMin) × doneMinutes / plannedMinutes` with `groundMin` = 20 % and `groundMax` = 70 % of the screen height. Before the morning the ground holds only the controls; at the end it holds the whole list.
- The sky list is bottom-anchored 10 pt above the horizon; the ground list starts 14 pt below it. Rows are 17 pt with 10 pt vertical padding and a 1 pt hairline.
- Controls sit 34 pt above the bottom, in the ground: text labels left and centre, one filled `clayLift` control right (Play / Pause / Learn / Hear my recap). Minimum hit height 48 pt. Stacked controls (Your day, first use) are full-width 3 pt-radius rectangles, 15 pt vertical padding, 8 pt apart.
- Up to ten moments fit in the sky without scrolling at default text size (10 × 37 pt = 370 pt under a 150 pt header, ground at 20 %).

## Motion

- **One motion.** When a moment completes, the ground height animates to its new value and the sun rises one cell row: `easeInOut`, 600 ms. The completed row crossfades from the sky list to the ground list over the same 600 ms. Nothing else moves; no springs, no parallax, no glow pulses.
- Before dawn the band above the horizon grows by the same step.
- Pause: nothing animates; the countdown digits stop. Stop: the ground returns to `groundMin` over 600 ms.
- **Reduce Motion:** heights snap, the row crossfades over 200 ms, the sun snaps.
- Launch: no entrance animation. The screen is simply there.

## Accessibility rules

- **Pixel art never carries meaning alone.** Progress is always stated in text: the `Now · 4 of 7` label, the countdown, and the two lists. The join, the sun and the dawn band are `accessibilityHidden`.
- VoiceOver order: date label, greeting (with the planned minutes as its value), the sky list ("Make some tea, 5 minutes, moment 4 of 7"), then the ground as a group ("3 of 7 done"), its list, then the controls. The horizon is not an element.
- Every text pairing listed above meets WCAG AA at its size; `clay` on bone is reserved for ≥ 24 pt where 3:1 applies.
- Dynamic Type through AX5: see Type. The horizon mechanic survives because the two lists scroll inside their halves; the smallest ground still shows the controls at 48 pt.
- Reduce Transparency removes the grain; Increase Contrast darkens secondary text and hairlines; Smart Invert is not needed because the design already ships a night appearance (mark the sun and band as `accessibilityIgnoresInvertColors`).
- Controls keep their current labels and roles (`Play`, `Pause`, `Continue`, `Next`, `Again`, `Stop`, `Hear my recap`, `Start my routine`); the look changes, the words and the flows do not.

## What this is not

- Not a change to the app on `main`. The DEBUG-only `--design-preview` flag renders a static proof of the home screen (`Sources/MorningOperator/HorizonDesignPreview.swift`) with system fonts; it reads no store and changes no behaviour.
- Not a decision on fonts in the bundle, the LEVE name, or French copy; those are separate.
- The lowcortisol.dev photograph is not used. Only the recipe is borrowed: grass, bone, clay, grain, a soft italic serif beside a light mono.
