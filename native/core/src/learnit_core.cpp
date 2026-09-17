#include "learnit_core.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
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

#if defined(LEARNIT_WITH_WHISPER)
#include "whisper_adapter.h"
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

struct TranscriptionJob {
  std::atomic<bool> cancel_requested{false};
  std::mutex mutex;
  bool finished = false;
  std::string result;
  std::thread worker;
};

}  // namespace

struct learnit_core_session {
  explicit learnit_core_session(const char *model_path, int32_t threads)
      : model_path(model_path == nullptr ? "" : model_path),
        whisper_threads(std::clamp<int32_t>(threads, 1, 8)) {}

  std::string model_path;
  int32_t whisper_threads;

  mutable std::mutex model_mutex;
  std::mutex inference_mutex;
#if defined(LEARNIT_WITH_WHISPER)
  std::unique_ptr<LearnItWhisperAdapter> whisper;
#endif

  mutable std::mutex error_mutex;
  std::string last_error;

  std::mutex jobs_mutex;
  std::unordered_map<learnit_core_job_id_t, std::shared_ptr<TranscriptionJob>>
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
    if (session->model_path.empty()) {
      return nullptr;
    }
    session->whisper = std::make_unique<LearnItWhisperAdapter>(
        session->model_path, session->whisper_threads);
  }
  return session->whisper.get();
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

void complete_job(const std::shared_ptr<TranscriptionJob> &job,
                  std::string result) {
  std::lock_guard<std::mutex> lock(job->mutex);
  job->result = std::move(result);
  job->finished = true;
}

}  // namespace

extern "C" {

const char *learnit_core_version(void) {
#if defined(LEARNIT_WITH_WHISPER)
  return "learnit-core/0.4.0-whisper";
#else
  return "learnit-core/0.4.0-abi";
#endif
}

const char *learnit_core_capabilities(void) {
#if defined(LEARNIT_WITH_WHISPER)
  return "{\"abi\":2,\"phase\":1,\"runtime\":\"whisper.cpp\",\"components\":[\"dialogue\",\"stt\"],\"whisper_backend\":true,\"models_verified\":false,\"async_transcribe\":true}";
#else
  return "{\"abi\":2,\"phase\":1,\"runtime\":\"native-abi\",\"components\":[\"dialogue\"],\"whisper_backend\":false,\"models_verified\":false,\"async_transcribe\":true}";
#endif
}

char *learnit_demo_reply(const char *input, const char *language) {
  const std::string safe_input = escape_json(input);
  const std::string safe_language = escape_json(language);
  const std::string response =
      "{\"mode\":\"demo\",\"runtime\":\"native-abi\",\"language\":\"" +
      safe_language +
      "\",\"input\":\"" + safe_input +
      "\",\"message\":\"Native ABI ready; configure a verified Whisper model for transcription.\"}";
  return copy_string(response);
}

learnit_core_session_t *learnit_core_session_create(
    const char *whisper_model_path,
    int32_t whisper_threads) {
  try {
    return new learnit_core_session(whisper_model_path, whisper_threads);
  } catch (...) {
    return nullptr;
  }
}

void learnit_core_session_destroy(learnit_core_session_t *session) {
  if (session == nullptr) {
    return;
  }
  std::vector<std::shared_ptr<TranscriptionJob>> jobs;
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
#if !defined(LEARNIT_WITH_WHISPER)
  const std::string message =
      "La biblioteca fue compilada sin el backend whisper.cpp.";
  set_last_error(session, "whisper_backend_unavailable", message);
  return 0;
#else
  try {
    LearnItWhisperAdapter *adapter = ensure_whisper_adapter(session);
    if (adapter == nullptr) {
      const std::string message =
          "La sesión no tiene una ruta local de modelo Whisper.";
      set_last_error(session, "model_path_missing", message);
      return 0;
    }
    if (!adapter->ready()) {
      set_last_error(session, adapter->error_code(), adapter->error_message());
      return 0;
    }
    return 1;
  } catch (...) {
    const std::string message = "No hay memoria suficiente para cargar Whisper.";
    set_last_error(session, "allocation_failed", message);
    return 0;
  }
#endif
}

int32_t learnit_core_session_is_ready(
    const learnit_core_session_t *session) {
  if (session == nullptr) {
    return 0;
  }
#if !defined(LEARNIT_WITH_WHISPER)
  return 0;
#else
  std::lock_guard<std::mutex> lock(session->model_mutex);
  return session->whisper != nullptr && session->whisper->ready() ? 1 : 0;
#endif
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
    auto audio = std::make_shared<std::vector<int16_t>>(samples,
                                                         samples + sample_count);
    auto job = std::make_shared<TranscriptionJob>();
    const learnit_core_job_id_t job_id =
        session->next_job_id.fetch_add(1, std::memory_order_relaxed);
    {
      std::lock_guard<std::mutex> lock(session->jobs_mutex);
      session->jobs.emplace(job_id, job);
    }
    const std::string hint = language_hint == nullptr ? "" : language_hint;
    try {
      job->worker = std::thread(
          [session, job, audio, hint]() {
            std::string result;
            try {
              result = transcribe_json(session, *audio, 16000, hint.c_str(),
                                       &job->cancel_requested);
            } catch (...) {
              const std::string message =
                  "La transcripción nativa no pudo reservar memoria.";
              set_last_error(session, "allocation_failed", message);
              result = error_response("allocation_failed", message);
            }
            complete_job(job, result);
          });
    } catch (...) {
      std::lock_guard<std::mutex> lock(session->jobs_mutex);
      session->jobs.erase(job_id);
      throw;
    }
    return job_id;
  } catch (...) {
    set_last_error(session, "allocation_failed",
                   "No hay memoria o hilos disponibles para transcribir.");
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

  std::shared_ptr<TranscriptionJob> job;
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
