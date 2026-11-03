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
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
#
# libgcc_s goes first, ahead of the Flutter engine and every plugin (#478).
# Since flutter/flutter#192607 (a clang roll, 2026-09-12), master builds of
# libflutter_linux_gtk.so export LLVM libunwind's `_Unwind_*` / `unw_*`
# symbols. Whichever library comes first in the executable's DT_NEEDED list
# provides those for the whole process, so the engine's copies shadowed
# libgcc_s's. glibc's pthread_cancel unwinds with libgcc_s, whose personality
# routine then called into libunwind with a libgcc context and crashed
# (SIGSEGV in unw_get_proc_info). PipeWire cancels its loop thread whenever
# libYSE closes the audio device, so every engine restart and every exit
# crashed. Listing libgcc_s first restores the system unwinder for all
# libraries. integration_test/control_plane_real_bus_tap_test.dart is the
# end-to-end guard. Remove this once the engine stops exporting those
# symbols (check with
# `nm -D --defined-only libflutter_linux_gtk.so | grep _Unwind_`).
target_link_libraries(${BINARY_NAME} PRIVATE
  "-Wl,--push-state,--no-as-needed" gcc_s "-Wl,--pop-state")
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
