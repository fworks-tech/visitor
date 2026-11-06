class_name InspectionScene
extends Control

## Main Gameplay Controller for the Visitor Inspection Scene.
## Wired to the REAL story data: the night queue comes from VisitorManager
## (visitors.json), portraits + reveal variants come from the art pipeline
## (portrait / reveal_portrait fields), inspection text is driven by
## dialogue_chain + reveal_on_inspection + assigned signs (signs.json),
## and every decision applies the visitor's authored consequences.

@export var crt_overlay_path: NodePath = "CRTOverlay"

# Top Bar UI Node References
@onready var day_label: Label = $TopBar/MarginContainer/HBoxContainer/DayLabel
@onready var time_label: Label = $TopBar/MarginContainer/HBoxContainer/TimeLabel
@onready var food_label: Label = $TopBar/MarginContainer/HBoxContainer/ResourceContainer/FoodLabel
@onready var water_label: Label = $TopBar/MarginContainer/HBoxContainer/ResourceContainer/WaterLabel
@onready var ammo_label: Label = $TopBar/MarginContainer/HBoxContainer/ResourceContainer/AmmoLabel
@onready var medicine_label: Label = $TopBar/MarginContainer/HBoxContainer/ResourceContainer/MedicineLabel

# Door figure: a hand-built 3D bust in its own diorama viewport (left), the
# dialogue floats on the right ("No, I'm not a Human" door framing).
@onready var diorama: VisitorDiorama3D = $MainSplit/LeftPanel/VBoxContainer/PortraitMargin/DoorView/SubViewport/Diorama
@onready var portrait_art: TextureRect = $MainSplit/LeftPanel/VBoxContainer/PortraitArt
@onready var visitor_name_label: Label = $MainSplit/LeftPanel/VBoxContainer/VisitorNameLabel
@onready var status_label: Label = $MainSplit/RightPanel/VBoxContainer/StatusLabel

# Left Physical Signs Panel Node References
@onready var physical_signs_container: VBoxContainer = $MainSplit/LeftPanel/VBoxContainer/ScrollContainer/SignsList
@onready var inspect_btn: Button = $MainSplit/LeftPanel/VBoxContainer/InspectButton

# Right Behavioral Panel Node References
@onready var behavioral_notes_text: RichTextLabel = $MainSplit/RightPanel/VBoxContainer/ScrollContainer/BehavioralNotesText
@onready var question_wounds_btn: Button = $MainSplit/RightPanel/VBoxContainer/QuestionsContainer/QuestionWoundsBtn
@onready var question_story_btn: Button = $MainSplit/RightPanel/VBoxContainer/QuestionsContainer/QuestionStoryBtn
@onready var test_reaction_btn: Button = $MainSplit/RightPanel/VBoxContainer/QuestionsContainer/TestReactionBtn

# Bottom Decision Buttons
@onready var let_in_btn: Button = $BottomBar/MarginContainer/HBoxContainer/LetInButton
@onready var turn_away_btn: Button = $BottomBar/MarginContainer/HBoxContainer/TurnAwayButton
@onready var eliminate_btn: Button = $BottomBar/MarginContainer/HBoxContainer/EliminateButton
@onready var end_night_btn: Button = $BottomBar/MarginContainer/HBoxContainer/EndNightButton

# CRT Effect Overlay reference
@onready var crt_overlay: CRTController = get_node_or_null(crt_overlay_path) as CRTController

# State
var current_visitor_index: int = 0
var current_visitor: Dictionary = {}
var visitor_queue: Array = []

# per-visitor inspection state (conversation model: the visitor speaks beats
# from dialogue_chain; the player listens, examines, asks, then judges)
var suspicion_level: float = 0.1
var revealed_signs: int = 0
var line_index: int = 0
var asked_about_marks: bool = false
var studied_face: bool = false
var visual_evidence_revealed: bool = false

# Aperture composite (plate + body + doorway shader). Null when disabled.
var aperture_stage: ApertureStage

# Cinematic layout: full-screen scene, dialogue box and choices.
var _cinematic := false
var _cinematic_view: SubViewportContainer
var _cinematic_vp: SubViewport
var _dialogue_layer: Control
var _dialogue_text: Label
var _speaker_label: Label
var _choice_row: HBoxContainer
var _hud_line: Label
var _notes_panel: PanelContainer
var _notes_text: RichTextLabel
var _notes_button: Button
var _choice_buttons: Array = []


func _ready() -> void:
	_build_cinematic_ui()
	_setup_aperture_view()
	_init_visitor_queue()
	_update_resources_ui()
	_connect_signals()
	_frame_portrait()

	if crt_overlay:
		crt_overlay.power_on(0.8)
		crt_overlay.set_glitch_intensity(0.15)

	_load_visitor(current_visitor_index)


