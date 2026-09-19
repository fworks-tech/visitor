# FlagsManager.gd
# Manages boolean/numeric/string persistent narrative and consequence flags.
extends Node

signal flag_changed(flag_name: String, value: Variant)

var _flags: Dictionary = {}
var _default_flags: Dictionary = {
	# Progression flags
	"chapter": 1,
	"day_number": 1,
	"game_started": true,
	
	# Visitor statistics & consequence counters
	"visitors_inspected_total": 0,
	"humans_let_in": 0,
	"infected_let_in": 0,
	"humans_turned_away": 0,
	"infected_turned_away": 0,
	"humans_eliminated": 0,
	"infected_eliminated": 0,
	"compound_breach_level": 0,
	"survivors_currently_inside": 0,
	
	# Story milestone flags
	"met_dr_vane": false,
	"met_marcus_scout": false,
	"radio_fixed": false,
	"medical_supplies_stolen": false,
	"generator_sabotaged": false,
	"night1_perfect": false,
	"has_scanner_upgrade": false,
	"ending_id": "",
	"ending_reason": ""
}

func _ready() -> void:
	reset_flags()

func reset_flags() -> void:
	_flags = _default_flags.duplicate(true)

func get_flag(flag_name: String, default_value: Variant = null) -> Variant:
	if _flags.has(flag_name):
		return _flags[flag_name]
	if _default_flags.has(flag_name):
		return _default_flags[flag_name]
	return default_value

func set_flag(flag_name: String, value: Variant) -> void:
	_flags[flag_name] = value
	flag_changed.emit(flag_name, value)

func increment_flag(flag_name: String, amount: int = 1) -> int:
	var current: int = int(get_flag(flag_name, 0))
	var new_val := current + amount
	set_flag(flag_name, new_val)
	return new_val

func has_flag(flag_name: String) -> bool:
	return _flags.has(flag_name)

func evaluate_requirements(requires_dict: Dictionary) -> bool:
	if requires_dict.is_empty():
		return true
		
	for key in requires_dict:
		var target_val = requires_dict[key]
		var current_val = get_flag(key)
		
		if target_val is Dictionary:
			for op in target_val:
				var compare_val = target_val[op]
				match op:
					">=":
						if not (current_val >= compare_val): return false
					">":
						if not (current_val > compare_val): return false
					"<=":
						if not (current_val <= compare_val): return false
					"<":
						if not (current_val < compare_val): return false
					"==":
						if not (current_val == compare_val): return false
					"!=":
						if not (current_val != compare_val): return false
		else:
			if current_val != target_val:
				return false
				
	return true

func apply_effects(effects_list: Array) -> void:
	for effect in effects_list:
		if effect is Dictionary:
			if effect.has("set"):
				for k in effect["set"]:
					set_flag(k, effect["set"][k])
			if effect.has("add"):
				for k in effect["add"]:
					increment_flag(k, int(effect["add"][k]))
			if effect.has("trust"):
				GameManager.trust_value += int(effect["trust"])
			if effect.has("corruption"):
				GameManager.corruption_value += int(effect["corruption"])

func get_all_flags() -> Dictionary:
	return _flags.duplicate(true)

func load_flags_data(data: Dictionary) -> void:
	_flags = data.duplicate(true)
