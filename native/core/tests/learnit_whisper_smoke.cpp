#include "learnit_core.h"

#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

uint16_t read_u16(const std::vector<uint8_t> &bytes, size_t offset) {
  return static_cast<uint16_t>(bytes[offset]) |
         static_cast<uint16_t>(bytes[offset + 1] << 8);
}

uint32_t read_u32(const std::vector<uint8_t> &bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

bool read_pcm16_wav(const std::string &path,
                    std::vector<int16_t> *samples,
                    int32_t *sample_rate) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    return false;
  }
  const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)),
                                   std::istreambuf_iterator<char>());
  if (bytes.size() < 12 || std::string(bytes.begin(), bytes.begin() + 4) !=
                               "RIFF" ||
      std::string(bytes.begin() + 8, bytes.begin() + 12) != "WAVE") {
    return false;
  }

  size_t cursor = 12;
  size_t data_offset = 0;
  size_t data_size = 0;
  uint16_t format = 0;
  uint16_t channels = 0;
  uint16_t bits_per_sample = 0;
  uint32_t rate = 0;
  while (cursor + 8 <= bytes.size()) {
    const std::string chunk(bytes.begin() + cursor,
                            bytes.begin() + cursor + 4);
    const size_t chunk_size = read_u32(bytes, cursor + 4);
    cursor += 8;
    if (chunk_size > bytes.size() - cursor) {
      return false;
    }
    if (chunk == "fmt " && chunk_size >= 16) {
      format = read_u16(bytes, cursor);
      channels = read_u16(bytes, cursor + 2);
      rate = read_u32(bytes, cursor + 4);
      bits_per_sample = read_u16(bytes, cursor + 14);
    } else if (chunk == "data") {
      data_offset = cursor;
      data_size = chunk_size;
      break;
    }
    cursor += chunk_size + (chunk_size & 1U);
  }

  if (format != 1 || channels != 1 || bits_per_sample != 16 || rate != 16000 ||
      data_size == 0 || (data_size & 1U) != 0) {
    return false;
  }
  samples->resize(data_size / 2);
  for (size_t index = 0; index < samples->size(); ++index) {
    const size_t offset = data_offset + index * 2;
    (*samples)[index] = static_cast<int16_t>(
        static_cast<uint16_t>(bytes[offset]) |
        static_cast<uint16_t>(bytes[offset + 1] << 8));
  }
  *sample_rate = static_cast<int32_t>(rate);
  return true;
}

}  // namespace

int main(int argc, char **argv) {
  if (argc != 3) {
    std::cerr << "usage: learnit_whisper_smoke MODEL AUDIO.wav\n";
    return 2;
  }

  std::vector<int16_t> samples;
  int32_t sample_rate = 0;
  if (!read_pcm16_wav(argv[2], &samples, &sample_rate)) {
    std::cerr << "could not read a 16-bit mono 16 kHz WAV\n";
    return 1;
  }

  auto *session = learnit_core_session_create(argv[1], 2);
  if (session == nullptr || learnit_core_session_load(session) == 0) {
    std::cerr << "model load failed: "
              << learnit_core_session_last_error(session) << "\n";
    learnit_core_session_destroy(session);
    return 1;
  }

  const auto job_id = learnit_core_transcribe_start(
      session, samples.data(), static_cast<int32_t>(samples.size()),
      sample_rate, "auto");
  if (job_id == 0) {
    std::cerr << "could not start transcription: "
              << learnit_core_session_last_error(session) << "\n";
    learnit_core_session_destroy(session);
    return 1;
  }

  char *raw = nullptr;
  for (int attempt = 0; attempt < 1000 && raw == nullptr; ++attempt) {
    raw = learnit_core_job_poll(session, job_id);
    if (raw == nullptr) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
  }
  if (raw == nullptr) {
    std::cerr << "transcription did not finish\n";
    learnit_core_session_cancel(session);
    learnit_core_session_destroy(session);
    return 1;
  }
  const std::string result(raw);
  learnit_free_string(raw);
  learnit_core_session_destroy(session);
  if (result.find("\"ok\":true") == std::string::npos ||
      result.find("\"text\":\"") == std::string::npos) {
    std::cerr << result << '\n';
    return 1;
  }
  std::cout << result << '\n';
  return 0;
}
