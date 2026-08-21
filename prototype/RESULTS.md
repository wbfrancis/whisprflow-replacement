# Prototype results — latency & injection spike

> Throwaway prototype. It answers two go/no-go questions before speccing v1; it is
> **not** production code and mirrors the real app's stack only where it matters.

## Q1 — Does transcribe-on-release feel seamless? (local whisper large-v3-turbo q5_0)

Measured with a synthetic 8.7s utterance through the exact afconvert→whisper path
(`say` voice, so accuracy here isn't the real-voice test — that's the mic run below).
Machine: M-series, 8 performance cores, Metal backend, Homebrew whisper.cpp 1.9.2.

| run | wall clock | whisper total | model load | encode | decode |
|-----|-----------|---------------|-----------|--------|--------|
| 1 (cold) | **17,945 ms** | 2,130 ms | 398 ms | 1,188 ms | 47 ms |
| 2 (warm) | **1,390 ms** | 1,283 ms | 221 ms | 857 ms | 7 ms |

**Reading it:**

- **The real app's per-utterance latency ≈ warm total − model load ≈ ~1.0–1.1 s** for
  an ~9s utterance. The model stays resident in memory, so the ~220 ms load is paid
  **once at launch**, not per utterance.
- **Encode (~850 ms) dominates and is roughly fixed** for any utterance up to whisper's
  30 s window — so a 3 s dictation costs about the same as a 9 s one. That sets a
  **~1 s floor** on release→text with this engine/model on this machine.
- **The 17.9 s first run is a one-time Metal shader compile**, not per-use cost. The
  real app must hide it by **warming up whisper at launch** (transcribe a silent buffer
  once on startup), or the very first dictation of a session will stall.
- Accuracy on synthetic voice was clean, including "Ads Data Hub" and "Spanner".

**Real-voice confirmation (2026-08-20):** live mic run captured 4.95 s and returned an
accurate transcript ("Check 2, check 2, check 5, check 6, check 7"). CLI-cold total was
1,838 ms including a 483 ms model reload → warm-app estimate ~1.3 s for a ~5 s utterance,
consistent with the ~1 s encode-bound floor. Q1 **confirmed**. (One recorder bug found and
fixed en route: `AVAudioFile` must be released before exit or the WAV header stays 0-length
and whisper reads no frames — a real note for the v1 capture code.)

**Verdict (Q1):** viable, with caveats. ~1 s warm is good-but-not-instant. Two levers if
it feels slow in real use: (a) a **Core ML encoder on the ANE** should cut the ~850 ms
encode meaningfully (the Homebrew build ran encode on Metal, not ANE); (b) streaming
partials (deferred to v2) would hide the floor. Recommend building v1 on turbo + a
launch warm-up, and only chasing Core ML if ~1 s bothers you in the real-voice run.

## Q2 — Does pasteboard paste + Cmd-V injection land text reliably?

**Confirmed (2026-08-20).** Ran `paste-test.swift` across real apps; text landed at the
cursor and the previous clipboard was restored. Pasteboard paste + synthesized ⌘V +
save-and-restore is the injection path for v1. Requires Accessibility permission (granted
to the host terminal here; the real app requests it via the first-run window).

## Both spike questions answered — spike closed

- [x] Q1 — real-voice latency + accuracy: ~1 s warm, accurate. Confirmed.
- [x] Q2 — injection reliability across real apps: works. Confirmed.

## Findings to carry into the v1 spec

1. **Warm whisper at launch** — transcribe a silent buffer once on startup to eat the
   one-time ~18 s Metal shader compile, so the first real dictation isn't slow.
2. **Release the `AVAudioFile` before the capture path finishes** — the header (frame
   count) only finalizes on deallocation; skip it and whisper reads a 0-length file.
3. **Core ML / ANE encoder is the latency lever** — the Homebrew build ran encode on
   Metal (~850 ms fixed floor). Only pursue if sub-second matters.
