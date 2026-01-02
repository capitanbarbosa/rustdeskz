#!/bin/sh
# Final script to generate bridge file - uses /bin/sh to avoid zsh issues

cd /Users/apple/AndroidStudioProjects/rustdesk/flutter

# Add cargo to PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Check if flutter_rust_bridge_codegen exists
if [ ! -f "$HOME/.cargo/bin/flutter_rust_bridge_codegen" ]; then
    echo "Installing flutter_rust_bridge_codegen..."
    cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid
    if [ $? -ne 0 ]; then
        echo "Failed to install flutter_rust_bridge_codegen"
        exit 1
    fi
fi

# Generate the bridge file
echo "Generating bridge file..."
"$HOME/.cargo/bin/flutter_rust_bridge_codegen" \
    --rust-input ../src/flutter_ffi.rs \
    --dart-output ./lib/generated_bridge.dart \
    --c-output ./macos/Runner/bridge_generated.h

if [ -f "./lib/generated_bridge.dart" ]; then
    echo "✓ Bridge file generated successfully!"
    echo "File: ./lib/generated_bridge.dart"
    exit 0
else
    echo "✗ Failed to generate bridge file"
    exit 1
fi

