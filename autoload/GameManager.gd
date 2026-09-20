# GameManager.gd
# Core game state machine for 'Visitor' (Dead Hours: Visitor)
# Manages overall flow, day/night cycles, trust, and corruption metrics.
extends Node

enum GameState {
	SPLASH,
	MENU,
	NIGHT,       # Night phase start / knocks
	INSPECTION,  # Core visitor inspection at peep-hole
	DAY,         # Morning resource management & survivor dialogue
	PAUSED,
	GAME_OVER
}

signal state_changed(new_state: GameState, old_state: GameState)
signal day_changed(new_day: int)
signal trust_changed(new_trust: int)
signal corruption_changed(new_corruption: int)
signal game_over_triggered(reason: String, outcome: String)

var current_state: GameState = GameState.SPLASH
var previous_state: GameState = GameState.SPLASH

var current_day: int = 1
var max_days: int = 7

# Core meter values (0 to 100)
var trust_value: int = 60:
	set(val):
		trust_value = clampi(val, 0, 100)
		trust_changed.emit(trust_value)
		_check_game_over_conditions()

var corruption_value: int = 10:
	set(val):
		corruption_value = clampi(val, 0, 100)
		corruption_changed.emit(corruption_value)
		_check_game_over_conditions()

var morale_value: int = 50:
	set(val):
		morale_value = clampi(val, 0, 100)

var security_value: int = 50:
	set(val):
		security_value = clampi(val, 0, 100)

# Night inspection stats
var visitors_inspected_today: int = 0
var correct_decisions_today: int = 0

# Flashlight battery: drains while on (~5 min of light), R swaps a spare.
const BATTERY_DRAIN := 0.3
var flashlight_battery: float = 100.0
var batteries: int = 1

func drain_battery(delta: float) -> void:
	if flashlight_battery > 0.0:
		flashlight_battery = maxf(0.0, flashlight_battery - BATTERY_DRAIN * delta)

## Swap in a spare battery. Returns false with no spares or a full cell.
func replace_battery() -> bool:
	if batteries <= 0 or flashlight_battery >= 100.0:
		return false
	batteries -= 1
	flashlight_battery = 100.0
	return true

# Day-phase energy (ported from the reference design): examinations and
# house actions cost energy; sleep is only allowed once it is spent.
const HOUSE_SCENE_PATH := "res://scenes/house/HouseScene.tscn"
var energy_max: int = 2
var energy_left: int = 0
var unlocked_tools_today: Array = []
var tv_watched_today: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	print("[GameManager] Initialized.")
	# Headless test harnesses: `godot --headless --path . -- --door-test`
	for flag in ["--door-test", "--house-test"]:
		if flag in OS.get_cmdline_args() or flag in OS.get_cmdline_user_args():
			var t: Node = load("res://tests/DoorFlowTest.gd" if flag == "--door-test" else "res://tests/HouseWalkTest.gd").new()
			get_tree().root.add_child.call_deferred(t)

func change_state(new_state: GameState) -> void:
	if current_state == new_state:
		return
	
	previous_state = current_state
	current_state = new_state
	
	if current_state == GameState.PAUSED:
		get_tree().paused = true
	elif previous_state == GameState.PAUSED:
		get_tree().paused = false
		
	state_changed.emit(current_state, previous_state)
	print("[GameManager] State changed from %s to %s" % [_state_to_string(previous_state), _state_to_string(current_state)])

func start_new_game() -> void:
	current_day = 1
	trust_value = 60
	corruption_value = 10
	morale_value = 50
	security_value = 50
	visitors_inspected_today = 0
	correct_decisions_today = 0
	flashlight_battery = 100.0
	batteries = 1

	FlagsManager.reset_flags()
	VisitorManager.reset_history()

	# Start Night 1 inspection phase
	start_night_phase()

func start_night_phase() -> void:
	change_state(GameState.NIGHT)
	visitors_inspected_today = 0
	correct_decisions_today = 0
	VisitorManager.prepare_night_queue(current_day)
	
	# Trigger story node for night if present
	StoryManager.trigger_phase_event(current_day, "night")
	
	# Nights now open in the house (wake in bed); the front door leads to inspection
	SceneManager.change_scene(HOUSE_SCENE_PATH)

func start_day_phase() -> void:
	change_state(GameState.DAY)

	# Evaluate overnight consequences from admitted visitors. The autoload
	# now points at the engine directly (bridge collapsed — see ADR-001).
	var shelter := {
		"trust": float(trust_value),
		"corruption": float(corruption_value),
		"morale": float(morale_value),
		"security": float(security_value)
	}
	ConsequenceSystem.process_day(current_day, shelter)
	trust_value = int(shelter.get("trust", trust_value))
	corruption_value = int(shelter.get("corruption", corruption_value))
	morale_value = int(shelter.get("morale", morale_value))
	security_value = int(shelter.get("security", security_value))
	StoryManager.trigger_phase_event(current_day, "day")
	
	# Daily energy budget grows 2 -> 4 over the week; TV gates the exam tools
	energy_max = clampi(2 + int((current_day - 1) / 2.0), 2, 4)
	energy_left = energy_max
	tv_watched_today = false
	unlocked_tools_today = []
	
	SaveManager.save_game()  # checkpoint: sleep is the only save point
	SceneManager.change_scene(HOUSE_SCENE_PATH)

## Sleep is the only night/day transition, triggered from the bedroom bed.
func go_sleep() -> void:
	match current_state:
		GameState.DAY:
			advance_to_next_day()
		GameState.NIGHT:
			start_day_phase()
		_:
			pass

