cmake_minimum_required(VERSION 3.18)
project(learnit_core LANGUAGES CXX)

option(LEARNIT_WITH_WHISPER
       "Link the pinned whisper.cpp checkout into learnit_core"
       OFF)
set(LEARNIT_WHISPER_ROOT "" CACHE PATH
    "Path to the pinned whisper.cpp checkout")

add_library(learnit_core SHARED src/learnit_core.cpp)
target_include_directories(learnit_core PUBLIC include)
target_compile_features(learnit_core PUBLIC cxx_std_17)
target_compile_options(learnit_core PRIVATE -Wall -Wextra -Wpedantic)

if(LEARNIT_WITH_WHISPER)
  if(NOT IS_DIRECTORY "${LEARNIT_WHISPER_ROOT}")
    message(FATAL_ERROR
            "LEARNIT_WITH_WHISPER=ON requires LEARNIT_WHISPER_ROOT")
  endif()

  # The mobile target is deliberately CPU-only and does not build whisper's
  # command-line tools, tests, downloads, or host-specific optimizations.
  set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
  set(WHISPER_CURL OFF CACHE BOOL "" FORCE)
  set(WHISPER_SDL2 OFF CACHE BOOL "" FORCE)
  set(WHISPER_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(GGML_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
  set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
  set(GGML_CCACHE OFF CACHE BOOL "" FORCE)
  set(CMAKE_POSITION_INDEPENDENT_CODE ON)

  add_subdirectory("${LEARNIT_WHISPER_ROOT}"
                   "${CMAKE_CURRENT_BINARY_DIR}/whisper.cpp"
                   EXCLUDE_FROM_ALL)
  target_sources(learnit_core PRIVATE src/whisper_adapter.cpp)
  target_include_directories(learnit_core PRIVATE
                             "${LEARNIT_WHISPER_ROOT}/include")
  target_compile_definitions(learnit_core PRIVATE LEARNIT_WITH_WHISPER=1)
  target_link_libraries(learnit_core PRIVATE whisper)
  if(TARGET whisper)
    set_property(TARGET whisper PROPERTY POSITION_INDEPENDENT_CODE ON)
  endif()
endif()

include(CTest)
if(BUILD_TESTING)
  add_executable(learnit_core_test tests/learnit_core_test.cpp)
  target_compile_features(learnit_core_test PRIVATE cxx_std_17)
  target_include_directories(learnit_core_test PRIVATE include)
  target_link_libraries(learnit_core_test PRIVATE learnit_core)
  add_test(NAME learnit_core_smoke COMMAND learnit_core_test)

  if(LEARNIT_WITH_WHISPER)
    add_executable(learnit_whisper_smoke tests/learnit_whisper_smoke.cpp)
    target_compile_features(learnit_whisper_smoke PRIVATE cxx_std_17)
    target_include_directories(learnit_whisper_smoke PRIVATE include)
    target_link_libraries(learnit_whisper_smoke PRIVATE learnit_core)
  endif()
endif()

# The default build keeps the ABI and demo available without downloading a
# runtime. Production/host inference is enabled explicitly with
# -DLEARNIT_WITH_WHISPER=ON and a pinned -DLEARNIT_WHISPER_ROOT=... checkout.
