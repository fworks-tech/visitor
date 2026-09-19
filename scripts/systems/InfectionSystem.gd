class_name InfectionSystem
extends Node

## InfectionSystem
## Tracks individual visitor infection progression from 0.0 (human) to 1.0 (turned zombie).
## Handles stage thresholds, visible sign filtering based on infection level, daily incubation,
## and delayed turning consequences inside the shelter.

signal visitor_turned(visitor: Dictionary)
signal infection_advanced(visitor: Dictionary, old_progress: float, new_progress: float)
signal infection_suppressed(visitor: Dictionary, progress_reduced: float)

# Infection Stage Threshold Constants
const THRESHOLD_STAGE0_CLEAN: float = 0.3   # < 0.3: No visible infection signs
const THRESHOLD_STAGE1_SUBTLE: float = 0.6  # 0.3 - 0.6: Subtle signs visible
const THRESHOLD_STAGE2_MODERATE: float = 0.9 # 0.6 - 0.9: Multiple signs visible
const THRESHOLD_STAGE3_TURNING: float = 0.9  # > 0.9: Critical stage, will turn soon

const BASE_DAILY_PROGRESSION_RATE: float = 0.18 # Base daily increase for infected
const VARIANCE_DAILY_RATE: float = 0.08         # Random variation per strain

var signs_system: SignsSystem = null

func _ready() -> void:
	pass

## Bind SignsSystem reference for sign querying
func set_signs_system(system: SignsSystem) -> void:
	signs_system = system

## Initialize infection profile for a visitor object
func create_infection_profile(is_infected: bool, initial_progress: float = -1.0, strain_rate: float = -1.0) -> Dictionary:
	var profile: Dictionary = {}
	if is_infected:
		var init_p: float = initial_progress if initial_progress >= 0.0 else randf_range(0.1, 0.45)
		var rate: float = strain_rate if strain_rate > 0.0 else (BASE_DAILY_PROGRESSION_RATE + randf_range(-VARIANCE_DAILY_RATE, VARIANCE_DAILY_RATE))
		profile["is_infected"] = true
		profile["infection_progress"] = clampf(init_p, 0.0, 1.0)
		profile["daily_rate"] = rate
		profile["days_infected"] = 0
		profile["turned"] = init_p >= 1.0
		profile["suppressed_days"] = 0
	else:
		profile["is_infected"] = false
		profile["infection_progress"] = 0.0
		profile["daily_rate"] = 0.0
		profile["days_infected"] = 0
		profile["turned"] = false
		profile["suppressed_days"] = 0
	return profile

## Returns only the signs assigned to visitor that are visible at their CURRENT infection level.
## Threshold logic:
## - < 0.3: Returns empty array (signs hidden/latent)
## - 0.3 - 0.6: Returns subtle signs (severity_min_threshold <= infection_progress)
## - 0.6 - 0.9: Returns moderate/multiple signs
## - > 0.9: Returns all assigned signs
func get_visible_signs(visitor: Dictionary) -> Array:
	var visible_signs: Array = []
	var progress: float = visitor.get("infection_progress", 0.0)
	var assigned_sign_ids: Array = visitor.get("assigned_sign_ids", [])

	# If infection is below 0.3, infection signs remain invisible (except false-positive stress signs on humans)
	if progress < THRESHOLD_STAGE0_CLEAN and visitor.get("is_infected", false):
		return visible_signs

	for sign_id in assigned_sign_ids:
		var sign: Dictionary = {}
		if signs_system != null:
			sign = signs_system.get_sign(sign_id)
		
		if sign.is_empty():
			# Fallback mock check if signs_system reference not attached
			visible_signs.append({"id": sign_id, "visible": true})
			continue

		var threshold: float = sign.get("severity_min_threshold", 0.3)
		
		# Human false-positive signs or infected signs above threshold
		if not visitor.get("is_infected", false):
			if sign.get("ambiguity_level") == "high":
				visible_signs.append(sign)
		elif progress >= threshold:
			visible_signs.append(sign)

	return visible_signs

## Returns true if visitor infection progress crosses turning threshold (> 0.9) today or on next step
func will_turn_today(visitor: Dictionary) -> bool:
	if not visitor.get("is_infected", false) or visitor.get("turned", false):
		return false

	var current: float = visitor.get("infection_progress", 0.0)
	var rate: float = visitor.get("daily_rate", BASE_DAILY_PROGRESSION_RATE)
	var suppressed: int = visitor.get("suppressed_days", 0)

	if suppressed > 0:
		rate *= 0.25 # Medicine drastically slows progress

	var projected: float = current + rate
	return projected >= THRESHOLD_STAGE3_TURNING or current >= THRESHOLD_STAGE3_TURNING

## Advances infection time for a visitor by delta_days (e.g., 1.0 day or 0.125 for 3 hours).
## Returns updated visitor profile.
func advance_time(visitor: Dictionary, delta_days: float) -> Dictionary:
	if not visitor.get("is_infected", false) or visitor.get("turned", false):
		return visitor

	var old_p: float = visitor.get("infection_progress", 0.0)
	var rate: float = visitor.get("daily_rate", BASE_DAILY_PROGRESSION_RATE)
	var suppressed: int = visitor.get("suppressed_days", 0)

	if suppressed > 0:
		rate *= 0.25
		visitor["suppressed_days"] = max(0, suppressed - 1)

	var new_p: float = clampf(old_p + (rate * delta_days), 0.0, 1.0)
	visitor["infection_progress"] = new_p
	visitor["days_infected"] = visitor.get("days_infected", 0) + delta_days

	infection_advanced.emit(visitor, old_p, new_p)

	if new_p >= 1.0 and not visitor.get("turned", false):
		visitor["turned"] = true
		visitor_turned.emit(visitor)

	return visitor

## Advance infection by 1 full day for a survivor/visitor inside shelter
func advance_daily_infection(visitor: Dictionary) -> Dictionary:
	return advance_time(visitor, 1.0)

## Treat visitor/survivor with medicine to suppress or reduce infection progress
func suppress_infection(visitor: Dictionary, medicine_potency: float = 0.2) -> bool:
	if not visitor.get("is_infected", false):
		return false

	var current: float = visitor.get("infection_progress", 0.0)
	var reduced: float = clampf(current - medicine_potency, 0.05, 1.0) # Cannot fully cure, only reduce/delay
	var delta: float = current - reduced

	visitor["infection_progress"] = reduced
	visitor["suppressed_days"] = visitor.get("suppressed_days", 0) + 2 # 2 days of slowed progress

	infection_suppressed.emit(visitor, delta)
	return true

## Returns textual stage description based on infection progress float
func get_stage_description(progress: float) -> String:
	if progress < THRESHOLD_STAGE0_CLEAN:
		return "STAGE 0: Latent / Asymptomatic (< 30%)"
	elif progress < THRESHOLD_STAGE1_SUBTLE:
		return "STAGE 1: Early Symptoms (30% - 60%)"
	elif progress < THRESHOLD_STAGE2_MODERATE:
		return "STAGE 2: Advanced Viral Activity (60% - 90%)"
	else:
		return "STAGE 3: Critical Necrosis / Imminent Turning (> 90%)"

## Check if visitor is in critical turning risk
func is_critical(visitor: Dictionary) -> bool:
	return visitor.get("infection_progress", 0.0) >= THRESHOLD_STAGE3_TURNING