func _connect_signals() -> void:
	if inspect_btn:
		inspect_btn.pressed.connect(_on_inspect_physical_pressed)
	if question_wounds_btn:
		question_wounds_btn.pressed.connect(_on_question_wounds_pressed)
	if question_story_btn:
		question_story_btn.pressed.connect(_on_question_story_pressed)
	if test_reaction_btn:
		test_reaction_btn.pressed.connect(_on_test_reaction_pressed)

	if let_in_btn:
		let_in_btn.pressed.connect(_on_let_in_pressed)
	if turn_away_btn:
		turn_away_btn.pressed.connect(_on_turn_away_pressed)
	if eliminate_btn:
		eliminate_btn.pressed.connect(_on_eliminate_pressed)
	if end_night_btn:
		end_night_btn.pressed.connect(_on_end_night_pressed)


func _update_resources_ui() -> void:
	var res: Dictionary = ResourceSystem.get_resources()
	if day_label:
		day_label.text = "DAY " + str(GameManager.current_day)
	if time_label:
		time_label.text = "TIME: " + current_time_guess()
	if food_label:
		food_label.text = "FOOD: " + str(res.get("food", 0))
	if water_label:
		water_label.text = "WATER: " + str(res.get("water", 0))
	if ammo_label:
		ammo_label.text = "AMMO: " + str(res.get("ammo", 0))
	if medicine_label:
		medicine_label.text = "MEDS: " + str(res.get("medicine", 0))
	if _hud_line:
		_hud_line.text = "NIGHT %d   %s   FOOD %d  WATER %d  AMMO %d  MEDS %d" % [
			GameManager.current_day, current_time_guess(),
			int(res.get("food", 0)), int(res.get("water", 0)),
			int(res.get("ammo", 0)), int(res.get("medicine", 0))]


func current_time_guess() -> String:
	# Night inspections happen in the small hours; keep the CRT feel.
	return "0%d:%02d AM" % [2 + current_visitor_index, 15 + (current_visitor_index * 7) % 40]


# --- queue + data wiring ----------------------------------------------------

func _init_visitor_queue() -> void:
	# The real queue, prepared by GameManager -> VisitorManager from visitors.json
	visitor_queue = VisitorManager.night_queue
	if visitor_queue.is_empty():
		VisitorManager.prepare_night_queue(GameManager.current_day)
		visitor_queue = VisitorManager.night_queue
	current_visitor_index = VisitorManager.current_visitor_index


func _load_visitor(index: int) -> void:
	if index >= visitor_queue.size():
		_show_no_more_visitors()
		return

	current_visitor = visitor_queue[index]
	suspicion_level = 0.1 + clampf(float(current_visitor.get("infection_progress", 0.0)), 0.0, 1.0) * 0.5
	revealed_signs = 0
	line_index = 0
	asked_about_marks = false
	studied_face = false
	visual_evidence_revealed = false

	if visitor_name_label:
		visitor_name_label.text = "SUBJECT: " + str(current_visitor.get("name", "UNKNOWN")).to_upper()
	if _speaker_label:
		_speaker_label.text = str(current_visitor.get("name", "UNKNOWN")).to_upper()
	for btn in [let_in_btn, turn_away_btn, eliminate_btn]:
		if btn:
			btn.visible = false  # judgment is earned through conversation
	if end_night_btn:
		end_night_btn.visible = false

	_update_diorama(false)

	# Reset glitch intensity for new visitor: infection_progress drives the
	# ambient unease — the more advanced the infection, the more the signal degrades.
	if crt_overlay:
		crt_overlay.set_glitch_intensity(suspicion_level)
		crt_overlay.trigger_glitch(0.3)

	# Opening knock, then the visitor's first beat hangs beside the figure.
	AudioManager.play_visitor_knock(current_visitor)
	SettingsManager.trigger_haptic_feedback(25)  # the knock, felt in the hand
	_seed_behavioral_log(["KNOCK DETECTED — subject at outer door."])
	_speak_line(0)

	_populate_physical_signs()
	_reset_question_buttons()
	_grab_tier_focus()
	_refresh_choices()


