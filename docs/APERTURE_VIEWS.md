# Aperture Views

A composable way to look through a peephole, window, door crack or hatch and
see an environment with a visitor standing in it. The reference is the peephole
framing of "No, I'm not a Human": one green, grainy, fisheye image, a face close
to the glass, and a dialogue box on the right.

The system is a prototype. It runs as a demo today and is not yet wired into
`InspectionScene` or the house windows.

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

## Wiring into InspectionScene

The current `DoorView` already renders `VisitorDiorama3D` in a SubViewport. The
least risky integration is a second stage, hidden until a preset exists:

1. Add an `ApertureStage` next to `Diorama` in the same SubViewport, or replace
   `Diorama` when the visitor has a `view_environment` field.
2. In `InspectionScene._show_visitor` (or `_update_portrait`), call
   `stage.set_view("peephole", visitor.get("view_environment", ""), visitor.id)`.
3. Call `stage.set_visitor(visitor, assigned_signs)`.
4. Keep the current diorama as fallback when the field is empty.
5. Move the dialogue box over the image only after the composite is approved on
   device; the current split layout still works.

## Wiring into the house

For windows and interior gaps, add an interactable in `House3D`:

- id: `window_view`, `door_crack`, `hatch_view`;
- action opens a full-screen `ApertureStage` overlay in `HouseScene`;
- aperture id comes from the interactable, environment id from the room or the
  time of day;
- close returns to the walk. Freeze player input while open.

Start with one window and one room, then add the rest.

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
