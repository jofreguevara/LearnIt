cmake_minimum_required(VERSION 3.18.1)
project(learnit_core LANGUAGES CXX)

set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(LEARNIT_WHISPER_ROOT "" CACHE PATH
    "Path to the pinned whisper.cpp checkout")
set(LEARNIT_WITH_WHISPER OFF CACHE BOOL
    "Link whisper.cpp into the Android shared core")

# AGP 9's new CMake DSL no longer exposes arbitrary configure arguments. Use
# environment variables for reproducible opt-in builds without changing the
# default APK configuration.
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

add_subdirectory(
    ../../../../../native/core
    ${CMAKE_CURRENT_BINARY_DIR}/learnit_core
)
