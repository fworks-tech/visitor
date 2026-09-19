import json
import os
import re

def test_signs_json():
    json_path = "visitor/assets/data/signs.json"
    assert os.path.exists(json_path), f"File {json_path} does not exist"
    
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    physical_signs = [s for s in data.get("signs", []) if s.get("category") == "physical"]
    behavioral_signs = [s for s in data.get("signs", []) if s.get("category") == "behavioral"]
    # Legacy shape fallback
    physical_signs += data.get("physical_signs", [])
    behavioral_signs += data.get("behavioral_signs", [])

    print(f"Physical signs count: {len(physical_signs)}")
    print(f"Behavioral signs count: {len(behavioral_signs)}")

    assert len(physical_signs) >= 20, f"Expected 20+ physical signs, got {len(physical_signs)}"
    assert len(behavioral_signs) >= 10, f"Expected 10+ behavioral signs, got {len(behavioral_signs)}"

    required_keys = ["id", "name", "category"]

    def norm_level(s):
        if "ambiguity_level" in s:
            return s["ambiguity_level"]
        a = int(s.get("ambiguity", 3))
        return "low" if a <= 2 else ("high" if a >= 4 else "medium")
    
    all_ids = set()
    for sign in physical_signs + behavioral_signs:
        for k in required_keys:
            assert k in sign, f"Sign {sign.get('id')} missing required key '{k}'"
        assert sign["category"] in ["physical", "behavioral"], f"Invalid category: {sign['category']}"
        assert norm_level(sign) in ["low", "medium", "high"], f"Invalid ambiguity: {sign}"
        assert sign["id"] not in all_ids, f"Duplicate sign ID: {sign['id']}"
        all_ids.add(sign["id"])
        
    print("SUCCESS: signs.json is valid!")

def test_gdscript_files():
    scripts = [
        "visitor/scripts/systems/SignsSystem.gd",
        "visitor/scripts/systems/InfectionSystem.gd",
        "visitor/scripts/systems/ConsequencesSystem.gd",
        "visitor/scripts/systems/GameLoop.gd",
        "visitor/scripts/systems/ResourceManager.gd"
    ]
    
    for script_path in scripts:
        assert os.path.exists(script_path), f"Script {script_path} does not exist"
        with open(script_path, "r", encoding="utf-8") as f:
            content = f.read()
            
        # Basic check for class_name
        assert "class_name" in content, f"{script_path} missing class_name declaration"
        print(f"Validated script presence & class_name for: {script_path}")

    # Check key required methods
    with open("visitor/scripts/systems/InfectionSystem.gd") as f:
        inf_content = f.read()
        assert "func get_visible_signs(" in inf_content, "InfectionSystem.gd missing get_visible_signs"
        assert "func will_turn_today(" in inf_content, "InfectionSystem.gd missing will_turn_today"
        
    with open("visitor/scripts/systems/ConsequencesSystem.gd") as f:
        con_content = f.read()
        assert "func process_day(" in con_content, "ConsequencesSystem.gd missing process_day"
        
    with open("visitor/scripts/systems/SignsSystem.gd") as f:
        sign_content = f.read()
        assert "func inspect_sign(" in sign_content or "func inspect_visitor(" in sign_content, "SignsSystem.gd missing inspect method"

    print("SUCCESS: GDScript methods verified!")

if __name__ == "__main__":
    test_signs_json()
    test_gdscript_files()
