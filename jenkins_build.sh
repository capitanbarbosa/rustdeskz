#!/bin/bash
set -e

echo "=== RustDesk Android Build Script ==="
echo "Running in: $(pwd)"
echo "Home: $HOME"

# === Configuration ===
export FLUTTER_VERSION="3.24.5"
export RUST_VERSION="1.75"
export NDK_VERSION="26.1.10909125"

# Use the SDK you already installed
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
export ANDROID_HOME="/var/jenkins_home/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${NDK_VERSION}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME}"
export ANDROID_NDK="${ANDROID_NDK_HOME}"

# Tools directory for Flutter, Rust, vcpkg
export TOOLS_DIR="$HOME/tools"
export FLUTTER_HOME="$TOOLS_DIR/flutter"
export CARGO_HOME="$TOOLS_DIR/.cargo"
export RUSTUP_HOME="$TOOLS_DIR/.rustup"
export VCPKG_ROOT="$TOOLS_DIR/vcpkg"

mkdir -p "$TOOLS_DIR"

# Update PATH
export PATH="$JAVA_HOME/bin:$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$CARGO_HOME/bin:$PATH"

# Fix bindgen to use NDK sysroot instead of host sysroot
NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${NDK_SYSROOT} -I${NDK_SYSROOT}/usr/include -I${NDK_SYSROOT}/usr/include/aarch64-linux-android"

echo "JAVA_HOME: $JAVA_HOME"
echo "ANDROID_HOME: $ANDROID_HOME"
echo "ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
echo "VCPKG_ROOT: $VCPKG_ROOT"

echo "=== Step 1: Verify Environment ==="
java -version
echo "NDK location: $(ls $ANDROID_NDK_HOME 2>/dev/null | head -3 || echo 'NOT FOUND')"

echo "=== Step 1b: Initialize Git Submodules ==="
cd "$WORKSPACE"
git submodule update --init --recursive
echo "Submodules initialized!"

echo "=== Step 2: Install Rust ==="
if [ ! -f "$CARGO_HOME/env" ]; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
source "$CARGO_HOME/env"

rustup default ${RUST_VERSION} 2>/dev/null || rustup install ${RUST_VERSION}
rustup default ${RUST_VERSION}
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 3.1.2 --locked 2>/dev/null || true

echo "Rust: $(rustc --version)"

echo "=== Step 3: Install Flutter ==="
if [ ! -d "${FLUTTER_HOME}" ]; then
    echo "Downloading Flutter ${FLUTTER_VERSION}..."
    cd "$TOOLS_DIR"
    wget -q --show-progress https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    rm flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
fi

flutter config --android-sdk ${ANDROID_HOME} 2>/dev/null || true
yes | flutter doctor --android-licenses 2>/dev/null || true

echo "=== Step 4: Setup VCPKG with prebuilt libs ==="
# Remove incomplete vcpkg if it exists without the binary
if [ -d "${VCPKG_ROOT}" ] && [ ! -f "${VCPKG_ROOT}/vcpkg" ]; then
    echo "Removing incomplete vcpkg installation..."
    rm -rf "${VCPKG_ROOT}"
fi

if [ ! -d "${VCPKG_ROOT}" ]; then
    echo "Cloning vcpkg..."
    cd "$TOOLS_DIR"
    git clone https://github.com/microsoft/vcpkg.git --depth=1
    cd vcpkg
    ./bootstrap-vcpkg.sh -disableMetrics
fi

echo "=== Step 5: Download prebuilt Android dependencies ==="
cd "$TOOLS_DIR"

# Use RustDesk's prebuilt third-party libraries
if [ ! -d "rustdesk_thirdparty_lib" ]; then
    echo "Cloning prebuilt libraries..."
    git clone https://github.com/rustdesk-org/rustdesk_thirdparty_lib.git --depth=1
fi

# Copy prebuilt vcpkg packages
echo "Copying prebuilt libraries to vcpkg..."
mkdir -p "$VCPKG_ROOT/installed"
if [ -d "rustdesk_thirdparty_lib/vcpkg/installed" ]; then
    cp -rf rustdesk_thirdparty_lib/vcpkg/installed/* "$VCPKG_ROOT/installed/" 2>/dev/null || true
fi

# Verify libraries exist
echo "Checking for prebuilt libraries..."
ls -la "$VCPKG_ROOT/installed/arm64-android/lib/" 2>/dev/null || {
    echo "Prebuilt libs not available, building with vcpkg..."
    cd "$WORKSPACE"
    $VCPKG_ROOT/vcpkg install opus libvpx libyuv --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed" || true
}

echo "=== Step 6: Setup Flutter Dependencies ==="
cd "$WORKSPACE/flutter"
flutter pub get

echo "=== Step 6b: Generate Flutter-Rust Bridge ==="
cd "$WORKSPACE"

# Install flutter_rust_bridge_codegen if not present
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked 2>/dev/null || true

# Always regenerate bridge files to ensure they're up to date
echo "Generating Flutter-Rust bridge files..."
$CARGO_HOME/bin/flutter_rust_bridge_codegen \
    --rust-input ./src/flutter_ffi.rs \
    --dart-output ./flutter/lib/generated_bridge.dart

# Verify the bridge file was created
if [ -f "src/bridge_generated.rs" ]; then
    echo "Bridge files generated successfully!"
    ls -la src/bridge_generated.rs
else
    echo "ERROR: bridge_generated.rs was not created!"
    exit 1
fi

echo "=== Step 7: Build Rust Library for ARM64 ==="
cd "$WORKSPACE"

echo "Building Rust library with cargo-ndk..."
# Build from project root with flutter feature (mediacodec has broken code in this fork)
cargo ndk --platform 21 --target aarch64-linux-android build --release --features flutter

# Copy library to jniLibs
mkdir -p flutter/android/app/src/main/jniLibs/arm64-v8a
cp target/aarch64-linux-android/release/liblibrustdesk.so flutter/android/app/src/main/jniLibs/arm64-v8a/librustdesk.so
echo "Rust library copied!"

# Copy libc++_shared.so
LIBCPP="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
if [ -f "$LIBCPP" ]; then
    cp "$LIBCPP" flutter/android/app/src/main/jniLibs/arm64-v8a/
    echo "libc++_shared.so copied!"
fi

echo "=== Step 8: Build Flutter APK ==="
cd "$WORKSPACE/flutter"
# Increase Gradle memory
sed -i "s/org.gradle.jvmargs=-Xmx1024M/org.gradle.jvmargs=-Xmx4g/g" android/gradle.properties 2>/dev/null || true

flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi

echo "=== Step 9: Copy APK ==="
APK_PATH="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
if [ -f "$APK_PATH" ]; then
    cp "$APK_PATH" "$WORKSPACE/rustdesk-arm64.apk"
    echo ""
    echo "========================================"
    echo "BUILD SUCCESSFUL!"
    echo "========================================"
    echo "APK: $WORKSPACE/rustdesk-arm64.apk"
    ls -lh "$WORKSPACE/rustdesk-arm64.apk"
    echo "========================================"
else
    echo "ERROR: APK not found at $APK_PATH"
    ls -la build/app/outputs/flutter-apk/ 2>/dev/null || echo "No APK output directory"
    exit 1
fi
