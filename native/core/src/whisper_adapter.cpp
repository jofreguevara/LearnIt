#include "whisper_adapter.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <limits>
#include <memory>
#include <mutex>
#include <utility>

#include "whisper.h"

namespace {

std::string normalize_language_hint(const char *language_hint) {
  if (language_hint == nullptr || language_hint[0] == '\0' ||
      std::string(language_hint) == "auto") {
    return "auto";
  }
  const std::string value(language_hint);
  if (value == "en" || value == "es") {
    return value;
  }
  return "auto";
}

}  // namespace

LearnItWhisperAdapter::LearnItWhisperAdapter(std::string model_path,
                                             int32_t threads)
    : model_path_(std::move(model_path)),
      threads_(std::clamp<int32_t>(threads, 1, 8)) {
  std::ifstream model(model_path_, std::ios::binary);
  if (!model.good()) {
    error_code_ = "model_file_missing";
    error_message_ = "No se pudo abrir el modelo Whisper local.";
    return;
  }

  auto context_params = whisper_context_default_params();
  context_params.use_gpu = false;
  context_ = whisper_init_from_file_with_params(model_path_.c_str(),
                                                context_params);
  if (context_ == nullptr) {
    error_code_ = "model_load_failed";
    error_message_ = "whisper.cpp no pudo cargar el modelo indicado.";
  }
}

LearnItWhisperAdapter::~LearnItWhisperAdapter() {
  if (context_ != nullptr) {
    whisper_free(context_);
    context_ = nullptr;
  }
}

bool LearnItWhisperAdapter::ready() const { return context_ != nullptr; }

const std::string &LearnItWhisperAdapter::error_code() const {
  return error_code_;
}

const std::string &LearnItWhisperAdapter::error_message() const {
  return error_message_;
}

bool LearnItWhisperAdapter::abort_callback(void *user_data) {
  if (user_data == nullptr) {
    return false;
  }
  const auto *cancel_requested =
      static_cast<const std::atomic<bool> *>(user_data);
  return cancel_requested->load(std::memory_order_relaxed);
}

bool LearnItWhisperAdapter::transcribe(
    const std::vector<int16_t> &samples,
    const char *language_hint,
    const std::atomic<bool> &cancel_requested,
    LearnItWhisperResult *result,
    std::string *error_code,
    std::string *error_message) {
  if (result == nullptr || error_code == nullptr || error_message == nullptr) {
    return false;
  }
  if (!ready()) {
    *error_code = error_code_.empty() ? "model_not_loaded" : error_code_;
    *error_message = error_message_.empty()
                         ? "El modelo Whisper no está disponible."
                         : error_message_;
    return false;
  }
  if (samples.empty()) {
    *error_code = "empty_audio";
    *error_message = "No se recibió audio para transcribir.";
    return false;
  }
  if (samples.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    *error_code = "audio_too_large";
    *error_message = "El bloque de audio excede el tamaño permitido.";
    return false;
  }
  if (cancel_requested.load(std::memory_order_relaxed)) {
    *error_code = "cancelled";
    *error_message = "La transcripción fue cancelada.";
    return false;
  }

  std::lock_guard<std::mutex> lock(inference_mutex_);
  std::vector<float> pcmf32(samples.size());
  std::transform(samples.begin(), samples.end(), pcmf32.begin(),
                 [](int16_t sample) {
                   return static_cast<float>(sample) / 32768.0f;
                 });

  const std::string language = normalize_language_hint(language_hint);
  auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.n_threads = threads_;
  params.translate = false;
  params.no_context = true;
  params.no_timestamps = true;
  params.single_segment = false;
  params.print_special = false;
  params.print_progress = false;
  params.print_realtime = false;
  params.print_timestamps = false;
  params.language = language.c_str();
  // "auto" asks whisper.cpp to detect and then continue transcription.
  // Setting detect_language=true would intentionally stop after detection.
  params.detect_language = false;
  params.abort_callback = &LearnItWhisperAdapter::abort_callback;
  params.abort_callback_user_data =
      const_cast<std::atomic<bool> *>(&cancel_requested);

  const int status = whisper_full(context_, params, pcmf32.data(),
                                  static_cast<int>(pcmf32.size()));
  if (status != 0) {
    if (cancel_requested.load(std::memory_order_relaxed)) {
      *error_code = "cancelled";
      *error_message = "La transcripción fue cancelada.";
    } else {
      *error_code = "inference_failed";
      *error_message = "whisper.cpp no pudo transcribir el audio.";
    }
    return false;
  }
  if (cancel_requested.load(std::memory_order_relaxed)) {
    *error_code = "cancelled";
    *error_message = "La transcripción fue cancelada.";
    return false;
  }

  std::string text;
  double probability_sum = 0.0;
  int probability_count = 0;
  const int segment_count = whisper_full_n_segments(context_);
  for (int segment_index = 0; segment_index < segment_count;
       ++segment_index) {
    const char *segment_text =
        whisper_full_get_segment_text(context_, segment_index);
    if (segment_text != nullptr) {
      text += segment_text;
    }
    const int token_count =
        whisper_full_n_tokens(context_, segment_index);
    for (int token_index = 0; token_index < token_count; ++token_index) {
      const auto token = whisper_full_get_token_data(
          context_, segment_index, token_index);
      if (std::isfinite(token.p) && token.p >= 0.0f) {
        probability_sum += token.p;
        ++probability_count;
      }
    }
  }

  if (text.find_first_not_of(" \t\r\n") == std::string::npos) {
    *error_code = "no_speech";
    *error_message = "Whisper no detectó habla utilizable en el audio.";
    return false;
  }

  const int language_id = whisper_full_lang_id(context_);
  const char *detected_language = whisper_lang_str(language_id);
  if (detected_language == nullptr || detected_language[0] == '\0') {
    detected_language = language.c_str();
  }
  result->text = text;
  result->language = detected_language;
  result->confidence = probability_count == 0
                           ? 0.0f
                           : static_cast<float>(probability_sum /
                                                probability_count);
  result->confidence = std::clamp(result->confidence, 0.0f, 1.0f);
  return true;
}
