#!/usr/bin/env python3
"""
deeptales-author — DEEPTALES Story Authoring CLI
================================================

Write DEEPTALES stories without hand-editing engine JSON. One source file
(`story_source.jsonc`) per game, with `//` comments allowed, plus shorthand
that the compiler expands into the exact shapes the games consume.

    python3 author_cli.py init <game-dir>      # import existing data -> source skeleton
    python3 author_cli.py validate <game-dir> # schema, graph, flags, portraits
    python3 author_cli.py compile <game-dir>   # source -> assets/data/*.json (+ locale sync)
    python3 author_cli.py stats <game-dir>     # word/branch/flag report
    python3 author_cli.py diagram <game-dir>   # Mermaid flow export

Author format
-------------
`story_source.jsonc` lives in the game root. JSON with:
  - `//` line comments anywhere
  - dialogue entries may be plain strings: "Name: the line" expands to
    {"speaker": "Name", "text": "the line"}; a bare string with no "Name:"
    becomes narration {"speaker": "", "text": "..."}
  - checkpoint `id` and `chapter` fields are auto-filled from the structure
  - narrative_choice games: `chapters` -> story.json
  - fate_arbiter games: `nights`, `visitors`, `signs`, `endings` sections ->
    story.json, visitors.json, signs.json

Round-trip safety: compile records hashes in assets/data/.author_meta.json.
If you hand-edit a compiled file after compiling, compile refuses until you
commit those edits back into the source (or pass --force, which prints a
summary of what the hand-edits were about to be replaced).
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

VALID_CP_TYPES = ("cutscene", "choice", "exploration", "puzzle", "end")
DECISIONS = ("let_in", "turn_away", "eliminate")

# ---------------------------------------------------------------- helpers


def load_jsonc(path):
    """JSON with // line comments. Strips // only OUTSIDE string literals,
    so URLs like \"https://...\" inside values are safe."""
    text = Path(path).read_text(encoding="utf-8")
    out = []
    in_string = False
    i = 0
    while i < len(text):
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < len(text):   # escaped char — keep both
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            # skip to end of line
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    try:
        return json.loads("".join(out))
    except json.JSONDecodeError as e:
        raise ValueError(
            f"story_source.jsonc: JSON error at line {e.lineno}, column {e.colno}: {e.msg}\n"
            f"  (remember: // comments are fine, but JSON itself must be valid — "
            f"check for unquoted keys, trailing commas, or a missing : after a key)")


def sha(data_bytes):
    return hashlib.sha256(data_bytes).hexdigest()[:16]


def expand_dialogue(dlg):
    """'Name: line' strings -> speaker/text dicts (already-dicts pass through)."""
    out = []
    for line in dlg:
        if isinstance(line, dict):
            out.append(line)
            continue
        text = str(line).strip()
        m = re.match(r"^([A-Za-z0-9_' -]+?):\s+(.+)$", text)
        if m:
            out.append({"speaker": m.group(1).strip(), "text": m.group(2).strip()})
        else:
            out.append({"speaker": "", "text": text})
    return out


def words_of(obj):
    """Count player-facing words in nested dicts/lists."""
    total = 0
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ("text", "prompt", "narration", "backstory", "briefing",
                     "summary", "description", "epilogue", "human_explanation",
                     "infection_explanation") and isinstance(v, str):
                total += len(v.split())
            else:
                total += words_of(v)
    elif isinstance(obj, list):
        for item in obj:
            total += words_of(item)
    return total


def load_source(game_dir):
    src = game_dir / "story_source.jsonc"
    if not src.exists():
        sys.exit(f"No story_source.jsonc in {game_dir} — run 'init' first.")
    return load_jsonc(src), src


def detect_genre(game_dir):
    return "fate_arbiter" if (game_dir / "assets/data/visitors.json").exists() else "narrative_choice"


def read_meta(game_dir):
    p = game_dir / "assets/data/.author_meta.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def write_meta(game_dir, source, outputs):
    """outputs maps filename -> exact bytes as written to disk."""
    meta = {"source_sha": sha(source.encode()), "outputs": {}}
    for rel, content in outputs.items():
        raw = content if isinstance(content, bytes) else content.encode()
        meta["outputs"][rel] = sha(raw)
    (game_dir / "assets/data/.author_meta.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8")


