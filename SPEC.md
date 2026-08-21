# Spec — macOS dictation app (WhisprFlow replacement), v1

Status: ready-for-agent. Source of design truth: `CONTEXT.md`. Prototype evidence:
`prototype/RESULTS.md`. iPhone is a separate, later build (see
`research/ios-keyboard-mic-constraint.md`).

## Problem Statement

I dictate on my Mac with WhisprFlow and want to replace it with something barebones I
own. I don't want analytics or "insights" — I want to press one key, talk, and have
accurate text appear where my cursor already is, in any app, fast enough that it feels
seamless. WhisprFlow does more than I need and isn't mine to change.

## Solution

A small native macOS menu-bar app that runs in the background. I hold one key
(Right Option by default), speak, release, and a second later the transcribed text is
pasted at my cursor in whatever app I'm using. Transcription runs locally on my machine,
so it's private, free per use, and works offline. A menu-bar icon and a subtle sound tell
me when it's listening. Nothing else — no windows, no dashboards.

## User Stories

1. As a Mac user, I want to hold Right Option and have the app record my voice, so that I start dictation with one deliberate gesture.
2. As a Mac user, I want the text to appear at my cursor when I release the key, so that dictation lands exactly where I was typing.
3. As a Mac user, I want transcription to run locally, so that my audio never leaves my machine and works offline.
4. As a Mac user, I want accurate transcription of normal speech including names and technical terms, so that I spend little time fixing mistakes.
5. As a Mac user, I want the text inserted into any app (browser, notes, chat, code editor), so that I'm not limited to specific apps.
6. As a Mac user, I want my existing clipboard restored after a dictation, so that dictating doesn't clobber what I had copied.
7. As a Mac user, I want an option to leave the dictated text on the clipboard instead of restoring, so that I can paste it again elsewhere when I choose.
8. As a Mac user, I want a menu-bar icon that changes when recording, so that I always know whether the app is listening.
9. As a Mac user, I want a subtle sound when recording starts and stops, so that I get feedback without watching the menu bar.
10. As a Mac user, I want to switch the activation key from a config, so that I can pick a key that suits me.
11. As a Mac user, I want a config option to switch from push-to-talk (hold) to toggle (tap on, tap off), so that I can dictate long passages without holding a key.
12. As a Mac user, I want the app to guide me through granting Microphone and Accessibility permissions on first run, so that setup isn't confusing.
13. As a Mac user, I want the transcription model downloaded automatically on first run, so that I don't have to find and place model files myself.
14. As a Mac user, I want the first dictation of a session to be as fast as the rest, so that I'm not surprised by a slow first use (the app warms up the engine at launch).
15. As a Mac user, I want the app to run as a background agent with no dock icon, so that it stays out of my way.
16. As a Mac user, I want to quit the app from the menu-bar menu, so that I can stop it cleanly.
17. As a Mac user, I want a clear indication if a dictation captured no audio, so that I know when a recording failed rather than getting silent nothing.
18. As a Mac user, I want a clear message if Microphone or Accessibility permission is missing, so that I know why dictation isn't working and how to fix it.
19. As a Mac user, I want a graceful, visible failure if transcription errors, so that the app never silently does nothing.
20. As a Mac user, I want dictation to keep working across app switches without re-granting anything, so that it's reliable day to day.
21. As a Mac user, I want the release-to-text delay to stay around a second, so that dictation feels responsive.
22. As a Mac developer of this tool, I want transcription behind an engine abstraction, so that a cloud engine can be added later without rewriting the app.
23. As a Mac developer of this tool, I want the activation, mode, and clipboard-restore settings persisted, so that my preferences survive restarts.
24. As a Mac developer of this tool, I want the core dictation loop covered by automated tests at one seam, so that I can change adapters without fear.

## Implementation Decisions

- **App shape**: native Swift menu-bar agent, `LSUIElement = true` (no dock icon). Personal tool — ad-hoc signed, no notarization/distribution. Built with Xcode 16 / Swift 6 on Apple Silicon (macOS 14.6+).
- **Core orchestrator — `DictationController`**: owns the dictation state machine and the hold→record→transcribe→inject loop. It depends only on protocols, never on concrete OS types. This is the single test seam. Rough state shape (from the design, not a demo):
  - `idle → recording` on activation key-down (push-to-talk) or key-tap (toggle);
  - `recording → transcribing` on key-up (push-to-talk) or second tap (toggle);
  - `transcribing → injecting → idle` when the transcript is ready;
  - a captured-empty transcript short-circuits to `idle` with a "no audio" signal;
  - a transcription error routes to `idle` with a visible error signal.
