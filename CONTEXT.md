# WhisprFlow Replacement — CONTEXT

A barebones, seamless dictation tool. **macOS is the priority platform** (this doc); iPhone is a later, separate build.

## Goal

Replace WhisprFlow with the most barebones feature set: press a key, talk, get accurate text inserted where the cursor is. No analytics or "analysis" features — unless a signal can be fed *back* into dictation to improve accuracy (e.g. custom vocabulary).

## Settled facts (environment)

- **Machine**: macOS 14.6.1 (Sonoma), Apple Silicon (arm64).
- **Toolchain present**: full Xcode 16.2, Swift 6.0.3, Homebrew 6.0.18, Python 3.14, Node 24. No whisper installed yet.
- Implication: a native Swift menu-bar app is fully viable; local whisper.cpp with Metal/CoreML acceleration is viable; cloud APIs are viable.
- Note: `SpeechAnalyzer` (Apple's newer STT) is macOS 26+ only, so it is **not** available on 14.6. On-device options here are whisper.cpp or the older `SFSpeechRecognizer`.

## Deferred (iPhone — researched, out of scope this session)

- iOS custom keyboard extensions **cannot** record the microphone (Apple blocks it at runtime; "Full Access" does not grant mic). iPhone dictation requires the **companion-app pattern**: keyboard button → containing app records + transcribes → shared App Group → keyboard inserts text. See `research/ios-keyboard-mic-constraint.md`.

## Settled decisions (Round 1)

- **Engine**: Local **whisper.cpp** for v1, behind a `TranscriptionEngine` abstraction (protocol) so a cloud engine can drop in later without touching the rest of the app.
- **Activation**: **Push-to-talk** by default (hold to talk, release to transcribe+insert), with a config option to switch to **Toggle**. Default key is **`fn`**, but the hotkey must be easily configurable.
- **Text injection**: **Pasteboard paste with save-and-restore** of the previous clipboard contents by default (paste is invisible to the user's clipboard). Config toggle to **disable restore**, which leaves the dictated text sitting on the clipboard.
- **App shape**: Native **Swift menu-bar agent** (`LSUIElement`), built as a **personal tool** — ad-hoc signed, no notarization/distribution.
- **Accuracy-feedback feature (custom vocabulary)**: **deferred to v2.** v1 is a clean dictate-and-insert loop. Local whisper's `initial_prompt` keeps the door open.

## Settled decisions (Round 2)

- **Model**: `large-v3-turbo`, quantized, with a CoreML encoder. Drop to `medium` only if warm-up/RAM is a problem.
- **Timing**: transcribe-on-release for v1 (no streaming partials).
- **Feedback**: menu-bar icon state change + subtle start/stop sound. No floating overlay in v1.
- **Hotkey**: still resolving — see Q7b (bare spacebar is not viable; picking the single hold-key).

## Settled decisions (Round 3)

- **Hotkey (resolved)**: **Right Option (`⌥`) held alone** is the default push-to-talk key. Bare spacebar is ruled out (it's a real character globally and can't be trapped without breaking space typing). Fully reconfigurable to `fn` or a chord.
- **Model acquisition**: **download on first run** into `~/Library/Application Support/`, not bundled in the app.
- **First-run permissions**: a **minimal guided first-run window** — request Microphone, then deep-link the user to the Accessibility pane with a direct "Open" button.

## Frontier: empty — design tree complete.

## Prototype outcome (spike closed 2026-08-20 — see `prototype/RESULTS.md`)

Both go/no-go questions passed:
- **Latency**: local whisper turbo q5_0 gives ~1 s warm release→text (encode ~850 ms is
  a fixed floor up to whisper's 30 s window). Good enough for transcribe-on-release.
- **Injection**: pasteboard paste + ⌘V + save-and-restore lands text reliably in real apps.

**Findings that become v1 spec requirements:**
1. Warm whisper up at launch (transcribe a silent buffer once) to hide the one-time ~18 s
   Metal shader compile.
2. In the capture code, release the `AVAudioFile` before finishing so the WAV header
   finalizes (otherwise transcription gets a 0-length file).
3. Core ML / ANE encoder is the lever to go sub-second later; not needed for v1.

---

## v1 build summary (the shared understanding)

A native Swift **menu-bar agent** (`LSUIElement`, personal tool, ad-hoc signed, no notarization) that does one thing: **hold Right Option → talk → release → accurate text pasted at the cursor.**

**The loop:**
1. A global `CGEventTap` watches for **Right Option** held alone (configurable; supports push-to-talk default and a toggle mode).
2. On key-down, capture mic audio via `AVAudioEngine` (16kHz mono). Menu-bar icon flips to "recording" + a subtle start sound.
3. On key-up, stop capture, play a stop sound, and transcribe the whole utterance (**transcribe-on-release**, no streaming).
4. Transcription runs through a `TranscriptionEngine` protocol. v1 impl = **local whisper.cpp**, `large-v3-turbo` quantized + CoreML encoder, downloaded on first run. The protocol keeps a cloud engine as a drop-in later.
5. Insert the transcript by **pasteboard paste + ⌘V**, with **save-and-restore** of the prior clipboard by default (config toggle to skip restore and leave the text on the clipboard).

**Permissions**: Microphone + Accessibility, requested through a guided first-run window.

**Explicitly deferred to v2**: custom-vocabulary / accuracy-feedback layer (whisper `initial_prompt` keeps the seam open), streaming partials, floating on-screen indicator, cloud engine, notarization/distribution.

**Separate track (researched, not this build)**: iPhone via the companion-app pattern — keyboard extensions can't record mic. See `research/ios-keyboard-mic-constraint.md`.
