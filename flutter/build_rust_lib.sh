#!/bin/bash
# Don't use set -e so we can handle errors and retry

cd /Users/apple/AndroidStudioProjects/rustdesk

# Source cargo environment
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

# Set NDK path
export ANDROID_NDK_HOME="/Users/apple/Library/Android/sdk/ndk/26.1.10909125"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

# Determine host tag for NDK toolchain
# Check which toolchain actually exists (cargo-ndk may use darwin-x86_64 even on arm64 Macs)
HOST_TAG="darwin-x86_64"
if [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-arm64" ]; then
    HOST_TAG="darwin-arm64"
elif [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64" ]; then
    HOST_TAG="darwin-x86_64"
else
    # Fallback: try to detect from uname
    if [ "$(uname -m)" = "arm64" ]; then
        HOST_TAG="darwin-arm64"
    fi
fi

# Set NDK toolchain paths (cargo-ndk will use these)
export TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
export PATH="$TOOLCHAIN/bin:$PATH"

# Set sysroot for C/C++ compilation (needed for kcp-sys and other native deps)
# Note: Don't set __ANDROID_API__ here - cargo-ndk sets it via --platform flag
# IMPORTANT: Only set target-specific flags to avoid affecting host builds
# Setting global CFLAGS breaks host builds (like libsodium-sys building for macOS host)
export SYSROOT="$TOOLCHAIN/sysroot"
# Use target-specific environment variables (cargo-ndk and cc-rs will use these)
export CFLAGS_aarch64_linux_android="--sysroot=$SYSROOT"
export CXXFLAGS_aarch64_linux_android="--sysroot=$SYSROOT"
export LDFLAGS_aarch64_linux_android="--sysroot=$SYSROOT"
# Clear global CFLAGS/CXXFLAGS to prevent them from affecting host builds
# Explicitly export empty values to override any inherited environment
export CFLAGS=""
export CXXFLAGS=""
export LDFLAGS=""
# Also unset to be extra sure
unset CFLAGS
unset CXXFLAGS
unset LDFLAGS

# Set VCPKG_ROOT if not set (required for hwcodec, magnum-opus, scrap)
# Check if VCPKG exists in common locations
if [ -z "$VCPKG_ROOT" ]; then
    if [ -d "$HOME/vcpkg" ]; then
        export VCPKG_ROOT="$HOME/vcpkg"
        echo "Using VCPKG at: $VCPKG_ROOT"
    elif [ -d "/usr/local/vcpkg" ]; then
        export VCPKG_ROOT="/usr/local/vcpkg"
        echo "Using VCPKG at: $VCPKG_ROOT"
    fi
fi

# Create symlinks for OpenSSL build script which expects traditional toolchain names
# OpenSSL's build script looks for aarch64-linux-android-ranlib, etc.
# but NDK uses llvm-ranlib, llvm-ar, etc.
TOOLCHAIN_BIN="$TOOLCHAIN/bin"
TARGET_PREFIX="aarch64-linux-android21"

# Create temporary directory for symlinks
TEMP_TOOL_DIR=$(mktemp -d)
export PATH="$TEMP_TOOL_DIR:$PATH"

# Create symlinks for tools that OpenSSL expects
ln -sf "$TOOLCHAIN_BIN/llvm-ranlib" "$TEMP_TOOL_DIR/${TARGET_PREFIX}-ranlib" 2>/dev/null || true
ln -sf "$TOOLCHAIN_BIN/llvm-ar" "$TEMP_TOOL_DIR/${TARGET_PREFIX}-ar" 2>/dev/null || true
ln -sf "$TOOLCHAIN_BIN/llvm-strip" "$TEMP_TOOL_DIR/${TARGET_PREFIX}-strip" 2>/dev/null || true
ln -sf "$TOOLCHAIN_BIN/llvm-nm" "$TEMP_TOOL_DIR/${TARGET_PREFIX}-nm" 2>/dev/null || true

# Also create without API level suffix (some scripts expect this)
ln -sf "$TOOLCHAIN_BIN/llvm-ranlib" "$TEMP_TOOL_DIR/aarch64-linux-android-ranlib" 2>/dev/null || true
ln -sf "$TOOLCHAIN_BIN/llvm-ar" "$TEMP_TOOL_DIR/aarch64-linux-android-ar" 2>/dev/null || true
ln -sf "$TOOLCHAIN_BIN/llvm-strip" "$TEMP_TOOL_DIR/aarch64-linux-android-strip" 2>/dev/null || true
ln -sf "$TOOLCHAIN_BIN/llvm-nm" "$TEMP_TOOL_DIR/aarch64-linux-android-nm" 2>/dev/null || true

# Set OpenSSL-specific environment variables
# openssl-sys build script needs ANDROID_NDK to be set
export ANDROID_NDK="$ANDROID_NDK_HOME"
export OPENSSL_STATIC=1

# Cleanup function to remove temp directory
cleanup() {
    rm -rf "$TEMP_TOOL_DIR"
}
trap cleanup EXIT

# Note: Let cargo-ndk handle compiler flags and environment setup
# Overriding CFLAGS/CXXFLAGS can cause conflicts with cargo-ndk's configuration

# Check if cargo-ndk is installed
if ! command -v cargo-ndk &> /dev/null; then
    echo "Installing cargo-ndk..."
    cargo install cargo-ndk --version 2.8.0
fi

# Install the Rust target if not already installed
echo "Checking if Rust target aarch64-linux-android is installed..."
if rustup target list --installed | grep -q "aarch64-linux-android"; then
    echo "Target aarch64-linux-android is already installed."
else
    echo "Installing Rust target aarch64-linux-android..."
    rustup target add aarch64-linux-android
fi

# Clean OpenSSL build artifacts if they exist (to avoid stale build issues)
if [ -d "target/aarch64-linux-android/release/build/openssl-sys-*" ]; then
    echo "Cleaning OpenSSL build artifacts..."
    rm -rf target/aarch64-linux-android/release/build/openssl-sys-*
fi

# Build for arm64-v8a (aarch64-linux-android)
# Use cargo-ndk which handles most of the environment setup
echo "Building Rust library for arm64-v8a..."
echo "Note: OpenSSL build may take several minutes..."

# Check if VCPKG_ROOT is set and valid
# Note: scrap and magnum-opus require VCPKG packages even without hwcodec feature
if [ -z "$VCPKG_ROOT" ] || [ ! -d "$VCPKG_ROOT" ]; then
    echo "ERROR: VCPKG_ROOT is not set or VCPKG is not installed."
    echo "VCPKG is required for Android builds (scrap and magnum-opus dependencies need it)."
    echo "Please install VCPKG and set VCPKG_ROOT environment variable."
    exit 1
fi

echo "VCPKG found at: $VCPKG_ROOT"

# Check if VCPKG packages are installed for arm64-android
# VCPKG installs packages to packages/ directory by default
# With --x-install-root, it may also copy to installed/ directory
VCPKG_INSTALLED="$VCPKG_ROOT/installed/arm64-android"
VCPKG_PACKAGES="$VCPKG_ROOT/packages"
MISSING_PACKAGES=0

# Check for packages - VCPKG stores them in packages/ directory
OPUS_FOUND=0
VPX_FOUND=0

# Check packages directory first (this is where VCPKG actually installs)
# Just check if the package directories exist - VCPKG installs complete packages
if [ -d "$VCPKG_PACKAGES/opus_arm64-android" ]; then
    # Check for any opus headers or include directory
    if [ -d "$VCPKG_PACKAGES/opus_arm64-android/include" ]; then
        OPUS_FOUND=1
        echo "✓ Found opus package"
    fi
fi

if [ -d "$VCPKG_PACKAGES/libvpx_arm64-android" ]; then
    # Check for any vpx headers or include directory
    if [ -d "$VCPKG_PACKAGES/libvpx_arm64-android/include" ]; then
        VPX_FOUND=1
        echo "✓ Found libvpx package"
    fi
fi

# Also check installed directory (in case packages were copied there)
if [ $OPUS_FOUND -eq 0 ] && [ -d "$VCPKG_INSTALLED/include" ]; then
    if [ -f "$VCPKG_INSTALLED/include/opus/opus_multistream.h" ] || \
       [ -d "$VCPKG_INSTALLED/include/opus" ]; then
        OPUS_FOUND=1
        echo "✓ Found opus package in installed directory"
    fi
fi

if [ $VPX_FOUND -eq 0 ] && [ -d "$VCPKG_INSTALLED/include" ]; then
    if [ -f "$VCPKG_INSTALLED/include/vpx/vp8.h" ] || \
       [ -d "$VCPKG_INSTALLED/include/vpx" ]; then
        VPX_FOUND=1
        echo "✓ Found libvpx package in installed directory"
    fi
fi

if [ $OPUS_FOUND -eq 0 ]; then
    echo "WARNING: opus package not found"
    MISSING_PACKAGES=1
fi

if [ $VPX_FOUND -eq 0 ]; then
    echo "WARNING: libvpx package not found"
    MISSING_PACKAGES=1
fi

# Check for additional required packages
# The build system looks in installed/arm64-android/, so check there first
AOM_FOUND=0
FFMPEG_FOUND=0

# Check for aom (needed by scrap) - check installed/ first (where build system looks)
if [ -f "$VCPKG_INSTALLED/include/aom/aom.h" ] || \
   [ -d "$VCPKG_INSTALLED/include/aom" ]; then
    AOM_FOUND=1
    echo "✓ Found aom package in installed/"
elif [ -d "$VCPKG_PACKAGES/aom_arm64-android/include" ]; then
    echo "Found aom in packages/, but build system needs it in installed/"
    AOM_FOUND=0  # Mark as not found since it's not in the right place
else
    echo "aom package not found"
fi

# Check for ffmpeg (needed by hwcodec) - check installed/ first
if [ -f "$VCPKG_INSTALLED/include/libavcodec/avcodec.h" ] || \
   [ -d "$VCPKG_INSTALLED/include/libavcodec" ]; then
    FFMPEG_FOUND=1
    echo "✓ Found ffmpeg package in installed/"
elif [ -d "$VCPKG_PACKAGES/ffmpeg_arm64-android/include" ]; then
    echo "Found ffmpeg in packages/, but build system needs it in installed/"
    FFMPEG_FOUND=0  # Mark as not found since it's not in the right place
else
    echo "ffmpeg package not found"
fi

# VCPKG's build system (used by Rust crates) looks in installed/ directory
# If packages are only in packages/, we may need to ensure they're accessible
# For now, if essential packages (opus, libvpx) are found, proceed
# Missing aom/ffmpeg will cause build failures but we'll handle that
if [ $OPUS_FOUND -eq 1 ] && [ $VPX_FOUND -eq 1 ]; then
    echo "✓ Essential VCPKG packages (opus, libvpx) are installed"
    if [ $AOM_FOUND -eq 0 ]; then
        echo "WARNING: aom package not found (needed by scrap)"
    fi
    if [ $FFMPEG_FOUND -eq 0 ]; then
        echo "WARNING: ffmpeg package not found (needed by hwcodec)"
    fi
    echo "Skipping VCPKG installation - essential packages available"
    MISSING_PACKAGES=0  # Essential packages found
    VCPKG_PACKAGES_READY=1
else
    VCPKG_PACKAGES_READY=0
fi

# Check if we need to install additional packages (aom, ffmpeg) or copy packages to installed/
if [ $VCPKG_PACKAGES_READY -eq 1 ]; then
    # Essential packages found, but check if we need aom/ffmpeg or need to copy to installed/
    # Also check for oboe and other required libraries
    OBOE_FOUND=0
    if [ -f "$VCPKG_INSTALLED/lib/liboboe.a" ] || [ -f "$VCPKG_INSTALLED/lib/liboboe.so" ]; then
        OBOE_FOUND=1
        echo "✓ Found oboe library"
    fi
    
    if [ $AOM_FOUND -eq 0 ] || [ $FFMPEG_FOUND -eq 0 ] || [ $OBOE_FOUND -eq 0 ] || [ ! -d "$VCPKG_INSTALLED/include" ]; then
        echo "Some packages are missing or not in installed/ directory."
        echo "Installing all required packages from vcpkg.json (manifest mode)..."
        echo "This will install: oboe, cpu-features, aom, ffmpeg, and other dependencies"
        echo ""
        
        # Try to install missing packages
        if [ -f "$VCPKG_ROOT/vcpkg" ] || command -v vcpkg > /dev/null 2>&1; then
            VCPKG_CMD="$VCPKG_ROOT/vcpkg"
            if ! [ -f "$VCPKG_CMD" ]; then
                VCPKG_CMD="vcpkg"
            fi
            
            # Check if nasm is installed (required for aom)
            if [ $AOM_FOUND -eq 0 ] && ! command -v nasm > /dev/null 2>&1; then
                echo ""
                echo "ERROR: nasm is required to build aom but is not installed."
                echo "Please install nasm first:"
                echo "  brew install nasm"
                echo ""
                echo "Then run this script again."
                exit 1
            fi
            
            # Install all packages from vcpkg.json using manifest mode
            # This ensures oboe, cpu-features, and all other dependencies are installed
            export ANDROID_NDK_HOME
            export ANDROID_NDK="$ANDROID_NDK_HOME"
            export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
            cd /Users/apple/AndroidStudioProjects/rustdesk
            
            echo "Running: $VCPKG_CMD install --triplet arm64-android --x-install-root=\"$VCPKG_ROOT/installed\""
            echo "This may take a while..."
            echo ""
            
            $VCPKG_CMD install --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed" 2>&1 | tee /tmp/vcpkg_install_all.log | tail -100
            
            INSTALL_RESULT=${PIPESTATUS[0]}
            if [ $INSTALL_RESULT -ne 0 ]; then
                echo ""
                echo "WARNING: VCPKG installation had errors. Checking what was installed..."
                tail -50 /tmp/vcpkg_install_all.log
                echo ""
            else
                echo ""
                echo "✓ VCPKG packages installed successfully"
            fi
            echo ""
            
            # Check if ndk_compat is installed (might be a custom port or part of NDK)
            # ndk_compat is not in vcpkg.json, so it might need special handling
            if [ ! -f "$VCPKG_INSTALLED/lib/libndk_compat.a" ] && [ ! -f "$VCPKG_INSTALLED/lib/libndk_compat.so" ]; then
                echo "WARNING: ndk_compat library not found in VCPKG."
                echo "This library might be provided by the Android NDK compatibility library."
                echo "Checking if it's in the NDK..."
                # Check NDK for ndk_compat
                if [ -f "$ANDROID_NDK_HOME/sources/third_party/vulkan/src/build-android/jniLibs/arm64-v8a/libVkLayer_*.so" ] || \
                   [ -d "$ANDROID_NDK_HOME/sources/cxx-stl/llvm-libc++" ]; then
                    echo "NDK compatibility libraries found in NDK"
                fi
                echo "If the build fails with missing ndk_compat, it might need to be installed separately."
                echo ""
            fi
        fi
    fi
    echo "VCPKG packages check complete, proceeding with Rust build..."
    # Skip the main installation block - jump to build features
elif [ $MISSING_PACKAGES -eq 1 ]; then
    echo "WARNING: VCPKG packages for arm64-android are not installed or incomplete."
    echo "Required packages (opus, libvpx, libyuv) are missing."
    echo ""
    echo "Attempting to install VCPKG packages for arm64-android..."
    echo "This may take a long time (especially ffmpeg)..."
    echo ""
    
    # Install VCPKG packages for arm64-android
    # Find VCPKG executable - it might be in the root or in a scripts directory
    VCPKG_CMD=""
    if [ -f "$VCPKG_ROOT/vcpkg" ]; then
        VCPKG_CMD="$VCPKG_ROOT/vcpkg"
    elif [ -f "$VCPKG_ROOT/vcpkg.exe" ]; then
        VCPKG_CMD="$VCPKG_ROOT/vcpkg.exe"
    elif [ -f "$VCPKG_ROOT/scripts/vcpkg" ]; then
        VCPKG_CMD="$VCPKG_ROOT/scripts/vcpkg"
    elif command -v vcpkg > /dev/null 2>&1; then
        VCPKG_CMD="vcpkg"
    fi
    
    # Check if VCPKG_CMD is valid
    if [ -z "$VCPKG_CMD" ]; then
        echo "ERROR: vcpkg executable not found."
        echo "Searched in:"
        echo "  - $VCPKG_ROOT/vcpkg"
        echo "  - $VCPKG_ROOT/vcpkg.exe"
        echo "  - $VCPKG_ROOT/scripts/vcpkg"
        echo "  - PATH (command -v vcpkg)"
        echo ""
        echo "Please ensure VCPKG is properly installed and the executable is accessible."
        echo "VCPKG_ROOT is set to: $VCPKG_ROOT"
        exit 1
    fi
    
    # Verify the command exists and is executable
    if [ -f "$VCPKG_CMD" ] && [ -x "$VCPKG_CMD" ]; then
        # File exists and is executable
        :
    elif command -v "$VCPKG_CMD" > /dev/null 2>&1; then
        # Command is in PATH
        :
    else
        echo "ERROR: vcpkg executable found but not executable: $VCPKG_CMD"
        exit 1
    fi
    
    if true; then
        
        # Install required packages for Android
        # VCPKG needs Android NDK environment variables to be set
        # Export NDK paths for VCPKG to detect
        export ANDROID_NDK_HOME_VCPKG="$ANDROID_NDK_HOME"
        export ANDROID_NDK_ROOT_VCPKG="$ANDROID_NDK_ROOT"
        export ANDROID_NDK="$ANDROID_NDK_HOME"
        
        # VCPKG uses these to find the NDK
        # Also set the toolchain path
        export ANDROID_NDK_LATEST="$ANDROID_NDK_HOME"
        
        echo "Installing VCPKG packages for arm64-android..."
        echo "Android NDK: $ANDROID_NDK_HOME"
        echo "This will install: opus, libvpx, libyuv, and other dependencies from vcpkg.json..."
        echo "This may take a long time (especially ffmpeg)..."
        echo ""
        
        # Check if VCPKG has the arm64-android triplet
        if [ ! -f "$VCPKG_ROOT/triplets/arm64-android.cmake" ] && [ ! -f "$VCPKG_ROOT/triplets/community/arm64-android.cmake" ]; then
            echo "WARNING: arm64-android triplet not found in VCPKG."
            echo "VCPKG should have built-in Android triplets. Checking available triplets..."
            ls "$VCPKG_ROOT/triplets/"*android*.cmake 2>/dev/null | head -5 || echo "No Android triplets found"
            echo ""
        fi
        
        cd /Users/apple/AndroidStudioProjects/rustdesk
        if [ -f "vcpkg.json" ]; then
            # Use manifest mode - VCPKG should detect Android NDK from environment
            # Try without host-triplet first (VCPKG should auto-detect)
            echo "Running: $VCPKG_CMD install --triplet arm64-android --x-install-root=\"$VCPKG_ROOT/installed\""
            
            # First attempt: let VCPKG auto-detect host triplet
            $VCPKG_CMD install --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed" 2>&1 | tee /tmp/vcpkg_install.log
            INSTALL_RESULT=${PIPESTATUS[0]}
            
            # If that fails due to host compiler detection, try with explicit host-triplet
            if [ $INSTALL_RESULT -ne 0 ] && grep -q "detect.*compiler\|arm64-osx\|Error\|error" /tmp/vcpkg_install.log 2>/dev/null; then
                echo ""
                echo "First attempt failed. Trying with x64-osx as host-triplet (may work with Rosetta)..."
                echo "Running: $VCPKG_CMD install --triplet arm64-android --host-triplet x64-osx --x-install-root=\"$VCPKG_ROOT/installed\""
                $VCPKG_CMD install --triplet arm64-android --host-triplet x64-osx --x-install-root="$VCPKG_ROOT/installed" 2>&1 | tee /tmp/vcpkg_install.log
                INSTALL_RESULT=${PIPESTATUS[0]}
                
                # If x64-osx also fails, try to work around the host compiler detection issue
                if [ $INSTALL_RESULT -ne 0 ]; then
                    echo ""
                    echo "Both attempts failed due to host compiler detection."
                    echo "Attempting workaround: checking if we can use existing packages or skip host deps..."
                    echo ""
                    
                    # Try using --classic mode which might bypass some host tool detection issues
                    echo "Trying with --classic mode (bypasses manifest mode)..."
                    echo "Installing minimal required packages: opus, libvpx, libyuv"
                    $VCPKG_CMD install opus libvpx libyuv --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed" --classic 2>&1 | tee /tmp/vcpkg_install.log
                    INSTALL_RESULT=${PIPESTATUS[0]}
                    
                    # If classic mode works for minimal packages, try installing from manifest
                    if [ $INSTALL_RESULT -eq 0 ]; then
                        echo ""
                        echo "✓ Minimal packages installed with --classic mode"
                        echo "Now trying to install remaining packages from vcpkg.json..."
                        $VCPKG_CMD install --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed" --classic 2>&1 | tee -a /tmp/vcpkg_install.log
                        INSTALL_RESULT=${PIPESTATUS[0]}
                    fi
                    
                    if [ $INSTALL_RESULT -ne 0 ]; then
                        echo ""
                        echo "All VCPKG installation attempts failed."
                        echo ""
                        echo "This is a known issue with VCPKG on macOS when CMake can't detect the compiler."
                        echo ""
                        echo "DIAGNOSIS:"
                        echo "Checking CMake error log..."
                        if [ -f "$VCPKG_ROOT/buildtrees/detect_compiler/config-arm64-osx-rel-err.log" ]; then
                            echo "Last 20 lines of CMake error log:"
                            tail -20 "$VCPKG_ROOT/buildtrees/detect_compiler/config-arm64-osx-rel-err.log" 2>/dev/null || echo "Could not read error log"
                            echo ""
                        fi
                        echo ""
                        echo "SOLUTION: You need to manually install VCPKG packages."
                        echo ""
                        echo "Option 1: Use the provided manual installation script:"
                        echo "  cd /Users/apple/AndroidStudioProjects/rustdesk/flutter"
                        echo "  ./install_vcpkg_android.sh"
                        echo ""
                        echo "Option 2: Install manually:"
                        echo "  cd $VCPKG_ROOT"
                        echo "  export ANDROID_NDK_HOME=\"$ANDROID_NDK_HOME\""
                        echo "  export ANDROID_NDK=\"$ANDROID_NDK_HOME\""
                        echo "  cd /Users/apple/AndroidStudioProjects/rustdesk"
                        echo "  ./vcpkg install --triplet arm64-android --x-install-root=\"$VCPKG_ROOT/installed\""
                        echo ""
                        echo "If VCPKG installation still fails, you may need to fix CMake/Xcode setup:"
                        echo "1. Ensure Xcode Command Line Tools are installed:"
                        echo "   xcode-select --install"
                        echo "2. Or set Xcode path explicitly:"
                        echo "   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
                        echo "3. Check CMake error logs for details:"
                        echo "   cat $VCPKG_ROOT/buildtrees/detect_compiler/config-arm64-osx-rel-err.log"
                        echo ""
                        echo "After successfully installing packages, run this script again."
                        exit 1
                    fi
                fi
            fi
            
            if [ $INSTALL_RESULT -ne 0 ]; then
                echo ""
                echo "ERROR: VCPKG package installation failed after all attempts."
                echo ""
                echo "Last 50 lines of VCPKG output:"
                tail -50 /tmp/vcpkg_install.log 2>/dev/null || true
                echo ""
                echo "Please manually install VCPKG packages (see instructions above) and try again."
                exit 1
            fi
            echo ""
            echo "✓ VCPKG packages installed successfully"
        else
            echo "ERROR: vcpkg.json not found."
            echo "Please install packages manually:"
            echo "  cd $VCPKG_ROOT"
            echo "  export ANDROID_NDK_HOME=\"$ANDROID_NDK_HOME\""
            echo "  ./vcpkg install --triplet arm64-android --x-install-root=\"$VCPKG_ROOT/installed\""
            exit 1
        fi
        echo ""
    else
        echo "ERROR: vcpkg executable not found."
        echo "Searched in:"
        echo "  - $VCPKG_ROOT/vcpkg"
        echo "  - $VCPKG_ROOT/vcpkg.exe"
        echo "  - $VCPKG_ROOT/scripts/vcpkg"
        echo "  - PATH (command -v vcpkg)"
        echo ""
        echo "Please ensure VCPKG is properly installed and the executable is accessible."
        echo "VCPKG_ROOT is set to: $VCPKG_ROOT"
        exit 1
    fi
fi

# Check if hwcodec feature should be enabled (only if we didn't skip installation)
if [ $VCPKG_PACKAGES_READY -eq 1 ] || [ $MISSING_PACKAGES -eq 0 ]; then
    # Packages are available
    echo "✓ VCPKG packages for arm64-android are available"
fi

# Check if hwcodec feature should be enabled
# hwcodec requires ffmpeg, so only enable if ffmpeg is available
if [ $FFMPEG_FOUND -eq 1 ] && [ $OPUS_FOUND -eq 1 ] && [ $VPX_FOUND -eq 1 ]; then
    echo "Building with hwcodec feature (all required packages available)..."
    BUILD_FEATURES="flutter,hwcodec"
elif [ $AOM_FOUND -eq 0 ] || [ $OPUS_FOUND -eq 0 ] || [ $VPX_FOUND -eq 0 ]; then
    echo "WARNING: Some required packages are missing."
    echo "Building without hwcodec feature (missing: aom or essential packages)..."
    BUILD_FEATURES="flutter"
else
    echo "Building without hwcodec feature (ffmpeg not available)..."
    BUILD_FEATURES="flutter"
fi
echo ""

# Try building with the selected features
echo "Building with features: $BUILD_FEATURES"
BUILD_SUCCESS=0

if cargo ndk --platform 21 --target aarch64-linux-android build --release --features "$BUILD_FEATURES" 2>&1; then
    BUILD_SUCCESS=1
    echo "✓ Build successful with features: $BUILD_FEATURES"
else
    echo ""
    echo "Build failed with features: $BUILD_FEATURES"
    if [ "$BUILD_FEATURES" = "flutter,hwcodec" ]; then
        echo "Retrying build without hwcodec feature..."
        if cargo ndk --platform 21 --target aarch64-linux-android build --release --features flutter 2>&1; then
            BUILD_SUCCESS=1
            echo "✓ Build successful without hwcodec feature"
        else
            echo "✗ Build failed even without hwcodec. Please check the error messages above."
            exit 1
        fi
    else
        echo "✗ Build failed. Please check the error messages above."
        exit 1
    fi
fi

if [ $BUILD_SUCCESS -eq 0 ]; then
    exit 1
fi

# Create jniLibs directory
mkdir -p flutter/android/app/src/main/jniLibs/arm64-v8a

# Copy the library
echo "Copying library to jniLibs..."
cp target/aarch64-linux-android/release/liblibrustdesk.so flutter/android/app/src/main/jniLibs/arm64-v8a/librustdesk.so

# Copy libc++_shared.so
if [ -f "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" ]; then
    cp "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" \
       flutter/android/app/src/main/jniLibs/arm64-v8a/
    echo "Copied libc++_shared.so"
fi

echo "✓ Rust library built and copied successfully!"