func _build_cinematic_ui() -> void:
	if not ViewPresets.ENABLED:
		return
	_cinematic = true
	for path in ["Background", "TopBar", "MainSplit", "BottomBar"]:
		var n := get_node_or_null(path)
		if n:
			n.visible = false

	_cinematic_view = SubViewportContainer.new()
	_cinematic_view.name = "CinematicView"
	_cinematic_view.stretch = true
	_cinematic_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cinematic_view)
	_cinematic_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(_cinematic_view, 0)

	_cinematic_vp = SubViewport.new()
	_cinematic_vp.name = "CinematicViewport"
	_cinematic_vp.size = Vector2i(1280, 720)
	_cinematic_vp.own_world_3d = true
	_cinematic_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cinematic_view.add_child(_cinematic_vp)

	_build_dialogue_panel()
	_build_hud()
	_build_notes()
	if crt_overlay:
		move_child(crt_overlay, get_child_count() - 1)

func _build_dialogue_panel() -> void:
	_dialogue_layer = Control.new()
	_dialogue_layer.name = "CinematicUI"
	_dialogue_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialogue_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialogue_layer)

	var panel := PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.anchor_left = 0.48
	panel.anchor_top = 0.56
	panel.anchor_right = 0.97
	panel.anchor_bottom = 0.95
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.022, 0.016, 0.88)
	style.border_color = Color(0.22, 0.34, 0.25, 0.90)
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	_dialogue_layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	_speaker_label = Label.new()
	_speaker_label.text = "THE DOOR"
	_speaker_label.add_theme_font_size_override("font_size", 13)
	_speaker_label.add_theme_color_override("font_color", Color(0.48, 0.66, 0.50))
	vb.add_child(_speaker_label)

	_dialogue_text = Label.new()
	_dialogue_text.text = ""
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text.custom_minimum_size = Vector2(0, 92)
	_dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_text.add_theme_font_size_override("font_size", 20)
	_dialogue_text.add_theme_color_override("font_color", Color(0.86, 0.93, 0.84))
	vb.add_child(_dialogue_text)

	var rule := ColorRect.new()
	rule.color = Color(0.20, 0.32, 0.22, 0.80)
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)

	_choice_row = HBoxContainer.new()
	_choice_row.alignment = BoxContainer.ALIGNMENT_END
	_choice_row.add_theme_constant_override("separation", 22)
	vb.add_child(_choice_row)

func _build_hud() -> void:
	_hud_line = Label.new()
	_hud_line.position = Vector2(28, 22)
	_hud_line.add_theme_font_size_override("font_size", 14)
	_hud_line.add_theme_color_override("font_color", Color(0.55, 0.72, 0.55, 0.85))
	_dialogue_layer.add_child(_hud_line)

func _build_notes() -> void:
	_notes_button = Button.new()
	_notes_button.text = "LOG"
	_notes_button.flat = true
	_notes_button.add_theme_font_size_override("font_size", 14)
	_notes_button.add_theme_color_override("font_color", Color(0.55, 0.75, 0.55))
	_dialogue_layer.add_child(_notes_button)
	_notes_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_notes_button.pressed.connect(_toggle_notes)

	_notes_panel = PanelContainer.new()
	_notes_panel.anchor_left = 0.62
	_notes_panel.anchor_top = 0.08
	_notes_panel.anchor_right = 0.97
	_notes_panel.anchor_bottom = 0.50
	_notes_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.022, 0.016, 0.94)
	style.border_color = Color(0.22, 0.34, 0.25, 0.90)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	_notes_panel.add_theme_stylebox_override("panel", style)
	_dialogue_layer.add_child(_notes_panel)

	_notes_text = RichTextLabel.new()
	_notes_text.bbcode_enabled = true
	_notes_text.scroll_active = true
	_notes_text.add_theme_font_size_override("normal_font_size", 13)
	_notes_panel.add_child(_notes_text)

func _toggle_notes() -> void:
	if _notes_panel:
		_notes_panel.visible = not _notes_panel.visible

func _setup_aperture_view() -> void:
	if not ViewPresets.ENABLED:
		return
	var vp: SubViewport = _cinematic_vp
	if vp == null and diorama != null:
		vp = diorama.get_parent() as SubViewport
	if vp == null:
		return
	aperture_stage = ApertureStage.new()
	aperture_stage.name = "ApertureStage"
	vp.add_child(aperture_stage)
	aperture_stage.set_active(false)
	if diorama and diorama.camera:
		diorama.camera.current = false if _cinematic else true

func _use_aperture() -> bool:
	return aperture_stage != null

func _view_environment() -> String:
	var env := str(current_visitor.get("view_environment", "env_porch_night"))
	if not ViewPresets.is_compatible("doorway", env):
		env = "env_porch_night"
	return env

func _activate_aperture(active: bool) -> void:
	if aperture_stage == null:
		return
	aperture_stage.set_active(active)
	if diorama:
		diorama.visible = not active and not _cinematic
		diorama.set_environment_enabled(not active and not _cinematic)
		if diorama.camera:
			diorama.camera.current = not active and not _cinematic

