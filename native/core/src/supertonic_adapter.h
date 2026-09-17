#ifndef LEARNIT_SUPERTONIC_ADAPTER_H
#define LEARNIT_SUPERTONIC_ADAPTER_H

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

struct LearnItSupertonicResult {
  std::vector<uint8_t> wav;
  int32_t sample_rate = 0;
  int32_t duration_ms = 0;
};

// Thin ownership adapter around the archived Supertonic C++ helper. ONNX
// Runtime, model files, and voice styles stay behind this class and never
// become part of the Dart-facing ABI.
class LearnItSupertonicAdapter {
 public:
  LearnItSupertonicAdapter(std::string model_dir,
                           std::string voice_style_path,
                           int32_t threads);
  ~LearnItSupertonicAdapter();

  LearnItSupertonicAdapter(const LearnItSupertonicAdapter &) = delete;
  LearnItSupertonicAdapter &operator=(const LearnItSupertonicAdapter &) =
      delete;

  bool ready() const;
  const std::string &error_code() const;
  const std::string &error_message() const;

  bool synthesize(const std::string &text,
                  const char *language,
                  const char *voice_style_id,
                  float speaking_rate,
                  const std::atomic<bool> &cancel_requested,
                  LearnItSupertonicResult *result,
                  std::string *error_code,
                  std::string *error_message);

 private:
  struct Impl;

  std::string model_dir_;
  std::string voice_style_path_;
  int32_t threads_;
  std::unique_ptr<Impl> impl_;
  std::string error_code_;
  std::string error_message_;
  std::mutex inference_mutex_;
};

#endif
