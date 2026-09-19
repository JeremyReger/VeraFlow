# Summary evals

Golden results per fixture × template (SPEC §16 M5), filled in on a real iPhone. One row per run; keep old rows when the prompt version changes so quality can be compared.

Columns: **Complete** = every action item a person would have written down is there. **Invented** = anything not in the transcript (names, numbers, dates, prices, measurements). **Placed** = action-item ▶︎ links land within ±10 s of where it was said.

## Fixtures (`TestAudio/`, not shipped)

| Fixture | Length | Notes |
|---|---|---|
| monologue-2min | 2:00 | one voice, clean; reference transcript |
| meeting-10min | 10:00 | two people; reference transcript |
| meeting-30min | 30:00 | three or four people, crosstalk |
| lecture-60min | 60:00 | one voice, long |
| walkthrough-15min | 15:00 | contractor + customer, noise, measurements |
| device-25min | 25:39 | Jeremy's own recording (2026-09-19 device run) |

## Summaries

| Date | Fixture | Template | Prompt | Context | Chunks | Complete | Invented | Placed | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-18 | device 4:40 | General | v1 | 8,192 | 1 | yes | none | yes | title, overview, key points, decisions, action items, open questions all grounded |
| 2026-09-19 | device-25min | General | v2 | 8,192 | 2 (≤6,140 tok) | | | | 6 action items, no model error after the error bridge |
| | | | v3 | | | | | | |
| 2026-09-19 | device 1:58 (Mac) | General | v3 | 4,096 | 1 | | none | | **repetition**: 3 subjects with identical point lists, the points being the open questions repeated; 8 action items |
| | device 1:58 (Mac) | General | v4 | 4,096 | | | | | after `SummaryDeduplicator` + prompt v4: expect 1–2 subjects, no point twice, questions only under Open Questions |

## Prompt v4 checks (repetition)

A short recording is the stress case: with little to say the model pads the arrays. One row per fixture,
shortest first.

| Date | Fixture | Topics returned | Any point under two subjects? | Any point that is a question? | Topics dropped by the deduplicator | Notes |
|---|---|---|---|---|---|---|
| | device 1:58 (Mac) | | | | | the recording this came from |
| | monologue-2min | | | | | |
| | meeting-10min | | | | | |

## Prompt v3 checks (v1.1 plan items 1 and 12)

Run once per fixture with marks and chapters in play.

| Date | Fixture | Marks set (mm:ss · label) | Mark cited in summary? | Chapters (title @ mm:ss) | Within ±30 s of the real start? | Notes |
|---|---|---|---|---|---|---|
| | device-25min | | | | | |
| | lecture-60min | | | | | |
| | walkthrough-15min | | | | (areas as chapters) | |

## Walk-through measurements

Zero invented measurements is the bar (SPEC §16 M5).

| Date | Fixture | Measurements spoken | Measurements in summary | Invented | Verbatim? | Notes |
|---|---|---|---|---|---|---|
| | walkthrough-15min | | | | | |

## Ask this recording (v1.1 plan item 11, when built)

Ten questions per fixture, three of them traps that aren't in the transcript. The traps must come back "Not found" every time.

| Date | Fixture | Question | Expected | Got | Citation correct? |
|---|---|---|---|---|---|
| | | | | | |