func _update_aperture(revealed: bool) -> void:
	var signs: Array = current_visitor.get("assigned_signs", [])
	aperture_stage.set_view("doorway", _view_environment(), str(current_visitor.get("id", "")))
	aperture_stage.set_visitor(current_visitor, signs)
	aperture_stage.set_corruption(suspicion_level)
	_activate_aperture(true)
	if revealed:
		aperture_stage.reveal()
	if portrait_art:
		portrait_art.visible = false

func _update_diorama(revealed: bool) -> void:
	if _use_aperture():
		_update_aperture(revealed)
		return
	if diorama == null:
		return
	if revealed:
		diorama.reveal()
		_update_portrait(true)
		return
	diorama.show_visitor(current_visitor, current_visitor.get("assigned_signs", []))
	diorama.set_corruption(suspicion_level)
	_update_portrait(false)


## The visitor's PNG art hangs over the door viewport — the uncanny face
## you actually judge. Swaps to the reveal variant when scrutiny (or a
## lethal mistake) strips the mask.
func _update_portrait(revealed: bool) -> void:
	if _use_aperture():
		if portrait_art:
			portrait_art.visible = false
		return
	if portrait_art == null or current_visitor.is_empty():
		return
	var path := str(current_visitor.get("portrait", ""))
	if revealed and str(current_visitor.get("reveal_portrait", "")) != "":
		path = str(current_visitor.get("reveal_portrait", ""))
	if path == "" or not ResourceLoader.exists(path):
		portrait_art.visible = false
		return
	portrait_art.texture = load(path) as Texture2D
	portrait_art.visible = true


## Shows one conversation beat beside the figure. dialogue_chain holds plain
## strings; beat 0 is stage direction, the rest are the visitor's words.
func _speak_line(i: int) -> void:
	var beats: Array = current_visitor.get("dialogue_chain", [])
	if i < 0 or i >= beats.size():
		if question_story_btn:
			question_story_btn.disabled = true
		return
	line_index = i
	var beat := str(beats[i])
	var shown := beat if i == 0 else "\"%s\"" % beat
	if status_label:
		status_label.add_theme_color_override("font_color", Color(0.667, 1.0, 0.667, 1.0))
	_add_behavioral_note(shown)  # mirrors to the dialogue line with typewriter
	_update_conversation_tiers()
	if question_story_btn and i >= beats.size() - 1:
		question_story_btn.disabled = true


# --- physical signs panel (assigned signs from signs.json) -------------------

func _populate_physical_signs() -> void:
	if not physical_signs_container:
		return

	for child in physical_signs_container.get_children():
		child.queue_free()

	var signs: Array = current_visitor.get("assigned_signs", [])
	var shown: int = 0

	for i in signs.size():
		if i >= revealed_signs:
			break
		shown += 1
		var s: Dictionary = signs[i]
		var weight := float(s.get("infection_weight", 0.0))
		var lbl := Label.new()
		lbl.text = "• " + str(s.get("name", s.get("id", "UNKNOWN"))).to_upper() \
			+ "\n  " + str(s.get("description", ""))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color",
			Color(1.0, 0.8, 0.2, 1.0) if weight >= 0.6 else Color(0.667, 1.0, 0.667, 1.0))
		physical_signs_container.add_child(lbl)

	if shown == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "[Nothing examined yet.\nLook them over.]"
		empty_lbl.add_theme_color_override("font_color", Color(0.3, 0.6, 0.3, 0.8))
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		physical_signs_container.add_child(empty_lbl)


# --- behavioral log ---------------------------------------------------------

func _seed_behavioral_log(lines: Array) -> void:
	if behavioral_notes_text:
		behavioral_notes_text.clear()
		behavioral_notes_text.append_text("[b][u]INSPECTION LOG[/u][/b]\n\n")
		for note in lines:
			behavioral_notes_text.append_text("[color=#aaffaa]> " + str(note) + "[/color]\n\n")
	if _notes_text:
		_notes_text.clear()
		_notes_text.append_text("[b]INSPECTION LOG[/b]\n\n")
		for note in lines:
			_notes_text.append_text("[color=#aaffaa]> " + str(note) + "[/color]\n\n")


func _add_behavioral_note(note_text: String) -> void:
	if behavioral_notes_text:
		behavioral_notes_text.append_text("[color=#aaffaa]> " + note_text + "[/color]\n\n")
	if _notes_text:
		_notes_text.append_text("[color=#aaffaa]> " + note_text + "[/color]\n\n")
	# The latest line doubles as the floating door dialogue — like the
	# reference's "You alone?" moment hanging beside the figure.
	if status_label and not note_text.begins_with("[color"):
		_say(note_text)