def check_roundtrip(game_dir, outputs):
    """M2-8: refuse to clobber hand-edited compiled files."""
    meta = read_meta(game_dir)
    edited = []
    for rel, new_data in outputs.items():
        compiled = game_dir / "assets/data" / rel
        current = compiled.read_text(encoding="utf-8") if compiled.exists() else ""
        if current and meta.get("outputs", {}).get(rel) and \
           sha(current.encode()) != meta["outputs"][rel]:
            edited.append(rel)
    return edited

# ---------------------------------------------------------------- init


SKELETON_NOTE = """// =============================================================================
// DEEPTALES story source — the single place you write your story.
// Compile with:  python3 tools/author_cli.py compile .
//   - // comments like this are allowed anywhere
//   - dialogue may be plain strings: "Name: the line" (narrator lines: no name)
//   - checkpoint id/chapter fields are filled in automatically
// =============================================================================
"""


def init_cmd(game_dir, force=False):
    """Import the game's existing compiled data into a commented source file."""
    out = game_dir / "story_source.jsonc"
    if out.exists() and not force:
        sys.exit(f"{out} already exists — init would OVERWRITE your authored story.\n"
                 f"Move/delete it first, or re-run init with --force if you really "
                 f"want to re-import the compiled data.")
    genre = detect_genre(game_dir)
    data_dir = game_dir / "assets/data"

    if genre == "narrative_choice":
        story = json.loads((data_dir / "story.json").read_text(encoding="utf-8"))
        source = {"game": {"title": story.get("game_title", ""), "genre": genre},
                  "chapters": story["chapters"]}
        for ch in source["chapters"].values():
            for cp in ch["checkpoints"].values():
                cp.pop("id", None); cp.pop("chapter", None)   # auto-filled at compile
    else:
        story = json.loads((data_dir / "story.json").read_text(encoding="utf-8"))
        visitors = json.loads((data_dir / "visitors.json").read_text(encoding="utf-8"))
        signs = json.loads((data_dir / "signs.json").read_text(encoding="utf-8"))
        source = {
            "game": {"title": story.get("game_title", ""), "genre": genre},
            "nights": story.get("nights", {}),
            "endings": story.get("endings", []),
            "visitors": visitors.get("visitors", []),
            "signs": {"physical_signs": signs.get("physical_signs", []),
                      "behavioral_signs": signs.get("behavioral_signs", [])},
        }

    out = game_dir / "story_source.jsonc"
    body = json.dumps(source, indent=2, ensure_ascii=False)
    # comment-annotate common fields for human readers
    body = body.replace('"chapters": {', '"chapters": {   // numeric keys = chapter numbers')
    out.write_text(SKELETON_NOTE + body + "\n", encoding="utf-8")
    print(f"Imported existing {genre} data -> {out}")
    print("Edit the story here, then: python3 tools/author_cli.py compile .")

# ---------------------------------------------------------------- validate


def entry_of(chapters):
    """The checkpoint the engine actually enters on new game: the first
    checkpoint (document order) of the lowest-numbered chapter."""
    if not chapters:
        return None
    first = sorted(chapters.keys(), key=lambda x: int(str(x)))[0]
    cps = chapters[first].get("checkpoints", {})
    return next(iter(cps), None)


