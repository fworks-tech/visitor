#!/usr/bin/env python3
"""DEEPTALES art pipeline (M3): manifest -> prompts -> generate -> postprocess -> wire -> verify.

One tool per generated game, run from the game root:

    python3 tools/art_pipeline.py manifest          # scan game data -> art_manifest.json
    python3 tools/art_pipeline.py prompts           # print ready-to-use image-gen prompts
    python3 tools/art_pipeline.py prompts --missing # only assets not on disk yet
    python3 tools/art_pipeline.py postprocess IMG --style analog_green
    python3 tools/art_pipeline.py wire              # point data files at art on disk
    python3 tools/art_pipeline.py verify            # exit 0 iff every referenced asset exists

Manifest sources:
  - fate_arbiter:    visitors.json -> one portrait per visitor (assets/images/portraits/<id>.png)
  - narrative_choice: portraits.json (char x emotion) + story.json speakers found missing

The wire step is idempotent: it only fills empty/missing portrait references,
never overwrites a path that already points at an existing file.
"""
import argparse
import json
import re
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------- style packs (M3-2)

STYLE_PACKS = {
    "dark_horror": {
        "label": "Dark Horror (painterly)",
        "env_modifiers": "dark painterly horror environment, desaturated muted palette, "
                         "dramatic chiaroscuro shadows, high contrast, unsettling atmosphere",
        "modifiers": "dark painterly horror illustration, desaturated muted palette, "
                     "dramatic chiaroscuro shadows, high contrast, unsettling atmosphere, "
                     "thick visible brush strokes, cinematic lighting, muted earth tones",
        "portrait": "Emotion is {emotion}. Expressive but restrained — the fear reads from the eyes.",
        "background": "single key light source, oppressive negative space, sense of a threat just off-frame",
        "prop": "still-life framing, worn and aged surfaces, dramatic side light",
        "icon": "flat emblem on near-black, single bone-white subject, subtle film grain",
        "postprocess": "desaturate ~35%, film grain, strong vignette",
    },
    "analog_green": {
        "label": "Analog Green (CRT monochrome)",
        "env_modifiers": "analog horror environment, hand-drawn illustration processed through "
                         "a rasterizer — almost photographic but clearly not, green-tinted "
                         "monochrome security-camera lighting, VHS/CRT aesthetic, dark "
                         "oppressive atmosphere, Mandela Catalogue inspired",
        "modifiers": "uncanny horror character portrait, hand-drawn illustration processed through "
                     "a rasterizer — almost photographic but clearly not, green-tinted monochrome "
                     "lighting, dark oppressive background, Mandela Catalogue inspired, things that "
                     "look ALMOST right but subtly wrong, VHS/CRT analog horror aesthetic",
        "portrait": "Standing at a door, looking directly at viewer, not blinking, slightly wrong. "
                    "Frozen, mechanical, or blank expression. Emotion hint: {emotion}.",
        "background": "security-camera framing, sickly green lamp glow, #0a1a0a shadows",
        "prop": "flat clinical documentation lighting, object centered, clinical and wrong",
        "icon": "flat emblem, muted green-white on near-black green, scanline texture",
        "postprocess": "green duotone, raster scanlines, grain, chroma bleed",
    },
    "vhs_red": {
        "label": "VHS Red",
        "env_modifiers": "analog horror environment, found-footage VHS still, washed-out "
                         "red-tinted palette, tape distortion, dark and grainy",
        "modifiers": "analog horror, found-footage VHS still, washed-out red-tinted palette, "
                     "tape distortion, tracking errors, dark and grainy, deeply unsettling",
        "portrait": "Mid-90s camcorder framing, timestamp smudged, subject slightly out of focus. "
                    "Emotion hint: {emotion}.",
        "background": "night-shot grain, red infrared glow, tape noise bands",
        "prop": "evidence-photo framing, flash overexposure, tape smear",
        "icon": "flat emblem, bone-white on near-black red, tape noise",
        "postprocess": "red duotone, tape noise bands, heavy grain, chroma bleed",
    },
    "amber_terminal": {
        "label": "Amber Terminal",
        "env_modifiers": "retro terminal horror environment, amber monochrome glow, phosphor "
                         "scanlines, 1980s institutional institutional dread",
        "modifiers": "retro terminal horror, amber monochrome glow, phosphor scanlines, "
                     "photocopied texture, bureaucratic dread, 1980s institutional document photo",
        "portrait": "institutional ID-photo framing, stiff posture, dead stare. Emotion hint: {emotion}.",
        "background": "long-exposure amber glow, terminal bezel vignette",
        "prop": "scanned-document framing, photocopy grain, amber tint",
        "icon": "flat emblem, amber-white on near-black brown, phosphor texture",
        "postprocess": "amber duotone, scanlines, photocopy grain",
    },
    "cold_noir": {
        "label": "Cold Noir (desaturated blue)",
        "env_modifiers": "cold desaturated blue-grey palette, noir environment lighting, "
                         "rain-slick surfaces, distant clinical dread",
        "modifiers": "cold desaturated blue-grey palette, noir lighting, rain-slick surfaces, "
                     "distant and clinical dread, deep shadows, muted contrast",
        "portrait": "harsh top-down or side light, half the face in shadow. Emotion hint: {emotion}.",
        "background": "wet street reflections, sodium-vs-blue light split, fog",
        "prop": "evidence-table framing, cold clinical light",
        "icon": "flat emblem, pale grey-blue on near-black blue, frost texture",
        "postprocess": "cool desaturate, grain, moderate vignette",
    },
}

