# Progress

Update this file at the end of every session. Check an item only when its "Done when" criteria (SPEC §16) pass on a real device.

- [x] M0 — Project foundation (2026-09-17: `scripts/test.sh` green on Jeremy's Mac; app launched on Jeremy's iPhone to the empty Library, Record placeholder, and Settings)
  - [x] `project.yml` (XcodeGen): iOS 26.0 min, Swift 6 strict concurrency, FluidAudio pinned to 0.15.7, `Alpha` config named "Riffle (alpha)"
  - [x] Folder structure per SPEC §6.1 (App / Features / Services / Persistence)
  - [x] SwiftData models per SPEC §7 and `PipelineStage` per §6.3
  - [x] Protocol + fake for every service in §6.1; `AppServices` container injected through the SwiftUI environment
  - [x] `RecordingStorage` (Application Support/Recordings/<uuid>/, backup-excluded, file protection)
  - [x] Preview data; empty Library screen; placeholder screens for later milestones
  - [x] Swift Testing unit tests, network-policy test (§6.2), single-dependency test, XCUITest launch test
  - [x] `scripts/test.sh`, `PrivacyInfo.xcprivacy`, `docs/DECISIONS.md`
  - [x] `xcodegen generate` + `scripts/test.sh --unit-only` pass on Jeremy's Mac (Xcode 26.6, 29 tests) with no strict-concurrency warnings
  - [x] `scripts/test.sh` (unit + UI) passes on Jeremy's Mac (29 unit tests + 1 XCUITest)
  - [x] App launches to an empty Library on a device (Jeremy's iPhone, iOS 26)
- [ ] M1 — Recording (tests green; all device checks pass except the 90-minute run and the two new checks below)
  - [x] `LiveAudioRecorderService`: AVAudioEngine → CAF/AAC mono 44.1 kHz 64 kbps; `.playAndRecord` with Bluetooth HFP + speaker; input picker
  - [x] Recorder screen: start, timer, level meter, pause/resume, stop, bookmarks, name-on-stop, permission-denied state
  - [x] Interruptions: auto-pause + "Interrupted" bookmark, "Resume recording?" prompt, route-change notice, engine restart on hardware change
  - [x] Disk space: warning banner under 500 MB, auto-stop under 100 MB
  - [x] Launch recovery of `.recording` rows (duration from file; unreadable → failed) with a one-time alert
  - [x] Minimal playback (play/pause/scrub/skip, bookmark tap-to-seek) in the detail screen
  - [x] Tests: view model (11), recovery (5), disk policy, level meter, file info; UI test of the record → save flow with fakes
  - [x] `scripts/test.sh` green on Jeremy's Mac (56 unit tests + 2 XCUITests, Xcode 26.6, no strict-concurrency warnings)
  - [x] Device: record → waveform/level meter/bookmarks → stop → save → playback with audio (Jeremy's iPhone; 1:13 recording = 606 KB CAF/AAC 44.1 kHz mono)
  - [x] Device: recording continues with the screen locked (10-minute locked recording plays back)
  - [ ] Device: 90-minute recording with the screen locked plays back fully (first attempt: system interruption at 43:42, crash on Resume in the configuration-change re-tap per the crash log; capture restarts now rebuild the engine and validate the format first; re-test needed)
  - [x] Device: connecting or disconnecting Bluetooth earbuds mid-recording switches mics without a pause (Jeremy's soundcore earbuds; both directions)
  - [ ] Device: Microphone menu shows iPhone Microphone by default with earbuds connected; picking the earbuds mid-recording switches to them; the choice survives relaunch
  - [ ] Device: Live Activity shows timer/Paused/bookmarks on the Lock Screen and in the Dynamic Island while recording, and disappears on Stop
  - [x] Device: force-quit mid-recording recovers a playable file (first try FAILED with CAF/AAC; after switching capture to ADTS: recovered alert, 0:09 row, plays)
  - [x] Device: a phone call pauses, adds an "Interrupted" bookmark, and offers resume (4:40 recording plays back)
- [ ] M2 — Library and import (tests green; needs the two device checks below)
  - [x] Library: search by title, sort (newest/oldest/title/longest), favorites filter, tag chips
  - [x] Rename (alert), favorite (swipe + menu), tags (editor sheet with suggestions), delete (confirmation; removes folder + cancels pipeline)
  - [x] Import from Files (`fileImporter`, m4a/mp3/wav/caf) and via share sheet / "Open in" (document types + `onOpenURL`, Inbox cleanup)
  - [x] `LiveAudioImportService`: security-scoped + coordinated copy, duration from the file, unreadable files rejected
  - [x] Tests: import service on real wav/caf/m4a (+ rejections), library actions (8), filter/sort (5); UI test renames via context menu and searches
  - [x] `scripts/test.sh` green on Jeremy's Mac (84 unit tests + 3 XCUITests, Xcode 26.6, widget extension included)
  - [ ] Device: share a Voice Memo into VeraFlow; it appears with the correct duration and plays
  - [ ] Device: Import from Files picks an m4a/wav and it plays
- [ ] M3 — Transcription (+ SpeechAnalyzer vs Parakeet benchmark) — code written; needs Jeremy's compile run and the device checks below
  - [x] `LiveTranscriptionService`: `SpeechTranscriber` with `.audioTimeRange`, `DictationTranscriber` fallback (engine recorded on the row), `AssetInventory` download with progress, file read + resample to the analyzer's format, `insufficientResources` retry
  - [x] `LivePipelineCoordinator`: FIFO queue on its own `ModelContext`, `.recorded`/`.transcribing` resumed on launch, cancel on delete, expiry puts the row back to `.recorded`, failure keeps `failedStage` for Retry
  - [x] `LiveBackgroundProcessing`: `BGContinuedProcessingTaskRequest` per drain with inline fallback (Simulator has no BG tasks)
  - [x] `Paragrapher` (gap > 1.2 s, sentence end past 25 words, > 45 s), `TranscriptCursor` (paragraph + word under the playhead), `WordErrorRate`
  - [x] `ParakeetTranscriptionService` (FluidAudio 0.15.7, Core ML, one-time model download) behind `EngineSelectingTranscriptionService`; Apple Speech is the default
  - [x] Detail screen tabs: Summary (placeholder) / Transcript / Audio. Transcript: timestamps, synced paragraph + word highlight, tap-to-seek, context menu "Play from here", Edit mode (original text kept, per-paragraph revert), search with match count, status banner (Transcribe / progress / model download / Retry), "Standard accuracy" badge
  - [x] Library rows show a progress bar while a stage runs; `AppState.pipelineProgress` fed by the coordinator's events
  - [x] DEBUG Settings → Developer → Transcription benchmark: pick a recording, paste a reference, run both engines, see time / speed / words / WER, share a Markdown report, choose the engine for new transcripts
  - [x] Tests: paragrapher (5), coordinator (6), cursor (4), WER (4), benchmark (4), transcript text (4), app-state progress (1); UI test opens a seeded transcript, searches, toggles Edit
  - [ ] `scripts/test.sh` green on Jeremy's Mac
  - [ ] Fixtures in `TestAudio/` (2-min monologue + 10-min two-person with reference text; 30-min, 60-min optional)
  - [x] Device: a new recording transcribes automatically and the transcript appears with timestamps (2026-09-18, iPhone iOS 27.0; 846 words / 4:40 in ~25 s). Follow-playback highlight and row progress still to eyeball
  - [x] Device: speech assets were already installed on Jeremy's iPhone; `SpeechTranscriber` path confirmed (Speech engine: Apple Speech)
  - [ ] Device: lock the phone during transcription; it finishes (or resumes on next launch from `.recorded`)
  - [ ] Device: the 60-minute fixture transcribes without a crash or memory warning
  - [ ] Device: benchmark on the 10-minute fixture; WER + time for both engines recorded in `docs/DECISIONS.md`, engine choice decided
- [ ] M4 — Speaker labels — code written while Jeremy was away (plan: `docs/plans/2026-09-17-m4-speaker-labels.md`); needs the compile run and device checks
  - [x] `LiveTranscriptAligner` (SPEC §10.2, ported from the Antigravity branch with credit): overlap / nearest / previous-speaker assignment, short-run smoothing, speaker-change + §9.3 paragraph breaks, `S1…Sn` by first appearance, majority labeling of edited paragraphs
  - [x] `LiveDiarizationService` on FluidAudio 0.15.7 `OfflineDiarizerManager` (calls verified against the pinned source); one-time model download with progress; "Expected speakers" hint
  - [x] Pipeline: transcribed → diarizing → diarized; failure is non-fatal (one speaker + Retry); cancellation resumes from `.transcribed`
  - [x] Transcript: coloured speaker names (tap to rename), Change speaker per paragraph (existing or new), Speakers menu with Rename / Merge into…, "Labeling speakers" progress and non-fatal failure banner
  - [x] Settings → Speaker labels → Expected speakers (Automatic / 2 / 3 / 4 or more) with the honesty note; Audio tab lists speakers with colours and the same note
  - [x] Tests: aligner (9), speaker actions (5), preference (1), coordinator diarization path (4 new, 4 updated)
  - [ ] `scripts/test.sh` green on Jeremy's Mac
  - [x] Device: first run downloaded the diarizer models (23 files, compiled in 17.7 s); a multi-speaker recording shows two speakers (third voice still merged; testing the Expected speakers hint)
  - [ ] Device: 10-minute 2-person fixture: spot-check 20 turns, ≥ 85 % correct (SPEC §16)
  - [x] Device: rename propagates to every paragraph and to the summary's action-item owner ("Don"). Merge / change speaker / new speaker still to try
  - [ ] Device: with the models not downloaded and no network, the transcript still appears with one speaker and Retry works once online
- [ ] M5 — Summaries and templates — written while Jeremy was away (plan: `docs/plans/2026-09-17-m5-summaries.md`); needs the compile run and device checks
  - [x] `LiveDueDateResolver` (rules + `NSDataDetector` fallback, re-anchored to the recording date, 5 PM default) with a 40-row table test on a fixed Thursday
  - [x] `TranscriptChunker` + `ContextBudget`: `[mm:ss] Name: text` lines, chunks that never split a line and overlap by one, chars ÷ 3.5 estimate, 1,000 / 1,500 output reserve, 30 % shrink
  - [x] `ActionItemPostProcessor`: de-dupe (> 0.8 token-set similarity, compatible owners), owner → speaker key, due dates in Swift, timestamps parsed / clamped / recovered from the transcript
  - [x] `Prompts` v1 (shared rules, MAP, FINAL per template, follow-up email)
  - [x] Pipeline: diarized → summarizing → ready; unavailable model or a failure keeps the row usable with the reason + Retry; "Change template" re-runs only the summary and keeps the history
  - [x] Summary tab: title / overview, template sections, action items with checkboxes (persisted), owner, due date, ▶︎ timestamp, walk-through measurements with the "check against the audio" note, history picker, Model row
  - [x] Tests: due dates (43), chunker + budget (5), post-processor (5), input builder (2), coordinator summary path (3 new)
  - [x] `LiveSummarizationService` on Foundation Models (API names checked against the developer.apple.com reference on 2026-09-18): availability mapping, `@Generable` drafts, fresh session per call, map → reduce → final, `contextSize` read at runtime, `tokenCount(for:)` on iOS 26.4+ to calibrate the estimate, overflow → 30 % smaller chunks and retry (3×)
  - [ ] `scripts/test.sh` green on Jeremy's Mac
  - [x] Device: a 4:40 recording summarized on device (8,192-token context, title/overview/key points/decisions/action items/open questions all grounded in the transcript). 60-min and 30-min fixtures still to run
  - [ ] Device: walk-through fixture has zero invented measurements; action items link to the right moment (±10 s)
  - [ ] `docs/EVALS.md` golden results per fixture × template
- [ ] M6 — Exports — written while Jeremy was away (plan: `docs/plans/2026-09-18-m6-exports.md`); needs the compile run and device checks
  - [x] `ExportRenderer`: Markdown / plain text / copy texts / file names / reminder notes (7 tests)
  - [x] `LiveExportService`: Core Text PDF with page footers (Simulator-tested), EventKit reminders with due dates + stored IDs, `.m4a` audio export
  - [x] Share menu on the detail screen: Markdown, PDF, plain text, include-transcript toggle, copy summary / action items, email (client follow-up via the model), Send to Reminders sheet, audio
  - [ ] `scripts/test.sh` green on Jeremy's Mac
  - [ ] Device: Markdown opens in Notes/Obsidian, PDF previews in Files, Mail draft is prefilled, Reminders shows the items with due dates, `.m4a` plays
- [ ] M7 — Onboarding, settings, capability messaging, privacy — written while Jeremy was away (plan: `docs/plans/2026-09-18-m7-onboarding-settings-privacy.md`); needs the compile run and device checks
  - [x] Onboarding: four pages incl. microphone permission and honest capability messaging + optional speech-model download; gated in `RootView`
  - [x] Consent reminder sheet (SPEC §14.2 copy) with "Don't show again" and a Settings toggle
  - [x] `LiveCapabilityService` (SPEC §15) wired into `AppServices.live`
  - [x] App lock (Face ID / passcode), Delete all data, AI disclaimer under summaries, `NSFaceIDUsageDescription`
  - [x] Diagnostics (7 taps on the version): capabilities, models, storage, failures, stage timings, event log
  - [x] Tests: preferences (1), timeline (3), delete all (1), app-state event log (1); UI test walks onboarding
  - [ ] `scripts/test.sh` green on Jeremy's Mac
  - [ ] Device: fresh install shows onboarding; capability page matches the phone; consent sheet once; Face ID lock on return; Delete all data; Diagnostics after 7 taps
  - [ ] Device: proxy (Charles/Proxyman) shows only Apple speech assets, Hugging Face model files, and StoreKit
- [ ] M8 — Purchases — written while Jeremy was away (plan: `docs/plans/2026-09-18-m8-purchases.md`); needs the compile run and StoreKit/TestFlight checks
  - [x] `LivePurchaseService` (StoreKit 2: products, purchase + verify + finish, current entitlements, updates listener, restore via `AppStore.sync`)
  - [x] Free-summary counter in Keychain + UserDefaults; pipeline stops the 4th summary with the unlock reason; unlocked summaries never count
  - [x] Paywall with price from the store, Restore, honest no–Apple Intelligence copy; opened from the 4th summary and locked exports (never on launch)
  - [x] `VeraFlow.storekit` attached to the scheme; `ExportGate` for the free tier
  - [x] Tests: counter (1), paywall model (2), export gate (1), coordinator free-limit path (1)
  - [ ] `scripts/test.sh` green on Jeremy's Mac
  - [x] Device/StoreKit: purchase in the Xcode StoreKit environment unlocks; the 4th summary was blocked correctly before it. Refund, restore, Family Sharing, and reinstall still to test
  - [ ] Decide the price and fill `AppLinks` (terms, privacy) before TestFlight
- [ ] M9 — Polish and ship (plan: `docs/plans/2026-09-18-m9-polish-and-ship.md`; Jeremy added a Section 508 accessibility review and a DoD-oriented security review up front)
  - [x] Security review filed (`docs/reviews/2026-09-18-security-review.md`); 13 of 17 findings fixed in code, 2 accepted, S-11 (bundle models) is Jeremy's call, S-10 needs `Package.resolved` committed after the next `test.sh`
  - [ ] Device: with the app lock on, pull down Control Center and open the app switcher → the cover shows, not the transcript; Lock Screen playback shows "Recording"; a shared export disappears from Files → On My iPhone → VeraFlow after the share sheet closes
  - [x] Accessibility review filed (`docs/reviews/2026-09-18-accessibility-review.md`); 28 of 33 findings fixed in code, 3 partly (PDF structure tags, list title truncation, scroll animations under Reduce Motion), 2 accepted/DEBUG-only
  - [x] Device 2026-09-18: the M9 batch compiled and ran; launch sweep removed 2 leftover files; speaker labelling failed in the background (GPU not permitted) → models now load on CPU + Neural Engine and a background failure waits for the foreground. Re-tested: no GPU errors, labelled 2 speakers and summarized without Retry; segmentation ~66 ms/window on CPU+ANE vs ~20 ms on GPU (2.3 s for a 69 s recording, still ~30× real time)
  - [ ] Device (VoiceOver on): record → hear "Recording"/"Paused" and the elapsed time on the timer; open a transcript → each paragraph is one element with Play from here / Change speaker / Rename in the actions rotor; check an action item → "Done"; Settings → Accessibility → Larger Text at the largest size → onboarding, consent sheet, recorder controls, summary rows still usable
  - [x] Dynamic Type (`@ScaledMetric` for every fixed size), dark-mode colour sets, Reduce Motion on the level meter, empty states already covered; error copy audit still open
  - [ ] App icon (generated, reproducible) + alpha variant
  - [ ] Listing copy, privacy + terms pages, screenshot UI test, review notes
  - [x] STIG review filed (`docs/reviews/2026-09-19-stig-review.md`): the iOS 26 STIG (V1R1, via NIST's mSCP copy) is a device benchmark; VeraFlow is eligible for the app allow list (no cloud, no backup, no diagnostics, AI on device) and stays usable under the full baseline. Open: V-1 whether the mandatory Siri restriction also disables the on-device model (needs a supervised device); R-1 managed app configuration so an MDM can force the app lock and the minimal Lock Screen; R-2 strict data-protection option; R-3 distribute as a custom app via Apple Business Manager
  - [ ] §14.5 checklist with evidence; TestFlight build
  - [ ] Xcode 27 migration (needs Xcode 27 on Jeremy's Mac). Until then `LanguageModelErrorBridge` names the iOS 27 `LanguageModelError` cases from their description. Device 2026-09-19: a 25:39 recording's summary had failed twice ("LanguageModelError error -1" after 110 s, then rate limited); on the bridged build Retry summarized it cleanly in 2 chunks of ≤6,140 tokens (context 8,192) with 6 action items and no model error
  - [x] Redesign from Jeremy's design package (plan: `docs/plans/2026-09-18-redesign.md`): every screen restyled; `scripts/test.sh` green; Jeremy 2026-09-18: "looks very good" on device. Follow-ups from that look: Appearance picker (System / Light / Dark) and search across summary, tags and transcript, both built the same day. Two real bugs surfaced by the UI tests on the way: a rename never showed because the card preferred the generated title, and a screen identifier was overwriting every header button's identifier. Now in day-to-day use by Jeremy; VoiceOver pass, largest text size, and Files import still to check

## M10 — v1.1 (plan: `docs/plans/2026-09-19-v1-1.md`)

Waves A, B and C were written together in one build on 2026-09-19 while Jeremy was away, on the existing pattern: tests written, `scripts/test.sh` not yet run (this session had no Xcode). Jeremy ran the unit tests green and started device testing; Waves D and E were then written the same way. F (Mac) and G (iPad, opens 1.2) are not started.

- [ ] Wave A — the promises
  - [x] Speaker filter chips on the transcript (`TranscriptFilter`, 4 tests); talk-time rows open the filtered transcript, rename moved to touch-and-hold
  - [x] Skip silence (`SilenceDetector`, 6 tests; `WaveformPeaks.levels`; player scan + jump; Audio tab row with "saves m:ss")
  - [x] Recently Deleted (`deletedAt`, trash / restore / delete now / empty, `TrashSweeper` at launch, Settings → Storage; 5 tests + 2 pipeline tests)
  - [x] "Summary ready" / "Needs attention" local notifications (`ProcessingNotifier`, 4 tests; `LiveNotificationService` provisional; tap opens the recording; Settings toggle; app-state test)
  - [x] Transcription language picker (`supportedLocales` on every engine, `TranscriptionLanguages`, 2 tests; "Transcribe again in…", 1 test; unsupported summary language parks the row, 1 test)
  - [x] `scripts/test.sh --unit-only` green on Jeremy's Mac (2026-09-19, after one round of fixes: silence threshold, notifier after a failed run, mark placement)
  - [ ] Device: two-speaker recording → chip → count line → play; skip silence on a recording with pauses; delete → Recently Deleted → restore; lock the phone during a summary → notification appears quietly, tap opens it; pick Spanish, download, record, transcript
- [ ] Wave B — summary quality (prompt v3)
  - [x] Marks: quick labels after Mark (`RecorderViewModel.mark` / `labelLastMark`, 1 test), ★ lines in the summarizer input (`SummarizationInput.merge`, chunker tests), transcript flag rows (`TranscriptMarkers`, 2 tests), "Marked moments" in exports (1 test)
  - [x] Chapters: `start` on topics and areas, `topics` on client summaries, `ChapterPostProcessor` (5 tests), Audio tab list + scrubber ticks, transcript headings, "Chapters" in exports (1 test)
  - [x] Editable action items (`ActionItemsState` overrides/added/removed, `resolvedActionItems`, `ActionItemEditor`; 4 tests; exports, Reminders and the card read the resolved list)
  - [x] `docs/EVALS.md` created with the golden tables and the prompt v3 checks
  - [x] `scripts/test.sh --unit-only` green on Jeremy's Mac (2026-09-19)
  - [ ] Device: record 5 min with three labelled marks → summary cites their times, transcript shows flags; the 25-min recording → chapters within ±30 s (log in EVALS); edit an owner and a due date, add an item, send to Reminders → edited values appear
- [ ] Wave C — data
  - [x] `.veraflowarchive` package (`RecordingSnapshot`, `LibraryArchive`, `LibraryActions.exportArchive` / `importArchive`, document picker, Files import and "Open in", UTType in `project.yml`; 5 tests)
  - [x] Settings → Storage: recordings on disk, "Include recordings in iPhone backup" (off), Export library…, Recently Deleted
  - [x] "Export recording…" in a recording's menu; `audioAvailable` false shows why playback is missing
  - [x] Sample recording path (`SampleRecording`, folder reference, Library and Settings buttons, alpha seeding; 1 test). The archive itself is still to record (`VeraFlow/Resources/SampleRecording/README.md`)
  - [x] `scripts/test.sh --unit-only` green on Jeremy's Mac (2026-09-19)
  - [ ] Device: Export library to iCloud Drive → delete a recording → import the package → it's back and plays; AirDrop a single-recording package to a second iPhone; flip the backup switch and check the folder attribute in Diagnostics; record the sample with a consenting second voice and drop it in
- [ ] Wave D — the bets (each can be cut on its own)
  - [x] Custom templates (`CustomTemplate` model, `TemplatesView` / editor, Record-screen picker and focus field, hidden sections in the Summary tab and exports, `FocusLine`; 6 tests). Unlocked-only
  - [x] Ask this recording (`TranscriptRetriever` BM25 + neighbours, `QuestionService` + `AnswerValidator`, `LiveQuestionService`, `AskController`, Ask tab with suggestions and cited moments; 9 tests). Unlocked-only, sample exempt
  - [x] Translation (`TranslationService` batching, `SummaryTranslation` prose visitor, `TranslationController` + `TranslationHost` on `translationTask`, "Translate to…" / Show original / Remove, "Include translation" in exports, archives carry it; 9 tests). Unlocked-only
  - [x] Words while recording (`TranscriptPreviewService` + `PreviewReducer`, `LiveTranscriptPreview`, tap-writer sink in the recorder, `LiveTranscriptBlock`, Settings toggle, background and thermal rules; 7 tests)
  - [ ] `scripts/test.sh --unit-only` on Jeremy's Mac
  - [ ] API names to verify in Xcode (comments say "Verify against the SDK"): `LanguageAvailability.supportedLanguages` / `status(from:to:)`, `TranslationSession.translations(from:)`, `TranslationSession.Request(sourceText:clientIdentifier:)`, `translationTask(_:action:)`, `TranslationSession.Configuration.invalidate()`; `SpeechTranscriber` `.volatileResults`, `SpeechAnalyzer.start(inputSequence:)`, `cancelAndFinishNow()`, `SpeechTranscriber.Result.isFinal`
  - [ ] Device: make a "Site visit" template hiding Open questions with focus "the budget" → record → summary shows the chip, no Open questions section, export matches; Ask the sample "what was decided?" → cited moment plays, ask something not there → "not in this recording" with closest moments; Translate the sample to Spanish → pack download sheet → relaunch keeps it → PDF with both languages; 30-minute recording with the preview on → words within ~10 s, thermal state and battery noted, switch mic mid-recording → preview continues, compare the final transcript's word count with a run done with the preview off
- [ ] Wave E — older iPhones
  - [x] iOS 18 floor (`project.yml` 18.0 + weak `FoundationModels`; `@available(iOS 26, *)` on the six iOS 26 files; `PlatformPolicy`, `LegacyCapabilityService`, `UnavailableSummarizationService` / `UnavailableQuestionService` / `UnavailableTranscriptPreview`, `InlineBackgroundProcessing`; Parakeet and the engine selector out of DEBUG; onboarding and Settings copy for the 600 MB download; 4 tests)
  - [x] Bundled-model investigation: `docs/reviews/2026-09-19-bundled-model.md` (no-go for 1.2)
  - [ ] Build with the lowered target in Xcode and read the errors: anything else that turns out to be iOS 26-only gets wrapped; confirm `FoundationModels` shows as weak in `otool -L`; confirm FluidAudio 0.15.7's iOS floor (believed iOS 17)
  - [ ] Device (needs an iPhone on iOS 18; not checked in until then): install, onboarding says Parakeet downloads ~600 MB, record 5 min, full transcript with two speakers, Summary tab says summaries need iOS 26 + Apple Intelligence, no crash or memory warning; time and memory logged in DECISIONS
- [ ] Wave F — Mac (native target, universal purchase); Wave G — iPad (opens 1.2)

## Requests from device testing

- Retry in the background + "Process next" (Jeremy, 2026-09-18): built the same day. iOS suspends the app in the background, so retries that fall due while suspended fire on the next foreground; the wait backs off (3, 6, 12, 24 min); "Process next" in a row's menu (and Retry on the Summary tab) jumps the queue and retries at once.
- Record Teams/Zoom call audio + Bluetooth mic (Jeremy, 2026-09-18): not possible on iOS (no app can capture another app's audio, and the call app owns the microphone). Instead, mp4/mov meeting recordings can now be imported; the audio track is extracted on device.

- Lock Screen controls (Jeremy, 2026-09-18): Pause/Resume + Bookmark buttons on the recording Live Activity, and standard playback controls for the player. Device: Pause and Bookmark work; Resume didn't (engine paused → app suspended), fixed by keeping the engine running while paused; buttons made thumb-sized. Device 2026-09-18: Resume, button size, and playback controls all confirmed. The in-app waveform kept scrolling while paused (empty bars); fixed by not appending samples while paused. Microphone menu showed iPhone Microphone while the Bluetooth headset was the actual route and switching did nothing: the preferred input was set before the session was active, which iOS ignores; now applied after activation (re-test: record with the headset connected, menu on iPhone Microphone → console route should say the phone; switch to the headset mid-recording → route should follow). Added "Import Video from Photos" (Photos picker, videos only) since the Files picker can't reach the camera roll; mp3 was already accepted. Device: pick a video you shot → it should appear as a recording and transcribe. Mic switch on device: phone → headset worked, headset → phone didn't, and choices took 3–4 taps. Removed the route-change reload pushing a fallback port to the recorder (it could undo a switch mid-change); Device 2026-09-18 (second run): phone → headset → phone → headset → phone all switched on the first tap, with the 48/16 kHz re-tap logged each time and the recording continuous. Note: switching mics mid-recording makes the diarizer hear one person as two (16 kHz call audio vs 48 kHz phone mic), so pick a mic before starting. Third run showed the real first-tap bug: right after switching to Bluetooth the phone mic is briefly missing from iOS's input list, and the recorder refused the tap; it now waits up to a second for the list to settle. Fourth run: a tap produced no `mic tap` line at all, so the menu itself dropped it; the picker is now its own view so the 10 Hz timer/level redraws don't rebuild an open menu. Fifth run: phone, headset, Automatic, phone, every tap took first time. Closed. Photos video import confirmed on device (2:17 stereo track → m4a, 111 words, summary). Files import (mp3/m4a/mp4) still to try on device. Expected speakers = 3 relabel on the 4:40 recording: 3 centroids (124/12/2 windows) but the 2-window cluster was absorbed and the result stayed at 2 speakers; Jeremy isn't sure that recording has a third speaker, so it isn't a failure. FluidAudio's zero-vote re-embed pass is enabled anyway (documented fix for absorbed turns). Multi-speaker check done: a separate device recording with five speakers was labelled correctly on Automatic (Jeremy, 2026-09-18). A 3-host podcast played through a speaker and recorded with the phone mic (2:22, 507 words) came out as exactly 3 speakers on Automatic: clustering 18/29/21 windows plus two one-window strays that reconstruction dropped (Jeremy, 2026-09-18).

- Filter the transcript by speaker (Jeremy, 2026-09-19): "pull up their clips". The design spec's Transcript screen already lists a speaker filter next to search. Planned shape: a row of speaker chips under the transcript search (All + one per speaker); one chip shows only that person's paragraphs, each still playable from its timecode, with the match count reading "12 paragraphs · 4:52 of talk time"; the Audio tab's talk-time rows would open the transcript already filtered to that speaker. Pure filtering over the existing segments, no model work. Not started.

- Auto-archive and cleanup (Jeremy, 2026-09-19; parked, "keep it as a thing to think about"): audio is the bulk (about 28 MB per hour at 64 kbps AAC; transcript and summary are kilobytes). Proposed: Settings shows storage used by recordings; "Archive audio older than 30 / 90 / 180 days" removes the audio file and keeps transcript, labels, summary and action items usable, with the card marked "audio archived" and playback hidden. Backup stays the user's move, never the app's: an optional "Move audio to Files" step hands the file to the system picker (iCloud Drive, Google Drive or any file provider) with no network call from VeraFlow, and "Restore audio" picks it back up; recordings stay excluded from device backup. Cleanup already done at launch: tmp exports, photo imports, Inbox. Not started.

- Live transcription while recording (Jeremy, 2026-09-18): start showing words about 10 s into a recording instead of after Stop. `SpeechAnalyzer` accepts streaming input, so the tap's buffers could feed it live and the file pass at the end would still produce the final, timed transcript. Built in v1.1 Wave D (2026-09-19) as the words-while-recording preview; the file pass is unchanged. Device check pending (see M10).

## Notes / blockers
