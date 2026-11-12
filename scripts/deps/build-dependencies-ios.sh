#!/usr/bin/env bash
# Builds DuckStation's third-party dependencies for iOS (arm64), installing into the given prefix.
# Mostly static libraries; shaderc/spirv-cross are dylibs because the core loads them at runtime,
# and soundtouch keeps its shared "DLL" target. Those dylibs are embedded in App.app/Frameworks.

set -e

if [ "$#" -ne 1 ]; then
  echo "Syntax: $0 <output directory>"
  exit 1
fi

INSTALLDIR="$1"
if [ "${INSTALLDIR:0:1}" != "/" ]; then
  INSTALLDIR="$PWD/$INSTALLDIR"
fi
mkdir -p "$INSTALLDIR"

NPROCS="$(sysctl -n hw.ncpu)"
IOS_MIN=15.0

FREETYPE=2.13.3
SDL2=2.30.6
ZSTD=1.5.6
LIBPNG=1.6.43
LIBJPEGTURBO=3.0.3
LIBWEBP=1.4.0

CPUINFO=7524ad504fdcfcf75a18a133da6abd75c5d48053
LUNASVG=9af1ac7b90658a279b372add52d6f77a4ebb482c
SHADERC=f60bb80e255144e71776e2ad570d89b78ea2ab4f
SOUNDTOUCH=463ade388f3a51da078dc9ed062bf28e4ba29da7
SPIRV_CROSS=vulkan-sdk-1.3.290.0

mkdir -p deps-build-ios
cd deps-build-ios

CMAKE_COMMON=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_MIN
  -DCMAKE_PREFIX_PATH="$INSTALLDIR"
  -DCMAKE_INSTALL_PREFIX="$INSTALLDIR"
  -DCMAKE_FIND_ROOT_PATH="$INSTALLDIR"
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
  -DCMAKE_INSTALL_NAME_DIR=@rpath
  -DCMAKE_MACOSX_BUNDLE=OFF
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
)

cat > SHASUMS <<EOF
0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289  freetype-$FREETYPE.tar.xz
6a5ca0652392a2d7c9db2ae5b40210843c0bbc081cbd410825ab00cc59f14a6c  libpng-$LIBPNG.tar.xz
343e789069fc7afbcdfe44dbba7dbbf45afa98a15150e079a38e60e44578865d  libjpeg-turbo-$LIBJPEGTURBO.tar.gz
61f873ec69e3be1b99535634340d5bde750b2e4447caa1db9f61be3fd49ab1e5  libwebp-$LIBWEBP.tar.gz
c6ef64ca18a19d13df6eb22df9aff19fb0db65610a74cc81dae33a82235cacd4  SDL2-$SDL2.tar.gz
8c29e06cf42aacc1eafc4077ae2ec6c6fcb96a626157e0593d5e82a34fd403c1  zstd-$ZSTD.tar.gz
e1351218d270db49c3dddcba04fb2153b09731ea3fa6830e423f5952f44585be  cpuinfo-$CPUINFO.tar.gz
3998b024b0d442614a9ee270e76e018bb37a17b8c6941212171731123cbbcac7  lunasvg-$LUNASVG.tar.gz
4c1780b6c65c27c4dcb109f08ab632241c98b77fe2e22be726c151ff514482bf  shaderc-$SHADERC.tar.gz
fe45c2af99f6102d2704277d392c1c83b55180a70bfd17fb888cc84a54b70573  soundtouch-$SOUNDTOUCH.tar.gz
EOF

curl -L --retry 3 \
  -o "freetype-$FREETYPE.tar.xz" "https://sourceforge.net/projects/freetype/files/freetype2/$FREETYPE/freetype-$FREETYPE.tar.xz/download" \
  -O "https://downloads.sourceforge.net/project/libpng/libpng16/$LIBPNG/libpng-$LIBPNG.tar.xz" \
  -O "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$LIBJPEGTURBO/libjpeg-turbo-$LIBJPEGTURBO.tar.gz" \
  -O "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$LIBWEBP.tar.gz" \
  -O "https://github.com/libsdl-org/SDL/releases/download/release-$SDL2/SDL2-$SDL2.tar.gz" \
  -O "https://github.com/facebook/zstd/releases/download/v$ZSTD/zstd-$ZSTD.tar.gz" \
  -o "cpuinfo-$CPUINFO.tar.gz" "https://github.com/stenzek/cpuinfo/archive/$CPUINFO.tar.gz" \
  -o "lunasvg-$LUNASVG.tar.gz" "https://github.com/stenzek/lunasvg/archive/$LUNASVG.tar.gz" \
  -o "shaderc-$SHADERC.tar.gz" "https://github.com/stenzek/shaderc/archive/$SHADERC.tar.gz" \
  -o "soundtouch-$SOUNDTOUCH.tar.gz" "https://github.com/stenzek/soundtouch/archive/$SOUNDTOUCH.tar.gz"

shasum -a 256 --check SHASUMS

