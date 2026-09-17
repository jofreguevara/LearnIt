cmake_minimum_required(VERSION 3.18)
project(learnit_core LANGUAGES CXX)

add_library(learnit_core SHARED src/learnit_core.cpp)
target_include_directories(learnit_core PUBLIC include)
target_compile_features(learnit_core PUBLIC cxx_std_17)
target_compile_options(learnit_core PRIVATE -Wall -Wextra -Wpedantic)

# Phase 1 replaces the demo entry point with adapters for whisper.cpp,
# llama.cpp and ONNX Runtime. Keeping this ABI small lets Flutter remain
# unchanged when those runtimes are added.
