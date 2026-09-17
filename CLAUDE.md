# VeraFlow — Claude Code instructions

Private on-device meeting recorder for iPhone (record → transcribe → speaker labels → summary + action items). One-time purchase, no servers.

## Naming
- **VeraFlow** is the product and the name used in code, targets, schemes, product IDs, and release builds.
- **Riffle** is the alpha/demo codename only: display name for TestFlight alpha builds, demo mode, and sample fixtures (SPEC §0). Don't introduce `Riffle` identifiers in code.

## Source of truth
- `docs/SPEC.md` is the spec. Read it before any work. `docs/PROGRESS.md` tracks milestones; `docs/DECISIONS.md` records decisions.
- Build one milestone at a time (SPEC §16). Don't start work outside the current milestone without asking.
- If the code must deviate from the spec, stop and explain why, then record the decision in `docs/DECISIONS.md` (date, decision, reason).

## Product guardrails (never violate)
- Everything runs on device. No network requests with user data, no analytics/crash SDKs, no accounts. Allowed network: Apple asset downloads, FluidAudio model download, StoreKit (SPEC §14.1).
- No Private Cloud Compute or third-party LLM APIs in v1.
- Never let the model invent names, numbers, dates, prices, or measurements. Due dates are resolved in Swift, not by the model.
- No medical, legal, or HIPAA claims in code, copy, or metadata.

## Tech rules
- Swift 6 strict concurrency, SwiftUI, SwiftData, iOS 26.0 minimum; iOS 27 APIs behind `#available(iOS 27, *)`.
- Only dependency: FluidAudio (pinned). Ask before adding any package.
- Services behind protocols with fakes for tests and previews. `@Observable` view models; actors for stateful services.
- **Verify Apple and FluidAudio API signatures against the current SDK/docs before using them.** Don't code from memory; these APIs are new and have changed since WWDC.
- Fresh `LanguageModelSession` per summarization call; read the context size at runtime on iOS 27; never hardcode it.
- Record to CAF (crash-safe), not directly to m4a.

## Workflow
- Plan first; wait for approval on anything touching more than a few files.
- Every change comes with tests (Swift Testing for logic). Run `scripts/test.sh`; it must pass before commit.
- Small commits on a milestone branch (`m1-recording`, etc.). Never commit to `main` directly.
- Never edit a branch another agent is working on.
- At the end of a milestone: update `docs/PROGRESS.md`, list on-device test steps for Jeremy, and note anything the Simulator couldn't verify (microphone, background, performance, Apple Intelligence).
- Explain things in plain language; Jeremy is technical but not a full-time iOS developer.

## Commands
- Test: `scripts/test.sh`
- Build: `xcodebuild -scheme VeraFlow -destination 'platform=iOS Simulator,name=<available iPhone>' build`
