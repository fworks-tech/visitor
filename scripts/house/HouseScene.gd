class_name HouseScene
extends Control

## Walkable first-person house in the spirit of Tales Beyond the Tomb:
## WASD + mouse, E/click to use. Nights open on the bed, the front door
## leads to the inspection slot, and sleep is the only night/day transition.
## Guests sit in rooms and are examined by day.

const INSPECTION_SCENE_PATH := "res://scenes/gameplay/InspectionScene.tscn"
const HOUSE_IMG_DIR := "res://assets/images/house/"

const CONTROLS_HINT := "\n\nWASD to walk, mouse to look, F flashlight, E to interact."

const ROOM_CAPS := {"hall": 2, "kitchen": 2, "office": 2, "bathroom": 1, "bedroom": 0}

const ROOM_NAMES := {
	"bedroom": "BEDROOM",
	"hall": "HALL",
	"kitchen": "KITCHEN",
	"office": "OFFICE",
	"bathroom": "BATHROOM",
}

const TOOL_LABELS := {
	"interrogation_clipboard": "INTERROGATION CLIPBOARD",
	"thermal_scanner": "THERMAL SCANNER",
	"blood_test_strips": "BLOOD TEST STRIPS",
	"rapid_pcr_diagnostic": "RAPID PCR",
	"uv_blacklight": "UV BLACKLIGHT",
	"neural_response_probe": "NEURAL PROBE",
	"master_bio_scanner": "MASTER BIO SCANNER",
	"flashlight": "FLASHLIGHT",
}

@onready var house3d: House3D = $View3D/SubViewport/House3D
@onready var room_label: Label = $TopBar/HBox/RoomLabel
@onready var day_label: Label = $TopBar/HBox/DayLabel
@onready var trust_label: Label = $TopBar/HBox/TrustLabel
@onready var energy_label: Label = $TopBar/HBox/EnergyLabel
@onready var battery_label: Label = $TopBar/HBox/BatteryLabel
@onready var crosshair: Label = $Crosshair
@onready var prompt_label: Label = $PromptLabel
@onready var popup: PanelContainer = $Popup
@onready var popup_title: Label = $Popup/VBox/PopupTitle
@onready var popup_image: TextureRect = $Popup/VBox/PopupImage
@onready var popup_text: RichTextLabel = $Popup/VBox/PopupText
@onready var popup_actions: VBoxContainer = $Popup/VBox/PopupActions

var current_room: String = "bedroom"
var _popup_guest: Dictionary = {}
var _focus: Dictionary = {}
# Último dispositivo visto: teclado, gamepad ou toque — move o glyph do prompt.
var _last_device := "keyboard"
var _touch_layer: Control
var _stick_vec := Vector2.ZERO
var _stick_touch := -1
var _look_touch := -1

func _ready() -> void:
	AudioManager.stop_music()
	AudioManager.stop_tap()
	house3d.set_mood(_is_day())
	house3d.set_guests(VisitorManager.admitted_visitors)
	_refresh_hud()
	_build_touch_controls()
	_capture_mouse()
	_unlock_floors_for_day()
	if _is_day():
		if not GameManager.tv_watched_today:
			_open_popup("MORNING", "", "You wake in your bunk. The TV in the corner flickers with the morning broadcast. Watch it before examining anyone." + CONTROLS_HINT)
		_try_trigger_day_dilemma()
	else:
		var briefing := _night_briefing()
		if briefing != "":
			_open_popup("NIGHT %d — CHECKPOINT 9" % GameManager.current_day, "", briefing + CONTROLS_HINT)
	if ResourceSystem.get_resources().get("fuel", 0) <= 0:
		house3d.set_mood(false)  # dark house when out of fuel

## Unlocks house floors based on the current day. New areas open as the
## siege progresses — more hands to scavenge, more places to search.
func _unlock_floors_for_day() -> void:
	if house3d == null:
		return
	var floors := ["ground"]
	var day: int = GameManager.current_day
	if day >= 3:
		floors.append("second")
	if day >= 5:
		floors.append("attic")
	if day >= 7:
		floors.append("basement")
	house3d.set_unlocked_floors(floors)

func _is_day() -> bool:
	return GameManager.current_state == GameManager.GameState.DAY

func _capture_mouse() -> void:
	if not popup.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- first-person presence -----------------------------------------------------

