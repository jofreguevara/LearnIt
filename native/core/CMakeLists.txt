cmake_minimum_required(VERSION 3.18)
project(learnit_core LANGUAGES CXX)

option(LEARNIT_WITH_LLAMA
       "Link the pinned llama.cpp checkout into learnit_core"
       OFF)
set(LEARNIT_LLAMA_ROOT "" CACHE PATH
    "Path to the pinned llama.cpp checkout")

option(LEARNIT_WITH_WHISPER
       "Link the pinned whisper.cpp checkout into learnit_core"
       OFF)
set(LEARNIT_WHISPER_ROOT "" CACHE PATH
    "Path to the pinned whisper.cpp checkout")

option(LEARNIT_WITH_SUPERTONIC
       "Link the pinned Supertonic C++ helper and ONNX Runtime into learnit_core"
       OFF)
set(LEARNIT_SUPERTONIC_ROOT "" CACHE PATH
    "Path to the pinned Supertonic checkout")
set(LEARNIT_ONNXRUNTIME_ROOT "" CACHE PATH
    "Path to an ONNX Runtime distribution with include/ and lib/")
set(LEARNIT_ONNXRUNTIME_VERSION "1.23.1" CACHE STRING
    "Expected ONNX Runtime version for the selected distribution")
set(LEARNIT_NLOHMANN_ROOT "" CACHE PATH
    "Path containing nlohmann/json.hpp")

find_package(Threads REQUIRED)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(learnit_core SHARED src/learnit_core.cpp)
target_include_directories(learnit_core PUBLIC include)
target_compile_features(learnit_core PUBLIC cxx_std_17)
target_compile_options(learnit_core PRIVATE -Wall -Wextra -Wpedantic)

