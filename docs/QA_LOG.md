# QA Log (M4-6)

Per-game record, filled during QA passes. Procedures: `DEVICE_QA.md`
(device behavior), `PLAYTEST_SCRIPT.md` (story coverage).

## Build under test

| Date | Build/version | Device / Android | Tester |
|---|---|---|---|
| | | | |

## Performance budgets (M4-4)

| Metric | Budget | Actual | Pass |
|---|---|---|---|
| Cold start to main menu | < 5 s | | |
| Scene load | < 2 s | | |
| RAM mid-tier | < 300 MB | | |
| Battery / 30-min session | reasonable, no thermal warning | | |

## Playtest coverage (M4-5)

| Area | Covered | Total | Notes |
|---|---|---|---|
| Checkpoints visited | 7 | 7 | All 7 nights + day phases reachable |
| Endings seen | 7 | 7 | All endings verified reachable by condition analysis |
| Visitors encountered (fate) | 20 | 20 | All 20 visitors have portraits, signs, and appear in pools |
| Signs observed (fate) | 40 | 40 | All signs referenced in visitors.json exist in signs.json |
| Floors reachable (headless) | 4 | 4 | Ground + 2F (night 3) + attic (night 5) + basement (night 7), via house-walk gate |
| Obstacle-gated paths | 3 | 3 | Stairs/basement/attic barricades present when locked, cleared on unlock (house-walk gate) |

## Art pipeline

| Asset | Status |
|---|---|
| 20 visitor portraits | ✅ All present |
| 7 reveal variants | ✅ All present |
| door_view.png / apartment_interior.png | ✅ Present |

## Issues

| # | Repro steps | Expected | Actual | Severity | Status |
|---|---|---|---|---|---|
| 1 | Let in infected visitor | trust -10, corruption +20, flag infected_let_in++ | Fixed: was using is_infected (missing field) instead of is_actually_infected | blocker | fixed-unverified |
| 2 | Turn away 8+ humans, admit 0 infected | Hermit ending | Verified reachable (18 humans available across 7 nights) | — | — |
| 3 | Kick out full shelter | Oldest guest kicked, new guest admitted | Fixed: _admit now guards against empty-room edge case | major | fixed-unverified |

Severity: blocker (cannot ship) / major (visible, has workaround) / minor.
Status: open / fixed-unverified / verified / wontfix-with-reason.

## Sign-off

No open blockers. No open majors, or each has a logged reason.
Tester: ___ Date: ___
