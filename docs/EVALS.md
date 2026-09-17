# Summary Quality Evaluations (EVALS) — VeraFlow

Track the accuracy, action-item completeness, timestamp fidelity, and hallucination checks across audio test fixtures and templates (§16 M5).

---

## Evaluation Fixture Matrix

| Fixture ID | Description | Duration | Speakers | Noise / Conditions | Expected Outcome |
|---|---|---|---|---|---|
| `FIX-01` | Clean Monologue | 2 min | 1 | Quiet studio | 100% transcription accuracy, concise overview |
| `FIX-02` | 2-Person Planning Meeting | 10 min | 2 | Normal office | Diarization ≥ 85% correct turns, all action items assigned |
| `FIX-03` | 4-Person Meeting with Crosstalk | 30 min | 3–4 | Conference room | Map-reduce chunking test, speaker disambiguation |
| `FIX-04` | University Lecture | 60 min | 1 | Hall reverb | Long-file map-reduce, key points hierarchy |
| `FIX-05` | Contractor Job Walk-Through | 15 min | 2 | Construction site / fan noise | 0 hallucinated measurements; exact room task lists |

---

## Template Evaluation Criteria

### Template 1: General Meeting / Lecture
- [ ] Overview captures main thesis in 3–5 sentences.
- [ ] Key points under 20 words each.
- [ ] Decisions clearly separated from discussion.
- [ ] Action items start with active verbs and have verifiable timestamps.

### Template 2: Client / Consulting Meeting
- [ ] Client goals recorded in verbatim or near-verbatim language.
- [ ] Concerns/objections specifically identified.
- [ ] Commitments by both parties properly attributed.
- [ ] Follow-up email draft is coherent and polite.

### Template 3: Contractor Job Walk-Through
- [ ] Zero invented or converted measurements (critical test).
- [ ] Areas/rooms cleanly isolated.
- [ ] Materials list accurately reflects stated items.
- [ ] Quote notes capture exclusions, permits, and timeline constraints.

---

## Test Logs

| Date | Run ID | Fixture | Template | Context Overflows | Hallucinations Detected | Action Item Fidelity | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | Initial baseline pending M5 |
