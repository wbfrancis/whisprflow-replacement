# Prototype — dictation latency & injection spike

**Throwaway code that answers two questions** before we spec v1:

1. Does local whisper large-v3-turbo **transcribe-on-release feel seamless**?
2. Does **pasteboard paste + ⌘V** reliably land text at the cursor in real apps?

Not the real app — no global hotkey, no menu bar, no polish. It isolates the two
risky bits. Findings live in [RESULTS.md](RESULTS.md).

## Setup (already run once)

```bash
./setup.sh          # brew install whisper-cpp + download turbo q5_0 model (~547MB)
```

## Q1 — latency + real-voice accuracy (needs the mic)

```bash
./dictate-latency.sh
```

Speak a sentence, press **Return** to stop. It prints the transcript and the
release→text timing, split into resample / transcribe / (one-time model load). Run
it 3–4 times; ignore the first run (Metal warm-up). First launch prompts your
terminal for **Microphone** permission — grant it.

## Q2 — injection (needs Accessibility permission)

```bash
swift paste-test.swift "hello from the dictation prototype"
```

You get 4 seconds to click into a target app and place your cursor; it pastes,
then restores your previous clipboard. Try it in **Notes, a browser field, Slack,
and a code editor** — those are the apps that expose injection quirks. First run
needs your terminal added to **System Settings → Privacy & Security →
Accessibility** (the paste silently does nothing without it).

## Throw it away

This whole dir folds into nothing — the validated decisions go into `../CONTEXT.md`
and the real build. Nothing here is imported by production code.
