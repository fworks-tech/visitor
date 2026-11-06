#!/usr/bin/env python3
"""Validate a character GLB against the Visitor mobile contract.

Works on both the generated blockouts (no rig) and production Blender exports.
With --production it additionally requires a skin, an animation and a reasonable
bone count.

Usage:
  python3 tools/characters/validate_blender_output.py --id v001
  python3 tools/characters/validate_blender_output.py --id v001 \
      --path assets/models/visitors/_wip/v001.glb --production
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

COMPONENTS = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}
TYPES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def read_glb(path: Path) -> tuple[dict, bytes]:
    with path.open("rb") as f:
        magic, version, total = struct.unpack("<4sII", f.read(12))
        if magic != b"glTF" or version != 2:
            raise ValueError(f"{path}: not a glTF 2.0 binary")
        jlen, jtype = struct.unpack("<I4s", f.read(8))
        if jtype != b"JSON":
            raise ValueError(f"{path}: first chunk is not JSON")
        doc = json.loads(f.read(jlen).decode("utf-8"))
        blen, btype = struct.unpack("<I4s", f.read(8))
        if btype != b"BIN\x00":
            raise ValueError(f"{path}: second chunk is not BIN")
        blob = f.read(blen)
        if total != 12 + 8 + jlen + 8 + blen:
            print(f"warn: header length {total} != actual {12 + 8 + jlen + 8 + blen}")
        return doc, blob


def _component(acc: dict) -> tuple[str, int]:
    comp = acc["componentType"]
    if comp not in COMPONENTS:
        raise ValueError(f"unsupported componentType {comp}")
    return COMPONENTS[comp]


def accessor_values(doc: dict, blob: bytes, index: int) -> list[tuple]:
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    fmt, size = _component(acc)
    width = TYPES[acc["type"]]
    count = acc["count"]
    stride = view.get("byteStride", size * width)
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(count):
        values = struct.unpack_from("<" + fmt * width, blob, offset + i * stride)
        out.append(values if width > 1 else values[0])
    return out


def png_size(data: bytes) -> tuple[int, int] | None:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", data[16:24])


def image_bytes(doc: dict, blob: bytes, image_index: int) -> bytes | None:
    image = doc["images"][image_index]
    if "bufferView" not in image:
        return None
    view = doc["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    return blob[start:start + view["byteLength"]]


def validate(path: Path, cid: str, production: bool, max_tris: int,
             height_min: float, height_max: float, feet_tolerance: float) -> tuple[bool, list[str]]:
    doc, blob = read_glb(path)
    errors: list[str] = []
    notes: list[str] = []

    meshes = doc.get("meshes", [])
    if not meshes:
        errors.append("no meshes")
    prims = [p for m in meshes for p in m.get("primitives", [])]
    if not prims:
        errors.append("no primitives")

    tris = 0
    aabb_min = [float("inf")] * 3
    aabb_max = [float("-inf")] * 3
    uv_prims = 0
    for prim in prims:
        attrs = prim.get("attributes", {})
        if "POSITION" not in attrs:
            errors.append("primitive without POSITION")
            continue
        if "TEXCOORD_0" in attrs:
            uv_prims += 1
        if "indices" in prim:
            tris += doc["accessors"][prim["indices"]]["count"] // 3
        else:
            tris += doc["accessors"][attrs["POSITION"]]["count"] // 3
        pos = doc["accessors"][attrs["POSITION"]]
        if "min" in pos and "max" in pos:
            for i in range(3):
                aabb_min[i] = min(aabb_min[i], pos["min"][i])
                aabb_max[i] = max(aabb_max[i], pos["max"][i])

    if tris > max_tris:
        errors.append(f"triangle budget exceeded: {tris} > {max_tris}")
    if uv_prims == 0:
        errors.append("no primitive has TEXCOORD_0")

    materials = doc.get("materials", [])
    mat_names = [m.get("name", "") for m in materials]
    if not any("portrait" in n for n in mat_names):
        errors.append("missing portrait/face material (expected name containing 'portrait')")

    nodes = doc.get("nodes", [])
    names = [n.get("name", "") for n in nodes]
    if cid and not any(cid in n for n in names):
        errors.append(f"no node name contains {cid!r}")

    if doc.get("cameras"):
        errors.append("camera present in export")
    if "KHR_lights_punctual" in (doc.get("extensionsUsed") or []):
        errors.append("lights present in export")

    height = aabb_max[1] - aabb_min[1] if aabb_min[1] != float("inf") else 0.0
    if not (height_min <= height <= height_max):
        errors.append(f"height {height:.3f} m outside {height_min}-{height_max} m")
    if abs(aabb_min[1]) > feet_tolerance:
        errors.append(f"feet not at origin: min Y {aabb_min[1]:.3f} (tolerance {feet_tolerance})")

    for idx, image in enumerate(doc.get("images", [])):
        data = image_bytes(doc, blob, idx)
        if data:
            size = png_size(data)
            if size:
                if max(size) > 2048:
                    errors.append(f"image {idx} is {size}, max 2048")
                notes.append(f"image {idx}: {size[0]}x{size[1]}")
            else:
                notes.append(f"image {idx}: non-PNG ({image.get('mimeType', '?')})")

    skin = doc.get("skins", [])
    animations = doc.get("animations", [])
    joints = len(skin[0].get("joints", [])) if skin else 0
    if production:
        if not skin:
            errors.append("production export requires a skin")
        if not animations:
            errors.append("production export requires idle and talk animations")
        if skin and not (20 <= joints <= 25):
            errors.append(f"production rig has {joints} joints, expected 20-25")
        if len(materials) > 4:
            errors.append(f"production uses {len(materials)} materials, max 4")
        anim_names = [a.get("name", "") for a in animations]
        for required in ("idle", "talk"):
            if not any(required in n for n in anim_names):
                errors.append(f"production is missing the {required!r} animation")

    notes.insert(0, f"tris={tris} materials={len(materials)} nodes={len(nodes)} "
                    f"height={height:.3f}m minY={aabb_min[1]:.3f} skins={len(skin)} "
                    f"joints={joints} animations={len(animations)}")
    return (not errors), notes + errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--path", default="")
    ap.add_argument("--production", action="store_true")
    ap.add_argument("--max-tris", type=int, default=15000)
    ap.add_argument("--height-min", type=float, default=1.55)
    ap.add_argument("--height-max", type=float, default=2.05)
    ap.add_argument("--feet-tolerance", type=float, default=0.1)
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[2]
    path = Path(args.path) if args.path else root / "assets/models/visitors" / f"{args.id}.glb"
    if not path.is_absolute():
        path = root / path
    if not path.exists():
        print(f"FAIL: model not found: {path}")
        return 2
    try:
        ok, lines = validate(path, args.id, args.production, args.max_tris,
                             args.height_min, args.height_max, args.feet_tolerance)
    except Exception as exc:
        print(f"FAIL: {path}: {exc}")
        return 2
    print(f"{'PASS' if ok else 'FAIL'}: {path}")
    for line in lines:
        print("  " + line)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