PORTRAIT_TEMPLATE = ("{modifiers}. {subject}. {style_portrait} "
                      "Chest-up portrait, centered, plain dark background, "
                      "portrait orientation 3:4, no text, no watermark.")


def _trim(text: str, n: int) -> str:
    """Cut at a word boundary so prompts never end mid-word."""
    return text[:n].rsplit(" ", 1)[0].rstrip(",;:.")


def compose_prompt(kind: str, subject: str, style: str, emotion: str = "neutral") -> str:
    pack = STYLE_PACKS[style]
    if kind == "portrait":
        return PORTRAIT_TEMPLATE.format(
            modifiers=pack["modifiers"], subject=subject,
            style_portrait=pack["portrait"].format(emotion=emotion))
    if kind == "background":
        return (f"{pack.get('env_modifiers', pack['modifiers'])}. {subject}. "
                f"{pack['background']} "
                "Single wide establishing shot, landscape orientation 16:9, "
                "no readable text anywhere in the image.")
    if kind == "prop":
        return (f"{pack['modifiers']}. {subject}. {pack['prop']} "
                "Single object centered, plain background, square 1:1, no text.")
    return (f"{pack['modifiers']}. {subject}. {pack['icon']} "
            "Minimal flat vector-style emblem, 1:1, no text.")


# ---------------------------------------------------------------- game data reading

def detect_style() -> str:
    """Style preset: from the generation report if stamped, else genre default
    (fate_arbiter default analog_green, narrative default dark_horror)."""
    for report in sorted(GAME.glob("*REPORT*.md")) + sorted(GAME.glob("GENERATION*.md")):
        try:
            txt = report.read_text(encoding="utf-8")
        except OSError:
            continue
        m = re.search(r"style[: ]+`?(\w+)`?", txt)
        if m and m.group(1) in STYLE_PACKS:
            return m.group(1)
    if (GAME / "assets" / "data" / "visitors.json").exists():
        return "analog_green"
    return "dark_horror"


