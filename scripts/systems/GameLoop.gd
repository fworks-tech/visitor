class_name GameLoop
extends Node

## GameLoop
## Central game controller and state machine for 'Visitor'.
## Manages transition between Night (Visitor arrival, inspection, decision, consequence)
## and Day (Resource management, survivor interactions, fortification, scavenging).

enum State {
	NIGHT_START,
	VISITOR_ARRIVAL,
	INSPECTION,
	DECISION,
	CONSEQUENCE,
	NIGHT_END,
	DAY_START,
	DAY_MANAGEMENT,
	DAY_END
}

signal state_changed(old_state: State, new_state: State)
signal visitor_arrived(visitor: Dictionary, current_index: int, total_visitors: int)
signal inspection_updated(visitor: Dictionary, ap_remaining: int)
signal decision_resolved(visitor: Dictionary, decision: String, result_summary: Dictionary)
signal day_started(day_number: int, daily_logs: Array)
signal game_over(reason: String)

@export var signs_system: SignsSystem
@export var infection_system: InfectionSystem
@export var consequences_system: ConsequencesSystem
@export var resource_manager: ResourceManager

var current_state: State = State.NIGHT_START
var current_day: int = 1

# Shelter Core Metrics
var shelter_state: Dictionary = {
	"trust": 70.0,
	"morale": 70.0,
	"corruption": 0.0,
	"security": 80.0
}

# Survivors residing inside shelter
var survivors_inside: Array = []

# Visitor Queue for current night
var night_visitors: Array = []
var current_visitor_index: int = -1
var current_visitor: Dictionary = {}
var current_ap: int = 4
var max_ap_per_visitor: int = 4

# Sample pool of names for generator
const SURVIVOR_NAMES: Array = [
	"Marcus Vance", "Elena Rostova", "Dr. Aris Thorne", "Sarah Miller",
	"David Chen", "Father Thomas", "Maya Lin", "Officer Rodriguez",
	"Hanna Becker", "Samuel Oak", "Chloe Price", "Viktor Krum"
]

func _ready() -> void:
	_initialize_subsystems()

## Ensure subsystem instances exist
func _initialize_subsystems() -> void:
	if signs_system == null:
		signs_system = SignsSystem.new()
		add_child(signs_system)

	if infection_system == null:
		infection_system = InfectionSystem.new()
		infection_system.set_signs_system(signs_system)
		add_child(infection_system)

	if consequences_system == null:
		consequences_system = ConsequencesSystem.new()
		add_child(consequences_system)

	if resource_manager == null:
		resource_manager = ResourceManager.new()
		add_child(resource_manager)

	# Initial starter survivors inside shelter
	if survivors_inside.is_empty():
		survivors_inside = [
			{"id": "s_01", "name": "Marcus Vance", "is_infected": false, "health": 100.0, "role": "Mechanic"},
			{"id": "s_02", "name": "Elena Rostova", "is_infected": false, "health": 90.0, "role": "Medic"}
		]

## Start game loop from Day 1 Night 1
func start_game() -> void:
	current_day = 1
	shelter_state = {"trust": 70.0, "morale": 70.0, "corruption": 0.0, "security": 80.0}
	change_state(State.NIGHT_START)

## Transition state machine
func change_state(new_state: State) -> void:
	var old_state: State = current_state
	current_state = new_state
	state_changed.emit(old_state, new_state)

	match current_state:
		State.NIGHT_START:
			_process_night_start()
		State.VISITOR_ARRIVAL:
			_process_visitor_arrival()
		State.INSPECTION:
			_process_inspection()
		State.DECISION:
			pass # Waiting for player action
		State.CONSEQUENCE:
			_process_consequence()
		State.NIGHT_END:
			_process_night_end()
		State.DAY_START:
			_process_day_start()
		State.DAY_MANAGEMENT:
			pass # Waiting for player day actions
		State.DAY_END:
			_process_day_end()

