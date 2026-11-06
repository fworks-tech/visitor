#!/usr/bin/env bash
# Play the two-night demo slice: 3 visitors, 2 endings.
# Override the engine with GODOT_BIN=/path/to/godot.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
exec "$GODOT_BIN" --path "$ROOT" -- --demo "$@"