def load(rel: str):
    p = GAME / rel
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def build_manifest(style: str) -> list[dict]:
    items: list[dict] = []
    visitors = load("assets/data/visitors.json")
    if visitors and "visitors" in visitors:
        for v in visitors["visitors"]:
            # base door portrait: appearance + the line they actually speak at
            # the door (so the expression matches the story scene, not a stock mood)
            first_line = ""
            chain = v.get("dialogue_chain") or []
            if chain and isinstance(chain[0], dict):
                first_line = chain[0].get("text", "")
            subject = v.get("appearance", v["name"])
            if first_line:
                subject += ('. Expression and mood consistent with what they plead at '
                            f'the door: "{first_line[:140]}"')
            items.append({
                "kind": "portrait", "path": f"assets/images/portraits/{v['id']}.png",
                "style": style, "subject": v.get("appearance", v["name"]),
                "emotion": "story-driven",
                "prompt": compose_prompt("portrait", subject, style),
            })
            # infected reveal variant: what close inspection actually uncovers
            if v.get("is_actually_infected"):
                reveal = v.get("reveal_on_inspection") or {}
                phys = "; ".join(reveal.get("physical_exam", [])[:2]) or "subtle infection signs"
                rsubj = (f"{v.get('appearance', v['name'])}. SAME person, now partially "
                         f"revealed as infected — what close inspection uncovers: {phys}. "
                         f"Wrong in a way the eye catches before the mind does: "
                         f"something ALMOST right but deeply off")
                items.append({
                    "kind": "portrait", "path": f"assets/images/portraits/{v['id']}_reveal.png",
                    "style": style, "subject": rsubj, "emotion": "revealed",
                    "prompt": compose_prompt("portrait", rsubj, style),
                })

    # fate scenes + outcome art, straight from story.json structure
    story = load("assets/data/story.json")
    if story and "nights" in story:
        brief = next((n.get("briefing", "") for n in story["nights"] if n.get("briefing")), "")
        scenes = [
            ("assets/images/scenes/main_menu.png",
             "Exterior of the fortified checkpoint at night, viewed head-on. Heavy door, "
             "fog rolling in thick from the lowlands, floodlights failing, oppressive silence. "
             f"Setting context: {_trim(brief, 200)}"),
            ("assets/images/scenes/day_phase.png",
             "Interior of the survivors' shelter common room, morning after a night of "
             "decisions. Barred windows, ration supplies stacked, everyone quietly dealing "
             "with what the door decisions cost them."),
            ("assets/images/scenes/inspection.png",
             "Interior POV facing the heavy front door of the checkpoint at night, the "
             "visitor unseen on the other side. Peephole light, fog seeping under the door, "
             "the tension of deciding who gets to come in."),
        ]
        for path, subj in scenes:
            items.append({"kind": "background", "path": path, "style": style,
                          "subject": subj, "prompt": compose_prompt("background", subj, style)})
        for key, e in (story.get("endings") or {}).items():
            subj = (f"Final outcome tableau for the ending '{e.get('title')}' — "
                    f"{_trim(e.get('summary', ''), 180)} "
                    f"Epilogue moment: {_trim(e.get('epilogue', ''), 180)}")
            items.append({
                "kind": "ending", "path": f"assets/images/endings/{key}.png",
                "style": style, "subject": subj,
                "prompt": compose_prompt("background", subj, style),
            })
    portraits = load("assets/data/portraits.json")
    story = load("assets/data/story.json")
    if portraits and "portraits" in portraits:
        for char, emotions in portraits["portraits"].items():
            for emotion, res_path in emotions.items():
                path = res_path.replace("res://", "")
                items.append({
                    "kind": "portrait", "path": path, "style": style,
                    "subject": char.replace("_", " "), "emotion": emotion,
                    "prompt": compose_prompt("portrait", f"{char.replace('_', ' ')} ({emotion} emotion)",
                                             style, emotion),
                })
    if story:
        # characters that speak but have no portraits.json entry -> flag for authoring
        known = {i["subject"].lower() for i in items if i["kind"] == "portrait"}
        speakers = set()
        for ch in story.get("chapters", []):
            cps = ch.get("checkpoints", []) if isinstance(ch, dict) else []
            for cp in cps:
                for line in cp.get("dialogue", []):
                    sp = line.get("speaker", "")
                    if sp and sp.lower() not in {"narrator", "player"}:
                        speakers.add(sp)
        for sp in sorted(speakers):
            if sp.lower() not in known:
                path = f"assets/images/portraits/{slug(sp)}_neutral.png"
                items.append({
                    "kind": "portrait", "path": path, "style": style,
                    "subject": sp, "emotion": "neutral",
                    "prompt": compose_prompt("portrait", sp, style, "neutral"),
                    "note": "speaker has no portraits.json entry — wire will add one",
                })
    return items


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def write_manifest(style: str) -> list[dict]:
    items = build_manifest(style)
    for i in items:
        i["present"] = (GAME / i["path"]).exists()
        i.setdefault("source", "")
        i.setdefault("license", "")
    (GAME / "art_manifest.json").write_text(
        json.dumps({"style": style, "assets": items}, indent=1), encoding="utf-8")
    missing = [i for i in items if not i["present"]]
    print(f"art_manifest.json: {len(items)} assets, {len(missing)} missing")
    return items


