class_name SignsSystem
extends Node

## SignsSystem
## Manages sign definitions, sign assignment to visitors based on infection level,
## and player inspection mechanics spending Action Points (AP).

signal sign_inspected(visitor: Dictionary, sign: Dictionary, ap_remaining: int)
signal inspection_completed(visitor: Dictionary, total_revealed: int)

const DEFAULT_SIGNS_PATH: String = "res://assets/data/signs.json"
const DEFAULT_AP_PER_VISITOR: int = 4

var physical_signs: Array = []
var behavioral_signs: Array = []
var signs_by_id: Dictionary = {}

func _ready() -> void:
	load_signs_from_json(DEFAULT_SIGNS_PATH)

## Load signs catalog from JSON file. Returns true if successful.
func load_signs_from_json(path: String) -> bool:
	physical_signs.clear()
	behavioral_signs.clear()
	signs_by_id.clear()

	var file_path: String = path

	if not FileAccess.file_exists(file_path):
		push_error("SignsSystem: File not found at " + path)
		return false

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("SignsSystem: Failed to open file at " + file_path)
		return false

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)
	if parse_result != OK:
		push_error("SignsSystem: JSON parse error: " + json.get_error_message())
		return false

	var data: Dictionary = json.get_data()
	if data.has("signs") and data["signs"] is Array:
		# Canonical shape: {"signs": [{id, name, category, description, ambiguity 1-5}]}
		for sign in data["signs"]:
			var s: Dictionary = _normalize_sign(sign)
			if s.is_empty():
				continue
			signs_by_id[s["id"]] = s
			if s["category"] == "physical":
				physical_signs.append(s)
			elif s["category"] == "behavioral":
				behavioral_signs.append(s)

	if data.has("physical_signs"):
		physical_signs = data["physical_signs"]
		for sign in physical_signs:
			signs_by_id[sign["id"]] = sign

	if data.has("behavioral_signs"):
		behavioral_signs = data["behavioral_signs"]
		for sign in behavioral_signs:
			signs_by_id[sign["id"]] = sign

	print("SignsSystem: Loaded %d physical and %d behavioral signs." % [physical_signs.size(), behavioral_signs.size()])
	return true

## Maps a canonical sign (numeric ambiguity 1-5) to the runtime shape.
static func _normalize_sign(sign: Dictionary) -> Dictionary:
	if not sign.has("id") or not sign.has("name"):
		return {}
	var level := "medium"
	var amb := int(sign.get("ambiguity", 3))
	if amb <= 2:
		level = "low"
	elif amb >= 4:
		level = "high"
	var category := str(sign.get("category", "physical"))
	return {
		"id": str(sign["id"]),
		"name": str(sign["name"]),
		"category": category,
		"human_explanation": str(sign.get("description", "")),
		"infection_explanation": "",
		"ambiguity_level": level,
		"detection_method": "visual" if category == "physical" else "dialogue",
	}

## Retrieve full sign data by sign ID
func get_sign(sign_id: String) -> Dictionary:
	if signs_by_id.has(sign_id):
		return signs_by_id[sign_id]
	return {}

## Get list of all signs
func get_all_signs() -> Array:
	var all: Array = []
	all.append_array(physical_signs)
	all.append_array(behavioral_signs)
	return all

## Get signs filtered by category ("physical" or "behavioral")
func get_signs_by_category(category: String) -> Array:
	if category == "physical":
		return physical_signs.duplicate()
	elif category == "behavioral":
		return behavioral_signs.duplicate()
	return []

## Get signs filtered by detection method ("visual", "dialogue", "physical_check")
func get_signs_by_method(method: String) -> Array:
	var result: Array = []
	for sign in get_all_signs():
		if sign.get("detection_method", "") == method:
			result.append(sign)
	return result

