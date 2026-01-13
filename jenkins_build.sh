#!/bin/bash
set -e

echo "=== RustDesk Android Build Script (No Sudo) ==="
echo "Running in: $(pwd)"
echo "Home: $HOME"

# === Configuration ===
export FLUTTER_VERSION="3.24.5"
export RUST_VERSION="1.75"
export NDK_VERSION="26.1.10909125"
export CMDLINE_TOOLS_VERSION="11076708"

# All tools go in Jenkins home (user space, no sudo needed)
export TOOLS_DIR="$HOME/tools"
export ANDROID_HOME="$TOOLS_DIR/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export FLUTTER_HOME="$TOOLS_DIR/flutter"
export CARGO_HOME="$TOOLS_DIR/.cargo"
export RUSTUP_HOME="$TOOLS_DIR/.rustup"

# Create tools directory
mkdir -p "$TOOLS_DIR"

# Update PATH
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$CARGO_HOME/bin:$PATH"

echo "=== Step 1: Check/Install Java ==="
if command -v java &> /dev/null; then
    java -version
    echo "Java is available"
else
    echo "ERROR: Java not found. Your Jenkins Docker image needs Java 17."
    echo "Consider using a different Jenkins image like jenkins/jenkins:lts-jdk17"
    exit 1
fi

echo "=== Step 2: Install Android SDK ==="
mkdir -p "${ANDROID_HOME}/cmdline-tools"
if [ ! -d "${ANDROID_HOME}/cmdline-tools/latest" ]; then
    echo "Downloading Android command-line tools..."
    cd /tmp
    wget -q --show-progress https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip -O cmdline-tools.zip
    unzip -q -o cmdline-tools.zip
    rm -rf ${ANDROID_HOME}/cmdline-tools/latest
    mv cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest
    rm cmdline-tools.zip
    echo "Android command-line tools installed!"
else
    echo "Android command-line tools already installed"
fi

echo "=== Step 3: Install SDK Components ==="
export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:$PATH"
yes | sdkmanager --licenses 2>/dev/null || true
sdkmanager "platform-tools" 2>/dev/null || true
sdkmanager "platforms;android-34" 2>/dev/null || true
sdkmanager "build-tools;34.0.0" 2>/dev/null || true
sdkmanager "ndk;${NDK_VERSION}" 2>/dev/null || true
echo "SDK components installed!"

echo "=== Step 4: Install Rust ==="
if [ ! -f "$CARGO_HOME/env" ]; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
source "$CARGO_HOME/env"

# Install/update Rust version
rustup default ${RUST_VERSION} 2>/dev/null || rustup install ${RUST_VERSION}
rustup default ${RUST_VERSION}

# Add Android targets
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi

# Install cargo-ndk
cargo install cargo-ndk --version 3.1.2 --locked 2>/dev/null || true

echo "Rust installed: $(rustc --version)"

echo "=== Step 5: Install Flutter ==="
if [ ! -d "${FLUTTER_HOME}" ]; then
    echo "Downloading Flutter ${FLUTTER_VERSION}..."
    cd "$TOOLS_DIR"
    wget -q --show-progress https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    rm flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    echo "Flutter installed!"
else
    echo "Flutter already installed"
fi

export PATH="${FLUTTER_HOME}/bin:$PATH"
flutter config --android-sdk ${ANDROID_HOME} 2>/dev/null || true
yes | flutter doctor --android-licenses 2>/dev/null || true
flutter doctor -v || true

echo "=== Step 6: Generate Bridge (if needed) ==="
cd "$WORKSPACE"
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid 2>/dev/null || true

if [ ! -f "flutter/lib/generated_bridge.dart" ]; then
    echo "Generating bridge file..."
    cd flutter
    flutter_rust_bridge_codegen \
        --rust-input ../src/flutter_ffi.rs \
        --dart-output ./lib/generated_bridge.dart \
        --c-output ./ios/Runner/bridge_generated.h 2>/dev/null || echo "Bridge generation skipped (may already exist)"
    cd ..
fi

echo "=== Step 7: Build Rust Library for ARM64 ==="
cd "$WORKSPACE"
export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${NDK_VERSION}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME}"

cd flutter
echo "Building Rust library..."
if [ -f "ndk_arm64.sh" ]; then
    chmod +x ndk_arm64.sh
    ./ndk_arm64.sh || cargo ndk -t arm64-v8a build --release
else
    cargo ndk -t arm64-v8a build --release
fi

# Copy library to jniLibs
mkdir -p android/app/src/main/jniLibs/arm64-v8a
if [ -f "../target/aarch64-linux-android/release/liblibrustdesk.so" ]; then
    cp ../target/aarch64-linux-android/release/liblibrustdesk.so android/app/src/main/jniLibs/arm64-v8a/librustdesk.so
    echo "Rust library copied!"
fi

# Copy libc++_shared.so
LIBCPP="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
if [ -f "$LIBCPP" ]; then
    cp "$LIBCPP" android/app/src/main/jniLibs/arm64-v8a/
    echo "libc++_shared.so copied!"
fi

echo "=== Step 8: Build Flutter APK ==="
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
    ls -la build/app/outputs/flutter-apk/ || true
    exit 1
fi

