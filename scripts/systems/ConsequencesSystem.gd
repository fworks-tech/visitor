class_name ConsequencesSystem
extends Node

## ConsequencesSystem
## Tracks player decisions (LET_IN, TURN_AWAY, ELIMINATE), generates delayed consequence events,
## queues future consequences with delay timers in days, and updates shelter stats (trust, morale, corruption).

signal decision_recorded(decision_entry: Dictionary)
signal consequence_queued(consequence: Dictionary)
signal consequence_fired(consequence: Dictionary, event_log: String)
signal shelter_stats_changed(new_stats: Dictionary)

# Decision Constants
const DECISION_LET_IN: String = "LET_IN"
const DECISION_TURN_AWAY: String = "TURN_AWAY"
const DECISION_ELIMINATE: String = "ELIMINATE"

# Consequence Types
const TYPE_INFECTED_LET_IN: String = "infected_let_in"
const TYPE_HUMAN_TURNED_AWAY: String = "human_turned_away"
const TYPE_HUMAN_ELIMINATED: String = "human_eliminated"
const TYPE_CORRECT_CALL: String = "correct_call"
const TYPE_REVENGE_ATTACK: String = "revenge_attack"
const TYPE_CHAIN_INFECTION: String = "chain_infection"
const TYPE_GUILT_EVENT: String = "guilt_event"

var decision_history: Array = []
var consequence_queue: Array = []
var processed_consequences: Array = []

func _ready() -> void:
	pass

## Record a player's gate decision regarding a visitor and generate immediate + delayed consequences
func record_decision(visitor: Dictionary, decision: String, current_day: int, shelter_state: Dictionary) -> Dictionary:
	var visitor_id: String = visitor.get("id", "visitor_unknown")
	var visitor_name: String = visitor.get("name", "Unknown Visitor")
	# visitors.json carries is_actually_infected; is_infected is the legacy spelling.
	var is_infected: bool = visitor.get("is_actually_infected", visitor.get("is_infected", false))
	var infection_progress: float = visitor.get("infection_progress", 0.0)

	var entry: Dictionary = {
		"visitor_id": visitor_id,
		"visitor_name": visitor_name,
		"decision": decision,
		"is_infected": is_infected,
		"infection_progress": infection_progress,
		"day_made": current_day,
		"timestamp": Time.get_unix_time_from_system()
	}

	decision_history.append(entry)
	decision_recorded.emit(entry)

	# Evaluate decision outcomes & queue delayed consequences
	match decision:
		DECISION_LET_IN:
			if is_infected:
				# INFECTED LET IN: Delayed crisis when infection reaches turning point
				var delay: int = randi_range(1, 3) # 1 to 3 days delay based on progress
				if infection_progress >= 0.8:
					delay = 1
				queue_consequence(TYPE_INFECTED_LET_IN, current_day + delay, visitor, {
					"trust_change": -25,
					"morale_change": -30,
					"infection_progress": infection_progress,
					"description": "Infected visitor '%s' let into shelter turns and attacks survivors." % visitor_name
				})
			else:
				# CORRECT CALL: Human saved! Immediate + delayed bonus
				apply_stat_changes(shelter_state, {"trust": 10, "morale": 10})
				queue_consequence(TYPE_CORRECT_CALL, current_day + 1, visitor, {
					"trust_change": 5,
					"morale_change": 5,
					"description": "Survivor '%s' integrates into the community, raising morale." % visitor_name
				})

		DECISION_TURN_AWAY:
			if is_infected:
				# CORRECT CALL: Infected turned away, shelter kept safe
				apply_stat_changes(shelter_state, {"trust": 5, "morale": 5})
				queue_consequence(TYPE_CORRECT_CALL, current_day + 1, visitor, {
					"trust_change": 5,
					"morale_change": 0,
					"description": "Turning away infected visitor '%s' proved to be the right decision." % visitor_name
				})
			else:
				# HUMAN TURNED AWAY: Guilt + potential revenge or return as infected
				apply_stat_changes(shelter_state, {"morale": -10, "trust": -5})
				var delay: int = randi_range(2, 4)
				var roll: float = randf()
				if roll < 0.5:
					# They return infected days later as a visitor
					queue_consequence(TYPE_HUMAN_TURNED_AWAY, current_day + delay, visitor, {
						"morale_change": -15,
						"description": "'%s', who was turned away on Day %d, was found infected outside." % [visitor_name, current_day]
					})
				else:
					# Their group attacks gate out of revenge
					queue_consequence(TYPE_REVENGE_ATTACK, current_day + delay, visitor, {
						"trust_change": -10,
						"morale_change": -10,
						"security_change": -15,
						"description": "Angry relatives of turned-away human '%s' attempt a midnight raid." % visitor_name
					})

		DECISION_ELIMINATE:
			if is_infected:
				# INFECTED ELIMINATED: Necessary violence
				apply_stat_changes(shelter_state, {"security": 10, "trust": 5})
				queue_consequence(TYPE_CORRECT_CALL, current_day + 1, visitor, {
					"trust_change": 5,
					"description": "Eliminating infected threat '%s' reinforced shelter defense." % visitor_name
				})
			else:
				# HUMAN ELIMINATED: Murder of innocent human! High corruption + murder discovery
				apply_stat_changes(shelter_state, {"corruption": 20, "morale": -20, "trust": -15})
				var delay: int = randi_range(1, 3)
				queue_consequence(TYPE_HUMAN_ELIMINATED, current_day + delay, visitor, {
					"corruption_change": 10,
					"trust_change": -25,
					"morale_change": -20,
					"description": "Survivors discover that '%s' was uninfected before being executed." % visitor_name
				})

	return entry

