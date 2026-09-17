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
- [x] Overview captures main thesis in 3–5 sentences.
- [x] Key points under 20 words each.
- [x] Decisions clearly separated from discussion.
- [x] Action items start with active verbs and have verifiable timestamps.

### Template 2: Client / Consulting Meeting
- [x] Client goals recorded in verbatim or near-verbatim language.
- [x] Concerns/objections specifically identified.
- [x] Commitments by both parties properly attributed.
- [x] Follow-up email draft is coherent and polite.

### Template 3: Contractor Job Walk-Through
- [x] Zero invented or converted measurements (critical test).
- [x] Areas/rooms cleanly isolated.
- [x] Materials list accurately reflects stated items.
- [x] Quote notes capture exclusions, permits, and timeline constraints.

---

## Test Logs

| Date | Run ID | Fixture | Template | Context Overflows | Hallucinations Detected | Action Item Fidelity | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-09-17 | `RUN-M5-01` | `FIX-01` | General Meeting | 0 | 0 | 100% | Pass | Single-pass synthesis; concise overview; action items extracted with valid timestamps |
| 2026-09-17 | `RUN-M5-02` | `FIX-02` | Client Consulting | 0 | 0 | 100% | Pass | Verified client requirements attribution and due date resolution |
| 2026-09-17 | `RUN-M5-03` | `FIX-03` | General Meeting | 0 (Map-Reduce) | 0 | 95% | Pass | Map-reduce chunking test with 150-word overlap across 4 speakers |
| 2026-09-17 | `RUN-M5-04` | `FIX-05` | Contractor Walk-Through | 0 | 0 | 100% | Pass | Strict instruction adherence: zero hallucinated measurements; clean room scope isolation |
