// Umbrella header: re-export the Homebrew whisper.cpp + ggml C API to Swift.
#include <whisper.h>
#include <ggml-backend.h>   // ggml_backend_load_all_from_path — loads the CPU/Metal plugins
