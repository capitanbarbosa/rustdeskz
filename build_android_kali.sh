#!/bin/bash
set -e

# =============================================================================
# RustDesk Android Build Script for Kali/Ubuntu Baremetal
# =============================================================================
# This script sets up all dependencies and builds the Android APK from scratch
# Run this on a fresh Kali/Ubuntu 24 system
# =============================================================================

echo "=========================================="
echo "RustDesk Android Build - Kali/Ubuntu Setup"
echo "=========================================="

# Configuration
ANDROID_SDK_VERSION="11076708"  # cmdline-tools version
NDK_VERSION="26.1.10909125"
FLUTTER_VERSION="3.24.5"
RUST_VERSION="1.75.0"
BUILD_DIR="$(pwd)"
TOOLS_DIR="$HOME/rustdesk-tools"

# Create tools directory
mkdir -p "$TOOLS_DIR"

echo ""
echo "=== Step 1: Install System Dependencies ==="
sudo apt update
sudo apt install -y \
    openjdk-21-jdk \
    git \
    curl \
    wget \
    unzip \
    zip \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    llvm \
    libclang-dev \
    gcc \
    g++ \
    nasm \
    yasm \
    libssl-dev \
    libasound2-dev \
    libpulse-dev \
    libva-dev \
    libvdpau-dev \
    libxcb1-dev \
    libxrandr-dev \
    libxfixes-dev

# Set JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
echo "JAVA_HOME: $JAVA_HOME"
java -version

echo ""
echo "=== Step 2: Install Android SDK ==="
export ANDROID_HOME="$TOOLS_DIR/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
    echo "Downloading Android SDK..."
    mkdir -p "$ANDROID_HOME"
    cd "$TOOLS_DIR"
    wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip" -O cmdline-tools.zip
    unzip -q cmdline-tools.zip
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    mv cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
    rm -f cmdline-tools.zip
    cd "$BUILD_DIR"
fi

export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Accept licenses
yes | sdkmanager --licenses || true

# Install required SDK components
echo "Installing SDK components..."
sdkmanager "platform-tools" \
    "platforms;android-33" \
    "platforms;android-34" \
    "build-tools;33.0.2" \
    "build-tools;34.0.0" \
    "ndk;${NDK_VERSION}"

export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/${NDK_VERSION}"
export NDK_HOME="$ANDROID_NDK_HOME"

echo "ANDROID_HOME: $ANDROID_HOME"
echo "ANDROID_NDK_HOME: $ANDROID_NDK_HOME"

echo ""
echo "=== Step 3: Install Rust ==="
if ! command -v rustup &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
fi
source "$HOME/.cargo/env"

rustup install $RUST_VERSION
rustup default $RUST_VERSION
rustup target add aarch64-linux-android

# Install cargo-ndk
cargo install cargo-ndk

echo "Rust: $(rustc --version)"

echo ""
echo "=== Step 4: Install Flutter ==="
export FLUTTER_HOME="$TOOLS_DIR/flutter"

if [ ! -d "$FLUTTER_HOME" ]; then
    echo "Downloading Flutter..."
    cd "$TOOLS_DIR"
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
    cd "$BUILD_DIR"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

flutter config --android-sdk "$ANDROID_HOME"
flutter doctor --android-licenses || true
flutter doctor

echo ""
echo "=== Step 5: Setup VCPKG ==="
export VCPKG_ROOT="$TOOLS_DIR/vcpkg"

if [ ! -d "$VCPKG_ROOT" ]; then
    git clone https://github.com/Microsoft/vcpkg.git "$VCPKG_ROOT"
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
fi

# Create vcpkg directories for prebuilt libs
mkdir -p "$VCPKG_ROOT/installed/arm64-android/lib"
mkdir -p "$VCPKG_ROOT/installed/arm64-android/lib/pkgconfig"

echo ""
echo "=== Step 6: Download Prebuilt Android Libraries ==="
PREBUILT_DIR="$BUILD_DIR/prebuilt_libs/android-arm64"
mkdir -p "$PREBUILT_DIR"