func _process(_delta: float) -> void:
	if house3d.player == null:
		return
	house3d.player.touch_move = _stick_vec if _touch_layer.visible else Vector2.ZERO
	var room := house3d.get_room_at(house3d.player.global_position)
	if room != current_room:
		current_room = room
		room_label.text = str(ROOM_NAMES.get(room, "ROOM"))
	_refresh_focus()
	_refresh_battery()  # cheap label write; the cell drains in real time

func _refresh_focus() -> void:
	_focus = {}
	if popup.visible or house3d.player == null or house3d.player.camera == null:
		prompt_label.text = ""
		crosshair.modulate.a = 0.35
		return
	var cam := house3d.player.camera
	_focus = house3d.get_focus(cam.global_position, -cam.global_transform.basis.z)
	if _focus.is_empty():
		prompt_label.text = ""
		crosshair.modulate.a = 0.35
	else:
		prompt_label.text = _interact_glyph() + " " + str(_focus.get("label", "USE"))
		crosshair.modulate.a = 1.0


# Glyph segue o último dispositivo: E no teclado, A no gamepad, toque direto.
func _interact_glyph() -> String:
	match _last_device:
		"gamepad":
			return "[A]"
		"touch":
			return "[TOQUE]"
		_:
			return "[E]"


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		_last_device = "keyboard"
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_last_device = "gamepad"
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_device = "touch"
	_handle_touch(event)


func _unhandled_input(event: InputEvent) -> void:
	if popup.visible:
		return
	var use := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			use = true
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
			or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_E):
		use = true
	if use:
		_try_use_from_input()

var _last_use_msec := 0

## Single gate for every physical use-input (left-click, E, touch USA): one
## press can arrive as two events on some stacks, and a doubled toggle would
## open-then-close furniture (or stop the tap it just started) in one click.
func _try_use_from_input() -> void:
	if popup.visible or _focus.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_use_msec < 350:
		return
	_last_use_msec = now
	_do_interact(_focus)

func _do_interact(focus: Dictionary) -> void:
	if str(focus.get("id", "")) == "guest":
		_open_guest_popup(focus.get("guest", {}))
		return
	_on_hotspot({"action": str(focus.get("id", ""))})

func _refresh_hud() -> void:
	day_label.text = "DAY %d / %d" % [GameManager.current_day, GameManager.max_days]
	trust_label.text = "TRUST %d" % GameManager.trust_value
	var pips := ""
	for i in range(GameManager.energy_max):
		pips += "▮" if i < GameManager.energy_left else "▯"
	energy_label.text = "ENERGY %s" % pips
	_refresh_battery()

func _refresh_battery() -> void:
	battery_label.text = "BATT %d%% x%d" % [int(GameManager.flashlight_battery), GameManager.batteries]
	battery_label.add_theme_color_override("font_color",
		Color(1.0, 0.3, 0.2, 1.0) if GameManager.flashlight_battery < 25.0 else Color(0.667, 1.0, 0.667, 1.0))

# --- interact actions (E / click on the focused point) -------------------------

func _on_hotspot(data: Dictionary) -> void:
	match str(data.get("action", "")):
		"bed":
			_action_bed()
		"tv":
			_action_tv()
		"radio":
			_action_radio()
		"window":
			_action_window()
		"front_door":
			_action_front_door()
		"scavenge":
			_action_scavenge()
		"cabinet":
			_action_cabinet()
		"drawer":
			_action_drawer()
		"tap":
			_action_tap()
		"fortify":
			_action_fortify()
		"mirror":
			_action_mirror()
		"guest":
			_open_guest_popup(data.get("guest", {}))
		"stairs_up", "stairs_down", "stairs_down_from_second", "stairs_up_from_basement", "ladder_up", "ladder_down":
			_action_stairs(str(data.get("action", "")))
		"scavenge_storage":
			_action_scavenge_storage()
		"guest_room_bed":
			_action_guest_room_bed()
		"search_attic":
			_action_search_attic()
		"generator":
			_action_generator()
		"cellar_search":
			_action_cellar_search()

func _action_bed() -> void:
	if _is_day() and GameManager.energy_left > 0:
		_open_popup("TOO RESTLESS", "", "There is still daylight and the checkpoint needs work. Spend your energy first.")
		return
	if not _is_day() and not VisitorManager.night_completed:
		_open_popup("NOT YET", "", "Someone may still knock tonight. The front door is your post.")
		return
	GameManager.go_sleep()

