#!/usr/bin/env python3
"""Build a low-poly, portrait-faced visitor GLB for the demo.

This is the runnable half of the character pipeline: it reads a character spec
and the visitor portrait, samples the palette, builds a blockout humanoid and
embeds the portrait's face band as the face material. The production path
(Blender sculpt/rig/anim) is documented in docs/CHARACTER_PIPELINE.md and
uses the same spec and output contract.

Usage:
  python3 tools/characters/build_character.py \
      --spec tools/characters/character_specs.json --out-dir assets/models/visitors
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import Iterable

from PIL import Image

FACE_UV = (0.34, 0.13, 0.28, 0.30)  # same band as VisitorBody3D.FACE_UV
FACE_SIZE = (0.24, 0.25)


def clamp(v: float) -> float:
    return max(0.0, min(1.0, v))


def avg(img: Image.Image, cx: float, cy: float, half: float) -> tuple[float, float, float]:
    w, h = img.size
    x0, x1 = int((cx - half) * w), int((cx + half) * w)
    y0, y1 = int((cy - half) * h), int((cy + half) * h)
    px = img.crop((x0, y0, x1, y1)).resize((1, 1), Image.Resampling.BOX).getpixel((0, 0))
    if len(px) == 4:
        px = px[:3]
    return tuple(clamp(c / 255.0) for c in px)


def multiply(c: Iterable[float], k: Iterable[float]) -> tuple[float, float, float]:
    return tuple(clamp(a * b) for a, b in zip(c, k))


class GLB:
    def __init__(self, scale: float = 1.0):
        self.scale = scale
        self.bin = bytearray()
        self.buffer_views: list[dict] = []
        self.accessors: list[dict] = []
        self.materials: list[dict] = []
        self.primitives: list[dict] = []
        self.images: list[dict] = []
        self.textures: list[dict] = []
        self._mat_cache: dict[tuple, int] = {}

    def _align(self) -> None:
        while len(self.bin) % 4:
            self.bin.append(0)

    def _buffer_view(self, data: bytes, target: int | None = None) -> int:
        self._align()
        offset = len(self.bin)
        self.bin.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            view["target"] = target
        self.buffer_views.append(view)
        return len(self.buffer_views) - 1

    def _accessor(self, data: bytes, component: int, kind: str, count: int,
                  target: int | None = None, minimum=None, maximum=None) -> int:
        view = self._buffer_view(data, target)
        acc = {"bufferView": view, "componentType": component, "count": count, "type": kind}
        if minimum is not None:
            acc["min"] = minimum
        if maximum is not None:
            acc["max"] = maximum
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def material(self, name: str, color: tuple[float, float, float],
                 rough: float = 0.9, metal: float = 0.0) -> int:
        key = ("solid", name)
        if key in self._mat_cache:
            return self._mat_cache[key]
        self.materials.append({
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": [color[0], color[1], color[2], 1.0],
                "metallicFactor": metal,
                "roughnessFactor": rough,
            },
        })
        self._mat_cache[key] = len(self.materials) - 1
        return len(self.materials) - 1

    def face_material(self, name: str, png: bytes) -> int:
        view = self._buffer_view(png)
        self.images.append({"bufferView": view, "mimeType": "image/png"})
        self.textures.append({"source": len(self.images) - 1, "sampler": 0})
        self.materials.append({
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": len(self.textures) - 1},
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
            "emissiveTexture": {"index": len(self.textures) - 1},
            "emissiveFactor": [0.55, 0.75, 0.55],
            "doubleSided": True,
        })
        return len(self.materials) - 1

    def _primitive(self, verts, normals, uvs, indices, material: int) -> None:
        pos = struct.pack("<%df" % (len(verts) * 3), *[c for v in verts for c in v])
        nor = struct.pack("<%df" % (len(normals) * 3), *[c for v in normals for c in v])
        uv = struct.pack("<%df" % (len(uvs) * 2), *[c for v in uvs for c in v])
        idx = struct.pack("<%dH" % len(indices), *indices)
        mins = [min(v[i] for v in verts) for i in range(3)]
        maxs = [max(v[i] for v in verts) for i in range(3)]
        prim = {
            "attributes": {
                "POSITION": self._accessor(pos, 5126, "VEC3", len(verts), 34962, mins, maxs),
                "NORMAL": self._accessor(nor, 5126, "VEC3", len(normals), 34962),
                "TEXCOORD_0": self._accessor(uv, 5126, "VEC2", len(uvs), 34962),
            },
            "indices": self._accessor(idx, 5123, "SCALAR", len(indices), 34963),
            "material": material,
            "mode": 4,
        }
        self.primitives.append(prim)

    def box(self, center, size, material: int) -> None:
        cx, cy, cz = (c * self.scale for c in center)
        sx, sy, sz = (s * self.scale for s in size)
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        faces = [
            ((1, 0, 0), [(hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz), (hx, -hy, hz)]),
            ((-1, 0, 0), [(-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz), (-hx, -hy, -hz)]),
            ((0, 1, 0), [(-hx, hy, -hz), (-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz)]),
            ((0, -1, 0), [(-hx, -hy, hz), (-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz)]),
            ((0, 0, 1), [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]),
            ((0, 0, -1), [(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)]),
        ]
        verts, normals, uvs, indices = [], [], [], []
        for normal, corners in faces:
            base = len(verts)
            for i, (x, y, z) in enumerate(corners):
                verts.append((cx + x, cy + y, cz + z))
                normals.append(normal)
                uvs.append(((i in (1, 2)), (i in (2, 3))))
            indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
        self._primitive(verts, normals, uvs, indices, material)

    def face(self, center, size, material: int, uv=FACE_UV) -> None:
        cx, cy, cz = (c * self.scale for c in center)
        sx, sy = (s * self.scale for s in size)
        hx, hy = sx / 2, sy / 2
        u0, v0, uw, vh = uv
        verts = [(cx - hx, cy - hy, cz), (cx + hx, cy - hy, cz),
                 (cx + hx, cy + hy, cz), (cx - hx, cy + hy, cz)]
        normals = [(0, 0, 1)] * 4
        uvs = [(u0, v0 + vh), (u0 + uw, v0 + vh), (u0 + uw, v0), (u0, v0)]
        self._primitive(verts, normals, uvs, [0, 1, 2, 0, 2, 3], material)

    def write(self, path: Path, name: str) -> None:
        mesh = {"name": name + "_mesh", "primitives": self.primitives}
        doc = {
            "asset": {"version": "2.0", "generator": "DEEPTALES character pipeline"},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"name": name, "mesh": 0}],
            "meshes": [mesh],
            "materials": self.materials,
            "textures": self.textures,
            "images": self.images,
            "samplers": [{"magFilter": 9729, "minFilter": 9987}],
            "accessors": self.accessors,
            "bufferViews": self.buffer_views,
            "buffers": [{"byteLength": len(self.bin)}],
        }
        json_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
        while len(json_bytes) % 4:
            json_bytes += b" "
        while len(self.bin) % 4:
            self.bin.append(0)
        total = 12 + 8 + len(json_bytes) + 8 + len(self.bin)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
            f.write(json_bytes)
            f.write(struct.pack("<I4s", len(self.bin), b"BIN\x00"))
            f.write(self.bin)


def build(spec: dict, root: Path, out_dir: Path) -> Path:
    portrait = root / spec["portrait"].replace("res://", "")
    img = Image.open(portrait).convert("RGB")
    skin = avg(img, 0.47, 0.27, 0.025)
    coat = multiply(avg(img, 0.50, 0.64, 0.06), spec.get("coat_tint", [1, 1, 1]))
    hair = multiply(avg(img, 0.50, 0.06, 0.035), spec.get("hair_tint", [1, 1, 1]))
    pants = tuple(c * 0.55 for c in coat)
    shoes = (0.035, 0.032, 0.030)
    dna = spec.get("dna", {})
    shoulder = dna.get("body", {}).get("shoulder_m", spec.get("shoulder", 0.54))
    height = spec.get("height_scale", 1.0)
    face_uv = tuple(dna.get("face", {}).get("uv_band", FACE_UV))

    g = GLB(scale=height)
    m_skin = g.material("skin", skin)
    m_skin_dark = g.material("skin_shadow", tuple(c * 0.72 for c in skin))
    m_coat = g.material("coat", coat)
    m_coat_dark = g.material("coat_shadow", tuple(c * 0.72 for c in coat))
    m_pants = g.material("pants", pants)
    m_shoes = g.material("shoes", shoes)
    m_hair = g.material("hair", hair)
    m_dark = g.material("detail", (0.035, 0.040, 0.035))

    for side in (-1, 1):
        g.box((side * 0.11, 0.42, 0), (0.13, 0.78, 0.15), m_pants)
        g.box((side * 0.11, 0.055, 0.035), (0.13, 0.075, 0.25), m_shoes)
    g.box((0, 0.96, 0), (shoulder, 0.72, 0.30), m_coat)
    g.box((0, 0.62, 0.005), (shoulder * 0.96, 0.10, 0.31), m_coat_dark)
    # coat opening / lapels
    for side in (-1, 1):
        g.box((side * 0.10, 1.10, 0.157), (0.055, 0.48, 0.015), m_coat_dark)
    g.box((0, 1.30, 0.155), (0.035, 0.035, 0.02), m_dark)
    for side in (-1, 1):
        g.box((side * (shoulder / 2 + 0.06), 0.98, 0.01), (0.11, 0.62, 0.14), m_coat)
        g.box((side * (shoulder / 2 + 0.06), 0.64, 0.02), (0.095, 0.12, 0.10), m_skin)
    g.box((0, 1.38, 0), (0.13, 0.12, 0.13), m_skin_dark)
    g.box((0, 1.58, 0), (0.21, 0.25, 0.22), m_skin)
    g.box((0, 1.50, 0.015), (0.19, 0.075, 0.20), m_skin_dark)
    style = dna.get("hair", {}).get("style", spec.get("hair", "short"))
    if style == "short":
        g.box((0, 1.72, -0.005), (0.24, 0.075, 0.235), m_hair)
    elif style == "long":
        g.box((0, 1.69, -0.045), (0.25, 0.08, 0.12), m_hair)
        for side in (-1, 1):
            g.box((side * 0.115, 1.52, -0.02), (0.055, 0.28, 0.10), m_hair)
    elif style == "cap":
        g.box((0, 1.72, -0.005), (0.25, 0.06, 0.24), m_hair)
        g.box((0, 1.69, 0.14), (0.23, 0.025, 0.11), m_hair)
    # face card uses the portrait face band; emissive so it survives night light
    g.face((0, 1.565, 0.113), FACE_SIZE,
           g.face_material("portrait_face", portrait.read_bytes()), face_uv)
    out = out_dir / (spec["id"] + ".glb")
    g.write(out, spec["id"])
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", default="tools/characters/character_specs.json")
    ap.add_argument("--out-dir", default="assets/models/visitors")
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[2]
    data = json.loads((root / args.spec).read_text())
    out_dir = root / args.out_dir
    for spec in data["characters"]:
        if args.only and spec["id"] != args.only:
            continue
        path = build(spec, root, out_dir)
        print(f"BUILT {path.relative_to(root)} ({path.stat().st_size / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
