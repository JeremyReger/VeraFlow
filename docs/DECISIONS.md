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
