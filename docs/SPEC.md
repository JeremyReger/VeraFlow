# VeraFlow — Build Spec

> Private, on-device meeting recorder for iPhone. Record → transcribe → speaker labels → summary + action items. No servers, no account, no subscription. One-time unlock.
>
> **Product name:** `VeraFlow` (App Store name; search App Store + USPTO before M9, §19)
> **Alpha / demo codename:** `Riffle` — the name used for pre-release builds (TestFlight alpha, demo mode, internal fixtures). See §0.
> **Owner:** Jeremy
> **Spec version:** 1.1 · September 17, 2026
> **Primary platform:** iOS (native Swift/SwiftUI). Android is Phase 2 (§17).
> **Build tools:** Claude Code and Google Antigravity (§18)

---

## Table of contents

0. Naming
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

## 0. Naming

| Name | Where it is used |
|---|---|
| **VeraFlow** | The product. App Store listing, marketing site, bundle display name for release builds, Xcode project and targets (`VeraFlow`, `VeraFlowTests`, `VeraFlowUITests`), scheme, StoreKit product IDs, repo name. |
| **Riffle** | The alpha / demo version. Use it as the display name for TestFlight alpha builds and the in-app demo mode, and as the name of sample/demo data and fixtures. It never appears on the App Store listing. |

Rules:
- Code identifiers, module names, and product IDs use `VeraFlow`. Don't create a second set of identifiers for the alpha.
- The alpha display name is a build setting (a `PRODUCT_NAME`/`CFBundleDisplayName` override in an `Alpha` build configuration), not a fork of the code.
- Copy in the app says "VeraFlow"; the alpha configuration may show "Riffle (alpha)" on the home screen so testers can tell builds apart.

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

