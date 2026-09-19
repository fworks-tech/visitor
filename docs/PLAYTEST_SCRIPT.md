# DEEPTALES Playtest Script (M4-5)

Content-coverage playbook: prove every branch of the story graph is
reachable and every ending is attainable. Companion to `DEVICE_QA.md`
(which covers device behavior, not story content). Run on desktop or
device; record results in `QA_LOG.md`.

## 0. Pre-flight (both genres)

- [ ] `python3 tools/author_cli.py validate <game>` → PASSED
- [ ] `python3 tools/author_cli.py stats <game>` → note checkpoint/ending counts below
- [ ] `python3 tools/author_cli.py diagram <game>` → open the Mermaid graph; this is your coverage map

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

## 3. Sign-off

- [ ] Coverage map (diagram) has no unvisited nodes, or each gap has a logged reason
- [ ] All findings moved to `QA_LOG.md` issues table with repro steps
