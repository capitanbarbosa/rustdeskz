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

# Tools directory for Flutter and Rust
export TOOLS_DIR="$HOME/tools"
export FLUTTER_HOME="$TOOLS_DIR/flutter"
export CARGO_HOME="$TOOLS_DIR/.cargo"
export RUSTUP_HOME="$TOOLS_DIR/.rustup"

mkdir -p "$TOOLS_DIR"

# Update PATH
export PATH="$JAVA_HOME/bin:$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$CARGO_HOME/bin:$PATH"

echo "JAVA_HOME: $JAVA_HOME"
echo "ANDROID_HOME: $ANDROID_HOME"
echo "ANDROID_NDK_HOME: $ANDROID_NDK_HOME"

echo "=== Step 1: Verify Environment ==="
java -version
echo "NDK location: $(ls $ANDROID_NDK_HOME 2>/dev/null | head -3 || echo 'NOT FOUND')"

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
flutter doctor -v || true

echo "=== Step 4: Build Rust Library for ARM64 ==="
cd "$WORKSPACE/flutter"

echo "Building Rust library with cargo-ndk..."
cargo ndk -t arm64-v8a build --release

# Copy library to jniLibs
mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp ../target/aarch64-linux-android/release/liblibrustdesk.so android/app/src/main/jniLibs/arm64-v8a/librustdesk.so 2>/dev/null || true

# Copy libc++_shared.so
LIBCPP="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
if [ -f "$LIBCPP" ]; then
    cp "$LIBCPP" android/app/src/main/jniLibs/arm64-v8a/
    echo "libc++_shared.so copied!"
fi

echo "=== Step 5: Build Flutter APK ==="
# Increase Gradle memory
sed -i "s/org.gradle.jvmargs=-Xmx1024M/org.gradle.jvmargs=-Xmx4g/g" android/gradle.properties 2>/dev/null || true

flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi

echo "=== Step 6: Copy APK ==="
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
