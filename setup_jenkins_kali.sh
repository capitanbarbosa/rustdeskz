#!/bin/bash
set -e

# =============================================================================
# Jenkins + Android Build Environment Setup for Kali/Ubuntu Baremetal
# =============================================================================
# This installs Jenkins directly (no Docker) + all Android build dependencies
# After running this, you'll have a web panel at http://your-ip:8080
# =============================================================================

echo "=========================================="
echo "Jenkins + Android Build Setup for Kali"
echo "=========================================="

# Configuration
NDK_VERSION="26.1.10909125"
ANDROID_SDK_VERSION="11076708"

echo ""
echo "=== Step 1: Install System Dependencies ==="
sudo apt update
sudo apt install -y \
    openjdk-21-jdk \
    openjdk-17-jdk \
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
    gnupg \
    apt-transport-https \
    ca-certificates

echo ""
echo "=== Step 2: Install Jenkins ==="
# Add Jenkins repo
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
    https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
    "https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
    /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install -y jenkins

echo ""
echo "=== Step 3: Setup Android SDK (system-wide) ==="
ANDROID_HOME="/opt/android-sdk"
sudo mkdir -p "$ANDROID_HOME"
sudo chown -R jenkins:jenkins "$ANDROID_HOME"

# Download and extract cmdline-tools as jenkins user
cd /tmp
wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip" -O cmdline-tools.zip
sudo unzip -q -o cmdline-tools.zip -d "$ANDROID_HOME"
sudo mkdir -p "$ANDROID_HOME/cmdline-tools"
sudo mv "$ANDROID_HOME/cmdline-tools" "$ANDROID_HOME/cmdline-tools-tmp" 2>/dev/null || true
sudo mv "$ANDROID_HOME/cmdline-tools-tmp" "$ANDROID_HOME/cmdline-tools/latest" 2>/dev/null || \
    sudo mv "$ANDROID_HOME/cmdline" "$ANDROID_HOME/cmdline-tools/latest" 2>/dev/null || true
rm cmdline-tools.zip

# Set ownership
sudo chown -R jenkins:jenkins "$ANDROID_HOME"

# Install SDK components as jenkins user
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
sudo -u jenkins bash -c "
    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
    export ANDROID_HOME=$ANDROID_HOME
    export PATH=\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH
    yes | sdkmanager --licenses || true
    sdkmanager 'platform-tools' 'platforms;android-33' 'platforms;android-34' 'build-tools;33.0.2' 'build-tools;34.0.0' 'ndk;${NDK_VERSION}'
"

echo ""
echo "=== Step 4: Install Rust for Jenkins User ==="
sudo -u jenkins bash -c '
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.75.0
    source $HOME/.cargo/env
    rustup target add aarch64-linux-android
    cargo install cargo-ndk
    cargo install flutter_rust_bridge_codegen --version "1.80.1"
'

echo ""
echo "=== Step 5: Install Flutter for Jenkins User ==="
FLUTTER_HOME="/opt/flutter"
sudo mkdir -p "$FLUTTER_HOME"
sudo chown -R jenkins:jenkins "$FLUTTER_HOME"

sudo -u jenkins bash -c "
    git clone https://github.com/flutter/flutter.git $FLUTTER_HOME -b stable --depth 1
    export PATH=$FLUTTER_HOME/bin:\$PATH
    flutter config --android-sdk $ANDROID_HOME
    yes | flutter doctor --android-licenses || true
"

echo ""
echo "=== Step 6: Setup VCPKG for Jenkins User ==="
VCPKG_ROOT="/opt/vcpkg"
sudo mkdir -p "$VCPKG_ROOT"
sudo chown -R jenkins:jenkins "$VCPKG_ROOT"

sudo -u jenkins bash -c "
    git clone https://github.com/Microsoft/vcpkg.git $VCPKG_ROOT
    $VCPKG_ROOT/bootstrap-vcpkg.sh -disableMetrics
    mkdir -p $VCPKG_ROOT/installed/arm64-android/lib
"

echo ""
echo "=== Step 7: Download Prebuilt Libraries ==="
PREBUILT_DIR="/opt/prebuilt-libs/android-arm64"
sudo mkdir -p "$PREBUILT_DIR"
sudo chown -R jenkins:jenkins "/opt/prebuilt-libs"

sudo -u jenkins bash -c "
    cd $PREBUILT_DIR
    PREBUILT_URL='https://github.com/nicenote/nicenote.github.io/releases/download/1.0.0'
    for lib in libaom.a liboboe.a libopus.a libvpx.a libyuv.a libjpeg.a libturbojpeg.a; do
        wget -q \"\${PREBUILT_URL}/\${lib}\" -O \"\$lib\" 2>/dev/null || echo \"Warning: \$lib not found\"
    done
    cp -f *.a $VCPKG_ROOT/installed/arm64-android/lib/ 2>/dev/null || true
"

echo ""
echo "=== Step 8: Configure Jenkins Environment ==="
# Create environment file for Jenkins
sudo tee /etc/default/jenkins-env > /dev/null << 'EOF'
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ANDROID_HOME=/opt/android-sdk
ANDROID_SDK_ROOT=/opt/android-sdk
ANDROID_NDK_HOME=/opt/android-sdk/ndk/26.1.10909125
NDK_HOME=/opt/android-sdk/ndk/26.1.10909125
FLUTTER_HOME=/opt/flutter
VCPKG_ROOT=/opt/vcpkg
CARGO_HOME=/var/lib/jenkins/.cargo
RUSTUP_HOME=/var/lib/jenkins/.rustup
PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/var/lib/jenkins/.cargo/bin:/usr/local/bin:/usr/bin:/bin
EOF

# Source it in Jenkins profile
sudo tee -a /var/lib/jenkins/.bashrc > /dev/null << 'EOF'
source /etc/default/jenkins-env
export JAVA_HOME ANDROID_HOME ANDROID_SDK_ROOT ANDROID_NDK_HOME NDK_HOME FLUTTER_HOME VCPKG_ROOT CARGO_HOME RUSTUP_HOME PATH
EOF

sudo chown jenkins:jenkins /var/lib/jenkins/.bashrc

echo ""
echo "=== Step 9: Start Jenkins ==="
sudo systemctl enable jenkins
sudo systemctl restart jenkins

# Wait for Jenkins to start
echo "Waiting for Jenkins to start..."
sleep 10

echo ""
echo "=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Jenkins URL: http://$(hostname -I | awk '{print $1}'):8080"
echo ""
echo "Initial admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "(Jenkins still starting, run: sudo cat /var/lib/jenkins/secrets/initialAdminPassword)"
echo ""
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Open Jenkins in browser"
echo "2. Enter the initial admin password"
echo "3. Install suggested plugins"
echo "4. Create admin user"
echo "5. Create a new Pipeline job with the Jenkinsfile from the repo"
echo ""
echo "Environment variables are pre-configured for Android builds!"
echo "=========================================="

