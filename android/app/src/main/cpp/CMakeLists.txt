cmake_minimum_required(VERSION 3.18.1)
project(learnit_core LANGUAGES CXX)

add_library(learnit_core SHARED
    ../../../../../native/core/src/learnit_core.cpp
)

target_include_directories(learnit_core PRIVATE
    ../../../../../native/core/include
)

target_compile_features(learnit_core PRIVATE cxx_std_17)
target_compile_options(learnit_core PRIVATE -Wall -Wextra -Wpedantic)
