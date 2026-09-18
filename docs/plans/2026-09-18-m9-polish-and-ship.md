# M9 plan — Polish and ship (SPEC §16 M9, §14.5)

Started 2026-09-18. Jeremy added two requirements up front: a **Section 508 accessibility review** and a **security review** aimed at a possible US DoD deployment. Both run first, because their findings decide part of the polish work.

## 1. Reviews (first)

- **Security review** of the whole app (data at rest, Keychain, logging, network surface, release-build hygiene, app lock and snapshots, inbound files, FluidAudio supply chain, entitlements, prompt-injection surface). Report: `docs/reviews/2026-09-18-security-review.md`. Findings that can be fixed in code are fixed in this milestone; the rest become a DoD-readiness checklist for Jeremy.
- **Accessibility review** against Section 508 / WCAG 2.2 AA (VoiceOver labels, traits, live regions, Dynamic Type, contrast and colour-only meaning, Reduce Motion, touch targets, keyboard/Switch Control reachability, Live Activity). Report: `docs/reviews/2026-09-18-accessibility-review.md`. Code fixes in this milestone; device checks listed for Jeremy (VoiceOver walk-through, AX5 text sizes, contrast on materials, Voice Control).

## 2. Polish (SPEC §16 M9)

- Accessibility fixes from the review; Dynamic Type (replace fixed `.font(.system(size:))` with text styles or `@ScaledMetric`); dark mode check (no hardcoded colours); Reduce Motion.
- Empty states: Library, Summary, Transcript, Recorder (permission) already use `ContentUnavailableView`; Diagnostics and the Library filter get the same treatment where missing.
- Error copy audit: every user-facing message in one tone (what happened, what to do), no stack-trace text; `PipelineFailure.message` and recorder/import/export/purchase errors.
- App icon: 1024×1024 generated in-repo (script in `scripts/icon/`) so it's reproducible; an alpha variant with a "RIFFLE" band for the `Alpha` config (SPEC §0).
- Security fixes from the review (file protection, temp-file cleanup, release-only launch-argument gating, snapshot hiding under the app lock, log privacy).

## 3. Ship

- **App Store listing copy** (`docs/store/listing.md`): name, subtitle, description, keywords, promo text, what's new, review notes (free tier, how to test without Apple Intelligence, sample recording). No medical/legal/HIPAA claims (SPEC §14.3).
- **Privacy page + terms** for the marketing site (`site/privacy.html`, `site/terms.html`, static, no scripts or trackers) → Jeremy hosts them and fills `AppLinks`.
- **Screenshots**: a UI test (`ScreenshotTests`) that seeds sample data and captures the Library, Recorder, Transcript, Summary, Exports, and Paywall as attachments, so the App Store set is one simulator run per device size.
- **TestFlight**: `Alpha` config ("Riffle (alpha)"), export-compliance key already set, tester list (5–10; 2–3 contractors, 2–3 consultants), feedback questions.
- **App Store checklist (§14.5)** tracked in PROGRESS with evidence per line.
- **Xcode 27 migration** (queued from M5/M3): `LanguageModelSession.GenerationError` → `LanguageModelError`, `GenerationOptions(samplingMode:)`, re-check `BGContinuedProcessingTaskRequest` launching on iOS 27. Can't be compiled with Xcode 26.6; done the day Jeremy installs Xcode 27.

## Decisions Jeremy owns (SPEC §19)

- Price (start $19.99–29.99) and the App Store Connect IAP setup.
- Hosting for the privacy/terms pages (GitHub Pages is fine) → URLs into `AppLinks`.
- App Store + USPTO search for "VeraFlow" before submission.
- Icon direction: the generated mark is a starting point; a designer can replace the PNG without code changes.
- Tester list.

## Done when

- Both reviews filed, code-level findings fixed and tested, remaining items on the DoD-readiness and device-check lists.
- `scripts/test.sh` green; VoiceOver walk-through of record → transcript → summary → export passes on device.
- §14.5 checklist complete; TestFlight build uploaded.
