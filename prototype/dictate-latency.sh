#!/usr/bin/env bash
# PROTOTYPE — throwaway. Answers Q1: does transcribe-on-release feel seamless?
# Records your voice, then measures wall-clock time from "stop" to "text ready"
# using local whisper.cpp large-v3-turbo (q5_0). Run it a few times.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="$DIR/models/ggml-large-v3-turbo-q5_0.bin"
WHISPER="/opt/homebrew/bin/whisper-cli"
RAW="$DIR/.rec-raw.wav"
WAV16="$DIR/.rec-16k.wav"
TXT="$DIR/.rec.txt"
LOG="$DIR/.whisper.log"

[ -f "$MODEL" ] || { echo "Model missing — run ./setup.sh first."; exit 1; }
[ -x "$WHISPER" ] || { echo "whisper-cli missing — run ./setup.sh first."; exit 1; }

echo "=== Dictation latency spike ==="
echo "You'll speak a sentence, press Return to stop, and see how long until text appears."
echo

# 1) Record until Return (mirrors push-to-talk release).
swift "$DIR/record.swift" "$RAW"

# 2) The clock starts the instant recording stops — this is the "release" moment.
START=$(python3 -c 'import time;print(int(time.time()*1000))')

# 3) Resample to 16kHz mono (the real app does this in-process; here afconvert, ~ms).
afconvert -f WAVE -d LEI16@16000 -c 1 "$RAW" "$WAV16" >/dev/null 2>&1
CONV=$(python3 -c 'import time;print(int(time.time()*1000))')

# 4) Transcribe locally.
"$WHISPER" -m "$MODEL" -f "$WAV16" -l en -nt > "$TXT" 2> "$LOG"
END=$(python3 -c 'import time;print(int(time.time()*1000))')

LOAD_MS=$(grep 'load time' "$LOG" | grep -oE '[0-9.]+ ms' | grep -oE '[0-9.]+' | head -1 || echo "?")

echo
echo "--- Transcript ---"
sed 's/^[[:space:]]*//' "$TXT"
echo "------------------"
echo "resample:            $((CONV-START)) ms"
echo "transcribe (CLI):    $((END-CONV)) ms   (includes one-time model load)"
echo "  of which model load: ${LOAD_MS} ms   <- the real app pays this ONCE at startup, not per utterance"
echo "TOTAL release->text (CLI, cold): $((END-START)) ms"
echo
echo ">> Warm estimate (what the real app feels) ~= transcribe minus model-load."
echo "(full whisper timing log: $LOG)"
