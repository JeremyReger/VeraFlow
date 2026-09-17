# Claude Code Guide — VeraFlow (Codename Riffle)

## Project Overview
**VeraFlow** (demo/alpha codename: `Riffle`) is a private, on-device meeting recorder for iPhone.
- **Pipeline:** Record → Transcribe (`SpeechAnalyzer`) → Speaker labels (`FluidAudio`) → AI Summary & Action Items (`Foundation Models`) → Export (Markdown, PDF, Reminders, Mail).
- **Architecture:** Native iOS (Swift 6, SwiftUI, SwiftData). Strict concurrency enabled.
- **Specification:** The single source of truth is [`docs/SPEC.md`](docs/SPEC.md).
- **Progress Tracking:** Update checkboxes in [`docs/PROGRESS.md`](docs/PROGRESS.md).
- **Decisions Log:** Record any technical decisions or package additions in [`docs/DECISIONS.md`](docs/DECISIONS.md).

---

## Multi-Agent Division of Labor (§18)
- **Claude Code = Primary Builder:** Works milestone by milestone, writes features, runs tests, creates PRs.
- **Antigravity = Reviewer & Parallel Worker:** Reviews milestone PRs against `docs/SPEC.md`, builds isolated pure-Swift logic (`TranscriptAligner`, `DueDateResolver`, `ExportService`), maintains evaluation logs (`docs/EVALS.md`), and leads Android Phase 2.
- **Rule:** Never edit the same branch concurrently. One agent per branch; merge via PRs.

---

## Strict Development Rules
1. **Zero Unauthorized Network Activity:** VeraFlow operates 100% on-device. No analytics, no telemetry, no cloud APIs, no network calls except OS speech asset downloads and the one-time FluidAudio model download (§14.1). Any unauthorized `URLSession` usage fails automated tests.
2. **Strict Concurrency:** Swift 6 mode with complete strict concurrency checks. Use `actor`, `Sendable`, and `@Observable`.
3. **Protocol-Driven Services:** Every service in `VeraFlow/Services/Protocols` must have a production implementation and a corresponding mock in `VeraFlow/Services/Fakes` for unit tests and SwiftUI previews.
4. **Resumable Pipeline:** Processing pipeline (`PipelineCoordinator`) must persist stage state after each transition to support crash recovery and background processing.
5. **Deterministic AI Post-Processing:** Never let the LLM guess dates or hallucinate. Use `DueDateResolver` (`NSDataDetector`) and timestamp clamping.

---

## Build & Test Commands
```bash
# Run test suite & check strict concurrency
./scripts/test.sh

# Build via xcodebuild
xcodebuild -scheme VeraFlow -destination 'generic/platform=iOS' build

# Run unit tests via xcodebuild (when simulator runtime is available)
xcodebuild test -scheme VeraFlow -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

---

## Starting a Session
1. Read `docs/SPEC.md` and `docs/PROGRESS.md`.
2. Identify the active milestone (M0 through M9).
3. Verify Apple and FluidAudio API signatures against SDK headers before implementing.
4. Plan your implementation, obtain approval, and test thoroughly with `./scripts/test.sh`.
