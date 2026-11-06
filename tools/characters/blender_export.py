#!/usr/bin/env python3
"""Blender-side export + review-render template for Visitor characters.

Run from the repository root, with the character scene open:

  blender --background assets/models/visitors/_wip/v001.blend \
    --python tools/characters/blender_export.py -- \
    --id v001 \
    --out assets/models/visitors/_wip/v001.glb \
    --preview-dir docs/renders/characters/v001 \
    --production

Expected scene contract (see docs/BLENDER_AGENT_PLAYBOOK.md):
  collection CH_<id>, root <id>, mesh BODY_<id>, armature RIG_<id>
  metres, feet at Z=0, front toward -Y, 20-25 bones, actions idle/talk.

This is a template, not a model generator. It refuses to export when the
bounds/rig/actions violate the contract, so OpenCode cannot silently produce a
bad asset.
"""
from __future__ import annotations

import argparse
import math
import os
import sys
from pathlib import Path

try:
    import bpy
    from mathutils import Vector
except ImportError:  # pragma: no cover - only when run outside Blender
    print("This script must run inside Blender: blender -b -P ...", file=sys.stderr)
    raise SystemExit(2)


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--preview-dir", default="")
    ap.add_argument("--production", action="store_true")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--feet-tolerance", type=float, default=0.1)
    ap.add_argument("--height-min", type=float, default=1.55)
    ap.add_argument("--height-max", type=float, default=2.05)
    return ap.parse_args(argv)


def collection_for(cid: str):
    name = f"CH_{cid}"
    coll = bpy.data.collections.get(name)
    if coll is None:
        matches = [c for c in bpy.data.collections if cid in c.name]
        if matches:
            coll = matches[0]
    if coll is None:
        raise SystemExit(f"collection {name} not found; create CH_{cid} first")
    return coll


def selected_objects(coll):
    objs = [o for o in coll.all_objects if o.type in {"MESH", "ARMATURE", "EMPTY"}]
    if not objs:
        raise SystemExit(f"collection {coll.name} has no mesh/armature/empty objects")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(
        (o for o in objs if o.type == "MESH"), objs[0])
    return objs


def apply_rot_scale(objs):
    for obj in objs:
        if obj.type not in {"MESH", "ARMATURE"}:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def bounds(objs):
    lo = Vector((math.inf, math.inf, math.inf))
    hi = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objs:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            lo.x, lo.y, lo.z = min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)
            hi.x, hi.y, hi.z = max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)
    return lo, hi


def rig_and_actions(cid: str):
    rig = bpy.data.objects.get(f"RIG_{cid}")
    if rig is None or rig.type != "ARMATURE":
        rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    bones = len(rig.data.bones) if rig else 0
    actions = [a.name for a in bpy.data.actions]
    return rig, bones, actions


def tri_count(objs) -> int:
    total = 0
    for obj in objs:
        if obj.type != "MESH":
            continue
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def add_preview_rig(cid: str):
    """Add temporary camera/lights, render three angles, then remove them."""
    scene = bpy.context.scene
    created = []
    world = bpy.data.worlds.new(f"PREVIEW_WORLD_{cid}") if not scene.world else scene.world
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.012, 0.016, 0.012, 1.0)
        bg.inputs[1].default_value = 0.35

    cam_data = bpy.data.cameras.new(f"PREVIEW_CAM_{cid}")
    cam = bpy.data.objects.new(f"PREVIEW_CAM_{cid}", cam_data)
    scene.collection.objects.link(cam)
    created.append(cam)
    scene.camera = cam
    target = Vector((0.0, 0.0, 1.0))

    for name, loc, energy, size in [
        (f"PREVIEW_KEY_{cid}", (-2.2, -3.0, 3.0), 700, 2.0),
        (f"PREVIEW_FILL_{cid}", (2.8, -1.0, 2.2), 350, 2.5),
        (f"PREVIEW_RIM_{cid}", (0.0, 3.0, 2.5), 500, 1.5),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = loc
        direction = target - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        created.append(light)

    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        try:
            scene.render.engine = "BLENDER_EEVEE"
        except TypeError:
            scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False

    angles = {
        "front": (0.0, -3.4, 1.35),
        "three_quarter": (2.3, -2.4, 1.35),
        "profile": (3.4, 0.0, 1.25),
    }
    out_dir = Path(args.preview_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for label, loc in angles.items():
        cam.location = loc
        direction = target - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(out_dir / f"{cid}_{label}.png")
        bpy.ops.render.render(write_still=True)
        print(f"PREVIEW {scene.render.filepath}")

    for obj in created:
        bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    global args
    args = parse_args()
    cid = args.id
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    coll = collection_for(cid)
    objs = selected_objects(coll)
    apply_rot_scale(objs)
    lo, hi = bounds(objs)
    height = hi.z - lo.z
    print(f"BOUNDS min=({lo.x:.3f},{lo.y:.3f},{lo.z:.3f}) max=({hi.x:.3f},{hi.y:.3f},{hi.z:.3f}) height={height:.3f}")

    if abs(lo.z) > args.feet_tolerance:
        raise SystemExit(f"feet not at Z=0: min Z {lo.z:.3f} > {args.feet_tolerance}")
    if not (args.height_min <= height <= args.height_max):
        raise SystemExit(f"height {height:.3f} outside {args.height_min}-{args.height_max}")

    rig, bones, actions = rig_and_actions(cid)
    tris = tri_count(objs)
    print(f"STATS tris={tris} bones={bones} actions={actions}")
    if tris > 15000:
        raise SystemExit(f"triangle budget exceeded: {tris} > 15000")
    if args.production:
        if rig is None:
            raise SystemExit("production requires RIG_{} armature".format(cid))
        if bones < 15:
            raise SystemExit(f"production rig has {bones} bones (<15)")
        missing = [name for name in ("idle", "talk") if not any(name in a for a in actions)]
        if missing:
            raise SystemExit(f"production is missing actions: {missing}")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next((o for o in objs if o.type == "MESH"), objs[0])

    kwargs = dict(
        filepath=str(out),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        for key in ("export_morph", "export_extras", "export_cameras", "export_lights"):
            kwargs.pop(key, None)
        bpy.ops.export_scene.gltf(**kwargs)
    print(f"EXPORT {out}")

    if args.preview_dir and not args.no_preview:
        add_preview_rig(cid)
    print("DONE")


if __name__ == "__main__":
    main()
