cmake_minimum_required(VERSION 3.18.1)
project(quickjs_napi C CXX)

# Use CMAKE_SYSROOT which is set by the HarmonyOS toolchain
set(SYSROOT "${CMAKE_SYSROOT}")
set(TARGET_LIB_DIR "${SYSROOT}/usr/lib/aarch64-linux-ohos")
set(TARGET_INCLUDE_DIR "${SYSROOT}/usr/include")

# QuickJS source files - compile as C
set(QUICKJS_C_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/quickjs_src/quickjs.c
    ${CMAKE_CURRENT_SOURCE_DIR}/quickjs_src/cutils.c
    ${CMAKE_CURRENT_SOURCE_DIR}/quickjs_src/dtoa.c
    ${CMAKE_CURRENT_SOURCE_DIR}/quickjs_src/libunicode.c
    ${CMAKE_CURRENT_SOURCE_DIR}/quickjs_src/libregexp.c
)

# Add compile flags for QuickJS C files
set_source_files_properties(
    ${QUICKJS_C_SOURCES}
    PROPERTIES
    COMPILE_FLAGS "-D_GNU_SOURCE -DCONFIG_VERSION=\\\"2024-12-31\\\" -Wno-error -fno-short-enums"
)

# ==================== QuickJS Native Module ====================

add_library(quickjs_napi SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/napi_quickjs.cpp
    ${QUICKJS_C_SOURCES}
)

target_link_libraries(quickjs_napi
    m
    "${TARGET_LIB_DIR}/libace_napi.z.so"
    "${TARGET_LIB_DIR}/libhilog_ndk.z.so"
)

target_include_directories(quickjs_napi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/quickjs_src
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${TARGET_INCLUDE_DIR}
)

set_target_properties(quickjs_napi PROPERTIES
    OUTPUT_NAME "quickjs_napi"
    C_VISIBILITY_PRESET default
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
)

# ==================== QuickJS Loader Module ====================

add_library(quickjs_loader SHARED
    ${CMAKE_CURRENT_SOURCE_DIR}/napi_quickjs_loader.cpp
)

target_link_libraries(quickjs_loader
    m
    dl
    "${TARGET_LIB_DIR}/libace_napi.z.so"
    "${TARGET_LIB_DIR}/libhilog_ndk.z.so"
)

target_include_directories(quickjs_loader PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${TARGET_INCLUDE_DIR}
)

set_target_properties(quickjs_loader PROPERTIES
    OUTPUT_NAME "quickjs_loader"
    C_VISIBILITY_PRESET default
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
)
