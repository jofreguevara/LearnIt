#ifndef LEARNIT_LLAMA_ADAPTER_H
#define LEARNIT_LLAMA_ADAPTER_H

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>

struct LearnItLlamaResult {
  std::string text;
  std::string language;
};

// Owns a llama.cpp model without allowing llama.cpp types to cross the
// LearnIt C ABI. Contexts are short-lived per request so the Dart session can
// provide its own verified conversation context on every turn.
class LearnItLlamaAdapter {
 public:
  LearnItLlamaAdapter(std::string model_path, int32_t threads);
  ~LearnItLlamaAdapter();

  LearnItLlamaAdapter(const LearnItLlamaAdapter &) = delete;
  LearnItLlamaAdapter &operator=(const LearnItLlamaAdapter &) = delete;

  bool ready() const;
  const std::string &error_code() const;
  const std::string &error_message() const;

  bool generate(const std::string &request_json,
                const std::atomic<bool> &cancel_requested,
                LearnItLlamaResult *result,
                std::string *error_code,
                std::string *error_message);

 private:
  static bool abort_callback(void *user_data);

  std::string model_path_;
  int32_t threads_;
  struct llama_model *model_ = nullptr;
  std::string error_code_;
  std::string error_message_;
  std::mutex inference_mutex_;
};

#endif
