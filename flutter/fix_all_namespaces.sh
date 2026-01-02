#!/bin/bash

# Script to automatically fix all plugin namespaces
# This will be called during build to fix plugins on the fly

fix_plugin_namespace() {
    local buildfile="$1"
    local plugin_dir=$(dirname "$buildfile")
    local manifest="$plugin_dir/src/main/AndroidManifest.xml"
    
    if [ ! -f "$manifest" ]; then
        return 1
    fi
    
    # Extract package name from AndroidManifest.xml
    local package=$(grep -oP 'package="\K[^"]+' "$manifest" | head -1)
    
    if [ -z "$package" ]; then
        return 1
    fi
    
    # Check if namespace already exists
    if grep -q "namespace" "$buildfile"; then
        return 0
    fi
    
    # Add namespace right after "android {"
    if grep -q "^android {" "$buildfile"; then
        sed -i '' "s/^android {/android {\n    namespace \"$package\"/" "$buildfile"
        echo "Fixed: $buildfile (namespace: $package)"
        return 0
    fi
    
    return 1
}

# Find and fix all plugins in pub cache
PUB_CACHE="$HOME/.pub-cache"
find "$PUB_CACHE" -name "build.gradle" -path "*/android/build.gradle" 2>/dev/null | while read buildfile; do
    # Check if it's a library plugin
    if grep -q "com.android.library" "$buildfile"; then
        # Check if namespace is missing
        if ! grep -q "namespace" "$buildfile"; then
            fix_plugin_namespace "$buildfile"
        fi
    fi
done

echo "Namespace fixes complete!"

