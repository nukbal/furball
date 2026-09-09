from pathlib import Path
import subprocess


root = Path(__file__).resolve().parent.parent
subprocess.run(
    ["zig", "build", "test", "-Dplatform=null", "-Doptimize=Debug"],
    cwd=root,
    check=True,
)
print("Media smoke tests passed: in-process ZIP contents and first-image thumbnail assertions.")
