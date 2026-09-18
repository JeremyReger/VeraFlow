# VeraFlow — design spec

On-device meeting recorder, transcriber and summariser. iOS native, everything
local to the phone. This spec covers the redesign: two appearances (Chalk light,
Slate dark), nine screens, and the Ember app icon.

The canvas that this spec describes is the "VeraFlow redesign" Design artifact —
dark screens in the upper rows, the same nine screens in light in the bottom row,
plus a token reference and the icon spec.

---

## 1. The idea behind the redesign

The build today is stock iOS dark mode: grouped lists, a segmented control, and
every recording titled `Meeting · Sep 18, 2026 at 2:25 PM`. It reads as a utility.
Four changes carry most of the difference:

1. **Recordings get generated titles and a one-line gist.** A library of identical
   timestamps is unbrowsable. Title, snippet, speaker count and action count are
   what make the list scannable.
2. **Reading material gets a serif.** Summaries and transcript body are set in
   Newsreader. Labels, metadata and controls stay in Manrope. The split tells the
   user at a glance what is content and what is chrome.
3. **The summary earns its tab.** Overview, numbered key points, and real
   checkable action items — not one paragraph.
4. **Privacy is presented, not buried.** The "stays on this iPhone" line appears
   on Record, the empty state and Settings, set in italic serif with a lock glyph.

---

## 2. Appearances

Two themes, one set of token names. Follow the system setting; no in-app theme
picker in v1.

| | Chalk (light) | Slate (dark) |
|---|---|---|
| background | `#F3F4F6` | `#1B1D22` |
| surface | `#FFFFFF` | `#23262C` |
| border | `#E1E4E9` | `#32363E` |
| textPrimary | `#16181C` | `#F2F4F7` |
| textSecondary | `#4A5058` | `#B4BAC4` |
| textTertiary | `#5F666F` | `#868E9A` |
| accent | `#2E5A8A` | `#7EB6DE` |
| danger | `#B3261E` | `#F0796B` |

Full table in `tokens.json` and `Sources/VeraFlowTokens.swift`.

**Speaker colours are authored per appearance, not derived.** The obvious approach
— one palette, lightened for dark mode — puts the name labels under 4.5:1 on a
light ground. Five pairs are defined; assignment is by speaker index within a
recording and wraps past five.

---

## 3. Type

Both families are bundled with the app (they are Google Fonts, SIL Open Font
License — redistribution inside an app is permitted; keep `OFL.txt` in the
bundle).

- **Newsreader 400** — screen titles, recording titles, card titles, summary
  body, transcript body, the recording timer, and the italic reassurance lines.
- **Manrope 400/500/600/700** — section labels, tab labels, speaker labels, row
  labels, metadata, buttons.

Every style maps to a Dynamic Type text style via `relativeTo:`, so the whole app
scales. Test at AX3; the library card and the settings rows are the two places
that break first.

**Every timecode and duration uses tabular figures.** `4:52` must not reflow as
it ticks.

---

## 4. Screens

All nine exist in both appearances on the canvas. Phone frame is 390 × 844.
**No status bar is drawn** — the real one renders on top; leave the top 58 px
clear and let the system fill it.

### Library
Eyebrow `VERAFLOW` over a serif `Library`, with search and settings as 44 px
circular buttons. Filter chips (All / Starred / and the user's own template
names). Recordings grouped under `TODAY` / `YESTERDAY` / date headers, each a
card: title, two-line snippet, then `time · N speakers · N actions` with the
action count in accent.

Bottom: a full-width accent Record pill plus a 56 px import button, over a
gradient scrim so cards scrolling underneath stay legible.

### Library — first run
Same header. Centred: a seven-bar waveform mark with the centre bar in accent,
serif headline, one explanatory sentence, the Record pill, and a text button for
importing. Footer carries the privacy line.

### Record — ready
Close button, `NEW RECORDING` eyebrow. Centre: a 148 px ring around a 104 px
accent circle. Below, two 60 px picker rows — input device and summary template —
then the privacy line. **Template selection belongs here**, before recording, not
only after.

### Record — running
Pulsing `RECORDING` chip, 62 px serif tabular timer, live waveform, then the live
transcript with the previous line dimmed and the current line full strength and
speaker-tagged. Transport: `MARK` (62 px), stop (84 px, accent), `PAUSE` (62 px).

