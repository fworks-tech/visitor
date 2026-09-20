# AGENTS.md — Visitor (Dead Hours: Visitor)

> Engineering manual for AI agents and collaborators working on this project.
> Engine: **Godot 4.x** · Target: **Android + iOS (portrait, touch-first)**

---

## What This Game Is

A zombie-apocalypse reimagining of the visitor-inspection genre ("Papers, Please" × "No, I'm not a Human" × the Mandela Catalogue). For seven nights, survivors knock on your door. Some are human. Some are infected mimicking humans. You inspect them for signs and decide: **LET IN, TURN AWAY, or ELIMINATE**. Wrong calls have delayed, compounding consequences.

**Art direction:** hand-drawn illustrations pushed through a rasterizer for an uncanny almost-photographic look. Green monochrome UI. VHS/CRT distortion. The horror is in the *almost right*.

---

## Project Layout

```
visitor/
├── project.godot              # 11 autoloads, landscape viewport 1280×720, [input] actions (WASD/setas/gamepad/touch)
├── autoload/                  # Singletons (load order matters)
│   ├── GameManager.gd         # State machine: SPLASH→MENU→NIGHT→INSPECTION→DAY→PAUSED→GAME_OVER. Trust & corruption meters, day counter (1-7).
│   ├── StoryManager.gd        # Night-by-night story beats from story.json
│   ├── FlagsManager.gd        # Persistent story flags
│   ├── SaveManager.gd         # JSON save/load to user:// (has_save_file, delete_save)
│   ├── AudioManager.gd        # Bus control; silence-first design (see docs/AUDIO_DIRECTION.md)
│   ├── SceneManager.gd        # change_scene(path, fade) — always use this, never get_tree().change_scene
│   ├── SettingsManager.gd     # set_setting/get_setting, apply/save/load, haptics
│   ├── VisitorManager.gd      # Visitor queue per night. Decision enum: LET_IN/TURN_AWAY/ELIMINATE. prepare_night_queue(day), start_next_inspection(), process_decision(decision)
│   ├── SignsManager.gd        # Bridge to SignsSystem — AP-based sign inspection
│   ├── ResourceSystem.gd     # food/water/ammo/medicine/fuel; add_resources, get_resources, consume_*
│   └── ConsequenceSystem.gd   # Delayed consequence queue (infected_let_in turns days later, etc.)
├── scripts/
│   ├── core/                  # SplashScreen.gd, MainMenu.gd
│   ├── gameplay/              # InspectionScene.gd (core loop), DayPhaseScene.gd
│   ├── systems/               # Node-based logic (SignsSystem, InfectionSystem, ConsequencesSystem, ResourceManager)
│   └── ui/                    # GameOver.gd, Settings.gd, PauseMenu.gd, CRTController.gd
├── scenes/
│   ├── core/                  # SplashScreen.tscn (main scene), MainMenu.tscn
│   ├── gameplay/              # InspectionScene.tscn, DayPhaseScene.tscn
│   ├── ui/                    # GameOver.tscn, Settings.tscn, PauseMenu.tscn
│   └── effects/               # CRTOverlay.tscn
├── assets/
│   ├── data/
│   │   ├── visitors.json      # 20 visitors: backstory, dialogue chains, signs, thresholds, consequences
│   │   └── story.json         # 7-night arc, 14 day/night events, 7 endings
│   ├── images/
│   │   ├── portraits/         # 20 uncanny visitor portraits (analog horror style)
│   │   └── backgrounds/       # door_view.png, apartment_interior.png
│   └── models/
│       ├── furniture/         # Kenney Furniture Kit (CC0)
│       ├── building/          # Kenney Building Kit (CC0)
│       ├── atomic/            # Atomic Realm Hospital Assets — commercial use ok, NO raw redistribution (repo stays private)
│       └── blackmire/         # BlackMire PSX School & Asylum — commercial use ok, NO raw redistribution (repo stays private)
├── scripts/
│   ├── house/                 # HouseScene.gd, House3D.gd, HousePlayer3D.gd — first-person walkable shelter
│   └── door/                  # VisitorBody3D.gd (shared NPC body), VisitorDiorama3D.gd (door stage)
├── tools/                     # run_gates.py (all gates), measure_models.gd, sight_audit.gd, placement_audit.gd
├── tests/                     # DoorFlowTest.gd (--door-test), HouseWalkTest.gd (--house-test), validate_systems.py
├── locale/                    # en.json + pt_BR.json (119 keys, loaded at runtime by SettingsManager)
├── shaders/                   # crt.gdshader, vhs.gdshader, glitch, green tint
├── theme/visitor_theme.tres   # Green monochrome Theme (Courier New / terminal aesthetic)
├── tests/validate_systems.py  # System integration test runner
└── docs/                      # AUDIO_DIRECTION.md, PORTRAIT_PROMPTS.md
```

