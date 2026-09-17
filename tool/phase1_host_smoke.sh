#!/usr/bin/env bash
set -euo pipefail

project_root="$(git rev-parse --show-toplevel)"
cd "$project_root"

whisper_cli="${PHASE1_WHISPER_CLI:-build/phase1/upstream/whisper.cpp/build-clang/bin/whisper-cli}"
llama_cli="${PHASE1_LLAMA_CLI:-build/phase1/upstream/llama.cpp/build/bin/llama-cli}"
python_bin="${PHASE1_PYTHON_BIN:-/usr/bin/python3}"
python_packages="${PHASE1_PYTHON_PACKAGES:-build/phase1/python-packages}"
supertonic_py="${PHASE1_SUPERTONIC_PY:-build/phase1/upstream/supertonic/py}"
audio_file="${PHASE1_AUDIO:-build/phase1/jfk.wav}"
model_root="build/phase1/models"
output_root="${PHASE1_OUTPUT:-build/phase1/host-smoke}"

if [[ "$python_bin" != /* ]]; then
  python_bin="$project_root/$python_bin"
fi
if [[ "$python_packages" == /* ]]; then
  python_path="$python_packages"
else
  python_path="$project_root/$python_packages"
fi

check_runtime_revision() {
  local repository="$1"
  local expected="$2"
  if [[ ! -d "$repository/.git" || "${PHASE1_ALLOW_UNPINNED_RUNTIME:-false}" == true ]]; then
    return
  fi
  local actual
  actual="$(git -C "$repository" rev-parse HEAD)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Runtime sin fijar: $repository está en $actual; se esperaba $expected" >&2
    echo 'Usa PHASE1_ALLOW_UNPINNED_RUNTIME=true solo para una comparación explícita.' >&2
    exit 1
  fi
}

for executable in "$whisper_cli" "$llama_cli" "$python_bin"; do
  if [[ ! -x "$executable" ]]; then
    echo "Falta el ejecutable: $executable" >&2
    exit 1
  fi
done
if [[ ! -f "$supertonic_py/example_onnx.py" ]]; then
  echo "Falta el ejemplo ONNX de Supertonic: $supertonic_py/example_onnx.py" >&2
  exit 1
fi

check_runtime_revision \
  "${PHASE1_WHISPER_REPO:-build/phase1/upstream/whisper.cpp}" \
  'da54572229bcf64ba367d96c7ef15770376c4280'
check_runtime_revision \
  "${PHASE1_LLAMA_REPO:-build/phase1/upstream/llama.cpp}" \
  'b49650adb31f2e49a0d76113aeb1792134fd8413'
check_runtime_revision \
  "${PHASE1_SUPERTONIC_REPO:-build/phase1/upstream/supertonic}" \
  '1e9799e964ea4c0dad7cde993b65c3c813a7b373'

./tool/validate_phase1_artifacts.sh

if [[ ! -f "$audio_file" ]]; then
  mkdir -p "$(dirname "$audio_file")"
  curl -fL --retry 3 --silent --show-error \
    'https://github.com/ggerganov/whisper.cpp/raw/da54572229bcf64ba367d96c7ef15770376c4280/samples/jfk.wav' \
    -o "$audio_file"
fi

mkdir -p "$output_root/tts"

echo 'Smoke STT: Whisper base q5_1'
/usr/bin/time -f 'stt_elapsed_seconds=%e stt_max_rss_kb=%M' \
  "$whisper_cli" \
  -m "$model_root/ggml-base-q5_1.bin" \
  -f "$audio_file" \
  -l en -nt -np -t 2 -ng

echo 'Smoke LLM: Qwen3.5 0.8B Q4_0'
/usr/bin/time -f 'llm_elapsed_seconds=%e llm_max_rss_kb=%M' \
  "$llama_cli" \
  -m "$model_root/Qwen3.5-0.8B-Q4_0.gguf" \
  -c 4096 -ngl 0 -t 2 -n 48 -st --reasoning off \
  --simple-io --no-display-prompt --no-show-timings --log-disable \
  -p 'You are an English practice companion. Reply in one short sentence to this learner: I go to the park yesterday.'

echo 'Smoke TTS: Supertonic 3, misma voz M1 en EN y ES'
(
  cd "$supertonic_py"
  PYTHONPATH="$python_path" \
    /usr/bin/time -f 'tts_elapsed_seconds=%e tts_max_rss_kb=%M' \
    "$python_bin" example_onnx.py \
    --onnx-dir "$project_root/$model_root/supertonic-3/onnx" \
    --voice-style \
      "$project_root/$model_root/supertonic-3/voice_styles/M1.json" \
      "$project_root/$model_root/supertonic-3/voice_styles/M1.json" \
    --text 'Hello, let us practice English today.' 'Hola, practiquemos inglés hoy.' \
    --lang en es --batch --n-test 1 --total-step 8 \
    --save-dir "$project_root/$output_root/tts"
)

echo "Artefactos de audio: $output_root/tts"
