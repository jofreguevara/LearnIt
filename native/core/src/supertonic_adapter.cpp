#include "supertonic_adapter.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <mutex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "helper.h"

namespace {

std::string normalize_language(const char *language) {
  if (language != nullptr && std::string(language) == "es") {
    return "es";
  }
  return "en";
}

void append_u16_le(std::vector<uint8_t> *bytes, uint16_t value) {
  bytes->push_back(static_cast<uint8_t>(value & 0xffU));
  bytes->push_back(static_cast<uint8_t>((value >> 8) & 0xffU));
}

void append_u32_le(std::vector<uint8_t> *bytes, uint32_t value) {
  bytes->push_back(static_cast<uint8_t>(value & 0xffU));
  bytes->push_back(static_cast<uint8_t>((value >> 8) & 0xffU));
  bytes->push_back(static_cast<uint8_t>((value >> 16) & 0xffU));
  bytes->push_back(static_cast<uint8_t>((value >> 24) & 0xffU));
}

std::vector<uint8_t> encode_wav(const std::vector<float> &samples,
                                int32_t sample_rate) {
  const size_t max_data_bytes =
      static_cast<size_t>(std::numeric_limits<uint32_t>::max()) - 36U;
  if (samples.size() > max_data_bytes / 2U) {
    throw std::runtime_error("El audio Supertonic excede el tamaño WAV permitido.");
  }
  const uint32_t data_size = static_cast<uint32_t>(samples.size() * 2U);
  std::vector<uint8_t> wav;
  wav.reserve(static_cast<size_t>(data_size) + 44U);
  wav.insert(wav.end(), {'R', 'I', 'F', 'F'});
  append_u32_le(&wav, 36U + data_size);
  wav.insert(wav.end(), {'W', 'A', 'V', 'E'});
  wav.insert(wav.end(), {'f', 'm', 't', ' '});
  append_u32_le(&wav, 16U);
  append_u16_le(&wav, 1U);
  append_u16_le(&wav, 1U);
  append_u32_le(&wav, static_cast<uint32_t>(sample_rate));
  append_u32_le(&wav, static_cast<uint32_t>(sample_rate * 2));
  append_u16_le(&wav, 2U);
  append_u16_le(&wav, 16U);
  wav.insert(wav.end(), {'d', 'a', 't', 'a'});
  append_u32_le(&wav, data_size);
  for (const float value : samples) {
    const float safe_value =
        std::isfinite(value) ? std::clamp(value, -1.0f, 1.0f) : 0.0f;
    const auto pcm = static_cast<int16_t>(std::lround(safe_value * 32767.0f));
    append_u16_le(&wav, static_cast<uint16_t>(pcm));
  }
  return wav;
}

}  // namespace

struct LearnItSupertonicAdapter::Impl {
  Impl() : env(ORT_LOGGING_LEVEL_WARNING, "LearnItSupertonic") {}

  Ort::Env env;
  Ort::SessionOptions options;
  Config config{};
  OnnxModels models;
  std::unique_ptr<UnicodeProcessor> text_processor;
  std::unique_ptr<Style> style;
  std::unique_ptr<TextToSpeech> tts;
};

