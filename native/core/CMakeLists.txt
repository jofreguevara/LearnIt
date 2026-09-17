cmake_minimum_required(VERSION 3.18)
project(learnit_core LANGUAGES CXX)

add_library(learnit_core SHARED src/learnit_core.cpp)
target_include_directories(learnit_core PUBLIC include)
target_compile_features(learnit_core PUBLIC cxx_std_17)
target_compile_options(learnit_core PRIVATE -Wall -Wextra -Wpedantic)

include(CTest)
if(BUILD_TESTING)
  add_executable(learnit_core_test tests/learnit_core_test.cpp)
  target_compile_features(learnit_core_test PRIVATE cxx_std_17)
  target_include_directories(learnit_core_test PRIVATE include)
  target_link_libraries(learnit_core_test PRIVATE learnit_core)
  add_test(NAME learnit_core_smoke COMMAND learnit_core_test)
endif()

# Phase 1 replaces the demo entry point with adapters for whisper.cpp,
# llama.cpp and ONNX Runtime. Keeping this ABI small lets Flutter remain
# unchanged when those runtimes are added.
