# iOS frontend. Builds a plain executable; scripts/ios/package-ipa.sh assembles the .app/.ipa around it.

add_executable(duckstation-ios
  ios_app.mm
  ios_host.h
  ios_host.mm
)

set_target_properties(duckstation-ios PROPERTIES OUTPUT_NAME "DuckStation")
set_source_files_properties(ios_app.mm ios_host.mm PROPERTIES
  COMPILE_FLAGS "-fobjc-arc"
  SKIP_PRECOMPILE_HEADERS TRUE
)

target_link_libraries(duckstation-ios PRIVATE core util common scmversion SDL2::SDL2)

target_link_libraries(duckstation-ios PRIVATE
  "-framework Foundation"
  "-framework UIKit"
  "-framework Metal"
  "-framework QuartzCore"
  "-framework CoreGraphics"
  "-framework GameController"
  "-framework UniformTypeIdentifiers"
  "-framework AVFoundation"
  "-framework AudioToolbox"
  "-framework CoreAudio"
  "-framework CoreMotion"
  "-framework CoreHaptics"
  "-framework CoreBluetooth"
  "-framework CoreFoundation"
  "-framework Security"
)

# Dylibs (shaderc, spirv-cross, soundtouch) are copied into App.app/Frameworks by the packaging script.
set_target_properties(duckstation-ios PROPERTIES
  BUILD_RPATH "@executable_path/Frameworks"
  INSTALL_RPATH "@executable_path/Frameworks"
)

# Builds Metal23.metallib next to the binary.
add_util_resources(duckstation-ios)

# Static libwebp depends on libsharpyuv, which FindWebP doesn't pull in.
find_library(SHARPYUV_LIBRARY sharpyuv)
if(SHARPYUV_LIBRARY)
  target_link_libraries(duckstation-ios PRIVATE "${SHARPYUV_LIBRARY}")
endif()
