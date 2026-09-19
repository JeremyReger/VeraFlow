# Bundled summary model for iPhones without Apple Intelligence — investigation (v1.1 plan item 17)

Date: 2026-09-19. Author: Claude Code, for Jeremy. Scope: written investigation only; no code changes. The question SPEC §11.7 and the v1.1 plan leave open: should VeraFlow ship its own small language model so that iPhones without Apple Intelligence (and, after item 16, iPhones on iOS 18–25) get summaries, action items and Ask?

## Recommendation

**No-go for 1.2. Revisit for 1.3 once the Mac target has shipped and there is device data from the iOS 18 Parakeet path.** The short version: a model that fits a 4 GB iPhone and runs in a usable time is a 1.5–2 GB download that summarizes noticeably worse than Apple's model under the same no-invention rules, and it needs a second dependency (MLX Swift) plus a new eval and support surface. The people it would serve (iPhone XR/XS/11/12/13/14 and 15 non-Pro owners) already get the parts of the product that are on-device-only and honest: recording, transcripts, speaker labels, marks, exports. The gap is real but it is a feature gap, not a trust gap, and closing it badly would be worse than leaving it open.

## What phones are in the gap

| Phone | Chip | RAM | iOS 26? | Apple Intelligence? | After item 16 |
|---|---|---|---|---|---|
| iPhone XR / XS | A12 | 3–4 GB | No | No | Parakeet transcripts, labels; no summaries |
| iPhone 11 | A13 | 4 GB | Yes | No | Apple Speech transcripts, labels; no summaries |
| iPhone 12 / 13 / 14 | A14–A16 | 4–6 GB | Yes | No | same |
| iPhone 15 / 15 Plus | A16 | 6 GB | Yes | No | same |
| iPhone 15 Pro and later | A17 Pro+ | 8 GB | Yes | Yes | full product |

So the bundled model would target A13–A16 phones with 4–6 GB, and, at the low end, an A12 with 3–4 GB that is already carrying Parakeet (0.6 B parameters, roughly 600 MB of Core ML weights) for transcription and the diarizer.

## Candidate models (2–3 B parameters, 4-bit)

All figures are from public model cards and community MLX benchmarks, not from our own measurements; the numbers below are the expectation to test against, not results.

| Model | Params | 4-bit size on disk | Working RAM (weights + KV cache for a 4K prompt) | Expected speed on A16 (MLX) | Notes |
|---|---|---|---|---|---|
| Qwen2.5-3B-Instruct | 3.1 B | ~1.8 GB | ~2.4 GB | ~10–14 tokens/s decode; prefill of a 4K-token chunk ~15–25 s | Best instruction following of the three; 32K context; Apache 2.0 |
| Gemma-2-2B-it | 2.6 B | ~1.6 GB | ~2.1 GB | ~12–16 tok/s; prefill ~12–20 s | Good summaries; 8K context; Gemma licence (allows commercial use with terms) |
| Llama-3.2-3B-Instruct | 3.2 B | ~1.9 GB | ~2.5 GB | ~9–13 tok/s; prefill ~15–25 s | 128K context; Llama licence; strongest at structured JSON in informal tests |
| Phi-3.5-mini (3.8 B) | 3.8 B | ~2.2 GB | ~3 GB | slower | Too big for a 4 GB phone in practice |

A 1–1.5 B model (Qwen2.5-1.5B, Llama-3.2-1B, SmolLM2-1.7B) would fit a 3 GB phone but is not good enough at "use only what was said" to trust with names, dates and measurements; in informal tests those models paraphrase into invention far more than the 3 B tier.

## What the 25-minute recording would cost

The M5 pipeline sends map chunks of a few thousand tokens and a reduce step. For the 25-minute meeting (~4,000 words, ~5,500 tokens of `[mm:ss] Speaker N:` lines), the map-reduce is roughly 3 chunks of 2K tokens plus a 1.5K reduce plus the final typed step.

- Apple's model (iPhone 16 Pro): about 60–110 s end to end on device today (from PROGRESS and the rate-limit notes).
- Qwen2.5-3B 4-bit on an A16 (iPhone 14 Pro / 15) under MLX: prefill dominates. Roughly 3 × 15 s + 10 s + 10 s of prefill, plus ~600 output tokens at ~12 tok/s ≈ 50 s, for something like **2–3 minutes** and sustained full-CPU/GPU load; expect the thermal state to reach `.fair` or `.serious` on a 25-minute recording and the phone to warm noticeably.
- On an A13 (iPhone 11) roughly double that: 4–6 minutes.
- On an A12 with 3 GB (iPhone XR) it is not credible: after Parakeet and the diarizer there is not enough headroom for a 2.4 GB working set; jetsam would kill the app.

