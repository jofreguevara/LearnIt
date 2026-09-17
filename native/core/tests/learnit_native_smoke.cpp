#include "learnit_core.h"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <string>
#include <thread>

namespace {

struct Arguments {
  std::string llama_model;
  std::string supertonic_dir;
  std::string voice_style;
  std::string text = "Hello, I want to practice English today.";
};

bool next_value(int argc, char **argv, int *index, std::string *value) {
  if (*index + 1 >= argc) {
    return false;
  }
  *value = argv[++(*index)];
  return true;
}

bool parse_arguments(int argc, char **argv, Arguments *arguments) {
  for (int index = 1; index < argc; ++index) {
    const std::string option = argv[index];
    if (option == "--llama") {
      if (!next_value(argc, argv, &index, &arguments->llama_model)) {
        return false;
      }
    } else if (option == "--tts-dir") {
      if (!next_value(argc, argv, &index, &arguments->supertonic_dir)) {
        return false;
      }
    } else if (option == "--voice") {
      if (!next_value(argc, argv, &index, &arguments->voice_style)) {
        return false;
      }
    } else if (option == "--text") {
      if (!next_value(argc, argv, &index, &arguments->text)) {
        return false;
      }
    } else {
      return false;
    }
  }
  return !arguments->llama_model.empty() ||
         (!arguments->supertonic_dir.empty() &&
          !arguments->voice_style.empty());
}

char *wait_for_job(learnit_core_session_t *session,
                   learnit_core_job_id_t job_id) {
  for (int attempt = 0; attempt < 6000; ++attempt) {
    if (char *result = learnit_core_job_poll(session, job_id);
        result != nullptr) {
      return result;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return nullptr;
}

}  // namespace

int main(int argc, char **argv) {
  Arguments arguments;
  if (!parse_arguments(argc, argv, &arguments)) {
    std::cerr << "usage: learnit_native_smoke [--llama MODEL] "
                 "[--tts-dir ONNX_DIR --voice VOICE.json] [--text TEXT]\n";
    return 2;
  }

  auto *session = learnit_core_session_create_ex(
      nullptr, arguments.llama_model.empty() ? nullptr
                                             : arguments.llama_model.c_str(),
      arguments.supertonic_dir.empty() ? nullptr
                                       : arguments.supertonic_dir.c_str(),
      arguments.voice_style.empty() ? nullptr : arguments.voice_style.c_str(),
      2);
  if (session == nullptr) {
    std::cerr << "could not create native session\n";
    return 1;
  }

  int exit_code = 0;
  if (!arguments.llama_model.empty()) {
    const std::string request =
        R"({"text":"Hello, I want to practice English today.","language":"en","level":"A1","companion":{"name":"Alex","personality":"warm and curious","correction_mode":"gentle"},"memories":[],"last_summary":null})";
    const auto job_id = learnit_core_dialogue_start(session, request.c_str());
    char *raw = job_id == 0 ? nullptr : wait_for_job(session, job_id);
    if (raw == nullptr ||
        std::string(raw).find("\"ok\":true") == std::string::npos ||
        std::string(raw).find("\"type\":\"dialogue\"") == std::string::npos) {
      std::cerr << "llama dialogue smoke failed: "
                << (raw == nullptr ? learnit_core_session_last_error(session)
                                   : raw)
                << "\n";
      exit_code = 1;
    } else {
      std::cout << raw << "\n";
    }
    if (raw != nullptr) {
      learnit_free_string(raw);
    }
  }

  if (!arguments.supertonic_dir.empty()) {
    const auto job_id = learnit_core_tts_start(
        session, arguments.text.c_str(), "en", "M1", 1.0f);
    char *raw = job_id == 0 ? nullptr : wait_for_job(session, job_id);
    if (raw == nullptr ||
        std::string(raw).find("\"ok\":true") == std::string::npos ||
        std::string(raw).find("\"type\":\"audio\"") == std::string::npos ||
        std::string(raw).find("\"audio_base64\":\"") == std::string::npos) {
      std::cerr << "Supertonic smoke failed: "
                << (raw == nullptr ? learnit_core_session_last_error(session)
                                   : raw)
                << "\n";
      exit_code = 1;
    } else {
      std::cout << "Supertonic audio smoke passed\n";
    }
    if (raw != nullptr) {
      learnit_free_string(raw);
    }
  }

  learnit_core_session_destroy(session);
  return exit_code;
}
