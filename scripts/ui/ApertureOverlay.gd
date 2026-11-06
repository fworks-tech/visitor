class_name ApertureOverlay
extends Control

## Full-screen window / crack / hatch view used from HouseScene. One
## SubViewport with an ApertureStage, a title card and a way back.
## The house freezes while this is open (see HouseScene._open_window_aperture).

signal closed

var stage: ApertureStage
var title_label: Label
var subtitle_label: Label
var caption_label: Label
var _viewport: SubViewport

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var container := SubViewportContainer.new()
	container.stretch = true
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(_viewport)

	stage = ApertureStage.new()
	_viewport.add_child(stage)
	stage.set_active(false)

	var card := PanelContainer.new()
	card.position = Vector2(24, 24)
	card.custom_minimum_size = Vector2(360, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.02, 0.88)
	style.border_color = Color(0.24, 0.36, 0.27, 1.0)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	title_label = Label.new()
	title_label.text = "WINDOW"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.82, 0.92, 0.82))
	vb.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.add_theme_color_override("font_color", Color(0.55, 0.68, 0.55))
	vb.add_child(subtitle_label)

	caption_label = Label.new()
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.custom_minimum_size = Vector2(340, 0)
	caption_label.add_theme_color_override("font_color", Color(0.68, 0.80, 0.68))
	caption_label.visible = false
	vb.add_child(caption_label)

	var hint := Label.new()
	hint.text = "E / ESC to step back"
	hint.add_theme_color_override("font_color", Color(0.45, 0.58, 0.45))
	vb.add_child(hint)

	var back := Button.new()
	back.text = "STEP BACK"
	back.custom_minimum_size = Vector2(180, 44)
	back.pressed.connect(close)
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)

func open(aperture_id: String, environment_id: String, title: String = "WINDOW", caption: String = "") -> void:
	if stage == null:
		return
	title_label.text = title
	stage.set_view(aperture_id, environment_id)
	stage.set_visitor({})
	stage.set_active(true)
	var preset := stage.get_preset()
	subtitle_label.text = str(preset.get("environment_label", environment_id))
	caption_label.text = caption
	caption_label.visible = caption != ""
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_focus()

func back_focus() -> void:
	for child in get_children():
		if child is Button:
			(child as Button).grab_focus()
			return

func close() -> void:
	if not visible:
		return
	visible = false
	stage.set_active(false)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	closed.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE or key == KEY_E:
			close()
			get_viewport().set_input_as_handled()
