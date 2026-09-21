# VisitorManager.gd
# Generates visitors per night, tracks visitor state, and manages inspection queue.
extends Node

enum Decision {
	LET_IN,
	TURN_AWAY,
	ELIMINATE
}

signal visitor_arrived(visitor_data: Dictionary)
signal visitor_processed(visitor_data: Dictionary, decision: Decision, is_correct: bool)
signal night_queue_completed

var visitor_database: Array = []
var night_queue: Array = []
var current_visitor: Dictionary = {}
var current_visitor_index: int = 0
var decision_history: Array = []
var admitted_visitors: Array = []
var rejected_visitors: Array = []
var night_completed: bool = false

# Guests fill rooms oldest-first; bedroom is never shared.
const ROOM_FILL_ORDER := ["hall", "kitchen", "office", "bathroom"]
const ROOM_CAPS := {"hall": 2, "kitchen": 2, "office": 2, "bathroom": 1}

const VISITORS_FILE_PATH: String = "res://assets/data/visitors.json"

# Indexed by the Decision enum: keys used by ConsequencesSystem.record_decision.
const DECISION_NAMES := ["LET_IN", "TURN_AWAY", "ELIMINATE"]

func _ready() -> void:
	load_visitor_database()

func load_visitor_database() -> void:
	if not FileAccess.file_exists(VISITORS_FILE_PATH):
		push_error("[VisitorManager] visitors.json not found at %s" % VISITORS_FILE_PATH)
		return
		
	var file := FileAccess.open(VISITORS_FILE_PATH, FileAccess.READ)
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(json_string) == OK and json.data is Dictionary:
		visitor_database = json.data.get("visitors", [])
		print("[VisitorManager] Loaded %d visitors from database." % visitor_database.size())
	else:
		push_error("[VisitorManager] Failed to parse visitors.json")

func prepare_night_queue(day_number: int) -> void:
	night_completed = false
	night_queue.clear()
	current_visitor_index = 0
	
	# Select visitors suitable for current day count (2 to 4 visitors per night)
	var count := clampi(day_number + 1, 2, 5)
	# Serve exactly the authored pool for this night: story.json scripts some
	# nights deliberately thin (night 1 is the Marcus-only tutorial), so we
	# never pad with visitors from other nights.
	var authored: Array = []
	for n in StoryManager.story_data.get("nights", []):
		if int(n.get("night_number", 0)) == day_number:
			authored = n.get("available_visitor_pool", [])
			break
	var pool: Array = []
	for v in visitor_database:
		if not authored.is_empty():
			# story.json owns the night: only its listed visitors appear.
			if str(v.get("id", "")) in authored:
				pool.append(v.duplicate(true))
			continue
		var nights: Array = v.get("nights_available", [])
		# JSON numbers parse as float; int day never matches float nights
		# with strict `in`, so compare as float (empty pool = silent no-show).
		if nights.is_empty() or float(day_number) in nights:
			pool.append(v.duplicate(true))
	pool.shuffle()
	
	for i in range(mini(count, pool.size())):
		var v_data: Dictionary = pool[i].duplicate(true)
		# Assign signs using SignsManager
		v_data["assigned_signs"] = SignsManager.get_signs_for_visitor(v_data)
		night_queue.append(v_data)
		
	print("[VisitorManager] Prepared night queue with %d visitors for Day %d" % [night_queue.size(), day_number])

func start_next_inspection() -> bool:
	if current_visitor_index < night_queue.size():
		current_visitor = night_queue[current_visitor_index]
		current_visitor_index += 1
		
		# Play knock pattern audio
		var knock_pattern: int = current_visitor.get("knock_pattern", 0)
		AudioManager.play_knock_pattern(knock_pattern)
		
		visitor_arrived.emit(current_visitor)
		return true
	else:
		current_visitor = {}
		night_queue_completed.emit()
		return false

