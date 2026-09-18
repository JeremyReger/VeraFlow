# Accessibility review — Section 508 / WCAG 2.2 AA / Apple HIG

Date: 2026-09-18 · Scope: every SwiftUI view under `VeraFlow/Features`, `VeraFlow/App`, `VeraFlowWidgets`, the Live Activity intents, and the export renderers. Read-only code audit; device checks listed at the end. Fix status is tracked in the last column (filled in as M9 progresses).

## Summary

VeraFlow has a solid accessibility baseline: nearly every icon-only control carries an `accessibilityLabel`, the waveform Canvas is hidden with a textual bookmark count next to it, the level meter exposes a value, alerts and confirmation dialogs are used for destructive and error flows, swipe actions have context-menu and toolbar-menu equivalents, text styles (not fixed sizes) are used for almost all copy, and system semantic colors are used so dark mode works. The gaps are concentrated in five places: (1) the app-lock overlay is not marked modal, so VoiceOver can read library content behind it (a privacy issue as much as an accessibility one); (2) the recorder timer's label replaces its spoken value, so a VoiceOver user cannot hear the elapsed time; (3) transcript paragraphs rely on tap gestures and a long-press context menu with no combined element or custom actions, so "Change speaker", "Revert", and "Play from here" are hard or impossible to reach with VoiceOver, Switch Control, or Full Keyboard Access; (4) there are no accessibility announcements anywhere, so recording start/pause, pipeline stage changes, search-match counts, and inline errors are silent; and (5) several tappable elements are well under 44 pt and some under the WCAG 2.2 24 pt minimum. Contrast issues are limited to speaker-palette colors used as caption text and red status text. The PDF export is untagged with no document metadata. Estimated readiness before fixes: roughly 60–65% of the applicable criteria.

## Findings

