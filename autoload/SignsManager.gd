# SignsManager.gd
# Loads signs.json, assigns symptom/infection signs to visitors, and calculates infection probability.
extends Node

var signs_database: Dictionary = {}
const SIGNS_FILE_PATH: String = "res://assets/data/signs.json"

func _ready() -> void:
	load_signs_database()

func load_signs_database() -> void:
	if not FileAccess.file_exists(SIGNS_FILE_PATH):
		push_error("[SignsManager] signs.json not found at %s" % SIGNS_FILE_PATH)
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
		push_error("[SignsManager] failed to parse signs.json")

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
