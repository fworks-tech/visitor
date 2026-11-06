# Aperture Views

A composable way to look through a doorway, peephole, window, door crack or
hatch and see an environment with a visitor standing in it. The reference is
"No, I'm not a Human": one green, grainy image, a visitor close to the door, and
a dialogue box with choices on the right.

It is wired into the door inspection and the night window behind
`ViewPresets.ENABLED`. Set that constant to false to fall back to the
`VisitorDiorama3D` and the old split layout.

## Why a hybrid composite

A pure 2D cutout would need 20 full-body character images with clean alpha, and
every new aperture would risk mismatched lighting. A pure 3D environment would
need a room built for every view.

This system uses:

- a 2D environment plate for the place (cheap, easy to replace, easy to grade);
- the existing 3D `VisitorBody3D` for the person (already lit, already animated,
  already carries signs and the face crop);
- a one-pass post shader that grades both into one image.

The green grade is not only style. It is what makes the 3D body and the photo
plate read as the same material.

## Files

| File | Role |
|---|---|
| `assets/data/view_presets.json` | Apertures, environments, anchors |
| `scripts/systems/ViewPresets.gd` | Loads and resolves presets |
| `scripts/door/ApertureStage.gd` | 3D stage: plate, body, lights, camera, post |
| `shaders/aperture_post.gdshader` | Fisheye, mask, grade, grain, scanlines |
| `tools/aperture_demo.gd` | Interactive preview (`--aperture-demo`) |
| `assets/images/environments/` | 1280x720 plates |

## Composition order

```
camera
  ├── environment plate (unshaded quad at z = -6)
  ├── visitor body (VisitorBody3D at z = 0)
  ├── key / fill / rim lights (per environment)
  └── CanvasLayer
        ├── BackBufferCopy
        └── ColorRect + aperture_post.gdshader
```

The shader samples the rendered viewport, applies barrel distortion, grades it,
adds grain and scanlines, then multiplies by the aperture mask. Outside the mask
is black.

## Preset schema

```json
{
  "apertures": {
    "peephole": {
      "label": "Peephole",
      "shape": 0,
      "mask_center": [0.5, 0.5],
      "mask_size": [0.92, 0.92],
      "mask_softness": 0.02,
      "fisheye": 0.32,
      "zoom": 1.05,
      "tint": [0.72, 0.86, 0.72],
      "tint_mix": 0.55,
      "grain": 0.05,
      "scanlines": 0.06,
      "vignette": 0.75,
      "aberration": 0.002,
      "tracking": 0.002,
      "camera": {"height": 1.55, "fov": 62.0, "distance": 1.35}
    }
  },
  "environments": {
    "env_porch_night": {
      "label": "Front porch",
      "texture": "res://assets/images/environments/env_porch_night.jpg",
      "depth": -6.0,
      "compatible": ["peephole", "door_crack", "window"],
      "light": {
        "key_color": [1.0, 0.82, 0.62], "key_energy": 1.1,
        "fill_color": [0.25, 0.40, 0.32], "fill_energy": 0.25,
        "rim_color": [0.30, 0.90, 0.60], "rim_energy": 0.5
      },
      "anchors": {
        "peephole": {"x": 0.0, "y": 0.0, "z": 0.0, "scale": 1.0, "yaw": 0.0}
      }
    }
  }
}
```

`shape`: 0 circle, 1 rectangle, 2 vertical slit. `mask_size` is a diameter for a
circle and width/height for rectangles. `camera.distance` is the camera Z.

Resolution order, later wins:

1. `defaults`
2. aperture
3. environment
4. environment anchor for that aperture
5. visitor override

## Adding content

### New environment

1. Add a 1280x720 plate to `assets/images/environments/`.
2. Add an entry with `texture`, `depth`, `compatible`, `light` and one anchor per
   compatible aperture.
3. Run `python3 tests/validate_systems.py`.
4. Preview with `--aperture-demo`.

### New aperture

1. Add an entry with shape, mask, camera and grade values.
2. Add an anchor for it in every compatible environment.
3. Keep at least one environment compatible, or the data contract fails.

### Visitor-specific placement

Add `visitor_overrides` by visitor id when a character needs a different scale
or offset, for example a trio that should stand wider:

```json
"visitor_overrides": {
  "v007": {"scale": 0.92}
}
```

## Demo

```bash
godot --path . -- --aperture-demo
```

- `A` / `D`: previous / next aperture
- `W` / `S`: previous / next compatible environment
- `V`: next visitor
- `Esc`: quit

The demo filters environments by `compatible`, so a hatch never shows a porch.

## Cinematic door layout

`InspectionScene` now hides the old split panels and builds a full-screen
composition:

```
CinematicView (SubViewportContainer)
  └── SubViewport (1280x720)
        └── ApertureStage (plate + body + doorway shader)
CinematicUI (Control)
  ├── HUD line: night, time, food, water, ammo, meds
  ├── Dialogue panel (bottom right)
  │     ├── speaker
  │     ├── typewriter line
  │     └── choice row: Listen / Look them over / Ask / Study,
  │         then Come in / You better leave / Eliminate
  └── LOG drawer (inspection notes)
```

The door uses the `doorway` aperture for the wide, full-frame view of the
reference. `peephole` stays available for a tighter view. The two primary
decision choices are exactly "Come in." and "You better leave."; ELIMINATE only
appears when the weapon option is available.

`InspectionScene._setup_aperture_view()` creates the stage in the full-screen
viewport. `_update_aperture()` sets the view, body, corruption and reveal.
`_refresh_choices()` rebuilds the choice row from the current conversation
tier; the old buttons remain as the state source, so the tests and consequences
still drive the flow.

Set `ViewPresets.ENABLED = false` to return to the old diorama and split UI.

## Night window

`HouseScene._action_window()` opens `ApertureOverlay` at night:

- the overlay freezes the player, shows the `window` aperture and returns on
  `E` / `ESC` / STEP BACK;
- `_window_environment()` maps the current room to a plate (bedroom porch,
  office road, kitchen and hall yard);
- the hazard and rejected-figure text still appears as the overlay caption;
- daylight keeps the text popup because the plates are night plates.

## Art direction for plates

- 1280x720, no people, no text, no UI, no border.
- Compose for a body at 1.35 m from the camera: keep the center clear.
- Keep the bottom third readable for the dialogue box.
- Light the plate as a photograph. The shader will grade it; do not pre-tint it
  green, or the grade will crush the shadows.
- Prefer one practical light in frame and deep shadow elsewhere.

## Performance

- One SubViewport, one full-screen pass, 8 plates at about 1.2 MB total.
- Disable SSIL and SSR; keep SSAO only if the frame budget allows.
- `BackBufferCopy` is required for the screen texture in a SubViewport.
- Target 60 fps on mid-tier. If the post pass costs too much, halve the grain
  resolution before touching the mask.

## Known limits

- The plate is flat. There is no parallax yet.
- The body always draws in front of the plate; no per-pixel occlusion.
- Anchors are manual. There is no editor tool yet.
- The visitor body is 3D, not a photographed cutout. The green grade hides most
  of the mismatch, but close inspection will show it.
- No weather variants yet. Add `_rain`, `_snow` plates or shader overlays later.
- The cinematic door is 16:9; the house overlay fills the device screen. The
  final safe-area and font-size pass still needs device QA.
- The reference has a wooden floor foreground. The current plate stops at the
  door; a foreground layer is a later art task.
