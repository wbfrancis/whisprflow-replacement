# whisprflow-replacement

A barebones, seamless macOS dictation app (a personal WhisprFlow replacement). Hold a key,
talk, release, get accurate text at the cursor — transcribed locally. See `CONTEXT.md` for
the v1 design and `SPEC.md` for the buildable spec. iPhone is a separate, later build.

## Build & run

Run the app as a signed `.app`, not via `swift run`. The hold-to-talk hotkey is a
CGEvent tap that needs Accessibility, and macOS TCC keys that grant on the code's
signature. A bare `swift build` binary is ad-hoc signed, so its identity changes on
every rebuild and the grant silently drops. The bundle is signed with one stable
self-signed identity, so the grant persists across rebuilds.

```sh
scripts/make-signing-cert.sh   # once per machine: creates the 'whisper-dev' identity
scripts/bundle.sh              # build + sign -> build/whisper.app
open build/whisper.app         # or drag to /Applications
```

First launch prompts for Microphone and Accessibility — enable **whisper** under
Accessibility and it starts working (no relaunch needed). Depends on Homebrew
`whisper-cpp` + `ggml`; the bundle links their dylibs by absolute path, so it is not
signed with the hardened runtime (library validation would reject those dylibs).

## Agent skills

### Issue tracker

Issues and specs are tracked as GitHub issues in `wbfrancis/whisprflow-replacement` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
