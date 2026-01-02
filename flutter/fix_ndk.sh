#!/bin/sh
# Fix malformed NDK by deleting it so Gradle can re-download

echo "Removing malformed NDK directory..."
rm -rf /Users/apple/Library/Android/sdk/ndk/26.1.10909125

if [ $? -eq 0 ]; then
    echo "✓ NDK directory removed. Gradle will re-download it on next build."
else
    echo "✗ Failed to remove NDK directory"
    exit 1
fi
