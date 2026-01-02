#!/usr/bin/env python3
"""Build Rust library and fix errors automatically."""
import os
import subprocess
import shutil
import sys
import re

def run_command(cmd, cwd=None, env=None, check=False):
    """Run a shell command and return output."""
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error output: {result.stderr}")
        if check:
            sys.exit(1)
    return result

def main():
    rustdesk_root = "/Users/apple/AndroidStudioProjects/rustdesk"
    os.chdir(rustdesk_root)
    
    # Set up environment
    env = os.environ.copy()
    
    # Source cargo
    cargo_bin = os.path.expanduser("~/.cargo/bin")
    if os.path.exists(cargo_bin):
        env["PATH"] = f"{cargo_bin}:{env.get('PATH', '')}"
    
    # Set NDK paths
    ndk_home = "/Users/apple/Library/Android/sdk/ndk/26.1.10909125"
    env["ANDROID_NDK_HOME"] = ndk_home
    env["ANDROID_NDK_ROOT"] = ndk_home
    env["ANDROID_NDK"] = ndk_home
    
    # Determine host tag
    import platform
    host_machine = platform.machine()
    if host_machine == "arm64":
        host_tag = "darwin-arm64"
    else:
        host_tag = "darwin-x86_64"
    
    toolchain = f"{ndk_home}/toolchains/llvm/prebuilt/{host_tag}"
    env["PATH"] = f"{toolchain}/bin:{env.get('PATH', '')}"
    
    # Set sysroot
    sysroot = f"{toolchain}/sysroot"
    env["SYSROOT"] = sysroot
    env["CFLAGS"] = f"--sysroot={sysroot} -D__ANDROID_API__=21"
    env["CXXFLAGS"] = f"--sysroot={sysroot} -D__ANDROID_API__=21"
    env["LDFLAGS"] = f"--sysroot={sysroot}"
    
    # OpenSSL
    env["OPENSSL_STATIC"] = "1"
    
    # Check VCPKG
    vcpkg_root = env.get("VCPKG_ROOT")
    if not vcpkg_root:
        if os.path.exists(os.path.expanduser("~/vcpkg")):
            vcpkg_root = os.path.expanduser("~/vcpkg")
            env["VCPKG_ROOT"] = vcpkg_root
            print(f"Using VCPKG at: {vcpkg_root}")
        else:
            print("WARNING: VCPKG_ROOT not set. Build may fail for hwcodec feature.")
    
    # Check Rust target
    print("Checking Rust target...")
    result = run_command(["rustup", "target", "list", "--installed"], env=env, check=False)
    if "aarch64-linux-android" not in result.stdout:
        print("Installing Rust target...")
        run_command(["rustup", "target", "add", "aarch64-linux-android"], env=env)
    
    # Try building
    print("\nBuilding Rust library...")
    result = run_command([
        "cargo", "ndk", "--platform", "21", "--target", "aarch64-linux-android",
        "build", "--release", "--features", "flutter,hwcodec"
    ], env=env, check=False)
    
    # Check for specific errors
    stderr = result.stderr
    stdout = result.stdout
    
    # Check for VCPKG errors
    if "VCPKG_ROOT" in stderr or "vcpkg" in stderr.lower():
        print("\nVCPKG error detected. Trying without hwcodec feature...")
        result = run_command([
            "cargo", "ndk", "--platform", "21", "--target", "aarch64-linux-android",
            "build", "--release", "--features", "flutter"
        ], env=env, check=False)
        stderr = result.stderr
        stdout = result.stdout
    
    # Check for kcp-sys stdlib.h error
    if "stdlib.h" in stderr and "kcp-sys" in stderr:
        print("\nstdlib.h error detected in kcp-sys. Checking sysroot configuration...")
        # The sysroot should already be set, but let's verify
        print(f"SYSROOT: {sysroot}")
        stdlib_path = f"{sysroot}/usr/include/stdlib.h"
        if os.path.exists(stdlib_path):
            print(f"Found stdlib.h at: {stdlib_path}")
        else:
            print(f"ERROR: stdlib.h not found at: {stdlib_path}")
            # Try to find it
            for root, dirs, files in os.walk(sysroot):
                if "stdlib.h" in files:
                    print(f"Found stdlib.h at: {os.path.join(root, 'stdlib.h')}")
                    break
    
    # Print output
    if result.returncode == 0:
        print("\n✓ Build successful!")
        # Copy library
        lib_path = "target/aarch64-linux-android/release/liblibrustdesk.so"
        if os.path.exists(lib_path):
            jni_libs_dir = "flutter/android/app/src/main/jniLibs/arm64-v8a"
            os.makedirs(jni_libs_dir, exist_ok=True)
            shutil.copy2(lib_path, f"{jni_libs_dir}/librustdesk.so")
            print(f"✓ Copied library to {jni_libs_dir}/librustdesk.so")
    else:
        print("\n✗ Build failed!")
        print("\nError output:")
        print(stderr[-2000:] if len(stderr) > 2000 else stderr)
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())

