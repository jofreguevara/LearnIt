#include "learnit_core.h"

#include <cassert>
#include <cstring>
#include <string>

int main() {
  assert(std::string(learnit_core_version()) ==
         "learnit-core/0.3-phase1-spike");

  const std::string capabilities = learnit_core_capabilities();
  assert(capabilities.find("\"phase\":1") != std::string::npos);
  assert(capabilities.find("\"dialogue\"") != std::string::npos);

  char *reply = learnit_demo_reply("a\"b\n", "en");
  assert(reply != nullptr);
  const std::string response(reply);
  assert(response.find("a\\\"b\\n") != std::string::npos);
  assert(response.find("\"runtime\":\"native-spike\"") !=
         std::string::npos);
  learnit_free_string(reply);
  return 0;
}