# ---------------------------------------------------------------- wire + verify (M3-4)

def wire() -> None:
    changed = 0
    portraits_p = GAME / "assets" / "data" / "portraits.json"
    visitors_p = GAME / "assets" / "data" / "visitors.json"

    if visitors_p.exists():
        data = json.loads(visitors_p.read_text(encoding="utf-8"))
        for v in data.get("visitors", []):
            path = f"assets/images/portraits/{v['id']}.png"
            if (GAME / path).exists() and (
                    not v.get("portrait") or not (GAME / v["portrait"].replace("res://", "")).exists()):
                v["portrait"] = "res://" + path
                changed += 1
            rpath = f"assets/images/portraits/{v['id']}_reveal.png"
            if v.get("is_actually_infected") and (GAME / rpath).exists() and not v.get("reveal_portrait"):
                v["reveal_portrait"] = "res://" + rpath
                changed += 1
        visitors_p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                              encoding="utf-8")

    if portraits_p.exists():
        data = json.loads(portraits_p.read_text(encoding="utf-8"))
        for char, emotions in data["portraits"].items():
            for emotion, res_path in emotions.items():
                path = res_path.replace("res://", "")
                if not (GAME / path).exists():
                    continue  # only wire art that actually exists
                # already fine
        # add entries for story speakers that have art but no config slot
        story = load("assets/data/story.json")
        if story:
            for ch in story.get("chapters", []):
                cps = ch.get("checkpoints", []) if isinstance(ch, dict) else []
                for cp in cps:
                    for line in cp.get("dialogue", []):
                        sp = line.get("speaker", "")
                        if not sp or sp.lower() in {"narrator", "player"}:
                            continue
                        cid = slug(sp)
                        if cid not in data["portraits"]:
                            cand = GAME / "assets" / "images" / "portraits" / f"{cid}_neutral.png"
                            if cand.exists():
                                data["portraits"][cid] = {"neutral": f"res://{cand.relative_to(GAME).as_posix()}"}
                                changed += 1
        portraits_p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n",
                               encoding="utf-8")
    print(f"wire: {changed} data reference(s) filled")


def verify() -> None:
    """M3-4 release gate: every portrait/scene res:// path in the data must exist."""
    missing: list[str] = []
    for rel in ("assets/data/visitors.json", "assets/data/portraits.json"):
        p = GAME / rel
        if not p.exists():
            continue
        data = json.loads(p.read_text(encoding="utf-8"))
        paths: list[str] = []
        for v in data.get("visitors", []):
            if v.get("portrait"):
                paths.append(v["portrait"])
            if v.get("reveal_portrait"):
                paths.append(v["reveal_portrait"])
        for char, emotions in data.get("portraits", {}).items():
            paths.extend(emotions.values())
        for rp in paths:
            if not (GAME / rp.replace("res://", "")).exists():
                missing.append(f"{rel}: {rp}")
    if missing:
        print(f"✗ {len(missing)} referenced asset(s) missing:")
        for m in missing[:10]:
            print("  " + m)
        sys.exit(1)
    print("✓ all referenced art assets exist")