def validate_narrative(source):
    errors, warnings = [], []
    chapters = source.get("chapters", {})
    cps, ends = {}, []

    for ch_num, ch in chapters.items():
        if not str(ch_num).isdigit():
            errors.append(f"chapter key '{ch_num}' should be numeric")
        for cp_id, cp in ch.get("checkpoints", {}).items():
            cp["_chapter"] = ch_num
            cps[cp_id] = cp
            t = cp.get("type", "cutscene")
            if t not in VALID_CP_TYPES:
                errors.append(f"{cp_id}: invalid type '{t}' (allowed: {', '.join(VALID_CP_TYPES)})")
            if t == "end":
                ends.append(cp_id)
            dlg = cp.get("dialogue", [])
            if isinstance(dlg, list):
                for i, line in enumerate(dlg):
                    if isinstance(line, dict) and not line.get("text", "").strip():
                        errors.append(f"{cp_id}: dialogue[{i}] has empty text")
            if t == "choice":
                ch_list = cp.get("choices", [])
                if len(ch_list) < 2:
                    warnings.append(f"{cp_id}: choice checkpoint with {len(ch_list)} option(s) — players need a real decision")
                ids = [c.get("id", f"choice_{i}") for i, c in enumerate(ch_list)]
                if len(set(ids)) != len(ids):
                    errors.append(f"{cp_id}: duplicate choice ids {ids}")
                for c in ch_list:
                    if not c.get("text"):
                        errors.append(f"{cp_id}: a choice has no 'text'")
            if t != "end" and t != "choice" and not cp.get("next"):
                errors.append(f"{cp_id}: {t} checkpoint has no 'next' (dead end — add next or make it type end)")

    # graph integrity
    for cp_id, cp in cps.items():
        if "next" in cp and cp["next"] not in cps:
            errors.append(f"{cp_id}: next -> '{cp['next']}' does not exist")
        for c in cp.get("choices", []):
            if c.get("next") not in cps:
                errors.append(f"{cp_id}: choice '{c.get('text', c.get('id'))}' -> '{c.get('next')}' does not exist")

    if not cps:
        errors.append("story has no checkpoints")
        return errors, warnings, cps
    if not ends:
        errors.append("story has no endings (no checkpoint with type 'end')")

    # reachability: forward from the real entry point
    entry = entry_of(source.get("chapters", {}))
    fwd = set()
    stack = [entry]
    while stack:
        cur = stack.pop()
        if cur in fwd or cur not in cps:
            continue   # missing targets are already reported as errors
        fwd.add(cur)
        cp = cps[cur]
        if cp.get("next"):
            stack.append(cp["next"])
        for c in cp.get("choices", []):
            if c.get("next"):
                stack.append(c["next"])
    unreachable = set(cps) - fwd
    for u in sorted(unreachable):
        warnings.append(f"{u}: unreachable from entry '{entry}'")

    no_exit = [e for e in ends if e not in fwd]
    for e in no_exit:
        warnings.append(f"{e}: ending is unreachable from entry '{entry}'")

    # flag consistency
    set_flags, req_flags = set(), set()
    def walk_flags(o, req=False):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "set" and isinstance(v, dict):
                    set_flags.update(v.keys())
                elif k == "requires" and isinstance(v, dict):
                    req_flags.update(v.keys())
                else:
                    walk_flags(v, req)
        elif isinstance(o, list):
            for i in o:
                walk_flags(i, req)
    walk_flags(source)
    for f in sorted(req_flags - set_flags):
        warnings.append(f"flag '{f}' is required somewhere but never set — it will always be falsy")

    # portrait manifest sync (M2-6)
    portraits_p = Path("assets/data/portraits.json")
    if portraits_p.exists():
        known = set(json.loads(portraits_p.read_text(encoding="utf-8")).get("characters", {}).keys())
        speakers = {l.get("speaker", "").lower() for cp in cps.values()
                    for l in (cp.get("dialogue", []) if isinstance(cp.get("dialogue"), list) else [])
                    if isinstance(l, dict)} - {""}
        for sp in sorted(speakers - {k.lower() for k in known}):
            warnings.append(f"character '{sp}' speaks but has no portrait — add to portraits.json "
                            f"(suggested prompt: uncanny hand-drawn portrait of {sp}, dark horror, desaturated)")
    return errors, warnings, cps