| ID | Severity | WCAG | File:line (at audit time) | Finding | Recommended fix | Status |
|---|---|---|---|---|---|---|
| A-1 | High | 1.3.1, 2.4.3 (+ privacy) | `App/RootView.swift:25-30`, `App/AppLock.swift:59-86` | `LockScreenView` is an overlay with an opaque background, but nothing removes the Library/detail hierarchy underneath from the accessibility tree. VoiceOver and Switch Control can reach recording titles and controls behind the lock. | `.accessibilityAddTraits(.isModal)` on the lock view and `.accessibilityHidden(lock.isLocked)` on the content; announce "VeraFlow is locked". | |
| A-2 | High | 1.3.1, 4.1.2 | `Recorder/RecorderView.swift:162-166` | `.accessibilityLabel("Elapsed time")` on the timer replaces the spoken content; VoiceOver never reads the time. No `.updatesFrequently`; 56 pt fixed font doesn't scale. | Label + `accessibilityValue` with the spoken duration + `.updatesFrequently`; `@ScaledMetric` size. | |
| A-3 | High | 2.1.1, 4.1.2, 1.3.1 | `RecordingDetail/TranscriptTab.swift:257-336` | Paragraphs are loose stacks; seeking is a tap gesture with no button trait; Play from here / Revert / Change speaker / New speaker exist only in a long-press context menu. | Combine the paragraph into one element with label, value, button trait, hint, and `accessibilityAction`s mirroring every menu item; expose "Now playing" / "Search match" as value. | |
| A-4 | High | 4.1.3 | `RecorderView.swift:157-160, 184-190`; `TranscriptTab.swift:56-90, 156-161`; `SummaryTab.swift:54-106`; `LibraryView.swift:166-170`; `PaywallView.swift:178-180` | No accessibility announcements anywhere: recording started/paused, interruption notices, pipeline stage changes, search-match counts, importing overlay, inline errors are all silent. | `AccessibilityNotification.Announcement` on phase/notice/stage/match-count changes. | |
| A-5 | High | 2.5.8, 4.1.2 | `SummaryTab.swift:292-329` | Action-item checkbox is a ~20 pt glyph with no state exposed; row pieces are separate stops; done state is strikethrough + gray only. | 44 pt hit area, `accessibilityValue("Done"/"Not done")`, combine the row, custom actions for play and toggle. | |
| A-6 | Medium | 2.5.8, 1.4.3, 4.1.2 | `TranscriptTab.swift:264-273` | Speaker-name button ~13 pt tall; label yields "Speaker Speaker 1, tap to rename" with the hint inside the label. | ≥ 24 pt (ideally 44) hit area; label = name, hint = "Renames this speaker". | |
| A-7 | Medium | 1.4.3 | `RecordingDetail/SpeakerActions.swift:121-127` (+ uses) | `SpeakerPalette` uses raw system orange/green/teal/pink/brown as caption-size text; 2.0–3.6:1 on white. | Asset-catalog colours tuned ≥ 4.5:1 for light and dark, or keep colour for the swatch only and name in `.primary`. | |
| A-8 | Medium | 4.1.2 | `Exports/ExportViews.swift:198-225` | Reminders item rows show selection only by glyph; no `.isSelected`/value. | `.isSelected` trait + value ("Selected", "Not selected", "Already in Reminders"). | |
| A-9 | Medium | 1.4.1, 4.1.2 | `RecorderView.swift:172-174, 318-333` | Level meter red-above-0.9 is colour only; value updates 10 Hz without `.updatesFrequently`. | `.updatesFrequently`, value says "too loud", `children: .ignore`. | |
| A-10 | Medium | 4.1.2, 1.3.1 | `RecordingDetail/AudioPlayerView.swift:16-41` | Slider value is a bare percent; the two time texts are unlabeled digit strings. | Slider value "m minutes s seconds of …"; hide the caption times. | |
| A-11 | Medium | 2.5.8 | `AudioPlayerView.swift:44-49, 60-67` | Back/Forward 15 s buttons ~22 pt. | 44×44 frames with `contentShape`. | |
| A-12 | Medium | 2.5.8 | `SummaryTab.swift:338-350` | "Play from mm:ss" mini buttons ≈ 20–24 pt; label read as digits. | Min 44 pt hit area; spoken label "Play from 3 minutes 45 seconds". | |
| A-13 | Medium | 2.5.8 | `Library/LibraryView.swift:175-198` | Tag chips ≈ 29 pt tall; no hint. | ≥ 44 pt hit area; hint "Filters the library by this tag". | |
| A-14 | Medium | 1.4.1 | `TranscriptTab.swift:260-262, 338-342`; `TranscriptText.swift:30-32` | Current paragraph / search match / current word are colour-only. | Expose as accessibility value (A-3); add a non-colour cue (leading bar or bold timestamp). | |
| A-15 | Medium | 1.4.4, 1.4.10 | `Onboarding/OnboardingView.swift:171-191` | Fixed page layout clips at AX3–AX5. | Wrap in `ScrollView`. | |
| A-16 | Medium | 1.4.4, 1.4.10 | `Recorder/ConsentSheet.swift:43` | `.medium` detent only; content overflows at large type with no scroll. | `[.medium, .large]` + `ScrollView`. | |
| A-17 | Medium | 1.3.1, 4.1.2 | `Services/Live/LiveExportService.swift:116-212` | PDF has no title/author metadata and no structure tags. | `documentInfo` (title, creator); tagged PDF per section. | |
| A-18 | Medium | 1.3.1 | `ExportViews.swift:23-62` | Gated exports swap the icon to a lock but the title stays "PDF"; no hint that it opens the paywall. | Hint "Opens the unlock screen" when gated. | |
| A-19 | Medium | 1.1.1 | `SummaryTab.swift:56-72`; `TranscriptTab.swift:92-113` | Progress banners' `ProgressView` has no label; percent is a separate element. | Label the progress view; combine the banner. | |
| A-20 | Medium | 1.1.1 | `ConsentSheet.swift:14-16`; `AppLock.swift:65-67`; `OnboardingView.swift:179-181`; `PaywallView.swift:124-127`; `SummaryTab.swift:60, 76`; `TranscriptTab.swift:97, 122, 137`; `RecorderView.swift:343, 395, 400`; `RecordingDetailView.swift:167-168`; `RecordingLiveActivity.swift:16-17, 63-66` | Decorative SF Symbols are read aloud ("person 2 wave 2", "sparkles"); Live Activity status icon read twice. | `.accessibilityHidden(true)` on decorative images. | |
| A-21 | Medium | 1.3.1 | `OnboardingView.swift:193-205`; `PaywallView.swift:198-210` | Capability rows and paywall benefits convey available/not by icon colour and strikethrough only. | Labels that include the state. | |
| A-22 | Low | 1.4.3 | `LibraryView.swift:318`; `RecordingDetailView.swift:145`; `OnboardingView.swift:136`; `ExportViews.swift:181`; `DiagnosticsView.swift:91`; `TranscriptionBenchmarkView.swift:117` | `.red` body text ≈ 4.0:1 on white. | Keep text `.primary` with a red icon, or a darker red asset. | |
| A-23 | Low | 1.4.4 | `RecorderView.swift:103-104, 201-239`; `AudioPlayerView.swift:55`; `AppLock.swift:66`; `OnboardingView.swift:180`; `PaywallView.swift:125`; `ConsentSheet.swift:15` | Fixed icon sizes / fixed circular frames don't scale. | `@ScaledMetric`. | |
| A-24 | Low | 1.4.4 | `LibraryView.swift:299-327`; `RecordingLiveActivity.swift:32-71` | `lineLimit(1)` on titles; fixed metadata row; compact timer capped at 56 pt. | `lineLimit(2)`, `ViewThatFits`, `minimumScaleFactor` in the widget. | |
| A-25 | Low | 2.5.8 | `TranscriptTab.swift:143-216`; `SummaryTab.swift:81-92, 202-221` | Clear-search, Speakers menu icon, small Retry/Unlock, footnote "Change template" all under 44 pt. | 44 pt minimum frames. | |
| A-26 | Low | 2.3.3, 2.2.2 | `RecorderView.swift:168-170, 328`; `TranscriptTab.swift:248, 252`; `OnboardingView.swift:29`; `RootView.swift:20` | No Reduce Motion handling. | Read `accessibilityReduceMotion`; pass `nil` animations; simpler waveform. | |
| A-27 | Low | 2.1.1 | `Library/TagEditorView.swift:37-43` | Tag removal is swipe-only. | `EditButton()` or per-row Remove. | |
| A-28 | Low | 4.1.2, 1.3.1 | `TranscriptTab.swift:167-174, 285` | Hint on a non-interactive badge; every edit field labelled "Paragraph text". | Label with the explanation; per-paragraph field labels. | |
| A-29 | Low | 1.3.1 | `LibraryView.swift:313-324`; `SummaryTab.swift:144, 349`; `TranscriptTab.swift:275`; `RecordingDetailView.swift:132`; `DiagnosticsView.swift:87-89`; `RecorderView.swift:177`; `ExportRenderer.swift:38, 68` | "·" read as "middle dot"; mm:ss read as digits; `S1` fallback read aloud; manual pluralisation. | Hide separators, spoken durations, "Speaker n" fallback, inflection. | |
| A-30 | Low | 1.3.1 | `ExportRenderer.swift:12-73`; `LiveExportService.swift:174-210` | Exports omit the AI disclaimer; PDF footer gray ≈ 3.9:1. | Append the disclaimer; darker footer. | |
| A-31 | Low | 1.4.3, 1.4.11 | `Assets.xcassets/AccentColor` | Single accent (#1D7AC7) ≈ 4.51:1, no margin, no dark variant. | Darken light variant, add dark variant. | |
| A-32 | Low | 4.1.2 | `Settings/SettingsView.swift:80-83` | Diagnostics 7-tap unlock is undiscoverable by assistive tech (acceptable for a hidden developer screen). | Optional custom action. | |
| A-33 | Low | 1.1.1, 4.1.2 | `Settings/TranscriptionBenchmarkView.swift` (DEBUG only) | Unlabelled editor; icon-only metrics. | Labels. Not shipped in release. | |

## Verified OK

- Icon-only buttons are labeled: Start/Stop/Pause/Resume/Bookmark, player Back/Forward/Play-Pause, clear search, Speakers menu, toolbar Settings/More/Share/Actions menus, Live Activity bookmark.
- `WaveformView` is hidden from VoiceOver with the bookmark count exposed as text beside it; `LevelMeter` exposes label + value; the library pipeline progress has a stage label.
- Favorite and Imported icons in library rows carry labels; tag chips carry `.isSelected`.
- Swipe actions (Delete/Favorite) have equivalents in the row context menu and the detail toolbar; speaker rename is available from the Speakers menu as well as by tapping the name.
- Errors and destructive actions use alerts / confirmation dialogs with explicit buttons; rename alerts use labelled text fields.
- Dynamic Type text styles nearly everywhere; system components (`Form`, `List`, `ContentUnavailableView`, `LabeledContent`) for Settings, Diagnostics, naming, tags, Reminders.
- Semantic/adaptive colours throughout; no hardcoded hex colours in views; status colours always paired with text.
- AI disclaimer is a section footer VoiceOver reads; walk-through measurement note is exported.
- Markdown export has real headings, task checkboxes, timestamped speaker lines.
- Live Activity intents have localized titles; buttons use `Label`s; the timer uses `Text(timerInterval:)` which VoiceOver reads live.
- No auto-dismissing content or time limits; the "Resume recording?" alert waits.
- App lock explains itself when no passcode is set; the lock screen has a visible Unlock button.
- Search fields have prompts; accessibility identifiers exist across screens.

## Needs a device

- VoiceOver reading order and rotor on the transcript, action-item rows, and Library rows.
- Whether the current iOS build exposes `.contextMenu` and `.swipeActions` in the VoiceOver Actions rotor, and whether Switch Control / Full Keyboard Access can reach the paragraph actions.
- Real contrast of `.secondary` and accent text over `.bar`, `.thinMaterial`, `.regularMaterial` in light and dark.
- Dynamic Type at AX3–AX5: recorder control row, microphone capsule, library metadata row, segmented picker, consent sheet, onboarding, Dynamic Island compact timer.
- Voice Control names for Start Recording, Stop, Speakers, Clear search, Unlock.
- Announcement timing and focus after the consent sheet, the interruption alert, and lock/unlock.
- Level-meter chatter with `.updatesFrequently` at 10 Hz.
- Live Activity: labels on Pause/Resume/Bookmark under VoiceOver, timer at large text, intents firing under VoiceOver.
- PDF: reading order and tags in Preview/Acrobat with a screen reader.
