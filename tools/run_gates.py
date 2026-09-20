#!/usr/bin/env python3
"""One command for all headless gates (AGENTS.md convention #10).

    python3 tools/run_gates.py

Set GODOT_BIN to override the Godot executable. Exit code 1 on any gate
failure; output of a failing gate is printed for triage.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") \
    or shutil.which("godot4") or r"C:\Godot\Godot_v4.7.1-stable_win64_console.exe"

GATES = [
    ("door-flow", [GODOT, "--headless", "--path", str(ROOT), "--", "--door-test"],
     "RESULT 0 failures"),
    ("house-walk", [GODOT, "--headless", "--path", str(ROOT), "--", "--house-test"],
     "RESULT 0 failures"),
    ("placement", [GODOT, "--headless", "--path", str(ROOT), "--script",
                   "res://tools/placement_audit.gd"], "0 FAIL"),
    ("focus", [GODOT, "--headless", "--path", str(ROOT), "--script",
               "res://tools/focus_audit.gd"], "0 FAIL"),
    ("data", [sys.executable, str(ROOT / "tests" / "validate_systems.py")], "SUCCESS"),
]


def main() -> int:
    failed = []
    for name, cmd, expect in GATES:
        print(f"== {name} ==")
        try:
            proc = subprocess.run(cmd, cwd=ROOT.parent, capture_output=True,
                                  text=True, errors="replace", timeout=300)
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            failed.append(name)
            print(f"FAIL {name}: {exc}")
            continue
        out = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode == 0 and expect in out:
            print(f"PASS {name}")
        else:
            failed.append(name)
            print(out[-3000:])
            print(f"FAIL {name} (exit={proc.returncode}, expected '{expect}')")
    if failed:
        print(f"\n{len(failed)} gate(s) failed: {', '.join(failed)}")
        return 1
    print("\nALL GATES PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