- **Seam protocols** (the four OS boundaries, each faked in tests):
  - `HotkeySource`: reports activation key-down / key-up (or tap events) for a configurable key; default is Right Option held alone, captured via a `CGEventTap` watching modifier-flag changes.
  - `AudioSource`: starts/stops mic capture and yields 16kHz mono audio. Real impl uses `AVAudioEngine`; **must release/finalize its `AVAudioFile` or buffer before handing audio on, or the data is unreadable** (prototype finding).
  - `TranscriptionEngine`: `func transcribe(_ audio) async throws -> String`. v1 impl `LocalWhisperEngine` wraps whisper.cpp (`large-v3-turbo` q5_0) with the model resident in memory. The protocol is the drop-in seam for a future `CloudEngine`.
  - `TextInjector`: inserts a string at the cursor. Real impl saves the current pasteboard, sets the transcript, synthesizes ⌘V via `CGEvent`, then (unless restore is disabled) restores the saved pasteboard.
- **Engine warm-up**: on launch the app loads the whisper model and runs one transcription on a silent buffer to eat the one-time ~18s Metal shader compile (prototype finding). Startup is allowed to take a moment; per-utterance latency after that is ~1s warm.
- **Model acquisition**: `large-v3-turbo` q5_0 downloaded on first run into `~/Library/Application Support/<app>/`, not bundled. Network needed once.
- **Text injection default**: pasteboard paste + ⌘V with save-and-restore ON by default; a config toggle disables restore (leaves dictated text on the clipboard).
- **Feedback**: menu-bar icon has an idle and a recording state; a subtle start sound and stop sound play on the loop transitions. No floating overlay in v1.
- **Configuration**: activation key, activation mode (push-to-talk | toggle), and clipboard-restore (on | off) persisted (e.g. `UserDefaults`). Reconfigurable; defaults are Right Option / push-to-talk / restore-on.
- **Permissions & first run**: app needs Microphone (TCC) and Accessibility (for the event tap and synthesized ⌘V). A minimal guided first-run window requests Microphone, then deep-links the user to the Accessibility pane with an "Open" button. The app detects missing permissions at runtime and surfaces a clear message rather than failing silently.
- **Latency target**: ~1s warm release→text is acceptable for v1. Core ML / ANE encoder is the lever to go sub-second later; not built in v1.

## Testing Decisions

- **What a good test is here**: it asserts the *external behavior* of the dictation loop, not implementation details. Tests drive `DictationController` through its states with fake `HotkeySource`, `AudioSource`, `TranscriptionEngine`, and `TextInjector`, and assert what the controller *did* (started capture, called transcribe with the captured audio, injected the returned text, restored or left the clipboard per config, emitted the right feedback/error signals).
- **Modules tested (automated)**: `DictationController` (the seam) is the focus. Pure units — the config model and any clipboard save/restore decision logic — can be tested directly where they hold real logic.
- **Representative controller tests**: push-to-talk key-down starts capture and key-up triggers transcribe+inject; toggle mode starts on first tap and stops on second; a fake engine returning text results in an inject call with that text; restore-on vs restore-off produces the right final clipboard state via the fake injector; an empty capture yields a "no audio" outcome and no inject; a throwing engine yields a visible-error outcome and no inject; launch performs a warm-up transcription.
- **Not automated (manual smoke, already validated in the prototype)**: the real `AVAudioEngine` capture, the real whisper transcription latency/accuracy, the real `CGEvent` ⌘V injection into third-party apps, and the real `CGEventTap` hotkey — these need a mic, a GUI, and granted permissions. `prototype/` holds the runnable checks; keep them as the manual verification for the OS adapters.
- **Prior art**: none in this repo (greenfield). Establish the controller-with-fakes pattern as the convention for this codebase.

## Out of Scope

- iPhone / iOS anything (separate build; keyboard extensions can't record mic — companion-app pattern required).
- Custom vocabulary / accuracy-feedback layer (v2; local whisper `initial_prompt` keeps the seam open).
- Streaming / partial transcription while holding (v2).
- A floating on-screen recording indicator (v2).
- A cloud transcription engine (the `TranscriptionEngine` seam is built for it, but no impl in v1).
- Notarization, signing for distribution, auto-update.
- Core ML / ANE encoder optimization (lever for later if ~1s isn't fast enough).
- Any analytics, history, or "insights" features.

## Further Notes

- Prototype-validated facts carried into build: warm-up hides the ~18s first-run Metal compile; the `AVAudioFile` header must be finalized before transcription reads it; ~1s warm latency is encode-bound (~850ms fixed floor up to whisper's 30s window).
- Bare spacebar was ruled out as an activation key — it's a real character globally and can't be trapped without breaking space typing. Right Option (a key that types nothing alone) gives the "hold one key" feel safely.
