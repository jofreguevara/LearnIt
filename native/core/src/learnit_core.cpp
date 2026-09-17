#include "learnit_core.h"

#include <cstdlib>
#include <cstring>
#include <string>

namespace {

std::string escape_json(const char *value) {
  std::string escaped;
  if (value == nullptr) {
    return escaped;
  }
  for (const unsigned char *cursor = reinterpret_cast<const unsigned char *>(value);
       *cursor != '\0';
       ++cursor) {
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

char *copy_string(const std::string &value) {
  auto *result = static_cast<char *>(std::malloc(value.size() + 1));
  if (result == nullptr) {
    return nullptr;
  }
  std::memcpy(result, value.c_str(), value.size() + 1);
  return result;
}

}  // namespace

const char *learnit_core_version(void) {
  return "learnit-core/0.1-demo";
}

char *learnit_demo_reply(const char *input, const char *language) {
  const std::string safe_input = escape_json(input);
  const std::string safe_language = escape_json(language);
  const std::string response =
      "{\"mode\":\"demo\",\"language\":\"" + safe_language +
      "\",\"input\":\"" + safe_input +
      "\",\"message\":\"Native bridge ready; install a verified model package for inference.\"}";
  return copy_string(response);
}

void learnit_free_string(char *value) {
  std::free(value);
}
