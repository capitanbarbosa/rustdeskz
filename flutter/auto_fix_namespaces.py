#!/usr/bin/env python3
"""
Automatically fix namespace issues for all Flutter plugins
"""
import os
import re
import glob
from pathlib import Path

def find_package_from_manifest(manifest_path):
    """Extract package name from AndroidManifest.xml"""
    try:
        with open(manifest_path, 'r') as f:
            content = f.read()
            match = re.search(r'package=["\']([^"\']+)["\']', content)
            if match:
                return match.group(1)
    except:
        pass
    return None

def fix_build_gradle(build_gradle_path):
    """Add namespace to build.gradle if missing"""
    try:
        with open(build_gradle_path, 'r') as f:
            content = f.read()
        
        # Check if namespace already exists
        if 'namespace' in content:
            return False
        
        # Check if it's an Android library
        if 'com.android.library' not in content:
            return False
        
        # Find AndroidManifest.xml
        plugin_dir = os.path.dirname(build_gradle_path)
        manifest_path = os.path.join(plugin_dir, 'src', 'main', 'AndroidManifest.xml')
        
        if not os.path.exists(manifest_path):
            return False
        
        package = find_package_from_manifest(manifest_path)
        if not package:
            return False
        
        # Add namespace after "android {"
        pattern = r'(android\s*\{)'
        replacement = f'\\1\n    namespace "{package}"'
        new_content = re.sub(pattern, replacement, content, count=1)
        
        if new_content != content:
            with open(build_gradle_path, 'w') as f:
                f.write(new_content)
            print(f"Fixed: {build_gradle_path} (namespace: {package})")
            return True
    except Exception as e:
        print(f"Error fixing {build_gradle_path}: {e}")
    
    return False

def main():
    """Fix all plugins in pub cache"""
    home = os.path.expanduser('~')
    pub_cache_paths = [
        os.path.join(home, '.pub-cache', 'hosted', 'pub.dev'),
        os.path.join(home, '.pub-cache', 'git'),
    ]
    
    fixed_count = 0
    for pub_cache in pub_cache_paths:
        if not os.path.exists(pub_cache):
            continue
        
        # Find all build.gradle files in android directories
        pattern = os.path.join(pub_cache, '**', 'android', 'build.gradle')
        for build_gradle in glob.glob(pattern, recursive=True):
            if fix_build_gradle(build_gradle):
                fixed_count += 1
    
    print(f"\nFixed {fixed_count} plugin(s)")

if __name__ == '__main__':
    main()

