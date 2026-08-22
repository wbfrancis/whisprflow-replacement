# Transcription eval fixtures

A corpus of audio clips + expected text, used to tune and regression-test transcription
(silence trim, whisper decoding params) by the numbers instead of by hunch.

## Run it

```sh
swift run eval
```

Each fixture is transcribed through the real engine and scored with word error rate (WER).
The run prints expected vs got per file and a mean, and exits nonzero if the mean is over
the threshold.

## Add your own clips (the iteration loop)

1. Record a clip (any format `AVAudioFile` reads — `.wav`, `.aiff`, `.m4a`, `.caf`) and drop
   it in `audio/`. **Whispered and quiet clips are the most valuable** — they're the cases
   hardest to get right.
2. Add a line to `manifest.json`: `{ "file": "audio/<name>", "expected": "<what you said>" }`.
   `expected` is compared case- and punctuation-insensitively.
3. `swift run eval` and read the scores.

## Tuning knobs (environment)

Sweep these to see WER move without recompiling:

| Var | Default | Meaning |
|-----|---------|---------|
| `TRIM` | `on` | `off` disables silence trimming entirely |
| `TRIM_FLOOR` | `0.0025` | absolute RMS floor (below = silence regardless of peak) |
| `TRIM_FRACTION` | `0.12` | speech if RMS ≥ this fraction of the clip's peak (lever for whispers) |
| `TRIM_PAD_MS` | `300` | audio kept after the last speech, so word tails aren't clipped |
| `THRESHOLD` | `0.2` | mean WER above which the run fails |
| `WHISPER_MODEL` | app's model | path to a specific model file |

Example: `TRIM_FRACTION=0.08 TRIM_PAD_MS=400 swift run eval`

Once a setting wins across the corpus, bake it into `SilenceTrim`'s defaults.

## Note

`say`-generated seed clips aren't real whispers — they only approximate the quiet path.
Replace them with real recordings for meaningful tuning.
