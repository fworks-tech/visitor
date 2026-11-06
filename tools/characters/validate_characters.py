#!/usr/bin/env python3
"""Validate generated character GLBs against the demo contract."""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read_glb(path: Path) -> dict:
    with path.open("rb") as f:
        magic, version, total = struct.unpack("<4sII", f.read(12))
        assert magic == b"glTF", f"{path}: bad magic"
        assert version == 2, f"{path}: glTF 2 required"
        jlen, jtype = struct.unpack("<I4s", f.read(8))
        assert jtype == b"JSON", f"{path}: missing JSON chunk"
        doc = json.loads(f.read(jlen).decode("utf-8"))
        blen, btype = struct.unpack("<I4s", f.read(8))
        assert btype == b"BIN\x00", f"{path}: missing BIN chunk"
        assert blen > 0, f"{path}: empty BIN"
        return doc


def main() -> None:
    specs = json.loads((ROOT / "tools/characters/character_specs.json").read_text())
    expected = {c["id"] for c in specs["characters"]}
    models = {}
    for cid in sorted(expected):
        path = ROOT / "assets/models/visitors" / f"{cid}.glb"
        assert path.exists(), f"missing model {path}"
        doc = read_glb(path)
        meshes = doc.get("meshes", [])
        assert meshes and meshes[0].get("primitives"), f"{cid}: no primitives"
        materials = doc.get("materials", [])
        assert any("portrait" in m.get("name", "") for m in materials), f"{cid}: no face material"
        assert any("TEXCOORD_0" in p.get("attributes", {}) for p in meshes[0]["primitives"]), f"{cid}: no UVs"
        models[cid] = path.stat().st_size
    assert set(models) == expected, f"model mismatch: {sorted(models)} != {sorted(expected)}"
    print("SUCCESS: character GLBs valid")
    for cid, size in models.items():
        print(f"  {cid}: {size / 1024:.1f} KiB")


if __name__ == "__main__":
    main()
