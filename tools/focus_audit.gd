extends SceneTree

## Focus audit: the crosshair ray must select exactly the object under it.
## Canned camera poses — one per interactable, plus blank-wall poses that
## must focus nothing (the reported bug: label showing while staring at a
## bare wall between props).
##   godot --headless --path <project> --script res://tools/focus_audit.gd
## Prints PASS/FAIL per pose; exit code 1 on any wrong focus.
## (Plain script: dynamic access only, so --script mode compiles it.)

var fails := 0
var passes := 0

const BEDROOM := Vector3(-6.25, 0, 0)
const HALL := Vector3(0, 0, 0)
const KITCHEN := Vector3(6.0, 0, 0)
const OFFICE := Vector3(0, 0, -6.0)
const BATHROOM := Vector3(0, 0, 5.5)

# [pose, cam offset from room base, look target offset, expected id or ""].
var poses := [
	["radio on table", BEDROOM, Vector3(0.2, 1.65, 0.2), Vector3(-0.85, 0.6, -1.6), "radio"],
	["bedroom blank wall", BEDROOM, Vector3(0.2, 1.65, 0.2), Vector3(0.0, 1.4, -2.0), ""],
	["tv panel", BEDROOM, Vector3(0.2, 1.65, 0.0), Vector3(1.95, 1.0, -1.2), "tv"],
	["front door", HALL, Vector3(-0.9, 1.65, 1.2), Vector3(-1.8, 1.5, 2.9), "front_door"],
	["hall blank wall", HALL, Vector3(-0.9, 1.65, 1.2), Vector3(-0.6, 1.5, 2.9), ""],
	["window", HALL, Vector3(0.6, 1.65, -0.8), Vector3(1.8, 1.8, -2.9), "window"],
	["kitchen sink", KITCHEN, Vector3(0.0, 1.65, 0.8), Vector3(1.55, 0.9, -0.1), "scavenge"],
	["office barricade", OFFICE, Vector3(0.2, 1.65, 0.0), Vector3(-0.9, 1.2, -1.9), "fortify"],
	["mirror", BATHROOM, Vector3(-0.5, 1.65, 0.0), Vector3(1.0, 1.7, -1.43), "mirror"],
	["bathroom blank", BATHROOM, Vector3(0.0, 1.65, 0.0), Vector3(-1.1, 0.7, 0.5), ""],
]

func _init() -> void:
	_run()

func _run() -> void:
	for i in range(20):
		await process_frame
	var packed: PackedScene = load("res://scenes/house/HouseScene.tscn")
	var scene = packed.instantiate()
	root.add_child(scene)
	for i in range(30):
		await process_frame
	var house3d: Node = scene.get_node("View3D/SubViewport/House3D")
	for p in poses:
		_check(house3d, p[0], p[1] + p[2], p[1] + p[3], p[4])
	printerr("FOCUS: %d PASS, %d FAIL" % [passes, fails])
	quit(1 if fails > 0 else 0)

func _check(house3d: Node, pose_name: String, cam: Vector3, target: Vector3, expected: String) -> void:
	var fwd := (target - cam).normalized()
	var res: Dictionary = house3d.call("get_focus", cam, fwd)
	var got := str(res.get("id", ""))
	if got == expected:
		passes += 1
		print("PASS %-18s -> '%s'" % [pose_name, expected if expected != "" else "(none)"])
	else:
		fails += 1
		print("FAIL %-18s expected '%s' got '%s'" % [pose_name, expected, got])