## Morning broadcast: reveals the night's briefing summary and unlocks the
## examination tools for the day. Returns {} if already watched.
func watch_tv() -> Dictionary:
	if tv_watched_today:
		return {}
	tv_watched_today = true
	var nights: Array = StoryManager.story_data.get("nights", [])
	for n in nights:
		if int(n.get("night_number", 0)) == current_day:
			unlocked_tools_today = n.get("unlocked_tools", [])
			break
	return {"tools": unlocked_tools_today.duplicate()}

func spend_energy(amount: int = 1) -> bool:
	if energy_left < amount:
		return false
	energy_left -= amount
	return true

func advance_to_next_day() -> void:
	if current_day >= max_days:
		trigger_ending(evaluate_endings(), "You survived all 7 days of the Visitor crisis.")
		return

	current_day += 1
	day_changed.emit(current_day)
	start_night_phase()

## Evaluation order: terminal states first, good endings last.
## Gatekeeper requires zero mistakes, so it must be checked after Pariah/Cure.
const ENDING_PRIORITY := [
	"ending_06_infected", "ending_03_executioner", "ending_07_exile",
	"ending_02_pariah", "ending_04_hermit", "ending_05_cure", "ending_01_gatekeeper",
]

func _ending_stats() -> Dictionary:
	var stats := {
		"trust": trust_value,
		"corruption": corruption_value,
		"infected_admitted": int(FlagsManager.get_flag("infected_let_in", 0)),
		"humans_killed": int(FlagsManager.get_flag("humans_eliminated", 0)),
		"visitors_turned_away": int(FlagsManager.get_flag("humans_turned_away", 0)),
		"player_infected": bool(FlagsManager.get_flag("player_infected", false)),
		"survivors_alive": VisitorManager.get_survivors_inside().size(),
		"admitted_dr_thorne": bool(FlagsManager.get_flag("admitted_dr_thorne", false)),
		"admitted_cure_subject": bool(FlagsManager.get_flag("admitted_cure_subject", false)),
	}
	return stats

## Checks every ending's conditions from story.json in ENDING_PRIORITY order.
## Returns the story.json key ("ending_01_gatekeeper") or a legacy fallback id.
func evaluate_endings() -> String:
	var endings: Dictionary = StoryManager.story_data.get("endings", {})
	if endings.is_empty():
		return "ending_01_gatekeeper"
	var stats := _ending_stats()
	for key in ENDING_PRIORITY:
		if not endings.has(key):
			continue
		if _ending_conditions_met(endings[key].get("conditions", {}), stats):
			return key
	return "ending_02_pariah"

func _ending_conditions_met(conditions: Dictionary, stats: Dictionary) -> bool:
	for cond in conditions:
		var target = conditions[cond]
		match cond:
			"corruption_max":
				if int(stats.get("corruption", 0)) > int(target): return false
			"max_trust":
				if int(stats.get("trust", 0)) > int(target): return false
			"max_humans_killed":
				if int(stats.get("humans_killed", 0)) > int(target): return false
			_:
				if str(cond).begins_with("min_"):
					if int(stats.get(str(cond).trim_prefix("min_"), 0)) < int(target): return false
				elif target is bool:
					if bool(stats.get(str(cond), false)) != bool(target): return false
				else:
					if stats.get(str(cond)) != target: return false
	return true

func trigger_ending(ending_id: String, reason: String) -> void:
	change_state(GameState.GAME_OVER)
	FlagsManager.set_flag("ending_id", ending_id)
	FlagsManager.set_flag("ending_reason", reason)
	game_over_triggered.emit(reason, ending_id)
	SceneManager.change_scene("res://scenes/ui/GameOver.tscn")

## Story data ids for endings triggered before the endings block existed.
const LEGACY_ENDINGS := {
	"rebellion": "ending_07_exile",
	"infected_overrun": "ending_02_pariah",
	"survived_outbreak": "ending_01_gatekeeper",
	"pariah": "ending_02_pariah",
}

## Display info for the GameOver screen, resolved from story.json endings.
func get_ending_display() -> Dictionary:
	var endings: Dictionary = StoryManager.story_data.get("endings", {})
	var eid := str(FlagsManager.get_flag("ending_id", ""))
	var key := ""
	if endings.has(eid):
		key = eid
	else:
		for k in endings:
			if str(endings[k].get("id", "")) == eid:
				key = k
				break
		if key == "" and LEGACY_ENDINGS.has(eid):
			key = str(LEGACY_ENDINGS[eid])
	if key != "" and endings.has(key):
		var e: Dictionary = endings[key]
		return {
			"title": str(e.get("title", "THE NIGHT ENDS")).to_upper(),
			"text": str(e.get("summary", "")) + "\n\n" + str(e.get("epilogue", "")),
		}
	return {
		"title": "THE NIGHT ENDS",
		"text": str(FlagsManager.get_flag("ending_reason", "")),
	}

func _check_game_over_conditions() -> void:
	if current_state == GameState.SPLASH or current_state == GameState.MENU or current_state == GameState.GAME_OVER:
		return
		
	if trust_value <= 0:
		trigger_ending(evaluate_endings(), "Trust collapsed. The surviving sanctuary members ousted you into the dark.")
	elif corruption_value >= 100:
		trigger_ending(evaluate_endings(), "Infection reached critical mass inside the compound. The sanctuary was overrun from within.")

func _state_to_string(state: GameState) -> String:
	match state:
		GameState.SPLASH: return "SPLASH"
		GameState.MENU: return "MENU"
		GameState.NIGHT: return "NIGHT"
		GameState.INSPECTION: return "INSPECTION"
		GameState.DAY: return "DAY"
		GameState.PAUSED: return "PAUSED"
		GameState.GAME_OVER: return "GAME_OVER"
		_: return "UNKNOWN"