var _say_tween: Tween
var _say_blips: int = 0

## Dialogue line with typewriter reveal — suspense lives in the pacing.
func _say(text: String) -> void:
	if status_label == null and _dialogue_text == null:
		return
	if _say_tween and _say_tween.is_valid():
		_say_tween.kill()
	if question_story_btn:
		question_story_btn.disabled = true  # LISTEN espera o typewriter acabar
	if status_label:
		status_label.text = text
		status_label.visible_ratio = 0.0
	if _dialogue_text:
		_dialogue_text.text = text
		_dialogue_text.visible_ratio = 0.0
	_say_blips = 0
	var dur := clampf(text.length() * 0.018, 0.3, 2.5)
	_say_tween = create_tween()
	if status_label:
		_say_tween.tween_property(status_label, "visible_ratio", 1.0, dur)
	if _dialogue_text:
		if status_label:
			_say_tween.parallel().tween_property(_dialogue_text, "visible_ratio", 1.0, dur)
		else:
			_say_tween.tween_property(_dialogue_text, "visible_ratio", 1.0, dur)
	_say_tween.finished.connect(_on_say_finished)


func _process(_delta: float) -> void:
	if _say_tween == null or not _say_tween.is_valid() or not _say_tween.is_running():
		return
	if status_label == null or status_label.text.is_empty():
		return
	var shown := int(status_label.visible_ratio * status_label.text.length())
	while _say_blips + 3 <= shown:
		_say_blips += 3
		AudioManager.play_sfx("ui_hover")  # blip de voz com cue curto existente


func _on_say_finished() -> void:
	if question_story_btn:
		var beats: Array = current_visitor.get("dialogue_chain", [])
		question_story_btn.disabled = line_index >= beats.size() - 1
	_refresh_choices()


# Moldura + scanlines sutis sobre o retrato, no verde do tema terminal.
func _frame_portrait() -> void:
	if portrait_art == null or portrait_art.has_meta("framed"):
		return
	portrait_art.set_meta("framed", true)
	var edge := Color(0.0, 0.9, 0.45, 0.6)
	_frame_bar(edge, 0.0, 0.0, 1.0, 0.0, Vector4(0, 0, 0, 2))
	_frame_bar(edge, 0.0, 1.0, 1.0, 1.0, Vector4(0, -2, 0, 0))
	_frame_bar(edge, 0.0, 0.0, 0.0, 1.0, Vector4(0, 0, 2, 0))
	_frame_bar(edge, 1.0, 0.0, 1.0, 1.0, Vector4(-2, 0, 0, 0))
	var scan := Color(0.0, 0.0, 0.0, 0.18)
	for i in 6:
		var y := float(i + 1) / 7.0
		_frame_bar(scan, 0.0, y, 1.0, y, Vector4(0, 0, 0, 1))


func _frame_bar(col: Color, al: float, at: float, ar: float, ab: float, off: Vector4) -> void:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = al
	r.anchor_top = at
	r.anchor_right = ar
	r.anchor_bottom = ab
	r.offset_left = off.x
	r.offset_top = off.y
	r.offset_right = off.z
	r.offset_bottom = off.w
	portrait_art.add_child(r)


# D-pad/mesa: primeiro botão visível da conversa recebe o foco.
func _grab_tier_focus() -> void:
	if get_viewport() == null:
		return
	if _cinematic:
		for b in _choice_buttons:
			if b.visible and not b.disabled:
				b.grab_focus()
				return
		return
	var owner := get_viewport().gui_get_focus_owner() as Button
	if owner != null and owner.visible and not owner.disabled:
		return
	for btn in [question_story_btn, question_wounds_btn, inspect_btn, test_reaction_btn,
			let_in_btn, turn_away_btn, eliminate_btn, end_night_btn]:
		if btn != null and btn.visible and not btn.disabled:
			btn.grab_focus()
			return

## A button earns its place: pop-in the first time its tier unlocks.
func _reveal_button(btn: Button) -> void:
	if btn == null or btn.visible:
		return
	btn.visible = true
	btn.modulate.a = 0.0
	btn.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(btn, "modulate:a", 1.0, 0.35)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Conversation tiers (NIAH flow): LISTEN first; examining verbs appear once
## the visitor has spoken; judgment appears once you know something.
func _update_conversation_tiers() -> void:
	var heard := line_index >= 1
	var probed := asked_about_marks or revealed_signs >= 1 or studied_face
	if heard:
		_reveal_button(question_wounds_btn)
		_reveal_button(inspect_btn)
	if probed:
		_reveal_button(test_reaction_btn)
		_reveal_button(let_in_btn)
		_reveal_button(turn_away_btn)
		_reveal_button(eliminate_btn)
	_grab_tier_focus()
	_refresh_choices()


