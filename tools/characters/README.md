# Character pipeline

This folder is the entry point for visitor characters. It has two lanes that
share one contract:

1. **Blockout lane (runs here, no Blender):** `build_character.py` reads
   `character_specs.json`, samples the visitor portrait, and writes a low-poly
   `.glb` with the portrait face band embedded as an emissive face card.
2. **Production lane:** replace the same character IDs with authored glTF/GLB
   exports from Blender (sculpt, retopo, rig, bake), keeping the same bounds,
   forward axis (+Z), origin (feet at 0), face band and material names.

## Commands

```bash
python3 tools/characters/build_character.py
python3 tools/characters/validate_characters.py
```

Outputs go to `assets/models/visitors/<visitor-id>.glb`. In demo mode,
`VisitorBody3D` automatically uses `<id>.glb`; the full game keeps the
procedural body unless a visitor declares `character_model`.

## Contract

- 1 unit = 1 metre; origin at the feet; front faces **+Z**.
- Height ~1.75-1.85 m; shoulders 0.50-0.58 m for the blockout.
- At least one primitive with `POSITION`, `NORMAL`, `TEXCOORD_0`.
- A material named `portrait_face` with the portrait texture.
- Keep the face visible under night lighting (emissive card in the blockout).
- Max 15k triangles for a mobile visitor; one or two materials plus the face.
- No animations required for the blockout; production exports may add a
  `AnimationPlayer`/`idle` clip.

## Current demo casts

`v001` Marcus Vane, `v003` Arthur Pendelton, `v008` Veronica Reyes. Their
portraits are the palette source, so the 3D blockout already belongs to the
same grade as the door scene.

## Production notes

Blender is not installed in this sandbox. The blockout lane exists so the demo
can ship before the sculpt is ready. The production replacement should keep
the node name `v001`/`v003`/`v008` and the same origin so no scene code changes.
See `docs/CHARACTER_PIPELINE.md` for the full stage list and QA gates.


## OpenCode / Blender handoff

When the work moves from blockout to a real Blender asset, give the agent:

- `docs/BLENDER_AGENT_PLAYBOOK.md` (rules, contract, acceptance, stop conditions)
- `tools/characters/OPENCODE_TASK.md` (copy-paste task for one character)
- `tools/characters/blender_export.py` (export + 3-angle review renders)
- `tools/characters/validate_blender_output.py` (strict GLB contract check)

Start with the environment check:

```bash
tools/characters/check_blender_env.sh
```

The expected target is **L2 GAME_READY**: silhouette, clothes, hands, hair and
face; 15k tris; 20-25 bones; `idle` and `talk`; validated GLB. L3 HERO needs a
sculpted base or a human artist, not an LLM-only pass.
