#!/bin/bash
set -e

cd /Users/apple/AndroidStudioProjects/rustdesk

export ANDROID_NDK_HOME="/Users/apple/Library/Android/sdk/ndk/26.1.10909125"
export ANDROID_NDK="$ANDROID_NDK_HOME"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export VCPKG_ROOT="/Users/apple/vcpkg"

echo "Installing all VCPKG packages from vcpkg.json for arm64-android..."
echo "This will install: oboe, cpu-features, and other required packages"
echo ""

$VCPKG_ROOT/vcpkg install --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed"

echo ""
echo "✓ All VCPKG packages installed successfully!"