func _action_tv() -> void:
	house3d.set_tv_on(true)
	if not _is_day():
		_open_popup("TV", "", "Static and a countdown to nightfall. The broadcast comes in the morning.")
		return
	var info := GameManager.watch_tv()
	if info.is_empty():
		_open_popup("TV", "", "You have seen today's broadcast.")
		return
	var names: Array = []
	for t in info.get("tools", []):
		names.append(str(TOOL_LABELS.get(str(t), str(t))))
	var text := ""
	var ev := _day_events()
	if ev.has("summary"):
		text += "[color=#aaffaa]%s[/color]\n\n" % str(ev.get("summary", ""))
	if not names.is_empty():
		text += "NEW INSPECTION TOOLS UNLOCKED: %s\nEach check on a guest costs 1 energy." % ", ".join(PackedStringArray(names))
	_open_popup("EMERCOM BROADCAST — DAY %d" % GameManager.current_day, "", text)

func _action_radio() -> void:
	var lines: Array = _day_events().get("dialogue_highlights", [])
	var text := ""
	for line in lines:
		text += "[color=#aaffaa]%s:[/color] \"%s\"\n\n" % [line.get("speaker", "RADIO"), line.get("text", "")]
	if text == "":
		text = "Static. The broadcast band has been dead for days."
	_open_popup("RADIO", "", text)

func _action_window() -> void:
	var hazard := ""
	var nights: Array = StoryManager.story_data.get("nights", [])
	for n in nights:
		if int(n.get("night_number", 0)) == GameManager.current_day:
			hazard = str(n.get("environmental_hazard", ""))
			break
	var text := ""
	if _is_day():
		text = "Daylight burns the streets empty. %s" % hazard
	else:
		var figures: int = VisitorManager.rejected_visitors.size()
		if figures > 0:
			text = "%s\n\nFigures linger near the wire — %d you turned away, still out there in the dark." % [hazard, figures]
		else:
			text = "%s\n\nNothing moves out there. For now." % hazard
	_open_popup("WINDOW", HOUSE_IMG_DIR + "house_window_outside.png", text)

func _action_front_door() -> void:
	if _is_day():
		_open_popup("FRONT DOOR", "", "Daylight. Nobody knocks under the sun. Night is when they come.")
		return
	if VisitorManager.night_completed:
		_open_popup("FRONT DOOR", "", "The wire is quiet. Everyone who was coming has come.")
		return
	SceneManager.change_scene(INSPECTION_SCENE_PATH)

func _action_scavenge() -> void:
	if not _is_day() or not GameManager.spend_energy(1):
		_open_popup("PANTRY", "", _energy_blocked_text())
		return
	ResourceSystem.add_resources({
		"food": randi_range(1, 3),
		"water": randi_range(1, 3),
		"medicine": 1 if randf() < 0.25 else 0,
		"ammo": 1 if randf() < 0.2 else 0,
	})
	var loot := "You pull what the previous owners left behind. It keeps someone alive a little longer."
	if randf() < 0.35:
		GameManager.batteries += 1
		loot += "\n[Spare battery found — press R to swap it in.]"
	_refresh_hud()
	_open_popup("SCAVENGE", "", loot)

func _action_cabinet() -> void:
	AudioManager.play_sfx("door_latch")
	house3d.toggle_cabinets()

func _action_drawer() -> void:
	AudioManager.play_sfx("drawer_slide")
	house3d.toggle_drawer()

func _action_tap() -> void:
	if not house3d.toggle_tap():
		return
	if int(FlagsManager.get_flag("tap_day", 0)) == GameManager.current_day:
		return
	FlagsManager.set_flag("tap_day", GameManager.current_day)
	ResourceSystem.add_resources({"water": 1})
	_refresh_hud()
	_open_popup("TAP", "", "You hold an old bottle under the trickle. +1 WATER — the pipes still run, for now.")

func _action_fortify() -> void:
	if not _is_day() or not GameManager.spend_energy(1):
		_open_popup("OFFICE", "", _energy_blocked_text())
		return
	_refresh_hud()
	_open_popup("FORTIFY", "", "You wedge furniture and wire against every pane. It buys minutes, not safety.")