def validate_fate(source):
    errors, warnings = [], []
    signs = {}
    for cat in ("physical_signs", "behavioral_signs"):
        for s in source.get("signs", {}).get(cat, []):
            if s.get("id") in signs:
                errors.append(f"duplicate sign id '{s.get('id')}'")
            if not s.get("id"):
                errors.append(f"sign in {cat} has no id")
            if s.get("id"):
                signs[s["id"]] = s
    visitors, seen = [], set()
    for v in source.get("visitors", []):
        vid = v.get("id", "?")
        if vid in seen:
            errors.append(f"duplicate visitor id '{vid}'")
        seen.add(vid)
        prog = v.get("infection_progress")
        if not isinstance(prog, (int, float)) or not 0.0 <= float(prog) <= 1.0:
            errors.append(f"{vid}: infection_progress must be 0.0-1.0 (got {prog})")
        decision = str(v.get("correct_decision", "")).lower()
        if decision not in DECISIONS:
            errors.append(f"{vid}: correct_decision must be one of {DECISIONS}")
        for sid in v.get("signs", []):
            if sid not in signs:
                errors.append(f"{vid}: references unknown sign '{sid}'")
        if not v.get("backstory"):
            warnings.append(f"{vid}: no backstory — inspection dialogue will feel thin")
        visitors.append(v)
    # Nights: a list of night objects; scheduling is per-visitor via
    # nights_available, so check every night has at least one visitor.
    nights = source.get("nights", [])
    night_numbers = set()
    for night in (nights if isinstance(nights, list) else list(nights.values())):
        n_num = night.get("night_number", night.get("day", "?"))
        night_numbers.add(n_num)
        scheduled = [v for v in visitors
                     if n_num in (v.get("nights_available") or [])]
        if not scheduled:
            warnings.append(f"night {n_num}: no visitor has this night in nights_available — nothing will knock")

    for v in visitors:
        for n in (v.get("nights_available") or []):
            if night_numbers and n not in night_numbers:
                errors.append(f"{v['id']}: nights_available references unknown night {n}")

    endings = source.get("endings", [])
    if isinstance(endings, dict):
        endings = list(endings.values())
    if not endings:
        warnings.append("no endings defined — game cannot conclude")
    for e in endings:
        cond = e.get("conditions", {})
        if isinstance(cond, dict) and not cond:
            warnings.append(f"ending '{e.get('id', '?')}': no conditions — it may never trigger")
    return errors, warnings, {"visitors": visitors, "signs": signs, "nights": nights}


def validate_cmd(game_dir, as_json=False):
    source, _ = load_source(game_dir)
    genre = source.get("game", {}).get("genre", detect_genre(game_dir))
    if genre == "fate_arbiter":
        errors, warnings, _ = validate_fate(source)
    else:
        errors, warnings, _ = validate_narrative(source)
    result = {"ok": not errors, "errors": errors, "warnings": warnings}
    if not as_json:
        for e in errors:
            print(f"  ERROR {e}")
        for w in warnings:
            print(f"  warn  {w}")
        print(f"{'FAILED' if errors else 'PASSED'} — {len(errors)} error(s), {len(warnings)} warning(s)")
    return result

# ---------------------------------------------------------------- compile


