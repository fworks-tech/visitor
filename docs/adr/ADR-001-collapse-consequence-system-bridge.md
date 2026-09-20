# ADR-001: Collapse ConsequenceSystem bridge into engine

**Date:** 2026-09-19
**Status:** Accepted

## Context

The autoload table (`project.godot`) pointed `ConsequenceSystem` at a 19-line
bridge file (`autoload/ConsequenceSystem.gd`) that instantiated the real engine
(`scripts/systems/ConsequencesSystem.gd`, 224 lines, `class_name ConsequencesSystem`)
as a child node. Two call sites reached the engine through the bridge:

- `GameManager.start_day_phase` called `ConsequenceSystem.process_overnight_outcomes()`,
  a wrapper that copied `trust`/`corruption` into a scratch dict, called the engine's
  `process_day()`, then copied the values back.
- `VisitorManager.process_decision` called `ConsequenceSystem.consequences_engine.record_decision(...)`,
  null-checking the engine field first.

The bridge added one indirection layer with no abstraction benefit — it wrapped a
single class with a single instance.

## Decision

Point the autoload directly at the engine (`scripts/systems/ConsequencesSystem.gd`),
delete the bridge file, and fold the trust/corruption round-trip inline at the
`start_day_phase` call site (~6 lines). The `process_decision` null-guard is no
longer needed — the autoload is always present.

## Alternatives Considered

| Option | Pros | Cons | Why Rejected |
|--------|------|------|-------------|
| Keep bridge | Isolates engine lifecycle | 19-line wrapper, 1 indirection, 1 call-site null-check | Complexity without benefit |
| Drop autoload, use `class_name` global only | One fewer autoload | Breaks the 10-autoload convention; every caller must guard against null | Inconsistent with project patterns |

## Consequences

- **Easier**: autoload is the engine — no `.consequences_engine` indirection.
- **Harder**: call site owns the scratch-dict round-trip (6 lines, self-contained).
- **Risks**: forgetting to update a call site when rewire happens. Mitigated by
  `grep -rn "consequences_engine"` returning zero after the change.

## References
- `tools/run_gates.py` — green after change validates no behavioral regression.
- AGENTS.md convention #2 — all gameplay state through GameManager (preserved).
