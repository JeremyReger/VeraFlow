# Progress

Update this file at the end of every session. Check an item only when its "Done when" criteria (SPEC §16) pass on a real device.

- [ ] M0 — Project foundation (code written; needs `scripts/test.sh` green on a Mac and a launch on a real device)
  - [x] `project.yml` (XcodeGen): iOS 26.0 min, Swift 6 strict concurrency, FluidAudio pinned to 0.15.7, `Alpha` config named "Riffle (alpha)"
  - [x] Folder structure per SPEC §6.1 (App / Features / Services / Persistence)
  - [x] SwiftData models per SPEC §7 and `PipelineStage` per §6.3
  - [x] Protocol + fake for every service in §6.1; `AppServices` container injected through the SwiftUI environment
  - [x] `RecordingStorage` (Application Support/Recordings/<uuid>/, backup-excluded, file protection)
  - [x] Preview data; empty Library screen; placeholder screens for later milestones
  - [x] Swift Testing unit tests, network-policy test (§6.2), single-dependency test, XCUITest launch test
  - [x] `scripts/test.sh`, `PrivacyInfo.xcprivacy`, `docs/DECISIONS.md`
  - [ ] `xcodegen generate` + `scripts/test.sh` pass on Jeremy's Mac with no strict-concurrency warnings
  - [ ] App launches to an empty Library on a device
- [ ] M1 — Recording
- [ ] M2 — Library and import
- [ ] M3 — Transcription (+ SpeechAnalyzer vs Parakeet benchmark)
- [ ] M4 — Speaker labels
- [ ] M5 — Summaries and templates
- [ ] M6 — Exports
- [ ] M7 — Onboarding, settings, capability messaging, privacy
- [ ] M8 — Purchases
- [ ] M9 — Polish and ship

## Notes / blockers
