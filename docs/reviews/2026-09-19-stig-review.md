# STIG review — Apple iOS/iPadOS STIG and what it means for VeraFlow

Date: 2026-09-19 · Asked by Jeremy: "review the STIGs and see if this passes"
(https://www.stigviewer.com/stigs/apple_iosipados_18, https://www.cyber.mil/, https://ncp.nist.gov/checklist/1263).

## Sources actually read

The DISA sites, STIG Viewer, NIST NCP, and the commercial mirrors are all blocked from the review
environment, so this review is built from:

- The machine-readable copy of the **Apple iOS/iPadOS 26 STIG, Version 1, Release 1** carried by
  NIST's macOS Security Compliance Project (`usnistgov/macos_security`, branch `ios_26`,
  "iOS 26 Guidance, Revision 3.0", dated 2026-06-22). Its `baselines/ios_stig.yaml` lists 84 rules
  with the DISA IDs (`AIOS-26-…`), severities, discussion text and the MDM payload keys, plus a
  Supplemental section for the rules that are procedural rather than a profile key.
- Search-engine excerpts of the **iOS/iPadOS 18 STIG** (IDs `AIOS-18-…`, V1R1 December 2024, later
  releases through 2025). The 18 and 26 STIGs are the same rule families with renumbered IDs; the
  18 STIG's V1R2 added the ChatGPT/"external intelligence" restriction and Apple Intelligence
  guidance in its Supplemental document. Jeremy's phone runs iOS 27, so the 26 STIG (and its
  successor) is the one an assessor would apply.
- Excerpts of the allow-list rule (`V-267997` in the 18 STIG; `AIOS-26-007400` in the 26 STIG):
  the app allow list "must be configured to not include applications that use artificial
  intelligence (AI) which processes data in the cloud (off device)", with Apple Intelligence
  Private Cloud Compute called out as the one permitted exception.

