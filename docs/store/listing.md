# App Store listing — VeraFlow

Draft for App Store Connect. No medical, legal, or HIPAA claims (SPEC §14.3). Price is Jeremy's call (SPEC §13.1, §19).

## Name (30)
VeraFlow: Meeting Notes

## Subtitle (30)
Private on-device transcripts

## Promotional text (170)
Record a meeting, get a transcript with speaker names, a summary, and action items — all made on your iPhone. No account, no subscription, nothing uploaded.

## Description (4000)
VeraFlow turns your meetings into notes you can act on, and it does all the work on your iPhone.

Record a client meeting, a job-site walk-through, a lecture, or a call on speaker. When you stop, VeraFlow transcribes the recording, labels who said what, and writes a summary with decisions, open questions, and action items with owners and due dates. Send the action items to Reminders, draft a follow-up email, or share the notes as PDF, Markdown, or plain text.

Nothing leaves your phone. There is no account to create and no server involved. Transcription uses Apple's on-device speech recognition, speaker labels run on device, and summaries use Apple Intelligence on the phone. If you turn on the app lock, your recordings sit behind Face ID.

WHAT YOU GET FREE
• Unlimited recording and importing (audio files, and the audio track of video recordings)
• Unlimited transcripts with speaker labels, search, and editing
• Three AI summaries to try the templates
• Plain-text copy of any transcript or summary

ONE-TIME UNLOCK
• Unlimited AI summaries with all templates: General meeting, Client meeting, Contractor walk-through
• Exports: PDF, Markdown, plain text files, email draft, and Apple Reminders with due dates
• Re-run a summary with a different template; keep the history
• Family Sharing supported. No subscription.

BUILT FOR PEOPLE WHO RECORD A FEW MEETINGS A WEEK
• Contractors: walk-throughs become punch lists with measurements you said, not ones the app invented
• Consultants and freelancers: client calls become follow-up emails in a minute
• Students and lecturers: long recordings become searchable, labelled transcripts

DETAILS
• Pause and resume from the Lock Screen; bookmarks while recording
• Crash-safe recording: if the phone dies, what you recorded so far is kept
• Choose your microphone, including Bluetooth headsets
• Dark mode, Dynamic Type, VoiceOver
• Requires iOS 18. AI summaries require an iPhone with Apple Intelligence on iOS 26 or later; transcripts and speaker labels work on every iPhone from iOS 18 (older iPhones download a speech model once, about 600 MB).

Summaries are AI-generated from your recording. Check important details.

## Keywords (100)
meeting,recorder,transcribe,transcript,notes,summary,action items,voice memo,private,offline,speaker

## What's new (first release)
First release.

## What's new (1.1, draft)
• Speaker filter: tap a name to see just their paragraphs
• Skip silence in playback
• Marks now carry a label and the summary weighs them
• Chapters from the summary's subjects, on the Audio tab and in the transcript
• Edit action items, owners and due dates, or add your own
• A notification when a summary is ready (only the recording's name is shown)
• Transcribe in another language, or transcribe a recording again
• Recently Deleted: 30 days to change your mind
• Export your whole library, or one recording, as a package you keep wherever you like
• Optional: include recordings in your iPhone backup
• Custom templates: start from a built-in one, hide sections, add a focus line
• Ask this recording: every answer points at a moment you can play, or says it isn't there
• See words while you record
• Translate a transcript and its summary on your iPhone
• Older iPhones: transcripts and speaker labels from iOS 18
• VeraFlow for Mac: the same app on your Mac, one purchase for both (macOS 26, Apple silicon for summaries)

## Support URL
(Jeremy) — marketing site support page

## Privacy Policy URL
(Jeremy) — `site/privacy.html` once hosted

## App Privacy (App Store Connect questionnaire)
Data Not Collected. The app makes no network requests with user data; the only network activity is Apple speech-model downloads, a one-time speaker-model download, and StoreKit.

## Review notes (App Review)
- VeraFlow works fully offline after two one-time downloads (Apple speech assets for the device language, and speaker-label models, about 60 MB). Both happen on first use with a progress indicator. On iOS 18–25 the speech model is FluidAudio's Parakeet (about 600 MB, same host as the speaker models). "Translate to…" uses Apple's Translation framework; iOS downloads the language pack.
- Free tier: three AI summaries in total, then the paywall offers a one-time unlock (product `veraflow.unlock.lifetime`). Transcripts and speaker labels are never limited.
- Summaries need Apple Intelligence. On a review device without it, the app still records and transcribes; the Summary tab explains that summaries aren't available on that device, and the paywall says so before purchase. To see a summary without Apple Intelligence, tap "Try a sample recording" on the empty Library (or Settings → About → Add the sample recording): it comes with its transcript, speaker names and a finished summary.
- Notifications: a local "Summary ready" notification is requested quietly (provisional) the first time a recording is still processing when the app goes to the background. It shows only the recording's name.
- The `.veraflowarchive` package (Settings → Storage → Export library) is a folder the user saves through the system document picker; nothing is uploaded by the app.
- Microphone: used only while recording; the audio session is closed when recording stops.
- Reminders: full access is requested only when the user chooses "Add to Reminders", to list their reminder lists. Nothing is read back except list names.
- Background audio mode: used only for an active recording (Lock Screen pause/resume).
- No accounts, no analytics, no crash reporting.

## Screenshots (6.9" and 6.5", light and dark)
Captured by `VeraFlowUITests/ScreenshotTests` with sample data:
1. Library with three recordings at different stages
2. Recorder with the waveform and Lock Screen-style controls
3. Transcript with speaker names and search
4. Summary with action items and due dates
5. Share sheet: PDF, Markdown, Reminders, email
6. Paywall (required by review for IAP)

Captions (draft): "Record. Everything stays on your iPhone." · "Who said what, labelled automatically." · "Action items with owners and dates." · "Send to Reminders or email in one tap." · "One price. No subscription."
