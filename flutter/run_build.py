#!/usr/bin/env python3
"""Run the Rust build script."""
import subprocess
import os
import sys

def main():
    script_path = "/Users/apple/AndroidStudioProjects/rustdesk/flutter/build_rust_lib.sh"
    
    # Make script executable
    os.chmod(script_path, 0o755)
    
    # Run the script
    result = subprocess.run(
        ["bash", script_path],
        cwd="/Users/apple/AndroidStudioProjects/rustdesk/flutter",
        capture_output=False,  # Show output in real-time
        text=True
    )
    
    sys.exit(result.returncode)

if __name__ == "__main__":
    main()

