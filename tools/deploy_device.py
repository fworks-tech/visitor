#!/usr/bin/env python3
"""DEEPTALES one-click device deploy (M4-3): build -> install -> launch -> logs.

Run from a generated game's root:
    python3 tools/deploy_device.py            # build APK + install + launch
    python3 tools/deploy_device.py --check   # environment diagnostics only
    python3 tools/deploy_device.py --device <serial>
    python3 tools/deploy_device.py --no-build # install an existing APK

Every step diagnoses itself: if something is missing it tells you exactly
what to fix and exits non-zero (CI-friendly).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
PRESETS = GAME / "export_presets.cfg"
BUILD_DIR = GAME / "build" / "android"


def _fail(step: str, msg: str, hint: str = "") -> None:
    print(f"  \u2717 {step}: {msg}")
    if hint:
        print(f"      fix: {hint}")
    sys.exit(1)


def _ok(step: str, msg: str) -> None:
    print(f"  \u2713 {step}: {msg}")


def find_godot() -> str:
    cand = os.environ.get("GODOT_BIN") or shutil.which("godot") \
        or shutil.which("godot4") or shutil.which("godot --headless")
    if not cand:
        _fail("godot", "Godot binary not found",
              "install Godot 4.x and set GODOT_BIN=/path/to/godot (or add to PATH)")
    return cand


def find_adb() -> str:
    cand = os.environ.get("ADB_BIN") or shutil.which("adb")
    if not cand:
        for p in (Path.home() / "Android/Sdk/platform-tools/adb",
                  Path("/usr/lib/android-sdk/platform-tools/adb")):
            if p.exists():
                cand = str(p)
                break
    if not cand:
        _fail("adb", "adb not found",
              "install Android platform-tools; set ADB_BIN or add to PATH; "
              "enable Developer options + USB debugging on the phone")
    return cand


def android_preset() -> str:
    if not PRESETS.exists():
        _fail("presets", "export_presets.cfg missing", "regenerate the game")
    txt = PRESETS.read_text(encoding="utf-8")
    m = re.search(r'\[preset\.\d+\]\s*\n\s*name="Android[^"]*"\s*\n\s*platform="Android"', txt)
    if not m:
        _fail("presets", "no Android preset in export_presets.cfg",
              "add one in Godot's export dialog or use generate_export_presets")
    name = re.search(r'name="(Android[^"]*)"', m.group(0)).group(1)
    return name


def package_name() -> str:
    """Android package id (used by adb install/monkey). Falls back through
    unique_name -> name since older presets may only carry the display name."""
    txt = PRESETS.read_text(encoding="utf-8")
    m = (re.search(r'package/unique_name="([^"]+)"', txt)
         or re.search(r'package/name="([^"]+)"', txt))
    if not m:
        _fail("package", "package id not set in export_presets.cfg",
              "set package/unique_name in the Android preset options "
              "(e.g. com.deeptales.<slug>)")
    return m.group(1)


def build_apk(godot: str, preset: str) -> Path:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    slug = GAME.name
    apk = BUILD_DIR / f"{slug}.apk"
    print(f"== Building APK (preset '{preset}') ==")
    r = subprocess.run([godot, "--headless", "--export-release", preset, str(apk),
                        str(GAME)], capture_output=True, text=True, timeout=900)
    if r.returncode != 0 or not apk.exists():
        tail = (r.stdout + r.stderr).strip().splitlines()[-8:]
        _fail("build", "export failed", "last output:\n        " + "\n        ".join(tail))
    _ok("build", f"{apk.name} ({apk.stat().st_size / 1e6:.1f} MB)")
    return apk


def pick_device(adb: str, serial: str | None) -> str:
    r = subprocess.run([adb, "devices"], capture_output=True, text=True, timeout=15)
    lines = [l.split("\t") for l in r.stdout.strip().splitlines()[1:]
             if "\tdevice" in l]
    if not lines:
        _fail("device", "no authorized device connected",
              "plug in via USB, authorize the debug prompt, check 'adb devices'")
    devs = [l[0] for l in lines]
    if serial:
        if serial not in devs:
            _fail("device", f"{serial} not among connected: {devs}", "check --device")
        return serial
    if len(devs) > 1:
        print(f"  ! multiple devices {devs} — using {devs[0]} (use --device to pick)")
    return devs[0]


def run(adb: str, dev: str, *args: str, timeout: int = 120) -> subprocess.CompletedProcess:
    return subprocess.run([adb, "-s", dev, *args], capture_output=True, text=True,
                          timeout=timeout)


def main() -> None:
    ap = argparse.ArgumentParser(description="DEEPTALES device deploy")
    ap.add_argument("--check", action="store_true", help="diagnostics only")
    ap.add_argument("--no-build", action="store_true", help="install existing build/android APK")
    ap.add_argument("--device", help="adb serial (see adb devices)")
    ap.add_argument("--keep-log", action="store_true", help="dump logcat to build/android/logcat.txt")
    args = ap.parse_args()

    godot = find_godot()
    adb = find_adb()
    preset = android_preset()
    pkg = package_name()
    _ok("env", f"godot @ {godot}")
    _ok("env", f"adb @ {adb} | preset '{preset}' | package {pkg}")
    if args.check:
        print("== Environment OK ==")
        return

    if args.no_build:
        apk = BUILD_DIR / f"{GAME.name}.apk"
        if not apk.exists():
            _fail("apk", f"{apk} missing", "run without --no-build first")
    else:
        apk = build_apk(godot, preset)

    dev = pick_device(adb, args.device)
    _ok("device", dev)

    print("== Installing ==")
    r = run(adb, dev, "install", "-r", str(apk), timeout=180)
    if r.returncode != 0:
        _fail("install", r.stdout.strip() or r.stderr.strip(),
              "check phone storage / signature mismatch (uninstall old build)")
    _ok("install", f"{pkg} installed")

    print("== Launching ==")
    r = run(adb, dev, "shell", "monkey", "-p", pkg, "-c",
            "android.intent.category.LAUNCHER", "1")
    time.sleep(3)
    r = run(adb, dev, "shell", "pidof", pkg)
    if r.returncode == 0 and r.stdout.strip():
        _ok("launch", f"process alive (pid {r.stdout.strip()})")
    else:
        _ok("launch", "launch intent sent (no pid visible — check the screen)")

    print("== Smoke logs ==")
    r = run(adb, dev, "logcat", "-d", "-t", "40")
    interesting = [l for l in r.stdout.splitlines()
                    if re.search(r"(?i)(error|crash|fatal|godot)", l)][-10:]
    for l in interesting or ["(no godot/error lines — likely clean boot)"]:
        print("  " + l.strip()[:150])
    if args.keep_log:
        out = BUILD_DIR / "logcat.txt"
        out.write_text(r.stdout, encoding="utf-8")
        _ok("log", f"full logcat -> {out}")

    print("\nOn-device QA checklist (docs/DEVICE_QA.md): touch input, safe-area/"
          "notch, back button, audio ducking, 30-min battery/heat, process death/restore.")


if __name__ == "__main__":
    main()
