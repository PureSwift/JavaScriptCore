#!/bin/sh
# Builds JavaScriptCore alone (WebKit's JSCOnly port) from a WebKit release,
# and installs it where the package finds it: the shared library, the C API's
# headers, and a pkg-config file named javascriptcore.
#
#   Scripts/build-engine.sh [prefix] [-- cmake arguments]
#
# The prefix defaults to /usr/local. What follows -- goes to CMake, which is
# where a cross build names its toolchain file. From the environment:
#
#   WEBKIT_VERSION  the WPE WebKit release to build
#   WEBKIT_SHA256   that release's checksum
#   WORK            where to download and build (.build/engine)
#   JOBS            parallel compile jobs (all processors)
#
# Needs CMake, Ninja, a C++23 compiler, Ruby, Perl, Python 3 and ICU's
# headers.
set -eu

version=${WEBKIT_VERSION:-2.54.3}
sha256=${WEBKIT_SHA256:-787afd32ae23eac061621465390f44a462e874a9ebaba0b65521d7237fa8a5e4}

prefix=/usr/local
if [ $# -gt 0 ] && [ "$1" != -- ]; then
    prefix=$1
    shift
fi
[ $# -gt 0 ] && [ "$1" = -- ] && shift

root=$(cd "$(dirname "$0")/.." && pwd)
work=${WORK:-$root/.build/engine}
archive=$work/wpewebkit-$version.tar.xz
source=$work/wpewebkit-$version
build=$work/build-$version

mkdir -p "$work"
if [ ! -f "$archive" ]; then
    curl -fL -o "$archive.part" "https://wpewebkit.org/releases/wpewebkit-$version.tar.xz"
    mv "$archive.part" "$archive"
fi
echo "$sha256  $archive" | sha256sum -c -

# Only the engine's own sources: the rest of WebKit is most of the archive.
if [ ! -f "$source/CMakeLists.txt" ]; then
    tar -xf "$archive" -C "$work" \
        "wpewebkit-$version/CMakeLists.txt" \
        "wpewebkit-$version/Source/CMakeLists.txt" \
        "wpewebkit-$version/Source/cmake" \
        "wpewebkit-$version/Source/bmalloc" \
        "wpewebkit-$version/Source/WTF" \
        "wpewebkit-$version/Source/JavaScriptCore" \
        "wpewebkit-$version/Source/ThirdParty/unifdef" \
        "wpewebkit-$version/Source/ThirdParty/gtest" \
        "wpewebkit-$version/Tools"
fi

cmake -S "$source" -B "$build" -G Ninja \
    -DPORT=JSCOnly \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DLIB_INSTALL_DIR="$prefix/lib" \
    -DDEVELOPER_MODE=OFF \
    "$@"
# The library alone: the port also configures its shell and its tests.
cmake --build "$build" --target JavaScriptCore ${JOBS:+-j "$JOBS"}
cmake --install "$build"

# The port installs the library alone.
mkdir -p "$prefix/include/JavaScriptCore" "$prefix/lib/pkgconfig"
for header in JavaScript JSBase JSContextRef JSObjectRef JSStringRef JSTypedArray JSValueRef WebKitAvailability; do
    cp "$source/Source/JavaScriptCore/API/$header.h" "$prefix/include/JavaScriptCore/"
done
cat > "$prefix/lib/pkgconfig/javascriptcore.pc" <<EOF
prefix=$prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: JavaScriptCore
Description: WebKit's JavaScript engine, built alone
Version: $version
Libs: -L\${libdir} -lJavaScriptCore
Cflags: -I\${includedir}
EOF