What could **not** be verified verbatim: the exact DISA check/fix wording of every rule (the mSCP
copy carries the discussion and the profile key, not DISA's check text), and the
**Application Security and Development STIG** rule IDs. Those are called out as "verify on
cyber.mil" below rather than guessed.

## The one-paragraph answer

The iOS STIG is a **device** benchmark: 84 configuration rules an MDM pushes to a supervised
iPhone (passcode policy, iCloud off, Siri off, AirDrop off, managed-app data boundaries, and so on).
An app does not "pass" it. An app is either (a) eligible for the device's app allow list, and
(b) still useful once every rule is applied. VeraFlow is eligible: it stores nothing in iCloud,
backs nothing up, sends no diagnostics, syncs nothing between devices, and its AI runs entirely on
the device, which is exactly the property the allow-list rule screens for. It also stays useful
under the full baseline, with one open question that only a supervised test device can answer:
whether the STIG's mandatory Siri restriction also switches off the on-device Foundation Models
that write summaries. Transcripts and speaker labels are unaffected either way. Three
improvements would make the app a better citizen on a STIG'd device: managed app configuration so
an MDM can force the app lock and the minimal Lock Screen, a stricter data-protection class as an
option, and an entitlements file (already planned) once the app is on a paid developer account.

## Rule-by-rule: the rules that touch the app

Severity is DISA's. "Status" is VeraFlow's position on the current build.

| STIG ID (iOS 26) | Sev | Rule | What it means for VeraFlow | Status |
|---|---|---|---|---|
| AIOS-26-007400 (18: V-267997) | Supplemental | App allow list must exclude apps that back up to non-DoD clouds, send diagnostics to non-DoD servers, sync between the user's devices, share data unencrypted, or use AI that processes data off device (Apple PCC excepted) | The app does none of these. Every source file is network-free (`NetworkPolicyTests`), no analytics or crash SDK, no iCloud, no App Group, no sync. Summaries use the on-device model only; PCC and third-party LLMs are ruled out by design (SPEC §14.1). | Eligible for the allow list |
| AIOS-26-003600 | Medium | Managed apps must not store data in iCloud (`allowManagedAppsCloudSync=false`) | No iCloud containers, no `NSUbiquitous*`, no CloudKit. | Pass |
| AIOS-26-003000, -010700, -009200 | Medium | iCloud backup off; encrypted backups forced; no backup of app data to locally connected systems | Recordings, the SwiftData store and the model cache are already excluded from backup (`DataProtection`). Nothing the app writes reaches a backup. | Pass, and consistent with the rule even on an unmanaged phone |
| AIOS-26-009700 | Medium | Documents from managed sources may not open in unmanaged destinations (`allowOpenFromManagedToUnmanaged=false`) | Share sheet, "Share audio", Files export, Mail draft and Reminders all go through system channels the MDM polices. When VeraFlow is a managed app, iOS simply hides unmanaged targets; the app needs no code for this and degrades cleanly (the share sheet shows fewer apps). | Pass |
| AIOS-26-014600 | Medium | Managed pasteboard: copy from managed to unmanaged apps blocked | "Copy summary" / "Copy action items" already write local-only, expiring clipboard items (security review S-4). Under this rule iOS refuses the paste into unmanaged apps; nothing for the app to do. | Pass |
| AIOS-26-011500, -010200 | Medium | AirDrop treated as unmanaged / disabled | AirDrop is only reachable through the system share sheet; the MDM removes it. | Pass |
| AIOS-26-007500, -007600 | Medium | No Notification Center or calendar on the Lock Screen | The app posts no notifications. Its **Live Activity** (recording banner with Pause/Resume/Mark) is a Lock Screen surface; today it shows the auto title ("Meeting · date"), and Now Playing shows "Recording" when the app lock is on. Recommendation R-1 below makes the minimal banner enforceable by MDM. | Pass with R-1 |
| AIOS-26-018000 | — | Screenshots and screen recording disabled | Device-level. The app's privacy shield already blanks the app-switcher snapshot when the lock is on (S-1). | Pass |
| AIOS-26-016100 (high), -007200, -016200, -016300 | High/Med | **Siri disabled** (`allowAssistant=false`), Siri while locked disabled, Siri user-generated content and suggestions disabled | The app uses no Siri, App Intents or Shortcuts. **Open question:** on iOS 26/27 the Settings switch is "Apple Intelligence & Siri"; whether `allowAssistant=false` also reports `SystemLanguageModel.availability` as unavailable is not documented in the STIG or the mSCP rule. If it does, summaries and action items are off on STIG'd devices and the app says so honestly (capabilities screen, "AI summaries aren't available on this iPhone" copy, Settings status dot). Transcripts, speaker labels, marks, search and exports are unaffected. The STIG itself allows Siri "if required to meet Section 508 compliance", which is a lever an AO could use. | Verify on a supervised device (V-1) |
| AIOS-26-015400 | Medium | External intelligence integrations (ChatGPT) disabled | Never used. | Pass |
| AIOS-26-017200, -017300, -017400 | — | Image Wand, Image Playground, Genmoji disabled | Never used. The STIG restricts these Apple Intelligence *features* individually; it does not carry a blanket "disable Apple Intelligence" key, which is why V-1 is the only open question. | Pass |
| AIOS-26-014400, -014500 | Medium | On-device dictation and translation enforced | Transcription is `SpeechAnalyzer` / `SpeechTranscriber` on device (Apple's assets download once from Apple, permitted by SPEC §14.1). The app never uses server dictation. | Pass |
| AIOS-26-013400 | Medium | No diagnostic or usage data to Apple | The app has no crash reporter or analytics; `OSLog` lines carry counts and UUIDs, never transcript text (S-9). | Pass |
| AIOS-26-015700 | — | Built-in Call Recording disabled | Unrelated: iOS gives no app access to another app's call audio (DECISIONS 2026-09-18), so VeraFlow cannot record calls at all. Worth stating in the listing so an assessor does not assume it. | N/A |
| AIOS-26-018100 | Medium | Camera disabled | The app never uses the camera. "Import Video from Photos" uses the Photos picker, which the MDM can also restrict; import simply fails closed. | Pass |
| AIOS-26-007000, -014900, -015000 | Low/Med | No enterprise-trusted apps, no third-party marketplaces, no web-distributed apps | Distribution must be App Store (public or custom app via Apple Business Manager) or MDM-installed. Ad-hoc/enterprise signing is out. TestFlight builds may be blocked on supervised devices; plan the DoD pilot around a custom-app build. | Plan for it (R-3) |
| AIOS-26-006500…-006950, -010400, -006800 | High/Med | Passcode forced, length ≥ ODV, no simple sequences, history, lockout, auto-lock ≤ ODV minutes, immediate grace period | Guarantees `AppLock.canAuthenticate` is true, so the app's Face ID / passcode lock (`deviceOwnerAuthentication`) is always available. The app lock is off by default; R-1 lets an MDM force it on. | Pass with R-1 |
| AIOS-26-013200 | Medium | Supervised MDM enrolment | Precondition for all of the above. Managed app configuration (R-1) rides on this. | — |
| AIOS-26-011200 | Supplemental | Latest iOS installed | Minimum deployment target iOS 26.0; iOS 27 APIs behind availability checks. | Pass |
| AIOS-26-008400, -011900, -014700, -017700 | Supplemental | DoD warning banner, user training, DoD PKI certificates, Mobile Threat Detection app | Device and organisation controls; no app interaction. The app makes no TLS connections, so PKI pinning does not apply. | N/A |

Everything else in the baseline (AirPlay, AirPrint, Exchange, Apple Watch, eSIM, Find My, Handoff,
Files network/USB drives, password autofill, movie/TV ratings, VPN configuration, iPhone
Mirroring) has no interaction with the app.

## App-level expectations (Application Security and Development STIG)

Assessors evaluating a custom app usually apply the ASD STIG (V6) alongside the platform STIG.
Its rule IDs are not reproduced here because the text could not be fetched; the topics that
apply to a standalone, network-free app and where VeraFlow stands:

| Topic | VeraFlow | Status |
|---|---|---|
| Data at rest encrypted with a validated algorithm | iOS Data Protection (AES-256, Apple's FIPS 140-3 validated CoreCrypto). Audio and the store use `completeUntilFirstUserAuthentication`; exports use `complete`. No app-level crypto to assess. | Pass; R-2 offers the stricter class |
| Session lock / re-authentication | Face ID or passcode lock with a privacy shield on inactive; locks on background. | Pass (default off; R-1) |
| Authentication | Delegated to the OS (`LAContext.deviceOwnerAuthentication`); no app accounts, no credentials stored. | Pass |
| Sensitive data in logs and error messages | Logs carry no user content; failure text logged private; startup fault message constant (S-9, S-17). | Pass |
| Temporary files | Exports protected and deleted on share-sheet dismissal; `tmp/Exports`, `tmp/PhotoImports`, `Documents/Inbox` swept at launch (S-5, S-7, S-8). | Pass |
| Clipboard | Local-only, 2-minute expiry (S-4). | Pass |
| Third-party components | One dependency, FluidAudio 0.15.7, pinned by exact version and commit; `Package.resolved` tracked. Model files downloaded once from Hugging Face with size-only validation (S-11). | Pass; S-11 still open (bundle the models or verify hashes) |
| Network surface | None with user data; ATS default; privacy manifest declares no tracking. | Pass |
| Mobile code / dynamic loading | None. | Pass |
| Audit records | No security event log beyond the on-device Diagnostics timeline (stage changes, failures, no content). A DoD deployment that requires per-action audit would need a decision; most mobile app assessments accept OS-level auditing for a single-user app. | Decision for Jeremy |
| Input validation on files | Imports go through `AVAudioFile` / `AVAssetExportSession`; unsupported files fail closed with a message; malformed audio cannot execute anything. | Pass |
| Accessibility (Section 508, applied alongside) | See `docs/reviews/2026-09-18-accessibility-review.md`: 28 of 33 findings fixed, the rest partial. | Ongoing |

## Recommendations

- **R-1 Managed app configuration (AppConfig).** Read the standard `com.apple.configuration.managed`
  dictionary from `UserDefaults` and honour a few keys an MDM can set: `requireAppLock` (force the
  lock on and hide the Settings toggle), `minimalLockScreen` (Live Activity and Now Playing show
  "Recording" only), `disableExports` (hide share, Files, mail and Reminders), `disableImports`.
  Small change; it turns the app's existing privacy features into something an AO can mandate
  rather than hope for. Document the keys for the MDM administrator.
- **R-2 Strict data-protection option.** Offer `NSFileProtectionComplete` for audio and the store
  behind a managed key or a Settings toggle. Cost: processing cannot run while the phone is locked,
  so transcription waits for unlock; the processing card already explains what continues in the
  background and would say so. Default stays `completeUntilFirstUserAuthentication` so the
  pipeline keeps working after Stop.
- **R-3 Distribution.** Plan the DoD pilot as a custom app through Apple Business Manager
  (MDM-installed) rather than TestFlight, and re-add the `com.apple.developer.default-data-protection`
  entitlement declaration once the app is on a paid Developer Program (S-6, S-16).
- **R-4 Listing and assessor notes.** State plainly: no network with user data, no iCloud, no
  backup, no PCC, no third-party AI, cannot record calls, AI features degrade to transcript-only
  when Apple Intelligence is unavailable. These are the exact questions the allow-list rule asks.

## Verification an assessor will want (needs a supervised device)

- **V-1** With the STIG profile applied (in particular `allowAssistant=false`): does
  `SystemLanguageModel.default.availability` still report available? If not, confirm the app's
  transcript-only path and its copy on the capabilities screen and Settings.
- **V-2** With `allowOpenFromManagedToUnmanaged=false` and `requireManagedPasteboard=true`: share
  sheet shows managed targets only; Copy summary cannot be pasted into an unmanaged app; Files
  export lands only in managed locations.
- **V-3** With `allowLockScreenNotificationsView=false`: the recording Live Activity still shows
  Pause/Resume/Mark and shows no recording title (after R-1).
- **V-4** With `allowCloudBackup=false` and `forceEncryptedBackup=true`: a local encrypted backup
  contains no VeraFlow recordings or store files (they are excluded regardless).
- **V-5** Passcode policy in force: the app lock toggle is enabled and Face ID falls back to the
  device passcode.

## Bottom line for Jeremy

Nothing in the iOS STIG blocks VeraFlow, and its design (on-device only, no cloud, no backup, no
diagnostics) is precisely what the allow-list rule wants to see. The only thing that could reduce
functionality on a STIG'd phone is the mandatory Siri restriction possibly taking Apple
Intelligence with it, which would leave transcripts and speaker labels intact and switch summaries
off with an honest message. R-1 is the one change worth making before showing the app to an
assessor.
