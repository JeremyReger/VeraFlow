# Milestone Progress — VeraFlow

Track the implementation of each milestone (§16 of `docs/SPEC.md`). Each milestone is built on its own branch, tested against acceptance criteria, reviewed, and merged via PR.

---

## Milestone Checklist

- [x] **M0: Project Foundation**
  - [x] Repository initialized with documentation suite (`docs/SPEC.md`, `CLAUDE.md`, `.agents/rules/project.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/EVALS.md`)
  - [x] Xcode project `VeraFlow` configured (iOS 26.0 min, Swift 6 strict concurrency, SwiftData)
  - [x] Service protocols defined with fake implementations for every service (§6.1)
  - [x] SwiftData models (`Recording`, `TranscriptSegment`, `Speaker`, `Bookmark`, `SummaryRecord`)
  - [x] FluidAudio package dependency integration
  - [x] Test script `scripts/test.sh` passing with zero concurrency warnings

- [x] **M1: Recording**
  - [x] `AVAudioSession` configuration (`.playAndRecord`, Bluetooth, speaker default)
  - [x] Crash-safe CAF container recording with `AVAudioEngine`
  - [x] Pause / resume / stop / bookmarks
  - [x] Live audio level metering
  - [x] Interruption handling (phone calls auto-pause with bookmark)
  - [x] Route change handling (headset disconnect)
  - [x] Disk space warnings (< 500 MB warning, < 100 MB stop)
  - [x] Launch crash-recovery scanner for in-progress recordings

- [x] **M2: Library and Import**
  - [x] SwiftData library list with search, sort, tags, favorites
  - [x] File import (Share Sheet / Files app) for m4a/mp3/wav/caf
  - [x] Recording rename and deletion (cleans audio files)

- [x] **M3: Transcription**
  - [x] `SpeechAnalyzer` + `SpeechTranscriber` pipeline with `AssetInventory` downloads
  - [x] `DictationTranscriber` fallback
  - [x] Timed word extraction (`[TimedWord]`) and paragraphing rules
  - [x] Progress reporting and resumable pipeline state
  - [x] Synced playback highlight, tap-to-seek, transcript text editing
  - [x] Benchmark `SpeechAnalyzer` vs FluidAudio Parakeet ASR

- [x] **M4: Speaker Labels**
  - [x] FluidAudio offline diarization integration
  - [x] `TranscriptAligner` (pure Swift alignment + smoothing) with unit tests
  - [x] Speaker rename (propagates across transcript and summaries)
  - [x] Speaker merge and turn reassignment
  - [x] Non-fatal failure fallback (single speaker + retry)

- [ ] **M5: Summaries and Templates**
  - [ ] Apple Foundation Models `LanguageModelSession` integration & availability check
  - [ ] Token budgeting and chunking (4K / 8K context)
  - [ ] Map-reduce pipeline for long recordings
  - [ ] 3 templates: General Meeting, Client/Consulting, Contractor Walk-Through
  - [ ] Action item extraction (`task`, `owner`, `dueText`, `timestamp`)
  - [ ] Pure Swift deterministic post-processing:
    - [ ] Deduplication
    - [ ] `DueDateResolver` (`NSDataDetector` + rules)
    - [ ] Speaker key resolution and audio timestamp clamping
  - [ ] Re-run summary with alternative template
  - [ ] Quality logging in `docs/EVALS.md`

- [ ] **M6: Exports**
  - [ ] Markdown export (`.md`)
  - [ ] PDF export with clean typographic layout
  - [ ] Plain text copy (`.txt`)
  - [ ] Email draft pre-fill (`MFMailComposeViewController`)
  - [ ] Apple Reminders sync via EventKit
  - [ ] Audio export (`.m4a`)

- [ ] **M7: Onboarding, Settings, Capability Messaging, Privacy**
  - [ ] 3-screen onboarding flow with mic permission request
  - [ ] Honest capability messaging for devices without Apple Intelligence
  - [ ] Recording consent reminder sheet with "Don't show again"
  - [ ] Settings screen with consent toggle, disk usage, model status
  - [ ] Hidden Diagnostics screen (tap version number 7×)
  - [ ] Face ID lock (`LocalAuthentication`)
  - [ ] "Delete all data" action
  - [ ] Zero-network test validation

- [ ] **M8: Purchases**
  - [ ] StoreKit 2 non-consumable lifetime unlock (`veraflow.unlock.lifetime`)
  - [ ] Free tier tracking (3 free AI summaries) backed by Keychain + UserDefaults
  - [ ] Paywall sheet with clear disclosure on unsupported AI devices
  - [ ] Restore purchases & Family Sharing support

- [ ] **M9: Polish and Ship**
  - [ ] Dynamic Type & VoiceOver accessibility audit
  - [ ] Dark mode and empty state polish
  - [ ] TestFlight distribution with test fixtures and feedback
  - [ ] App Store checklist verification
