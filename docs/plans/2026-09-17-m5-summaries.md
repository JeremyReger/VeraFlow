# M5 plan — Summaries and templates (SPEC §11, §16 M5)

Written 2026-09-17 while Jeremy was away. Split into two halves on purpose:

**Half A — deterministic Swift, written now, no SDK needed.** Everything under `VeraFlow/Services/Summaries/` plus the pipeline stage and the Summary tab, all testable with `FakeSummarizationService`:

1. `LiveDueDateResolver` — rules + `NSDataDetector` fallback, re-anchored to the recording date, 5 PM default. Table-driven tests on a fixed Thursday (SPEC §16). Started from the Antigravity resolver; the review's findings fixed ("next Friday" = next week's Friday, "next week" = Monday, no wall-clock dependence, "end of month", "EOD").
2. `TranscriptChunker` + `ContextBudget` — `[mm:ss] Name: text` lines, chunks by token budget that never split a line and overlap by one line, chars ÷ 3.5 estimate on iOS 26 (injectable counter for iOS 27), 1,000 / 1,500 output reserve, 30 % shrink on overflow.
3. `ActionItemPostProcessor` — de-dupe (token-set similarity > 0.8, compatible owners, longer text + earliest time), owner → speaker key, due dates via the resolver, timestamps parsed / clamped / recovered from the paragraph sharing ≥ 3 words.
4. `Prompts` — versioned shared rules, MAP, FINAL per template, follow-up email.
5. Pipeline: `diarized → summarizing → ready`. Skipped (straight to `.ready`, reason kept) when the summarizer reports unavailable, so transcripts work on every iPhone (SPEC §15). Re-run with another template = `retry(from: .summarizing)` after setting `templateID`. Summary history is the existing `Recording.summaries`.
6. Summary tab: overview, key points / decisions / open questions, action items with checkboxes (persisted in `SummaryRecord.actionItemsState`), owner + due date + ▶︎ timestamp that seeks the player; template-specific sections (client goals / concerns / next meeting; walk-through areas with measurements + the permanent "Check measurements against the audio before quoting." note); "Change template" and "Regenerate" menu; history picker.

**Half B — Foundation Models. Written the same night after all API names were checked against developer.apple.com (2026-09-18); see the DECISIONS entry on `GenerationError`.** `LiveSummarizationService`: `SystemLanguageModel.default.availability` mapping, `@Generable` draft types with `@Guide`, a fresh `LanguageModelSession(instructions:)` per call, `respond(to:generating:options:)` with temperature 0.2–0.3, `exceededContextWindowSize` → shrink + retry, `prewarm()`, iOS 27 `contextSize` / `tokenCount(for:)` behind `#available(iOS 27, *)` and `#if canImport` checks (DECISIONS 2026-09-17 on the iOS 26.5 SDK). Every API name gets verified against the SDK on Jeremy's Mac before use; that's why it waits.

Free-summary gating (3 free, SPEC §13) is M8; M5 counts nothing.
