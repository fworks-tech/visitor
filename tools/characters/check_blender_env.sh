#!/usr/bin/env bash
# Check the toolchain OpenCode needs before starting a character.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BLENDER_BIN="${BLENDER_BIN:-blender}"

fail=0
if command -v "$BLENDER_BIN" >/dev/null 2>&1; then
  "$BLENDER_BIN" --version | head -1
else
  echo "MISSING: Blender ($BLENDER_BIN). Set BLENDER_BIN or install Blender 4.2+." >&2
  fail=1
fi

python3 --version
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -version 2>/dev/null | head -1
else
  echo "OPTIONAL: ffmpeg not found (contact sheets only)" >&2
fi

for id in v001 v003 v008; do
  if python3 "$ROOT/tools/characters/validate_blender_output.py" --id "$id" >/dev/null 2>&1; then
    echo "OK: $id blockout contract"
  else
    echo "FAIL: $id blockout contract" >&2
    fail=1
  fi
done
exit "$fail"