# ---------------------------------------------------------------- rasterizer (M3-3)

def postprocess(img_path: str, style: str, out: str | None = None) -> None:
    """The 'almost photographic' analog pass: duotone -> grain -> scanlines -> chroma bleed."""
    try:
        from PIL import Image, ImageEnhance, ImageFilter
    except ImportError:
        sys.exit("✗ Pillow required for postprocess: pip install pillow")
    pack = STYLE_PACKS[style]
    img = Image.open(img_path).convert("RGB")
    w, h = img.size

    # 1. duotone per style
    duo = {"analog_green": ((2, 16, 6), (140, 220, 150)),
           "vhs_red": ((16, 4, 4), (220, 160, 150)),
           "amber_terminal": ((20, 12, 4), (230, 180, 110)),
           "cold_noir": ((8, 12, 18), (170, 190, 210)),
           "dark_horror": None}
    if duo[style]:
        lo, hi = duo[style]
        gray = img.convert("L")
        ch = gray.load()
        duo_img = Image.new("RGB", (w, h))
        px = duo_img.load()
        for y in range(h):
            for x in range(w):
                t = ch[x, y] / 255.0
                px[x, y] = (int(lo[0] + (hi[0] - lo[0]) * t),
                            int(lo[1] + (hi[1] - lo[1]) * t),
                            int(lo[2] + (hi[2] - lo[2]) * t))
        img = duo_img
    else:  # dark_horror: desaturate + keep painterly color
        img = ImageEnhance.Color(img).enhance(0.65)

    # 2. chroma bleed (offset red/blue channels a hair — the analog tell)
    r, g, b = img.split()
    r = r.transform((w, h), Image.AFFINE, (1, 0, 1.5, 0, 1, 0))
    b = b.transform((w, h), Image.AFFINE, (1, 0, -1.5, 0, 1, 0))
    img = Image.merge("RGB", (r, g, b))

    # 3. grain (noise centered around 0 — offset=-128 cancels the mean;
    #    scale<1 would MULTIPLY brightness and blow out the image)
    import random
    rng = random.Random(13)
    grain = Image.effect_noise((w, h), 18).convert("L")
    from PIL import ImageChops
    img = ImageChops.add(img, grain.convert("RGB"), scale=1.0, offset=-128)

    # 4. scanlines (not for painterly)
    if style != "dark_horror":
        sl = Image.new("L", (w, h), 0)
        sp = sl.load()
        for y in range(0, h, 3):
            for x in range(w):
                sp[x, y] = 40
        img = ImageChops.subtract(img, sl.convert("RGB"))

    # 5. soften + vignette — 'looked at through glass'
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    vig = Image.new("L", (w, h), 0)
    vp = vig.load()
    for y in range(h):
        for x in range(w):
            dx, dy = (x - w / 2) / (w / 2), (y - h / 2) / (h / 2)
            d = min(1.0, (dx * dx + dy * dy) ** 0.5)
            vp[x, y] = int(90 * max(0.0, d - 0.55) / 0.45)
    img = ImageChops.subtract(img, vig.convert("RGB"))

    out = out or str(Path(img_path).with_stem(Path(img_path).stem + "_" + style))
    img.save(out, quality=90)
    print(f"✓ postprocess [{pack['label']}]: {out}")
    print(f"  recipe: {pack['postprocess']}")


# ---------------------------------------------------------------- cli

# ---------------------------------------------------------------- attribution (M3-8)

def attribute(path: str, source: str, license_type: str, url: str = "", author: str = "") -> None:
    """Record where an asset came from and under what license (for fetched/hand-made art)."""
    items = write_manifest(detect_style())  # fresh manifest incl. present/source fields
    for i in items:
        if i["path"] == path:
            i["source"] = source
            i["license"] = license_type
            if url:
                i["source_url"] = url
            if author:
                i["author"] = author
            (GAME / "art_manifest.json").write_text(
                json.dumps({"style": i.get("style", detect_style()), "assets": items}, indent=1),
                encoding="utf-8")
            print(f"✓ attributed {path} -> {source} ({license_type})")
            return
    sys.exit(f"✗ {path} is not in the manifest (run `manifest` first)")


