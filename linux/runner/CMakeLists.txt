cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "window_chrome.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Optional native pixel regression, separate from the ordinary app build.
option(BUILD_LINUX_WINDOW_TESTS "Build GTK rounded-window pixel checks" OFF)
if(BUILD_LINUX_WINDOW_TESTS)
  pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
  add_executable(${BINARY_NAME}_window_frame_test "window_frame_test.cc")
  apply_standard_settings(${BINARY_NAME}_window_frame_test)
  target_link_libraries(${BINARY_NAME}_window_frame_test
    PRIVATE PkgConfig::GTK PkgConfig::EPOXY)
endif()
