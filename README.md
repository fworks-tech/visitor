# Visitor

> Formerly working-titled **"Dead Hours: Visitor"**. Dead Hours is a separate
> game; this project is Visitor. The legacy name remains in `project.godot`
> until the store title is locked.

A first-person 3D shelter and door-inspection horror game for mobile, built in
Godot 4.x. For seven nights, someone knocks on your door. You inspect them for
signs of infection and decide: let them in, turn them away, or eliminate them.
Some of the infected look almost human. Almost.

> Papers, Please x "No, I'm not a Human" x the Mandela Catalogue: a fate-arbiter
> game where the horror is in the *almost right*.

## Current State

| Area | Status |
|---|---|
| Core loop | Seven-night campaign data, 20 visitors, 40 signs, seven endings |
| Door scene | Full-screen cinematic doorway with 3D visitor, environment plate, typewriter dialogue and choices |
| Aperture system | `doorway`, `peephole`, `window`, `door_crack`, `hatch`; eight environments |
| Shelter | Four-floor 3D apartment, scavenging, stairs, flashlight, guests |
| Demo | Two nights, three visitors, two endings, runnable without the full campaign |
| Characters | L1 blockouts + Character DNA contract; L2 Blender production is the next gate |
| Quality | Data, layout, house, door and balance gates pass; device QA is pending |

## Start Here

```bash
# Play the two-night demo
tools/run_demo.sh
# or: godot --path . -- --demo

# Run the data contracts without Godot
python3 tests/validate_systems.py

# Run every engine gate (Godot 4.x on PATH or GODOT_BIN)
python3 tools/run_gates.py
```

## The Premise

The outbreak started six days ago. You're holed up in your apartment with
limited supplies. Every night, survivors knock: desperate, cold, convincing.
Some carry the infection, and in its early stages it mimics humanity perfectly:
the right words, the right tears, the wrong details.

You have three choices at every door:

- **LET IN**: gain an ally, a drain on resources, or a threat that turns inside
  your walls days later
- **TURN AWAY**: stay safe tonight, carry the scream you heard walk away
- **ELIMINATE**: certain, final, and it changes what you are

Trust and corruption track who you're becoming. After seven nights, the game
ends: one of seven endings, depending on who you let in, who you turned away,
and what you're willing to live with.

## Key Features

- **Uncanny analog-horror art**: hand-drawn portraits through a rasterizer,
  almost photographic and subtly wrong. Green monochrome UI, VHS/CRT distortion.
- **Sign-based inspection**: spend limited action points on physical checks
  (wounds, pallor, movement) and behavioral questions (story consistency,
  emotional reactions). No single sign is proof. Judgment is.
- **A shelter you walk**: first-person 3D apartment across four floors, with
  scavenging, flashlight battery, guests, and stairs that open as the week
  progresses.
