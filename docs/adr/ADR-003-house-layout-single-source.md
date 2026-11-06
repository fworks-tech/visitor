# ADR-003: Single-source floor plan and floor-aware room lookup

- **Status:** Accepted
- **Date:** 2026-11-05
- **Deciders:** Fabio Ritzel Borges
- **Supersedes:** none
- **Related:** `docs/HOUSE_SYSTEM.md`, `tests/HouseLayoutTest.gd`

## Context

The house rebuild introduced `LAYOUT` as a single table for four floors, but kept
the older per-floor tables (`ROOM_POSITIONS`, `SECOND_FLOOR_ROOMS`,
`ATTIC_*`, `BASEMENT_*`, `ROOM_SIZES`, `DOORS`) because the geometry builders
still took separate dictionaries.

Two problems followed:

1. Two sources of truth for the same plan. A room moved in `LAYOUT` would still
   be built, collided and lit at its old coordinates.
2. `get_room_at()` iterated every floor and compared only x/z. Because all
   floors share the same coordinates, the ground floor always won the tie. The
   HUD named the second-floor storage "BEDROOM" and the guest room "KITCHEN",
   defeating the floor-name commit.

The data validator was also stale: it pointed at `visitor/assets/...`, so it
failed before checking anything.

## Decision

1. `House3D.LAYOUT` is the only floor plan. The duplicated tables are deleted.
2. Builders take a floor id and derive rooms, sizes and doors through
   `_floor_rooms()`, `_floor_sizes()` and `_floor_doors()`.
3. `get_room_at(pos)` resolves the floor first with `floor_at_y(pos.y)`, then
   compares room centers on that floor only.
4. Every room id must have a `HouseScene.ROOM_NAMES` entry.
5. The contract is enforced twice:
   - `tests/HouseLayoutTest.gd` (`--layout-test`) walks all rooms and fails on a
     wrong floor resolution.
   - `tests/validate_systems.py` parses `LAYOUT` and `ROOM_NAMES` and fails if a
     per-floor table returns.

## Consequences

Positive:

- One edit moves a room everywhere: visuals, collision, lights, HUD, loot.
- The HUD reports the real room on every floor.
- Layout regressions fail fast without launching the game.
- CI can validate the plan without Godot.

Negative:

- Builders depend on small derived dictionaries; adding a builder means using
  the helpers instead of reading constants.
- `get_room_at()` now depends on a meaningful player height. A camera detached
  from the player (debug fly) can report the wrong floor; tests always pass a
  world position with the floor offset.

## Alternatives considered

- **Keep duplicates and add a sync check.** Rejected: a sync failure is still a
  silent visual bug until someone runs the check.
- **Pass a floor argument to `get_room_at` from every caller.** Rejected: the
  caller often only has a world position, and the HUD would still need to know
  the floor. Height is already in the position.
- **Generate `LAYOUT` from the old tables at parse time.** Rejected: keeps the
  old tables alive and makes the source ambiguous.

## Compliance

- `python3 tools/run_gates.py` includes `--layout-test`.
- `python3 tests/validate_systems.py` runs in CI on every push.
