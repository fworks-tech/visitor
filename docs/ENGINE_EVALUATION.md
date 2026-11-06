# Engine Evaluation: Godot vs Unity for Visitor

- **Status:** Accepted
- **Date:** 2026-11-05
- **Owner:** Fabio Ritzel Borges
- **Related:** [ADR-003](adr/ADR-003-house-layout-single-source.md), [ART_DIRECTION_ANALOG.md](ART_DIRECTION_ANALOG.md)

## Decision

Stay on **Godot 4.x** for Visitor and DEEPTALES. Do not port mid-project.
Re-evaluate the engine per title, not per brand, and only when a concrete
requirement appears that Godot cannot meet.

## Context

Visitor is a first-person 3D shelter plus a door-inspection loop for Android and
iOS. It already has 32 GDScript files (6,396 lines), 11 autoloads, 8 scenes,
four floors of runtime geometry, 20 visitors, 40 signs, 7 nights and 7 endings.
Android and iOS export presets are configured, and a browser demo is planned.

DEEPTALES, the generator behind the games, is also Godot-native: 58 GDScript
files (7,381 lines), 38 scenes, 3 blueprints and a 968-line generator.

The visual references are "No, I'm not a Human" and "Tales Beyond the Tomb".
Their engines are not publicly confirmed by the sources reviewed, and the
decision below does not depend on them. What they share is art direction,
sound, limited information and a strong authored mood.

## Why not migrate now

1. **Content is the bottleneck.** The narrative audit found a contradictory
   tutorial, a missing neutral ending, an absent character on night 2 and
   dilemmas without mechanical effect. None of those are engine problems.
2. **Port cost is larger than it looks.** A faithful port rewrites the
   autoloads, 3D house builders, stairs and collision, door UI, save format,
   input, audio, mobile plugins, shaders and tests. Estimate: 8 to 12 weeks
   full-time for Visitor, 6 to 10 weeks for DEEPTALES, plus device regression.
3. **The framework is a second product.** Moving Visitor alone leaves DEEPTALES
   generating Godot projects. Moving both is a studio reset, not a game choice.
4. **The visual gap is narrower than the engine gap.** The analog look comes
   from lighting, grading, grain, faces, framing and sound. Godot 4 Forward+
   supports PBR, SSAO, fog, glow, DOF, custom shaders and 3D audio.
5. **Browser demos favor Godot.** The web export is native and lighter than
   Unity WebGL, which matters for the planned 10-minute demos.

## Scorecard

Decision aid, not a precise measurement. Scores are 1 to 5.

| Criterion | Weight | Godot | Unity |
|---|---:|---:|---:|
| Time to ship Visitor | 30% | 5.0 | 1.5 |
| Ceiling for the analog-horror look | 20% | 3.5 | 4.5 |
| Mobile performance and build pipeline | 15% | 4.0 | 3.5 |
| Asset and content ecosystem | 10% | 2.5 | 5.0 |
| Animation and cinematics | 10% | 2.5 | 5.0 |
| Browser demo | 5% | 5.0 | 2.0 |
| Console path | 5% | 3.0 | 5.0 |
| Licensing and cost | 5% | 5.0 | 3.0 |
| **Weighted total** | **100%** | **3.95** | **3.38** |

## What would make Unity win

Take a Unity spike seriously only if at least two of these are true:

- Console launch is a requirement for the next title.
- Cinematics, facial animation or mocap are more than 20% of runtime.
- A publisher or platform holder requires Unity or a specific middleware.
- The team already ships Unity and hiring is the constraint.
- A concrete Godot blocker appears in rendering, animation or platform SDKs.

### Two-week spike, if triggered

Build one room, one door, one inspection and one portrait treatment, then ship
an Android build to the target device. Measure:

- frame time on the target phone (target 60 fps, floor 30 fps);
- build size and cold start;
- iteration time from save to device;
- blind comparison of three lighting shots against Godot;
- work required for save, input, audio buses and localization.

If the spike is not at least 2x better on a named bottleneck, stay on Godot.

## Consequences

- Visitor ships on Godot; the remaining work is narrative, art and device QA.
- DEEPTALES stays Godot-native; engine choice remains per title.
- Art investment goes into the analog pipeline described in
  [ART_DIRECTION_ANALOG.md](ART_DIRECTION_ANALOG.md), not into a rewrite.
- Revisit this decision after Visitor ships, with real device and store data.
