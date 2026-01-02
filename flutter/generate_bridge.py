#!/usr/bin/env python3
"""Generate Flutter Rust Bridge file"""
import os
import subprocess
import sys

def main():
    os.chdir('/Users/apple/AndroidStudioProjects/rustdesk/flutter')
    
    # Add cargo to PATH
    cargo_bin = os.path.expanduser('~/.cargo/bin')
    env = os.environ.copy()
    if 'PATH' in env:
        env['PATH'] = f"{cargo_bin}:{env['PATH']}"
    else:
        env['PATH'] = cargo_bin
    
    # Check if flutter_rust_bridge_codegen exists
    codegen_path = os.path.join(cargo_bin, 'flutter_rust_bridge_codegen')
    
    if not os.path.exists(codegen_path):
        print("Installing flutter_rust_bridge_codegen...")
        result = subprocess.run(
            ['cargo', 'install', 'flutter_rust_bridge_codegen', '--version', '1.80.1', '--features', 'uuid'],
            env=env,
            cwd=os.path.expanduser('~')
        )
        if result.returncode != 0:
            print("Failed to install flutter_rust_bridge_codegen")
            sys.exit(1)
    
    # Generate bridge file
    print("Generating bridge file...")
    rust_input = '../src/flutter_ffi.rs'
    dart_output = './lib/generated_bridge.dart'
    c_output = './macos/Runner/bridge_generated.h'
    
    result = subprocess.run(
        [codegen_path, '--rust-input', rust_input, '--dart-output', dart_output, '--c-output', c_output],
        env=env,
        cwd='/Users/apple/AndroidStudioProjects/rustdesk/flutter'
    )
    
    if result.returncode == 0:
        print("Bridge file generated successfully!")
        if os.path.exists(dart_output):
            print(f"✓ Created {dart_output}")
        return 0
    else:
        print("Failed to generate bridge file")
        return 1

if __name__ == '__main__':
    sys.exit(main())

