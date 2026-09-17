cmake_minimum_required(VERSION 3.18.1)
project(learnit_core LANGUAGES CXX)

set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(LEARNIT_LLAMA_ROOT "" CACHE PATH
    "Path to the pinned llama.cpp checkout")
set(LEARNIT_WITH_LLAMA OFF CACHE BOOL
    "Link llama.cpp into the Android shared core")
set(LEARNIT_WHISPER_ROOT "" CACHE PATH
    "Path to the pinned whisper.cpp checkout")
set(LEARNIT_WITH_WHISPER OFF CACHE BOOL
    "Link whisper.cpp into the Android shared core")
set(LEARNIT_SUPERTONIC_ROOT "" CACHE PATH
    "Path to the pinned Supertonic checkout")
set(LEARNIT_WITH_SUPERTONIC OFF CACHE BOOL
    "Link Supertonic into the Android shared core")
set(LEARNIT_ONNXRUNTIME_ROOT "" CACHE PATH
    "Path to the Android ONNX Runtime distribution")
set(LEARNIT_NLOHMANN_ROOT "" CACHE PATH
    "Path containing nlohmann/json.hpp")

# AGP 9's new CMake DSL no longer exposes arbitrary configure arguments. Use
# environment variables for reproducible opt-in builds without changing the
# default APK configuration.
if(DEFINED ENV{LEARNIT_LLAMA_ROOT})
    set(LEARNIT_LLAMA_ROOT "$ENV{LEARNIT_LLAMA_ROOT}" CACHE PATH
        "Path to the pinned llama.cpp checkout" FORCE)
else()
    set(LEARNIT_LLAMA_ROOT "" CACHE PATH
        "Path to the pinned llama.cpp checkout" FORCE)
endif()
if(DEFINED ENV{LEARNIT_WITH_LLAMA})
    set(LEARNIT_WITH_LLAMA "$ENV{LEARNIT_WITH_LLAMA}" CACHE BOOL
        "Link llama.cpp into the Android shared core" FORCE)
else()
    set(LEARNIT_WITH_LLAMA OFF CACHE BOOL
        "Link llama.cpp into the Android shared core" FORCE)
endif()
if(DEFINED ENV{LEARNIT_WHISPER_ROOT})
    set(LEARNIT_WHISPER_ROOT "$ENV{LEARNIT_WHISPER_ROOT}" CACHE PATH
        "Path to the pinned whisper.cpp checkout" FORCE)
else()
    set(LEARNIT_WHISPER_ROOT "" CACHE PATH
        "Path to the pinned whisper.cpp checkout" FORCE)
endif()
if(DEFINED ENV{LEARNIT_WITH_WHISPER})
    set(LEARNIT_WITH_WHISPER "$ENV{LEARNIT_WITH_WHISPER}" CACHE BOOL
        "Link whisper.cpp into the Android shared core" FORCE)
else()
    set(LEARNIT_WITH_WHISPER OFF CACHE BOOL
        "Link whisper.cpp into the Android shared core" FORCE)
endif()
if(DEFINED ENV{LEARNIT_SUPERTONIC_ROOT})
    set(LEARNIT_SUPERTONIC_ROOT "$ENV{LEARNIT_SUPERTONIC_ROOT}" CACHE PATH
        "Path to the pinned Supertonic checkout" FORCE)
else()
    set(LEARNIT_SUPERTONIC_ROOT "" CACHE PATH
        "Path to the pinned Supertonic checkout" FORCE)
endif()
if(DEFINED ENV{LEARNIT_WITH_SUPERTONIC})
    set(LEARNIT_WITH_SUPERTONIC "$ENV{LEARNIT_WITH_SUPERTONIC}" CACHE BOOL
        "Link Supertonic into the Android shared core" FORCE)
else()
    set(LEARNIT_WITH_SUPERTONIC OFF CACHE BOOL
        "Link Supertonic into the Android shared core" FORCE)
endif()
if(DEFINED ENV{LEARNIT_ONNXRUNTIME_ROOT})
    set(LEARNIT_ONNXRUNTIME_ROOT "$ENV{LEARNIT_ONNXRUNTIME_ROOT}" CACHE PATH
        "Path to the Android ONNX Runtime distribution" FORCE)
else()
    set(LEARNIT_ONNXRUNTIME_ROOT "" CACHE PATH
        "Path to the Android ONNX Runtime distribution" FORCE)
endif()
if(DEFINED ENV{LEARNIT_NLOHMANN_ROOT})
    set(LEARNIT_NLOHMANN_ROOT "$ENV{LEARNIT_NLOHMANN_ROOT}" CACHE PATH
        "Path containing nlohmann/json.hpp" FORCE)
elseif(LEARNIT_WITH_SUPERTONIC AND LEARNIT_WITH_LLAMA)
    set(LEARNIT_NLOHMANN_ROOT "${LEARNIT_LLAMA_ROOT}/vendor" CACHE PATH
        "Path containing nlohmann/json.hpp" FORCE)
else()
    set(LEARNIT_NLOHMANN_ROOT "" CACHE PATH
        "Path containing nlohmann/json.hpp" FORCE)
endif()

add_subdirectory(
    ../../../../../native/core
    ${CMAKE_CURRENT_BINARY_DIR}/learnit_core
)