The **Mark** button is new — one tap drops a flag at the current timestamp so the
summary can weight that moment. Cheap to build, and it is the thing people
actually want mid-meeting.

### Processing
The state the current build hides. A card with a determinate progress bar and
four stages — audio saved (done), transcribing (in progress, with `8:45 of 14:08`),
telling the voices apart (queued), writing the summary (queued). Partial
transcript streams in below. A `Read what's ready` button lets the user leave.

Copy matters here: *"This runs on your iPhone, so it keeps going in the
background. You can close the app."*

### Summary / Transcript / Audio
One header (back, star, share, more), the recording title in serif, a metadata
line, then **underline tabs** rather than the iOS segmented pill. A mini player
is pinned to the bottom of Summary and Transcript, so playback is reachable
without going to the Audio tab.

- **Summary** — template chip with a Change affordance, overview paragraph,
  numbered key points separated by hairlines, and action items as real
  checkboxes. Completed items strike through and drop to tertiary.
- **Transcript** — search field and a speaker filter. Each block is speaker dot +
  tappable name + timecode + serif paragraph. The block being played gets a
  tinted fill and a border, **not** a left accent bar. Unidentified speakers carry
  a `NAME?` chip.
- **Audio** — full waveform scrubber with the playhead, transport with ±15 s and
  a speed pill, per-voice talk time with rename chevrons, file details, and two
  export buttons.

### Settings
Serif `Settings` with a Done pill. Three groups on hairline-separated cards:
on-device model status with sizes, recording defaults (template, consent
reminder, expected voices), and privacy (Face ID lock, destructive delete).
Footer carries the full privacy statement in italic serif.

---

## 5. States to build that the designs imply

- Recording paused (timer dimmed, waveform frozen, `PAUSED` chip).
- Transcription failed or model not downloaded — Settings status dot goes from
  success to danger with a `Download` action.
- A recording with one speaker: hide the speaker section rather than showing a
  list of one.
- Long titles: card titles clamp to two lines, detail titles to three.
- Import in progress, and import of an unsupported file.
- Empty search result in the transcript.

---

## 6. Accessibility

- Every tappable target is at least 44 × 44, including the 34 px filter chips
  (visual height 34, hit area 44) and the settings toggles.
- Text contrast is at least 4.5:1 against its own background in both
  appearances, 3:1 above 24 px. The values above were picked against that bar —
  changing a grey means re-checking it.
- Controls are real controls: `Button`, `Toggle`, `TextField`. The custom toggle
  style uses `accessibilityRepresentation` so VoiceOver announces a switch.
- Icon-only buttons all carry labels.
- The waveform is `accessibilityHidden` — the transport controls carry the
  semantics. Do not make the user swipe through 36 bars.
- Speaker identity is never carried by colour alone; the name is always present.
- Respect Reduce Motion: the pulsing record dot and the processing ring should
  hold steady rather than animate.

---

## 7. Icon — Ember

Five bars, one lit. The tile stays dark in both appearances — it is the one place
the brand keeps a warm note now that the interface has gone cool.

- Tile `#1B1D22`; outer bars `#4A505A`; inner pair `#B4BAC4`; centre bar
  **`#E07A4F` (clay)**.
- Bar width and gap: 5.36 % of the tile each. Heights outward from centre:
  61.9 % / 44.0 % / 23.8 %. Bar corner radius: half the bar width. Group centred
  on both axes.
- Export 1024 × 1024 square with no rounding and no inner shadow — iOS applies
  the mask. Tinted and clear home-screen variants use the same bars on a
  transparent ground.
- Below 40 px, ship a three-bar variant as a separate asset rather than scaling
  the five-bar one.

The alternative — the centre bar in accent blue `#7EB6DE` — is on the canvas.
It matches the UI exactly and disappears on a home screen full of blue apps.
Clay is the recommendation.

---

## 8. Open questions

1. Who generates the recording titles and snippets — the summary model on the
   same pass, or a cheaper second call? It affects how fast the library updates
   after a recording ends.
2. Does the Mark button write into the transcript as a marker, or into a separate
   list the summary reads? The design assumes the latter.
3. Export formats for transcript and audio are drawn as two buttons; the actual
   menu (txt, md, srt, the audio file) is not yet designed.