def compile_cmd(game_dir, force, as_json=False):
    source, src_path = load_source(game_dir)
    genre = source.get("game", {}).get("genre", detect_genre(game_dir))
    data_dir = game_dir / "assets/data"
    data_dir.mkdir(parents=True, exist_ok=True)

    if genre == "narrative_choice":
        errors, _, _ = validate_narrative(source)
    else:
        errors, _, _ = validate_fate(source)
    if errors:
        if not as_json:
            for e in errors:
                print(f"  ERROR {e}")
            print("Validation failed — fix the source before compiling.")
        return {"ok": False, "stage": "validate", "errors": errors}

    outputs = {}
    if genre == "narrative_choice":
        chapters = {}
        for ch_num, ch in source.get("chapters", {}).items():
            cps = {}
            for cp_id, cp in ch.get("checkpoints", {}).items():
                out = dict(cp)
                out.pop("_chapter", None)
                out["id"] = cp_id
                out["chapter"] = int(ch_num)
                if isinstance(out.get("dialogue"), list):
                    out["dialogue"] = expand_dialogue(out["dialogue"])
                cps[cp_id] = out
            chapters[str(ch_num)] = {"id": int(ch_num), "title": ch.get("title", ""),
                                     "summary": ch.get("summary", ""), "checkpoints": cps}
        end_count = sum(1 for c in chapters.values() for cp in c["checkpoints"].values()
                        if cp.get("type") == "end")
        story = {"game_title": source.get("game", {}).get("title", ""),
                 "version": source.get("game", {}).get("version", "1.0"),
                 "total_endings": end_count,
                 "chapters": chapters}
        outputs["story.json"] = json.dumps(story, indent=2, ensure_ascii=False)
    else:
        story = {"version": source.get("game", {}).get("version", "1.0"),
                 "title": source.get("game", {}).get("title", ""),
                 "game_title": source.get("game", {}).get("title", ""),
                 "description": source.get("game", {}).get("description", ""),
                 "tracked_stats": source.get("tracked_stats", []),
                 "total_nights": len(source.get("nights", {})),
                 "nights": source.get("nights", {}),
                 "endings": source.get("endings", [])}
        visitors = source.get("visitors", [])
        signs = source.get("signs", {})
        outputs["story.json"] = json.dumps(story, indent=2, ensure_ascii=False)
        outputs["visitors.json"] = json.dumps(
            {"version": "1.0",
             "description": source.get("game", {}).get("description", ""),
             "total_count": len(visitors), "visitors": visitors},
            indent=2, ensure_ascii=False)
        outputs["signs.json"] = json.dumps(signs, indent=2, ensure_ascii=False)

    # M2-8 round-trip safety
    edited = check_roundtrip(game_dir, outputs)
    if edited and not force:
        if not as_json:
            print(f"Refusing to compile: {', '.join(edited)} changed by hand after the last "
                  f"compile. Move those edits into story_source.jsonc, or re-run with --force "
                  f"(hand-edits will be overwritten).")
        return {"ok": False, "stage": "roundtrip", "hand_edited": edited}

    file_bytes = {}
    for rel, data in outputs.items():
        content = (data + "\n").encode("utf-8")
        (data_dir / rel).write_bytes(content)
        file_bytes[rel] = content
    write_meta(game_dir, src_path.read_text(encoding="utf-8"), file_bytes)

    # M2-7 translation scaffold: sync locale CSVs with new strings
    i18n = game_dir / "tools/extract_strings.py"
    if i18n.exists():
        r = subprocess.run([sys.executable, str(i18n), str(game_dir), "--write"],
                           capture_output=True, text=True)
        if r.returncode == 0 and not as_json:
            print("Locale CSVs synced (tools/extract_strings.py)")

    result = {"ok": True, "compiled": sorted(outputs)}
    if not as_json:
        print(f"Compiled {len(outputs)} data file(s) -> assets/data/")
        stats_cmd(game_dir, quiet_exit=True)
    else:
        source_for_stats, _ = load_source(game_dir)
        result["stats"] = stats_dict(source_for_stats, genre)
    return result

# ---------------------------------------------------------------- stats


