# DEEPTALES Device QA Playbook (Android)

One-click deploy from the game root:

    python3 tools/deploy_device.py --check   # env diagnostics
    python3 tools/deploy_device.py            # build + install + launch + smoke logs

Requirements: Godot 4.x (`GODOT_BIN`), Android platform-tools (`adb` on
`PATH` or `ADB_BIN`), a phone with Developer options + USB debugging.

## Per-build checklist (M4-3)

- [ ] Install via `deploy_device.py` — no signature/storage errors
- [ ] Launch: cold start < 5s to main menu (budget M4-4)
- [ ] Touch input: tap targets register on first try, no double-fire
- [ ] Safe area: no UI under notch / gesture bar, all orientations used
- [ ] Back button: opens pause menu (never exits the game mid-scene)
- [ ] Audio: ducks correctly on notification, resumes after focus loss
- [ ] Process death: background the app, kill via `adb shell am kill <pkg>`,
      relaunch — save restores at the last checkpoint
- [ ] 30-min play session: battery drain reasonable, no thermal warning
- [ ] Scene loads < 2s; RAM < 300 MB mid-tier (record actual numbers below)

## House and stairs (per build)

- [ ] Ground floor HUD reads HALL, BEDROOM, KITCHEN, OFFICE, BATHROOM
- [ ] Night 3: second floor unlocks; storage reads STORAGE, guest room reads GUEST ROOM
- [ ] Night 5: attic reads ATTIC and ATTIC STORAGE; the ladder lands on the plate
- [ ] Night 7: basement reads BASEMENT, GENERATOR ROOM, CELLAR
- [ ] Climb every stair up and down three times: no fall-through, no wall clip, no stuck landing
- [ ] Barricades block locked paths and clear on the unlock day
- [ ] Save on an upper floor, kill the app, relaunch: same floor and room restored
- [ ] Doorways never open into void; connectors have floor and side walls

## Per-game QA log (fill during passes)

| Date | Build | Device/Android | Cold start | RAM | Battery/30min | Issues |
|---|---|---|---|---|---|---|

Playtest coverage (M4-5): use the flags/save cheat to reach every ending —
trace `assets/data/story.json` events by hand to see which remain unvisited.
