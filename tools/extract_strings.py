#!/usr/bin/env python3
"""
extract_strings.py — DEEPTALES translation workflow
====================================================

Keeps a game's locale JSONs in sync with its story data. The game calls tr()
with the ENGLISH string as the translation key, so this tool extracts every
player-facing English string from assets/data/ and merges it into
locale/en.json + locale/pt_BR.json without losing translations you made.

Locale files are plain {english: translated} maps, loaded at runtime by
SettingsManager.load_locale_files() — no Godot CSV importer involved.

Usage (from inside a generated project, or pass the project dir):
    python3 tools/extract_strings.py                # report only
    python3 tools/extract_strings.py --write        # merge into the JSONs
    python3 tools/extract_strings.py /path/to/game --write

How it works
------------
1. Detects the genre: assets/data/visitors.json -> fate_arbiter,
    otherwise narrative_choice.
2. Walks the data files and collects player-facing strings
    (dialogue, choices, prompts, briefings, ending text, sign names...).
3. Reads the existing locale/pt_BR.json and keeps any translation already
    present for a key; new keys get an empty pt_BR value (the game falls
    back to the English key until you translate it).
4. --write rewrites both JSONs, sorted for stable diffs. Without --write
    it only reports what's new/missing.
"""

import argparse
import json
import sys
from pathlib import Path

# Story fields that hold player-facing prose, per data shape.
# (field name, recurse-into subfields) — kept explicit so the extraction is
# predictable and easy to extend per genre.
NARRATIVE_TEXT_FIELDS = ("text", "prompt")


def _walk(value, fields, out):
    """Recursively collect strings from the given text fields."""
    if isinstance(value, dict):
        for k, v in value.items():
            if k in fields and isinstance(v, str) and v.strip() and not v.startswith("TODO"):
                out.add(v.strip())
            else:
                _walk(v, fields, out)
    elif isinstance(value, list):
        for item in value:
            _walk(item, fields, out)


def collect_narrative(data_dir):
    """narrative_choice: dialogue lines, choice labels, prompts."""
    strings = set()
    story = data_dir / "story.json"
    if story.exists():
        _walk(json.loads(story.read_text(encoding="utf-8")),
               NARRATIVE_TEXT_FIELDS, strings)
    return strings


def collect_fate_arbiter(data_dir):
    """fate_arbiter: visitor stories + dialogue, night briefings, endings,
    sign names + explanations."""
    strings = set()
    for fname, fields in (
        ("visitors.json", ("backstory", "text", "name")),
        ("story.json", ("briefing", "title", "text", "summary", "epilogue")),
        ("signs.json", ("name", "human_explanation", "infection_explanation")),
    ):
        path = data_dir / fname
        if path.exists():
            _walk(json.loads(path.read_text(encoding="utf-8")), fields, strings)
    return strings


def read_json(path):
    """Existing locale JSON -> {key: translation}; missing file -> {}."""
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def write_json(path, strings, existing):
    """Write {key: translation} map; preserve existing translations."""
    merged = {s: existing.get(s, "") for s in sorted(strings)}
    missing = sum(1 for v in merged.values() if not v)
    path.write_text(json.dumps(merged, ensure_ascii=False, indent=1, sort_keys=True)
                    + "\n", encoding="utf-8")
    return missing


def main():
    ap = argparse.ArgumentParser(
        description="Extract translatable strings from story data into locale CSVs")
    ap.add_argument("project", nargs="?", default=".", help="Project root (default: cwd)")
    ap.add_argument("--write", action="store_true",
                    help="Write the merged CSVs (default: report only)")
    args = ap.parse_args()

    root = Path(args.project)
    data_dir = root / "assets" / "data"
    locale_dir = root / "locale"
    if not data_dir.exists():
        sys.exit(f"No assets/data at {root} — run from inside a DEEPTALES project")

    if (data_dir / "visitors.json").exists():
        strings = collect_fate_arbiter(data_dir)
        genre = "fate_arbiter"
    else:
        strings = collect_narrative(data_dir)
        genre = "narrative_choice"

    existing_pt = read_json(locale_dir / "pt_BR.json")
    already = set(existing_pt.keys())
    new_keys = strings - already
    untranslated = [s for s in strings if not existing_pt.get(s)]

    print(f"Genre: {genre}")
    print(f"Player-facing strings in data: {len(strings)}")
    print(f"New since last extraction:    {len(new_keys)}")
    print(f"Missing pt_BR translation:    {len(untranslated)}")
    for s in sorted(new_keys)[:10]:
        print(f"  + {s[:70]}")
    if len(new_keys) > 10:
        print(f"  ... and {len(new_keys) - 10} more")

    if args.write:
        locale_dir.mkdir(exist_ok=True)
        for lang in ("en", "pt_BR"):
            existing = existing_pt if lang == "pt_BR" else {}
            missing = write_json(locale_dir / f"{lang}.json", strings, existing)
        print(f"Wrote locale/en.json + locale/pt_BR.json "
              f"({len(untranslated)} pt_BR values still empty)")
    elif new_keys:
        print("Run with --write to merge these into the JSONs.")


if __name__ == "__main__":
    main()
