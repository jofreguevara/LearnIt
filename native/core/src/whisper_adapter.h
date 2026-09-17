#ifndef LEARNIT_WHISPER_ADAPTER_H
#define LEARNIT_WHISPER_ADAPTER_H

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

struct whisper_context;

struct LearnItWhisperResult {
  std::string text;
  std::string language;
  float confidence = 0.0f;
};

// Thin ownership and parameter adapter around whisper.cpp. Keeping this
// class behind the LearnIt ABI prevents whisper.cpp types from crossing into
// Dart or the platform projects.
class LearnItWhisperAdapter {
 public:
  LearnItWhisperAdapter(std::string model_path, int32_t threads);
  ~LearnItWhisperAdapter();

  LearnItWhisperAdapter(const LearnItWhisperAdapter &) = delete;
  LearnItWhisperAdapter &operator=(const LearnItWhisperAdapter &) = delete;

  bool ready() const;
  const std::string &error_code() const;
  const std::string &error_message() const;

  bool transcribe(const std::vector<int16_t> &samples,
                  const char *language_hint,
                  const std::atomic<bool> &cancel_requested,
                  LearnItWhisperResult *result,
                  std::string *error_code,
                  std::string *error_message);

 private:
  static bool abort_callback(void *user_data);

  std::string model_path_;
  int32_t threads_;
  whisper_context *context_ = nullptr;
  std::string error_code_;
  std::string error_message_;
  std::mutex inference_mutex_;
};

#endif
