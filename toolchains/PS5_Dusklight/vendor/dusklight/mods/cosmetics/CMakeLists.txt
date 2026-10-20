cmake_minimum_required(VERSION 3.25)
project(cosmetics CXX)

if (CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    # Fetch dusklight if we are invoking this as the root CMakeLists.txt
    if (NOT DUSKLIGHT_VERSION)
        set(DUSKLIGHT_VERSION "281475c9b193cac3ef8774dacf30d2ef6cd0110d")
    endif ()
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/FetchDusklight.cmake")
    option(DUSK_MOD_USE_FULL_TREE "Use full build instead of the minimal mod SDK" OFF)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    if (DUSK_MOD_USE_FULL_TREE)
        add_subdirectory("${DUSKLIGHT_DIR}" dusk EXCLUDE_FROM_ALL)
    else ()
        add_subdirectory("${DUSKLIGHT_DIR}/sdk" dusk-sdk EXCLUDE_FROM_ALL)
    endif ()
endif ()

include(FetchContent)

message(STATUS "cosmetics: Fetching xxhash")
FetchContent_Declare(
        xxhash
        GIT_REPOSITORY https://github.com/Cyan4973/xxHash.git
        GIT_TAG        v0.8.3
        SOURCE_SUBDIR  cmake_unofficial
)

# Prevent building extra xxhash artifacts
set(XXHASH_BUILD_XXHSUM OFF CACHE BOOL "" FORCE)
option(BUILD_SHARED_LIBS "Build shared libs" OFF)

FetchContent_MakeAvailable(xxhash)

set(COSMETICS_SOURCES src/color_utils.cpp src/midna_hair_color.cpp src/texture_utils.cpp src/hooks.cpp)

add_mod(cosmetics
    FEATURES game fmt
    SOURCES  src/mod.cpp ${COSMETICS_SOURCES}
    MOD_JSON mod.json
    RES_DIR  res
    BUNDLE
)

target_link_libraries(cosmetics PRIVATE xxHash::xxhash)