func _action_mirror() -> void:
	if not _is_day() or not GameManager.spend_energy(1):
		_open_popup("MIRROR", "", _energy_blocked_text())
		return
	if bool(FlagsManager.get_flag("player_infected", false)):
		AudioManager.play_glitch(2)
		_open_popup("MIRROR", "", "Your gums bleed when you smile. You do not smile anymore.")
	else:
		_open_popup("MIRROR", "", "Clean teeth, tired eyes, human hands. You look human. For now.")

# --- multi-floor navigation ---------------------------------------------------

const FLOOR_Y := {"ground": 0.0, "second": 3.2, "attic": 6.4, "basement": -3.2}

## Maps each stairs/ladder action to the target floor and the player spawn offset.
const STAIRS_TARGET := {
	"stairs_up": ["second", Vector3(2.5, 0.05, 0.0)],
	"stairs_down": ["basement", Vector3(2.5, 0.05, 0.0)],
	"stairs_down_from_second": ["ground", Vector3(2.5, 0.05, 0.0)],
	"stairs_up_from_basement": ["ground", Vector3(2.5, 0.05, 0.0)],
	"ladder_up": ["attic", Vector3(2.5, 0.05, 0.0)],
	"ladder_down": ["second", Vector3(2.5, 0.05, 0.0)],
}

func _action_stairs(action: String) -> void:
	if not STAIRS_TARGET.has(action):
		return
	var target_floor: String = STAIRS_TARGET[action][0]
	var local_offset: Vector3 = STAIRS_TARGET[action][1]
	if house3d == null:
		return
	# Teleport the player to the corresponding position on the target floor.
	var target_pos := Vector3(local_offset.x, FLOOR_Y[target_floor] + local_offset.y, local_offset.z)
	house3d.player.position = target_pos
	house3d._current_floor = target_floor
	_open_popup("STAIRS" if "ladder" not in action else "LADDER", "", "You climb to the %s." % target_floor)

func _action_scavenge_storage() -> void:
	if not _is_day() or not GameManager.spend_energy(1):
		_open_popup("STORAGE", "", _energy_blocked_text())
		return
	ResourceSystem.add_resources({"food": randi_range(1, 2), "water": 1})
	if randf() < 0.4:
		GameManager.batteries += 1
		_open_popup("STORAGE ROOM", "", "Crates of old rations and a spare battery. It keeps someone alive a little longer.")
	else:
		_open_popup("STORAGE ROOM", "", "Old supplies. Not much left, but enough to matter.")
	_refresh_hud()

func _action_guest_room_bed() -> void:
	if not _is_day():
		_open_popup("GUEST ROOM", "", "A narrow bed. Someone slept here once. The sheets smell like dust and decisions.")
		return
	if GameManager.energy_left >= GameManager.energy_max:
		_open_popup("GUEST ROOM", "", "You are not tired enough to rest. The bed waits.")
		return
	GameManager.energy_left = mini(GameManager.energy_left + 1, GameManager.energy_max)
	_refresh_hud()
	_open_popup("GUEST ROOM", "", "You collapse on the narrow mattress. The springs groan. +1 ENERGY — just enough to keep going.")

func _action_search_attic() -> void:
	if not _is_day() or not GameManager.spend_energy(1):
		_open_popup("ATTIC", "", _energy_blocked_text())
		return
	ResourceSystem.add_resources({"medicine": 1})
	if randf() < 0.35:
		ResourceSystem.add_resources({"ammo": 1})
		_open_popup("ATTIC STORAGE", "", "Cobwebs and old furniture. Behind a loose board: medical supplies and a loaded magazine.")
	else:
		_open_popup("ATTIC STORAGE", "", "Cobwebs and old furniture. Behind a loose board: medical supplies.")
	_refresh_hud()

func _action_generator() -> void:
	if not _is_day() or not GameManager.spend_energy(1):
		_open_popup("GENERATOR", "", _energy_blocked_text())
		return
	FlagsManager.set_flag("generator_checked", true)
	var fuel: int = int(ResourceSystem.get_resources().get("fuel", 0))
	if fuel <= 0:
		_open_popup("GENERATOR — EMPTY", "", "The generator sputters and dies. The lights go out. Find fuel in the cellar before nightfall.")
		_refresh_hud()
		return
	var refuel := mini(fuel, 3)
	ResourceSystem.consume_fuel(refuel)
	GameManager.security_value += 2
	_refresh_hud()
	_open_popup("GENERATOR", "", "You top off the tank. +2 SECURITY. The hum steadies. Fuel remaining: %d." % ResourceSystem.get_resources().get("fuel", 0))

