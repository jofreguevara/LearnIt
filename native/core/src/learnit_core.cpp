#include "learnit_core.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <iomanip>
#include <limits>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

#if defined(LEARNIT_WITH_LLAMA)
#include "llama_adapter.h"
#endif
#if defined(LEARNIT_WITH_WHISPER)
#include "whisper_adapter.h"
#endif
#if defined(LEARNIT_WITH_SUPERTONIC)
#include "supertonic_adapter.h"
#endif

namespace {

std::string escape_json(const char *value) {
  std::string escaped;
  if (value == nullptr) {
    return escaped;
  }
  for (const unsigned char *cursor =
           reinterpret_cast<const unsigned char *>(value);
       *cursor != '\0'; ++cursor) {
    switch (*cursor) {
      case '\\':
        escaped += "\\\\";
        break;
      case '"':
        escaped += "\\\"";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        if (*cursor < 0x20) {
          static constexpr char hex[] = "0123456789abcdef";
          escaped += "\\u00";
          escaped += hex[*cursor >> 4];
          escaped += hex[*cursor & 0x0f];
        } else {
          escaped += static_cast<char>(*cursor);
        }
    }
  }
  return escaped;
}

std::string escape_json(const std::string &value) {
  return escape_json(value.c_str());
}

char *copy_string(const std::string &value) {
  auto *result = static_cast<char *>(std::malloc(value.size() + 1));
  if (result == nullptr) {
    return nullptr;
  }
  std::memcpy(result, value.c_str(), value.size() + 1);
  return result;
}

std::string error_response(const std::string &code,
                           const std::string &message) {
  return "{\"ok\":false,\"error\":{\"code\":\"" +
         escape_json(code) + "\",\"message\":\"" +
         escape_json(message) + "\"}}";
}

#if defined(LEARNIT_WITH_WHISPER)
std::string confidence_string(float confidence) {
  std::ostringstream stream;
  stream << std::fixed << std::setprecision(4) << confidence;
  return stream.str();
}
#endif

#if defined(LEARNIT_WITH_SUPERTONIC)
std::string base64_encode(const std::vector<uint8_t> &bytes) {
  static constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string encoded;
  encoded.reserve((bytes.size() + 2U) / 3U * 4U);
  for (size_t index = 0; index < bytes.size(); index += 3U) {
    const uint32_t first = bytes[index];
    const uint32_t second = index + 1U < bytes.size() ? bytes[index + 1U] : 0U;
    const uint32_t third = index + 2U < bytes.size() ? bytes[index + 2U] : 0U;
    const uint32_t block = (first << 16U) | (second << 8U) | third;
    encoded.push_back(alphabet[(block >> 18U) & 0x3fU]);
    encoded.push_back(alphabet[(block >> 12U) & 0x3fU]);
    encoded.push_back(index + 1U < bytes.size()
                          ? alphabet[(block >> 6U) & 0x3fU]
                          : '=');
    encoded.push_back(index + 2U < bytes.size() ? alphabet[block & 0x3fU]
                                                 : '=');
  }
  return encoded;
}
#endif

struct NativeJob {
  std::atomic<bool> cancel_requested{false};
  std::mutex mutex;
  bool finished = false;
  std::string result;
  std::thread worker;
};

}  // namespace

struct learnit_core_session {
  explicit learnit_core_session(const char *whisper_path,
                                const char *dialogue_path,
                                const char *tts_dir,
                                const char *tts_voice_path,
                                int32_t threads)
      : whisper_model_path(whisper_path == nullptr ? "" : whisper_path),
        dialogue_model_path(dialogue_path == nullptr ? "" : dialogue_path),
        supertonic_model_dir(tts_dir == nullptr ? "" : tts_dir),
        supertonic_voice_style_path(tts_voice_path == nullptr ? ""
                                                               : tts_voice_path),
        runtime_threads(std::clamp<int32_t>(threads, 1, 8)) {}

  std::string whisper_model_path;
  std::string dialogue_model_path;
  std::string supertonic_model_dir;
  std::string supertonic_voice_style_path;
  int32_t runtime_threads;