LearnItSupertonicAdapter::LearnItSupertonicAdapter(
    std::string model_dir,
    std::string voice_style_path,
    int32_t threads)
    : model_dir_(std::move(model_dir)),
      voice_style_path_(std::move(voice_style_path)),
      threads_(std::clamp<int32_t>(threads, 1, 8)),
      impl_(std::make_unique<Impl>()) {
  if (model_dir_.empty()) {
    error_code_ = "tts_model_path_missing";
    error_message_ = "No se indicó el directorio de modelos Supertonic.";
    return;
  }
  if (!std::filesystem::is_directory(model_dir_)) {
    error_code_ = "tts_model_path_missing";
    error_message_ = "El directorio de modelos Supertonic no existe.";
    return;
  }
  if (voice_style_path_.empty() ||
      !std::filesystem::is_regular_file(voice_style_path_)) {
    error_code_ = "tts_voice_missing";
    error_message_ = "No se encontró el estilo de voz Supertonic.";
    return;
  }

  try {
    impl_->options.SetIntraOpNumThreads(threads_);
    impl_->options.SetInterOpNumThreads(1);
    impl_->options.SetGraphOptimizationLevel(
        GraphOptimizationLevel::ORT_ENABLE_ALL);
    impl_->config = loadCfgs(model_dir_);
    impl_->models = loadOnnxAll(impl_->env, model_dir_, impl_->options);
    impl_->text_processor = loadTextProcessor(model_dir_);
    impl_->style = std::make_unique<Style>(
        loadVoiceStyle({voice_style_path_}, false));
    impl_->tts = std::make_unique<TextToSpeech>(
        impl_->config, impl_->text_processor.get(), impl_->models.dp.get(),
        impl_->models.text_enc.get(), impl_->models.vector_est.get(),
        impl_->models.vocoder.get());
  } catch (const std::exception &error) {
    error_code_ = "tts_model_load_failed";
    error_message_ = error.what();
    impl_->tts.reset();
  }
}

LearnItSupertonicAdapter::~LearnItSupertonicAdapter() = default;

bool LearnItSupertonicAdapter::ready() const {
  return impl_ != nullptr && impl_->tts != nullptr && impl_->style != nullptr;
}

const std::string &LearnItSupertonicAdapter::error_code() const {
  return error_code_;
}

const std::string &LearnItSupertonicAdapter::error_message() const {
  return error_message_;
}

bool LearnItSupertonicAdapter::synthesize(
    const std::string &text,
    const char *language,
    const char *voice_style_id,
    float speaking_rate,
    const std::atomic<bool> &cancel_requested,
    LearnItSupertonicResult *result,
    std::string *error_code,
    std::string *error_message) {
  if (result == nullptr || error_code == nullptr || error_message == nullptr) {
    return false;
  }
  if (!ready()) {
    *error_code = error_code_.empty() ? "tts_model_not_loaded" : error_code_;
    *error_message = error_message_.empty()
                         ? "El modelo Supertonic no está disponible."
                         : error_message_;
    return false;
  }
  if (text.find_first_not_of(" \t\r\n") == std::string::npos) {
    *error_code = "empty_text";
    *error_message = "No se recibió texto para sintetizar.";
    return false;
  }
  if (voice_style_id != nullptr && voice_style_id[0] != '\0' &&
      std::string(voice_style_id) != "M1") {
    *error_code = "voice_style_unavailable";
    *error_message =
        "La integración actual solo incluye el estilo de voz verificado M1.";
    return false;
  }
  if (cancel_requested.load(std::memory_order_relaxed)) {
    *error_code = "cancelled";
    *error_message = "La síntesis fue cancelada.";
    return false;
  }

  std::lock_guard<std::mutex> lock(inference_mutex_);
  try {
    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(
        OrtAllocatorType::OrtArenaAllocator, OrtMemType::OrtMemTypeDefault);
    const float safe_speed =
        std::clamp(std::isfinite(speaking_rate) ? speaking_rate : 1.0f, 0.5f,
                   2.0f);
    const auto synthesis = impl_->tts->call(
        memory_info, text, normalize_language(language), *impl_->style, 8,
        safe_speed);
    if (cancel_requested.load(std::memory_order_relaxed)) {
      *error_code = "cancelled";
      *error_message = "La síntesis fue cancelada.";
      return false;
    }
    if (synthesis.wav.empty()) {
      *error_code = "empty_audio";
      *error_message = "Supertonic no produjo audio.";
      return false;
    }
    result->sample_rate = impl_->tts->getSampleRate();
    result->duration_ms = synthesis.duration.empty()
                              ? 0
                              : static_cast<int32_t>(std::lround(
                                    synthesis.duration.front() * 1000.0f));
    result->wav = encode_wav(synthesis.wav, result->sample_rate);
    return true;
  } catch (const std::exception &error) {
    *error_code = "tts_inference_failed";
    *error_message = error.what();
    return false;
  }
}