## NIGHT_START: Generate 1-3 visitors based on day difficulty scaling
func _process_night_start() -> void:
	night_visitors.clear()
	current_visitor_index = -1

	# Difficulty scaling: visitor count increases over days
	var visitor_count: int = 1
	if current_day >= 6:
		visitor_count = randi_range(2, 4)
	elif current_day >= 3:
		visitor_count = randi_range(2, 3)
	else:
		visitor_count = randi_range(1, 2)

	# Infection chance scales with days
	var infection_prob: float = clampf(0.35 + (current_day * 0.05), 0.35, 0.75)
	var ambiguity_mod: float = clampf(0.3 + (current_day * 0.08), 0.3, 0.85)

	for i in range(visitor_count):
		var vis: Dictionary = _generate_visitor(infection_prob, ambiguity_mod)
		night_visitors.append(vis)

	print("GameLoop: Day %d Night Start. %d visitors queued." % [current_day, night_visitors.size()])
	change_state(State.VISITOR_ARRIVAL)

## VISITOR_ARRIVAL: Load next visitor from queue
func _process_visitor_arrival() -> void:
	current_visitor_index += 1

	if current_visitor_index >= night_visitors.size():
		change_state(State.NIGHT_END)
		return

	current_visitor = night_visitors[current_visitor_index]
	current_ap = max_ap_per_visitor

	visitor_arrived.emit(current_visitor, current_visitor_index + 1, night_visitors.size())
	change_state(State.INSPECTION)

## INSPECTION: Player spends AP to inspect current visitor
func _process_inspection() -> void:
	inspection_updated.emit(current_visitor, current_ap)

## Perform inspection on current visitor
func inspect_current_visitor_sign(sign_id: String) -> Dictionary:
	if current_state != State.INSPECTION:
		return {"success": false, "reason": "Not in inspection phase"}

	var result: Dictionary = signs_system.inspect_sign(current_visitor, sign_id, current_ap)
	if result.get("success", false):
		current_ap = result.get("ap_remaining", current_ap)
		inspection_updated.emit(current_visitor, current_ap)

	return result

## Make decision on current visitor (LET_IN, TURN_AWAY, ELIMINATE)
func make_visitor_decision(decision: String) -> Dictionary:
	if current_state != State.INSPECTION and current_state != State.DECISION:
		return {"success": false, "reason": "Not in decision phase"}

	change_state(State.DECISION)

	# Check ammo cost for ELIMINATE
	if decision == ConsequencesSystem.DECISION_ELIMINATE:
		if not resource_manager.use_ammo(1):
			return {"success": false, "reason": "Out of ammo! Cannot execute eliminate decision."}

	# Record decision in ConsequencesSystem
	var entry: Dictionary = consequences_system.record_decision(
		current_visitor,
		decision,
		current_day,
		shelter_state
	)

	# Handle direct shelter entry if LET_IN
	if decision == ConsequencesSystem.DECISION_LET_IN:
		var new_survivor: Dictionary = {
			"id": current_visitor.get("id"),
			"name": current_visitor.get("name"),
			"is_infected": current_visitor.get("is_infected", false),
			"infection_progress": current_visitor.get("infection_progress", 0.0),
			"daily_rate": current_visitor.get("daily_rate", 0.15),
			"health": 100.0,
			"role": "Survivor"
		}
		survivors_inside.append(new_survivor)

	decision_resolved.emit(current_visitor, decision, entry)
	change_state(State.CONSEQUENCE)
	return {"success": true, "decision": decision, "entry": entry}

## CONSEQUENCE: Step to next visitor or night end
func _process_consequence() -> void:
	if current_visitor_index + 1 < night_visitors.size():
		change_state(State.VISITOR_ARRIVAL)
	else:
		change_state(State.NIGHT_END)

## NIGHT_END: Transition from night to day
func _process_night_end() -> void:
	change_state(State.DAY_START)

