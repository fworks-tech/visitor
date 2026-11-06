extends Node

## Headless layout gate: `godot --headless --path . -- --layout-test`
## Pure data: no scene tree, no rendering, no autoload state.
## Guards the regression where room lookup ignored the floor and every upper
## room resolved to its ground-floor twin (storage -> bedroom, guest -> kitchen).

var failures: Array = []
var checks: int = 0

func check(cond: bool, label: String) -> void:
	checks += 1
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		failures.append(label)

func _ready() -> void:
	var script = load("res://scripts/house/House3D.gd")
	var consts: Dictionary = script.get_script_constant_map()
	var floors: Dictionary = consts["FLOOR_Y"]
	var layout: Dictionary = consts["LAYOUT"]
	var house = script.new()

	check(floors.size() == 4, "four floors declared")
	check(layout.size() == floors.size(), "LAYOUT covers every floor")

	for floor in floors:
		check(layout.has(floor), "LAYOUT has %s" % floor)
		var y: float = float(floors[floor])
		check(house.floor_at_y(y + 0.05) == floor, "floor_at_y resolves %s" % floor)
		for room in layout[floor]:
			var pos: Vector3 = layout[floor][room]["pos"]
			var world := Vector3(pos.x, y + 0.05, pos.z)
			check(house.get_room_at(world) == room, "%s/%s resolves by height" % [floor, room])

	# The exact bug this gate exists for: identical x/z on different floors.
	check(house.get_room_at(Vector3(0, 0.05, 0)) == "hall", "ground hall")
	check(house.get_room_at(Vector3(0, 3.25, 0)) == "hall_up", "second hall is not ground hall")
	check(house.get_room_at(Vector3(-6.25, 3.25, 0)) == "storage", "second storage is not bedroom")
	check(house.get_room_at(Vector3(6.0, 3.25, 0)) == "guest_room", "guest room is not kitchen")
	check(house.get_room_at(Vector3(-6.25, -3.15, 0)) == "generator_room", "basement is not bedroom")

	for floor in layout:
		for room in layout[floor]:
			check(HouseScene.ROOM_NAMES.has(room), "HUD name for %s" % room)

	house.free()
	print("RESULT %d failures (%d checks)" % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)
