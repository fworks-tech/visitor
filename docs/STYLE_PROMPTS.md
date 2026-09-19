# DEEPTALES Art Toolkit (M3)

One script per game — from the game root:

    python3 tools/art_pipeline.py manifest     # data -> art_manifest.json (what art the game needs)
    python3 tools/art_pipeline.py prompts      # numbered, ready-to-paste image-gen prompts
    python3 tools/art_pipeline.py prompts --missing
    python3 tools/art_pipeline.py postprocess IMG.png --style analog_green
    python3 tools/art_pipeline.py wire        # fill empty portrait refs in visitors/portraits data
    python3 tools/art_pipeline.py verify      # release gate: every referenced asset exists

## Flow (per batch)

1. `manifest` — scans visitors.json / portraits.json / story.json and lists
   every art asset the game needs, with present/missing status.
2. `prompts` — prints one composed prompt per missing asset, built from the
   style prompt pack below. Paste into an image generator (or ask the
   DEEPTALES agent to run the batch). Portrait framing is fixed: chest-up,
   centered, plain dark background, 3:4.
3. `postprocess` — the analog pass (see recipe below). Painterly styles only
   need light desaturation; analog styles want the full chain.
4. `wire` — idempotent: fills `portrait` fields in visitors.json and adds
   portraits.json entries for story speakers whose art just landed.
   Never overwrites a reference that already resolves.
5. `verify` — exit 0 = every referenced portrait exists. Gate a release on it.

## Style prompt packs (M3-2)

Each style has: base modifiers + per-kind template (portrait/background/prop/icon).
The script composes these automatically — the packs below are the source of truth.

- **dark_horror** — painterly: desaturated muted palette, chiaroscuro, thick
  brush strokes. Post: desaturate ~35% + grain + vignette.
- **analog_green** — the uncanny look ("No, I'm not a Human"): hand-drawn
  illustration through a rasterizer, almost-photographic, green monochrome,
  subject at a door staring at viewer, not blinking, slightly wrong.
  Post: green duotone + scanlines + grain + chroma bleed.
- **vhs_red** — found-footage: washed-out red tint, tape distortion, tracking
  errors. Post: red duotone + tape noise + heavy grain.
- **amber_terminal** — retro institutional: amber phosphor glow, photocopied
  document-photo texture, bureaucratic dread. Post: amber duotone + scanlines.
- **cold_noir** — desaturated blue-grey, harsh noir light, clinical dread.
  Post: cool desaturate + grain.

## Working without generative AI (manual pipeline)

The pipeline is AI-agnostic: generation is just one way to fill the slots.
Manifest tells you WHAT the game needs, the paths tell you WHERE it goes,
`wire` + `verify` tell you WHEN it's done. They do not care how the pixels
were made. The manual flow:

1. `manifest` -> your commission list: every asset with its path, subject,
   story context, and present/missing status. Treat each entry as a work order.
2. Read this doc's style packs as an **art direction brief** (that is all a
   "prompt" is): framing (chest-up, centered, plain dark background, 3:4),
   palette per style, the emotion the story requires at that moment.
3. Create the art by any means — Krita/Photoshop, photobash, 3D render pass,
   physical media scanned, hand-drawn on paper. Save it at the manifest path.
4. `postprocess IMG --style <style>` — the analog pass is ESPECIALLY for
   hand-made art: hand-drawn illustration put through a rasterizer is
   literally the provenance of the "No, I'm not a Human" look. A genuinely
   hand-made base + this pass is the most on-brand result possible.
5. `wire` then `verify` — release gate green when every slot is filled.

Mixed workflow is fine too: fill slots with generated placeholders now,
replace them by hand later — `verify` keeps the integrity gate either way.

## Rasterization recipe (M3-3) — "almost photographic"

The uncanny pass, in order (implemented in `postprocess`):

1. **Duotone** — collapse to grayscale, remap black->style lo, white->style hi
   (analog_green: #021006 -> #8cdc96). Painterly styles skip this.
2. **Chroma bleed** — shift the red channel +1.5px, blue -1.5px. The analog tell.
3. **Grain** — uniform noise added at low opacity (seed fixed: reproducible).
4. **Scanlines** — every 3rd row darkened (analog styles only).
5. **Softening + vignette** — 0.6px gaussian, then edge falloff.

Tune per game; the defaults are the Visitor-validated baseline.
