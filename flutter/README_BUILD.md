# Build Instructions

## Fixed Issues

1. ✅ Gradle updated to 8.7
2. ✅ Android Gradle Plugin updated to 8.6.0
3. ✅ Namespace added to main app
4. ✅ Java 21 configured
5. ✅ Rust/cargo installed
6. ✅ NDK version updated to 26.1.10909125
7. ✅ Plugin namespaces fixed

## Required Steps Before Building

### 1. Generate Bridge File

The `lib/generated_bridge.dart` file needs to be generated. Run:

```bash
cd /Users/apple/AndroidStudioProjects/rustdesk/flutter
source ~/.cargo/env
./generate_bridge.sh
```

Or manually:

```bash
cd /Users/apple/AndroidStudioProjects/rustdesk/flutter
source ~/.cargo/env

# Install flutter_rust_bridge_codegen if not already installed
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid

# Generate the bridge file
flutter_rust_bridge_codegen \
    --rust-input ../src/flutter_ffi.rs \
    --dart-output ./lib/generated_bridge.dart \
    --c-output ./macos/Runner/bridge_generated.h
```

### 2. Ensure NDK is Installed

The build requires NDK 26.1.10909125. If it's not installed, Android Studio/Gradle will download it automatically during the build.

### 3. Build and Run

```bash
cd /Users/apple/AndroidStudioProjects/rustdesk/flutter
source ~/.cargo/env
flutter run
```

## Fixed Plugins (Namespaces Added)

- external_path-1.0.3
- qr_code_scanner-1.0.1
- sqflite-2.2.0
- flutter_keyboard_visibility-5.4.1
- uni_links (git)

If you encounter more namespace errors, run:
```bash
python3 auto_fix_namespaces.py
```

