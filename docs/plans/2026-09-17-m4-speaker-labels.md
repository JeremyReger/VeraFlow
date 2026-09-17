# M4 plan — Speaker labels (SPEC §10, §16 M4)

Written 2026-09-17 while Jeremy was away from the computer, with his go-ahead to "plan or do everything you can". Everything below was implemented on `claude/confident-cori-w668u8` in the commits that follow this file. Nothing has met a compiler yet (the M3 code is in the same state), so the first `scripts/test.sh` run will need a round of fixes.

## Scope

1. **`LiveTranscriptAligner`** (pure Swift, unit-tested). Ported from the Antigravity branch's `TranscriptAligner` (see `docs/reviews/2026-09-17-antigravity-review.md`) and fitted to our `TranscriptAligning` protocol:
   - each word → the turn with the largest time overlap; no overlap → nearest turn within 0.5 s; none → previous word's speaker (§10.2 #1)
   - runs of fewer than 3 words sandwiched between the same speaker are reassigned (§10.2 #2)
   - a new segment on speaker change or on the §9.3 paragraph rules, reusing `Paragrapher.Rules` (§10.2 #3)
   - diarizer IDs → `S1…Sn` in order of first appearance (§10.2 #4)
   - new: `speakerKeys(forSegments:turns:)` labels *existing* paragraphs by majority vote of their words, used when the user has already edited the transcript so edits survive.
2. **`LiveDiarizationService`** on FluidAudio 0.15.7's `OfflineDiarizerManager` (verified against the pinned source, not from memory):
   - models: `OfflineDiarizerModels.load(progressHandler:)` once, cached in the actor; `modelsReady()` checks the cache folder on disk (`Application Support/FluidAudio/Models/speaker-diarization-coreml/`)
   - a fresh manager per call (`OfflineDiarizerManager(config:)` + `initialize(models:)`) so the "expected speakers" hint can go into `config.clustering.numSpeakers`
   - `process(url, progressCallback:)` → `DiarizationResult.segments` → `[SpeakerTurn]`; `noSpeechDetected` → no turns (single speaker), not an error
3. **Pipeline stage** in `LivePipelineCoordinator`: `transcribed → diarizing → diarized`. Progress and model-download events as in M3. **Failure is non-fatal** (§6.3): the recording still reaches `.diarized` with one speaker, `failedStage = .diarizing` and the message kept, so the transcript shows "Speaker labels couldn't be added" with Retry. M5 will pick up from `.diarized`.
4. **UI** (§10.3):
   - speaker name on each paragraph in the speaker's colour; tap → Rename
   - paragraph context menu → "Change speaker" (any existing speaker or "New speaker")
   - Speakers menu in the transcript header → Rename / Merge into… per speaker
   - honest note "Labels can be wrong when people talk over each other" in Settings and the Audio tab's Speakers section
   - Settings → Speaker labels → Expected speakers: Auto / 2 / 3 / 4+ (`DiarizationPreference`, UserDefaults); applies to the next diarization run
5. **Tests**: aligner (9), speaker actions (4), preference (1), coordinator diarization path (4: labels after transcription, non-fatal failure, edited transcript keeps text, retry).

## Out of scope / deferred

- Bundling the diarizer models in the app instead of downloading (`ModelHub.offlineMode`): evaluate in M9 once download size and time are measured on device.
- The `com.apple.developer.background-tasks.continued-processing.inference` entitlement (iOS 27, Neural Engine in the background): request it before M9; until then long diarizations should be run with the app open.

## Device checks for Jeremy (added to PROGRESS.md)

- First run downloads the diarizer models with progress; a 2-person recording shows Speaker 1 / Speaker 2 with mostly correct turns (spot-check 20 turns on the 10-minute fixture, ≥ 85 % correct per §16).
- Rename a speaker: every paragraph updates. Merge two speakers: paragraphs re-label. Change speaker on one paragraph.
- Airplane mode + models not downloaded: transcript still appears with one speaker and a Retry.
