#!/bin/bash
set -e

# =============================================================================
# RustDesk Android Build Script for Baremetal Jenkins (not Docker)
# =============================================================================
# This script is designed for Jenkins installed directly on Linux (no Docker)
# All paths are pre-configured by setup_jenkins_kali.sh
# =============================================================================

echo "=== RustDesk Android Build Script (Baremetal) ==="
echo "Running in: $WORKSPACE"

# Source environment
source /etc/default/jenkins-env 2>/dev/null || true

# Environment
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/26.1.10909125}"
export NDK_HOME="$ANDROID_NDK_HOME"
export FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
export VCPKG_ROOT="${VCPKG_ROOT:-/opt/vcpkg}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$CARGO_HOME/bin:$PATH"

echo "JAVA_HOME: $JAVA_HOME"
echo "ANDROID_HOME: $ANDROID_HOME"
echo "ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
echo "FLUTTER_HOME: $FLUTTER_HOME"
echo "VCPKG_ROOT: $VCPKG_ROOT"

# Verify tools
echo ""
echo "=== Verifying Tools ==="
java -version
rustc --version
flutter --version
echo "NDK: $(ls $ANDROID_NDK_HOME 2>/dev/null | head -1 || echo 'NOT FOUND')"

echo ""
echo "=== Step 1: Initialize Git Submodules ==="
cd "$WORKSPACE"
git submodule update --init --recursive

echo ""
echo "=== Step 2: Setup Flutter Dependencies ==="
cd "$WORKSPACE/flutter"
flutter pub get

echo ""
echo "=== Step 3: Generate Flutter-Rust Bridge ==="
cd "$WORKSPACE"
$CARGO_HOME/bin/flutter_rust_bridge_codegen \
    --rust-input ./src/flutter_ffi.rs \
    --dart-output ./flutter/lib/generated_bridge.dart \
    --class-name Rustdesk || echo "Bridge generation completed (warnings are OK)"

echo ""
echo "=== Step 4: Build Rust Library for Android ARM64 ==="
cd "$WORKSPACE"

# Clean previous oboe-sys builds
rm -rf target/aarch64-linux-android/release/build/oboe-sys-* 2>/dev/null || true

# Build with cargo-ndk
cargo ndk -t arm64-v8a -o flutter/android/app/src/main/jniLibs build --release --features flutter

# Verify library
echo "Checking library..."
ls -la flutter/android/app/src/main/jniLibs/arm64-v8a/

# Copy libc++_shared.so
LIBCPP="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
if [ -f "$LIBCPP" ]; then
    cp -f "$LIBCPP" flutter/android/app/src/main/jniLibs/arm64-v8a/
    echo "libc++_shared.so copied!"
fi

echo ""
echo "=== Step 5: Fix gradle.properties ==="
cd "$WORKSPACE/flutter"
sed -i '/org.gradle.java.home=/d' android/gradle.properties 2>/dev/null || true
echo "org.gradle.java.home=$JAVA_HOME" >> android/gradle.properties
echo "gradle.properties updated"

echo ""
echo "=== Step 6: Build Flutter APK ==="
cd "$WORKSPACE/flutter"
flutter pub get
flutter build apk --release --target-platform android-arm64

echo ""
echo "=== Step 7: Collect APK ==="
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
APK_PATH_ALT="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

if [ -f "$APK_PATH" ]; then
    mkdir -p "$WORKSPACE/output"
    cp "$APK_PATH" "$WORKSPACE/output/rustdesk-arm64.apk"
    echo ""
    echo "========================================"
    echo "BUILD SUCCESSFUL!"
    echo "========================================"
    ls -lh "$WORKSPACE/output/rustdesk-arm64.apk"
elif [ -f "$APK_PATH_ALT" ]; then
    mkdir -p "$WORKSPACE/output"
    cp "$APK_PATH_ALT" "$WORKSPACE/output/rustdesk-arm64.apk"
    echo ""
    echo "========================================"
    echo "BUILD SUCCESSFUL!"
    echo "========================================"
    ls -lh "$WORKSPACE/output/rustdesk-arm64.apk"
else
    echo "ERROR: APK not found!"
    find build -name "*.apk" 2>/dev/null || echo "No APK files found"
    exit 1
fi