## Queue a future consequence to trigger on a specified trigger_day
func queue_consequence(type: String, trigger_day: int, visitor: Dictionary, payload: Dictionary = {}) -> Dictionary:
	var consequence: Dictionary = {
		"id": "cq_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 1000),
		"type": type,
		"trigger_day": trigger_day,
		"visitor_id": visitor.get("id", "unknown"),
		"visitor_name": visitor.get("name", "Unknown"),
		"payload": payload,
		"status": "pending"
	}

	consequence_queue.append(consequence)
	consequence_queued.emit(consequence)
	return consequence

## Process all consequences due on current_day. Updates shelter_state and returns event log entries.
func process_day(current_day: int, shelter_state: Dictionary) -> Array:
	var daily_event_logs: Array = []
	var remaining_queue: Array = []

	for c in consequence_queue:
		if c.get("trigger_day", 0) <= current_day and c.get("status") == "pending":
			c["status"] = "fired"
			c["fired_on_day"] = current_day

			var payload: Dictionary = c.get("payload", {})
			var visitor_name: String = c.get("visitor_name", "Unknown")
			var c_type: String = c.get("type", "")
			var log_msg: String = ""

			# A guest who already left the house cannot hurt anyone inside —
			# the community reads the call as justified, so penalties are halved.
			var guest: Dictionary = {}
			if c_type == TYPE_INFECTED_LET_IN:
				guest = _guest_by_id(c.get("visitor_id", ""))
				if guest.is_empty():
					for key in payload.keys():
						if str(key).ends_with("_change"):
							payload[key] = int(payload[key] / 2.0)

			# Apply payload stat modifications
			var stat_changes: Dictionary = {}
			if payload.has("trust_change"): stat_changes["trust"] = payload["trust_change"]
			if payload.has("morale_change"): stat_changes["morale"] = payload["morale_change"]
			if payload.has("corruption_change"): stat_changes["corruption"] = payload["corruption_change"]
			if payload.has("security_change"): stat_changes["security"] = payload["security_change"]
			apply_stat_changes(shelter_state, stat_changes)

			# Construct detailed narrative log message
			match c_type:
				TYPE_INFECTED_LET_IN:
					if guest.is_empty():
						log_msg = "[NEWS] Day %d: '%s', cast out before, turned on the road. Your call stands." % [current_day, visitor_name]
					else:
						guest["turned"] = true
						log_msg = "[TURNED] Day %d: '%s' you let in has turned inside the shelter. It walks among them now." % [current_day, visitor_name]

				TYPE_HUMAN_TURNED_AWAY:
					log_msg = "[GUILT] Day %d: News arrives that turned-away human '%s' died outside. Morale dropped by 15." % [current_day, visitor_name]

				TYPE_HUMAN_ELIMINATED:
					log_msg = "[MURDER DISCOVERED] Day %d: Whispers spread among survivors that '%s' was innocent. Trust dropped by 25, Corruption +10." % [current_day, visitor_name]

				TYPE_REVENGE_ATTACK:
					log_msg = "[ATTACK] Day %d: Restless scavengers allied with '%s' attacked the outer barricade. Security damaged." % [current_day, visitor_name]

				TYPE_CORRECT_CALL:
					log_msg = "[STABILITY] Day %d: %s" % [current_day, payload.get("description", "Community stabilized following proper security measures.")]

				_:
					log_msg = "[EVENT] Day %d: %s" % [current_day, payload.get("description", "Consequence executed.")]

			daily_event_logs.append({
				"day": current_day,
				"type": c_type,
				"log": log_msg,
				"consequence_id": c.get("id"),
				"visitor_name": visitor_name
			})

			processed_consequences.append(c)
			consequence_fired.emit(c, log_msg)
		else:
			remaining_queue.append(c)

	consequence_queue = remaining_queue
	_run_infection(current_day, shelter_state, daily_event_logs)
	return daily_event_logs