if(LEARNIT_WITH_LLAMA)
  if(NOT IS_DIRECTORY "${LEARNIT_LLAMA_ROOT}")
    message(FATAL_ERROR
            "LEARNIT_WITH_LLAMA=ON requires LEARNIT_LLAMA_ROOT")
  endif()

  # Build only the CPU library. The same configuration works for host and
  # Android/iOS cross-builds and avoids pulling tools, examples, tests, or
  # dynamically loaded GPU backends into the app.
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_IS_DEV OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_MTMD OFF CACHE BOOL "" FORCE)
  set(LLAMA_TOOLS_INSTALL OFF CACHE BOOL "" FORCE)
  set(LLAMA_TESTS_INSTALL OFF CACHE BOOL "" FORCE)
  set(LLAMA_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(LLAMA_ALL_WARNINGS_3RD_PARTY OFF CACHE BOOL "" FORCE)
  set(LLAMA_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
  set(LLAMA_SUBPROCESS OFF CACHE BOOL "" FORCE)
  set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
  set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
  set(GGML_ALL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(GGML_ALL_WARNINGS_3RD_PARTY OFF CACHE BOOL "" FORCE)
  set(GGML_FATAL_WARNINGS OFF CACHE BOOL "" FORCE)
  set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(GGML_BUILD_SERVER OFF CACHE BOOL "" FORCE)
  set(GGML_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
  set(GGML_ACCELERATE OFF CACHE BOOL "" FORCE)
  set(GGML_BLAS OFF CACHE BOOL "" FORCE)
  set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
  set(GGML_CCACHE OFF CACHE BOOL "" FORCE)

  add_subdirectory("${LEARNIT_LLAMA_ROOT}"
                   "${CMAKE_CURRENT_BINARY_DIR}/llama.cpp"
                   EXCLUDE_FROM_ALL)
  if(NOT LEARNIT_NLOHMANN_ROOT AND
     EXISTS "${LEARNIT_LLAMA_ROOT}/vendor/nlohmann/json.hpp")
    set(LEARNIT_NLOHMANN_ROOT "${LEARNIT_LLAMA_ROOT}/vendor")
  endif()
  if(EXISTS "${LEARNIT_LLAMA_ROOT}/vendor/nlohmann/json.hpp")
    set(LEARNIT_NLOHMANN_INCLUDE_DIR "${LEARNIT_LLAMA_ROOT}/vendor")
  else()
    find_path(LEARNIT_NLOHMANN_INCLUDE_DIR
              NAMES nlohmann/json.hpp
              HINTS "${LEARNIT_NLOHMANN_ROOT}"
              NO_CMAKE_FIND_ROOT_PATH)
  endif()
  if(NOT LEARNIT_NLOHMANN_INCLUDE_DIR)
    message(FATAL_ERROR
            "LEARNIT_WITH_LLAMA=ON requires nlohmann/json.hpp. "
            "Set LEARNIT_NLOHMANN_ROOT to its include root.")
  endif()
  target_sources(learnit_core PRIVATE src/llama_adapter.cpp)
  target_include_directories(learnit_core PRIVATE
                             "${LEARNIT_LLAMA_ROOT}/include"
                             "${LEARNIT_NLOHMANN_INCLUDE_DIR}")
  target_compile_definitions(learnit_core PRIVATE LEARNIT_WITH_LLAMA=1)
  target_link_libraries(learnit_core PRIVATE llama Threads::Threads)
endif()

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

if(LEARNIT_WITH_SUPERTONIC)
  if(NOT IS_DIRECTORY "${LEARNIT_SUPERTONIC_ROOT}")
    message(FATAL_ERROR
            "LEARNIT_WITH_SUPERTONIC=ON requires LEARNIT_SUPERTONIC_ROOT")
  endif()

  # Android receives a multi-ABI package. Select the directory that matches
  # Gradle's ANDROID_ABI before resolving any headers or libraries; otherwise
  # CMake can silently pick the host Linux distribution.
  set(_learnit_onnxruntime_root "${LEARNIT_ONNXRUNTIME_ROOT}")
  if(ANDROID AND ANDROID_ABI AND
     IS_DIRECTORY "${LEARNIT_ONNXRUNTIME_ROOT}/${ANDROID_ABI}/include")
    set(_learnit_onnxruntime_root
        "${LEARNIT_ONNXRUNTIME_ROOT}/${ANDROID_ABI}")
  endif()
  set(LEARNIT_ONNXRUNTIME_INCLUDE_DIR
      "${_learnit_onnxruntime_root}/include")
  set(LEARNIT_ONNXRUNTIME_LIBRARY
      "${_learnit_onnxruntime_root}/lib/libonnxruntime.so")
  if(NOT IS_DIRECTORY "${LEARNIT_ONNXRUNTIME_INCLUDE_DIR}" OR
     NOT EXISTS "${LEARNIT_ONNXRUNTIME_INCLUDE_DIR}/onnxruntime_cxx_api.h" OR
     NOT EXISTS "${LEARNIT_ONNXRUNTIME_LIBRARY}")
    message(FATAL_ERROR
            "LEARNIT_WITH_SUPERTONIC=ON requires an ONNX Runtime C++ "
            "distribution. Set LEARNIT_ONNXRUNTIME_ROOT to its root.")
  endif()

  set(_learnit_onnxruntime_abi "host")
  if(ANDROID)
    set(_learnit_onnxruntime_abi "${ANDROID_ABI}")
    if(NOT EXISTS "${_learnit_onnxruntime_root}/abi.txt")
      message(FATAL_ERROR
              "ONNX Runtime mobile package is missing abi.txt at "
              "${_learnit_onnxruntime_root}")
    endif()
    file(READ "${_learnit_onnxruntime_root}/abi.txt"
         _learnit_onnxruntime_package_abi)
    string(STRIP "${_learnit_onnxruntime_package_abi}"
           _learnit_onnxruntime_package_abi)
    if(NOT _learnit_onnxruntime_package_abi STREQUAL ANDROID_ABI)
      message(FATAL_ERROR
              "ONNX Runtime ABI mismatch: package="
              "${_learnit_onnxruntime_package_abi}, requested=${ANDROID_ABI}")
    endif()
  endif()

  set(_learnit_onnxruntime_package_version "")
  if(EXISTS "${_learnit_onnxruntime_root}/version.txt")
    file(READ "${_learnit_onnxruntime_root}/version.txt"
         _learnit_onnxruntime_package_version)
  elseif(EXISTS "${_learnit_onnxruntime_root}/VERSION_NUMBER")
    file(READ "${_learnit_onnxruntime_root}/VERSION_NUMBER"
         _learnit_onnxruntime_package_version)
  endif()
  string(STRIP "${_learnit_onnxruntime_package_version}"
         _learnit_onnxruntime_package_version)
  if(_learnit_onnxruntime_package_version AND
     NOT _learnit_onnxruntime_package_version STREQUAL
         LEARNIT_ONNXRUNTIME_VERSION)
    message(FATAL_ERROR
            "ONNX Runtime version mismatch: package="
            "${_learnit_onnxruntime_package_version}, expected="
            "${LEARNIT_ONNXRUNTIME_VERSION}")
  endif()
  message(STATUS
          "LearnIt: ONNX Runtime ${LEARNIT_ONNXRUNTIME_VERSION} ABI "
          "${_learnit_onnxruntime_abi} from ${_learnit_onnxruntime_root}")

  add_library(learnit_onnxruntime SHARED IMPORTED GLOBAL)
  set_target_properties(learnit_onnxruntime PROPERTIES
                        IMPORTED_LOCATION "${LEARNIT_ONNXRUNTIME_LIBRARY}"
                        INTERFACE_INCLUDE_DIRECTORIES
                        "${LEARNIT_ONNXRUNTIME_INCLUDE_DIR}")

  if(NOT LEARNIT_NLOHMANN_ROOT AND LEARNIT_WITH_LLAMA AND
     EXISTS "${LEARNIT_LLAMA_ROOT}/vendor/nlohmann/json.hpp")
    set(LEARNIT_NLOHMANN_ROOT "${LEARNIT_LLAMA_ROOT}/vendor")
  endif()
  find_path(LEARNIT_NLOHMANN_INCLUDE_DIR
            NAMES nlohmann/json.hpp
            HINTS "${LEARNIT_NLOHMANN_ROOT}"
            NO_CMAKE_FIND_ROOT_PATH)
  if(NOT LEARNIT_NLOHMANN_INCLUDE_DIR)
    message(FATAL_ERROR
            "LEARNIT_WITH_SUPERTONIC=ON requires nlohmann/json.hpp. "
            "Set LEARNIT_NLOHMANN_ROOT to its include root.")
  endif()

  add_library(learnit_supertonic_helper STATIC
              "${LEARNIT_SUPERTONIC_ROOT}/cpp/helper.cpp")
  target_compile_features(learnit_supertonic_helper PUBLIC cxx_std_17)
  target_include_directories(learnit_supertonic_helper PUBLIC
                             "${LEARNIT_SUPERTONIC_ROOT}/cpp"
                             "${LEARNIT_ONNXRUNTIME_INCLUDE_DIR}"
                             "${LEARNIT_NLOHMANN_INCLUDE_DIR}")
  target_link_libraries(learnit_supertonic_helper PUBLIC
                        learnit_onnxruntime
                        Threads::Threads
                        ${CMAKE_DL_LIBS})
  set_property(TARGET learnit_supertonic_helper
               PROPERTY POSITION_INDEPENDENT_CODE ON)

  target_sources(learnit_core PRIVATE src/supertonic_adapter.cpp)
  target_include_directories(learnit_core PRIVATE
                             "${LEARNIT_SUPERTONIC_ROOT}/cpp"
                             "${LEARNIT_ONNXRUNTIME_INCLUDE_DIR}"
                             "${LEARNIT_NLOHMANN_INCLUDE_DIR}")
  target_compile_definitions(learnit_core PRIVATE
                             LEARNIT_WITH_SUPERTONIC=1
                             LEARNIT_ONNXRUNTIME_VERSION=\"${LEARNIT_ONNXRUNTIME_VERSION}\"
                             LEARNIT_ONNXRUNTIME_ABI=\"${_learnit_onnxruntime_abi}\")
  target_link_libraries(learnit_core PRIVATE
                        learnit_supertonic_helper
                        learnit_onnxruntime
                        Threads::Threads
                        ${CMAKE_DL_LIBS})
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

  if(LEARNIT_WITH_LLAMA OR LEARNIT_WITH_SUPERTONIC)
    add_executable(learnit_native_smoke tests/learnit_native_smoke.cpp)
    target_compile_features(learnit_native_smoke PRIVATE cxx_std_17)
    target_include_directories(learnit_native_smoke PRIVATE include)
    target_link_libraries(learnit_native_smoke PRIVATE learnit_core)
  endif()
endif()

# The default build keeps the ABI and demo available without downloading a
# runtime. Production/host inference is enabled explicitly with the relevant
# pinned checkouts and model paths.