### v1.1 additions (plan: `docs/plans/2026-09-19-v1-1.md`)
- Transcript speaker filter; skip silence in playback; Recently Deleted (30 days); a local notification when a summary is ready; a transcription-language picker and "transcribe again in…".
- Marks carry a label and are weighted and cited by the summary; chapters from the summary's subjects; action items editable by hand.
- A `.veraflowarchive` package for moving or keeping the whole library or one recording; an "include in iPhone backup" switch (off by default); a bundled sample recording.
- Wave D: custom templates (a built-in base, hidden sections, a focus line); "Ask this recording" (retrieval in Swift, one model call, every answer cites a moment or says the recording doesn't have it; the questions are kept with the recording, a follow-up resolves against the previous answer, and an answer can be copied); words while recording (a second `SpeechAnalyzer` with volatile results, no speaker tags, foreground only); on-device translation of the transcript and the summary's prose with Apple's Translation framework.
- Wave E: an iOS 18 floor. iPhones on iOS 18–25 transcribe with FluidAudio's Parakeet and get speaker labels; summaries, Ask and live words need iOS 26. The bundled-model question is answered in `docs/reviews/2026-09-19-bundled-model.md` (no-go for 1.2).
- Wave F: a native Mac app (`VeraFlow-macOS`, macOS 26, Apple silicon for summaries). The same SwiftUI screens, view models, services and pipeline; the Library is a sidebar and the recording fills the detail column; the microphone list comes from Core Audio; exports go through the save panel and Mail; drag a file onto the window to import it. No Live Activity, no continued-processing task (the Mac keeps running), no privacy cover on losing focus. One App Store record with universal purchase, so the iPhone unlock covers the Mac. The iPad layout opens 1.2.

### Non-goals (v1)
- No cloud features, account, sync server, or analytics SDKs.
- No Zoom/Teams/Meet bot joining.
- No healthcare/clinical template; the app must not make HIPAA claims.
- No live AI summary during recording (live transcript preview is optional/stretch).
- No iPad-optimized or Apple Watch app (iPad can run the iPhone layout). The native Mac app arrived in v1.1 (above).
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
| IDE / SDK | Xcode 27 with the iOS 27 SDK |
| Minimum iOS | **iOS 18.0** since v1.1 (plan item 16). `SpeechAnalyzer`, Foundation Models, `BGContinuedProcessingTaskRequest` and the live preview are iOS 26 and sit behind `@available(iOS 26, *)`; iOS 18–25 transcribe with Parakeet. Use iOS 27 APIs behind `#available(iOS 27, *)` |
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

**Development machine:** a Mac with Xcode (required for iOS builds). **Test devices:** at least one Apple Intelligence–capable iPhone (iPhone 15 Pro or newer) plus, ideally, one older iOS 26 iPhone to test the no-AI fallback. The Simulator can't test microphone, background recording, or real performance; use real devices for those.

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
```
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
  // v1.1
  var deletedAt: Date?                // Recently Deleted; swept after 30 days
  var audioAvailable: Bool            // false when an archive came without the audio
}

@Model final class TranscriptSegment {       // one speaker turn / paragraph
  var index: Int
  var start: TimeInterval
  var end: TimeInterval
  var text: String                            // user-editable
  var originalText: String                    // as transcribed
  var speakerKey: String?                     // "S1", "S2"...
  var wordsData: Data?                        // encoded [TimedWord] for highlight/seek
  // v1.1
  var translatedText: String?                 // this paragraph in another language (plan item 14)
  var translationLanguage: String?            // BCP-47 of that language
}

@Model final class Speaker {
  var key: String          // "S1"
  var displayName: String  // "Speaker 1" → user renames to "Dave"
  var colorIndex: Int
}

@Model final class Bookmark { var time: TimeInterval; var note: String?; var kind: BookmarkKind /* v1.1: .manual / .interrupted; note = the quick label */ }

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

Full-text search: v1 can use a SwiftData `#Predicate` with `localizedStandardContains` over title + segment text. If it's slow above ~200 recordings, add a denormalized `searchText` field on `Recording`.

---

## 8. Recording

### 8.1 Session
- `AVAudioSession` category `.playAndRecord`, mode `.default`, options `[.allowBluetoothHFP, .defaultToSpeaker]`. Verify the Bluetooth option name against the current SDK. Let the user choose the input (built-in / AirPods / USB mic).
- Info.plist: `NSMicrophoneUsageDescription`, and `UIBackgroundModes` = `audio` (continue recording while locked or backgrounded).

### 8.2 Crash-safe file format
- **Don't record straight to `.m4a`.** An MPEG-4 file isn't playable if the app is killed before it finalizes.
- Record with `AVAudioEngine` input tap → `AVAudioFile` in **CAF container, AAC, mono, 44.1 kHz, ~64 kbps** (~29 MB/hour). CAF stays readable if writing is cut off.
- On stop: keep CAF as the master (or export to `.m4a` for sharing only when exporting audio).
- On launch: scan for recordings with `stage == .recording` (an in-progress flag), finalize duration from the file, mark `.recorded`, and tell the user "Recovered an interrupted recording."

### 8.3 Interruptions and routes
- Observe `AVAudioSession.interruptionNotification`: on a phone call, auto-pause and insert a bookmark "Interrupted"; on `.ended` with `.shouldResume`, show "Resume recording?" (don't auto-resume silently).
- Observe `routeChangeNotification`: if a headset disconnects, keep recording on the built-in mic.
- Warn when free disk space is < 500 MB; stop gracefully at < 100 MB.

### 8.4 Nice-to-have
- Live Activity + Dynamic Island timer (ActivityKit).
- App Intent / Control Center control: "Start VeraFlow recording."
- Live transcript preview during recording (SpeechAnalyzer supports live input with volatile results). Stretch; the final transcript still comes from the file pass for quality.

---

## 9. Transcription (SpeechAnalyzer)

> Verify every API name below against the current SDK docs before coding. Apple's shipping API has differed from WWDC slides before (e.g. no `.offlineTranscription` preset shipped).

### 9.1 Setup
1. **Availability:** check `SpeechTranscriber.isAvailable`. If false, use `DictationTranscriber` (older devices, lower quality) and record which one was used.
2. **Locale:** `SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)`; compare with `.identifier(.bcp47)`. Never compare `Locale` objects directly; differently built locales may not be equal.
3. **Assets:** `AssetInventory.assetInstallationRequest(supporting: [transcriber])` → if non-nil, `try await request.downloadAndInstall()` and show `request.progress`. This call is idempotent.
4. **Transcriber config for files:** `SpeechTranscriber(locale:, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])`. Add `.transcriptionConfidence` if useful. Don't use `.volatileResults` for file input.

### 9.2 File pass
```swift
let analyzer = SpeechAnalyzer(modules: [transcriber])
async let words = collectTimedWords(from: transcriber.results)   // start consumer FIRST
let audioFile = try AVAudioFile(forReading: recordingURL)
if let lastTime = try await analyzer.analyzeSequence(from: audioFile) {
  try await analyzer.finalizeAndFinish(through: lastTime)
} else {
  try await analyzer.finalizeAndFinishThroughEndOfInput()
}
let timedWords = try await words
```
- Results are `AttributedString`s; read the `audioTimeRange` attribute from each run to build `[TimedWord]`.
- **Progress:** there's no percent API; use `result.resultsFinalizationTime / fileDuration`.
- **Errors:** after an error the analyzer session is finished; create a new analyzer to retry.
- **Resources:** run one analysis at a time. Handle an `insufficientResources` error by waiting and retrying. Don't set `ignoresResourceLimits`.
- **Long files:** test 2-hour recordings. If memory or time is a problem, process in ~10-minute windows with a 2-second overlap and de-duplicate words at the seams by timestamp.
- **Cleanup:** release reserved locales you no longer need (`AssetInventory.release(reservedLocale:)`).

### 9.3 Paragraphing (before diarization)
Build provisional segments from `TimedWord`s: break on a gap > 1.2 s, sentence end + > 25 words, or > 45 s. Diarization later re-splits by speaker.

### 9.4 Alternative engine (benchmark in v1; the engine on iOS 18–25 since v1.1)
FluidAudio also ships **Parakeet TDT v3** speech-to-text on Core ML. Build a `TranscriptionService` implementation behind a debug flag and compare accuracy and speed against SpeechAnalyzer on the test fixtures (§16, M3). Ship whichever is better. Write down the result in `docs/DECISIONS.md`.

v1.1 (plan item 16): on iPhones running iOS 18–25 Parakeet is the transcription engine (`AppServices.live` picks by `#available(iOS 26, *)`); its models (about 600 MB) download once from the same host as the diarizer, and onboarding says so before the download. Parakeet covers 25 European languages; the language picker lists those on such phones. On iOS 26 Apple's engine stays the default and Parakeet stays behind the debug benchmark screen.

---

## 10. Speaker labels (FluidAudio)

### 10.1 Integration
- Swift Package: `https://github.com/FluidInference/FluidAudio.git` (pin an exact version; check the current release).
- Use the **offline** pipeline (pyannote segmentation + embeddings + clustering) for recorded files:
```swift
let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
try await manager.prepareModels()                 // downloads Core ML models once
let samples = try AudioConverter().resampleAudioFile(path: url.path)  // 16 kHz mono
let result = try await manager.process(audio: samples)
// result → [(speakerId, start, end)]
```
Confirm the exact type names against the FluidAudio docs for the pinned version.

### 10.2 Alignment (`TranscriptAligner`, pure Swift, unit-tested)
1. For each `TimedWord`, assign the speaker turn with the **largest time overlap**. If there's no overlap, use the nearest turn within 0.5 s, else the previous word's speaker.
2. Smooth: if a run of < 3 words is sandwiched between the same speaker, reassign it to that speaker.
3. Build segments: start a new segment when the speaker changes, or on the §9.3 paragraph rules.
4. Map FluidAudio speaker IDs to `S1…Sn` in order of first appearance. Create `Speaker` rows named "Speaker 1…n".

### 10.3 UX
- Rename a speaker once → updates everywhere, including summaries: summaries store `speakerKey` references and display names are substituted at render time.
- "Merge speakers" (S3 is really S1) and "Change speaker for this paragraph."
- Setting: "Expected number of speakers" (Auto / 2 / 3 / 4+) if the FluidAudio config supports a hint.
- Be honest in the UI: labels can be wrong when people talk over each other.

---

## 11. Summaries, action items, templates

### 11.1 Availability
```swift
switch SystemLanguageModel.default.availability {
case .available: // proceed
case .unavailable(let reason): // .deviceNotEligible / .appleIntelligenceNotEnabled / .modelNotReady
}
```
- `.appleIntelligenceNotEnabled` → deep-link instructions to turn on Apple Intelligence.
- `.modelNotReady` → "Apple Intelligence is still downloading"; retry later.
- `.deviceNotEligible` → hide AI features; transcripts still work; paywall copy adapts (§13.3).

### 11.2 Context budget (the key constraint)
- On-device context window: **4,096 tokens on iOS 26**. On iOS 27 read it at runtime with `SystemLanguageModel.contextSize` (Apple's WWDC26 session shows 8,192) and count tokens with `tokenCount(for:)`. **Never hardcode the size.**
- On iOS 26, estimate tokens as `characters / 3.5` (conservative), and catch `LanguageModelSession.GenerationError.exceededContextWindowSize` → shrink the chunk by 30% and retry.
- Budget per call: `contextSize − instructionsTokens − schemaOverhead − outputReserve`. Start with outputReserve = 1,000 tokens (4K model) / 1,500 (8K model). Measure the real overhead and tune.
- **Use a fresh `LanguageModelSession` for every call.** Sessions accumulate transcript history and will overflow.
- Call `session.prewarm()` when the user opens a recording that needs a summary.

### 11.3 Map-reduce pipeline
```
Transcript (speaker-labeled, timestamped lines)
   │  chunk by token budget, split only at segment boundaries, 1 segment overlap
   ▼
MAP: each chunk → ChunkNotes (@Generable)
   ▼
REDUCE: concatenate compact ChunkNotes → if over budget, reduce in groups recursively
   ▼
FINAL: notes → Template output struct (@Generable)
   ▼
POST-PROCESS (deterministic Swift): de-dupe action items, resolve due dates,
   map speaker names → keys, validate timestamps, attach to SummaryRecord
```
- **Chunk text format** (compact, so the model can cite times and speakers):
  `[12:34] Speaker 2: We need the permit before we pour the footer.`
- **Short recordings** (whole transcript fits in budget): skip MAP; go straight to FINAL using the transcript.
- Report progress as `completedChunks / totalChunks`.
- Run the reduce/final step at `temperature` ≈ 0.2–0.3 for consistency (`GenerationOptions`).

### 11.4 Output schemas (`@Generable`)
Keep the schemas small; every field costs output tokens. Strings the model can't support from the transcript must be empty or nil, not invented.

```swift
@Generable struct ActionItemDraft {
  @Guide(description: "The task, starting with a verb. One sentence.")
  var task: String
  @Guide(description: "Person responsible, exactly as named in the transcript, e.g. 'Speaker 2' or a first name. Empty if not stated.")
  var owner: String
  @Guide(description: "Due date phrase exactly as spoken, e.g. 'next Friday', 'by the 30th'. Empty if none was said. Do not invent dates.")
  var dueText: String
  @Guide(description: "Timestamp mm:ss or h:mm:ss of the line where this was said.")
  var timestamp: String
}

@Generable struct ChunkNotes {
  @Guide(description: "Key points discussed, max 6, each under 20 words.") var keyPoints: [String]
  @Guide(description: "Decisions actually agreed on. Empty if none.") var decisions: [String]
  var actionItems: [ActionItemDraft]
  @Guide(description: "Unresolved questions. Empty if none.") var openQuestions: [String]
  // template-specific extras are added per template, see below
}
```

**Template 1: General meeting / lecture**
```swift
@Generable struct GeneralSummary {
  @Guide(description: "Short title, max 8 words.") var title: String
  @Guide(description: "3–5 sentence overview.") var overview: String
  var keyPoints: [String]
  var decisions: [String]
  var actionItems: [ActionItemDraft]
  var openQuestions: [String]
}
```

**Template 2: Client / consulting meeting**
```swift
@Generable struct ClientMeetingSummary {
  var title: String
  var overview: String
  @Guide(description: "What the client wants to achieve, in their words where possible.") var clientGoals: [String]
  @Guide(description: "Concerns, objections, budget or timeline constraints the client raised.") var concerns: [String]
  var decisions: [String]
  var actionItems: [ActionItemDraft]
  @Guide(description: "Next meeting or check-in if mentioned, else empty.") var nextMeeting: String
  var openQuestions: [String]
}
// Follow-up email is a SEPARATE call (on demand, button tap) using the summary as input:
@Generable struct FollowUpEmail { var subject: String; var body: String }
```

**Template 3: Contractor job walk-through**
```swift
@Generable struct Measurement {
  var item: String      // "Kitchen wall, north"
  var value: String     // "12 ft 4 in" — verbatim
}
@Generable struct Material { var name: String; var quantity: String; var notes: String }
@Generable struct WorkArea {
  @Guide(description: "Room or area name, e.g. 'Master bath'.") var name: String
  @Guide(description: "Work to be done in this area.") var tasks: [String]
  @Guide(description: "Only measurements explicitly spoken. Never estimate or convert.") var measurements: [Measurement]
  var materials: [Material]
}
@Generable struct WalkthroughSummary {
  var title: String
  @Guide(description: "Job address or location if spoken, else empty.") var location: String
  var overview: String
  var areas: [WorkArea]
  @Guide(description: "Specific customer requests or preferences (colors, brands, finishes).") var customerRequests: [String]
  @Guide(description: "Problems found: damage, code, safety, access issues.") var issuesFound: [String]
  @Guide(description: "Notes useful for writing the quote: scope, exclusions, permits, timeline.") var quoteNotes: [String]
  var actionItems: [ActionItemDraft]
}
```
UI shows a permanent note on walk-through summaries: *"Check measurements against the audio before quoting."* Each measurement has a ▶︎ link.

### 11.5 Instructions (system prompts, starting drafts)
Store prompts as versioned Swift constants in `Prompts.swift`; save `promptVersion` in `SummaryRecord.modelInfo`.

**Shared rules (prepended to every template):**
```
You summarize transcripts of real conversations.
Use only information in the transcript. Never invent names, numbers, dates, prices, or measurements.
If something is not stated, leave that field empty.
Write plainly and concisely. No filler.
Lines look like: [mm:ss] Speaker N: text. Use those timestamps when citing.
Refer to people exactly as they are labeled or named in the transcript.
```
**MAP instruction:** `Extract notes from this PART of a longer transcript. Other parts are handled separately; do not guess what happens outside this part.`
**FINAL, General:** `Combine these notes into one summary of the whole recording. Merge duplicates. Keep the most specific version of each action item.`
**FINAL, Client:** `...This was a meeting between a consultant and a client. Focus on client goals, concerns, commitments made by either side, and next steps.`
**FINAL, Walk-through:** `...This was a contractor walking a job site with a customer. Organize work by area/room. Copy measurements exactly as spoken.`

### 11.6 Post-processing (deterministic, unit-tested)
- **De-dupe action items:** normalize (lowercase, strip punctuation/stopwords); merge when token-set similarity > 0.8 and the owners are compatible; keep the longer task text and the earliest timestamp.
- **Due dates (`DueDateResolver`):** never let the model compute dates. Resolve `dueText` against `Recording.createdAt` with `NSDataDetector` (`.date`) plus a small rule set ("end of week" → Friday, "EOD" → same day 5 PM, "next week" → Monday of next week). Keep `dueText` visible; the resolved date can be edited.
- **Owner mapping:** if `owner` matches "Speaker N" or a renamed speaker display name, store `speakerKey`; otherwise store free text.
- **Timestamp validation:** parse; clamp to the recording duration; if invalid, find the nearest segment containing ≥ 3 words from the task text; else nil.

### 11.7 Future model options (not v1)
iOS 27 adds a `LanguageModel` protocol (swap in local MLX / Core AI models) and a Private Cloud Compute model with a 32K context. Keep `SummarizationService` behind a protocol so these can be added later:
- **Bundled MLX model** as a fallback for iPhones without Apple Intelligence (a Phase 1.5 candidate; mind the app size and RAM).
- **Private Cloud Compute**: user opt-in only, clearly labeled as not on-device; it would change the privacy promise, so it's a product decision, not a default.

---

## 12. Exports

| Export | Contents | Implementation |
|---|---|---|
| Markdown | Title, date, duration, speakers, summary sections, action items as `- [ ]`, full transcript with timestamps (toggle) | String builder → `.md` via ShareLink |
| PDF | Same content, clean typographic layout, page numbers | `ImageRenderer`/`UIGraphicsPDFRenderer` |
| Plain text | Same as MD without markup | |
| Copy | Summary only, or action items only | `UIPasteboard` |
| Email draft | Client template follow-up email (§11.4) or summary + action items | `MFMailComposeViewController`; fall back to share sheet |
| Reminders | Selected action items → chosen list; title = task; notes = owner + "From: <recording title> @ mm:ss"; due date if resolved | EventKit; request **write-only / full** access as required by the current API; store created reminder IDs to avoid duplicates |
| Audio | `.m4a` export of the recording | `AVAssetExportSession` |
| Archive (v1.1) | The library or one recording as a `.veraflowarchive` package: manifest, per-recording JSON (transcript, speakers, marks, summaries with edits), audio as stored | Package directory via `UIDocumentPickerViewController(forExporting:)`; import from Files or "Open in" |

Filename pattern: `YYYY-MM-DD <Title>.<ext>`.

---

## 13. Monetization (one-time unlock)

### 13.1 Product
- StoreKit 2 **non-consumable**: `veraflow.unlock.lifetime`.
- Suggested price: **$19.99–$29.99**, with an optional launch discount. Decide after TestFlight feedback.
- Family Sharing on.
- Apple Small Business Program: 15% commission (enroll before launch).

### 13.2 Free vs unlocked
| Feature | Free | Unlocked |
|---|---|---|
| Recording, import | Unlimited | Unlimited |
| Transcripts + speaker labels | Unlimited | Unlimited |
| AI summaries | **3 total** (any template) | Unlimited |
| Templates | All 3 (within the 3 free summaries) | All 3 (+ future templates in v1.x) |
| Exports | Plain text copy | All exports, Reminders, email draft |
| Search | Yes | Yes |
| v1.1: speaker filter, skip silence, Recently Deleted, notification, language picker, marks, editable action items, archive export/import | Yes | Yes |
| v1.1: chapters | With the summary | Yes |
| v1.1 (Wave D): Ask this recording, custom templates, translation | No (Ask: unlimited on the sample recording) | Yes |
| v1.1 (Wave D): words while recording | Yes (Settings toggle, on by default) | Yes |
| v1.1 (Wave E): transcripts and speaker labels on iOS 18–25 (Parakeet) | Unlimited | Unlimited |

Keep the free count in the Keychain (survives reinstall) as well as UserDefaults.

### 13.3 Paywall rules
- Show at natural moments: 4th summary, tapping a locked export. Never on launch.
- On devices without Apple Intelligence, the paywall must clearly say AI summaries aren't available on this iPhone, so buyers aren't misled. Consider hiding the unlock entirely on those devices, or selling it as "exports + templates for future use" with clear copy. **Open decision (§19).**
- Include Restore Purchases, terms and privacy links.
- Verify transactions with `Transaction.currentEntitlements`; listen to `Transaction.updates`.

### 13.4 Future revenue without subscriptions
- Paid major upgrades (v2 as a new non-consumable unlock for v2-only features; v1 buyers keep what they paid for).
- Template packs (e.g. "Real Estate Pack," "Coaching Pack") as separate non-consumables.

---

## 14. Privacy, consent, App Store compliance

### 14.1 Network policy
- The app makes **no network requests with user data. Ever.**
- Allowed network activity: Apple system asset downloads (speech models, via `AssetInventory`; **Translation language packs**, downloaded by iOS on first use of "Translate to…", v1.1); the one-time FluidAudio model download (from the host FluidAudio uses; show the source in Settings → About; on iOS 18–25 this also covers the Parakeet speech model, v1.1); StoreKit.
- Better option to evaluate in M4: **bundle the diarization Core ML models in the app** so there's no third-party download at all. Measure the app-size impact.
- App Privacy label target: **Data Not Collected.**
- Include `PrivacyInfo.xcprivacy` (privacy manifest) declaring required-reason APIs used (e.g. UserDefaults, file timestamps, disk space).

### 14.2 Recording consent
- The pre-record sheet reads: *"Recording laws vary. Some states require everyone's permission. Let people know you're recording."* It has a "Don't show again" checkbox. Settings → "Consent reminder" toggle.
- No legal advice in-app; link to a short help article on the marketing site.

### 14.3 Content claims
- No medical, legal, or HIPAA claims in the app, App Store listing, or marketing.
- An AI-output disclaimer appears under every summary: *"AI-generated from your recording. Check important details."*

### 14.4 Data controls
- Delete a recording (removes audio, transcript, summaries).
- "Delete all data" in Settings.
- Optional Face ID lock for the app (LocalAuthentication).
- Audio stored with `FileProtectionType.completeUntilFirstUserAuthentication` (recording must keep working while locked).

### 14.5 App Store checklist
- [ ] Mic usage string explains why ("to record your meetings; audio stays on this iPhone").
- [ ] Background audio mode justified (active recording only; stop the session when not recording).
- [ ] Reminders usage string.
- [ ] Privacy manifest.
- [ ] IAP configured, screenshots of the paywall, review notes explaining the free tier.
- [ ] Review notes: how to test without Apple Intelligence (include a sample recording in the review notes or a demo mode).
- [ ] Accessibility: VoiceOver labels on all controls, Dynamic Type, sufficient contrast.

---

## 15. Device capability matrix and fallbacks

| Capability check | Available | Not available → behavior |
|---|---|---|
| `SpeechTranscriber.isAvailable` | Full-quality transcription | Use `DictationTranscriber`; show "Standard accuracy" badge |
| Speech locale supported + assets installed | Transcribe | Prompt download; if unsupported locale, pick from supported list |
| FluidAudio models ready | Speaker labels | Single-speaker transcript + "Label speakers" retry |
| `SystemLanguageModel.default.availability == .available` | AI summaries | See §11.1 and §13.3 |
| iOS 27+ | Runtime `contextSize`, `tokenCount(for:)`, usage metrics | iOS 26 estimation path (§11.2) |
| Background continued processing supported | Processing continues after leaving app | Processing pauses in background; resumes on foreground with a notification prompt |
| Notifications (v1.1) | Provisional (quiet) "Summary ready" when the app is away; title only | Nothing is posted; Settings → "Notify when a summary is ready" asks for full alerts |
| iOS 26 or later (v1.1) | Apple Speech, summaries, Ask, live words, continued processing | iOS 18–25: Parakeet transcription + speaker labels; the Summary and Ask tabs say summaries need an Apple Intelligence iPhone on iOS 26; processing runs inline |
| `SpeechTranscriber` + foreground + thermal state below `.serious` (v1.1) | Words while recording | No live block (dictation fallback, background, hot phone, or the Settings toggle off); the file pass after Stop is unchanged |
| `LanguageAvailability` supports the pair (v1.1) | "Translate to…" lists the language; iOS downloads the pack | Language not listed |

`CapabilityService` exposes one observable struct the UI reads. Include a hidden **Diagnostics** screen (tap version number 7×) that shows all checks, model info, last pipeline errors, and timing per stage. It's extremely useful for testing and support.

---

## 16. Milestones with acceptance criteria

Work in order. Each milestone is a branch + PR. Don't start the next until the current one's acceptance criteria pass on a **real device**.

### M0: Project foundation
- Xcode project `VeraFlow`, iOS 26.0 min, Swift 6 strict concurrency, SwiftData container, folder structure per §6.1, FluidAudio package added (pinned).
- Service protocols + fake implementations; preview data.
- `docs/DECISIONS.md` created.
- CI script `scripts/test.sh` runs `xcodebuild test` on a simulator.
- **Done when:** app launches to an empty Library; `scripts/test.sh` passes; no warnings under strict concurrency.

### M1: Recording
- §8 in full (except nice-to-haves): record, pause, resume, stop, bookmarks, levels, CAF crash-safe, interruptions, route changes, disk space, recovery.
- **Done when:** a 90-minute recording with the screen locked plays back fully; force-quitting mid-recording recovers a playable file; a phone call during recording pauses and offers resume.

### M2: Library and import
- Library list, rename, delete, tags, favorites, search by title; import from Files and share sheet (Share Extension or `onOpenURL` document types) for m4a/mp3/wav/caf.
- **Done when:** a Voice Memos recording can be shared into VeraFlow and appears with the correct duration.

### M3: Transcription
- §9 in full, including assets, progress, resumable pipeline stage, `DictationTranscriber` fallback, paragraphing.
- Transcript tab: synced playback highlight, tap-to-seek, edit text, search within the transcript.
- Test fixtures in `TestAudio/` (not shipped): a 2-min clean monologue, a 10-min 2-person meeting, a 30-min 3–4 person meeting with crosstalk, a 60-min lecture, a 15-min noisy walk-through (outdoors/indoors, fan noise). Jeremy records these; include a hand-corrected reference transcript for at least the 2-min and 10-min files.
- Benchmark SpeechAnalyzer vs FluidAudio Parakeet (§9.4); record word error rate (WER) and time in `docs/DECISIONS.md`.
- **Done when:** a 60-min file transcribes on an iPhone 15 Pro-class device without crashing or memory warnings; the pipeline survives backgrounding; WER on the 10-min fixture is recorded.

### M4: Speaker labels
- §10 in full: diarization, `TranscriptAligner` with unit tests (synthetic word/turn fixtures), rename, merge, reassign.
- **Done when:** the 10-min 2-person fixture shows 2 speakers with mostly correct turns (spot-check 20 turns, ≥ 85% correct); rename propagates; failure path shows a single speaker + retry.

### M5: Summaries and templates
- §11 in full: availability handling, token budgeting, map-reduce, 3 templates, post-processing, re-run with a different template, summary history.
- Unit tests: chunker (never splits a segment; respects budget), de-dupe, `DueDateResolver` (table-driven tests with fixed reference dates), timestamp validation.
- Golden tests (manual, logged in `docs/EVALS.md`): for each fixture × template, record whether action items are complete and whether anything was hallucinated.
- **Done when:** the 60-min lecture and 30-min meeting produce summaries with no context-overflow failures; zero invented measurements on the walk-through fixture; action items link to the correct audio moment (±10 s).

### M6: Exports
- §12 in full.
- **Done when:** each export opens correctly in its target (Files preview, Mail, Reminders with due dates, Notes/Obsidian for Markdown).

### M7: Onboarding, settings, capability messaging, privacy
- §4.1, §14, §15 including the Diagnostics screen, consent sheet, Face ID lock, delete all data, privacy manifest.
- Network test (§6.2).
- **Done when:** a fresh install on a non–Apple Intelligence device shows correct messaging and still produces transcripts; Charles/Proxyman shows no requests other than those allowed in §14.1.

### M8: Purchases
- §13 in full with a StoreKit configuration file for local testing.
- **Done when:** the free-summary counter works across reinstall; purchase, restore, Family Sharing and refund (revoked entitlement) behave correctly in the StoreKit test environment and TestFlight sandbox.

### M9: Polish and ship
- Accessibility pass, Dynamic Type, dark mode, empty states, error copy, app icon, App Store screenshots, listing copy, marketing site privacy page, TestFlight with 5–10 testers (include 2–3 contractors and 2–3 consultants).
- **Done when:** App Store checklist (§14.5) is complete and the build is submitted.

**Stretch (v1.1+):** Live Activity, live transcript preview, Control Center control, App Intents/Shortcuts ("Summarize last recording"), iPad layout, Mac Catalyst/native Mac, more templates, MLX fallback model.

---

## 17. Phase 2: Android (outline only; verify all APIs when starting)

Build natively in **Kotlin + Jetpack Compose**, mirroring the iOS architecture and the same template schemas (as Kotlin data classes + JSON schema prompts).

| Area | Primary | Fallback |
|---|---|---|
| Recording | `MediaRecorder` / `AudioRecord` in a **foreground service** (type `microphone`) | — |
| Transcription | ML Kit GenAI Speech Recognition (alpha as of 2026; "basic" mode on API 31+, "advanced" mode Pixel 10/11 only; file input must be 16 kHz mono 16-bit PCM) | whisper.cpp or sherpa-onnx (on-device, all devices) |
| Speaker labels | sherpa-onnx speaker diarization | Single speaker |
| Summaries | Gemini Nano via ML Kit GenAI (Prompt API / Summarization API) on supported devices | Bundled small model (e.g. Gemma) via Google AI Edge / LiteRT-LM, or llama.cpp |
| Storage | Room | — |
| Purchases | Google Play Billing, one-time product | — |

Android is harder than iOS because on-device AI support varies a lot by phone model. Consider limiting v1 Android to devices that pass a capability check, and sell it as a separate purchase (app stores don't share purchases across platforms).

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
├── VeraFlow/ (Xcode project)
├── VeraFlowTests/
├── VeraFlowUITests/
├── TestAudio/                 ← fixtures, git-LFS or gitignored
└── scripts/test.sh
```
Put the project under git from the first commit. Push to a private GitHub repo.

### 18.2 Division of labor (recommended)
- **Never let both agents edit the same branch at the same time.** One agent per branch; merge through PRs.
- **Claude Code = primary builder.** Runs in Terminal next to Xcode, builds with `xcodebuild`, runs tests, and works milestone by milestone. (Xcode 27 also has built-in agent support if you prefer working inside Xcode.)
- **Antigravity = reviewer and parallel worker.** Good uses: review a finished milestone PR against SPEC.md; build isolated pure-Swift pieces on their own branch (`TranscriptAligner`, `DueDateResolver`, exporters) with unit tests; write the marketing site/privacy page; later, lead the Android Phase 2 build.
- After either agent finishes a milestone, have the *other* one review the diff against the milestone's acceptance criteria.

### 18.3 Session habits
- Start every session with: "Read docs/SPEC.md and docs/PROGRESS.md. Continue with the next unchecked item."
- Ask for a plan first on each milestone (Claude Code plan mode; Antigravity planning mode), approve it, then build.
- Require tests with each change and a passing `scripts/test.sh` before commit.
- Test on your iPhone at the end of every milestone; paste device logs/crashes back to the agent.
- When the agent and spec disagree, update SPEC.md or DECISIONS.md. Don't let the code quietly move away from the spec.

### 18.4 Kickoff prompts

**Claude Code: M0**
```
Read docs/SPEC.md fully. We are building milestone M0 only.
Create the Xcode project "VeraFlow" (SwiftUI, iOS 26.0 minimum, Swift 6 strict concurrency, SwiftData),
the folder structure from §6.1, service protocols with fake implementations for every service,
add FluidAudio via SPM pinned to its current release, create docs/DECISIONS.md, docs/PROGRESS.md
(copy the milestone list from §16 as checkboxes), and scripts/test.sh that runs xcodebuild test on
an available iPhone simulator. Show me your plan before writing code. Stop when M0's "Done when"
criteria pass and summarize what to verify on my Mac.
```

**Claude Code: any later milestone**
```
Read docs/SPEC.md and docs/PROGRESS.md. Implement milestone M<N> exactly as specified.
Before coding: list the Apple/FluidAudio APIs you'll use and verify their current signatures
(don't rely on memory — check SDK headers or docs). Plan first, then build with unit tests.
Run scripts/test.sh. Update PROGRESS.md and DECISIONS.md. Tell me the on-device test steps.
```

**Antigravity: review**
```
Follow .agents/rules/project.md. Review branch m<N> against docs/SPEC.md milestone M<N>
and its "Done when" criteria. Report: missing requirements, spec deviations, concurrency or
memory risks, any network calls outside §14.1, and missing tests. Do not modify code;
write findings to docs/reviews/M<N>.md.
```

**Antigravity: isolated component**
```
Follow .agents/rules/project.md. On a new branch feature/due-date-resolver, implement
DueDateResolver exactly per docs/SPEC.md §11.6 as a pure Swift type with no UI or framework
dependencies beyond Foundation. Write table-driven Swift Testing tests using fixed reference
dates (include "next Friday", "end of week", "by the 30th", "tomorrow morning", "EOD", and
phrases with no date). Open a PR when tests pass.
```

---

## 19. Risks and open questions

| # | Risk / question | Mitigation / decision owner |
|---|---|---|
| 1 | Apple Intelligence required for summaries shrinks the buyer pool | Clear messaging; evaluate MLX fallback in v1.1; decide paywall behavior on ineligible devices (**Jeremy**) |
| 2 | Small context window hurts quality on long meetings | Map-reduce + evals in M5; iOS 27 larger window read at runtime |
| 3 | Diarization errors with crosstalk | Honest UI, easy merge/reassign, expected-speakers hint |
| 4 | Background processing gets expired by iOS | Resumable stages; progress reporting; foreground resume prompt |
| 5 | Competitors at $2–7 | Compete on templates + action-item workflow, not price; niche marketing (contractors, consultants) |
| 6 | Apple ships similar features in Notes / Voice Memos | Stay vertical-focused; move fast on templates and exports |
| 7 | API names differ from docs/WWDC | Agents must verify signatures against the SDK each milestone |
| 8 | FluidAudio model download = third-party network call | Evaluate bundling models (M4/M7) |
| 9 | Final app name / trademark | Product name is **VeraFlow** (alpha codename Riffle, §0). Search the App Store + USPTO before M9 (**Jeremy**) |
| 10 | Price point | TestFlight survey; start $19.99–29.99 (**Jeremy**) |

---

## 20. References

- Apple, *Bring advanced speech-to-text to your app with SpeechAnalyzer* (WWDC25): https://developer.apple.com/videos/play/wwdc2025/277/
- Apple, *What's new in the Foundation Models framework* (WWDC26): https://developer.apple.com/videos/play/wwdc2026/241/
- Apple, *Finish tasks in the background* (WWDC25): https://developer.apple.com/videos/play/wwdc2025/227/
- Apple docs, `BGContinuedProcessingTaskRequest`: https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest
- SpeechAnalyzer file-transcription API notes (community research): https://github.com/yrocaz/mac-transcriber/blob/main/docs/research/2026-07-27-apple-speechanalyzer-docs.md
- FluidAudio (diarization, VAD, Parakeet ASR): https://github.com/FluidInference/FluidAudio
- ML Kit GenAI Speech Recognition (Android): https://developers.google.com/ml-kit/genai/speech-recognition/android
- Gemini Nano on Android: https://developer.android.com/ai/gemini-nano
- Antigravity rules docs: https://antigravity.google/docs/rules-workflows/
- Competitor reference: https://synopsule.com/ · https://viskalocal.com/blog/meeting-transcription-no-subscription.html
