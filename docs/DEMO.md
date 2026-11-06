# Demo Build

A two-night vertical slice of *The Visitor*: three visitors, two outcomes, and
the same door/inspection/house loop as the full game. It is meant for a
10-minute playtest or store demo, not a replacement for the seven-night story.

## Run it

```bash
tools/run_demo.sh
# or
godot --path . -- --demo
```

The demo also runs headless through the existing harness:

```bash
godot --headless --path . -- --demo --door-test
python3 tests/validate_systems.py
```

## What is in the slice

| Item | Full game | Demo |
|---|---|---|
| Nights | 7 | 2 |
| Visitors | 20 | 3 (v001, v003, v008) |
| Endings | 7 | 2 (Gatekeeper, Pariah) |
| House | 4 floors | same house, same loop |
| Inspection | full sign set | same signs, 5 light charges |
| Decision | let in / turn away / eliminate | same, with Shoot / Hear out |

The two demo endings:

- **The Gatekeeper** — no infected admitted, corruption <= 30, trust >= 50, at
  least two survivors alive.
- **The Pariah** — at least one infected admitted.

If neither condition matches, the gatekeeper is the fallback at the end of
night 2. The demo ends when `GameManager.advance_to_next_day()` sees
`current_day >= max_days`.

## Data

`assets/data/story_demo.json` is a normal story document with:

- `"demo": true`, `"total_nights": 2`
- two `nights` with `available_visitor_pool`
- two `endings` using the existing evaluation ids

`StoryManager` loads it when `--demo` is present (or when the build has the
`demo` feature). `GameManager.start_new_game()` reads `total_nights` into
`max_days`, so the same code path handles the short run. `VisitorManager` still
uses the full `visitors.json`; the night pools limit the cast.

## Build a demo binary

Add a `demo` custom feature to an export preset (or run with `--demo` for a
local build). `StoryManager.demo_mode` checks both the command line and
`OS.has_feature("demo")`. Keep the full story data in the build; the demo
document is the only content the run reads.

## Cut list (deliberate)

- Five nights and four endings are removed.
- Only three character models are shipped; the rest of the cast is out of scope.
- No store artwork, no live-service telemetry, no post-demo progression.
- The house is unchanged, including stairs and resources, so the demo can test
  the real movement and inspection loop.

## QA checklist

- [ ] Night 1 has two knocks; night 2 has three.
- [ ] All three demo visitors load a GLB (no procedural fallback in demo mode).
- [ ] Both endings are reachable: hold the line; admit one infected.
- [ ] Demo ends after night 2, not after seven.
- [x] `--demo --door-test` passes with 0 failures (2026-11-05).
- [ ] Phone capture: safe area, dialogue box, choices, close-ups.
- [x] `python3 tests/validate_systems.py` includes the demo contract (2026-11-05).

## Known limits

The GLBs are blockouts with a portrait face card. There is no rig animation,
no facial blend shapes and no per-visitor sign geometry on the external model
yet. Those are the next production steps in
[CHARACTER_PIPELINE.md](CHARACTER_PIPELINE.md).
