# Phrases to record

Record each into `fixtures/audio/<filename>` (any format `AVAudioFile` reads: `.m4a`, `.wav`,
`.aiff`, `.caf`). Easiest capture: QuickTime Player → File → New Audio Recording, or your
phone, then drop the file in. Then add its line to `manifest.json` (a ready block is at the
bottom) and run `swift run eval`.

**How to record so results are meaningful:**
- For the **level set (A)**, say the *same* phrase at each level, same mic and distance —
  that isolates loudness as the only variable, which is what tunes `TRIM_FLOOR` /
  `TRIM_FRACTION`.
- For the **tail set (B)**, deliberately hold the key ~1s after your last word, or let the
  last word trail off quietly — that's what stresses the trailing-silence trim.
- Start speaking the instant you'd press the key (don't wait) — that also checks first-word
  capture.

## A. Levels — same phrase, four volumes (tunes the silence threshold)

| filename | say it | expected |
|---|---|---|
| `lvl-whisper.m4a` | whispered | the meeting is at three o'clock tomorrow |
| `lvl-quiet.m4a` | quietly | the meeting is at three o'clock tomorrow |
| `lvl-normal.m4a` | normal voice | the meeting is at three o'clock tomorrow |
| `lvl-loud.m4a` | projected/loud | the meeting is at three o'clock tomorrow |

## B. Tail & trailing-off (tunes `TRIM_PAD_MS`)

| filename | say it | expected |
|---|---|---|
| `tail-trailoff.m4a` | let the last word fade | i think we should probably just wait |
| `tail-quietend.m4a` | last word quiet | send it whenever you get a chance |
| `tail-longhold.m4a` | hold ~1s of silence after "done" | the report is done |

## C. Hallucination triggers (should NOT run on)

| filename | say it | expected |
|---|---|---|
| `hall-count.m4a` | normal | one two three four five six |
| `hall-repeat.m4a` | normal | no no no no |
| `hall-filler.m4a` | normal | um so basically the thing is |
| `hall-oneword.m4a` | normal | okay |

## D. Real dictation (punctuation, names, homophones, jargon)

| filename | say it | expected |
|---|---|---|
| `real-pr.m4a` | normal | let's ship the pull request after review then merge to main |
| `real-email.m4a` | normal | email Sarah about the Q3 budget by Friday |
| `real-error.m4a` | normal | the API returns a 404 when the token expires |
| `real-homophone.m4a` | normal | they're going to leave their notes over there |
| `real-tech.m4a` | normal | refactor the AVAudioEngine tap to be sendable |

## E. Length & pace extremes

| filename | say it | expected |
|---|---|---|
| `len-short.m4a` | normal | cancel that |
| `len-long.m4a` | one breath, run-on | first draft the outline then fill in each section then read it aloud once before you send it |
| `pace-slow.m4a` | with pauses between words | the quick brown fox |

## Notes on expected text

- WER ignores case and punctuation, so write `expected` naturally.
- **Numbers and counting are a known-messy category**: whisper often writes spoken digits
  contiguously (you say "one two three four five six", it writes `123456`). If a number clip
  scores high, check whether it's a real error or just digit vs word formatting before
  tuning — that's a formatting choice, separate from the trim/hallucination work.

## Ready-to-merge manifest block

Append these into `manifest.json` (mind the commas) once the files exist:

```json
{ "file": "audio/lvl-whisper.m4a",     "expected": "the meeting is at three o'clock tomorrow" },
{ "file": "audio/lvl-quiet.m4a",       "expected": "the meeting is at three o'clock tomorrow" },
{ "file": "audio/lvl-normal.m4a",      "expected": "the meeting is at three o'clock tomorrow" },
{ "file": "audio/lvl-loud.m4a",        "expected": "the meeting is at three o'clock tomorrow" },
{ "file": "audio/tail-trailoff.m4a",   "expected": "i think we should probably just wait" },
{ "file": "audio/tail-quietend.m4a",   "expected": "send it whenever you get a chance" },
{ "file": "audio/tail-longhold.m4a",   "expected": "the report is done" },
{ "file": "audio/hall-count.m4a",      "expected": "one two three four five six" },
{ "file": "audio/hall-repeat.m4a",     "expected": "no no no no" },
{ "file": "audio/hall-filler.m4a",     "expected": "um so basically the thing is" },
{ "file": "audio/hall-oneword.m4a",    "expected": "okay" },
{ "file": "audio/real-pr.m4a",         "expected": "let's ship the pull request after review then merge to main" },
{ "file": "audio/real-email.m4a",      "expected": "email Sarah about the Q3 budget by Friday" },
{ "file": "audio/real-error.m4a",      "expected": "the API returns a 404 when the token expires" },
{ "file": "audio/real-homophone.m4a",  "expected": "they're going to leave their notes over there" },
{ "file": "audio/real-tech.m4a",       "expected": "refactor the AVAudioEngine tap to be sendable" },
{ "file": "audio/len-short.m4a",       "expected": "cancel that" },
{ "file": "audio/len-long.m4a",        "expected": "first draft the outline then fill in each section then read it aloud once before you send it" },
{ "file": "audio/pace-slow.m4a",       "expected": "the quick brown fox" }
```