## DAY_START: Process daily consequences, resource consumption, infection progress
func _process_day_start() -> void:
	# 1. Advance daily infection for infected survivors inside shelter
	var survivors_to_remove: Array = []
	for survivor in survivors_inside:
		if survivor.get("is_infected", false):
			infection_system.advance_daily_infection(survivor)
			if infection_system.will_turn_today(survivor) or survivor.get("turned", false):
				# Crisis: Survivor turned inside shelter during day!
				shelter_state["trust"] = clampf(shelter_state["trust"] - 20.0, 0.0, 100.0)
				shelter_state["morale"] = clampf(shelter_state["morale"] - 25.0, 0.0, 100.0)

	# 2. Consume food and water for all survivors
	var resource_report: Dictionary = resource_manager.consume_daily_resources(survivors_inside.size())

	# Penalties if food/water shortages exist
	if resource_report.get("has_shortage", false):
		shelter_state["morale"] = clampf(shelter_state["morale"] - 15.0, 0.0, 100.0)

	# 3. Process queued consequences due today
	var daily_logs: Array = consequences_system.process_day(current_day, shelter_state, survivors_inside)

	# Check Game Over conditions
	if shelter_state["trust"] <= 0.0:
		game_over.emit("COMMUNITY MUTINY: Trust fell to zero. Survivors exiled you.")
		return
	elif shelter_state["morale"] <= 0.0:
		game_over.emit("DESPAIR: Morale collapsed completely. The shelter disintegrated.")
		return
	elif shelter_state["security"] <= 0.0:
		game_over.emit("BREACH: Barricades failed. Zombies overran the gate.")
		return

	day_started.emit(current_day, daily_logs)
	change_state(State.DAY_MANAGEMENT)

## Day Action: Send survivor on scavenging run
func perform_scavenge_run(survivor_index: int, danger_level: float) -> Dictionary:
	if current_state != State.DAY_MANAGEMENT:
		return {"success": false, "reason": "Not in day management phase"}

	if survivor_index < 0 or survivor_index >= survivors_inside.size():
		return {"success": false, "reason": "Invalid survivor index"}

	var survivor: Dictionary = survivors_inside[survivor_index]
	var result: Dictionary = resource_manager.scavenge(danger_level, survivor)

	if result["survivor_status"]["died"]:
		survivors_inside.remove_at(survivor_index)

	return {"success": true, "result": result}

## Day Action: Use medicine on survivor
func use_medicine_on_survivor(survivor_index: int) -> Dictionary:
	if survivor_index < 0 or survivor_index >= survivors_inside.size():
		return {"success": false, "reason": "Invalid survivor index"}

	var survivor: Dictionary = survivors_inside[survivor_index]
	return resource_manager.use_medicine(survivor)

## Day Action: Fortify defenses using fuel/materials
func fortify_defenses(amount: float = 15.0) -> Dictionary:
	if not resource_manager.use_fuel(2.0):
		return {"success": false, "reason": "Not enough fuel for fortification work."}

	shelter_state["security"] = minf(100.0, shelter_state["security"] + amount)
	return {"success": true, "new_security": shelter_state["security"]}

## End Day Phase and advance to next Night
func end_day() -> void:
	if current_state != State.DAY_MANAGEMENT:
		return

	change_state(State.DAY_END)

func _process_day_end() -> void:
	current_day += 1
	change_state(State.NIGHT_START)

## Helper to procedurally generate a visitor
func _generate_visitor(infection_prob: float, ambiguity_mod: float) -> Dictionary:
	var v_name: String = SURVIVOR_NAMES[randi() % SURVIVOR_NAMES.size()] + " #" + str(randi() % 90 + 10)
	var is_infected: bool = randf() < infection_prob
	var init_p: float = randf_range(0.2, 0.85) if is_infected else 0.0

	var visitor: Dictionary = {
		"id": "v_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000),
		"name": v_name,
		"is_infected": is_infected,
		"infection_progress": init_p,
		"daily_rate": randf_range(0.12, 0.25) if is_infected else 0.0,
		"assigned_sign_ids": [],
		"revealed_sign_ids": [],
		"backstory": "Seeking refuge after fleeing Riverside perimeter."
	}

	# Assign physical and behavioral signs via SignsSystem
	if signs_system != null:
		signs_system.assign_signs_to_visitor(visitor, init_p, ambiguity_mod)

	return visitor

## Get full snapshot summary of game state
func get_game_summary() -> Dictionary:
	return {
		"current_day": current_day,
		"state": State.keys()[current_state],
		"shelter_state": shelter_state.duplicate(),
		"survivor_count": survivors_inside.size(),
		"resources": resource_manager.get_resource_status() if resource_manager else {},
		"queued_consequences": consequences_system.get_queued_consequences().size() if consequences_system else 0
	}