  mutable std::mutex model_mutex;
  std::mutex inference_mutex;
#if defined(LEARNIT_WITH_LLAMA)
  std::unique_ptr<LearnItLlamaAdapter> llama;
#endif
#if defined(LEARNIT_WITH_WHISPER)
  std::unique_ptr<LearnItWhisperAdapter> whisper;
#endif
#if defined(LEARNIT_WITH_SUPERTONIC)
  std::unique_ptr<LearnItSupertonicAdapter> supertonic;
#endif

  mutable std::mutex error_mutex;
  std::string last_error;

  std::mutex jobs_mutex;
  std::unordered_map<learnit_core_job_id_t, std::shared_ptr<NativeJob>>
      jobs;
  std::atomic<learnit_core_job_id_t> next_job_id{1};
};

namespace {

void set_last_error(learnit_core_session_t *session,
                    const std::string &code,
                    const std::string &message) {
  if (session == nullptr) {
    return;
  }
  std::lock_guard<std::mutex> lock(session->error_mutex);
  session->last_error = code + ": " + message;
}

#if defined(LEARNIT_WITH_WHISPER)
LearnItWhisperAdapter *ensure_whisper_adapter(
    learnit_core_session_t *session) {
  std::lock_guard<std::mutex> lock(session->model_mutex);
  if (!session->whisper) {
    if (session->whisper_model_path.empty()) {
      return nullptr;
    }
    session->whisper = std::make_unique<LearnItWhisperAdapter>(
        session->whisper_model_path, session->runtime_threads);
  }
  return session->whisper.get();
}
#endif

#if defined(LEARNIT_WITH_LLAMA)
LearnItLlamaAdapter *ensure_llama_adapter(learnit_core_session_t *session) {
  std::lock_guard<std::mutex> lock(session->model_mutex);
  if (!session->llama) {
    if (session->dialogue_model_path.empty()) {
      return nullptr;
    }
    session->llama = std::make_unique<LearnItLlamaAdapter>(
        session->dialogue_model_path, session->runtime_threads);
  }
  return session->llama.get();
}
#endif

#if defined(LEARNIT_WITH_SUPERTONIC)
LearnItSupertonicAdapter *ensure_supertonic_adapter(
    learnit_core_session_t *session) {
  std::lock_guard<std::mutex> lock(session->model_mutex);
  if (!session->supertonic) {
    if (session->supertonic_model_dir.empty() ||
        session->supertonic_voice_style_path.empty()) {
      return nullptr;
    }
    session->supertonic = std::make_unique<LearnItSupertonicAdapter>(
        session->supertonic_model_dir, session->supertonic_voice_style_path,
        session->runtime_threads);
  }
  return session->supertonic.get();
}
#endif

std::string transcribe_json(learnit_core_session_t *session,
                            const std::vector<int16_t> &samples,
                            int32_t sample_rate,
                            const char *language_hint,
                            const std::atomic<bool> *cancel_requested) {
  if (session == nullptr) {
    return error_response("invalid_session", "La sesión nativa no es válida.");
  }
  if (samples.empty()) {
    const std::string message = "No se recibió audio para transcribir.";
    set_last_error(session, "empty_audio", message);
    return error_response("empty_audio", message);
  }
  if (sample_rate != 16000) {
    const std::string message =
        "La transcripción requiere audio PCM16 mono a 16 kHz.";
    set_last_error(session, "unsupported_sample_rate", message);
    return error_response("unsupported_sample_rate", message);
  }
  if (cancel_requested != nullptr &&
      cancel_requested->load(std::memory_order_relaxed)) {
    const std::string message = "La transcripción fue cancelada.";
    set_last_error(session, "cancelled", message);
    return error_response("cancelled", message);
  }

#if !defined(LEARNIT_WITH_WHISPER)
  (void)language_hint;
  const std::string message =
      "La biblioteca fue compilada sin el backend whisper.cpp.";
  set_last_error(session, "whisper_backend_unavailable", message);
  return error_response("whisper_backend_unavailable", message);
#else
  LearnItWhisperAdapter *adapter = ensure_whisper_adapter(session);
  if (adapter == nullptr) {
    const std::string message =
        "La sesión no tiene una ruta local de modelo Whisper.";
    set_last_error(session, "model_path_missing", message);
    return error_response("model_path_missing", message);
  }
  if (!adapter->ready()) {
    set_last_error(session, adapter->error_code(), adapter->error_message());
    return error_response(adapter->error_code(), adapter->error_message());
  }

  static const std::atomic<bool> never_cancelled{false};
  const std::atomic<bool> &cancel =
      cancel_requested == nullptr ? never_cancelled : *cancel_requested;
  LearnItWhisperResult result;
  std::string error_code;
  std::string error_message;
  {
    std::lock_guard<std::mutex> lock(session->inference_mutex);
    if (!adapter->transcribe(samples, language_hint, cancel, &result,
                             &error_code, &error_message)) {
      set_last_error(session, error_code, error_message);
      return error_response(error_code, error_message);
    }
  }
  return "{\"ok\":true,\"type\":\"transcript\",\"text\":\"" +
         escape_json(result.text) + "\",\"language\":\"" +
         escape_json(result.language) + "\",\"confidence\":" +
         confidence_string(result.confidence) + "}";
#endif
}

std::string dialogue_json(learnit_core_session_t *session,
                          const std::string &request_json,
                          const std::atomic<bool> *cancel_requested) {
  if (session == nullptr) {
    return error_response("invalid_session", "La sesión nativa no es válida.");
  }
  if (request_json.find_first_not_of(" \t\r\n") == std::string::npos) {
    set_last_error(session, "empty_request",
                   "No se recibió una solicitud de diálogo.");
    return error_response("empty_request",
                          "No se recibió una solicitud de diálogo.");
  }
  if (cancel_requested != nullptr &&
      cancel_requested->load(std::memory_order_relaxed)) {
    set_last_error(session, "cancelled", "La generación fue cancelada.");
    return error_response("cancelled", "La generación fue cancelada.");
  }

#if !defined(LEARNIT_WITH_LLAMA)
  (void)request_json;
  (void)cancel_requested;
  const std::string message =
      "La biblioteca fue compilada sin el backend llama.cpp.";
  set_last_error(session, "llama_backend_unavailable", message);
  return error_response("llama_backend_unavailable", message);
#else
  LearnItLlamaAdapter *adapter = ensure_llama_adapter(session);
  if (adapter == nullptr) {
    const std::string message =
        "La sesión no tiene una ruta local de modelo GGUF.";
    set_last_error(session, "dialogue_model_path_missing", message);
    return error_response("dialogue_model_path_missing", message);
  }
  if (!adapter->ready()) {
    set_last_error(session, adapter->error_code(), adapter->error_message());
    return error_response(adapter->error_code(), adapter->error_message());
  }

  static const std::atomic<bool> never_cancelled{false};
  const std::atomic<bool> &cancel =
      cancel_requested == nullptr ? never_cancelled : *cancel_requested;
  LearnItLlamaResult result;
  std::string error_code;
  std::string error_message;
  {
    std::lock_guard<std::mutex> lock(session->inference_mutex);
    if (!adapter->generate(request_json, cancel, &result, &error_code,
                           &error_message)) {
      set_last_error(session, error_code, error_message);
      return error_response(error_code, error_message);
    }
  }
  return "{\"ok\":true,\"type\":\"dialogue\",\"language\":\"" +
         escape_json(result.language) + "\",\"text\":\"" +
         escape_json(result.text) + "\"}";
#endif
}

std::string tts_json(learnit_core_session_t *session,
                     const std::string &text,
                     const std::string &language,
                     const std::string &voice_style_id,
                     float speaking_rate,
                     const std::atomic<bool> *cancel_requested) {
  if (session == nullptr) {
    return error_response("invalid_session", "La sesión nativa no es válida.");
  }
  if (text.find_first_not_of(" \t\r\n") == std::string::npos) {
    set_last_error(session, "empty_text", "No se recibió texto para sintetizar.");
    return error_response("empty_text", "No se recibió texto para sintetizar.");
  }
  if (cancel_requested != nullptr &&
      cancel_requested->load(std::memory_order_relaxed)) {
    set_last_error(session, "cancelled", "La síntesis fue cancelada.");
    return error_response("cancelled", "La síntesis fue cancelada.");
  }

#if !defined(LEARNIT_WITH_SUPERTONIC)
  (void)language;
  (void)voice_style_id;
  (void)speaking_rate;
  (void)cancel_requested;
  const std::string message =
      "La biblioteca fue compilada sin el backend Supertonic.";
  set_last_error(session, "supertonic_backend_unavailable", message);
  return error_response("supertonic_backend_unavailable", message);
#else
  LearnItSupertonicAdapter *adapter = ensure_supertonic_adapter(session);
  if (adapter == nullptr) {
    const std::string message =
        "La sesión no tiene rutas locales del bundle Supertonic.";
    set_last_error(session, "tts_model_path_missing", message);
    return error_response("tts_model_path_missing", message);
  }
  if (!adapter->ready()) {
    set_last_error(session, adapter->error_code(), adapter->error_message());
    return error_response(adapter->error_code(), adapter->error_message());
  }

  static const std::atomic<bool> never_cancelled{false};
  const std::atomic<bool> &cancel =
      cancel_requested == nullptr ? never_cancelled : *cancel_requested;
  LearnItSupertonicResult result;
  std::string error_code;
  std::string error_message;
  {
    std::lock_guard<std::mutex> lock(session->inference_mutex);
    if (!adapter->synthesize(text, language.c_str(), voice_style_id.c_str(),
                             speaking_rate, cancel, &result, &error_code,
                             &error_message)) {
      set_last_error(session, error_code, error_message);
      return error_response(error_code, error_message);
    }
  }
  return "{\"ok\":true,\"type\":\"audio\",\"mime_type\":\"audio/wav\",\"sample_rate\":" +
         std::to_string(result.sample_rate) + ",\"duration_ms\":" +
         std::to_string(result.duration_ms) + ",\"audio_base64\":\"" +
         base64_encode(result.wav) + "\"}";
#endif
}

void complete_job(const std::shared_ptr<NativeJob> &job,
                  std::string result) {
  std::lock_guard<std::mutex> lock(job->mutex);
  job->result = std::move(result);
  job->finished = true;
}

using NativeJobTask =
    std::function<std::string(const std::atomic<bool> &cancel_requested)>;

learnit_core_job_id_t start_job(learnit_core_session_t *session,
                                NativeJobTask task) {
  if (session == nullptr) {
    return 0;
  }
  try {
    auto job = std::make_shared<NativeJob>();
    const learnit_core_job_id_t job_id =
        session->next_job_id.fetch_add(1, std::memory_order_relaxed);
    {
      std::lock_guard<std::mutex> lock(session->jobs_mutex);
      session->jobs.emplace(job_id, job);
    }
    try {
      job->worker = std::thread(
          [session, job, task = std::move(task)]() mutable {
            std::string result;
            try {
              result = task(job->cancel_requested);
            } catch (...) {
              const std::string message =
                  "El worker nativo terminó con una excepción inesperada.";
              set_last_error(session, "native_exception", message);
              result = error_response("native_exception", message);
            }
            complete_job(job, std::move(result));
          });
    } catch (...) {
      std::lock_guard<std::mutex> lock(session->jobs_mutex);
      session->jobs.erase(job_id);
      throw;
    }
    return job_id;
  } catch (...) {
    set_last_error(session, "allocation_failed",
                   "No hay memoria o hilos disponibles para inferir.");
    return 0;
  }
}

}  // namespace

