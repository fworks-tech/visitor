#!/usr/bin/env python3
"""Data and layout contract for Visitor.

Run from anywhere: python3 tests/validate_systems.py
No Godot required, so CI can run it on every push.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_json(rel):
    path = ROOT / rel
    assert path.exists(), f"File {rel} does not exist"
    return json.loads(path.read_text(encoding="utf-8"))


def gd_block(text, marker):
    """Return the balanced {...} block that follows marker."""
    start = text.index(marker)
    depth = 0
    begun = False
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
            begun = True
        elif text[i] == "}":
            depth -= 1
            if begun and depth == 0:
                return text[start:i + 1]
    raise AssertionError(f"Unbalanced block after {marker!r}")


def test_signs_json():
    data = load_json("assets/data/signs.json")
    physical = [s for s in data.get("signs", []) if s.get("category") == "physical"]
    behavioral = [s for s in data.get("signs", []) if s.get("category") == "behavioral"]
    physical += data.get("physical_signs", [])
    behavioral += data.get("behavioral_signs", [])
    print(f"Physical signs: {len(physical)} | Behavioral signs: {len(behavioral)}")
    assert len(physical) >= 20, f"Expected 20+ physical signs, got {len(physical)}"
    assert len(behavioral) >= 10, f"Expected 10+ behavioral signs, got {len(behavioral)}"

    seen = set()
    for sign in physical + behavioral:
        for key in ("id", "name", "category"):
            assert key in sign, f"Sign {sign.get('id')} missing {key}"
        assert sign["category"] in ("physical", "behavioral"), sign
        assert sign["id"] not in seen, f"Duplicate sign ID: {sign['id']}"
        seen.add(sign["id"])
    print(f"SUCCESS: signs.json valid ({len(seen)} unique signs)")


def test_visitors_json():
    visitors = load_json("assets/data/visitors.json")
    visitors = visitors.get("visitors", visitors) if isinstance(visitors, dict) else visitors
    assert len(visitors) == 20, f"Expected 20 visitors, got {len(visitors)}"

    seen = set()
    for v in visitors:
        for key in ("id", "name", "portrait", "is_actually_infected", "nights_available", "signs"):
            assert key in v, f"Visitor {v.get('id')} missing {key}"
        assert v["id"] not in seen, f"Duplicate visitor ID: {v['id']}"
        seen.add(v["id"])
        portrait = v["portrait"].replace("res://", "")
        assert (ROOT / portrait).exists(), f"Missing portrait: {v['portrait']}"

    infected = sum(1 for v in visitors if v["is_actually_infected"])
    print(f"SUCCESS: visitors.json valid ({len(visitors)} visitors, {infected} infected)")


def test_story_json():
    story = load_json("assets/data/story.json")
    assert len(story.get("nights", [])) == 7, "Story must have 7 nights"
    assert len(story.get("endings", {})) == 7, "Story must have 7 endings"
    for night in story["nights"]:
        for key in ("night_number", "title"):
            assert key in night, f"Night missing {key}: {night}"
    for key, ending in story["endings"].items():
        assert ending.get("conditions"), f"Ending {key} has no conditions"
    print("SUCCESS: story.json valid (7 nights, 7 endings)")


def test_layout_contract():
    house = (ROOT / "scripts/house/House3D.gd").read_text(encoding="utf-8")
    scene = (ROOT / "scripts/house/HouseScene.gd").read_text(encoding="utf-8")

    layout = gd_block(house, "const LAYOUT := {")
    floors = re.findall(r'^\t"(\w+)": \{', layout, re.MULTILINE)
    rooms = re.findall(r'^\t\t"(\w+)": \{"pos"', layout, re.MULTILINE)
    assert len(floors) == 4, f"Expected 4 floors, got {floors}"
    assert len(rooms) == len(set(rooms)), "Room ids repeat across floors"

    floor_y = re.search(r"const FLOOR_Y := \{([^}]*)\}", house)
    assert floor_y, "FLOOR_Y not found"
    assert set(re.findall(r'"(\w+)":', floor_y.group(1))) == set(floors), "FLOOR_Y/LAYOUT floors differ"

    names_block = gd_block(scene, "const ROOM_NAMES := {")
    names = re.findall(r'^\t"(\w+)":', names_block, re.MULTILINE)
    missing = [r for r in rooms if r not in names]
    assert not missing, f"Rooms without a HUD name: {missing}"

    for stale in ("SECOND_FLOOR_ROOMS", "ATTIC_ROOMS", "BASEMENT_ROOMS", "ROOM_POSITIONS"):
        assert stale not in house, f"Duplicated floor table came back: {stale}"

    print(f"SUCCESS: layout contract valid ({len(floors)} floors, {len(rooms)} rooms)")


def test_consequence_system():
    path = ROOT / "scripts/systems/ConsequencesSystem.gd"
    assert path.exists(), "ConsequencesSystem.gd missing"
    content = path.read_text(encoding="utf-8")
    assert "func process_day(" in content, "ConsequencesSystem.gd missing process_day"
    print("SUCCESS: consequence system verified")


if __name__ == "__main__":
    test_signs_json()
    test_visitors_json()
    test_story_json()
    test_layout_contract()
    test_consequence_system()
    print("\nALL DATA CONTRACTS PASS")
