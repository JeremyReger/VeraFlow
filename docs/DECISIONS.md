# Decisions

Format: `YYYY-MM-DD — Decision — Reason — Who`

- 2026-09-17 — iOS native first (Swift/SwiftUI), Android Phase 2 — Apple on-device speech + Foundation Models need the least code; iPhone buyers pay for one-time apps — Jeremy
- 2026-09-17 — v1 templates: General meeting/lecture, Client/consulting meeting, Contractor walk-through — Matches owner's consulting work and contractor niche — Jeremy
- 2026-09-17 — Business model: free download, 3 free summaries, one-time unlock; no subscription — No server costs — Jeremy
- 2026-09-17 — v1 strictly on-device (no Private Cloud Compute, no third-party LLM APIs) — Privacy promise is the core pitch — Jeremy
- 2026-09-17 — Product name is VeraFlow; Riffle stays as the alpha/demo codename (TestFlight alpha display name, demo mode, fixtures). Code identifiers and product IDs use VeraFlow — Avoids a rename across code later; testers can tell alpha builds apart — Jeremy
- 2026-09-17 — Xcode project is generated from `project.yml` with XcodeGen; `VeraFlow.xcodeproj` is gitignored — M0 was written without access to Xcode; a YAML definition is reviewable and reproducible, and XcodeGen is a dev tool, not an app dependency (the FluidAudio-only rule is about linked packages) — Jeremy / Claude Code
- 2026-09-17 — Alpha builds use the same bundle ID as release, differing only in display name ("Riffle (alpha)") and the `ALPHA` compile flag — Keeps StoreKit product config and TestFlight simple; side-by-side installs aren't needed — Jeremy / Claude Code
- 2026-09-17 — FluidAudio pinned to exact version 0.15.7 (latest tag at time of M0) — SPEC §10.1 asks for an exact pin; bump deliberately in M4 after checking release notes — Claude Code
- 2026-09-17 — `AppServices.live()` returns fakes until each milestone lands its real service — Lets the app launch and the UI be built against protocols from M0; each milestone swaps one service — Claude Code
- 2026-09-17 — Building with Xcode 26.6 / iOS 26.5 SDK until Xcode 27 ships — That is what is installed; nothing through M4 needs iOS 27 APIs. M5 must gate `SystemLanguageModel.contextSize` and `tokenCount(for:)` behind `#available(iOS 27, *)` and also compile-time `#if canImport` checks if the SDK still lacks them — Jeremy / Claude Code
- 2026-09-17 — M1 recorder uses the classic `AVAudioEngine.connect`, `installTap`, and `AVAudioSession.interruptionNotification` APIs — Apple's docs mark them deprecated in iOS 27 in favour of `connectNode`, `AVAudioSession.InterruptionContext`, and friends, but those replacements are iOS 27-only and absent from the iOS 26.5 SDK we build with. Revisit when Xcode 27 is in use: gate the new calls behind `#available(iOS 27, *)` — Claude Code
- 2026-09-17 — Recorder graph is input → `AVAudioMixerNode` → muted main mixer, with the file tap on the mixer — The mixer does sample-rate and channel conversion, so the tap always sees mono 44.1 kHz float regardless of the mic (built-in, AirPods HFP at 16 kHz, USB stereo) and the CAF/AAC file settings never change — Claude Code
- 2026-09-17 — Launch recovery marks an interrupted recording `.failed` (not `.recorded`) when its audio file is missing or unreadable — SPEC §8.2 says mark `.recorded`, but a row that can't play or transcribe would just fail later with a worse message; readable files are marked `.recorded` as specified — Claude Code
- 2026-09-17 — Risk to verify on device in M1: AAC inside CAF needs the packet table Core Audio writes at close. If a force-quit leaves an unplayable file, fall back to Apple Lossless or 16-bit PCM in CAF (bigger files) and record the outcome here — Claude Code

