#!/bin/bash
# Manual VCPKG installation script for Android
# Run this if the automatic installation in build_rust_lib.sh fails

set -e

# Make sure we're using bash
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

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

echo "Installing VCPKG packages for Android..."
echo "VCPKG_ROOT: $VCPKG_ROOT"
echo "ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
echo ""

# Set environment variables
export ANDROID_NDK_HOME
export ANDROID_NDK="$ANDROID_NDK_HOME"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

cd /Users/apple/AndroidStudioProjects/rustdesk

if [ ! -f "vcpkg.json" ]; then
    echo "ERROR: vcpkg.json not found in rustdesk root"
    exit 1
fi

echo "Running VCPKG install..."
echo ""
echo "Attempting installation with --classic mode (may bypass host tool detection issues)..."
echo "Command: $VCPKG_ROOT/vcpkg install opus libvpx libyuv --triplet arm64-android --x-install-root=\"$VCPKG_ROOT/installed\" --classic"
echo ""

# Try classic mode first (installs specific packages without manifest)
$VCPKG_ROOT/vcpkg install opus libvpx libyuv --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed" --classic

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Minimal packages (opus, libvpx, libyuv) installed successfully!"
    echo ""
    echo "Note: These are the essential packages needed for scrap and magnum-opus."
    echo "Additional packages from vcpkg.json (like ffmpeg) can be installed later if needed."
    echo "For now, we can proceed with the Rust build."
    INSTALL_RESULT=0
else
    echo ""
    echo "Classic mode failed. Trying manifest mode..."
    echo "Command: $VCPKG_ROOT/vcpkg install --triplet arm64-android --x-install-root=\"$VCPKG_ROOT/installed\""
    $VCPKG_ROOT/vcpkg install --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed"
    INSTALL_RESULT=$?
fi

echo ""
echo "✓ VCPKG packages installed successfully!"
echo "You can now run ./build_rust_lib.sh again."

