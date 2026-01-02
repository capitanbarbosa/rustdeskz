#!/usr/bin/env python3
"""Build Rust library for Android and copy to jniLibs directory."""
import os
import subprocess
import shutil
import sys

def run_command(cmd, cwd=None, check=True):
    """Run a shell command."""
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        if check:
            sys.exit(1)
    return result

def main():
    # Change to rustdesk root directory
    rustdesk_root = "/Users/apple/AndroidStudioProjects/rustdesk"
    os.chdir(rustdesk_root)
    
    # Source cargo environment by setting PATH
    cargo_bin = os.path.expanduser("~/.cargo/bin")
    env = os.environ.copy()
    if os.path.exists(cargo_bin):
        env["PATH"] = f"{cargo_bin}:{env.get('PATH', '')}"
    
    # Set NDK paths
    ndk_home = "/Users/apple/Library/Android/sdk/ndk/26.1.10909125"
    env["ANDROID_NDK_HOME"] = ndk_home
    env["ANDROID_NDK_ROOT"] = ndk_home
    
    # Check if cargo-ndk is installed
    cargo_ndk_path = shutil.which("cargo-ndk", path=env["PATH"])
    if not cargo_ndk_path:
        print("Installing cargo-ndk...")
        run_command(["cargo", "install", "cargo-ndk", "--version", "2.8.0"], env=env)
    
    # Check if Rust target is installed
    print("Checking if Rust target aarch64-linux-android is installed...")
    result = run_command(["rustup", "target", "list", "--installed"], env=env, check=False)
    if "aarch64-linux-android" not in result.stdout:
        print("Installing Rust target aarch64-linux-android...")
        run_command(["rustup", "target", "add", "aarch64-linux-android"], env=env)
    else:
        print("Target aarch64-linux-android is already installed.")
    
    # Build for arm64-v8a
    print("Building Rust library for arm64-v8a...")
    run_command([
        "cargo", "ndk", "--platform", "21", "--target", "aarch64-linux-android",
        "build", "--release", "--features", "flutter,hwcodec"
    ], env=env)
    
    # Create jniLibs directory
    jni_libs_dir = "flutter/android/app/src/main/jniLibs/arm64-v8a"
    os.makedirs(jni_libs_dir, exist_ok=True)
    
    # Copy the library
    source_lib = "target/aarch64-linux-android/release/liblibrustdesk.so"
    dest_lib = f"{jni_libs_dir}/librustdesk.so"
    
    if not os.path.exists(source_lib):
        print(f"Error: Source library not found at {source_lib}")
        sys.exit(1)
    
    print(f"Copying library from {source_lib} to {dest_lib}...")
    shutil.copy2(source_lib, dest_lib)
    print(f"✓ Copied librustdesk.so")
    
    # Copy libc++_shared.so
    import platform
    host_machine = platform.machine()
    if host_machine == "arm64":
        host_tag = "darwin-arm64"
    else:
        host_tag = "darwin-x86_64"
    
    libcpp_source = f"{ndk_home}/toolchains/llvm/prebuilt/{host_tag}/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
    if os.path.exists(libcpp_source):
        libcpp_dest = f"{jni_libs_dir}/libc++_shared.so"
        shutil.copy2(libcpp_source, libcpp_dest)
        print(f"✓ Copied libc++_shared.so")
    else:
        print(f"Warning: libc++_shared.so not found at {libcpp_source}")
    
    print("✓ Rust library built and copied successfully!")

if __name__ == "__main__":
    main()