- **A door conversation**: a full-screen doorway with the visitor standing in
  the environment, typewriter dialogue and choices ("Come in." / "You better
  leave."). Peephole, window, crack and hatch views use the same composite. See
  [docs/APERTURE_VIEWS.md](docs/APERTURE_VIEWS.md).
- **Delayed consequences**: the infected don't reveal themselves at the door.
  A wrong LET IN turns days later, inside.
- **Resource pressure**: survivors inside eat and drink. Generosity has a cost.
- **Silence-first audio**: no gameplay music. CRT hum, knocks, and what you
  hear through the door.

## Demo

The two-night slice uses `assets/data/story_demo.json` and the three GLB visitors
(`v001`, `v003`, `v008`). It runs through the same `StoryManager`,
`GameManager`, `VisitorManager` and `InspectionScene` as the full game, so a
demo change cannot silently fork the campaign.

Scope, cut list and QA gates: [docs/DEMO.md](docs/DEMO.md).

## Character Pipeline

Visitors are GLB assets, not pure code. The repository has a runnable blockout
lane (portrait palette + face card), a deterministic Character DNA contract, and
a production Blender handoff:

```bash
python3 tools/characters/build_character.py
python3 tools/characters/validate_character_dna.py
python3 tools/characters/validate_characters.py
python3 tools/characters/validate_blender_output.py --id v001
```

- Blockout and production contract: [docs/CHARACTER_PIPELINE.md](docs/CHARACTER_PIPELINE.md)
- Why character creators work, and what "precision" means:
  [docs/CHARACTER_GENERATION_RESEARCH.md](docs/CHARACTER_GENERATION_RESEARCH.md)
- Blender + OpenCode handoff:
  [docs/BLENDER_AGENT_PLAYBOOK.md](docs/BLENDER_AGENT_PLAYBOOK.md)
- Copy-paste task: [tools/characters/OPENCODE_TASK.md](tools/characters/OPENCODE_TASK.md)

The current demo cast is L1: low-poly bodies with portrait face cards. The L2
gate requires a rig, `idle`/`talk`, at most 15k triangles and at most four
materials. Blender is not required to play or test the game.

## Tech

- **Engine:** Godot 4.x (GDScript), Forward Plus renderer, 11 autoload singletons
- **Viewport:** 1280x720 landscape, `canvas_items` stretch with `expand`
- **Data-driven:** visitors, signs, story nights, endings, aperture presets and
  the floor plan live in JSON and one `LAYOUT` table
- **Character data:** `tools/characters/character_specs.json` v2 with a
  validated `dna` block per visitor
- **Platform:** Android + iOS, landscape, touch-first with keyboard and gamepad

## Project Structure

| Path | What |
|------|------|
| `autoload/` | GameManager, StoryManager, FlagsManager, SaveManager, AudioManager, SceneManager, SettingsManager, VisitorManager, SignsManager, ResourceSystem, and the ConsequencesSystem bridge |
| `scripts/gameplay/` | `InspectionScene` (the core door loop) |
| `scripts/house/` | `House3D` (floor plan and builders), `HouseScene` (HUD and actions), `HousePlayer3D` (walker) |
| `scripts/door/` | `ApertureStage`, `VisitorBody3D`, `VisitorDiorama3D` |
| `scripts/ui/` | CRT, aperture overlay, weapon and bolt overlays, menus |
| `scenes/` | Core, gameplay, house, UI and effects scenes |
| `assets/data/` | `visitors.json` (20 visitors), `signs.json` (40 signs), `story.json` (7 nights, 7 endings), `story_demo.json`, `view_presets.json` |
| `assets/models/visitors/` | Demo GLBs (`v001`, `v003`, `v008`) |
| `tools/characters/` | Blockout generator, DNA schema/validator, Blender export, OpenCode task |
| `tests/` | Door, house walk, house layout, balance and data contracts |
| `docs/` | Systems, art, audio, production, research and QA; index in [docs/README.md](docs/README.md) |
| `docs/adr/` | Architecture decision records |

## The Shelter

The apartment is one floor plan loaded from `House3D.LAYOUT`: ground floor,
second floor (unlocks night 3), attic (night 5) and basement (night 7). Each
room declares a position, a size and which walls have doors. Walls, connectors,
collision, lights and the HUD room name all derive from that table.

Stairs are real geometry with ramp collision, not teleport holes. The stair
action still places the player on the correct landing as a travel shim, and the
landing height is resolved per action.

`get_room_at()` resolves the floor from the player's height before the room, so
the upper halls and storage rooms report their own names instead of their
ground-floor twins.

## Visual Direction

The target is analog horror in the vein of "No, I'm not a Human": uncanny,
almost-photographic faces, one lit detail in a dark frame, green monochrome UI
and analog decay. The Godot implementation, starting values and one-week sprint
live in [docs/ART_DIRECTION_ANALOG.md](docs/ART_DIRECTION_ANALOG.md). The engine
decision is recorded in
[docs/ENGINE_EVALUATION.md](docs/ENGINE_EVALUATION.md).

## Testing and Gates

```bash
# All headless gates (needs Godot 4.x on PATH or GODOT_BIN)
python3 tools/run_gates.py

# Data + layout contracts only (no Godot required, runs in CI)
python3 tests/validate_systems.py

# Character contracts
python3 tools/characters/validate_character_dna.py
python3 tools/characters/validate_characters.py

# Individual engine gates
godot --headless --path . -- --door-test
godot --headless --path . -- --house-test
godot --headless --path . -- --layout-test
godot --headless --path . -- --balance-test

# Aperture view playground
godot --path . -- --aperture-demo
```

CI is available as a template in `docs/ci/contract-workflow.yml`. This
repository has not enabled GitHub Actions yet; copy it to
`.github/workflows/contract.yml` to run the data gate on every push.

## Documentation

Start with [docs/README.md](docs/README.md). The most-used documents are:

- [AGENTS.md](AGENTS.md): architecture map, conventions and agent rules
- [docs/HOUSE_SYSTEM.md](docs/HOUSE_SYSTEM.md): floor plan and collision contract
- [docs/APERTURE_VIEWS.md](docs/APERTURE_VIEWS.md): door and window composition
- [docs/CHARACTER_PIPELINE.md](docs/CHARACTER_PIPELINE.md): blockout to L2/L3
- [docs/CHARACTER_GENERATION_RESEARCH.md](docs/CHARACTER_GENERATION_RESEARCH.md): research and DNA rationale
- [docs/BLENDER_AGENT_PLAYBOOK.md](docs/BLENDER_AGENT_PLAYBOOK.md): OpenCode production rules
- [docs/QA_LOG.md](docs/QA_LOG.md): test history and open QA items

## The Seven Endings

Survive all seven nights and the epilogue is decided by your accumulated trust,
corruption, and who's still breathing inside your walls: the Gatekeeper, the
Pariah, the Executioner, the Hermit, the Cure, the Infected, the Exile.

## Known Gaps

- Android and iOS device QA is still pending: safe area, touch targets, final
  framing and performance.
- L2 character models and rigs are not produced yet; the demo uses L1 blockouts.
- Environment plates are first-pass placeholders and can be replaced without
  touching the composite code.
- The CI workflow is a template, not active in this repository.

---

**License:** Proprietary. All rights reserved.
**By:** Fabio Ritzel Borges
