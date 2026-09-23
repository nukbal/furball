cmake_minimum_required(VERSION 3.20)
project(furball_ncnn LANGUAGES C CXX)

set(NCNN_SOURCE_DIR "" CACHE PATH "ncnn source directory")
set(MOLTENVK_PREFIX "" CACHE PATH "MoltenVK installation prefix")

if(NOT EXISTS "${NCNN_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "NCNN_SOURCE_DIR must point to the ncnn source tree")
endif()

if(NOT EXISTS "${MOLTENVK_PREFIX}/lib/libMoltenVK.a")
    message(FATAL_ERROR "MoltenVK static library was not found under MOLTENVK_PREFIX")
endif()

add_subdirectory("${NCNN_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/ncnn")
target_sources(ncnn PRIVATE "${CMAKE_CURRENT_LIST_DIR}/vulkan_bridge.cpp")
target_include_directories(ncnn PRIVATE "${MOLTENVK_PREFIX}/libexec/include")
foreach(framework IN ITEMS Metal Foundation QuartzCore CoreGraphics IOSurface AppKit IOKit)
    set(framework_path_var "FURBALL_FRAMEWORK_${framework}")
    find_library(${framework_path_var} NAMES "${framework}" REQUIRED)
    target_link_libraries(ncnn PRIVATE "${${framework_path_var}}")
endforeach()
target_link_libraries(ncnn PRIVATE objc)
set_target_properties(ncnn PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib"
    MACOSX_RPATH ON
    INSTALL_NAME_DIR "@rpath"
    BUILD_WITH_INSTALL_NAME_DIR ON
)
