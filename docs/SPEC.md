# VeraFlow — Build Spec

> Private, on-device meeting recorder for iPhone. Record → transcribe → speaker labels → summary + action items. No servers, no account, no subscription. One-time unlock.
>
> **Product Name:** `VeraFlow`
> **Demo / Alpha Codename:** `Riffle` (internal/demo version)
> **Owner:** Jeremy
> **Spec version:** 1.0 · September 17, 2026
> **Primary platform:** iOS (native Swift/SwiftUI). Android is Phase 2 (§17).
> **Build tools:** Claude Code and Google Antigravity (§18)

---

## Table of contents

1. Product summary
2. Positioning and competitors
3. v1 scope and non-goals
4. Core user flows
5. Tech stack and minimum requirements
6. Architecture
7. Data model
8. Recording
9. Transcription
10. Speaker labels (diarization)
11. Summaries, action items, templates
12. Exports
13. Monetization (one-time unlock)
14. Privacy, consent, App Store compliance
15. Device capability matrix and fallbacks
16. Milestones with acceptance criteria
17. Phase 2: Android
18. Working with Claude Code and Antigravity
19. Risks and open questions
20. References

---

## 1. Product summary

**Problem.** Otter, Fireflies and similar tools cost $17–20/month, upload your audio to their servers, and get pricey for small-business owners who only record a few meetings a week.

**Solution.** An iPhone app that does all the work on the phone:

1. Records meetings, calls on speaker, lectures, or job-site walk-throughs.
2. Transcribes on device with Apple's Speech framework (`SpeechAnalyzer`).
3. Labels speakers on device (FluidAudio diarization).
4. Produces a structured summary with **action items (task, owner, due date)** using Apple's on-device Foundation Models, formatted by a **template** that matches the kind of recording.
5. Exports to Markdown, PDF, plain text, email draft, and Apple Reminders.

**Business model.** Free download. Recording and transcripts are free and unlimited. A one-time in-app purchase unlocks unlimited AI summaries, all templates, and exports. Nothing runs on servers, so there are no running costs to pass on to buyers.

**Differentiator.** "Private + no subscription" is not enough on its own, because cheap competitors already offer it (§2). The edge is **output that's useful after the meeting**: templates built for specific jobs (client meetings, contractor walk-throughs), clean action items with owners and resolved due dates, and one-tap follow-up (email draft, Reminders).

---

## 2. Positioning and competitors

| Product | Price | On-device | Summaries / action items | Speaker labels | Notes |
|---|---|---|---|---|---|
| Otter.ai | ~$17/mo | No | Yes | Yes | Cloud; meeting bots |
| iPhone Notes (built in) | Free | Yes | Summary (Apple Intelligence) | No | Generic, no action-item workflow |
| Google Recorder (Pixel) | Free | Yes | Varies | Yes | Pixel only |
| Synopsule | $1.99 + optional $4.99/mo Pro | Yes | Templates, action items | Yes | Closest competitor |
| Viska | $4.99–6.99 one-time | Yes | Yes | No | iOS + Android |
| WhisperNotes | $4.99 one-time | Yes | No | No | Transcription only |

**Positioning line (draft):** *"Your meetings, turned into a to-do list — without the subscription or the cloud."*

**Why buyers would pick VeraFlow:**
- Templates tuned for real work (a contractor walk-through becomes scope, measurements, materials, quote notes).
- Action items that are *actionable*: owner, resolved due date, jump-to-audio timestamp, send to Reminders.
- Fair one-time price, no upsell subscription.

---

## 3. v1 scope and non-goals

### In scope (v1)
- Record in-app (background-safe, interruption-safe, crash-recoverable).
- Import audio files (Files app, share sheet from Voice Memos and others).
- On-device transcription with timestamps; synced playback; tap a line to seek; search; edit transcript text.
- On-device speaker labels; rename speakers (renames apply across the whole recording).
- AI summaries using 3 templates:
  1. **General meeting / lecture**
  2. **Client / consulting meeting**
  3. **Contractor job walk-through**
- Re-run a summary with a different template.
- Exports: Markdown, PDF, plain text, copy to clipboard, email draft, action items → Apple Reminders.
- Library: list, search (titles + transcripts), sort, folders or tags (tags are fine).
- One-time unlock via StoreKit 2; restore purchases; Family Sharing on.
- Recording-consent reminder.
- English (US) first. The architecture must not assume English, but don't test other languages in v1.

### Non-goals (v1)
- No cloud features, account, sync server, or analytics SDKs.
- No Zoom/Teams/Meet bot joining.
- No healthcare/clinical template; the app must not make HIPAA claims.
- No live AI summary during recording (live transcript preview is optional/stretch).
- No Mac, iPad-optimized, or Apple Watch app (iPad can run the iPhone layout).
- No Android (Phase 2).
- No Private Cloud Compute or third-party LLM APIs. v1 is strictly on-device (§11.7).