## Quality against Apple's model, same prompts, same rules

`docs/EVALS.md` lists the golden checks (no invented names, dates, numbers; action items with owners as spoken; due dates resolved in Swift). What we know from public comparisons of 3 B 4-bit models on summarization with strict grounding prompts:

- They follow "only from the transcript" less reliably than a 3 B model with a large instruction-tuning budget behind it; hallucinated owners and merged speakers are the common failure, which is exactly the failure this product promises not to have.
- Structured output: none of them has Apple's guided generation (`@Generable`), so the typed schema has to be enforced with a JSON grammar (MLX has constrained sampling but it is not on par) and a repair-and-retry step. Expect 5–15 % of calls to need a retry on the first pass, which multiplies the time above.
- Map-reduce over chunks helps the small model (shorter inputs) and hurts it (it has to keep consistent speaker names across chunks). The chapters and marks features (prompt v3) add fields that a 3 B model gets right less often.

Expectation: a Qwen2.5-3B run through the same fixtures would pass the "no invented content" checks most of the time but not reliably enough to ship without a human-review line that we do not have anywhere else in the product. That would require a different, more conservative template ("Notes" rather than "Summary") for those phones, which is itself a design and copy project.

## App size and download

- Bundling is out: 1.6–1.9 GB on top of the app breaks the 200 MB cellular default, makes every update a multi-GB download, and puts the whole install at risk on 64 GB phones.
- A one-time download from Hugging Face (the same host FluidAudio uses) is the only shape. That is a second ~1.8 GB model download next to Parakeet's 600 MB on the very phones with the least storage. SPEC §14.1 would need the model host added to the allowed list, and the network-policy test would need a second allow-listed file.
- Model updates are a support surface: a changed model changes summaries; the eval tables in `docs/EVALS.md` would need a second column and a second golden run for every prompt bump.

## Dependency

MLX Swift (`mlx-swift` + `mlx-swift-examples`' LLM package) is the realistic runtime: Core ML conversions of decoder-only LLMs exist but are slower and more fragile, and llama.cpp via a Swift wrapper is a C++ dependency with its own build story. MLX Swift adds:

- A second package on top of FluidAudio, which CLAUDE.md says needs a written reason in DECISIONS.
- A large binary (Metal kernels), a Swift 6 strict-concurrency story that is still uneven in the examples package, and a runtime that needs the GPU, which is exactly the background restriction we hit with the diarizer (DECISIONS 2026-09-18: "Insufficient Permission to submit GPU work from background"). Summaries would run only in the foreground on those phones.
- App Review: models downloaded at runtime are fine (FluidAudio already does it); executable code is not. MLX downloads weights only. OK.

## What would make this a go later

1. Device data from item 16: how many alpha users are on iOS 18–25 or on non-Apple-Intelligence phones, and whether they finish recordings and export without summaries. If the number is small, the feature is not worth its weight.
2. A 3 B model with guided JSON output that passes the EVALS checks on the same fixtures with the same prompts, run on an A16 phone within 3 minutes for the 25-minute recording and without a `.serious` thermal state.
3. Apple's `LanguageModel` protocol on iOS 27 (SPEC §11.7) maturing so an MLX model plugs into `LanguageModelSession` and the existing `@Generable` types work unchanged; that would remove most of the second code path.
4. The Mac target (item 15) shipping first: on the Mac a 3 B model is cheap to run, and if the Mac is where reviewing happens anyway, a Mac-only bundled model may be the better first step than a phone one.

## What to do in 1.2 instead

- Keep `SummarizationService` as the seam (already the case); add nothing.
- Make the no-summary experience on those phones as good as the summary one is: "Notes" export of transcript + marks + chapters from marks only (no model), and Ask limited to search with the BM25 retriever already built for item 11, which works without a model. Both are small and honest.
- Log, in Diagnostics only and never sent anywhere, the chip and iOS version so Jeremy can see the split from alpha testers' screenshots.

## Sources to verify before any go decision

Model cards for Qwen2.5-3B-Instruct, Gemma-2-2B-it and Llama-3.2-3B-Instruct (licence terms, context length); MLX Swift's iOS memory and speed numbers on the exact phones; Apple's guidance on runtime model downloads in App Review; FluidAudio's current platform floor for the Parakeet path this would sit beside.