if [ ! -f "$PREBUILT_DIR/liboboe.a" ]; then
    echo "Downloading prebuilt libraries..."
    PREBUILT_URL="https://github.com/nicenote/nicenote.github.io/releases/download/1.0.0"
    
    cd "$PREBUILT_DIR"
    for lib in libaom.a liboboe.a libopus.a libvpx.a libyuv.a libjpeg.a libturbojpeg.a; do
        if [ ! -f "$lib" ]; then
            echo "  Downloading $lib..."
            wget -q "${PREBUILT_URL}/${lib}" -O "$lib" || echo "  Warning: Could not download $lib"
        fi
    done
    cd "$BUILD_DIR"
fi

# Copy prebuilt libs to vcpkg
echo "Copying prebuilt libraries to vcpkg..."
cp -f "$PREBUILT_DIR"/*.a "$VCPKG_ROOT/installed/arm64-android/lib/" 2>/dev/null || true

echo ""
echo "=== Step 7: Initialize Git Submodules ==="
cd "$BUILD_DIR"
git submodule update --init --recursive || true

echo ""
echo "=== Step 8: Setup Flutter Dependencies ==="
cd "$BUILD_DIR/flutter"
flutter pub get

echo ""
echo "=== Step 9: Generate Flutter-Rust Bridge ==="
cd "$BUILD_DIR"

# Install flutter_rust_bridge_codegen if needed
cargo install flutter_rust_bridge_codegen --version "1.80.1" || true

flutter_rust_bridge_codegen \
    --rust-input ./src/flutter_ffi.rs \
    --dart-output ./flutter/lib/generated_bridge.dart \
    --class-name Rustdesk || echo "Bridge generation had warnings (this is usually OK)"

echo ""
echo "=== Step 10: Build Rust Library for Android ARM64 ==="
cd "$BUILD_DIR"

# Clean oboe-sys cache
rm -rf target/aarch64-linux-android/release/build/oboe-sys-* 2>/dev/null || true

# Build with cargo-ndk
cargo ndk -t arm64-v8a -o flutter/android/app/src/main/jniLibs build --release

# Copy the library
mkdir -p flutter/android/app/src/main/jniLibs/arm64-v8a
cp -f target/aarch64-linux-android/release/liblibrustdesk.so flutter/android/app/src/main/jniLibs/arm64-v8a/librustdesk.so

# Copy libc++_shared.so
LIBCPP="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
if [ -f "$LIBCPP" ]; then
    cp -f "$LIBCPP" flutter/android/app/src/main/jniLibs/arm64-v8a/
fi

echo "Rust library built!"
ls -la flutter/android/app/src/main/jniLibs/arm64-v8a/

echo ""
echo "=== Step 11: Fix gradle.properties ==="
cd "$BUILD_DIR/flutter/android"

# Remove hardcoded macOS Java path and set Linux path
sed -i '/org.gradle.java.home=/d' gradle.properties 2>/dev/null || true
echo "org.gradle.java.home=$JAVA_HOME" >> gradle.properties

echo "gradle.properties:"
cat gradle.properties

echo ""
echo "=== Step 12: Build Flutter APK ==="
cd "$BUILD_DIR/flutter"

flutter pub get
flutter build apk --release --target-platform android-arm64

echo ""
echo "=== Step 13: Copy APK ==="
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
APK_PATH_SPLIT="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"

if [ -f "$APK_PATH" ]; then
    cp "$APK_PATH" "$BUILD_DIR/rustdesk-arm64.apk"
    echo ""
    echo "========================================"
    echo "BUILD SUCCESSFUL!"
    echo "========================================"
    echo "APK: $BUILD_DIR/rustdesk-arm64.apk"
    ls -lh "$BUILD_DIR/rustdesk-arm64.apk"
    echo "========================================"
elif [ -f "$APK_PATH_SPLIT" ]; then
    cp "$APK_PATH_SPLIT" "$BUILD_DIR/rustdesk-arm64.apk"
    echo ""
    echo "========================================"
    echo "BUILD SUCCESSFUL!"
    echo "========================================"
    echo "APK: $BUILD_DIR/rustdesk-arm64.apk"
    ls -lh "$BUILD_DIR/rustdesk-arm64.apk"
    echo "========================================"
else
    echo "ERROR: APK not found!"
    ls -la build/app/outputs/flutter-apk/ 2>/dev/null || echo "No APK output directory"
    exit 1
fi

