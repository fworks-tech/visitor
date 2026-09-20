# DEEPTALES Playtest Script (M4-5)

Content-coverage playbook: prove every branch of the story graph is
reachable and every ending is attainable. Companion to `DEVICE_QA.md`
(which covers device behavior, not story content). Run on desktop or
device; record results in `QA_LOG.md`.

## 0. Pre-flight (both genres)

- [ ] `python3 tests/validate_systems.py` → PASSED
- [ ] Inspect `assets/data/story.json` → note checkpoint/ending counts below
- [ ] Coverage map: trace `story.json` events by hand (no graph exporter available)

Checkpoints: ___ Endings: ___

## 1. narrative_choice (Dead Hours architecture)

- [ ] Happy-path playthrough to one ending without cheats — story reads coherently, no placeholder text
- [ ] For each remaining ending: seed the deciding flags (debug flags if the build exposes them, else replay from the branching checkpoint shown in the diagram) and play to the ending screen
- [ ] Every ending displays its own title/epilogue (no neutral fallback)
- [ ] Unreachable-ending check: `validate` reports zero unreachable endings
- [ ] Flag consistency: every choice's required/set flags exist (`validate` covers this — re-run after any story edit)
- [ ] Portrait sync: every speaking character has a portrait for every emotion used (`validate` face/portrait check)
- [ ] Save/restore at 3 different checkpoints (early / mid / late) — state resumes exactly
- [ ] Locale spot-check: switch to pt-BR, replay the opening — no missing-string keys

Endings seen: ___ / ___

## 2. fate_arbiter (Visitor architecture)

- [ ] Full-night loop without cheats: inspect → observe signs → verdict → next night
- [ ] Every visitor encountered at least once across runs (___ / ___)
- [ ] Every sign observed at least once: physical ___ / ___ , behavioral ___ / ___
- [ ] Correct-verdict path and wrong-verdict path both played — consequences differ
- [ ] All endings reached (___ / ___)
- [ ] Balance notes for the tuning pass (record raw numbers, don't tune yet):
      runs ___ · false positives ___ · false negatives ___ · nights survived avg ___
- [ ] `validate` fate cross-checks pass (nights/signs/visitors consistent)
- [ ] Save/restore across a night boundary — schedule state resumes exactly
- [ ] Multi-floor unlock flow (desktop or device):
      night 1-2: stairs to 2F + basement door visible but blocked by barricades (walk into them, cannot pass) ·
      night 3: barricade gone, `stairs_up` works, storage loot = food+water+battery ·
      night 5: attic hatch opens, search_attic = medicine+ammo ·
      night 7: basement door opens, generator + cellar_search = fuel ·
      generator burns 2 fuel/day (+1 more if not checked) · guest-room bed (2F) restores 1 energy, day only

## 3. Sign-off

- [ ] Coverage map (diagram) has no unvisited nodes, or each gap has a logged reason
- [ ] All findings moved to `QA_LOG.md` issues table with repro steps
