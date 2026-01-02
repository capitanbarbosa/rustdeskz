#!/bin/sh
# Standalone script to generate bridge file - run with: sh run_bridge_gen.sh

cd /Users/apple/AndroidStudioProjects/rustdesk/flutter

# Add cargo to PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Check and install flutter_rust_bridge_codegen if needed
if [ ! -f "$HOME/.cargo/bin/flutter_rust_bridge_codegen" ]; then
    echo "Installing flutter_rust_bridge_codegen..."
    cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid
fi

# Generate the bridge file
echo "Generating bridge file..."
"$HOME/.cargo/bin/flutter_rust_bridge_codegen" \
    --rust-input ../src/flutter_ffi.rs \
    --dart-output ./lib/generated_bridge.dart \
    --c-output ./macos/Runner/bridge_generated.h

if [ -f "./lib/generated_bridge.dart" ]; then
    echo "✓ Bridge file generated successfully!"
    echo "File location: ./lib/generated_bridge.dart"
else
    echo "✗ Failed to generate bridge file"
    exit 1
fi

