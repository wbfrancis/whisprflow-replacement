#!/usr/bin/env bash
# PROTOTYPE — throwaway. Installs whisper.cpp and the quantized large-v3-turbo model
# used by the latency spike. Safe to delete this whole prototype/ dir afterward.
set -euo pipefail

MODEL_DIR="$(cd "$(dirname "$0")" && pwd)/models"
MODEL_FILE="$MODEL_DIR/ggml-large-v3-turbo-q5_0.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"

echo "==> Installing whisper-cpp via Homebrew (idempotent)"
if ! brew list whisper-cpp >/dev/null 2>&1; then
  brew install whisper-cpp
else
  echo "    whisper-cpp already installed"
fi

echo "==> whisper-cli location:"
command -v whisper-cli || echo "    (whisper-cli not on PATH — check brew output)"

mkdir -p "$MODEL_DIR"
if [ -f "$MODEL_FILE" ]; then
  echo "==> Model already present: $MODEL_FILE"
else
  echo "==> Downloading large-v3-turbo q5_0 (~547MB) to $MODEL_FILE"
  curl -L --fail --progress-bar -o "$MODEL_FILE.partial" "$MODEL_URL"
  mv "$MODEL_FILE.partial" "$MODEL_FILE"
fi

echo "==> Model size:"
ls -lh "$MODEL_FILE"
echo "==> Setup done."