extern "C" {

const char *learnit_core_version(void) {
#if defined(LEARNIT_WITH_LLAMA) && defined(LEARNIT_WITH_SUPERTONIC)
  return "learnit-core/0.5.0-native";
#elif defined(LEARNIT_WITH_LLAMA)
  return "learnit-core/0.5.0-llama";
#elif defined(LEARNIT_WITH_SUPERTONIC)
  return "learnit-core/0.5.0-supertonic";
#elif defined(LEARNIT_WITH_WHISPER)
  return "learnit-core/0.5.0-whisper";
#else
  return "learnit-core/0.5.0-abi";
#endif
}

const char *learnit_core_capabilities(void) {
  return "{\"abi\":3,\"phase\":1,\"runtime\":\"learnit-native\","
         "\"components\":[\"dialogue\",\"stt\",\"tts\"],"
#if defined(LEARNIT_WITH_LLAMA)
         "\"llama_backend\":true,\"dialogue_backend\":true,"
#else
         "\"llama_backend\":false,\"dialogue_backend\":false,"
#endif
#if defined(LEARNIT_WITH_WHISPER)
         "\"whisper_backend\":true,"
#else
         "\"whisper_backend\":false,"
#endif
#if defined(LEARNIT_WITH_SUPERTONIC)
         "\"supertonic_backend\":true,\"tts_backend\":true,"
#else
         "\"supertonic_backend\":false,\"tts_backend\":false,"
#endif
         "\"models_verified\":false,\"async_transcribe\":true,"
         "\"async_dialogue\":true,\"async_tts\":true}";
}

char *learnit_demo_reply(const char *input, const char *language) {
  const std::string safe_input = escape_json(input);
  const std::string safe_language = escape_json(language);
  const std::string response =
      "{\"mode\":\"demo\",\"runtime\":\"native-abi\",\"language\":\"" +
      safe_language +
      "\",\"input\":\"" + safe_input +
      "\",\"message\":\"Native ABI ready; configure verified local models for inference.\"}";
  return copy_string(response);
}

learnit_core_session_t *learnit_core_session_create_ex(
    const char *whisper_model_path,
    const char *dialogue_model_path,
    const char *supertonic_model_dir,
    const char *supertonic_voice_style_path,
    int32_t threads) {
  try {
    return new learnit_core_session(whisper_model_path, dialogue_model_path,
                                    supertonic_model_dir,
                                    supertonic_voice_style_path, threads);
  } catch (...) {
    return nullptr;
  }
}

learnit_core_session_t *learnit_core_session_create(
    const char *whisper_model_path,
    int32_t whisper_threads) {
  return learnit_core_session_create_ex(whisper_model_path, nullptr, nullptr,
                                         nullptr, whisper_threads);
}

void learnit_core_session_destroy(learnit_core_session_t *session) {
  if (session == nullptr) {
    return;
  }
  std::vector<std::shared_ptr<NativeJob>> jobs;
  {
    std::lock_guard<std::mutex> lock(session->jobs_mutex);
    jobs.reserve(session->jobs.size());
    for (const auto &entry : session->jobs) {
      entry.second->cancel_requested.store(true, std::memory_order_relaxed);
      jobs.push_back(entry.second);
    }
  }
  for (const auto &job : jobs) {
    if (job->worker.joinable()) {
      job->worker.join();
    }
  }
  delete session;
}

int32_t learnit_core_session_load(learnit_core_session_t *session) {
  if (session == nullptr) {
    return 0;
  }
  bool configured = false;
  try {
#if defined(LEARNIT_WITH_WHISPER)
    if (!session->whisper_model_path.empty()) {
      configured = true;
      auto *adapter = ensure_whisper_adapter(session);
      if (adapter == nullptr || !adapter->ready()) {
        const std::string code =
            adapter == nullptr ? "model_path_missing" : adapter->error_code();
        const std::string message =
            adapter == nullptr
                ? "La sesión no tiene una ruta local de modelo Whisper."
                : adapter->error_message();
        set_last_error(session, code, message);
        return 0;
      }
    }
#endif
#if defined(LEARNIT_WITH_LLAMA)
    if (!session->dialogue_model_path.empty()) {
      configured = true;
      auto *adapter = ensure_llama_adapter(session);
      if (adapter == nullptr || !adapter->ready()) {
        const std::string code =
            adapter == nullptr ? "dialogue_model_path_missing"
                               : adapter->error_code();
        const std::string message =
            adapter == nullptr
                ? "La sesión no tiene una ruta local de modelo GGUF."
                : adapter->error_message();
        set_last_error(session, code, message);
        return 0;
      }
    }
#endif
#if defined(LEARNIT_WITH_SUPERTONIC)
    if (!session->supertonic_model_dir.empty() ||
        !session->supertonic_voice_style_path.empty()) {
      configured = true;
      auto *adapter = ensure_supertonic_adapter(session);
      if (adapter == nullptr || !adapter->ready()) {
        const std::string code =
            adapter == nullptr ? "tts_model_path_missing"
                               : adapter->error_code();
        const std::string message =
            adapter == nullptr
                ? "La sesión no tiene rutas locales del bundle Supertonic."
                : adapter->error_message();
        set_last_error(session, code, message);
        return 0;
      }
    }
#endif
    if (!configured) {
      set_last_error(session, "no_models_configured",
                     "La sesión no tiene modelos locales configurados.");
      return 0;
    }
    return 1;
  } catch (...) {
    set_last_error(session, "allocation_failed",
                   "No hay memoria suficiente para cargar los modelos.");
    return 0;
  }
}

int32_t learnit_core_session_is_ready(
    const learnit_core_session_t *session) {
  if (session == nullptr) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(session->model_mutex);
  bool configured = false;
  bool ready = true;
#if defined(LEARNIT_WITH_WHISPER)
  if (!session->whisper_model_path.empty()) {
    configured = true;
    ready = ready && session->whisper != nullptr && session->whisper->ready();
  }
#endif
#if defined(LEARNIT_WITH_LLAMA)
  if (!session->dialogue_model_path.empty()) {
    configured = true;
    ready = ready && session->llama != nullptr && session->llama->ready();
  }
#endif
#if defined(LEARNIT_WITH_SUPERTONIC)
  if (!session->supertonic_model_dir.empty() ||
      !session->supertonic_voice_style_path.empty()) {
    configured = true;
    ready = ready && session->supertonic != nullptr &&
            session->supertonic->ready();
  }
#endif
  return configured && ready ? 1 : 0;
}

const char *learnit_core_session_last_error(
    const learnit_core_session_t *session) {
  static thread_local std::string error;
  if (session == nullptr) {
    error = "invalid_session: La sesión nativa no es válida.";
    return error.c_str();
  }
  std::lock_guard<std::mutex> lock(session->error_mutex);
  error = session->last_error;
  return error.c_str();
}

char *learnit_core_transcribe(learnit_core_session_t *session,
                              const int16_t *samples,
                              int32_t sample_count,
                              int32_t sample_rate,
                              const char *language_hint) {
  if (session == nullptr) {
    return copy_string(
        error_response("invalid_session", "La sesión nativa no es válida."));
  }
  if (samples == nullptr || sample_count <= 0) {
    const std::string message = "No se recibió audio para transcribir.";
    set_last_error(session, "empty_audio", message);
    return copy_string(error_response("empty_audio", message));
  }
  try {
    const std::vector<int16_t> input(samples, samples + sample_count);
    const std::string result =
        transcribe_json(session, input, sample_rate, language_hint, nullptr);
    return copy_string(result);
  } catch (...) {
    const std::string message = "No hay memoria suficiente para el audio.";
    set_last_error(session, "allocation_failed", message);
    return copy_string(error_response("allocation_failed", message));
  }
}

learnit_core_job_id_t learnit_core_transcribe_start(
    learnit_core_session_t *session,
    const int16_t *samples,
    int32_t sample_count,
    int32_t sample_rate,
    const char *language_hint) {
  if (session == nullptr) {
    return 0;
  }
  if (samples == nullptr || sample_count <= 0) {
    set_last_error(session, "empty_audio", "No se recibió audio para transcribir.");
    return 0;
  }
  if (sample_rate != 16000) {
    set_last_error(session, "unsupported_sample_rate",
                   "La transcripción requiere audio PCM16 mono a 16 kHz.");
    return 0;
  }
  if (static_cast<uint64_t>(sample_count) >
      static_cast<uint64_t>(std::numeric_limits<int>::max())) {
    set_last_error(session, "audio_too_large",
                   "El bloque de audio excede el tamaño permitido.");
    return 0;
  }

  try {
    auto audio = std::make_shared<std::vector<int16_t>>(
        samples, samples + sample_count);
    const std::string hint = language_hint == nullptr ? "" : language_hint;
    return start_job(
        session, [session, audio, hint](const std::atomic<bool> &cancel) {
          return transcribe_json(session, *audio, 16000, hint.c_str(), &cancel);
        });
  } catch (...) {
    set_last_error(session, "allocation_failed",
                   "No hay memoria o hilos disponibles para transcribir.");
    return 0;
  }
}

learnit_core_job_id_t learnit_core_dialogue_start(
    learnit_core_session_t *session,
    const char *request_json) {
  if (session == nullptr) {
    return 0;
  }
  if (request_json == nullptr ||
      std::string(request_json).find_first_not_of(" \t\r\n") ==
          std::string::npos) {
    set_last_error(session, "empty_request",
                   "No se recibió una solicitud de diálogo.");
    return 0;
  }
  try {
    const std::string request(request_json);
    return start_job(
        session, [session, request](const std::atomic<bool> &cancel) {
          return dialogue_json(session, request, &cancel);
        });
  } catch (...) {
    set_last_error(session, "allocation_failed",
                   "No hay memoria o hilos disponibles para dialogar.");
    return 0;
  }
}

learnit_core_job_id_t learnit_core_tts_start(
    learnit_core_session_t *session,
    const char *text,
    const char *language,
    const char *voice_style_id,
    float speaking_rate) {
  if (session == nullptr) {
    return 0;
  }
  const std::string text_value = text == nullptr ? "" : text;
  if (text_value.find_first_not_of(" \t\r\n") == std::string::npos) {
    set_last_error(session, "empty_text", "No se recibió texto para sintetizar.");
    return 0;
  }
  try {
    const std::string language_value = language == nullptr ? "en" : language;
    const std::string voice_value =
        voice_style_id == nullptr ? "M1" : voice_style_id;
    return start_job(
        session,
        [session, text_value, language_value, voice_value,
         speaking_rate](const std::atomic<bool> &cancel) {
          return tts_json(session, text_value, language_value, voice_value,
                          speaking_rate, &cancel);
        });
  } catch (...) {
    set_last_error(session, "allocation_failed",
                   "No hay memoria o hilos disponibles para sintetizar.");
    return 0;
  }
}

char *learnit_core_job_poll(learnit_core_session_t *session,
                            learnit_core_job_id_t job_id) {
  if (session == nullptr) {
    return copy_string(
        error_response("invalid_session", "La sesión nativa no es válida."));
  }
  if (job_id == 0) {
    return copy_string(
        error_response("invalid_job", "El identificador del trabajo no es válido."));
  }

  std::shared_ptr<NativeJob> job;
  std::string result;
  {
    std::lock_guard<std::mutex> jobs_lock(session->jobs_mutex);
    const auto found = session->jobs.find(job_id);
    if (found == session->jobs.end()) {
      return copy_string(
          error_response("job_not_found", "El trabajo nativo ya no existe."));
    }
    job = found->second;
    std::lock_guard<std::mutex> job_lock(job->mutex);
    if (!job->finished) {
      return nullptr;
    }
    result = job->result;
    session->jobs.erase(found);
  }
  if (job->worker.joinable()) {
    job->worker.join();
  }
  return copy_string(result);
}

int32_t learnit_core_job_cancel(learnit_core_session_t *session,
                                learnit_core_job_id_t job_id) {
  if (session == nullptr || job_id == 0) {
    return 0;
  }
  std::lock_guard<std::mutex> lock(session->jobs_mutex);
  const auto found = session->jobs.find(job_id);
  if (found == session->jobs.end()) {
    return 0;
  }
  found->second->cancel_requested.store(true, std::memory_order_relaxed);
  return 1;
}

void learnit_core_session_cancel(learnit_core_session_t *session) {
  if (session == nullptr) {
    return;
  }
  std::lock_guard<std::mutex> lock(session->jobs_mutex);
  for (const auto &entry : session->jobs) {
    entry.second->cancel_requested.store(true, std::memory_order_relaxed);
  }
}

void learnit_free_string(char *value) { std::free(value); }

}  // extern "C"
