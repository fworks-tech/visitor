extends SceneTree

## Measures real AABBs of furniture + building models. Run with:
##   godot --headless --path <project> --script res://tools/measure_models.gd
## (Plain script: no autoload identifiers, so --script mode compiles it.)

var files := ["bedSingle", "pillow", "cabinetTelevision", "radio", "desk",
	"chairDesk", "bookcaseOpen", "kitchenCabinet", "kitchenSink",
	"kitchenFridgeSmall", "bathroomSink", "bathroomMirror", "toilet",
	"doorwayFront", "coatRackStanding", "rugDoormat", "sideTable",
	"lampRoundTable", "televisionVintage", "lampWall", "lampSquareCeiling",
	"ceilingFan", "rugRectangle", "rugRound", "paneling", "pottedPlant",
	"plantSmall1", "books"]
var building := ["wall", "wall-half", "wall-doorway-square",
	"wall-doorway-wide-square", "wall-window-square", "wall-window-wide-square",
	"floor", "floor-half", "door-rotate-square-a", "barricade-window-a",
	"barricade-doorway-a", "detail-pipe", "plating", "column"]
var atomic := ["tray_1", "cupboard_bottom", "cupboard_top", "machine_1",
	"machine_2", "overhead_light", "bed_1", "bed_2", "bed_4", "wall_door"]
var pack := ["radiator small", "Armchair red", "office table",
	"chim chair_001", "caffetaria_001"]

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	print("MODEL min size centered_xz")
	for f in files:
		await _measure_one("res://assets/models/furniture/" + f + ".glb", f)
	print("BUILDING min size centered_xz")
	for f in building:
		await _measure_one("res://assets/models/building/" + f + ".glb", f)
	print("ATOMIC min size centered_xz")
	for f in atomic:
		await _measure_one("res://assets/models/atomic/" + f + ".glb", f)
	print("PACK min size centered_xz")
	for name in pack:
		await _measure_pack(name)
	quit()

## BlackMire showcase glb: measure one named child in place.
func _measure_pack(node_name: String) -> void:
	var packed := load("res://assets/models/blackmire/PSX Asset Pack-free.glb") as PackedScene
	if packed == null:
		print("MISSING pack")
		return
	var showroom := packed.instantiate() as Node3D
	root.add_child(showroom)
	await process_frame
	var src := _find(showroom, node_name)
	if src == null:
		print("MISSING pack child ", node_name)
		showroom.queue_free()
		return
	var box := AABB()
	var first := true
	if src is MeshInstance3D:
		box = src.global_transform * (src as VisualInstance3D).get_aabb()
		first = false
	for mi in _meshes(src):
		var a: AABB = (mi as Node3D).global_transform * (mi as VisualInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	print("%s min=(%.2f,%.2f,%.2f) size=%.2f,%.2f,%.2f" % [node_name,
		box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z])
	showroom.queue_free()

func _find(n: Node, target: String) -> Node3D:
	if n.name == target and n is Node3D:
		return n as Node3D
	for c in n.get_children():
		var hit := _find(c, target)
		if hit:
			return hit
	return null

func _measure_one(path: String, label: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("MISSING ", label)
		return
	var n := packed.instantiate() as Node3D
	root.add_child(n)
	await process_frame
	await process_frame
	var box := AABB()
	var first := true
	for mi in _meshes(n):
		var vi := mi as VisualInstance3D
		var a: AABB = (mi as Node3D).global_transform * vi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	print("%s min=(%.2f,%.2f,%.2f) size=%.2f,%.2f,%.2f centered_xz=%s" % [
		label, box.position.x, box.position.y, box.position.z,
		box.size.x, box.size.y, box.size.z,
		str(absf(box.get_center().x) < 0.05 and absf(box.get_center().z) < 0.05)])
	n.queue_free()

func _meshes(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out
