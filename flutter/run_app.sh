#!/bin/bash

# Fix NDK issue
rm -rf "/Users/apple/Library/Android/sdk/ndk/26.1.10909125"

# Source cargo environment
source ~/.cargo/env

# Change to project directory
cd /Users/apple/AndroidStudioProjects/rustdesk/flutter

# Run Flutter app
flutter run

