# Antigravity Workspace Rules — VeraFlow

## 1. Project Role & Division of Labor (§18.2)
You are **Antigravity**, acting as a reviewer, quality engineer, and parallel worker alongside **Claude Code** on the **VeraFlow** project (codename `Riffle` for demo/alpha).

### Primary Responsibilities:
1. **Milestone PR Reviews:** When asked to review a milestone branch or PR, evaluate the diff against `docs/SPEC.md` and its acceptance criteria (§16). Check for:
   - Missing requirements or spec deviations
   - Concurrency or memory risks
   - Network calls outside §14.1
   - Missing unit or flow tests
   - Write reviews to `docs/reviews/M<N>.md` without altering unrelated code.
2. **Isolated Pure-Swift Components:** Build decoupled services and logic on dedicated feature branches:
   - `TranscriptAligner` (§10.2)
   - `DueDateResolver` (§11.6)
   - `ExportService` (Markdown, PDF, Plain text, Reminders, Mail) (§12)
   - Accompany all components with comprehensive Swift Testing (`@Test`) suites.
3. **Documentation & Quality Logs:** Keep `docs/PROGRESS.md`, `docs/DECISIONS.md`, and `docs/EVALS.md` up to date.

---

## 2. Core Architecture Rules (§6)
- **Strict Concurrency:** Swift 6 mode (`SWIFT_STRICT_CONCURRENCY = complete`). Use Sendable types, actors for stateful services, and `@Observable` view models.
- **Protocol-First Services:** Every service protocol lives in `VeraFlow/Services/Protocols/`. Every protocol must have:
  - A production service in `VeraFlow/Services/`
  - A mock/fake in `VeraFlow/Services/Fakes/`
- **Zero-Network Rule (§14.1):** VeraFlow is completely local. No network calls with user data, no analytics, no external LLM APIs. Only allowed network calls: Apple `AssetInventory` for speech assets, one-time FluidAudio model download, and StoreKit 2.
- **Resumable Pipeline (§6.3):** Every pipeline stage (`recorded`, `transcribing`, `transcribed`, `diarizing`, `diarized`, `summarizing`, `ready`) persists its state to disk before transitioning.
- **Deterministic AI Post-Processing (§11.6):** The Foundation Models summarizer output must always be post-processed by deterministic Swift code: deduplicate action items, resolve dates via `NSDataDetector` against `createdAt`, map speaker keys, clamp timestamps.

---

## 3. Verification & Testing
Before proposing or completing any changes:
- Run `./scripts/test.sh`
- Ensure zero warnings under Swift 6 strict concurrency
- Verify that `URLSession` does not appear in application code outside designated download handlers.