---

## 4. Core user flows

### 4.1 First launch
1. Three-screen onboarding: what it does → "everything stays on your iPhone" → mic permission.
2. Capability check (§15). Show honest messaging if Apple Intelligence isn't available: "Transcripts work on this iPhone; AI summaries need an Apple Intelligence–capable iPhone."
3. Speech model asset download if needed (show progress). Diarization model download (show progress, one time).

### 4.2 Record
1. Tap the big record button → consent reminder sheet (can be turned off in Settings) → recording starts.
2. Recording screen: timer, live level meter, pause/resume, stop, add bookmark (flag a moment), optional template pre-select.
3. Recording continues with the screen locked or the app in the background. Optional Live Activity shows the timer.
4. Stop → name the recording (auto-suggest date + time, e.g. "Meeting · Sep 17, 2:30 PM"; replace with AI title later) → processing starts automatically.

### 4.3 Processing pipeline (automatic, resumable)
`Recorded → Transcribing → Labeling speakers → Summarizing → Ready`
- Each stage saves its output before the next begins. If the app is killed, processing resumes from the last completed stage.
- Status shows on the library row with progress.
- The user can open the recording and read the transcript as soon as transcription finishes.

### 4.4 Review
Recording detail has 3 tabs:
- **Summary**: template output; action items with checkboxes; each item shows owner, due date, and a ▶︎ timestamp link.
- **Transcript**: speaker-labeled paragraphs with timestamps; audio player pinned at the bottom; the current line highlights during playback; tap a line to seek; edit mode.
- **Audio**: waveform, bookmarks, playback speed (1×, 1.5×, 2×), skip silence (stretch).

### 4.5 Act
- Share menu: Markdown / PDF / text / copy.
- "Send action items to Reminders" → choose a list → creates reminders with due dates.
- "Draft follow-up email" (Client template) → opens Mail compose prefilled.

---

## 5. Tech stack and minimum requirements