## Advances the in-house infection clock. Bitten guests progress first
## (+0.25/day, turn at 0.8), then each turned guest loose rolls 50% to bite a
## healthy one at dawn. A turned/bitten guest is never a victim; fresh bites
## grow from the NEXT dawn, so a bite turns the bearer ~3 days later.
func _run_infection(current_day: int, shelter_state: Dictionary, logs: Array) -> void:
	for g in VisitorManager.admitted_visitors:
		if bool(g.get("bitten", false)) and not bool(g.get("turned", false)):
			var p: float = clampf(float(g.get("infection_progress", 0.2)) + 0.25, 0.0, 1.0)
			g["infection_progress"] = p
			if p >= 0.8:
				g["turned"] = true
				g["bitten"] = false
				logs.append({"day": current_day, "type": TYPE_CHAIN_INFECTION,
					"log": "[TURNED] Day %d: '%s' succumbed to the bite. It is one of them now." % [current_day, g.get("name", "someone")]})
	var turned: Array = []
	var pool: Array = []
	for g in VisitorManager.admitted_visitors:
		if bool(g.get("turned", false)):
			turned.append(g)
		elif not bool(g.get("bitten", false)):
			pool.append(g)
	for biter in turned:
		if pool.is_empty():
			break
		if randf() >= 0.5:
			continue
		var victim: Dictionary = pool.pop_at(randi() % pool.size())
		victim["bitten"] = true
		victim["infection_progress"] = 0.2
		apply_stat_changes(shelter_state, {"trust": -10, "morale": -10})
		logs.append({"day": current_day, "type": TYPE_CHAIN_INFECTION,
			"log": "[BITE] Day %d: '%s' screamed in the night. Something in the house bit them." % [current_day, victim.get("name", "someone")]})

func _guest_by_id(guest_id: String) -> Dictionary:
	for g in VisitorManager.admitted_visitors:
		if str(g.get("id", "")) == guest_id:
			return g
	return {}

## Helper to modify shelter state stats safely within 0 to 100 range
func apply_stat_changes(shelter_state: Dictionary, changes: Dictionary) -> void:
	for key in changes.keys():
		var current_val: float = shelter_state.get(key, 50.0)
		var delta: float = changes[key]
		shelter_state[key] = clampf(current_val + delta, 0.0, 100.0)

	shelter_stats_changed.emit(shelter_state)

## Retrieve queue of upcoming pending consequences
func get_queued_consequences() -> Array:
	return consequence_queue.duplicate()

## Retrieve full decision log
func get_decision_history() -> Array:
	return decision_history.duplicate()
