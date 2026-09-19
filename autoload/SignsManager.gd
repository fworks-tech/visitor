# SignsManager.gd
# Loads signs.json, assigns symptom/infection signs to visitors, and calculates infection probability.
extends Node

signal signs_evaluated(visitor_id: String, total_risk_score: float)

var signs_database: Dictionary = {}
const SIGNS_FILE_PATH: String = "res://assets/data/signs.json"

func _ready() -> void:
	load_signs_database()

func load_signs_database() -> void:
	if not FileAccess.file_exists(SIGNS_FILE_PATH):
		push_error("[SignsManager] signs.json not found at %s" % SIGNS_FILE_PATH)
		_create_fallback_signs()
		return
		
	var file := FileAccess.open(SIGNS_FILE_PATH, FileAccess.READ)
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(json_string) == OK and json.data is Dictionary:
		var raw: Variant = json.data.get("signs", {})
		if raw is Array:
			# Canonical shape: list -> id-keyed dict
			signs_database = {}
			for s in raw:
				if s is Dictionary and s.has("id"):
					signs_database[str(s["id"])] = s
		elif raw is Dictionary:
			signs_database = raw
		print("[SignsManager] Loaded %d symptom signs from database." % signs_database.size())
	else:
		_create_fallback_signs()

func _create_fallback_signs() -> void:
	signs_database = {
		"jaundice_eyes": {
			"name": "Scleral Icterus (Yellow Eyes)",
			"category": "physical",
			"description": "Marked yellow discoloration of the ocular sclera.",
			"infection_weight": 0.8,
			"false_positive_cause": "Liver stress / Jaundice"
		},
		"vein_discoloration": {
			"name": "Subcutaneous Vein Necrosis",
			"category": "physical",
			"description": "Darkened, prominent blackish veins near throat and temples.",
			"infection_weight": 0.95,
			"false_positive_cause": "Severe vascular trauma"
		},
		"fever_high": {
			"name": "High Core Temperature (>39.5°C)",
			"category": "biometric",
			"description": "Thermal scanner detects acute hyperthermia.",
			"infection_weight": 0.6,
			"false_positive_cause": "Common viral flu"
		},
		"fever_mild": {
			"name": "Mild Fever (38.1°C)",
			"category": "biometric",
			"description": "Elevated thermal signature.",
			"infection_weight": 0.2,
			"false_positive_cause": "Exhaustion, dehydration"
		},
		"tremor_hand": {
			"name": "Motor Tremor",
			"category": "behavioral",
			"description": "Involuntary quivering in hands and fingers.",
			"infection_weight": 0.3,
			"false_positive_cause": "Panic, hypothermia"
		},
		"delayed_response": {
			"name": "Cognitive Latency",
			"category": "vocal",
			"description": "Pause of >3 seconds before answering basic personal questions.",
			"infection_weight": 0.75,
			"false_positive_cause": "Shock, fatigue"
		}
	}

func get_signs_for_visitor(visitor: Dictionary) -> Array:
	var result: Array = []
	var sign_ids: Array = visitor.get("sign_ids", visitor.get("signs", []))
	
	for s_id in sign_ids:
		# visitors.json uses the "sign_" prefixed form; signs.json keys are bare ids
		s_id = str(s_id).trim_prefix("sign_")
		if signs_database.has(s_id):
			var s_data: Dictionary = signs_database[s_id].duplicate(true)
			s_data["id"] = s_id
			result.append(s_data)
			
	return result

func calculate_visitor_risk_score(assigned_signs: Array) -> float:
	var total_weight: float = 0.0
	for s in assigned_signs:
		total_weight += float(s.get("infection_weight", 0.0))
		
	return clampf(total_weight, 0.0, 1.0)

func evaluate_inspection_accuracy(assigned_signs: Array, player_flagged_ids: Array) -> Dictionary:
	var total_risk := calculate_visitor_risk_score(assigned_signs)
	var correct_flags: int = 0
	
	for f_id in player_flagged_ids:
		for s in assigned_signs:
			if s.get("id", "") == f_id:
				correct_flags += 1
				break

	var result := {
		"total_risk_score": total_risk,
		"signs_count": assigned_signs.size(),
		"flagged_count": player_flagged_ids.size(),
		"correct_flags": correct_flags,
		"is_likely_infected": total_risk >= 0.65
	}
	signs_evaluated.emit("", total_risk)
	return result
