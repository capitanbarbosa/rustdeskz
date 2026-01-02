#!/bin/bash
# Install missing VCPKG packages (aom, ffmpeg) for Android

set -e

VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/Users/apple/Library/Android/sdk/ndk/26.1.10909125}"

if [ ! -d "$VCPKG_ROOT" ]; then
    echo "ERROR: VCPKG_ROOT not set or VCPKG not found at $VCPKG_ROOT"
    exit 1
fi

if [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "ERROR: Android NDK not found at $ANDROID_NDK_HOME"
    exit 1
fi

echo "Installing missing VCPKG packages: aom, ffmpeg"
echo "VCPKG_ROOT: $VCPKG_ROOT"
echo "ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
echo ""

# Set environment variables
export ANDROID_NDK_HOME
export ANDROID_NDK="$ANDROID_NDK_HOME"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

cd /Users/apple/AndroidStudioProjects/rustdesk

# Find VCPKG executable
VCPKG_CMD=""
if [ -f "$VCPKG_ROOT/vcpkg" ]; then
    VCPKG_CMD="$VCPKG_ROOT/vcpkg"
elif command -v vcpkg > /dev/null 2>&1; then
    VCPKG_CMD="vcpkg"
else
    echo "ERROR: vcpkg executable not found"
    exit 1
fi

echo "Installing aom and ffmpeg for arm64-android..."
echo "This may take a long time (especially ffmpeg)..."
echo ""

$VCPKG_CMD install aom ffmpeg --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed" --classic

echo ""
echo "✓ Packages installed successfully!"
echo "You can now run ./build_rust_lib.sh again."

