# House System

The shelter is a first-person 3D space built at runtime from data. This page is
the contract for anyone adding a room, a floor, a prop or a stair.

## One floor plan

`House3D.LAYOUT` is the only floor plan:

```gdscript
const LAYOUT := {
    "ground": {
        "hall": {"pos": Vector3(0, 0, 0), "size": Vector2(6, 6),
                 "doors": {"n": true, "s": true, "e": true, "w": true}},
        # ...
    },
    # second, attic, basement
}
```

- `pos` is local to the floor. Height comes from `FLOOR_Y`.
- `size` is the full room footprint in meters.
- `doors` lists which walls have a gap. A gap only becomes passable when a
  facing neighbour also has a door (`_linked_doors`).

There are no per-floor copies. The builders receive plain dictionaries derived
from `LAYOUT`:

| Helper | Returns |
|---|---|
| `_floor_rooms(floor)` | `{room: Vector3}` |
| `_floor_sizes(floor)` | `{room: Vector2}` |
| `_floor_doors(floor)` | `{room: {n/s/e/w: bool}}` |
| `_room_pos(room, floor := "ground")` | one room position |

## Floors

| Floor | Y | Unlocks | Rooms |
|---|---:|---|---|
| ground | 0.0 | night 1 | hall, bedroom, kitchen, office, bathroom |
| second | 3.2 | night 3 | hall_up, storage, guest_room |
| attic | 6.4 | night 5 | attic_hall, attic_storage |
| basement | -3.2 | night 7 | basement_hall, generator_room, cellar |

Unlock logic lives in `_compute_unlocked_floors()`. `set_unlocked_floors()`
clears static bodies and rebuilds collision, obstacles and interactables, so
ramps and barricades always match the current floor set.

## Room lookup

Every floor repeats x/z, so height decides the floor first:

```gdscript
func floor_at_y(y: float) -> String      # nearest floor by absolute height
func get_room_at(pos: Vector3) -> String # floor, then nearest room center
```

`HouseScene._process()` calls `get_room_at(player.global_position)` and writes
`ROOM_NAMES[room]` to the HUD. If a room id is missing from `ROOM_NAMES`, the
label reads "ROOM".

Regression guard: `tests/HouseLayoutTest.gd` walks every room on every floor and
asserts the id, plus the exact collisions that used to fail (second-floor
storage returning "bedroom", guest room returning "kitchen").

## Stairs

- Column: `STAIR_X0 = 1.7`, `STAIR_X1 = 2.9`.
- Run: `STAIR_ZB = 2.3` (south base) to `STAIR_ZT = -2.3` (north top).
- Rise: 3.2 per floor, 4.6 run, about 35 degrees, 11 steps.
- Visuals: `_build_stair_flight()` and `_build_stair_landing()`.
- Collision: `_build_stair_ramps()` places rotated `StaticBody3D` ramps flush
  with the base and the landing. Collision is rebuilt on every unlock change.
- Guards: `_build_hatch_guards()` closes the west edge of the slot; the south
  entry stays open.
- Travel shim: `HouseScene._action_stairs()` still teleports the player to the
  landing (`STAIRS_LAND_Z`, clamped to the slot) and zeroes velocity. The ramps
  are what make the stairs walkable; the teleport only handles the floor change
  reliably on touch.

## Build order

`House3D._ready()`:

1. `_build_environment()`
2. `_compute_unlocked_floors()`
3. `_build_house()` (floors, shells, stairs, room dressing)
4. `_build_collisions()` (walls, floor slabs, connectors, stair ramps)
5. `_build_obstacles()` (barricades for locked paths)
6. `_build_interactables()`
7. `_spawn_player()`

## Adding a room

1. Add the room to `LAYOUT` on its floor.
2. Add its id to `HouseScene.ROOM_NAMES`.
3. Register interactables in `_build_interactables()` and solids in
   `_build_furniture_solids()` if it needs them.
4. Make sure each door has a facing neighbour; otherwise leave the wall solid.
5. Run `godot --headless --path . -- --layout-test` and `-- --house-test`.

## Verification

```bash
godot --headless --path . -- --layout-test   # data and lookup contract
godot --headless --path . -- --house-test    # spawn, interactables, floors
godot --path . -- --stairshot                # five stair screenshots
python3 tests/validate_systems.py            # layout + data contract, no Godot
```

`tests/validate_systems.py` also fails if a duplicated floor table returns
(`SECOND_FLOOR_ROOMS`, `ATTIC_ROOMS`, `BASEMENT_ROOMS`, `ROOM_POSITIONS`).

## Known limits

- Rooms are axis-aligned rectangles; no rotated or L-shaped rooms yet.
- Door openings are a fixed 1.6 m.
- One stair column serves all floors; there is no second stairwell.
- The teleport shim remains for touch reliability; it is not a substitute for
  the ramp collider.
- No navigation mesh: guests are placed, not pathfound.