def report() -> None:
    """Write/update ATTRIBUTIONS.md from the manifest — every shipped game keeps one."""
    manifest = json.loads((GAME / "art_manifest.json").read_text(encoding="utf-8"))
    attributed, unattributed = [], []
    for i in manifest["assets"]:
        if not i.get("present"):
            continue
        if i.get("license"):
            attributed.append(i)
        else:
            unattributed.append(i)
    lines = [
        "# Attributions", "",
        f"> Auto-generated from art_manifest.json by the DEEPTALES art pipeline (style: {manifest.get('style', '?')}).",
        "> Re-run `report` after adding assets. CC-BY/CC-BY-NC entries MUST stay listed here.", "",
    ]
    if attributed:
        lines += ["## Sources", ""]
        for i in attributed:
            lines.append(f"- **{i['path']}** — {i.get('source', 'unknown')}"
                         + (f" by {i['author']}" if i.get("author") else "")
                         + f" — {i['license']}"
                         + (f" — {i.get('source_url', '')}" if i.get("source_url") else ""))
        lines.append("")
    if unattributed:
        lines += ["## Unattributed (present, no license recorded)", ""]
        lines += [f"- {i['path']}" for i in unattributed]
        lines += ["", "> Run: `art_pipeline.py attribute <path> --source <name> --license <type>`", ""]
    lines += ["## Notes", "",
             "Assets synthesized or drawn fully in-house need no attribution",
             "(record them as `--source in-house --license none`).", ""]
    (GAME / "ATTRIBUTIONS.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"ATTRIBUTIONS.md: {len(attributed)} attributed, {len(unattributed)} unattributed")


def main() -> None:
    ap = argparse.ArgumentParser(description="DEEPTALES art pipeline (M3)")
    ap.add_argument("command", choices=["manifest", "prompts", "wire", "verify", "postprocess", "attribute", "report"])
    ap.add_argument("--missing", action="store_true", help="prompts: only missing assets")
    ap.add_argument("--style", default=None, help="style preset (default: stamped game style)")
    ap.add_argument("image", nargs="?", help="postprocess: input image")
    ap.add_argument("--out", help="postprocess: output path")
    ap.add_argument("--source", help="attribute: where the asset came from")
    ap.add_argument("--license", dest="license_type", help="attribute: license (CC0, CC-BY 4.0, none, ...)")
    ap.add_argument("--url", default="", help="attribute: source URL")
    ap.add_argument("--author", default="", help="attribute: author name")
    args = ap.parse_args()

    style = args.style or detect_style()
    if style not in STYLE_PACKS:
        sys.exit(f"✗ unknown style '{style}' (have: {', '.join(STYLE_PACKS)})")

    if args.command == "manifest":
        write_manifest(style)
    elif args.command == "prompts":
        items = build_manifest(style)
        if args.missing:
            items = [i for i in items if not (GAME / i["path"]).exists()]
        for n, i in enumerate(items, 1):
            print(f"[{n}] {i['path']}")
            print(f"    {i['prompt']}")
            print()
        print(f"{len(items)} prompt(s) | style: {STYLE_PACKS[style]['label']}")
    elif args.command == "wire":
        wire()
    elif args.command == "verify":
        verify()
    elif args.command == "postprocess":
        if not args.image:
            sys.exit("postprocess needs an image path")
        postprocess(args.image, style, args.out)
    elif args.command == "attribute":
        if not args.image or not args.source or not args.license_type:
            sys.exit("attribute needs: <path> --source <name> --license <type>")
        attribute(args.image, args.source, args.license_type, args.url, args.author)
    elif args.command == "report":
        report()


if __name__ == "__main__":
    main()
