# ADR-002: Infection State on Guest Dicts, Consequence Queue as the Clock

**Date:** 2026-09-21
**Status:** Accepted

## Context

Letting in a latent carrier must turn a guest inside the shelter days
later. Two systems already hold time-indexed data: the guest dicts in
`VisitorManager.admitted_visitors` (per-day state) and the delayed-consequence
queue in `ConsequencesSystem` (firing on trigger_day). A third option was a
standalone daily "infection tick" sweeping all guests.

## Decision

- Guest infection state lives on the guest dictionaries: `turned`,
  `bitten`, `infection_progress` — same shape as every other guest flag,
  survives save/restore via the existing round-trip (save format 1.1).
- The `infected_let_in` consequence queue entry IS the progression clock:
  its 1-3 day delay (1 day when progress ≥ 0.8) stands in for progression
  of the original carrier; firing sets `turned = true`.
- Bitten guests progress `+0.25/day` in `_run_infection` and turn at 0.8;
  each turned guest rolls 50% at dawn to bite one healthy guest.
- No season/exam loop, no AI. A turned guest drains nothing by itself —
  it bites at dawn, forcing action with a visible cost.

## Alternatives Considered

| Option | Why Considered | Why Rejected |
|--------|---------------|-------------|
| Separate progression system ticking `infection_progress` daily for all guests | Symmetric with door-side thresholds | Two clocks would race the queue; queue delay already encodes progression for carriers |
| Turned-guest AI (patrol/attack in the 3D house) | More "game" | Night is the door's phase; in-house complexity would ship without tests or tuning data |
| Stat-only turn (log + deltas, no body) | Cheapest | This was the shipped behavior — playtesters called it invisible. The mechanic's whole point is doubt you can see |

## Consequences

**Positive:** One guest shape; one clock (the queue); save/restore covers infection for free.
**Negative:** Balance constants (+0.25, 50%, thresholds) live in `ConsequencesSystem` next to content, not a tuning table.
**Neutral:** `get_survivors_inside()` and `confirmed_infected` (exam discovery) remain the door-side vocabulary; `turned` is the house-side one — see ADR text above before merging them.

## References

- Issue #4 (infected guests never turned inside the shelter)
- Issue #5 (save/restore of the new state)
- Issue #7 (--balance-test pins the fuel economy this system interacts with)
