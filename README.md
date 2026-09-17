# VeraFlow

Private, on-device meeting recorder for iPhone. Record → transcribe → speaker labels → summary + action items. No servers, no account, no subscription.

**Riffle** is the codename for the alpha / demo builds (SPEC §0).

## Layout

- `docs/SPEC.md` — the build spec (source of truth)
- `docs/PROGRESS.md` — milestone checklist
- `docs/DECISIONS.md` — dated decisions and reasons
- `CLAUDE.md` — Claude Code instructions
- `.agents/rules/project.md` — Antigravity workspace rules

## Getting started (Mac with Xcode 27)

```sh
brew install xcodegen          # one time
xcodegen generate              # builds VeraFlow.xcodeproj from project.yml
scripts/test.sh                # unit + UI tests on an iPhone simulator
scripts/test.sh --unit-only    # faster
```

Open `VeraFlow.xcodeproj` in Xcode for device runs. The `VeraFlow-Alpha` scheme builds the "Riffle (alpha)" configuration.

Milestones are built in order (SPEC §16), one branch and PR each. `docs/PROGRESS.md` shows where things stand.

## Layout

- `project.yml` — XcodeGen project definition (the `.xcodeproj` is generated and gitignored)
- `VeraFlow/` — app sources: `App/`, `Features/`, `Services/`, `Persistence/`, `Preview/`, `Resources/`
- `VeraFlowTests/`, `VeraFlowUITests/` — Swift Testing unit tests and XCUITest flows
- `TestAudio/` — audio fixtures (gitignored; see its README)
- `scripts/test.sh` — the test entry point agents and CI use
