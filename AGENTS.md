# AGENTS.md — Visitor

> Engineering manual for AI agents and collaborators working on this project.
> Engine: **Godot 4.x (Forward Plus)** · Target: **Android + iOS, landscape,
> touch-first**

---

## What This Game Is

A zombie-apocalypse reimagining of the visitor-inspection genre ("Papers,
Please" x "No, I'm not a Human" x the Mandela Catalogue). For seven nights,
survivors knock on your door. Some are human. Some are infected mimicking
humans. You inspect them for signs and decide: **LET IN, TURN AWAY, or
ELIMINATE**. Wrong calls have delayed, compounding consequences.

The day phase is a first-person 3D shelter: four floors, scavenging, flashlight
battery, guests, and stairs that unlock as the week progresses.

**Art direction:** hand-drawn illustrations pushed through a rasterizer for an
uncanny almost-photographic look. Green monochrome UI. VHS/CRT distortion. The
horror is in the *almost right*.

**Direction:** Godot 4.x for Visitor and DEEPTALES, recorded in
`docs/ENGINE_EVALUATION.md`. The visual target is the analog-horror pipeline in
`docs/ART_DIRECTION_ANALOG.md`: uncanny faces, practical light, green
monochrome UI, readable grain.

---

## Demo Mode

The two-night demo is a data slice, not a fork. `StoryManager` loads
`assets/data/story_demo.json` when `--demo` is in the user args or the build has
the `demo` feature. `GameManager.start_new_game()` reads `total_nights` into
`max_days`, so the same progression code ends the demo after night 2.
`VisitorManager` limits the cast through the night pools. Run it with
`tools/run_demo.sh`; validate with `--demo --door-test`.

## Character Pipeline

`VisitorBody3D` prefers a visitor's `character_model` path, and in demo mode it
automatically loads `res://assets/models/visitors/<id>.glb`. The blockout
generator lives in `tools/characters/`; the production contract (metres, feet at
origin, +Z forward, `portrait_face` material, 15k tri budget) is in
`docs/CHARACTER_PIPELINE.md`. Keep external models optional: the full game still
falls back to the procedural body, and `show_sign()`/`reveal()` no-op safely
when an external model has no procedural head.

## Project Layout

```
.
├── project.godot             # 11 autoloads, 1280x720 landscape, input actions
├── autoload/                 # singletons, load order matters
│   ├── GameManager.gd        # state machine, trust/corruption, day 1-7, harnesses
│   ├── StoryManager.gd       # night beats from story.json
│   ├── FlagsManager.gd       # persistent story flags
│   ├── SaveManager.gd        # JSON save/load in user://
│   ├── AudioManager.gd       # 5 buses, silence-first
│   ├── SceneManager.gd       # change_scene(path, fade)
│   ├── SettingsManager.gd    # settings, locale, haptics
│   ├── VisitorManager.gd     # queue, decisions, history
│   ├── SignsManager.gd       # AP-based sign inspection
│   ├── ResourceSystem.gd     # food/water/ammo/medicine/fuel
│   └── ConsequenceSystem.gd  # bridge to scripts/systems/ConsequencesSystem.gd
├── scripts/
│   ├── core/                 # splash, main menu
│   ├── gameplay/             # InspectionScene.gd (door loop)
│   ├── systems/              # ConsequencesSystem.gd
│   ├── ui/                   # game over, settings, pause, CRT
│   ├── house/                # House3D.gd, HouseScene.gd, HousePlayer3D.gd
│   └── door/                 # VisitorBody3D.gd, VisitorDiorama3D.gd
├── scenes/                   # core, gameplay, ui, effects, house
├── assets/
│   ├── data/                 # visitors.json, signs.json, story.json
│   ├── images/               # portraits, reveal variants, backgrounds
│   ├── models/               # furniture, building, atomic, blackmire
│   └── audio/                # synthesized cues
├── tests/                    # DoorFlowTest, HouseWalkTest, HouseLayoutTest,
│                             # BalanceSimTest, validate_systems.py
├── tools/                    # run_gates.py, placement_audit.gd, focus_audit.gd,
│                             # stairshot.gd, screenshot_mode.gd, audio_synth.py
├── docs/                     # audio, portraits, house system, ADRs, QA, store
├── shaders/                  # crt.gdshader, vhs.gdshader, glitch, tint
├── theme/visitor_theme.tres  # green monochrome theme
└── locale/                   # en + pt_BR, loaded at runtime
```

---

## Core Loop

```
NIGHT:  knock -> conversational inspection at the door (3D figure + portrait):
        LISTEN (dialogue beats, typewriter) -> ASK/LOOK -> STUDY + decision
        -> consequences queued
DAY:    walkable shelter: scavenge, fortify, talk, TV/radio, flashlight,
        guests -> sleep -> next night
AFTER 7 NIGHTS or on collapse: ending (7 total; priority Infected > Executioner
> Exile > Pariah > Hermit > Cure > Gatekeeper)
```

### The infection trick

Every visitor carries a hidden `infection_progress` (0.0 to 1.0). Signs only
manifest past thresholds, so an infected visitor at 0.2 looks completely human.
LET IN a latent carrier and they turn *inside* days later. That is the heart of
the game's doubt mechanic.

---

## House System (do not break)

The floor plan lives in **one** table: `House3D.LAYOUT`, keyed
`floor -> room -> {pos, size, doors}`. Room positions are local to their floor;
height comes from `FLOOR_Y`.

1. **No per-floor copies.** Walls, connectors, collision, lights and loot all
   derive from `LAYOUT` through `_floor_rooms()`, `_floor_sizes()` and
   `_floor_doors()`. Do not reintroduce `SECOND_FLOOR_ROOMS`-style tables.
2. **Room lookup is floor-first.** `get_room_at(pos)` calls `floor_at_y(pos.y)`
   before comparing room centers. Every floor repeats x/z, so a lookup that
   ignores height always returns the ground twin. `HouseLayoutTest` guards this.
3. **Every room needs a HUD name.** Add the id to `HouseScene.ROOM_NAMES`, or
   the label falls back to "ROOM".
4. **Door gaps are linked, not assumed.** `_linked_doors()` only builds a gap
   when a facing neighbour exists; otherwise the wall is solid on both sides.
5. **Stairs are real geometry plus a ramp collider.** The `_action_stairs`
   teleport is a travel shim, not the way you traverse. Landing Z comes from
   `STAIRS_LAND_Z`, clamped to the stairwell slot.
6. **Collision rebuilds on unlock.** `set_unlocked_floors()` clears static
   bodies and rebuilds, so ramps and barricades cannot go stale.

See `docs/HOUSE_SYSTEM.md` and `docs/adr/ADR-003-house-layout-single-source.md`.

---

## Aperture Views (prototype)

`ApertureStage` composites a 2D environment plate, the 3D visitor body and a
one-pass aperture shader. The data lives in `assets/data/view_presets.json`.

- Apertures: `doorway`, `peephole`, `window`, `door_crack`, `hatch`.
- Environments: porch, yard, road, hallway, kitchen, basement, bedroom,
  bathroom.
- Each environment lists compatible apertures and a character anchor for each.
- `ViewPresets.resolve()` merges defaults, aperture, environment, anchor and
  visitor override. Later wins.
- Wired into the door (`InspectionScene`) and the night window (`HouseScene` +
  `ApertureOverlay`) behind `ViewPresets.ENABLED`. The door is full-screen:
  `CinematicView` + `CinematicUI`, with a dialogue panel and the reference
  choice pair "Come in." / "You better leave.".
- Set `ViewPresets.ENABLED = false` to fall back to `VisitorDiorama3D` and the
  old split layout.
- Preview with `godot --path . -- --aperture-demo`; captures with
  `--aperture-demo --aperture-shot` or `--door-test --door-shot`.
- Keep plates 1280x720, ungraded, with the center clear for a 1.8 m body.
- See `docs/APERTURE_VIEWS.md`.

---

## Conventions (do not break)

1. **Never call `get_tree().change_scene_to_file()`**. Use
   `SceneManager.change_scene(path)`.
2. **All gameplay state changes go through GameManager**. `change_state()` emits
   `state_changed`; scenes listen, they don't poll.
3. **Scene scripts must never instantiate autoloads**. They are singletons.
4. **New visitors go in `visitors.json`**, new signs in `signs.json`. No
   hardcoded visitor data in scripts.
5. **Green monochrome only.** Colors come from `theme/visitor_theme.tres`.
6. **Silence-first audio.** See `docs/AUDIO_DIRECTION.md`.
7. **Portraits stay uncanny.** Prompts in `docs/PORTRAIT_PROMPTS.md`.
8. **CC0-only third-party 3D, with two paid-tier exceptions** (Atomic Hospital,
   BlackMire PSX). Raw files never leave the private repo; ship only inside
   compiled builds. Notices live in `assets/models/*/NOTICE.txt`.
9. **Every prop rests on something.** After touching `House3D`, run the
   placement audit; 0 FAIL is the gate.
10. **All gates before done:** `python3 tools/run_gates.py` (door, house, layout,
    balance, placement, focus, data). Exit code 1 on any failure.
11. **Data contracts run in CI.** `python3 tests/validate_systems.py` must pass
    without Godot.

---

## Adding a Room

1. Add the room to `House3D.LAYOUT` under its floor with `pos`, `size` and
   `doors`.
2. Add a matching entry to `HouseScene.ROOM_NAMES`.
3. If it needs interaction, register it in `_build_interactables()` and, for
   collision, `_build_furniture_solids()` or the room builder.
4. Check the door has a facing neighbour; a gap with no neighbour is solid.
5. Run `--layout-test` and `--house-test`. Both must report zero failures.

## Adding a Visitor

1. Append to `assets/data/visitors.json`: id, name, portrait path, backstory,
   dialogue chain, sign map, `infection_progress`, consequence hooks.
2. Portrait goes in `assets/images/portraits/` following PORTRAIT_PROMPTS.md.
3. Validate: `python3 tests/validate_systems.py`.

---

## Testing

```bash
python3 tools/run_gates.py                  # every engine gate (needs Godot)
python3 tests/validate_systems.py           # data + layout contracts (CI)

godot --headless --path . -- --door-test
godot --headless --path . -- --house-test
godot --headless --path . -- --layout-test
godot --headless --path . -- --balance-test
godot --path . -- --stairshot               # stair screenshots (real window)
```

`--layout-test` is pure data: four floors, 13 rooms, floor-aware lookup, and a
HUD name for every room.

---

## Status

- Architecture, 11 autoloads, core systems, shaders, theme, data (20 visitors,
  40 signs, 7 nights, 7 endings), portraits and backgrounds
- Walkable 3D shelter: multi-floor, real stairs with ramp collision, flashlight
  battery, guest bodies, floor-specific loot, generator fuel loop
- Door conversation: tiers, typewriter, jump scare, 3D body plus portrait
- Floor plan consolidated into `LAYOUT`; floor-aware room lookup fixes the HUD
  naming upper rooms after their ground twins
- Controls: keyboard, gamepad, touch (virtual stick, drag look, on-screen
  buttons)
- Audio: synthesized silence-first cues, 5-bus AudioManager
- All 7 endings reachable by condition analysis; 20 portraits and 7 reveals
- Pending: device playtesting, store screenshots and feature graphic

**Export:** Android Debug/Release, landscape 1280x720, min SDK 24, target 34.
See `docs/EXPORT_GUIDE.md` and `docs/SIGNING_GUIDE.md`.