func process_decision(decision: Decision) -> Dictionary:
	if current_visitor.is_empty():
		return {}

	var is_infected: bool = current_visitor.get("is_actually_infected", current_visitor.get("is_infected", false))
	var is_correct: bool = false
	
	match decision:
		Decision.LET_IN:
			is_correct = not is_infected
			if is_infected:
				FlagsManager.increment_flag("infected_let_in")
				GameManager.corruption_value += 20
				GameManager.trust_value -= 10
			else:
				FlagsManager.increment_flag("humans_let_in")
				GameManager.trust_value += 15
				ResourceSystem.consume_food(1)
				
		Decision.TURN_AWAY:
			is_correct = is_infected
			if is_infected:
				FlagsManager.increment_flag("infected_turned_away")
				GameManager.trust_value += 5
			else:
				FlagsManager.increment_flag("humans_turned_away")
				GameManager.trust_value -= 10
				
		Decision.ELIMINATE:
			is_correct = is_infected
			if is_infected:
				FlagsManager.increment_flag("infected_eliminated")
				GameManager.trust_value += 10
				ResourceSystem.consume_ammo(1)
			else:
				FlagsManager.increment_flag("humans_eliminated")
				GameManager.trust_value -= 25
				GameManager.corruption_value += 10
				ResourceSystem.consume_ammo(1)

	if is_correct:
		GameManager.correct_decisions_today += 1
	GameManager.visitors_inspected_today += 1
	
	match decision:
		Decision.LET_IN:
			_admit(current_visitor)
		Decision.TURN_AWAY:
			rejected_visitors.append(current_visitor.duplicate(true))
	
	var log_entry := {
		"day": GameManager.current_day,
		"visitor_id": current_visitor.get("id", "unknown"),
		"visitor_name": current_visitor.get("name", "Anonymous"),
		"is_infected": is_infected,
		"decision": decision,
		"is_correct": is_correct,
		"timestamp": Time.get_time_string_from_system()
	}
	
	decision_history.append(log_entry)
	visitor_processed.emit(current_visitor, decision, is_correct)
	
	# Feed the delayed-consequence engine: it queues the "turns days later"
	# payoffs that start_day_phase fires via ConsequenceSystem.process_day.
	# Immediate stats are already applied above, so the engine gets a scratch
	# shelter state and only its queued consequences reach GameManager.
	var shelter := {
		"trust": float(GameManager.trust_value),
		"corruption": float(GameManager.corruption_value)
	}
	ConsequenceSystem.record_decision(
		current_visitor, DECISION_NAMES[decision], GameManager.current_day, shelter)
	
	return log_entry

func reset_history() -> void:
	decision_history.clear()
	night_queue.clear()
	current_visitor = {}
	current_visitor_index = 0
	admitted_visitors.clear()
	rejected_visitors.clear()
	night_completed = false

## Admitted humans who have not turned (confirmed infected = they'll turn).
func get_survivors_inside() -> Array:
	var out: Array = []
	for g in admitted_visitors:
		if not bool(g.get("confirmed_infected", false)):
			out.append(g.duplicate(true))
	return out

## Admitted guests sit in rooms for the day phase (2 per room max).
func _admit(visitor: Dictionary) -> void:
	# If the shelter is full, kick the oldest guest until a room frees up.
	while _first_free_room() == "" and not admitted_visitors.is_empty():
		kick_guest(str(admitted_visitors[0].get("id")))
	var room := _first_free_room()
	if room == "":
		return  # no room and no one to kick — visitor waits outside
	var v := visitor.duplicate(true)
	v["room"] = room
	v["admitted_day"] = GameManager.current_day
	v["revealed_signs_count"] = 0
	v["talk_step"] = 0
	v["confirmed_infected"] = false
	admitted_visitors.append(v)

func _first_free_room() -> String:
	var used := {}
	for g in admitted_visitors:
		var r := str(g.get("room", ""))
		used[r] = int(used.get(r, 0)) + 1
	for r in ROOM_FILL_ORDER:
		if int(used.get(r, 0)) < int(ROOM_CAPS.get(r, 2)):
			return r
	return ""  # full — _admit kicks the oldest guest until a bed frees up

## Removes an admitted guest back outside; trust takes the hit.
func kick_guest(guest_id: String) -> Dictionary:
	for i in admitted_visitors.size():
		if str(admitted_visitors[i].get("id", "")) == guest_id:
			var g: Dictionary = admitted_visitors.pop_at(i)
			rejected_visitors.append(g)
			FlagsManager.increment_flag("humans_turned_away")
			GameManager.trust_value -= 10
			return g
	return {}

## Shooting a turned guest inside the house: it leaves no corpse outside and
## costs no trust — the community saw a Visitor fall.
func eliminate_guest(guest_id: String) -> Dictionary:
	for i in admitted_visitors.size():
		if str(admitted_visitors[i].get("id", "")) == guest_id:
			var g: Dictionary = admitted_visitors.pop_at(i)
			FlagsManager.increment_flag("infected_eliminated")
			return g
	return {}

func get_save_data() -> Dictionary:
	return {
		"decision_history": decision_history,
		"current_visitor_index": current_visitor_index,
		"admitted_visitors": admitted_visitors
	}

func load_save_data(data: Dictionary) -> void:
	decision_history = data.get("decision_history", [])
	current_visitor_index = data.get("current_visitor_index", 0)
	admitted_visitors = data.get("admitted_visitors", [])
