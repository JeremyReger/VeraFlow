# Sample recording (Riffle demo, SPEC §0; v1.1 plan item 7)

This folder is copied into the app bundle as-is (a folder reference in `project.yml`). When it
holds a VeraFlow archive (`manifest.json` + `recordings/<uuid>/`), the app offers "Try a sample
recording" on the empty Library and "Add the sample recording" in Settings → About, and alpha
builds add it on first launch. While it holds only this README, those buttons stay hidden.

## How to produce it (Jeremy)

1. Record a scripted two-person conversation of about two minutes on your iPhone: a project
   kickoff with one decision, two action items with spoken dates, and one open question. The
   second voice must be someone who agreed to be in the app.
2. Let it transcribe, label the speakers (rename both), and summarize with the General template
   on a build with prompt v3. Mark one moment while recording so the sample shows a mark.
3. Rename it "Sample: Project kickoff".
4. Recording menu → Export recording… → save the `.veraflowarchive` to Files.
5. Copy the package's *contents* (`manifest.json` and `recordings/`) into this folder, replacing
   nothing else, and commit. Keep the audio under 2 MB (two minutes of 64 kbps AAC is about 1 MB).

The fixture keeps the Riffle name in the repo only; the app shows the recording's own title.
