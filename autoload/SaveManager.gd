# SaveManager.gd
# Manages persistence of game state, visitor history, decision logs, and flags.
extends Node

signal game_saved
signal game_loaded

const SAVE_PATH: String = "user://visitor_save.json"

func save_game() -> bool:
	var save_data := {
		"version": "1.0",
		"timestamp": Time.get_datetime_string_from_system(),
		"game_manager": {
			"current_day": GameManager.current_day,
			"trust_value": GameManager.trust_value,
			"corruption_value": GameManager.corruption_value,
			"morale_value": GameManager.morale_value,
			"security_value": GameManager.security_value,
			"current_state": int(GameManager.current_state)
		},
		"flags": FlagsManager.get_all_flags(),
		"visitor_data": VisitorManager.get_save_data(),
		"resources": ResourceSystem.get_save_data()
	}
	
	var json_string := JSON.stringify(save_data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("[SaveManager] Game saved successfully to %s" % SAVE_PATH)
		game_saved.emit()
		return true
	else:
		push_error("[SaveManager] Failed to open save file for writing: %s" % SAVE_PATH)
		return false

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] No save file found at %s" % SAVE_PATH)
		return false
		
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
		
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("[SaveManager] Error parsing save file: %s" % json.get_error_message())
		return false
		
	var data: Dictionary = json.data
	
	if data.has("game_manager"):
		var gm: Dictionary = data["game_manager"]
		GameManager.current_day = gm.get("current_day", 1)
		GameManager.trust_value = gm.get("trust_value", 60)
		GameManager.corruption_value = gm.get("corruption_value", 10)
		GameManager.morale_value = gm.get("morale_value", 50)
		GameManager.security_value = gm.get("security_value", 50)
		# Restore the phase so MainMenu routes Continue to the right scene
		# (set directly — no change_state, no scene change, no pause side effect).
		var loaded_state: GameManager.GameState = gm.get("current_state", int(GameManager.GameState.NIGHT)) as GameManager.GameState
		GameManager.current_state = loaded_state
		
	if data.has("flags"):
		FlagsManager.load_flags_data(data["flags"])
		
	if data.has("visitor_data"):
		VisitorManager.load_save_data(data["visitor_data"])
		
	if data.has("resources"):
		ResourceSystem.load_save_data(data["resources"])
		
	print("[SaveManager] Game loaded successfully from %s" % SAVE_PATH)
	game_loaded.emit()
	return true

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[SaveManager] Save file deleted.")
