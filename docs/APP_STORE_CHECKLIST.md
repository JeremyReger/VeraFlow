# VeraFlow — App Store Submission & Review Checklist

This document provides the complete App Store pre-submission verification checklist for **VeraFlow** (iOS 26+, Swift 6 strict concurrency), satisfying all privacy, security, StoreKit 2, accessibility, and reviewer guidelines (§14, §15, §16 M9).

---

## 1. App Store Connect Metadata

| Field | Configuration | Specification Reference |
|---|---|---|
| **App Name** | `VeraFlow` | AppConstants.appName |
| **Alpha / Demo Codename** | `Riffle` | AppConstants.alphaCodename |
| **Subtitle** | Private On-Device Meeting Recorder | Max 30 chars |
| **Primary Category** | Productivity | |
| **Secondary Category** | Business | |
| **Age Rating** | 4+ (No unmoderated user content, no gambling, no adult themes) | |
| **Copyright** | © 2026 VeraFlow. All rights reserved. | |

### Promotional Text
> Record meetings with 100% on-device privacy. Instant speaker diarization, Apple Foundation Models summaries, and zero cloud data egress.

### Description
VeraFlow is a private, on-device meeting recorder and transcription intelligence assistant designed for professionals who demand absolute data sovereignty.

- **100% On-Device AI**: Powered entirely by Apple SpeechAnalyzer and local Foundation Models. Your audio never touches an external cloud server or remote LLM API.
- **Instant Speaker Diarization**: Automatically segments multiple speakers using local Core ML clustering.
- **Domain-Specific Meeting Templates**: Generate structured summaries tailored for General Team Reviews, Client Consultations, and Contractor Site Walkthroughs.
- **Due Date & Action Item Extraction**: Automatically extracts action items with natural language due date parsing, syncable directly to Apple Reminders.
- **Typographic PDF & Audio Export**: Export publication-quality PDFs, raw transcripts, and audio files through the standard iOS Share Sheet.
- **Fair Lifetime Monetization**: Enjoy 3 free AI meeting summaries with full access to recording and playback. Unlock unlimited lifetime AI summaries with a single one-time purchase—no subscriptions, no recurring fees.

---

## 2. Privacy & Data Sovereignty Review (§14.1, §14.2)

### Apple Privacy Manifest (`PrivacyInfo.xcprivacy`)
- [x] **Tracking**: Set to `false` (`NSPrivacyTracking = NO`).
- [x] **Tracking Domains**: Empty array (`NSPrivacyTrackingDomains = []`).
- [x] **Collected Data Types**: Empty array (`NSPrivacyCollectedDataTypes = []`). Zero user telemetry, zero analytics, zero crash logs egressed.
- [x] **NSPrivacyAccessedAPITypes**:
  - `NSPrivacyAccessedAPICategoryFileTimestamp`: Used solely for local disk cache maintenance and crash recovery scanning (`CrashRecoveryService`).
  - `NSPrivacyAccessedAPICategoryDiskSpace`: Used solely for the 500 MB low-disk safety guardrail (`AudioRecordingService`).

### Two-Party Consent Compliance (§14.2)
- [x] Pre-recording consent reminder modal presented before the first recording session (`ConsentReminderSheet`).
- [x] Visual and audible recording indicators active during capture.
- [x] Optional setting in Settings to re-enable or dismiss consent reminders.

### Zero-Network Verification
- [x] `./scripts/test.sh` automatically scans the codebase for network imports (`URLSession`, `Network`, `Alamofire`, `WebKit`) to enforce the zero-egress guarantee.

---

## 3. In-App Purchase & StoreKit 2 Review (§13)

### Product Identifiers
- **Primary Product ID**: `veraflow.unlock.lifetime`
- **Fallback Product ID**: `riffle.unlock.lifetime`
- **Product Type**: Non-Consumable (Lifetime Unlock)
- **Tier**: Tier 10 / Tier 15 ($9.99 – $14.99 one-time)

### Free Tier Behavior
- Full unlimited audio recording, playback, bookmarks, and tag organization.
- 3 free AI summaries and action item extractions tracked via secure local Keychain (`KeychainStorage`).
- Clear, honest paywall sheet (`PaywallSheet`) triggered upon attempting the 4th summary or accessing premium PDF export.
- Working "Restore Purchases" button with `AppStore.sync()` and real-time entitlement refresh.

---

## 4. Accessibility & Human Interface (§16 M9)

- [x] **VoiceOver Navigation**:
  - Pinned audio player bar controls (`Play/Pause`, `Rewind 15s`, `Forward 15s`, `Scrubber Slider`, `Playback Rate Toggle`) feature explicit `.accessibilityLabel`, `.accessibilityValue`, and `.accessibilityHint`.
  - Action items checklist items announce status ("Mark complete / Mark incomplete"), owner, due date, and audio jump buttons.
  - Recording row items announce combined title, formatted duration, timestamp, stage, favorite status, and tags.
  - Record and bookmark controls provide clear VoiceOver feedback during live capture.
- [x] **Dynamic Type**: All text elements scale cleanly with user-selected system text sizes without clipping or overlapping.
- [x] **Biometric Security**: Optional Face ID / Touch ID lock screen with graceful fallback to device passcode.

---

## 5. Reviewer Notes for App Store Review Team

```text
Reviewer Instructions:
1. VeraFlow is an entirely on-device application. It makes ZERO network requests and requires no user account or login.
2. To test the app with sample data immediately without needing an extended live meeting:
   - Navigate to Settings (gear icon in the top left of the Library).
   - Scroll to "Demo & Testing" and tap "Load Sample Meetings".
   - This will populate 3 complete sample recordings (General Team Review, Client Consultation, Contractor Walkthrough) with transcripts, bookmarks, diarized speakers, and AI summaries.
3. To test StoreKit In-App Purchase:
   - Use a StoreKit Sandbox Apple ID.
   - Tap "Unlock Lifetime Access" in Settings or after running 3 meeting summaries.
   - Lifetime unlock product ID: veraflow.unlock.lifetime.
4. Two-party consent notice is enabled by default and presents a reminder prior to initiating a new recording.
```

---

## 6. Pre-Submission Build & Validation Steps

1. Run verification test suite:
   ```bash
   ./scripts/test.sh
   ```
2. Validate Xcode project generation:
   ```bash
   python3 scripts/generate_xcodeproj.py
   ```
3. Create Release Archive in Xcode:
   ```bash
   xcodebuild -project VeraFlow.xcodeproj -scheme VeraFlow -configuration Release -destination "generic/platform=iOS" archive -archivePath build/VeraFlow.xcarchive
   ```
4. Validate Archive against App Store Connect requirements:
   ```bash
   xcrun altool --validate-app -f build/VeraFlow.xcarchive -t ios --apiKey <KEY> --apiIssuer <ISSUER>
   ```
