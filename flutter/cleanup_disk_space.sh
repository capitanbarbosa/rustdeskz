#!/bin/sh
# Clean up disk space to fix "No space left on device" error

echo "Checking disk space..."
df -h / | tail -1

echo ""
echo "Cleaning up Android SDK temp files..."
rm -rf /Users/apple/Library/Android/sdk/.temp/*
rm -rf /Users/apple/Library/Android/sdk/ndk/.temp/*

echo "Cleaning up Gradle caches..."
rm -rf ~/.gradle/caches/*
rm -rf /Users/apple/AndroidStudioProjects/rustdesk/flutter/android/.gradle/*

echo "Cleaning up Flutter build caches..."
cd /Users/apple/AndroidStudioProjects/rustdesk/flutter
flutter clean

echo "Cleaning up incomplete NDK downloads..."
rm -rf /Users/apple/Library/Android/sdk/ndk/26.1.10909125

echo ""
echo "Checking disk space after cleanup..."
df -h / | tail -1

echo ""
echo "Cleanup complete! Try building again."