func _action_cellar_search() -> void:
	if not _is_day() or not GameManager.spend_energy(1):
		_open_popup("CELLAR", "", _energy_blocked_text())
		return
	ResourceSystem.add_resources({"fuel": randi_range(2, 4), "food": 1})
	_refresh_hud()
	_open_popup("CELLAR", "", "Barrels in the dark. Diesel sloshes in the old drums. +%d FUEL — the generator lives another day." % randi_range(2, 4))

func _energy_blocked_text() -> String:
	if not _is_day():
		return "Not at night. The dark outside answers to nothing you do here."
	if GameManager.energy_left <= 0:
		return "Exhausted. The bed is the only thing left worth doing today."
	return "Watch the TV broadcast first — you don't know what to check for yet."

# --- guests ------------------------------------------------------------------

func _open_guest_popup(guest: Dictionary) -> void:
	_popup_guest = guest
	var intro := "Admitted on night %d. They sit where you placed them." % int(guest.get("admitted_day", 0))
	var actions: Array = [{"label": "TALK", "action": "talk"}]
	if _is_day():
		actions.append({"label": "EXAMINE (1 ENERGY)", "action": "examine"})
		actions.append({"label": "KICK OUT", "action": "kick"})
	actions.append({"label": "CLOSE", "action": "close"})
	_open_popup("GUEST — %s" % str(guest.get("name", "GUEST")).to_upper(), str(guest.get("portrait", "")), intro)
	_set_popup_actions(actions)

func _popup_talk() -> void:
	var chain: Array = _popup_guest.get("dialogue_chain", [])
	var step := int(_popup_guest.get("talk_step", 0))
	if step < chain.size():
		_popup_guest["talk_step"] = step + 1
		var beat := str(chain[step])
		popup_text.text = "[color=#aaffaa]%s:[/color] \"%s\"" % [str(_popup_guest.get("name", "GUEST")).to_upper(), beat]
	else:
		popup_text.text = str(_popup_guest.get("backstory", "They have nothing more to say."))

func _popup_examine() -> void:
	if not _is_day():
		return
	if not GameManager.tv_watched_today:
		popup_text.text = "You don't know what to look for yet. Watch the TV broadcast."
		return
	if not GameManager.spend_energy(1):
		popup_text.text = _energy_blocked_text()
		_refresh_hud()
		return
	var signs: Array = _popup_guest.get("assigned_signs", [])
	var revealed := int(_popup_guest.get("revealed_signs_count", 0))
	if revealed < signs.size():
		var s: Dictionary = signs[revealed]
		_popup_guest["revealed_signs_count"] = revealed + 1
		house3d.show_guest_sign(str(_popup_guest.get("id", "")), s)
		popup_text.text = "[color=#aaffaa]%s[/color]\n%s" % [s.get("name", "SIGN"), s.get("human_explanation", "")]
	else:
		if _guest_infected():
			_popup_guest["confirmed_infected"] = true
			AudioManager.play_glitch(2)
			popup_text.text = "…beyond the signs, something underneath answers your exam. This one is a Visitor."
		else:
			popup_text.text = "No further signs. %s reads human." % str(_popup_guest.get("name", "The guest"))
	_refresh_hud()

func _popup_kick() -> void:
	var kicked := VisitorManager.kick_guest(str(_popup_guest.get("id", "")))
	_popup_guest = {}
	popup.visible = false
	house3d.set_guests(VisitorManager.admitted_visitors)
	_refresh_hud()
	if not kicked.is_empty():
		_open_popup("KICKED OUT", "", "%s is back outside in the cold. The house watches you do it." % str(kicked.get("name", "The guest")))

func _guest_infected() -> bool:
	return bool(_popup_guest.get("is_actually_infected", _popup_guest.get("is_infected", false)))

# --- popups ------------------------------------------------------------------

func _open_popup(title: String, image_path: String, text: String) -> void:
	popup_title.text = title
	if image_path != "" and ResourceLoader.exists(image_path):
		popup_image.texture = load(image_path)
		popup_image.visible = true
	else:
		popup_image.visible = false
	popup_text.text = text
	_set_popup_actions([{"label": "CLOSE", "action": "close"}])
	popup.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # free the cursor for buttons