---

## Core Loop

```
NIGHT:  knock → conversational inspection at the door (3D figure + PNG portrait):
        LISTEN (dialogue_chain beats, typewriter) → unlocks ASK/LOOK →
        unlocks STUDY + LET_IN / TURN_AWAY / ELIMINATE → consequences queue
DAY:    walkable shelter (HouseScene, FPS): scavenge, fortify, talk, TV/radio,
        flashlight battery, check rooms → sleep → advance to next night
AFTER 7 NIGHTS or on collapse: ending (7 total; Infected > Executioner > Exile
> Pariah > Hermit > Cure > Gatekeeper)
```

### The infection trick
Every visitor carries a hidden `infection_progress` (0.0–1.0). Signs only manifest past thresholds — an infected visitor at 0.2 looks completely human. LET IN a latent carrier and they turn *inside* days later (delayed consequence). This is the heart of the game's doubt mechanic.

---

## Conventions (do not break)

1. **Never call `get_tree().change_scene_to_file()`** — use `SceneManager.change_scene(path)`.
2. **All gameplay state changes go through GameManager** — `change_state()` emits `state_changed`; scenes should listen, not poll.
3. **Scene scripts must never instantiate autoloads** — they're singletons; call them directly (`GameManager.start_night_phase()`).
4. **New visitors go in `visitors.json`**, new signs in `signs.json`. Both are loaded at runtime — no hardcoding visitor data in scripts.
5. **Green monochrome only.** UI colors come from `theme/visitor_theme.tres`. No blues/reds/purples.
6. **Silence-first audio.** See `docs/AUDIO_DIRECTION.md` — no gameplay music, CRT hum is constant, knocks are the signature sound.
7. **Portraits stay uncanny.** Generation prompts in `docs/PORTRAIT_PROMPTS.md` — hand-drawn → rasterizer → almost-photographic.
8. **CC0-only third-party 3D, with two paid-tier exceptions already in repo** (Atomic Hospital, BlackMire PSX) — their raw files must never leave a private repo; ship only inside compiled builds. Notices in `assets/models/*/NOTICE.txt`.
9. **Every prop rests on something.** Run `godot --headless --path . --script res://tools/placement_audit.gd` after touching House3D; 0 FAIL is the gate.
10. **Headless gates before done:** run all five with `python3 tools/run_gates.py` (door-test 21 checks, house-test 23 checks, placement audit, focus audit, validate_systems.py) — exit code 1 on any failure.

## Adding a New Visitor

1. Append to `assets/data/visitors.json`: id, name, portrait path, backstory, dialogue chain, sign map, infection_progress, correct_decision, consequence hooks.
2. Portrait goes in `assets/images/portraits/` following PORTRAIT_PROMPTS.md style.
3. Validate: `python3 tests/validate_systems.py`.

---

## Status

- ✅ Architecture, autoloads, core systems, shaders, theme, data (20 visitors, 40 signs, 7 endings), base scenes, portraits/backgrounds
- ✅ Walkable 3D shelter (HouseScene + House3D + HousePlayer3D), door conversation (tiers + typewriter + jump scare + PNG portrait), 3D NPC body shared house/door, flashlight battery loop, locale EN/PT-BR, story events
- ✅ Controls: [input] action table, gamepad (left stick move, right stick look, A/X/Y), touch (virtual joystick + drag-look + on-screen buttons, auto-on for touchscreens), keyboard unchanged
- ✅ Audio: synthesized silence-first cue set (assets/audio, tools/audio_synth.py), 5-bus AudioManager, knocks/decisions/sign-reveals/glitches/UI clicks wired (see AUDIO_DIRECTION.md)
- ⏳ Playtesting, balancing infection thresholds (blocked on device QA + playtest data)
- ✅ Mobile export presets: Android Debug/Release (landscape 1280×720, min SDK 24, target 34); see docs/EXPORT_GUIDE.md + docs/SIGNING_GUIDE.md
