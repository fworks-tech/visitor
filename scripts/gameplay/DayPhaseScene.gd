# DayPhaseScene.gd
# Morning resource management: survivors, resources, day actions, then next night.
extends Control

@onready var day_label: Label = $TopBar/HBox/DayLabel
@onready var trust_label: Label = $TopBar/HBox/TrustLabel
@onready var food_label: Label = $TopBar/HBox/ResourcesBox/FoodLabel
@onready var water_label: Label = $TopBar/HBox/ResourcesBox/WaterLabel
@onready var ammo_label: Label = $TopBar/HBox/ResourcesBox/AmmoLabel
@onready var medicine_label: Label = $TopBar/HBox/ResourcesBox/MedicineLabel
@onready var fuel_label: Label = $TopBar/HBox/ResourcesBox/FuelLabel

@onready var survivors_list: ItemList = $LeftPanel/VBox/SurvivorsList
@onready var log_text: RichTextLabel = $RightPanel/VBox/ScrollContainer/LogText

@onready var scavenge_btn: Button = $ActionBar/HBox/ScavengeButton
@onready var fortify_btn: Button = $ActionBar/HBox/FortifyButton
@onready var talk_btn: Button = $ActionBar/HBox/TalkButton
@onready var rest_btn: Button = $ActionBar/HBox/RestButton
@onready var next_night_btn: Button = $ActionBar/HBox/NextNightButton

var actions_taken: int = 0
const MAX_ACTIONS_PER_DAY := 3

func _ready() -> void:
	GameManager.change_state(GameManager.GameState.DAY)
	_refresh_all()
	_seed_day_log()

	scavenge_btn.pressed.connect(_on_scavenge)
	fortify_btn.pressed.connect(_on_fortify)
	talk_btn.pressed.connect(_on_talk)
	rest_btn.pressed.connect(_on_rest)
	next_night_btn.pressed.connect(_on_next_night)

	ResourceSystem.resources_changed.connect(_on_resources_changed)

func _seed_day_log() -> void:
	_log("[color=#aaffaa]DAY %d — You have %d actions before nightfall. Scavenge, fortify, talk, or rest — then press NEXT NIGHT.[/color]" % [GameManager.current_day, MAX_ACTIONS_PER_DAY])
	var nights: Array = StoryManager.story_data.get("nights", [])
	for n in nights:
		if int(n.get("night_number", 0)) == GameManager.current_day:
			var ev: Dictionary = n.get("day_phase_events", {})
			if ev.has("summary"):
				_log("[color=#aaffaa]BRIEFING: %s[/color]" % ev.get("summary", ""))
			if ev.has("shelter_event"):
				_log(str(ev.get("shelter_event", "")))
			for line in ev.get("dialogue_highlights", []):
				_log("[color=#aaffaa]%s: \"%s\"[/color]" % [line.get("speaker", "?"), line.get("text", "")])
			break

func _on_resources_changed(_res: Dictionary) -> void:
	_refresh_resources()

func _refresh_all() -> void:
	day_label.text = "DAY %d / %d" % [GameManager.current_day, GameManager.max_days]
	trust_label.text = "TRUST %d" % GameManager.trust_value
	_refresh_resources()
	_refresh_survivors()
	_update_action_buttons()

func _refresh_resources() -> void:
	var res := ResourceSystem.get_resources()
	food_label.text = "FOOD %d" % res.get("food", 0)
	water_label.text = "WATER %d" % res.get("water", 0)
	ammo_label.text = "AMMO %d" % res.get("ammo", 0)
	medicine_label.text = "MEDS %d" % res.get("medicine", 0)
	fuel_label.text = "FUEL %d" % res.get("fuel", 0)

func _refresh_survivors() -> void:
	survivors_list.clear()
	var survivors: Array = VisitorManager.get_survivors_inside()
	if survivors.is_empty():
		survivors_list.add_item("(no one else made it inside)")
	else:
		for s in survivors:
			survivors_list.add_item(str(s.get("name", "Unknown")))

func _log(message: String) -> void:
	log_text.append_text("[color=gray]" + message + "[/color]\n")

func _update_action_buttons() -> void:
	var exhausted := actions_taken >= MAX_ACTIONS_PER_DAY
	scavenge_btn.disabled = exhausted
	fortify_btn.disabled = exhausted
	talk_btn.disabled = exhausted
	rest_btn.disabled = exhausted

# --- Day actions -------------------------------------------------------------

func _on_scavenge() -> void:
	actions_taken += 1
	_update_action_buttons()
	# Scavenge yields: food/water usually, small chance of meds or ammo
	ResourceSystem.add_resources({
		"food": randi_range(1, 3),
		"water": randi_range(1, 3),
		"medicine": 1 if randf() < 0.25 else 0,
		"ammo": 1 if randf() < 0.2 else 0,
	})
	_log("You search the apartment. You find what the previous owners left behind.")
	_refresh_resources()

func _on_fortify() -> void:
	actions_taken += 1
	_update_action_buttons()
	if GameManager.has_method("fortify_defense"):
		GameManager.fortify_defense()
	_log("You wedge furniture against the door. Again. It buys minutes, not safety.")

func _on_talk() -> void:
	actions_taken += 1
	_update_action_buttons()
	if GameManager.has_method("add_trust"):
		GameManager.add_trust(3)
	_log("You share coffee with whoever is inside. The talking helps more than the coffee.")

func _on_rest() -> void:
	actions_taken = MAX_ACTIONS_PER_DAY  # resting consumes the rest of the day
	_update_action_buttons()
	if GameManager.has_method("restore_energy"):
		GameManager.restore_energy()
	_log("You sleep in shifts. Nobody really sleeps.")

func _on_next_night() -> void:
	# advance_to_next_day triggers the final ending via evaluate_endings()
	# when current_day > max_days — this scene must not double-trigger.
	GameManager.advance_to_next_day()