if [ ! -d "SPIRV-Cross" ]; then
  git clone https://github.com/KhronosGroup/SPIRV-Cross/ -b $SPIRV_CROSS --depth 1
fi

echo "::group::zstd"
rm -fr "zstd-$ZSTD" && tar xf "zstd-$ZSTD.tar.gz" && cd "zstd-$ZSTD"
cmake "${CMAKE_COMMON[@]}" -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -B build-ios build/cmake
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::libpng"
rm -fr "libpng-$LIBPNG" && tar xf "libpng-$LIBPNG.tar.xz" && cd "libpng-$LIBPNG"
cmake "${CMAKE_COMMON[@]}" -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_EXECUTABLES=OFF -DPNG_FRAMEWORK=OFF -DPNG_ARM_NEON=on -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::libjpeg-turbo"
rm -fr "libjpeg-turbo-$LIBJPEGTURBO" && tar xf "libjpeg-turbo-$LIBJPEGTURBO.tar.gz" && cd "libjpeg-turbo-$LIBJPEGTURBO"
cmake "${CMAKE_COMMON[@]}" -DENABLE_STATIC=ON -DENABLE_SHARED=OFF -DWITH_SIMD=OFF -DWITH_TURBOJPEG=OFF -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::libwebp"
rm -fr "libwebp-$LIBWEBP" && tar xf "libwebp-$LIBWEBP.tar.gz" && cd "libwebp-$LIBWEBP"
cmake "${CMAKE_COMMON[@]}" -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF \
  -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::freetype"
rm -fr "freetype-$FREETYPE" && tar xf "freetype-$FREETYPE.tar.xz" && cd "freetype-$FREETYPE"
cmake "${CMAKE_COMMON[@]}" -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_ZLIB=TRUE -DFT_DISABLE_PNG=TRUE -DFT_DISABLE_BZIP2=TRUE \
  -DFT_DISABLE_BROTLI=TRUE -DFT_DISABLE_HARFBUZZ=TRUE -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::SDL2"
rm -fr "SDL2-$SDL2" && tar xf "SDL2-$SDL2.tar.gz" && cd "SDL2-$SDL2"
cmake "${CMAKE_COMMON[@]}" -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_TESTS=OFF -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::cpuinfo"
rm -fr "cpuinfo-$CPUINFO" && tar xf "cpuinfo-$CPUINFO.tar.gz" && cd "cpuinfo-$CPUINFO"
cmake "${CMAKE_COMMON[@]}" -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCPUINFO_LIBRARY_TYPE=static -DCPUINFO_RUNTIME_TYPE=static \
  -DCPUINFO_LOG_LEVEL=error -DCPUINFO_LOG_TO_STDIO=ON -DCPUINFO_BUILD_TOOLS=OFF -DCPUINFO_BUILD_UNIT_TESTS=OFF \
  -DCPUINFO_BUILD_MOCK_TESTS=OFF -DCPUINFO_BUILD_BENCHMARKS=OFF -DUSE_SYSTEM_LIBS=ON -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::lunasvg"
rm -fr "lunasvg-$LUNASVG" && tar xf "lunasvg-$LUNASVG.tar.gz" && cd "lunasvg-$LUNASVG"
cmake "${CMAKE_COMMON[@]}" -DBUILD_SHARED_LIBS=OFF -DLUNASVG_BUILD_EXAMPLES=OFF -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::soundtouch"
rm -fr "soundtouch-$SOUNDTOUCH" && tar xf "soundtouch-$SOUNDTOUCH.tar.gz" && cd "soundtouch-$SOUNDTOUCH"
cmake "${CMAKE_COMMON[@]}" -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::shaderc"
rm -fr "shaderc-$SHADERC" && tar xf "shaderc-$SHADERC.tar.gz" && cd "shaderc-$SHADERC"
cmake "${CMAKE_COMMON[@]}" -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
  -DSHADERC_SKIP_INSTALL=OFF -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON -DENABLE_GLSLANG_BINARIES=OFF \
  -DSPIRV_TOOLS_BUILD_STATIC=ON -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "::group::SPIRV-Cross"
cd SPIRV-Cross
rm -fr build-ios
cmake "${CMAKE_COMMON[@]}" -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF \
  -DSPIRV_CROSS_ENABLE_GLSL=ON -DSPIRV_CROSS_ENABLE_HLSL=OFF -DSPIRV_CROSS_ENABLE_MSL=ON -DSPIRV_CROSS_ENABLE_CPP=OFF \
  -DSPIRV_CROSS_ENABLE_REFLECT=OFF -DSPIRV_CROSS_ENABLE_C_API=ON -DSPIRV_CROSS_ENABLE_UTIL=ON -B build-ios
cmake --build build-ios --parallel "$NPROCS" && cmake --install build-ios
cd ..
echo "::endgroup::"

echo "Installed dylibs:"
ls -la "$INSTALLDIR"/lib/*.dylib || true