| Area | Choice |
|---|---|
| Language / UI | Swift 6 (strict concurrency), SwiftUI |
| IDE / SDK | Xcode 26+ with iOS 26+ SDK |
| Minimum iOS | **iOS 26.0** (required for `SpeechAnalyzer`). Use iOS 27 APIs behind `#available(iOS 27, *)` |
| Persistence | SwiftData |
| Audio capture / playback | AVFoundation (`AVAudioEngine` + `AVAudioFile`, `AVAudioPlayer`) |
| Transcription | Speech framework: `SpeechAnalyzer` + `SpeechTranscriber` (fallback `DictationTranscriber`) |
| Speaker labels | [FluidAudio](https://github.com/FluidInference/FluidAudio) (Swift Package, Apache-2.0, Core ML) |
| Summaries | Foundation Models framework (`LanguageModelSession`, `@Generable`, `@Guide`) |
| Background processing | BackgroundTasks: `BGContinuedProcessingTaskRequest` (iOS 26+) |
| Purchases | StoreKit 2 (non-consumable) |
| Reminders | EventKit |
| Email | `MFMailComposeViewController` (fallback: `mailto:` / share sheet) |
| PDF | `ImageRenderer` → PDF, or UIKit `UIGraphicsPDFRenderer` |
| Tests | Swift Testing (`@Test`) for logic; XCUITest for flows |
| Dependencies | Keep to **FluidAudio only**. Any new package needs a written reason in `docs/DECISIONS.md` |

---

## 6. Architecture

### 6.1 Layers
```
App (SwiftUI views, navigation)
  └── Features (Library, Recorder, RecordingDetail, Settings, Paywall, Onboarding)
        └── Services (protocol-based, injectable, testable)
              ├── AudioRecorderService
              ├── AudioImportService
              ├── TranscriptionService      (SpeechAnalyzer)
              ├── DiarizationService        (FluidAudio)
              ├── TranscriptAligner         (pure Swift: merges words + speaker turns)
              ├── SummarizationService      (Foundation Models, map-reduce)
              ├── DueDateResolver           (pure Swift + NSDataDetector)
              ├── ExportService             (MD / PDF / TXT / Reminders / Mail)
              ├── PipelineCoordinator       (stage machine, resumable, background task)
              ├── CapabilityService         (§15)
              └── PurchaseService           (StoreKit 2)
        └── Persistence (SwiftData models, file storage)
```

### 6.2 Rules
- Every service sits behind a protocol, with a fake implementation for tests and SwiftUI previews.
- Use `@Observable` view models, `async/await`, and actors for services that hold mutable state. No Combine unless required by an API.
- **No network code** anywhere except OS-managed and FluidAudio model downloads (§14.1). Add a unit test that fails if `URLSession` shows up in app targets outside an allow-listed `ModelDownload` file.
- Store audio files in `Application Support/Recordings/<uuid>/`, excluded from iCloud backup by default (Settings toggle to include).

### 6.3 Pipeline state machine
```swift
enum PipelineStage: String, Codable {
  case recording,   // capture in progress (used for crash recovery)
       recorded, transcribing, transcribed,
       diarizing, diarized,
       summarizing, ready,
       failed   // with stage + error message persisted
}
```
- `PipelineCoordinator` runs one recording at a time (a FIFO queue).
- It persists the stage after each step, and resumes queued or interrupted work on launch.
- It wraps a processing run in a `BGContinuedProcessingTaskRequest` so work can continue if the user leaves the app. It reports progress and handles expiration by saving partial state and re-queueing.
- Diarization failure is **non-fatal**: continue with a single "Speaker" label and show a retry button.
- Summary failure is **non-fatal**: the transcript remains usable; show a retry button.

---

## 7. Data model (SwiftData)

```swift
@Model final class Recording {
  @Attribute(.unique) var id: UUID
  var title: String
  var createdAt: Date
  var duration: TimeInterval
  var audioFileName: String          // relative to recording folder
  var source: RecordingSource        // .recorded / .imported
  var stage: PipelineStage
  var failureMessage: String?
  var localeIdentifier: String       // BCP-47, e.g. "en-US"
  var templateID: TemplateID         // .general / .client / .walkthrough
  var tags: [String]
  var isFavorite: Bool
  @Relationship(deleteRule: .cascade) var segments: [TranscriptSegment]
  @Relationship(deleteRule: .cascade) var speakers: [Speaker]
  @Relationship(deleteRule: .cascade) var bookmarks: [Bookmark]
  @Relationship(deleteRule: .cascade) var summaries: [SummaryRecord] // history; newest is current
}

@Model final class TranscriptSegment {       // one speaker turn / paragraph
  var index: Int
  var start: TimeInterval
  var end: TimeInterval
  var text: String                            // user-editable
  var originalText: String                    // as transcribed
  var speakerKey: String?                     // "S1", "S2"...
  var wordsData: Data?                        // encoded [TimedWord] for highlight/seek
}

@Model final class Speaker {
  var key: String          // "S1"
  var displayName: String  // "Speaker 1" → user renames to "Dave"
  var colorIndex: Int
}

@Model final class Bookmark { var time: TimeInterval; var note: String? }

@Model final class SummaryRecord {
  var id: UUID
  var createdAt: Date
  var templateID: TemplateID
  var payloadJSON: Data       // encoded template output struct (§11.4)
  var actionItemsState: Data  // completion checkboxes, reminder IDs
  var modelInfo: String       // e.g. "SystemLanguageModel iOS 27.0"
}

struct TimedWord: Codable { var text: String; var start: TimeInterval; var end: TimeInterval }
```

---

## 8. Recording

### 8.1 Session
- `AVAudioSession` category `.playAndRecord`, mode `.default`, options `[.allowBluetoothHFP, .defaultToSpeaker]`. Let user choose input (built-in / AirPods / USB mic).
- Info.plist: `NSMicrophoneUsageDescription`, and `UIBackgroundModes` = `audio` (continue recording while locked or backgrounded).

### 8.2 Crash-safe file format
- Record with `AVAudioEngine` input tap → `AVAudioFile` in **CAF container, AAC, mono, 44.1 kHz, ~64 kbps** (~29 MB/hour). CAF stays readable if writing is cut off.
- On stop: keep CAF as master (or export to `.m4a` for sharing only when exporting audio).
- On launch: scan for recordings with `stage == .recording` (in-progress flag), finalize duration from file, mark `.recorded`.

### 8.3 Interruptions and routes
- Observe `AVAudioSession.interruptionNotification`: on call, auto-pause and insert bookmark "Interrupted"; on resume, offer user prompt.
- Observe `routeChangeNotification`: if headset disconnects, keep recording on built-in mic.
- Disk space warnings: warn at < 500 MB; stop gracefully at < 100 MB.

---

## 9. Transcription (SpeechAnalyzer)

### 9.1 Setup
1. Check `SpeechTranscriber.isAvailable`. If false, fallback to `DictationTranscriber`.
2. Locale check via `SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)`.
3. Asset check via `AssetInventory.assetInstallationRequest(supporting: [transcriber])`.
4. File config: `attributeOptions: [.audioTimeRange]`.

### 9.2 File pass
Use `SpeechAnalyzer` with `SpeechTranscriber`, process audio file, collect `[TimedWord]`. Handle errors and de-duplicate across chunk boundaries if required.

---

## 10. Speaker labels (FluidAudio)

- Integrated via Swift Package: `https://github.com/FluidInference/FluidAudio.git`.
- Offline diarization pipeline.
- `TranscriptAligner`: pure Swift alignment between `TimedWord`s and speaker turns with smoothing.

---

## 11. Summaries, action items, templates

- Check `SystemLanguageModel.default.availability`.
- Context budgeting with 4,096 tokens (iOS 26) / runtime `contextSize` (iOS 27+).
- Map-reduce architecture for transcripts larger than context limit.
- 3 built-in templates: General meeting, Client/consulting meeting, Contractor job walk-through.
- Pure Swift deterministic post-processing: deduplication, `DueDateResolver` with `NSDataDetector`, timestamp validation.

---

## 12. Exports

- Formats: Markdown, PDF, plain text, clipboard copy, email draft, Reminders, audio export (.m4a).

---

## 13. Monetization (one-time unlock)

- Product ID: `veraflow.unlock.lifetime` (alpha/demo fallback: `riffle.unlock.lifetime`).
- Free tier: unlimited recording and transcripts; 3 free AI summaries; plain text export.
- Unlocked tier: unlimited AI summaries, all templates, all exports.
- Keychain-backed free counter.

---

## 14. Privacy, consent, App Store compliance

- Zero user-data network requests.
- Privacy manifest (`PrivacyInfo.xcprivacy`).
- Explicit pre-record consent reminder.
- Safe audio storage with `completeUntilFirstUserAuthentication`.

---

## 15. Device capability matrix and fallbacks

- `CapabilityService` monitoring transcription, Apple Intelligence, model downloads, and background processing.
- Hidden Diagnostics screen (tap version number 7×).

---

## 16. Milestones with acceptance criteria

- **M0: Project foundation** — Architecture skeleton, protocols, fakes, tests, CI.
- **M1: Recording** — Audio capture, CAF crash-safety, level meter, interruptions.
- **M2: Library and import** — File management, tags, favorites, import from Files/Share.
- **M3: Transcription** — `SpeechAnalyzer` pipeline, timestamps, synced playback, search/edit.
- **M4: Speaker labels** — FluidAudio diarization, `TranscriptAligner`, speaker renames/merges.
- **M5: Summaries and templates** — Foundation Models, map-reduce, 3 templates, `DueDateResolver`.
- **M6: Exports** — Markdown, PDF, text, email draft, Reminders, audio export.
- **M7: Onboarding, settings, capability messaging, privacy** — Onboarding, permissions, zero-network test.
- **M8: Purchases** — StoreKit 2 lifetime unlock, Keychain free count, restore.
- **M9: Polish and ship** — Accessibility, TestFlight, App Store checklist.

---

## 17. Phase 2: Android

Kotlin + Jetpack Compose architecture mirroring the iOS service pipeline.

---

## 18. Working with Claude Code and Antigravity

### 18.1 Repo setup
```
VeraFlow/
├── CLAUDE.md                  ← Claude Code reads this automatically
├── .agents/rules/project.md   ← Antigravity workspace rules
├── docs/
│   ├── SPEC.md                ← this file (source of truth)
│   ├── DECISIONS.md           ← dated decisions + reasons
│   ├── EVALS.md               ← summary quality log per fixture/template
│   └── PROGRESS.md            ← milestone checklist, updated by agents
├── VeraFlow/ (Xcode project source)
├── VeraFlowTests/
├── VeraFlowUITests/
├── TestAudio/                 ← fixtures, gitignored
└── scripts/test.sh
```

### 18.2 Division of labor
- One agent per branch; merge through PRs.
- **Claude Code:** Primary builder.
- **Antigravity:** Reviewer and parallel worker for isolated pure-Swift modules (`TranscriptAligner`, `DueDateResolver`, exporters), documentation, and Android Phase 2.

### 18.3 Session habits
- Read `docs/SPEC.md` and `docs/PROGRESS.md` at session start.
- Plan first, approve, build with unit tests.
- Always run `scripts/test.sh` before committing.

---

## 19. Risks and open questions

1. Apple Intelligence availability constraints.
2. Context window budgeting for long audio transcripts.
3. Diarization accuracy during crosstalk.
4. Background processing task expiration.
5. Pricing and value proposition.
6. Local model bundling evaluation for FluidAudio.

---

## 20. References

- Apple SpeechAnalyzer docs & WWDC sessions.
- Apple Foundation Models framework docs.
- Apple BackgroundTasks (`BGContinuedProcessingTaskRequest`).
- FluidAudio (Swift Package): https://github.com/FluidInference/FluidAudio
