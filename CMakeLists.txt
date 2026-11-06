cmake_minimum_required(VERSION 3.20)
project(FleshCore VERSION 0.1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
add_library(FleshCore SHARED
    src/flesh.cpp
    src/lattice.cpp
    src/chunknif.cpp
    src/windiag.cpp
)
target_link_libraries(FleshCore PRIVATE psapi winmm)
set_target_properties(FleshCore PROPERTIES PREFIX "")