def stats_dict(source, genre):
    d = {"genre": genre, "words": words_of(source)}
    if genre == "narrative_choice":
        _, _, cps = validate_narrative(source)
        d["chapters"] = len(source.get("chapters", {}))
        d["checkpoints"] = len(cps)
        d["choices"] = sum(len(cp.get("choices", [])) for cp in cps.values())
        d["endings"] = sum(1 for cp in cps.values() if cp.get("type") == "end")
        flags = set()
        def _flags(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    if k == "set" and isinstance(v, dict): flags.update(v.keys())
                    else: _flags(v)
            elif isinstance(o, list):
                for i in o: _flags(i)
        _flags(source)
        d["flags"] = len(flags)
    else:
        nights = source.get("nights", [])
        s = source.get("signs", {})
        d["nights"] = len(nights)
        d["visitors"] = len(source.get("visitors", []))
        d["signs"] = len(s.get("physical_signs", [])) + len(s.get("behavioral_signs", []))
        endings = source.get("endings", [])
        d["endings"] = len(endings.values()) if isinstance(endings, dict) else len(endings)
    return d


def stats_cmd(game_dir, quiet_exit=False, as_json=False):
    source, _ = load_source(game_dir)
    genre = source.get("game", {}).get("genre", detect_genre(game_dir))
    if as_json:
        return stats_dict(source, genre)
    print(f"\n--- stats ({genre}) ---")
    print(f"Words of player-facing text: {words_of(source)}")
    if genre == "narrative_choice":
        _, _, cps = validate_narrative(source)
        choices = sum(len(cp.get('choices', [])) for cp in cps.values())
        ends = [cp for cp in cps.values() if cp.get("type") == "end"]
        flags = set()
        def _flags(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    if k == "set" and isinstance(v, dict): flags.update(v.keys())
                    else: _flags(v)
            elif isinstance(o, list):
                for i in o: _flags(i)
        _flags(source)
        print(f"Chapters: {len(source.get('chapters', {}))}  checkpoints: {len(cps)}  "
              f"choices: {choices}  endings: {len(ends)}  flags: {len(flags)}")
    else:
        v = source.get("visitors", [])
        s = source.get("signs", {})
        nights = source.get("nights", [])
        print(f"Nights: {len(nights)}  visitors: {len(v)}  "
              f"signs: {len(s.get('physical_signs', [])) + len(s.get('behavioral_signs', []))}  "
              f"endings: {len(source.get('endings', []))}")


# ---------------------------------------------------------------- diagram


def _narrative_graph(cps):
    nodes, edges = [], []
    for cp_id, cp in cps.items():
        t = cp.get("type", "cutscene")
        nodes.append({"id": cp_id, "kind": t, "label": cp_id,
                      "meta": {"chapter": cp.get("chapter", "")}})
        if cp.get("next"):
            edges.append({"from": cp_id, "to": cp["next"], "label": ""})
        for i, c in enumerate(cp.get("choices", [])):
            label = (c.get("text", "") or c.get("id", f"opt{i}"))[:24]
            edges.append({"from": cp_id, "to": c.get("next", ""), "label": label})
    return nodes, edges


def _fate_graph(source):
    """Nights -> visitors -> outcomes. Coverage warnings are part of the graph:
    a night nobody knocks on is a dead night."""
    nights = source.get("nights", [])
    visitors = source.get("visitors", [])
    nights = nights if isinstance(nights, list) else list(nights.values())
    nodes, edges, warns = [], [], []
    for n in nights:
        num = n.get("night_number", n.get("id"))
        nodes.append({"id": f"night_{num}", "kind": "night",
                      "label": f"N{num} · {(n.get('title') or '')[:22]}",
                      "meta": {"number": num}})
    outcomes = {}
    for v in visitors:
        vid = v.get("id") or v.get("name", "?")
        nodes.append({"id": vid, "kind": "visitor",
                      "label": v.get("name", vid),
                      "meta": {"infected": v.get("is_actually_infected", False),
                               "recurring": v.get("recurring", False),
                               "nights": v.get("nights_available", [])}})
        for num in (v.get("nights_available") or []):
            edges.append({"from": f"night_{num}", "to": vid, "label": "knocks"})
        for act in ("LET_IN", "TURN_AWAY", "ELIMINATE"):
            cons = (v.get("consequences") or {}).get(act)
            if cons:
                outcomes.setdefault(str(cons), None)
                edges.append({"from": vid, "to": str(cons),
                              "label": act.replace("_", " ").lower()})
    for o in outcomes:
        nodes.append({"id": o, "kind": "outcome", "label": o})
    knocking = {e["from"] for e in edges if e["label"] == "knocks"}
    for n in nights:
        num = n.get("night_number", n.get("id"))
        if f"night_{num}" not in knocking:
            warns.append(f"night {num}: no visitor knocks on this night — dead night")
    return nodes, edges, warns


def diagram_cmd(game_dir, as_json=False):
    source, _ = load_source(game_dir)
    genre = source.get("game", {}).get("genre", detect_genre(game_dir))
    warns = []
    if genre == "narrative_choice":
        _, _, cps = validate_narrative(source)
        nodes, edges = _narrative_graph(cps)
        lines = ["flowchart TD"]
        for cp in nodes:
            if cp["kind"] == "end":
                lines.append(f'    {cp["id"]}(["{cp["id"]} (end)"])')
                lines.append(f'    style {cp["id"]} fill:#3E5C46,color:#E6E1D5')
            elif cp["kind"] == "choice":
                lines.append(f'    {cp["id"]}{{"{cp["id"]}?"}}')
            else:
                lines.append(f'    {cp["id"]}["{cp["id"]}"]')
        for e in edges:
            if e["label"]:
                lines.append(f'    {e["from"]} -->|"{e["label"]}"| {e["to"]}')
            else:
                lines.append(f'    {e["from"]} --> {e["to"]}')
        mmd = "\n".join(lines)
    else:
        nodes, edges, warns = _fate_graph(source)
        lines = ["flowchart LR"]
        for nd in nodes:
            if nd["kind"] == "night":
                lines.append(f'    {nd["id"]}["{nd["label"]}"]')
            elif nd["kind"] == "visitor":
                tag = " ☣" if nd["meta"].get("infected") else ""
                lines.append(f'    {nd["id"]}{{"{nd["label"]}{tag}"}}')
                lines.append(f'    style {nd["id"]} fill:#26302B,color:#E6E1D5')
            else:
                lines.append(f'    {nd["id"]}(["{nd["label"]}"])')
                lines.append(f'    style {nd["id"]} fill:#6E2B26,color:#E6E1D5')
        for e in edges:
            lines.append(f'    {e["from"]} -->|"{e["label"]}"| {e["to"]}')
        mmd = "\n".join(lines)
    (game_dir / "story_flow.mmd").write_text(mmd + "\n", encoding="utf-8")
    if as_json:
        return {"ok": True, "genre": genre, "nodes": nodes, "edges": edges,
                "warnings": warns, "mermaid": mmd}
    print(f"Wrote {len(nodes)}-node flow diagram -> {game_dir / 'story_flow.mmd'}")
    print(mmd)
    for w in warns:
        print("WARNING:", w)


# ---------------------------------------------------------------- main


def main():
    try:
        _main()
    except ValueError as e:  # parse errors from load_jsonc — clean CLI exit
        print(str(e), file=sys.stderr)
        sys.exit(1)


def _main():
    ap = argparse.ArgumentParser(prog="deeptales-author",
                                 description="DEEPTALES story authoring CLI")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("init", "validate", "stats", "diagram"):
        p = sub.add_parser(name)
        p.add_argument("game_dir", nargs="?", default=".", type=Path)
        if name in ("validate", "stats", "diagram"):
            p.add_argument("--json", action="store_true",
                          help="Machine-readable output for the Studio API")
        if name == "init":
            p.add_argument("--force", action="store_true",
                          help="Overwrite an existing story_source.jsonc (loses authored work)")
    p = sub.add_parser("compile")
    p.add_argument("game_dir", nargs="?", default=".", type=Path)
    p.add_argument("--json", action="store_true",
                   help="Machine-readable output for the Studio API")
    p.add_argument("--force", action="store_true",
                   help="Overwrite hand-edited compiled files (their edits are lost)")
    args = ap.parse_args()

    game_dir = Path(args.game_dir).resolve()
    if not (game_dir / "assets").exists():
        sys.exit(f"{game_dir} doesn't look like a game project (no assets/ dir)")

    as_json = getattr(args, "json", False)
    if args.cmd == "init":
        init_cmd(game_dir, force=getattr(args, "force", False))
    elif args.cmd == "validate":
        result = validate_cmd(game_dir, as_json=as_json)
        if as_json:
            print(json.dumps(result))
        sys.exit(0 if result["ok"] else 1)
    elif args.cmd == "compile":
        result = compile_cmd(game_dir, force=getattr(args, "force", False), as_json=as_json)
        if as_json:
            print(json.dumps(result))
        sys.exit(0 if result.get("ok") else 1)
    elif args.cmd == "stats":
        result = stats_cmd(game_dir, as_json=as_json)
        if as_json:
            print(json.dumps(result))
    elif args.cmd == "diagram":
        result = diagram_cmd(game_dir, as_json=as_json)
        if as_json:
            print(json.dumps(result))


if __name__ == "__main__":
    main()
