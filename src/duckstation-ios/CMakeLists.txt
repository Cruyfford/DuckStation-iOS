# iOS frontend: the ARMSX2 SwiftUI interface (GPL-3.0, see ui/COPYING.GPLv3 and ui/ARMSX2_COMMIT)
# driving DuckStation through ui/Bridge/DSBridge.mm. Builds a plain executable; scripts/ios/package-ipa.sh
# assembles the .app/.ipa (assets, asset catalog, localizations) around it.

enable_language(Swift)

set(UI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ui")

file(GLOB_RECURSE SWIFT_SOURCES CONFIGURE_DEPENDS "${UI_DIR}/Swift/*.swift")
if(NOT SWIFT_SOURCES)
  message(FATAL_ERROR "No Swift sources found in ${UI_DIR}/Swift")
endif()

# Every ARMSX2Bridge method DSBridge.mm doesn't implement gets a generated default.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(BRIDGE_STUBS "${CMAKE_CURRENT_BINARY_DIR}/ARMSX2Bridge+Stubs.mm")
add_custom_command(
  OUTPUT "${BRIDGE_STUBS}"
  COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/scripts/ios/gen_bridge_stubs.py"
          "${UI_DIR}/Bridge/ARMSX2Bridge.h" "${UI_DIR}/Bridge/DSBridge.mm" "${BRIDGE_STUBS}"
  DEPENDS "${PROJECT_SOURCE_DIR}/scripts/ios/gen_bridge_stubs.py" "${UI_DIR}/Bridge/ARMSX2Bridge.h"
          "${UI_DIR}/Bridge/DSBridge.mm"
  COMMENT "Generating ARMSX2Bridge stubs"
)

set(OBJC_SOURCES
  ios_host.mm
  "${UI_DIR}/Bridge/DSBridge.mm"
  "${UI_DIR}/Bridge/DSCheats.mm"
  "${BRIDGE_STUBS}"
  "${UI_DIR}/Runtime/DSRuntime.mm"
)

add_executable(duckstation-ios ${OBJC_SOURCES} ios_host.h ${SWIFT_SOURCES})

set_target_properties(duckstation-ios PROPERTIES
  OUTPUT_NAME "DuckStation"
  Swift_MODULE_NAME "DuckStation"
  # One object per Swift file, which the clang++ link step below expects.
  Swift_COMPILATION_MODE "incremental"
  BUILD_RPATH "@executable_path/Frameworks"
  INSTALL_RPATH "@executable_path/Frameworks"
)

set_source_files_properties(${OBJC_SOURCES} PROPERTIES
  COMPILE_FLAGS "-fobjc-arc -fmodules"
  SKIP_PRECOMPILE_HEADERS TRUE
)

target_include_directories(duckstation-ios PRIVATE "${UI_DIR}/Bridge" "${CMAKE_CURRENT_SOURCE_DIR}")

# Swift: language mode 6 like ARMSX2, ObjC bridge exposed through the bridging header.
target_compile_options(duckstation-ios PRIVATE
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-swift-version 6>"
  "$<$<COMPILE_LANGUAGE:Swift>:-O>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-import-objc-header ${UI_DIR}/Bridge/ARMSX2-Bridging-Header.h>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${UI_DIR}/Bridge>"
)

target_link_libraries(duckstation-ios PRIVATE core util common scmversion SDL2::SDL2)

target_link_libraries(duckstation-ios PRIVATE
  "-lc++"
  "-framework Foundation"
  "-framework UIKit"
  "-framework SwiftUI"
  "-framework Combine"
  "-framework Metal"
  "-framework MetalKit"
  "-framework QuartzCore"
  "-framework CoreGraphics"
  "-framework ImageIO"
  "-framework GameController"
  "-framework UniformTypeIdentifiers"
  "-framework PhotosUI"
  "-framework AVKit"
  "-framework AVFoundation"
  "-framework AudioToolbox"
  "-framework CoreAudio"
  "-framework CoreMotion"
  "-framework CoreHaptics"
  "-framework CoreBluetooth"
  "-framework CoreFoundation"
  "-framework CryptoKit"
  "-framework Security"
)

# Link with clang++ (swiftc rejects -Wl,-framework,... flags from SDL's static target) and point it at
# the Swift runtime/compat libraries that the Swift objects auto-link.
set_target_properties(duckstation-ios PROPERTIES LINKER_LANGUAGE CXX)
execute_process(COMMAND xcrun --sdk iphoneos --show-sdk-path OUTPUT_VARIABLE IOS_SDK_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND xcrun --sdk iphoneos --find swiftc OUTPUT_VARIABLE SWIFTC_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)
get_filename_component(SWIFT_TOOLCHAIN_BIN "${SWIFTC_PATH}" DIRECTORY)
target_link_options(duckstation-ios PRIVATE
  "-L${IOS_SDK_PATH}/usr/lib/swift"
  "-L${SWIFT_TOOLCHAIN_BIN}/../lib/swift/iphoneos"
  "-Wl,-rpath,/usr/lib/swift"
)

# Static libwebp depends on libsharpyuv, which FindWebP doesn't pull in.
find_library(SHARPYUV_LIBRARY sharpyuv)
if(SHARPYUV_LIBRARY)
  target_link_libraries(duckstation-ios PRIVATE "${SHARPYUV_LIBRARY}")
endif()

# Builds Metal23.metallib next to the binary.
add_util_resources(duckstation-ios)
