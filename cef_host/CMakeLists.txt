cmake_minimum_required(VERSION 3.21)

# Force a single-config Release build. Arch: arm64 on macOS, x86_64 on Windows.
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
if(APPLE)
  set(PROJECT_ARCH "arm64" CACHE STRING "")
  set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "")
endif()

project(cef_host CXX)

# Locate CEF (FindCEF.cmake ships in the distribution's cmake/ dir).
set(CEF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/cef" CACHE PATH "")
set(CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
set(USE_SANDBOX OFF CACHE BOOL "" FORCE)  # we run with no_sandbox + a single helper
find_package(CEF REQUIRED)

# Build the libcef_dll_wrapper static lib that ships as source.
add_subdirectory("${CEF_LIBCEF_DLL_WRAPPER_PATH}" libcef_dll_wrapper)

# Multi-config generators (VS) put binaries in a per-config subdir.
if(GEN_IS_MULTI_CONFIG OR CMAKE_CONFIGURATION_TYPES)
  set(CEF_TARGET_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/$<CONFIGURATION>")
else()
  set(CEF_TARGET_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}")
endif()

# ---- shared sources ----
set(WV_SOURCES
  src/wv_shm.cpp
  src/wv_client.cpp
  src/wv_app.cpp
  src/wv_control.cpp
  src/wv_scheme.cpp
)

if(OS_MAC)
  # ---------------------------------------------------------------------------
  # Helper (sub-process) app — one helper is enough with no_sandbox.
  # ---------------------------------------------------------------------------
  add_executable(cef_host_helper MACOSX_BUNDLE src/helper_mac.mm)
  set_target_properties(cef_host_helper PROPERTIES
    OUTPUT_NAME "cef_host Helper"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/mac/helper-Info.plist.in"
  )
  SET_EXECUTABLE_TARGET_PROPERTIES(cef_host_helper)
  target_include_directories(cef_host_helper PRIVATE "${CEF_ROOT}" src)
  target_link_libraries(cef_host_helper libcef_dll_wrapper ${CEF_STANDARD_LIBS})

  # ---------------------------------------------------------------------------
  # Main browser-process app.
  # ---------------------------------------------------------------------------
  add_executable(cef_host MACOSX_BUNDLE src/main_mac.mm ${WV_SOURCES})
  set_target_properties(cef_host PROPERTIES
    OUTPUT_NAME "cef_host"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/mac/Info.plist.in"
  )
  SET_EXECUTABLE_TARGET_PROPERTIES(cef_host)
  target_include_directories(cef_host PRIVATE "${CEF_ROOT}" src)
  target_link_libraries(cef_host libcef_dll_wrapper ${CEF_STANDARD_LIBS})
  add_dependencies(cef_host cef_host_helper)

  set(APP "$<TARGET_BUNDLE_DIR:cef_host>")
  set(FRAMEWORK_SRC "${CEF_BINARY_DIR}/Chromium Embedded Framework.framework")

  # Assemble the bundle: framework + helper into Contents/Frameworks, then codesign.
  add_custom_command(TARGET cef_host POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${APP}/Contents/Frameworks"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${FRAMEWORK_SRC}"
            "${APP}/Contents/Frameworks/Chromium Embedded Framework.framework"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "$<TARGET_BUNDLE_DIR:cef_host_helper>"
            "${APP}/Contents/Frameworks/cef_host Helper.app"
    COMMAND codesign --force --sign - --timestamp=none
            "${APP}/Contents/Frameworks/Chromium Embedded Framework.framework"
    COMMAND codesign --force --sign - --timestamp=none
            "${APP}/Contents/Frameworks/cef_host Helper.app"
    COMMAND codesign --force --sign - --timestamp=none "${APP}"
    VERBATIM
  )
endif()

if(OS_WINDOWS)
  # ---------------------------------------------------------------------------
  # Single exe: with --single-process (see wv_app.cpp) CEF spawns no helper
  # processes; any stray sub-process re-execs this exe (CefExecuteProcess).
  # WIN32 subsystem so no console window appears when launched from Pharo.
  # ---------------------------------------------------------------------------
  add_executable(cef_host WIN32 src/main_win.cpp ${WV_SOURCES})
  SET_EXECUTABLE_TARGET_PROPERTIES(cef_host)
  ADD_LOGICAL_TARGET("libcef_lib" "${CEF_LIB_DEBUG}" "${CEF_LIB_RELEASE}")
  target_include_directories(cef_host PRIVATE "${CEF_ROOT}" src)
  target_link_libraries(cef_host libcef_lib libcef_dll_wrapper
                        ${CEF_STANDARD_LIBS} shell32)

  # Copy libcef.dll & friends plus icudtl.dat/.pak resources next to the exe.
  COPY_FILES("cef_host" "${CEF_BINARY_FILES}" "${CEF_BINARY_DIR}" "${CEF_TARGET_OUT_DIR}")
  COPY_FILES("cef_host" "${CEF_RESOURCE_FILES}" "${CEF_RESOURCE_DIR}" "${CEF_TARGET_OUT_DIR}")
endif()