func _reset_question_buttons() -> void:
	for btn in [inspect_btn, question_wounds_btn, question_story_btn, test_reaction_btn]:
		if btn:
			btn.disabled = false
			btn.visible = btn == question_story_btn  # LISTEN first; rest is earned
			btn.modulate.a = 1.0
			btn.scale = Vector2.ONE
	_refresh_choices()


func _increase_suspicion(delta: float) -> void:
	suspicion_level = clampf(suspicion_level + delta, 0.0, 1.0)
	if _use_aperture():
		aperture_stage.set_corruption(suspicion_level)
	elif diorama and diorama.has_model():
		diorama.set_corruption(suspicion_level)
	if crt_overlay:
		crt_overlay.set_glitch_intensity(suspicion_level)
		if delta > 0.15:
			crt_overlay.trigger_glitch(0.4)
			AudioManager.play_glitch(1 if delta < 0.25 else 2)


# --- inspection actions: a conversation, not a checklist ---------------------

## LOOK THEM OVER — each press notices one more assigned sign on the figure.
func _on_inspect_physical_pressed() -> void:
	var signs: Array = current_visitor.get("assigned_signs", [])
	if revealed_signs < signs.size():
		var s: Dictionary = signs[revealed_signs]
		revealed_signs += 1
		AudioManager.play_ui_cue("reveal_sign")
		_populate_physical_signs()
		var finding := "%s — %s" % [s.get("name", ""), s.get("description", "")]
		_say(finding)
		if float(s.get("infection_weight", 0.0)) >= 0.6:
			_increase_suspicion(0.2)
		else:
			_increase_suspicion(0.05)
		_add_behavioral_note("Noticed: " + finding)
		if _use_aperture():
			aperture_stage.show_sign(s)
		elif diorama:
			diorama.show_sign(s)
		_check_visual_evidence()
		_update_conversation_tiers()
		return
	_say("Nothing more to see with the naked eye.")
	if inspect_btn:
		inspect_btn.disabled = true


## LISTEN — the visitor keeps talking through their beats.
func _on_question_story_pressed() -> void:
	_speak_line(line_index + 1)
	_increase_suspicion(0.05)


## ASK ABOUT THE MARKS — close questioning draws out the authored reveal.
func _on_question_wounds_pressed() -> void:
	var reveal := str(current_visitor.get("reveal_on_inspection", ""))
	if reveal != "" and not asked_about_marks:
		asked_about_marks = true
		_say("\"%s\"" % reveal)
		_add_behavioral_note("Pressed about the marks: \"%s\"" % reveal)
		_increase_suspicion(0.2)
		_check_visual_evidence()
		_update_conversation_tiers()
		return
	_say("They repeat themselves. Nothing new.")
	_add_behavioral_note("Pressed about the marks — nothing new.")
	if question_wounds_btn:
		question_wounds_btn.disabled = true


## STUDY THEIR FACE — hold their gaze; the wrong ones give it away.
func _on_test_reaction_pressed() -> void:
	if studied_face:
		return
	studied_face = true
	_say("You hold their gaze. They do not blink when they should.")
	_add_behavioral_note("Held their gaze a beat too long.")
	_increase_suspicion(0.15)
	_check_visual_evidence()
	_update_conversation_tiers()
	if test_reaction_btn:
		test_reaction_btn.disabled = true


func _check_visual_evidence() -> void:
	# Visual evidence uncovered on an actually-infected subject: the portrait
	# degrades into the reveal variant — what you see when you look closer.
	# Only after real scrutiny: every sign noticed, the marks asked about,
	# or a long held gaze.
	if visual_evidence_revealed:
		return
	if not current_visitor.get("is_actually_infected", false):
		return
	if current_visitor.get("reveal_portrait", "") == "":
		return
	var signs: Array = current_visitor.get("assigned_signs", [])
	var scrutinized := asked_about_marks or studied_face \
		or (not signs.is_empty() and revealed_signs >= signs.size())
	if not scrutinized:
		return
	visual_evidence_revealed = true
	_update_diorama(true)
	SettingsManager.trigger_haptic_feedback(90)  # the mask slips — strongest buzz
	if crt_overlay:
		crt_overlay.trigger_glitch(0.8)
	AudioManager.play_glitch(3)
	_add_behavioral_note("…Something about the subject's face is not right.")


# --- decisions (authored consequences) ---------------------------------------

