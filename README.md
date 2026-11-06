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
- **Delayed consequences**: the infected don't reveal themselves at the door.
  A wrong LET IN turns days later, inside.
- **Resource pressure**: survivors inside eat and drink. Generosity has a cost.
- **Silence-first audio**: no gameplay music. CRT hum, knocks, and what you
  hear through the door.

## Tech

- **Engine:** Godot 4.x (GDScript), Forward Plus renderer, 11 autoload singletons
- **Viewport:** 1280x720 landscape, `canvas_items` stretch with `expand`
- **Data-driven:** visitors, signs, story nights, endings and the floor plan live
  in JSON and one `LAYOUT` table
- **Platform:** Android + iOS, landscape, touch-first with keyboard and gamepad

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

# Individual engine gates
godot --headless --path . -- --door-test
godot --headless --path . -- --house-test
godot --headless --path . -- --layout-test
godot --headless --path . -- --balance-test

# Stairwell screenshots for visual review (real window)
godot --path . -- --stairshot
```

## Project Structure

See [AGENTS.md](AGENTS.md) for the architecture map and conventions, and
[docs/HOUSE_SYSTEM.md](docs/HOUSE_SYSTEM.md) for the floor plan contract.

| Path | What |
|------|------|
| `autoload/` | GameManager, VisitorManager, SignsManager, ResourceSystem, ConsequenceSystem, SaveManager, AudioManager, SceneManager, SettingsManager, StoryManager, FlagsManager |
| `scripts/gameplay/` | `InspectionScene` (the core door loop) |
| `scripts/house/` | `House3D` (floor plan and builders), `HouseScene` (HUD and actions), `HousePlayer3D` (walker) |
| `scripts/door/` | `VisitorBody3D`, `VisitorDiorama3D` |
| `assets/data/` | `visitors.json` (20 visitors), `signs.json` (40 signs), `story.json` (7 nights, 7 endings) |
| `tests/` | `DoorFlowTest`, `HouseWalkTest`, `HouseLayoutTest`, `BalanceSimTest`, `validate_systems.py` |
| `docs/` | Audio direction, portrait prompts, house system, ADRs, QA and store docs |

## The Seven Endings

Survive all seven nights and the epilogue is decided by your accumulated trust,
corruption, and who's still breathing inside your walls: the Gatekeeper, the
Pariah, the Executioner, the Hermit, the Cure, the Infected, the Exile.

---

**License:** Proprietary. All rights reserved.
**By:** Fabio Ritzel Borges
