extends Node

## Stairwell verification shots: `godot --path . -- --stairshot` (real window).
## One fresh scene per shot with the day set first, so unlocked floors match.

var _idx := 0

const SHOTS := [
	# [name, day, cam_pos, look_at]
	["s1_day1_stairwell_sw", 1, Vector3(-2.0, 1.7, 0.5), Vector3(2.3, 1.2, 0.0)],
	["s2_day1_stair_base", 1, Vector3(0.6, 1.5, 1.4), Vector3(2.3, 0.6, 2.4)],
	["s3_day3_landing", 3, Vector3(-1.0, 4.4, -1.0), Vector3(2.3, 3.2, -2.5)],
	["s4_day5_attic_landing", 5, Vector3(-1.0, 7.6, -1.0), Vector3(2.3, 6.4, -2.5)],
	["s5_day7_basement_foot", 7, Vector3(-0.5, -1.6, -0.6), Vector3(2.3, -2.8, -2.2)],
]

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	_next()

func _next() -> void:
	if _idx >= SHOTS.size():
		print("[stairshot] done")
		get_tree().quit()
		return
	GameManager.current_day = SHOTS[_idx][1]
	GameManager.tv_watched_today = true
	var scene = load("res://scenes/house/HouseScene.tscn").instantiate()
	get_tree().root.add_child(scene)
	for i in range(40):
		await get_tree().process_frame
	if scene.has_method("_on_popup_action"):
		scene._on_popup_action("close")
		for i in range(5):
			await get_tree().process_frame
	var cam := Camera3D.new()
	# The house renders inside its own SubViewport — the rig must live there,
	# a root-level camera never gets picked up by that viewport.
	scene.get_node("View3D/SubViewport").add_child(cam)
	cam.position = SHOTS[_idx][2]
	cam.look_at(SHOTS[_idx][3])
	cam.current = true
	for i in range(8):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path: String = "user://screenshots/" + SHOTS[_idx][0] + ".png"
	img.save_png(path)
	print("[stairshot] " + path)
	cam.queue_free()
	scene.queue_free()
	_idx += 1
	await get_tree().process_frame
	_next()
