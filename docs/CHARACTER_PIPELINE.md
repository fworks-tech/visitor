# Character Pipeline

How a visitor goes from a portrait and a character brief to a 3D actor at the
door. The runtime is Godot 4.x; the asset is a glTF/GLB, not code-generated
geometry. The blockout lane is runnable in this repository; the production lane
is the Blender path used for final art.

## Why not pure code

A convincing 3D horror character is mostly authored asset work:

- **Mesh:** body, clothing, hair and silhouette. Procedural primitives read as
  mannequins; the uncanny face needs sculpted or scanned form.
- **Texture/material:** skin, eyes, mouth, cloth, dirt, wetness. The analog grade
  is applied in Godot, but the albedo/normal detail starts in a texture tool.
- **Rig/animation:** a humanoid skeleton and an idle/breath/turn set. Without it
  the visitor reads as a statue.
- **Engine layer:** collision, state machine, aperture framing, corruption,
  lighting and the portrait face card. This is the part code owns.

## Two lanes, one contract

| Lane | Tool | Output | Used for |
|---|---|---|---|
| Blockout | `tools/characters/build_character.py` | low-poly GLB + portrait face card | demo, greybox, scale/pose checks |
| Production | Blender (sculpt, retopo, rig, bake) | skinned GLB/FBX + textures | final visitors |

Both lanes target the same files and node names:

```
assets/models/visitors/v001.glb
assets/models/visitors/v003.glb
assets/models/visitors/v008.glb
```

## Stages

1. **Brief and spec.** Add a character to
   `tools/characters/character_specs.json`: id, name, portrait, height, shoulder,
   hair, palette tints. The portrait is the palette source.
2. **Blockout.** Run the generator. It samples skin/coat/hair from the portrait,
   builds a box humanoid, and puts the portrait face band on an emissive card.
3. **Sculpt and retopo.** In Blender, use the blockout only for scale and pose.
   Sculpt the head and hands first; retopo to a mobile budget. Keep the feet at
   the origin and the face toward +Z.
4. **UV and texture.** One 1k or 2k atlas for body/cloth, a separate face card or
   face region. Bake AO/normals. Keep the green grade in the engine so the asset
   stays reusable.
5. **Rig and animate.** Humanoid armature, skin weights, at least `idle` and
   `talk` clips. Optional: `blink`, `step_in`, `turn`. Bake at 30 fps.
6. **Export.** glTF 2.0 binary, +Y up, +Z forward, origin at feet. Include the
   `portrait_face` material. No cameras or lights in the export.
7. **Import.** Godot imports the `.glb` as a `PackedScene` under
   `res://assets/models/visitors/`. Commit the `.glb` and its `.import`.
8. **Validate.** `python3 tools/characters/validate_characters.py` checks the
   GLB header, primitives, UVs and face material.
9. **Wire.** In demo mode, `VisitorBody3D` loads `<visitor-id>.glb`; in the full
   game, a visitor can opt in with `"character_model": "res://..."`. The body
   still owns corruption, signs and the aperture stage when the procedural body
   is active.

## Contract

- 1 unit = 1 metre. Feet at y=0. Front toward +Z.
- Height 1.75-1.85 m; shoulder 0.50-0.58 m for a blockout.
- At least one primitive with `POSITION`, `NORMAL`, `TEXCOORD_0`.
- Material name `portrait_face` carries the face texture.
- Mobile budget: <= 15k triangles, <= 2 materials plus the face, 1k/2k textures.
- No cameras/lights in the export.
- Keep the node name equal to the visitor id.

## Current demo cast

| Id | Character | Model | Notes |
|---|---|---|---|
| v001 | Marcus Vane | `v001.glb` | tall, dark coat, short hair |
| v003 | Arthur Pendelton | `v003.glb` | heavier coat, cap |
| v008 | Veronica Reyes | `v008.glb` | long hair, narrower shoulders |

The generated GLBs are **blockouts**, not final art. They prove the import,
framing, material and demo path. Replacing them with Blender exports needs no
scene changes.

## Godot integration

`scripts/door/VisitorBody3D.gd`:

- `_model_path(visitor)` returns `character_model` if present, otherwise the
  demo path when `StoryManager.story_data.demo` is true.
- `_build_external_model()` instantiates the `PackedScene` and returns early, so
  the procedural body is skipped.
- External models have no procedural face/sign geometry yet; `show_sign()` and
  `reveal()` safely no-op when there is no procedural head. The production
  model should add sign attachments or a face swap before shipping.

## QA gates

- [ ] GLB loads in Godot with no import errors.
- [ ] Model faces the camera in the door diorama and all four apertures.
- [ ] Feet at the floor; head inside the aperture mask.
- [ ] Face material is readable at night without blowing out.
- [ ] Silhouette reads at 720p and on a phone screenshot.
- [ ] Triangle/material budget checked.
- [ ] `python3 tests/validate_systems.py` and `--demo --door-test` pass.

## Licensing

Only commit models and textures with a clear license or original authorship.
Record source, author and license in `ATTRIBUTIONS.md` when a third-party base
mesh, texture or animation is used.