## Assign signs to a visitor based on infection progress and ambiguity modifier.
## Infection progress ranges from 0.0 (healthy) to 1.0 (fully infected/turned).
func assign_signs_to_visitor(visitor: Dictionary, infection_progress: float, ambiguity_modifier: float = 0.5) -> Array:
	var assigned_signs: Array = []
	var is_infected: bool = visitor.get("is_infected", infection_progress >= 0.3)

	# Determine target number of signs based on infection level or stress
	var target_physical_count: int = 0
	var target_behavioral_count: int = 0

	if infection_progress < 0.3:
		# Healthy or early latent: 0-1 false positive / stress signs if high ambiguity
		if randf() < ambiguity_modifier * 0.5:
			target_physical_count = 1 if randf() > 0.5 else 0
			target_behavioral_count = 1 if target_physical_count == 0 else 0
	elif infection_progress < 0.6:
		# Subtle infection: 1 physical + 1 behavioral sign
		target_physical_count = 1
		target_behavioral_count = 1
	elif infection_progress < 0.9:
		# Moderate/severe infection: 2 physical + 2 behavioral signs
		target_physical_count = 2
		target_behavioral_count = 2
	else:
		# Advanced infection (>0.9): 3+ physical + 2+ behavioral signs
		target_physical_count = 3
		target_behavioral_count = 3

	# Pick eligible physical signs meeting infection threshold
	var candidate_physical: Array = []
	for s in physical_signs:
		var thresh: float = s.get("severity_min_threshold", 0.3)
		if is_infected and infection_progress >= thresh:
			candidate_physical.append(s)
		elif not is_infected and s.get("ambiguity_level") == "high":
			candidate_physical.append(s) # Stress false positive candidate

	candidate_physical.shuffle()
	for i in range(mini(target_physical_count, candidate_physical.size())):
		assigned_signs.append(candidate_physical[i]["id"])

	# Pick eligible behavioral signs meeting threshold
	var candidate_behavioral: Array = []
	for s in behavioral_signs:
		var thresh: float = s.get("severity_min_threshold", 0.3)
		if is_infected and infection_progress >= thresh:
			candidate_behavioral.append(s)
		elif not is_infected and s.get("ambiguity_level") == "high":
			candidate_behavioral.append(s)

	candidate_behavioral.shuffle()
	for i in range(mini(target_behavioral_count, candidate_behavioral.size())):
		assigned_signs.append(candidate_behavioral[i]["id"])

	visitor["assigned_sign_ids"] = assigned_signs
	visitor["revealed_sign_ids"] = []
	return assigned_signs

## Inspect a sign on a visitor using Action Points.
## Returns dictionary containing inspection result and remaining AP.
func inspect_sign(visitor: Dictionary, sign_id: String, current_ap: int) -> Dictionary:
	var sign_data: Dictionary = get_sign(sign_id)
	if sign_data.is_empty():
		return {"success": false, "reason": "Sign ID not found", "ap_remaining": current_ap}

	var assigned: Array = visitor.get("assigned_sign_ids", [])
	if not assigned.has(sign_id):
		return {"success": false, "reason": "Sign not present on visitor", "ap_remaining": current_ap}

	var cost: int = sign_data.get("cost_ap", 1)
	if current_ap < cost:
		return {"success": false, "reason": "Insufficient Action Points", "ap_remaining": current_ap}

	var revealed: Array = visitor.get("revealed_sign_ids", [])
	if not revealed.has(sign_id):
		revealed.append(sign_id)
		visitor["revealed_sign_ids"] = revealed

	var new_ap: int = current_ap - cost

	var result: Dictionary = {
		"success": true,
		"sign_id": sign_id,
		"sign_name": sign_data.get("name", ""),
		"category": sign_data.get("category", ""),
		"ambiguity_level": sign_data.get("ambiguity_level", "medium"),
		"detection_method": sign_data.get("detection_method", "visual"),
		"human_explanation": sign_data.get("human_explanation", ""),
		"infection_explanation": sign_data.get("infection_explanation", ""),
		"ap_spent": cost,
		"ap_remaining": new_ap
	}

	sign_inspected.emit(visitor, result, new_ap)
	return result

## Get all signs that have been revealed by player inspection for this visitor
func get_revealed_signs(visitor: Dictionary) -> Array:
	var result: Array = []
	var revealed_ids: Array = visitor.get("revealed_sign_ids", [])
	for sid in revealed_ids:
		var sign: Dictionary = get_sign(sid)
		if not sign.is_empty():
			result.append(sign)
	return result

## Get signs assigned to visitor that have NOT yet been revealed by inspection
func get_unrevealed_signs(visitor: Dictionary) -> Array:
	var result: Array = []
	var assigned_ids: Array = visitor.get("assigned_sign_ids", [])
	var revealed_ids: Array = visitor.get("revealed_sign_ids", [])
	for sid in assigned_ids:
		if not revealed_ids.has(sid):
			var sign: Dictionary = get_sign(sid)
			if not sign.is_empty():
				result.append(sign)
	return result

## Check if player can afford to inspect a given sign
func can_inspect(sign_id: String, available_ap: int) -> bool:
	var sign: Dictionary = get_sign(sign_id)
	if sign.is_empty():
		return false
	return available_ap >= sign.get("cost_ap", 1)