## Bridges the authored-consequences flow to VisitorManager: feeds flags,
## decision history and key-visitor milestones (Dr. Thorne / cure subjects).
## Syncs the local visitor into the manager first — process_decision only
## acts on the manager's own current_visitor, otherwise the decision is a no-op.
func _record_decision(decision: VisitorManager.Decision, is_infected: bool) -> void:
	if current_visitor.is_empty():
		return  # night-complete state: no one at the door, nothing to judge
	current_visitor["is_infected"] = is_infected
	VisitorManager.current_visitor = current_visitor
	VisitorManager.current_visitor_index = current_visitor_index
	var entry: Dictionary = VisitorManager.process_decision(decision)
	if entry.is_empty():
		return
	match decision:
		VisitorManager.Decision.LET_IN:
			var vid := str(current_visitor.get("id", ""))
			if vid == "v009":
				FlagsManager.set_flag("admitted_dr_thorne", true)
			if vid == "v006" or vid == "v020":
				FlagsManager.set_flag("admitted_cure_subject", true)
			if is_infected and int(FlagsManager.get_flag("infected_let_in", 0)) >= 3:
				FlagsManager.set_flag("player_infected", true)

func _on_let_in_pressed() -> void:
	_set_decisions_enabled(false)
	AudioManager.play_decision("let_in")
	var is_infected: bool = current_visitor.get("is_actually_infected", current_visitor.get("is_infected", false))
	var cons: Dictionary = (current_visitor.get("consequences", {}) as Dictionary).get("let_in", {})

	_record_decision(VisitorManager.Decision.LET_IN, is_infected)
	_apply_consequences(cons)

	if is_infected:
		_update_diorama(true)
		_say("[CRITICAL WARNING: INFECTED SUBJECT ADMITTED!]")
		SettingsManager.trigger_haptic_feedback(70)
		if status_label:
			status_label.add_theme_color_override("font_color", Color(1.0, 0.267, 0.267, 1.0))
		if crt_overlay:
			crt_overlay.set_glitch_intensity(0.9)
			crt_overlay.trigger_glitch(1.2)
	else:
		_say("\"Inside. Now.\" — the door shuts behind them.")
		if status_label:
			status_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.255, 1.0))
		if crt_overlay:
			crt_overlay.trigger_glitch(0.2)

	_show_consequence_summary(cons)
	get_tree().create_timer(2.0).timeout.connect(_next_visitor)


func _on_turn_away_pressed() -> void:
	_set_decisions_enabled(false)
	AudioManager.play_decision("turn_away")
	var cons: Dictionary = (current_visitor.get("consequences", {}) as Dictionary).get("turned_away", {})
	_record_decision(VisitorManager.Decision.TURN_AWAY, current_visitor.get("is_actually_infected", current_visitor.get("is_infected", false)))
	_apply_consequences(cons)

	_say("\"No room. Keep walking.\" — the dark takes them back.")
	if status_label:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0, 1.0))

	if crt_overlay:
		crt_overlay.trigger_glitch(0.4)

	_show_consequence_summary(cons)
	get_tree().create_timer(1.8).timeout.connect(_next_visitor)


func _on_eliminate_pressed() -> void:
	_set_decisions_enabled(false)
	AudioManager.play_decision("eliminate")
	var cons: Dictionary = (current_visitor.get("consequences", {}) as Dictionary).get("eliminated", {})
	_record_decision(VisitorManager.Decision.ELIMINATE, current_visitor.get("is_actually_infected", current_visitor.get("is_infected", false)))
	_apply_consequences(cons)

	# The round is spent inside VisitorManager.process_decision; refresh only.
	_update_resources_ui()

	_say("One shot. The knocking stops.")
	SettingsManager.trigger_haptic_feedback(50)
	if status_label:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.267, 0.267, 1.0))

	if crt_overlay:
		crt_overlay.trigger_glitch(1.0)

	_show_consequence_summary(cons)
	get_tree().create_timer(2.0).timeout.connect(_next_visitor)


func _apply_consequences(cons: Dictionary) -> void:
	if cons.is_empty():
		return
	GameManager.trust_value = GameManager.trust_value + int(cons.get("trust_change", 0))
	GameManager.corruption_value = clampi(GameManager.corruption_value + int(cons.get("corruption_change", 0)), 0, 100)
	var rc: Dictionary = cons.get("resource_change", {})
	if rc is Dictionary and not rc.is_empty():
		ResourceSystem.add_resources(rc)
	_update_resources_ui()


func _show_consequence_summary(cons: Dictionary) -> void:
	var summary: String = str(cons.get("summary", ""))
	if summary != "":
		_add_behavioral_note("OUTCOME: " + summary)


