#!/usr/bin/env python3
"""Validate the Character DNA in character_specs.json.

The DNA is the deterministic input an artist or Blender agent uses to assemble
a visitor: body proportions, face source, outfit layers, rig profile, animations,
assets and validation budget. It is intentionally stricter than a mood board.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPECS = ROOT / "tools/characters/character_specs.json"

BUILDS = {"slim", "lean", "average", "heavy", "broad"}
POSTURES = {"neutral", "guarded", "tired", "upright", "slouched"}
FACE_MODES = {"card", "mesh", "scan"}
HAIR_STYLES = {"short", "long", "cap", "bald", "ponytail", "bun", "messy"}
SLOTS = {"coat", "shirt", "pants", "shoes", "hat", "scarf", "bag", "apron"}
FITS = {"fitted", "regular", "loose", "oversized"}
MATERIALS = {"fabric", "leather", "wool", "denim", "synthetic", "skin"}
RIGS = {"humanoid_20", "humanoid_25", "mixamo", "vrm_humanoid"}
LEVELS = {"L1", "L2", "L3"}


def res_path(value: str) -> Path | None:
    if not isinstance(value, str) or not value.startswith("res://"):
        return None
    return ROOT / value.removeprefix("res://")


def check_rgb(value, where: str, errors: list[str]) -> None:
    if not (isinstance(value, list) and len(value) == 3
            and all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in value)):
        errors.append(f"{where}: expected RGB array of 3 values in 0..1")


def check_number(value, where: str, low: float, high: float, errors: list[str]) -> None:
    if not isinstance(value, (int, float)) or not (low <= value <= high):
        errors.append(f"{where}: expected number in {low}..{high}, got {value!r}")


def validate_character(c: dict, seen: set[str], errors: list[str]) -> None:
    cid = c.get("id", "?")
    if cid in seen:
        errors.append(f"{cid}: duplicate id")
    seen.add(cid)
    if not isinstance(cid, str) or not (len(cid) == 4 and cid.startswith("v") and cid[1:].isdigit()):
        errors.append(f"{cid}: id must look like v001")

    portrait = res_path(c.get("portrait", ""))
    if portrait is None or not portrait.exists():
        errors.append(f"{cid}: portrait missing: {c.get('portrait')!r}")

    dna = c.get("dna")
    if not isinstance(dna, dict):
        errors.append(f"{cid}: missing dna object")
        return
    if dna.get("version") != 1:
        errors.append(f"{cid}: dna.version must be 1")
    if not isinstance(dna.get("seed"), int) or dna["seed"] < 0:
        errors.append(f"{cid}: dna.seed must be a non-negative integer")

    body = dna.get("body", {})
    check_number(body.get("height_m"), f"{cid}.body.height_m", 1.55, 2.05, errors)
    check_number(body.get("shoulder_m"), f"{cid}.body.shoulder_m", 0.4, 0.7, errors)
    if body.get("build") not in BUILDS:
        errors.append(f"{cid}: body.build invalid: {body.get('build')!r}")
    check_number(body.get("head_scale"), f"{cid}.body.head_scale", 0.85, 1.15, errors)
    check_number(body.get("limb_length"), f"{cid}.body.limb_length", 0.9, 1.1, errors)
    if body.get("posture") not in POSTURES:
        errors.append(f"{cid}: body.posture invalid: {body.get('posture')!r}")

    face = dna.get("face", {})
    if face.get("mode") not in FACE_MODES:
        errors.append(f"{cid}: face.mode invalid: {face.get('mode')!r}")
    source = res_path(face.get("source", ""))
    if source is None or not source.exists():
        errors.append(f"{cid}: face.source missing: {face.get('source')!r}")
    if portrait and source and source != portrait:
        errors.append(f"{cid}: face.source must match portrait")
    band = face.get("uv_band", [])
    if not (isinstance(band, list) and len(band) == 4
            and all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in band)):
        errors.append(f"{cid}: face.uv_band must be 4 values in 0..1")
    elif band[2] <= 0 or band[3] <= 0:
        errors.append(f"{cid}: face.uv_band width/height must be > 0")

    hair = dna.get("hair", {})
    if hair.get("style") not in HAIR_STYLES:
        errors.append(f"{cid}: hair.style invalid: {hair.get('style')!r}")
    if "color" in hair:
        check_rgb(hair["color"], f"{cid}.hair.color", errors)

    outfit = dna.get("outfit", {})
    layers = outfit.get("layers", [])
    if not isinstance(layers, list) or not layers:
        errors.append(f"{cid}: outfit.layers must be non-empty")
        layers = []
    for i, layer in enumerate(layers):
        where = f"{cid}.outfit.layers[{i}]"
        if layer.get("slot") not in SLOTS:
            errors.append(f"{where}.slot invalid: {layer.get('slot')!r}")
        if not isinstance(layer.get("asset"), str) or not layer["asset"]:
            errors.append(f"{where}.asset must be non-empty")
        check_rgb(layer.get("color"), f"{where}.color", errors)
        if layer.get("fit") not in FITS:
            errors.append(f"{where}.fit invalid: {layer.get('fit')!r}")
        if "material" in layer and layer["material"] not in MATERIALS:
            errors.append(f"{where}.material invalid: {layer.get('material')!r}")

    rig = dna.get("rig", {})
    if rig.get("profile") not in RIGS:
        errors.append(f"{cid}: rig.profile invalid: {rig.get('profile')!r}")
    if not isinstance(rig.get("mixamo"), bool) or not isinstance(rig.get("vrm"), bool):
        errors.append(f"{cid}: rig.mixamo and rig.vrm must be booleans")
    check_number(rig.get("max_influences", 0), f"{cid}.rig.max_influences", 1, 4, errors)

    anims = dna.get("animations", [])
    if not isinstance(anims, list) or not all(isinstance(a, str) for a in anims):
        errors.append(f"{cid}: animations must be a string array")
        anims = []
    for required in ("idle", "talk"):
        if required not in anims:
            errors.append(f"{cid}: animations missing {required!r}")

    assets = dna.get("assets", {})
    model = res_path(assets.get("model", ""))
    if model is None or not model.exists():
        errors.append(f"{cid}: assets.model missing: {assets.get('model')!r}")
    for tex in assets.get("textures", []):
        p = res_path(tex)
        if p is None or not p.exists():
            errors.append(f"{cid}: texture missing: {tex!r}")

    lod = dna.get("lod", [])
    if not isinstance(lod, list) or not lod:
        errors.append(f"{cid}: lod must be a non-empty array")
    else:
        levels = [x.get("level") for x in lod if isinstance(x, dict)]
        if len(levels) != len(set(levels)):
            errors.append(f"{cid}: duplicate LOD levels")
        for i, item in enumerate(lod):
            check_number(item.get("max_tris"), f"{cid}.lod[{i}].max_tris", 100, 50000, errors)
            if "screen_size" in item:
                check_number(item["screen_size"], f"{cid}.lod[{i}].screen_size", 0, 1, errors)

    validation = dna.get("validation", {})
    if validation.get("level") not in LEVELS:
        errors.append(f"{cid}: validation.level invalid: {validation.get('level')!r}")
    check_number(validation.get("max_tris"), f"{cid}.validation.max_tris", 100, 50000, errors)
    check_number(validation.get("max_materials"), f"{cid}.validation.max_materials", 1, 8, errors)
    if validation.get("level") == "L2":
        if validation.get("max_tris", 0) > 15000:
            errors.append(f"{cid}: L2 max_tris must be <= 15000")
        if validation.get("max_materials", 0) > 4:
            errors.append(f"{cid}: L2 max_materials must be <= 4")
        if validation.get("require_rig") is not True:
            errors.append(f"{cid}: L2 must require a rig")
        if validation.get("require_animations") is not True:
            errors.append(f"{cid}: L2 must require animations")
    if not isinstance(dna.get("license"), str) or not dna["license"].strip():
        errors.append(f"{cid}: license must be non-empty")


def main() -> int:
    if not SPECS.exists():
        print(f"FAIL: {SPECS} not found")
        return 2
    data = json.loads(SPECS.read_text())
    errors: list[str] = []
    if data.get("version", 1) < 2:
        errors.append("character_specs.version must be >= 2 for DNA")
    chars = data.get("characters", [])
    if not isinstance(chars, list) or not chars:
        errors.append("characters must be a non-empty array")
        chars = []
    seen: set[str] = set()
    for c in chars:
        validate_character(c, seen, errors)

    if errors:
        print("FAIL: Character DNA")
        for e in errors:
            print("  - " + e)
        return 1
    print(f"SUCCESS: Character DNA valid ({len(chars)} characters)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
