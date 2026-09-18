# M7 plan — Onboarding, settings, capability messaging, privacy (SPEC §4.1, §14, §15, §16 M7)

Written and implemented 2026-09-18 while Jeremy was away.

- **Onboarding** (`OnboardingView`): four pages — what it does → everything stays on your iPhone → microphone permission (asks through the recorder service) → what this iPhone can do (honest Apple Intelligence copy per reason, "Standard accuracy" note, optional speech-model download with progress). Completion stored in `AppPreferences`; `RootView` gates the Library on it. UI tests skip it unless launched with `--show-onboarding`.
- **Consent reminder** (`ConsentSheet`, SPEC §14.2 copy verbatim): shown before Start Recording, "Don't show again" toggle, Settings toggle to turn it back on. Off automatically for UI tests.
- **Capabilities** (`LiveCapabilityService`): speech engine (`SpeechTranscriber.isAvailable` / `DictationTranscriber.supportedLocales`), asset status, diarizer models, summarizer availability, runtime token counting (iOS 26.4+), background processing (device only), OS version.
- **App lock** (`AppLock`, SPEC §14.4): Face ID / passcode via `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`; locks on background, `LockScreenView` overlay on return; disabled when the device has no passcode. `NSFaceIDUsageDescription` added.
- **Delete all data** (`LibraryActions.deleteAll`): rows, folders (orphans too), queued work; confirmation dialog in Settings.
- **Diagnostics** (`DiagnosticsView`, SPEC §15): unlocked by seven taps on the version and kept unlocked; shows every capability, model info, prompt version, model source, storage, recordings with failures, per-stage timings and the recent event log (`AppState.recentEvents`, `PipelineTimeline`).
- **AI disclaimer** under every summary (SPEC §14.3) and the privacy copy in Settings. Privacy manifest already lists UserDefaults, file timestamps, and disk space (SPEC §14.1).

Device checks: fresh install shows the four pages; a non–Apple Intelligence phone shows the "Transcripts work…" copy and still transcribes; consent sheet appears once and honours "Don't show again"; Face ID lock engages on return from background; Delete all data empties the Library; Diagnostics appears after seven taps; a proxy shows only Apple/Hugging Face/StoreKit traffic.