func _set_decisions_enabled(enabled: bool) -> void:
	if let_in_btn: let_in_btn.disabled = not enabled
	if turn_away_btn: turn_away_btn.disabled = not enabled
	if eliminate_btn: eliminate_btn.disabled = not enabled
	_refresh_choices()


func _next_visitor() -> void:
	current_visitor_index += 1
	VisitorManager.current_visitor_index = current_visitor_index
	_set_decisions_enabled(true)
	_load_visitor(current_visitor_index)


func _show_no_more_visitors() -> void:
	AudioManager.play_sfx("day_transition")
	current_visitor = {}  # no one left at the door; decisions are guarded
	# Hide the whole conversation: nothing left to ask or judge.
	for btn in [let_in_btn, turn_away_btn, eliminate_btn, inspect_btn,
			question_wounds_btn, question_story_btn, test_reaction_btn]:
		if btn:
			btn.visible = false
	if _use_aperture():
		aperture_stage.clear_visitor()  # empty doorway; the figure is gone
	elif diorama:
		diorama.clear_visitor()
	if portrait_art:
		portrait_art.visible = false  # no one left to look at
	var briefing := _night_briefing()
	if visitor_name_label:
		visitor_name_label.text = "CHECKPOINT CLEAR — NIGHT %d SURVIVED" % GameManager.current_day
	_say("[NIGHT SURVIVED — RETURN HOME, CHECK ON THE HOUSE, THEN SLEEP]")
	_add_behavioral_note("[color=#aaffaa]NIGHT %d COMPLETE. SHELTER HOLDS. %s[/color]" % [GameManager.current_day, briefing])
	_add_behavioral_note("[color=#aaffaa]Press RETURN HOME — inside you can peek at rooms, the window, and sleep.[/color]")
	if end_night_btn:
		end_night_btn.visible = true
	if _speaker_label:
		_speaker_label.text = "THE DOOR"
	_grab_tier_focus()
	_refresh_choices()


## Rebuilds the choice row from the conversation tier. The decision tier shows
## the two lines from the reference ("Come in." / "You better leave.") plus
## ELIMINATE only when the weapon option is actually available.
func _refresh_choices() -> void:
	if _choice_row == null:
		return
	for child in _choice_row.get_children():
		_choice_row.remove_child(child)
		child.queue_free()
	_choice_buttons.clear()

	if current_visitor.is_empty():
		if end_night_btn and end_night_btn.visible:
			_add_choice("Return home.", "end_night")
		return

	if let_in_btn and let_in_btn.visible and let_in_btn.disabled:
		return

	if let_in_btn and let_in_btn.visible:
		_add_choice("Come in.", "let_in")
		_add_choice("You better leave.", "turn_away")
		if eliminate_btn and eliminate_btn.visible:
			_add_choice("Eliminate.", "eliminate", true)
		return

	if question_story_btn and question_story_btn.visible and not question_story_btn.disabled:
		_add_choice("Listen.", "listen")
	if inspect_btn and inspect_btn.visible and not inspect_btn.disabled:
		_add_choice("Look them over.", "inspect")
	if question_wounds_btn and question_wounds_btn.visible and not question_wounds_btn.disabled:
		_add_choice("Ask about the wounds.", "wounds")
	if test_reaction_btn and test_reaction_btn.visible and not test_reaction_btn.disabled:
		_add_choice("Study their face.", "study")

func _add_choice(text: String, id: String, danger: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 18)
	var col := Color(1.0, 0.42, 0.34) if danger else Color(0.72, 1.0, 0.72)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	b.pressed.connect(_on_choice.bind(id))
	_choice_row.add_child(b)
	_choice_buttons.append(b)

func _on_choice(id: String) -> void:
	match id:
		"listen":
			_on_question_story_pressed()
		"inspect":
			_on_inspect_physical_pressed()
		"wounds":
			_on_question_wounds_pressed()
		"study":
			_on_test_reaction_pressed()
		"let_in":
			_on_let_in_pressed()
		"turn_away":
			_on_turn_away_pressed()
		"eliminate":
			_on_eliminate_pressed()
		"end_night":
			_on_end_night_pressed()
			return
	_refresh_choices()

func _night_briefing() -> String:
	var nights: Array = StoryManager.story_data.get("nights", [])
	for n in nights:
		if int(n.get("night_number", 0)) == GameManager.current_day:
			return "[NIGHT BRIEFING] " + str(n.get("briefing", ""))
	return ""


func _on_end_night_pressed() -> void:
	VisitorManager.night_completed = true
	SceneManager.change_scene(GameManager.HOUSE_SCENE_PATH)
