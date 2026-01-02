#!/bin/bash

# Script to add namespace to all Flutter plugins that need it for AGP 8.0+

PUB_CACHE="$HOME/.pub-cache/hosted/pub.dev"

echo "Searching for plugins that need namespace fixes..."

find "$PUB_CACHE" -name "build.gradle" -path "*/android/build.gradle" | while read buildfile; do
    plugin_dir=$(dirname "$buildfile")
    
    # Check if namespace is already set
    if grep -q "namespace" "$buildfile"; then
        continue
    fi
    
    # Check if it's an Android library plugin
    if ! grep -q "com.android.library" "$buildfile"; then
        continue
    fi
    
    # Find the package name from AndroidManifest.xml
    manifest="$plugin_dir/src/main/AndroidManifest.xml"
    if [ ! -f "$manifest" ]; then
        continue
    fi
    
    package=$(grep -oP 'package="\K[^"]+' "$manifest" | head -1)
    
    if [ -z "$package" ]; then
        continue
    fi
    
    echo "Fixing: $plugin_dir (package: $package)"
    
    # Check if android block exists
    if grep -q "^android {" "$buildfile"; then
        # Add namespace right after "android {"
        sed -i '' "s/^android {/android {\n    namespace \"$package\"/" "$buildfile"
        echo "  ✓ Added namespace to $buildfile"
    fi
done

echo "Done!"