func _set_popup_actions(actions: Array) -> void:
	for child in popup_actions.get_children():
		child.queue_free()
	for i in actions.size():
		var a: Dictionary = actions[i]
		var btn := Button.new()
		btn.text = str(a.get("label", "OK"))
		btn.custom_minimum_size = Vector2(0, 44)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_popup_action.bind(str(a.get("action", ""))))
		popup_actions.add_child(btn)
		if i == 0:
			btn.call_deferred("grab_focus")  # D-pad já entra navegando

func _on_popup_action(action: String) -> void:
	match action:
		"close":
			popup.visible = false
			_popup_guest = {}
			_capture_mouse()
		"talk":
			_popup_talk()
		"examine":
			_popup_examine()
		"kick":
			_popup_kick()

# --- toque: joystick esquerdo + botões E/F/R + arrasto direito = look --------
# Camada invisível no desktop; só aparece com touchscreen de verdade.

func _build_touch_controls() -> void:
	_touch_layer = Control.new()
	_touch_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_layer.visible = false
	add_child(_touch_layer)
	var stick := Control.new()
	stick.name = "Stick"
	stick.anchor_left = 0.0
	stick.anchor_top = 1.0
	stick.anchor_right = 0.0
	stick.anchor_bottom = 1.0
	stick.offset_left = 40.0
	stick.offset_top = -260.0
	stick.offset_right = 260.0
	stick.offset_bottom = -40.0
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_layer.add_child(stick)
	var base := ColorRect.new()
	base.color = Color(0.4, 1.0, 0.4, 0.15)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick.add_child(base)
	var knob := ColorRect.new()
	knob.name = "Knob"
	knob.color = Color(0.4, 1.0, 0.4, 0.45)
	knob.custom_minimum_size = Vector2(72, 72)
	knob.size = Vector2(72, 72)
	knob.position = Vector2(74, 74)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick.add_child(knob)
	var btns := HBoxContainer.new()
	btns.anchor_left = 1.0
	btns.anchor_top = 1.0
	btns.anchor_right = 1.0
	btns.anchor_bottom = 1.0
	btns.offset_left = -380.0
	btns.offset_top = -140.0
	btns.offset_right = -40.0
	btns.offset_bottom = -60.0
	btns.add_theme_constant_override("separation", 16)
	_touch_layer.add_child(btns)
	_add_touch_button(btns, "USA", _on_touch_use)
	_add_touch_button(btns, "LUZ", _on_touch_flashlight)
	_add_touch_button(btns, "BAT", _on_touch_battery)
	_touch_layer.visible = DisplayServer.is_touchscreen_available()


