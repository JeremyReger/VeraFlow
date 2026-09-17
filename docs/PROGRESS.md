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
- [ ] M1 — Recording (code written; needs `scripts/test.sh` green on a Mac and the §16 device checks)
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
  - [ ] Device: 90-minute recording with the screen locked plays back fully
  - [x] Device: force-quit mid-recording recovers a playable file (first try FAILED with CAF/AAC; after switching capture to ADTS: recovered alert, 0:09 row, plays)
  - [x] Device: a phone call pauses, adds an "Interrupted" bookmark, and offers resume (4:40 recording plays back)
- [ ] M2 — Library and import
- [ ] M3 — Transcription (+ SpeechAnalyzer vs Parakeet benchmark)
- [ ] M4 — Speaker labels
- [ ] M5 — Summaries and templates
- [ ] M6 — Exports
- [ ] M7 — Onboarding, settings, capability messaging, privacy
- [ ] M8 — Purchases
- [ ] M9 — Polish and ship

## Notes / blockers
