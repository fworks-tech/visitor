# Analog Horror Art Direction

Target: the uncanny, almost-photographic mood of "No, I'm not a Human", built
inside Godot 4 at mobile budgets. This is the style contract for Visitor; the
engine decision is in [ENGINE_EVALUATION.md](ENGINE_EVALUATION.md).

## What we copy, what we do not

| Copy | Do not copy |
|---|---|
| Static, eye-level framing with one lit detail | Jumpscare spam |
| Faces that are almost right, never monsters | Obvious monster makeup |
| Green monochrome UI over a desaturated world | A green filter over everything |
| Practical light, deep shadow, visible grain | Flat ambient fill |
| Limited information and ambiguous signs | Random outcomes that make deduction pointless |
| Silence, room tone, knocks, muffled voices | Continuous music |
| Low-clutter 3D with high-detail faces | Over-modeled, busy rooms |

The last row in "do not copy" is a design rule, not only art: if a sign never
predicts anything, the horror stops being about judgment. Keep signs causal.

## Six pillars

1. **Almost human.** Correct anatomy, wrong detail: an eye line a few pixels
   low, a smile too wide, a neck too long, clothes too clean.
2. **One lit detail.** A warm lamp, a door slit, a TV glow. Everything else
   falls into cold green-grey shadow.
3. **Analog decay, readable faces.** Grain, scanlines, vignette, slight
   chromatic aberration and tracking. Never so strong that a face becomes
   unreadable.
4. **Green monochrome interface.** Terminal green, bone text, rust for danger.
   Thin lines, no cards, no rounded corners.
5. **Silence, then impact.** Room tone and diegetic sound carry the scene. A
   single low drone is the exception, not the bed.
6. **Limited information.** Frame the door, the slit, the hands. Hide the room
   until the player earns it.

## Godot 4 setup

### Environment (starting values, tune on device)

```gdscript
# WorldEnvironment.environment
background_mode = Environment.BG_COLOR
background_color = Color(0.012, 0.014, 0.012)

ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
ambient_light_color = Color(0.42, 0.50, 0.42)
ambient_light_energy = 0.35

tonemap_mode = Environment.TONE_MAPPER_FILMIC
tonemap_exposure = 0.95
tonemap_white = 1.0

glow_enabled = true
glow_intensity = 0.35
glow_bloom = 0.08
glow_hdr_threshold = 0.90

fog_enabled = true
fog_light_color = Color(0.05, 0.07, 0.05)
fog_density = 0.04

ssao_enabled = true
ssao_radius = 1.2
ssao_intensity = 1.8
ssil_enabled = false      # mobile: off
ssr_enabled = false       # mobile: off

dof_blur_far_enabled = true
dof_blur_far_distance = 12.0
dof_blur_far_transition = 4.0

adjustment_enabled = true
adjustment_saturation = 0.65
adjustment_contrast = 1.08
adjustment_brightness = 0.98
```

Use Forward+. Keep one warm `OmniLight3D` per room with shadows, plus a cold
window or door fill. Do not add a second warm key in the same room.

### Camera and framing

- Eye height 1.55 m at the door, 1.62 m walking.
- Door inspection: FOV 65, static, subject centered with headroom.
- Walking: FOV 72, subtle breathing sway (0.015 amplitude, 0.6 Hz), no roll.
- Let negative space do the work. The door frame is part of the composition.
- Reference shots: (1) door slit from inside, (2) guest under the hall lamp,
  (3) close portrait at the glass, (4) stairwell at night, (5) empty room with
  one practical.

### Analog post pass

One full-screen `CanvasLayer` with a `ColorRect` and a `canvas_item` shader.
One pass, no loops, no per-pixel texture fetches beyond the screen texture.

