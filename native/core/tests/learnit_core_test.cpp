#include "learnit_core.h"

#include <cassert>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>

int main() {
  assert(std::string(learnit_core_version()).find("learnit-core/0.4.0") == 0);

  const std::string capabilities = learnit_core_capabilities();
  assert(capabilities.find("\"abi\":2") != std::string::npos);
  assert(capabilities.find("\"phase\":1") != std::string::npos);
  assert(capabilities.find("\"async_transcribe\":true") !=
         std::string::npos);

  char *reply = learnit_demo_reply("a\"b\n", "en");
  assert(reply != nullptr);
  const std::string response(reply);
  assert(response.find("a\\\"b\\n") != std::string::npos);
  assert(response.find("\"runtime\":\"native-abi\"") !=
         std::string::npos);
  learnit_free_string(reply);

  auto *session = learnit_core_session_create(nullptr, 0);
  assert(session != nullptr);
  assert(learnit_core_session_is_ready(session) == 0);

  char *empty = learnit_core_transcribe(session, nullptr, 0, 16000, "auto");
  assert(empty != nullptr);
  assert(std::string(empty).find("\"code\":\"empty_audio\"") !=
         std::string::npos);
  learnit_free_string(empty);
  assert(std::string(learnit_core_session_last_error(session)).find(
             "empty_audio") != std::string::npos);

  const int16_t samples[320] = {};
  const auto job_id = learnit_core_transcribe_start(
      session, samples, 320, 16000, "auto");
  assert(job_id != 0);
  char *job_result = nullptr;
  for (int attempt = 0; attempt < 100 && job_result == nullptr; ++attempt) {
    job_result = learnit_core_job_poll(session, job_id);
    if (job_result == nullptr) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  }
  assert(job_result != nullptr);
  assert(std::string(job_result).find("\"ok\":false") != std::string::npos);
  learnit_free_string(job_result);
  learnit_core_session_destroy(session);
  return 0;
}
