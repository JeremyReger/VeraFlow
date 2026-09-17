# Architecture Decision Records (ADR) — VeraFlow

All architectural, dependency, and design decisions are recorded here with context, date, and rationale.

---

## ADR 001: Project Naming — VeraFlow (Demo/Alpha: Riffle)
- **Date:** 2026-09-17
- **Status:** Accepted
- **Decision:** The official product name is **VeraFlow**. The original codename **Riffle** is retained as the internal demo and alpha version name.
- **Context:** The original working specification used `Riffle` as a temporary working title (§19 #9). The name VeraFlow emphasizes truthful ("vera"), local-first flow of spoken dialogue into actionable tasks.
- **Consequences:**
  - Production app bundle identifier: `com.veraflow.app`
  - Demo/alpha bundle identifier: `com.veraflow.riffle`
  - Lifetime unlock IAP ID: `veraflow.unlock.lifetime` (with `riffle.unlock.lifetime` supported for alpha builds)
  - Code repositories, directories, schemes, and documentation are unified under VeraFlow.

---

## ADR 002: Tech Stack & Minimum Requirements
- **Date:** 2026-09-17
- **Status:** Accepted
- **Decision:**
  - Primary language: Swift 6 with strict concurrency checking (`SWIFT_STRICT_CONCURRENCY = complete`).
  - Minimum iOS version: **iOS 26.0** (required for Apple Speech framework `SpeechAnalyzer`).
  - Persistence: SwiftData.
  - Audio Engine: AVFoundation (`AVAudioEngine` with CAF container).
  - Diarization: FluidAudio (pinned Swift Package).
  - Summarization: Apple Foundation Models framework (`LanguageModelSession`, `@Generable`).
- **Rationale:** Ensures complete on-device functionality, privacy compliance, zero ongoing cloud inference costs, and native iOS system integration.

---

## ADR 003: Zero-Network Privacy Architecture
- **Date:** 2026-09-17
- **Status:** Accepted
- **Decision:** No user audio, transcripts, or summaries will ever leave the device. The application will contain zero telemetry, zero analytics SDKs, and zero cloud backend servers.
- **Allowed Network Requests:**
  1. Apple system asset downloads via `AssetInventory` (speech models).
  2. One-time FluidAudio Core ML model download.
  3. StoreKit 2 transactions.
- **Enforcement:** Automated tests verify that `URLSession` does not appear outside approved download handlers.

---

## ADR 004: Multi-Agent Development Workflow (Claude Code + Antigravity)
- **Date:** 2026-09-17
- **Status:** Accepted
- **Decision:** Claude Code acts as the primary builder (feature milestones M0–M9). Antigravity acts as PR reviewer, documentation maintainer, and parallel builder for isolated pure-Swift modules (`TranscriptAligner`, `DueDateResolver`, exporters).
- **Rule:** Never touch the same git branch concurrently. All contributions merge via PRs after automated verification.

---

## ADR 005: Platform Roadmap — Native iOS First, Android in Phase 2
- **Date:** 2026-09-17
- **Status:** Accepted
- **Decision:** Focus exclusively on native iOS (Swift 6, SwiftUI) for Milestones M0 through M9. Do not restructure the repository or introduce cross-platform framework abstractions (Flutter/KMP) at this time. Android will be implemented natively in Kotlin + Jetpack Compose as a distinct Phase 2 project (§17).
- **Rationale:** Deep native iOS integration (`SpeechAnalyzer`, `Foundation Models`, `StoreKit 2`, `FluidAudio`) requires native Swift to achieve zero latency, privacy compliance, and strict concurrency safety. Protocol-driven service architecture (§6.1) maintains clean domain boundaries that will map directly to Kotlin services when Phase 2 begins.