```glsl
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.045;
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.08;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float aberration : hint_range(0.0, 0.01) = 0.0015;
uniform float tracking_strength : hint_range(0.0, 0.02) = 0.003;
uniform vec3 tint = vec3(0.72, 0.86, 0.72);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.35;
uniform float time_scale = 1.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float t = TIME * time_scale;

    // Sparse tracking band, not a constant wobble.
    float band = smoothstep(0.02, 0.0, abs(fract(uv.y * 3.0 + t * 0.07) - 0.5));
    uv.x += band * tracking_strength * (hash(vec2(floor(uv.y * 120.0), floor(t))) - 0.5);

    vec2 d = uv - 0.5;
    vec3 col;
    col.r = texture(screen_texture, uv + d * aberration).r;
    col.g = texture(screen_texture, uv).g;
    col.b = texture(screen_texture, uv - d * aberration).b;

    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(lum) * tint, tint_mix);

    float grain = hash(uv * vec2(1280.0, 720.0) + t) - 0.5;
    col += grain * grain_strength;

    float scan = 0.5 + 0.5 * sin(uv.y * 720.0 * 3.14159);
    col *= 1.0 - scan * scanline_strength;

    float vig = smoothstep(0.95, 0.30, length(d));
    col *= mix(1.0, vig, vignette_strength);

    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
```

Tune order: grade first, then grain, then scanlines, then vignette. On low-end
devices halve grain resolution or set `grain_strength = 0.0` before touching
framerate.

### Portraits

- Source at 1024, in-game at 512 with mipmaps.
- Desaturate 60 to 70 percent, lift shadows toward green, keep skin highlights
  bone-white.
- Add 3 to 5 percent grain and a 0.3 px blur, then inspect at phone size.
- Build the "almost right" checklist into the prompt: neutral stare, direct
  eye contact, slightly asymmetric eyes, too-even teeth, wrong neck length,
  clothes too clean for the apocalypse.
- Godot import: filter on, mipmaps on, sRGB, ASTC 4x4 for mobile. Check for
  cheek and eye artifacts before shipping; use 1024 uncompressed only for the
  store build if needed.
- Material: unshaded albedo. The portrait is the face; do not light it twice.

### 3D dressing

- Realistic proportions, low clutter, 1k textures with a shared trim sheet.
- The room is a stage: bed, door, lamp, one personal object. Empty space is
  part of the horror.
- Visitor bodies stay simple; the face plane carries the character.
- Use fog to hide draw distance, not to hide bad geometry.
- Stairs and doors get the best light in the house. They are thresholds.

### Interface

- Palette: Void `#0A0C0B`, Bone `#E6E1D5`, Threshold green `#3E5C46`, Rust
  `#6E2B26`.
- Monospace for UI, distressed serif only for titles and endings.
- Typewriter at 35 to 45 characters per second; choices as plain text lines.
- No rounded cards, no drop shadows, no gradients. One-pixel rules.
- HUD: room name, battery, current prompt. Nothing else.

### Audio

- Room tone at the edge of hearing, knocks with per-visitor variation, voices
  muffled through the door, no music.
- One low drone for reveals, then silence again.
- Reverb: small room, low mix. The door should sound like a door.

## Mobile budgets

| Budget | Target |
|---|---|
| Frame rate | 60 fps on mid-tier, 30 fps floor |
| Draw calls | under 150 |
| Triangles | under 150k |
| Materials | under 80 |
| Realtime lights | 4 to 6 per room, shadows only on the key |
| Post pass | one full-screen pass |
| Texture memory | under 150 MB |
| Build | keep the demo slice under 60 MB |

## First sprint (one week)

1. **Environment preset.** Create `resources/environment/analog_night.tres` and
   apply it to `HouseScene`. Acceptance: five reference shots, 60 fps on the
   target phone.
2. **Analog post pass.** Add the shader and a `CanvasLayer` with tunable
   uniforms. Acceptance: grain, scanlines, vignette and aberration can be
   toggled; faces stay readable at phone size.
3. **Door framing.** Lock camera height, FOV and practical light for the
   inspection. Acceptance: three shots that match the reference mood.
4. **Portrait treatment.** Apply the grade and grain to five portraits.
   Acceptance: before/after sheet, no lost expression.
5. **UI pass.** Apply the palette and typewriter to the inspection screen.
   Acceptance: one screenshot with green UI, bone text and rust danger only.

## Success test

Show three screenshots to someone who has not seen the game and ask what genre
it is. If the answer is "analog horror about letting someone in", the direction
is working. If the answer is "a green filter", the grade is too heavy.
