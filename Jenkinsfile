pipeline {
    agent any

    environment {
        // Version info
        VERSION = "1.4.4"
        
        // Tool versions (match the GitHub workflow)
        FLUTTER_VERSION = "3.24.5"
        RUST_VERSION = "1.75"
        NDK_VERSION = "26.1.10909125"
        CARGO_NDK_VERSION = "3.1.2"
        CMDLINE_TOOLS_VERSION = "11076708"  // Android command-line tools
        
        // Paths - everything goes in Jenkins home
        ANDROID_HOME = "${HOME}/android-sdk"
        ANDROID_SDK_ROOT = "${HOME}/android-sdk"
        FLUTTER_HOME = "${HOME}/flutter"
        VCPKG_ROOT = "${HOME}/vcpkg"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install System Dependencies') {
            steps {
                sh '''
                    echo "=== Installing system dependencies ==="
                    sudo apt-get update
                    sudo apt-get install -y \
                        clang cmake curl gcc-multilib git g++ g++-multilib \
                        libclang-dev nasm ninja-build pkg-config wget unzip \
                        openjdk-17-jdk-headless libssl-dev
                    
                    # Set JAVA_HOME
                    echo "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> $WORKSPACE/.env
                '''
            }
        }

        stage('Install Android SDK & NDK') {
            steps {
                sh '''
                    echo "=== Setting up Android SDK ==="
                    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
                    
                    # Create SDK directory
                    mkdir -p ${ANDROID_HOME}/cmdline-tools
                    
                    # Download command-line tools if not present
                    if [ ! -d "${ANDROID_HOME}/cmdline-tools/latest" ]; then
                        echo "Downloading Android command-line tools..."
                        cd /tmp
                        wget -q https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip -O cmdline-tools.zip
                        unzip -q cmdline-tools.zip
                        mv cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest
                        rm cmdline-tools.zip
                    fi
                    
                    # Add to PATH
                    export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
                    
                    # Accept licenses
                    yes | sdkmanager --licenses || true
                    
                    # Install required SDK components
                    echo "Installing SDK components..."
                    sdkmanager "platform-tools"
                    sdkmanager "platforms;android-34"
                    sdkmanager "build-tools;34.0.0"
                    sdkmanager "ndk;${NDK_VERSION}"
                    
                    echo "Android SDK setup complete!"
                    echo "NDK installed at: ${ANDROID_HOME}/ndk/${NDK_VERSION}"
                '''
            }
        }

        stage('Install Rust') {
            steps {
                sh '''
                    echo "=== Installing Rust ==="
                    
                    # Install Rust if not present
                    if [ ! -f "$HOME/.cargo/env" ]; then
                        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                    fi
                    
                    source $HOME/.cargo/env
                    
                    # Set Rust version
                    rustup default ${RUST_VERSION} || rustup install ${RUST_VERSION}
                    rustup default ${RUST_VERSION}
                    
                    # Add Android targets for cross-compilation
                    rustup target add aarch64-linux-android   # arm64-v8a (most phones)
                    rustup target add armv7-linux-androideabi # armeabi-v7a (older phones)
                    rustup target add x86_64-linux-android    # x86_64 (emulators)
                    
                    # Install cargo-ndk for Android builds
                    cargo install cargo-ndk --version ${CARGO_NDK_VERSION} --locked || true
                    
                    echo "Rust setup complete!"
                    rustc --version
                '''
            }
        }

        stage('Install Flutter') {
            steps {
                sh '''
                    echo "=== Installing Flutter ==="
                    
                    if [ ! -d "${FLUTTER_HOME}" ]; then
                        cd $HOME
                        wget -q https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
                        tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
                        rm flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
                    fi
                    
                    export PATH="${FLUTTER_HOME}/bin:${PATH}"
                    export ANDROID_HOME="${ANDROID_HOME}"
                    export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
                    
                    # Configure Flutter
                    flutter config --android-sdk ${ANDROID_HOME}
                    flutter doctor --android-licenses || true
                    flutter doctor -v
                    
                    echo "Flutter setup complete!"
                '''
            }
        }

        stage('Setup vcpkg') {
            steps {
                sh '''
                    echo "=== Setting up vcpkg ==="
                    
                    if [ ! -d "${VCPKG_ROOT}" ]; then
                        cd $HOME
                        git clone https://github.com/microsoft/vcpkg
                        cd vcpkg
                        ./bootstrap-vcpkg.sh -disableMetrics
                    fi
                    
                    echo "vcpkg ready at ${VCPKG_ROOT}"
                '''
            }
        }

        stage('Generate Bridge') {
            steps {
                sh '''
                    echo "=== Generating Rust-Flutter bridge ==="
                    source $HOME/.cargo/env
                    export PATH="${FLUTTER_HOME}/bin:${PATH}"
                    
                    # Install flutter_rust_bridge_codegen
                    cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid || true
                    
                    # Generate bridge file
                    cd flutter
                    if [ ! -f "lib/generated_bridge.dart" ]; then
                        flutter_rust_bridge_codegen \
                            --rust-input ../src/flutter_ffi.rs \
                            --dart-output ./lib/generated_bridge.dart \
                            --c-output ./ios/Runner/bridge_generated.h || echo "Bridge generation had issues, continuing..."
                    fi
                '''
            }
        }

        stage('Build Rust Library for ARM64') {
            steps {
                sh '''
                    echo "=== Building Rust library for ARM64 (aarch64) ==="
                    source $HOME/.cargo/env
                    
                    export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${NDK_VERSION}"
                    export ANDROID_NDK_ROOT="${ANDROID_HOME}/ndk/${NDK_VERSION}"
                    export VCPKG_ROOT="${VCPKG_ROOT}"
                    
                    # Build the Rust library for ARM64
                    cd flutter
                    chmod +x ndk_arm64.sh
                    ./ndk_arm64.sh || cargo ndk -t arm64-v8a build --release
                    
                    # Copy library to jniLibs
                    mkdir -p android/app/src/main/jniLibs/arm64-v8a
                    cp ../target/aarch64-linux-android/release/liblibrustdesk.so android/app/src/main/jniLibs/arm64-v8a/librustdesk.so || true
                    
                    # Copy libc++_shared.so
                    cp ${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so android/app/src/main/jniLibs/arm64-v8a/ || true
                    
                    echo "Rust library built!"
                '''
            }
        }

        stage('Build Flutter APK') {
            steps {
                sh '''
                    echo "=== Building Flutter APK ==="
                    source $HOME/.cargo/env
                    
                    export PATH="${FLUTTER_HOME}/bin:${PATH}"
                    export ANDROID_HOME="${ANDROID_HOME}"
                    export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
                    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
                    
                    cd flutter
                    
                    # Increase Gradle memory
                    sed -i "s/org.gradle.jvmargs=-Xmx1024M/org.gradle.jvmargs=-Xmx4g/g" android/gradle.properties || true
                    
                    # Get dependencies
                    flutter pub get
                    
                    # Build release APK for ARM64 (most Android phones)
                    flutter build apk --release --target-platform android-arm64 --split-per-abi
                    
                    echo "=== APK Build Complete! ==="
                    ls -la build/app/outputs/flutter-apk/
                '''
            }
        }

        stage('Copy APK to Workspace') {
            steps {
                sh '''
                    echo "=== Copying APK ==="
                    cp flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ./rustdesk-${VERSION}-arm64.apk
                    
                    # Show file info
                    ls -lh rustdesk-*.apk
                    echo ""
                    echo "========================================"
                    echo "APK READY FOR DOWNLOAD!"
                    echo "========================================"
                    echo "File: rustdesk-${VERSION}-arm64.apk"
                    echo "========================================"
                '''
            }
        }
    }

    post {
        success {
            archiveArtifacts artifacts: 'rustdesk-*.apk', fingerprint: true
            echo '''
            =========================================
            BUILD SUCCESSFUL!
            =========================================
            Download the APK from Jenkins:
            1. Go to this build's page
            2. Click "Build Artifacts"
            3. Download rustdesk-*.apk
            4. Transfer to your phone and install
            =========================================
            '''
        }
        failure {
            echo 'Build failed! Check the console output for errors.'
        }
        always {
            // Clean up large build files to save disk space
            sh 'rm -rf flutter/build/app/intermediates || true'
        }
    }
}
