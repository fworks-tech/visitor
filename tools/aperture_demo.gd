extends Node

## Aperture view playground: `godot --path . -- --aperture-demo`
## Cycles aperture (A/D), environment (W/S) and visitor (V) to preview the
## composite before wiring it into InspectionScene or HouseScene.

var stage: ApertureStage
var label: Label
var aps: Array = []
var all_envs: Array = []
var envs: Array = []
var visitors: Array = []
var ai := 0
var ei := 0
var vi := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	aps = ViewPresets.aperture_ids()
	all_envs = ViewPresets.environment_ids()
	visitors = _load_visitors()
	_build()
	await get_tree().process_frame
	_rebuild_envs()
	_refresh()
	if "--aperture-shot" in OS.get_cmdline_user_args():
		await _capture_shots()
		get_tree().quit()

func _build() -> void:
	var view_layer := CanvasLayer.new()
	view_layer.layer = 0
	add_child(view_layer)

	var root := Control.new()
	view_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false

	var container := SubViewportContainer.new()
	container.stretch = true
	root.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(vp)

	stage = ApertureStage.new()
	vp.add_child(stage)

	var ui := CanvasLayer.new()
	ui.layer = 20
	add_child(ui)

	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(440, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.02, 0.88)
	style.border_color = Color(0.28, 0.40, 0.30, 1.0)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "APERTURE VIEW DEMO"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.82, 0.92, 0.82))
	vb.add_child(title)

	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.70, 0.82, 0.70))
	vb.add_child(label)

	var hint := Label.new()
	hint.text = "A/D aperture   W/S environment   V visitor   Esc quit"
	hint.add_theme_color_override("font_color", Color(0.50, 0.62, 0.50))
	vb.add_child(hint)

func _capture_shots() -> void:
	DirAccess.make_dir_recursive_absolute("res://demo_shots")
	var shots := [
		{"ap": "peephole", "env": "env_porch_night", "visitor": -1, "name": "00_peephole_porch_empty"},
		{"ap": "peephole", "env": "env_porch_night", "visitor": 0, "name": "01_peephole_porch"},
		{"ap": "peephole", "env": "env_road_fog", "visitor": 3, "name": "02_peephole_road"},
		{"ap": "window", "env": "env_yard_night", "visitor": -1, "name": "03_window_yard"},
		{"ap": "door_crack", "env": "env_hallway", "visitor": 9, "name": "04_crack_hallway"},
		{"ap": "hatch", "env": "env_basement", "visitor": 12, "name": "05_hatch_basement"},
	]
	for shot in shots:
		var ap := str(shot["ap"])
		var env := str(shot["env"])
		var idx: int = int(shot["visitor"])
		var visitor: Dictionary = visitors[idx] if idx >= 0 and idx < visitors.size() else {}
		stage.set_view(ap, env, str(visitor.get("id", "")))
		stage.set_visitor(visitor, [])
		stage.set_active(true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := stage.get_viewport().get_texture().get_image()
		var path := "res://demo_shots/%s.png" % str(shot["name"])
		var err := img.save_png(path)
		print("SHOT %s -> %s" % [path, error_string(err)])

func _load_visitors() -> Array:
	var f := FileAccess.open("res://assets/data/visitors.json", FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var list = parsed.get("visitors", [])
		return list if list is Array else []
	if parsed is Array:
		return parsed
	return []

func _rebuild_envs() -> void:
	envs.clear()
	if aps.is_empty():
		return
	var ap := str(aps[ai])
	for e in all_envs:
		if ViewPresets.is_compatible(ap, str(e)):
			envs.append(e)
	if envs.is_empty():
		envs = all_envs.duplicate()
	ei = clampi(ei, 0, maxi(0, envs.size() - 1))

func _refresh() -> void:
	if stage == null or aps.is_empty() or envs.is_empty():
		return
	var ap := str(aps[ai])
	var env := str(envs[ei])
	var visitor: Dictionary = visitors[vi] if vi < visitors.size() else {}
	stage.set_view(ap, env, str(visitor.get("id", "")))
	stage.set_visitor(visitor, [])
	var preset := stage.get_preset()
	label.text = "Aperture: %s\nEnvironment: %s\nVisitor: %s" % [
		str(preset.get("aperture_label", ap)),
		str(preset.get("environment_label", env)),
		str(visitor.get("name", "none")),
	]

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_A:
			ai = wrapi(ai - 1, 0, aps.size())
			_rebuild_envs()
			_refresh()
		KEY_D:
			ai = wrapi(ai + 1, 0, aps.size())
			_rebuild_envs()
			_refresh()
		KEY_W:
			ei = wrapi(ei + 1, 0, envs.size())
			_refresh()
		KEY_S:
			ei = wrapi(ei - 1, 0, envs.size())
			_refresh()
		KEY_V:
			if not visitors.is_empty():
				vi = wrapi(vi + 1, 0, visitors.size())
				_refresh()
		KEY_ESCAPE:
			get_tree().quit()
