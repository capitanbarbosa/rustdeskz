#!/bin/bash

# Generate Flutter Rust Bridge file
cd /Users/apple/AndroidStudioProjects/rustdesk/flutter

# Source cargo environment
source ~/.cargo/env

# Check if flutter_rust_bridge_codegen is installed
if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
    echo "Installing flutter_rust_bridge_codegen..."
    cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid
fi

# Generate the bridge file
echo "Generating bridge file..."
flutter_rust_bridge_codegen \
    --rust-input ../src/flutter_ffi.rs \
    --dart-output ./lib/generated_bridge.dart \
    --c-output ./macos/Runner/bridge_generated.h

echo "Bridge file generated successfully!"

