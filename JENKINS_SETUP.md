# Jenkins Setup Guide for Building RustDesk Android APK

This guide explains how to set up Jenkins to build the RustDesk Android APK and install it on your phone.

## Overview

**RustDesk** is a remote desktop application. This repo builds:
- **Android APK** (for your phone) - via Flutter + Rust
- Desktop apps for Windows, macOS, Linux

## Prerequisites for Jenkins Server

Your Jenkins server needs to be running **Linux (Ubuntu 22.04+ recommended)** with:

### 1. System Requirements
- **RAM**: 8GB minimum (16GB recommended)
- **Disk**: 50GB+ free space
- **CPU**: 4+ cores recommended

### 2. Required Software on Jenkins Agent

```bash
# Install build dependencies
sudo apt-get update
sudo apt-get install -y \
    clang cmake curl gcc-multilib git g++ g++-multilib \
    libclang-dev nasm ninja-build pkg-config wget unzip \
    openjdk-17-jdk-headless

# Set JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

## Jenkins Configuration

### Step 1: Install Required Jenkins Plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:
- Git plugin
- Pipeline plugin
- Credentials Binding plugin
- Android Signing plugin (optional)

### Step 2: Configure Global Tools

Go to **Manage Jenkins → Tools**:

1. **JDK Installation**
   - Name: `jdk17`
   - JAVA_HOME: `/usr/lib/jvm/java-17-openjdk-amd64`

### Step 3: Configure Credentials (for Signing)

Go to **Manage Jenkins → Credentials → Global → Add Credentials**:

| ID | Type | Description |
|----|------|-------------|
| `android-signing-key` | Secret file | Your `.keystore` file |
| `android-keystore-password` | Secret text | Keystore password |
| `android-key-password` | Secret text | Key password |
| `android-alias` | Secret text | Key alias name |

> **Note**: If you don't have a signing key, the build will produce an unsigned APK that you can still install manually.

### Step 4: Create Pipeline Job

1. Go to **New Item → Pipeline**
2. Name it `rustdesk-android-build`
3. Under **Pipeline**, choose:
   - **Definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/YOUR_USERNAME/rustdeskz.git`
   - **Branch**: `*/main`
   - **Script Path**: `Jenkinsfile`

### Step 5: Connect Your GitHub Repo

In the Pipeline configuration:
```
Repository URL: https://github.com/YOUR_USERNAME/rustdeskz.git
```

Or if using SSH:
```
Repository URL: git@github.com:YOUR_USERNAME/rustdeskz.git
```

Add GitHub credentials if it's a private repo.

## Running the Build

1. Click **Build Now** on your Jenkins job
2. Wait for the build (first build takes 30-60 minutes)
3. Download the APK from **Build Artifacts**

## Getting the APK on Your Phone

### Option 1: Direct Download from Jenkins
1. Go to your Jenkins job → Last successful build → **Build Artifacts**
2. Download `rustdesk-*.apk`
3. Transfer to your phone and install

### Option 2: Automatic Deployment (Advanced)

Add to Jenkinsfile for automatic deployment:

```groovy
stage('Deploy to Device') {
    steps {
        sh '''
            # Using adb over network
            adb connect YOUR_PHONE_IP:5555
            adb install -r rustdesk-${VERSION}-arm64.apk
        '''
    }
}
```

### Option 3: Upload to Distribution Service

```groovy
stage('Upload to Firebase App Distribution') {
    steps {
        sh '''
            # Install Firebase CLI and upload
            firebase appdistribution:distribute rustdesk-*.apk \
                --app YOUR_FIREBASE_APP_ID \
                --groups testers
        '''
    }
}
```

## Alternative: Simpler Build Script

If Jenkins pipeline is complex, use this simpler shell script approach:

### Create `build_android.sh`:
```bash
#!/bin/bash
set -e

# Setup environment
export PATH="$HOME/flutter/bin:$PATH"
source $HOME/.cargo/env

# Navigate to flutter directory
cd flutter

# Generate bridge (if needed)
./generate_bridge.sh || true

# Build the APK
flutter build apk --release --target-platform android-arm64

echo "APK built: flutter/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
```

Then in Jenkins, just run:
```groovy
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh './build_android.sh'
            }
        }
    }
    post {
        success {
            archiveArtifacts 'flutter/build/app/outputs/flutter-apk/*.apk'
        }
    }
}
```

## Directory to Connect in Jenkins

When setting up your Jenkins job, point to the **root of this repository**:

```
/path/to/rustdeskz/
├── Jenkinsfile          ← Jenkins reads this
├── flutter/             ← Flutter mobile app code
│   ├── android/         ← Android-specific config
│   └── build_android.sh
├── src/                 ← Rust source code
└── ...
```

## Troubleshooting

### Build fails with "NDK not found"
```bash
# Set NDK path in Jenkinsfile environment
environment {
    ANDROID_NDK_HOME = '/path/to/android-ndk-r27c'
    ANDROID_NDK_ROOT = '/path/to/android-ndk-r27c'
}
```

### Flutter doctor shows issues
```bash
flutter doctor --android-licenses
flutter doctor -v
```

### Out of memory during build
Increase Gradle memory in `flutter/android/gradle.properties`:
```
org.gradle.jvmargs=-Xmx4g
```

### Bridge generation fails
```bash
cd flutter
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid
./generate_bridge.sh
```

## Quick Start Summary

1. **Push this repo** to your GitHub
2. **Create Jenkins Pipeline job** pointing to your repo URL
3. **Set Script Path** to `Jenkinsfile`
4. **Build** and download the APK
5. **Install APK** on your Android phone (enable "Install from unknown sources")

## Phone Compatibility

The APK builds for:
- **arm64-v8a** (aarch64) - Most modern Android phones (2017+)
- **armeabi-v7a** (armv7) - Older 32-bit phones
- **x86_64** - Emulators, some tablets

The default Jenkinsfile builds for **arm64** which covers 95%+ of phones.