func _add_touch_button(parent: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(100, 80)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	parent.add_child(b)


func _on_touch_use() -> void:
	_try_use_from_input()


func _on_touch_flashlight() -> void:
	if house3d.player != null:
		house3d.player._try_toggle()


func _on_touch_battery() -> void:
	if house3d.player != null and GameManager.replace_battery():
		house3d.player.flashlight_on = true
		house3d.player.spot.visible = true


func _handle_touch(event: InputEvent) -> void:
	if _touch_layer == null or not _touch_layer.visible:
		if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
			_stick_touch = -1
			_look_touch = -1
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and t.position.x <= vp.x * 0.4 and _stick_touch < 0:
			_stick_touch = t.index
			_update_stick(t.position)
		elif t.pressed and t.position.x > vp.x * 0.4 and _look_touch < 0:
			_look_touch = t.index
		elif not t.pressed:
			if t.index == _stick_touch:
				_stick_touch = -1
				_stick_vec = Vector2.ZERO
				_reset_knob()
			if t.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_update_stick(d.position)
		elif d.index == _look_touch and house3d.player != null:
			house3d.player.drag_look(d.relative * 0.006)


func _update_stick(pos: Vector2) -> void:
	var stick := _touch_layer.get_node_or_null("Stick") as Control
	if stick == null:
		return
	var center := stick.get_global_rect().get_center()
	var off := (pos - center) / 90.0
	_stick_vec = off.limit_length(1.0)
	var knob := stick.get_node_or_null("Knob") as ColorRect
	if knob != null:
		knob.position = Vector2(74, 74) + _stick_vec * 60.0


func _reset_knob() -> void:
	var knob := _touch_layer.get_node_or_null("Stick/Knob") as ColorRect
	if knob != null:
		knob.position = Vector2(74, 74)


# --- story helpers -----------------------------------------------------------

func _night_briefing() -> String:
	var nights: Array = StoryManager.story_data.get("nights", [])
	for n in nights:
		if int(n.get("night_number", 0)) == GameManager.current_day:
			return str(n.get("briefing", ""))
	return ""

func _day_events() -> Dictionary:
	var nights: Array = StoryManager.story_data.get("nights", [])
	for n in nights:
		if int(n.get("night_number", 0)) == GameManager.current_day:
			return n.get("day_phase_events", {})
	return {}

# --- day-phase dilemmas (Mason bite, Silas proposal) --------------------------

## Presents the day's dilemma choice if one exists and hasn't been resolved yet.
func _try_trigger_day_dilemma() -> void:
	if not _is_day():
		return
	var ev: Dictionary = _day_events()
	var dilemma: Dictionary = ev.get("dilemma_choice", {})
	if dilemma.is_empty():
		return
	var flag_key := "dilemma_resolved_day%d" % GameManager.current_day
	if bool(FlagsManager.get_flag(flag_key, false)):
		return
	_open_dilemma_popup(dilemma, flag_key)

func _open_dilemma_popup(dilemma: Dictionary, flag_key: String) -> void:
	popup_title.text = str(dilemma.get("title", "DECISION")).to_upper()
	var ev: Dictionary = _day_events()
	popup_text.text = str(ev.get("shelter_event", dilemma.get("description", "")))
	popup_image.visible = false
	for child in popup_actions.get_children():
		child.queue_free()
	var options: Array = dilemma.get("options", [])
	for i in options.size():
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = str(opt.get("label", opt.get("action", "CHOICE %d" % i)).replace("_", " ")).to_upper()
		btn.custom_minimum_size = Vector2(0, 48)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_dilemma_choice.bind(opt, flag_key))
		popup_actions.add_child(btn)
		if i == 0:
			btn.call_deferred("grab_focus")
	popup.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Applies the mechanical effect of a dilemma choice and marks it resolved.
func _on_dilemma_choice(opt: Dictionary, flag_key: String) -> void:
	var action: String = str(opt.get("action", ""))
	match action:
		"quarantine_mason":
			FlagsManager.increment_flag("morale", 5)
			FlagsManager.increment_flag("trust", -5)
			_open_popup("QUARANTINE", "", "Mason is locked in the holding cell. Dr. Stern says the antivirals may slow the infection. You'll know by morning if he turns.")
		"execute_mason":
			FlagsManager.increment_flag("corruption", 20)
			FlagsManager.increment_flag("trust", -15)
			_open_popup("EXECUTED", "", "Viktor doesn't hesitate. One shot, and the only witness to the protocol is the smell of gunpowder. The shelter is silent tonight.")
		"cover_up_mason":
			FlagsManager.set_flag("mason_bite_hidden", true)
			FlagsManager.increment_flag("corruption", 10)
			_open_popup("COVER-UP", "", "You pocket the bandage and lie to Viktor. Mason sweats through the night in the dark. You pray the antivirals work.")
		"hold_the_line":
			FlagsManager.increment_flag("trust", 10)
			FlagsManager.increment_flag("morale", -5)
			FlagsManager.set_flag("silas_hostile", true)
			_open_popup("HOLD THE LINE", "", "You refuse to abandon the gate. Silas curses and storms off, but Vera nods. The checkpoint holds — for now.")
		"cut_rations":
			FlagsManager.increment_flag("morale", -20)
			FlagsManager.increment_flag("food", 5)
			FlagsManager.set_flag("silas_hostile", false)
			_open_popup("HALF RATIONS", "", "Vera waters down the stew. The shelter eats half portions. Nobody speaks, but the generator burns a little longer.")
		"plan_evacuation":
			FlagsManager.increment_flag("security", 5)
			FlagsManager.set_flag("radio_fixed", true)
			_open_popup("EVACUATION PLAN", "", "Silas cracks his knuckles and starts on the generator. Nia recalibrates the radio array. If the choppers come, you'll hear them.")
		_:
			_open_popup("DECISION", "", str(opt.get("effect", "You make your choice.")))
	FlagsManager.set_flag(flag_key, true)
	_refresh_hud()
