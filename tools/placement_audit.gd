extends SceneTree

## Placement audit: every house object must rest on floor, wall or ceiling.
##   godot --headless --path <project> --script res://tools/placement_audit.gd
## Prints PASS/FAIL per item; exit code 1 on any floater.
## (Plain script: dynamic access only, so --script mode compiles it.)

# Room footprints duplicated from House3D (x, z, w, d).
var rooms := [
	["hall", 0.0, 0.0, 6.0, 6.0],
	["bedroom", -6.25, 0.0, 4.5, 4.0],
	["kitchen", 6.0, 0.0, 4.0, 4.0],
	["office", 0.0, -6.0, 4.5, 4.0],
	["bathroom", 0.0, 5.5, 3.0, 3.0],
]

var fails := 0
var passes := 0

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
	var player: Node = house3d.get("player")
	var items := []
	for c in house3d.get_children():
		if c == player or not (c is Node3D):
			continue
		if String(c.name) == "figures_root":
			for g in c.get_children():
				items.append(g)
			continue
		items.append(c)
	var boxed := []
	for item in items:
		var acc := _box_of(item)
		if acc[1]:
			boxed.append([item, acc[0]])
	var supporters := []
	for entry in boxed:
		var b: AABB = entry[1]
		if b.position.y <= 0.06 and b.size.y > 0.4:
			supporters.append({"top": b.position.y + b.size.y, "name": String(entry[0].name),
				"minx": b.position.x - 0.15, "maxx": b.position.x + b.size.x + 0.15,
				"minz": b.position.z - 0.15, "maxz": b.position.z + b.size.z + 0.15})
	for entry in boxed:
		_check(entry[0], entry[1], supporters)

func _box_of(n: Node) -> Array:
	var acc := [AABB(), false]
	_accum(n, Transform3D.IDENTITY, acc)
	return acc

func _accum(node: Node, xf: Transform3D, acc: Array) -> void:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var vi := node as VisualInstance3D
		if vi.get_aabb().size.length() > 0.001:
			var b: AABB = here * vi.get_aabb()
			if acc[1]:
				acc[0] = (acc[0] as AABB).merge(b)
			else:
				acc[0] = b
				acc[1] = true
	for c in node.get_children():
		_accum(c, here, acc)

func _wall_dist(center: Vector3) -> float:
	var best := 1e9
	for r in rooms:
		var dx: float = minf(absf(center.x - (r[1] - r[3] / 2.0)), absf(center.x - (r[1] + r[3] / 2.0)))
		var dz: float = minf(absf(center.z - (r[2] - r[4] / 2.0)), absf(center.z - (r[2] + r[4] / 2.0)))
		best = minf(best, minf(dx, dz))
	return best

	printerr("PLACEMENT: %d PASS, %d FAIL" % [passes, fails])
	quit(1 if fails > 0 else 0)

func _check(item: Node, box: AABB, supporters: Array) -> void:
	var c := box.get_center()
	var tag := ""
	var ok := false
	if box.size.y <= 0.4 and absf(box.position.y + box.size.y) <= 0.06:
		tag = "floor-slab"
		ok = true
	elif box.position.y <= 0.06:
		tag = "floor-standing"
		ok = true
	elif box.position.y >= 2.4:
		tag = "ceiling"
		ok = box.position.y + box.size.y >= 2.5
	else:
		for s in supporters:
			if c.x >= s["minx"] and c.x <= s["maxx"] and c.z >= s["minz"] and c.z <= s["maxz"] \
					and absf(box.position.y - s["top"]) <= 0.07:
				tag = "on-%s" % String(s["name"]).left(16)
				ok = true
				break
		if not ok:
			var d := _wall_dist(c)
			tag = "wall-mounted d=%.2f" % d
			ok = d < 0.35
	if ok:
		passes += 1
		print("PASS %-14s %-28s min=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)" % [
			tag, String(item.name).left(28), box.position.x, box.position.y, box.position.z,
			box.size.x, box.size.y, box.size.z])
	else:
		fails += 1
		print("FAIL %-14s %-28s min=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)" % [
			tag, String(item.name).left(28), box.position.x, box.position.y, box.position.z,
			box.size.x, box.size.y, box.size.z])
