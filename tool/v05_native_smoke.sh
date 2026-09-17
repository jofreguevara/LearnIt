#!/usr/bin/env bash
set -euo pipefail

project_root="$(git rev-parse --show-toplevel)"
cd "$project_root"

build_root="${V05_NATIVE_BUILD:-build/native-v0.5-all}"
llama_root="${V05_LLAMA_ROOT:-build/phase1/upstream/llama.cpp}"
whisper_root="${V05_WHISPER_ROOT:-build/phase1/upstream/whisper.cpp}"
supertonic_root="${V05_SUPERTONIC_ROOT:-build/phase1/upstream/supertonic}"
onnx_root="${V05_ONNXRUNTIME_ROOT:-build/phase1/onnxruntime-1.23.1}"
llama_model="${V05_LLAMA_MODEL:-build/phase1/models/Qwen3.5-0.8B-Q4_0.gguf}"
tts_dir="${V05_TTS_DIR:-build/phase1/models/supertonic-3/onnx}"
voice_style="${V05_VOICE_STYLE:-build/phase1/models/supertonic-3/voice_styles/M1.json}"

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$project_root" "$1" ;;
  esac
}

check_revision() {
  local repository="$1"
  local expected="$2"
  if [[ -d "$repository/.git" ]]; then
    local actual
    actual="$(git -C "$repository" rev-parse HEAD)"
    if [[ "$actual" != "$expected" ]]; then
      echo "Runtime sin fijar: $repository está en $actual; se esperaba $expected" >&2
      exit 1
    fi
  fi
}

check_revision "$llama_root" 'b49650adb31f2e49a0d76113aeb1792134fd8413'
check_revision "$whisper_root" 'da54572229bcf64ba367d96c7ef15770376c4280'
check_revision "$supertonic_root" '1e9799e964ea4c0dad7cde993b65c3c813a7b373'

cmake -S native/core -B "$build_root" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=ON \
  -DLEARNIT_WITH_LLAMA=ON \
  -DLEARNIT_LLAMA_ROOT="$(absolute_path "$llama_root")" \
  -DLEARNIT_WITH_WHISPER=ON \
  -DLEARNIT_WHISPER_ROOT="$(absolute_path "$whisper_root")" \
  -DLEARNIT_WITH_SUPERTONIC=ON \
  -DLEARNIT_SUPERTONIC_ROOT="$(absolute_path "$supertonic_root")" \
  -DLEARNIT_ONNXRUNTIME_ROOT="$(absolute_path "$onnx_root")"
cmake --build "$build_root" --parallel 2
ctest --test-dir "$build_root" --output-on-failure

onnx_library="$(absolute_path "$onnx_root")/lib"
LD_LIBRARY_PATH="$onnx_library${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$(absolute_path "$build_root")/learnit_native_smoke" \
  --llama "$(absolute_path "$llama_model")" \
  --tts-dir "$(absolute_path "$tts_dir")" \
  --voice "$(absolute_path "$voice_style")"
