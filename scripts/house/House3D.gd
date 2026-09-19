class_name House3D
extends Node3D

## Procedural low-poly checkpoint apartment rendered inside the house
## SubViewport. Every room is a 6x6 cell with a door gap toward the hall;
## the camera slides between room centers, point-and-click style.

const WALL_COL := Color(0.3, 0.29, 0.33)
const FLOOR_COL := Color(0.17, 0.17, 0.2)
const DOOR_COL := Color(0.4, 0.3, 0.2)
const FURNITURE_COL := Color(0.24, 0.23, 0.26)
const CEIL_COL := Color(0.18, 0.17, 0.2)

## Rooms sized like what they are: hall is the hub, bathroom is tight.
const ROOM_POSITIONS := {
	"hall": Vector3(0, 0, 0),
	"bedroom": Vector3(-6.25, 0, 0),
	"kitchen": Vector3(6.0, 0, 0),
	"office": Vector3(0, 0, -6.0),
	"bathroom": Vector3(0, 0, 5.5),
}
const ROOM_SIZES := {
	"hall": Vector2(6, 6),
	"bedroom": Vector2(4.5, 4),
	"kitchen": Vector2(4, 4),
	"office": Vector2(4.5, 4),
	"bathroom": Vector2(3, 3),
}

const DOORS := {
	"hall": {"n": true, "s": true, "e": true, "w": true},
	"bedroom": {"e": true},
	"kitchen": {"w": true},
	"office": {"s": true},
	"bathroom": {"n": true},
}

var player: HousePlayer3D
var _interactables: Array = []
var _guest_interactables: Array = []
var _guest_bodies := {}
var _fan: Node3D
const WOOD_COL := Color(0.25, 0.18, 0.12)
var _lights: Dictionary = {}
var _tv_mat: StandardMaterial3D
var _window_mat: StandardMaterial3D
var _tv_on: bool = false
var _is_night: bool = false
var _time: float = 0.0
var _figures_root: Node3D

func _ready() -> void:
	_build_environment()
	_build_house()
	_build_collisions()
	_build_interactables()
	_spawn_player()
	_figures_root = Node3D.new()
	add_child(_figures_root)

func get_room_at(pos: Vector3) -> String:
	var best := "hall"
	var best_d := 1e9
	for room in ROOM_POSITIONS:
		var d: float = Vector2(pos.x - ROOM_POSITIONS[room].x, pos.z - ROOM_POSITIONS[room].z).length()
		if d < best_d:
			best_d = d
			best = room
	return best

## Nearest interactable the player faces: within reach, roughly ahead.
func get_focus(cam_pos: Vector3, cam_fwd: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 2.4
	for it in _interactables + _guest_interactables:
		var to: Vector3 = it["pos"] - cam_pos
		var dist := to.length()
		if dist > 2.4 or dist < 0.2:
			continue
		if to.normalized().dot(cam_fwd) < 0.55:
			continue
		if dist < best_d:
			best_d = dist
			best = it
	return best

func _spawn_player() -> void:
	player = HousePlayer3D.new()
	add_child(player)
	player.position = ROOM_POSITIONS["bedroom"] + Vector3(0.2, 0.05, 1.2)
	# Wake facing the bed, not the corner between bed and TV.
	var to_bed: Vector3 = (ROOM_POSITIONS["bedroom"] + Vector3(-1.72, 0, -0.8)) - player.position
	player.yaw = atan2(-to_bed.x, -to_bed.z)
	player.rotation.y = player.yaw

const FURN_DIR := "res://assets/models/furniture/"
const BUILD_DIR := "res://assets/models/building/"
const ATOMIC_DIR := "res://assets/models/atomic/"
const BLACKMIRE_PACK := "res://assets/models/blackmire/PSX Asset Pack-free.glb"

## Instance a CC0 furniture model. Kenney fronts face +Z — rotate the prop
## so +Z points at the room. Kenney models are ~half true scale (a 0.38m
## "desk"), so every prop takes a measured scale (see tools/measure_models.gd).
## Missing file = null, never a crash.
func _prop(file: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0) -> Node3D:
	return _prop_at(FURN_DIR, file, pos, rot_y, scl)

func _bprop(file: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0) -> Node3D:
	return _prop_at(BUILD_DIR, file, pos, rot_y, scl)

## Instance a CC0 model. Kenney fronts face +Z — rotate the prop
## so +Z points at the room. Kenney models are ~half true scale (a 0.38m
## "desk"), so every prop takes a measured scale (see tools/measure_models.gd).
## Missing file = null, never a crash.
func _prop_at(dir: String, file: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0) -> Node3D:
	var path := dir + file
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var n := packed.instantiate() as Node3D
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * scl
	# Kenney origins sit at the model's back edge — center the real visual
	# box on the target instead, feet on the floor (see measure_models.gd).
	var lb := _local_box_scaled(n, Basis.from_scale(Vector3.ONE * scl))
	var c := lb.get_center()
	var off: Vector3 = Basis(Vector3.UP, rot_y) * Vector3(c.x, 0, c.z)
	n.position = Vector3(pos.x - off.x, pos.y - lb.position.y, pos.z - off.z)
	add_child(n)
	return n

## Instance an Atomic hospital model (true scale, feet on floor, +Z front).
func _atomic(file: String, pos: Vector3, rot_y: float = 0.0) -> Node3D:
	return _prop_at(ATOMIC_DIR, file, pos, rot_y, 1.0)

## Instance one named prop out of the BlackMire showcase pack: a single
## .glb of scattered display items, so duplicate the chosen child and seat
## it like any other prop. Owners are cleared — the showroom is freed.
func _pack_prop(node_name: String, pos: Vector3, rot_y: float = 0.0) -> Node3D:
	if not ResourceLoader.exists(BLACKMIRE_PACK):
		return null
	var packed := load(BLACKMIRE_PACK) as PackedScene
	if packed == null:
		return null
	var showroom := packed.instantiate() as Node3D
	var src := _find_by_name(showroom, node_name)
	if src == null:
		showroom.queue_free()
		return null
	var n := src.duplicate() as Node3D
	showroom.queue_free()
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		cur.owner = null
		stack.append_array(cur.get_children())
	n.rotation = Vector3(0, rot_y, 0)
	n.scale = Vector3.ONE
	# Pack items can be bare MeshInstance3D (mesh on self, no children) —
	# include the node's own box or the seat math comes out empty.
	var acc := [AABB(), false]
	for child in n.get_children():
		_accum_box(child, Basis.IDENTITY, acc)
	if n is MeshInstance3D:
		var own: AABB = Transform3D() * (n as MeshInstance3D).get_aabb()
		if acc[1]:
			acc[0] = (acc[0] as AABB).merge(own)
		else:
			acc[0] = own
			acc[1] = true
	var lb: AABB = acc[0]
	var c := lb.get_center()
	var off: Vector3 = Basis(Vector3.UP, rot_y) * Vector3(c.x, 0, c.z)
	n.position = Vector3(pos.x - off.x, pos.y - lb.position.y, pos.z - off.z)
	add_child(n)
	return n

## Name search that ignores scene ownership (instantiated pack children
## are owned by the showroom root, so find_child's owned filter misses).
func _find_by_name(n: Node, target: String) -> Node3D:
	if n.name == target and n is Node3D:
		return n as Node3D
	for child in n.get_children():
		var hit := _find_by_name(child, target)
		if hit:
			return hit
	return null

## Combined mesh box in prop space (rotation applied separately by caller).
func _local_box_scaled(n: Node, parent_xf: Transform3D) -> AABB:
	var acc := [AABB(), false]
	for child in n.get_children():
		_accum_box(child, parent_xf, acc)
	return acc[0]

func _accum_box(node: Node, xf: Transform3D, acc: Array) -> void:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var b: AABB = here * (node as MeshInstance3D).get_aabb()
		if acc[1]:
			acc[0] = (acc[0] as AABB).merge(b)
		else:
			acc[0] = b
			acc[1] = true
	for child in node.get_children():
		_accum_box(child, here, acc)

func _solid(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

## Collision mirrors the visual walls, but door gaps stay walkable: gap walls
## become two stubs + a lintel overhead instead of one full solid.
func _build_collisions() -> void:
	_solid(Vector3(0, -0.15, 0), Vector3(24, 0.3, 24))
	for room in ROOM_POSITIONS:
		var base: Vector3 = ROOM_POSITIONS[room]
		var hz := _half(room)
		var doors: Dictionary = DOORS.get(room, {})
		_solid_wall(base, hz, "z", -1.0, bool(doors.get("n", false)))
		_solid_wall(base, hz, "z", 1.0, bool(doors.get("s", false)))
		_solid_wall(base, hz, "x", -1.0, bool(doors.get("w", false)))
		_solid_wall(base, hz, "x", 1.0, bool(doors.get("e", false)))
	_build_bridges()
	_build_furniture_solids()

## Floor + side rails across the 1m voids between cells: every doorway is an
## enclosed tunnel stub, never a pit you can strafe off.
func _build_bridges() -> void:
	var h: Vector3 = ROOM_POSITIONS["hall"]
	var links := [
		[ROOM_POSITIONS["bedroom"] + Vector3(_half("bedroom").x, 0, 0), h + Vector3(-3.0, 0, 0), "x"],
		[ROOM_POSITIONS["kitchen"] + Vector3(-_half("kitchen").x, 0, 0), h + Vector3(3.0, 0, 0), "x"],
		[ROOM_POSITIONS["office"] + Vector3(0, 0, _half("office").y), h + Vector3(0, 0, -3.0), "z"],
		[ROOM_POSITIONS["bathroom"] + Vector3(0, 0, -_half("bathroom").y), h + Vector3(0, 0, 3.0), "z"],
	]
	for link in links:
		var a: Vector3 = link[0]
		var b: Vector3 = link[1]
		var mid := (a + b) * 0.5
		var span: float = absf(a.x - b.x) if link[2] == "x" else absf(a.z - b.z)
		# Floor meets the room slabs edge-to-edge (shared edges don't fight).
		var floor_size := Vector3(span, 0.3, 1.6) if link[2] == "x" else Vector3(1.6, 0.3, span)
		_solid(Vector3(mid.x, -0.15, mid.z), floor_size)
		_box(self, Vector3(mid.x, -0.1, mid.z), Vector3(floor_size.x, 0.2, floor_size.z), FLOOR_COL)
		# Rails stop short of every face and clear the stub planes: no fins
		# poking into rooms, no coplanar flicker at the mouths.
		var rail := Vector3(span - 0.1, 3.0, 0.12) if link[2] == "x" else Vector3(0.12, 3.0, span - 0.1)
		var off := 0.9
		if link[2] == "x":
			_solid(Vector3(mid.x, 1.5, mid.z - off), rail)
			_solid(Vector3(mid.x, 1.5, mid.z + off), rail)
			_box(self, Vector3(mid.x, 1.5, mid.z - off), rail, WALL_COL)
			_box(self, Vector3(mid.x, 1.5, mid.z + off), rail, WALL_COL)
		else:
			_solid(Vector3(mid.x - off, 1.5, mid.z), rail)
			_solid(Vector3(mid.x + off, 1.5, mid.z), rail)
			_box(self, Vector3(mid.x - off, 1.5, mid.z), rail, WALL_COL)
			_box(self, Vector3(mid.x + off, 1.5, mid.z), rail, WALL_COL)

func _solid_wall(base: Vector3, hz: Vector2, axis: String, dir_sign: float, has_gap: bool) -> void:
	var length := hz.x * 2.0 if axis == "x" else hz.y * 2.0
	var seg := (length - 1.6) / 2.0
	var off := 1.6 / 2.0 + seg / 2.0
	if axis == "x":
		var pos := base + Vector3(dir_sign * (hz.x + 0.1), 1.5, 0)
		if not has_gap:
			_solid(pos, Vector3(0.2, 3, length + 0.4))
			return
		_solid(pos + Vector3(0, 0, -off), Vector3(0.2, 3, seg))
		_solid(pos + Vector3(0, 0, off), Vector3(0.2, 3, seg))
		_solid(pos + Vector3(0, 1.1, 0), Vector3(0.2, 0.8, 1.6))
	else:
		var pos2 := base + Vector3(0, 1.5, dir_sign * (hz.y + 0.1))
		if not has_gap:
			_solid(pos2, Vector3(length + 0.4, 3, 0.2))
			return
		_solid(pos2 + Vector3(-off, 0, 0), Vector3(seg, 3, 0.2))
		_solid(pos2 + Vector3(off, 0, 0), Vector3(seg, 3, 0.2))
		_solid(pos2 + Vector3(0, 1.1, 0), Vector3(1.6, 0.8, 0.2))

func _build_furniture_solids() -> void:
	var b: Vector3 = ROOM_POSITIONS["bedroom"]
	var k: Vector3 = ROOM_POSITIONS["kitchen"]
	var o: Vector3 = ROOM_POSITIONS["office"]
	var t: Vector3 = ROOM_POSITIONS["bathroom"]
	_solid(b + Vector3(-1.72, 0.35, -0.8), Vector3(1.1, 0.7, 2.0))
	_solid(b + Vector3(1.95, 0.3, -1.4), Vector3(1.6, 0.6, 0.5))
	_solid(b + Vector3(-0.85, 0.25, -1.6), Vector3(0.7, 0.5, 0.5))
	_solid(k + Vector3(1.55, 0.45, 0), Vector3(1.0, 0.9, 3.6))
	_solid(k + Vector3(1.6, 0.6, 1.65), Vector3(0.9, 1.2, 0.7))
	_solid(o + Vector3(-1.0, 0.4, -1.61), Vector3(1.6, 0.8, 0.9))
	_solid(o + Vector3(-1.0, 0.3, -0.9), Vector3(0.5, 0.6, 0.5))
	_solid(o + Vector3(1.5, 0.9, 1.72), Vector3(1.0, 1.8, 0.5))
	_solid(t + Vector3(1.0, 0.4, -1.27), Vector3(0.7, 0.8, 0.6))
	_solid(t + Vector3(-1.1, 0.35, 0.5), Vector3(0.6, 0.7, 0.8))

func _build_interactables() -> void:
	var b: Vector3 = ROOM_POSITIONS["bedroom"]
	var h: Vector3 = ROOM_POSITIONS["hall"]
	var k: Vector3 = ROOM_POSITIONS["kitchen"]
	var o: Vector3 = ROOM_POSITIONS["office"]
	var t: Vector3 = ROOM_POSITIONS["bathroom"]
	_interactables = [
		{"id": "bed", "pos": b + Vector3(-1.72, 0.7, -0.8), "label": "SLEEP"},
		{"id": "tv", "pos": b + Vector3(1.95, 1.0, -1.12), "label": "WATCH TV"},
		{"id": "radio", "pos": b + Vector3(-0.85, 0.6, -1.6), "label": "TURN ON RADIO"},
		{"id": "front_door", "pos": h + Vector3(-1.8, 1.5, 2.9), "label": "FRONT DOOR"},
		{"id": "window", "pos": h + Vector3(1.8, 1.8, -2.9), "label": "LOOK OUT THE WINDOW"},
		{"id": "scavenge", "pos": k + Vector3(1.55, 0.9, -0.1), "label": "SCAVENGE PANTRY"},
		{"id": "fortify", "pos": o + Vector3(-1.0, 0.9, -1.61), "label": "FORTIFY WINDOWS"},
		{"id": "mirror", "pos": t + Vector3(1.0, 1.4, -1.2), "label": "MIRROR — CHECK YOURSELF"},
	]

func set_mood(day: bool) -> void:
	_is_night = not day
	var energy := 2.2 if day else 1.1
	var tint := Color(1.0, 0.92, 0.8) if day else Color(0.9, 0.6, 0.55)
	for l in _lights.values():
		l.light_energy = energy
		l.light_color = tint
	_refresh_window()

func set_tv_on(on: bool) -> void:
	_tv_on = on

func set_guests(guests: Array) -> void:
	for child in _figures_root.get_children():
		child.queue_free()
	_guest_bodies.clear()
	_guest_interactables.clear()
	var offsets := [Vector3(0, 0, -1.4), Vector3(1.6, 0, -0.6), Vector3(-1.6, 0, -0.6), Vector3(1.6, 0, 0.8)]
	var per_room := {}
	for g in guests:
		var room := str(g.get("room", "hall"))
		if not ROOM_POSITIONS.has(room):
			continue
		var i: int = int(per_room.get(room, 0))
		per_room[room] = i + 1
		var pos: Vector3 = ROOM_POSITIONS[room] + offsets[i % offsets.size()]
		# Small rooms (bathroom) can't fit the wide offsets — pull inside.
		var hz := _half(room)
		pos.x = clampf(pos.x, ROOM_POSITIONS[room].x - hz.x + 0.3, ROOM_POSITIONS[room].x + hz.x - 0.3)
		pos.z = clampf(pos.z, ROOM_POSITIONS[room].z - hz.y + 0.3, ROOM_POSITIONS[room].z + hz.y - 0.3)
		# Same body as the door: portrait face, sampled palette, full legs.
		var body := VisitorBody3D.new()
		_figures_root.add_child(body)
		body.position = pos
		body.build(g, _signs_of(g), true)
		# Door examinations persist on the figure standing in your house.
		var shown: int = int(g.get("revealed_signs_count", 0))
		var all: Array = _signs_of(g)
		for j in range(mini(shown, all.size())):
			if all[j] is Dictionary:
				body.show_sign(all[j])
		_guest_bodies[str(g.get("id", ""))] = body
		_guest_interactables.append({"id": "guest", "pos": pos + Vector3(0, 1.0, 0),
			"label": str(g.get("name", "GUEST")).to_upper(), "guest": g})

func _signs_of(g: Dictionary) -> Array:
	return g.get("assigned_signs", [])

## A house examination marks the 3D figure, not just the log.
func show_guest_sign(guest_id: String, sign_data: Dictionary) -> void:
	var b: Variant = _guest_bodies.get(guest_id)
	if b is VisitorBody3D:
		(b as VisitorBody3D).show_sign(sign_data)

# --- construction helpers ----------------------------------------------------

func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := _mesh(parent, mesh, _mat(col))
	mi.name = "box_%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	mi.position = pos
	return mi

func _mesh(parent: Node3D, mesh: Mesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m

func _emissive(pos: Vector3, size: Vector3, col: Color) -> Array:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r * 0.2, col.g * 0.2, col.b * 0.2)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.8
	var mi := _box(self, pos, size, Color(0, 0, 0))
	mi.material_override = m
	return [mi, m]

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.52, 0.6)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.035, 0.05)
	env.fog_density = 0.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _half(room: String) -> Vector2:
	return ROOM_SIZES.get(room, Vector2(6, 6)) * 0.5

func _build_house() -> void:
	for room in ROOM_POSITIONS:
		var base: Vector3 = ROOM_POSITIONS[room]
		var hz := _half(room)
		_box(self, base + Vector3(0, -0.1, 0), Vector3(hz.x * 2.0, 0.2, hz.y * 2.0), FLOOR_COL)
		_wall(base, hz, "z", -1.0, DOORS.get(room, {}).get("n", false))
		_wall(base, hz, "z", 1.0, DOORS.get(room, {}).get("s", false))
		_wall(base, hz, "x", -1.0, DOORS.get(room, {}).get("w", false))
		_wall(base, hz, "x", 1.0, DOORS.get(room, {}).get("e", false))
		var light := OmniLight3D.new()
		light.position = base + Vector3(0, 2.6, 0)
		light.omni_range = 12.0
		light.light_energy = 2.2
		add_child(light)
		_lights[room] = light
	_build_bedroom()
	_build_hall()
	_build_kitchen()
	_build_office()
	_build_bathroom()
	_build_decor()
	_build_structure()
	# One lid over the whole complex: the player only ever sees interiors.
	_box(self, Vector3(0, 3.1, 0), Vector3(22, 0.2, 22), CEIL_COL)

func _wall(base: Vector3, hz: Vector2, axis: String, dir_sign: float, has_gap: bool) -> void:
	var pos: Vector3
	var size: Vector3
	var length := hz.x * 2.0 if axis == "x" else hz.y * 2.0
	if axis == "x":
		pos = base + Vector3(dir_sign * (hz.x + 0.1), 1.5, 0)
		size = Vector3(0.2, 3, length + 0.4)
	else:
		pos = base + Vector3(0, 1.5, dir_sign * (hz.y + 0.1))
		size = Vector3(length + 0.4, 3, 0.2)
	if not has_gap:
		_box(self, pos, size, WALL_COL)
		return
	var seg := (length - 1.6) / 2.0
	var off := 1.6 / 2.0 + seg / 2.0
	if axis == "x":
		_box(self, pos + Vector3(0, 0, -off), Vector3(0.2, 3, seg), WALL_COL)
		_box(self, pos + Vector3(0, 0, off), Vector3(0.2, 3, seg), WALL_COL)
		_box(self, pos + Vector3(0, 1.1, 0), Vector3(0.2, 0.8, 1.6), WALL_COL)
	else:
		_box(self, pos + Vector3(-off, 0, 0), Vector3(seg, 3, 0.2), WALL_COL)
		_box(self, pos + Vector3(off, 0, 0), Vector3(seg, 3, 0.2), WALL_COL)
		_box(self, pos + Vector3(0, 1.1, 0), Vector3(1.6, 0.8, 0.2), WALL_COL)

func _build_bedroom() -> void:
	var base: Vector3 = ROOM_POSITIONS["bedroom"]
	_prop("bedSingle.glb", base + Vector3(-1.72, 0, -0.8), 0.0, 1.7)
	_prop("pillow.glb", base + Vector3(-1.72, 0.62, -1.5), 0.0, 1.7)
	_prop("sideTable.glb", base + Vector3(-0.85, 0, -1.6), 0.0, 1.2)
	_prop("cabinetTelevision.glb", base + Vector3(1.95, 0, -1.4), 0.0, 2.0)
	# Screen floats on the room-side face of the cabinet, static when the TV is on.
	var tv_pair: Array = _emissive(base + Vector3(1.95, 0.95, -1.12), Vector3(1.4, 0.8, 0.08), Color(0.1, 0.12, 0.15))
	_tv_mat = tv_pair[1]
	_prop("radio.glb", base + Vector3(-0.85, 0.46, -1.6), 0.0, 1.5)
	# Salvaged radiator against the north wall — shelter heating.
	_pack_prop("radiator small", base + Vector3(1.2, 0, -1.7), -PI / 2.0)

func _build_hall() -> void:
	var base: Vector3 = ROOM_POSITIONS["hall"]
	_build_window(base + Vector3(1.8, 1.8, -2.94))
	# Real door leaf in the frame — the slab read as a hole in the wall.
	_bprop("door-rotate-square-a.glb", base + Vector3(-1.8, 0, 2.96), PI / 2.0, 1.0)
	_prop("doorwayFront.glb", base + Vector3(-1.8, 0, 2.9), 0.0, 2.1)
	_prop("rugDoormat.glb", base + Vector3(-1.8, 0.02, 2.0), 0.0, 2.5)
	_prop("coatRackStanding.glb", base + Vector3(-2.5, 0, 1.0), 0.0, 2.2)
	# Reading corner + salvaged medical gear on the north wall.
	_pack_prop("Armchair red", base + Vector3(2.3, 0, 2.3), -PI * 0.75)
	_atomic("machine_1.glb", base + Vector3(-2.3, 0, -2.45), 0.0)
	_atomic("machine_2.glb", base + Vector3(-1.5, 0, -2.5), 0.0)
	# Surgical light: geometry hangs 1.22..2.0 below its origin, so seat
	# the origin at 2.42 — the mount rod kisses the 3.0 ceiling slab.
	_atomic("overhead_light.glb", base + Vector3(-1.9, 2.42, -2.0), 0.0)

## A real window: glow quad set in a wood frame with sill, muntins,
## curtain rod and drapes. `center` = glow-quad center on the wall face.
func _build_window(center: Vector3) -> void:
	var win: Array = _emissive(center, Vector3(1.2, 1.0, 0.06), Color(0.5, 0.4, 0.25))
	_window_mat = win[1]
	var frame := WOOD_COL
	_box(self, center + Vector3(0, 0.54, 0.02), Vector3(1.36, 0.08, 0.08), frame)
	_box(self, center + Vector3(0, -0.54, 0.02), Vector3(1.36, 0.08, 0.08), frame)
	_box(self, center + Vector3(-0.64, 0, 0.02), Vector3(0.08, 1.16, 0.08), frame)
	_box(self, center + Vector3(0.64, 0, 0.02), Vector3(0.08, 1.16, 0.08), frame)
	_box(self, center + Vector3(0, -0.62, 0.08), Vector3(1.5, 0.07, 0.18), frame)
	var dark := Color(0.08, 0.07, 0.08)
	_box(self, center + Vector3(0, 0, 0.04), Vector3(0.05, 1.0, 0.03), dark)
	_box(self, center + Vector3(0, 0, 0.04), Vector3(1.2, 0.05, 0.03), dark)
	var drape := Color(0.32, 0.1, 0.12)
	_box(self, center + Vector3(-0.82, -0.1, 0.06), Vector3(0.28, 1.7, 0.1), drape)
	_box(self, center + Vector3(0.82, -0.1, 0.06), Vector3(0.28, 1.7, 0.1), drape)
	_box(self, center + Vector3(0, 0.72, 0.06), Vector3(1.9, 0.05, 0.05), WOOD_COL)

func _build_kitchen() -> void:
	var base: Vector3 = ROOM_POSITIONS["kitchen"]
	_prop("kitchenCabinet.glb", base + Vector3(1.55, 0, -1.2), -PI / 2.0, 2.0)
	_prop("kitchenSink.glb", base + Vector3(1.55, 0, -0.1), -PI / 2.0, 2.0)
	_prop("kitchenCabinet.glb", base + Vector3(1.55, 0, 1.0), -PI / 2.0, 2.0)
	_prop("kitchenFridgeSmall.glb", base + Vector3(-1.6, 0, -1.5), PI / 2.0, 2.0)
	# Hospital storage on the west wall, wall unit stacked on its base.
	_atomic("cupboard_bottom.glb", base + Vector3(-1.7, 0, 0.6), PI / 2.0)
	_atomic("cupboard_top.glb", base + Vector3(-1.7, 0.69, 0.6), PI / 2.0)
	_pack_prop("caffetaria_001", base + Vector3(-0.3, 0, 1.6), PI)

func _build_office() -> void:
	var base: Vector3 = ROOM_POSITIONS["office"]
	_prop("desk.glb", base + Vector3(-1.0, 0, -1.61), 0.0, 2.0)
	_prop("chairDesk.glb", base + Vector3(-1.0, 0, -0.9), PI, 1.6)
	_prop("bookcaseOpen.glb", base + Vector3(1.5, 0, 1.72), 0.0, 2.0)
	# Second workstation on the east side, chair pulled up to it.
	_pack_prop("office table", base + Vector3(1.2, 0, -0.4), PI / 2.0)
	_pack_prop("chim chair_001", base + Vector3(0.3, 0, -0.4), PI / 2.0)
	_box(self, base + Vector3(-0.6, 1.9, -1.95), Vector3(2.6, 0.2, 0.1), DOOR_COL)
	_box(self, base + Vector3(-1.2, 1.4, -1.95), Vector3(2.6, 0.2, 0.1), DOOR_COL)

func _build_bathroom() -> void:
	var base: Vector3 = ROOM_POSITIONS["bathroom"]
	# Sink origin hangs below the model — the auto-centering seats it.
	_prop("bathroomSink.glb", base + Vector3(1.0, 0, -1.27), 0.0, 1.6)
	_emissive(base + Vector3(1.0, 1.7, -1.43), Vector3(0.8, 1.0, 0.05), Color(0.4, 0.5, 0.55))
	_prop("toilet.glb", base + Vector3(-1.1, 0, 0.5), 0.0, 1.6)
	# Instrument tray beside the sink — triage kit.
	_atomic("tray_1.glb", base + Vector3(0.0, 0, -1.25), 0.0)

# --- structure: kit trim over the box shell ------------------------------------
# The 2m/2.4m kit modules don't match our 6x3m cells, so boxes stay structural
# and kit pieces land where they read: doors, barricades, baseboards, pipes.

func _build_structure() -> void:
	var h: Vector3 = ROOM_POSITIONS["hall"]
	var o: Vector3 = ROOM_POSITIONS["office"]
	var b: Vector3 = ROOM_POSITIONS["bedroom"]
	# Boarded office opening over the plank fortify.
	_bprop("barricade-window-a.glb", o + Vector3(-0.9, 1.1, -1.9), 0.0, 1.6)
	# Baseboards kill the floating-wall read (crossings read as thresholds).
	var bb := Color(0.1, 0.09, 0.1)
	for room in ROOM_POSITIONS:
		var base: Vector3 = ROOM_POSITIONS[room]
		var hz := _half(room)
		_box(self, base + Vector3(0, 0.06, -(hz.y - 0.015)), Vector3(hz.x * 2.0, 0.12, 0.03), bb)
		_box(self, base + Vector3(0, 0.06, hz.y - 0.015), Vector3(hz.x * 2.0, 0.12, 0.03), bb)
		_box(self, Vector3(base.x - (hz.x - 0.015), 0.06, base.z), Vector3(0.03, 0.12, hz.y * 2.0), bb)
		_box(self, Vector3(base.x + hz.x - 0.015, 0.06, base.z), Vector3(0.03, 0.12, hz.y * 2.0), bb)
	# Pipes and patch plates: checkpoint-industrial, not apartment.
	_bprop("detail-pipe.glb", h + Vector3(2.7, 0, -2.7), 0.0, 1.5)
	_bprop("detail-pipe.glb", o + Vector3(2.7, 0, 1.5), 0.0, 1.5)
	_bprop("plating.glb", h + Vector3(-2.0, 1.1, -2.96), 0.0, 1.5)
	_bprop("plating.glb", b + Vector3(2.96, 1.3, 0.5), PI / 2.0, 1.5)

# --- decor: rugs, plants, lamps, fan, wainscot ---------------------------------
# No new collision except floor plants; decor never takes focus.
# No new collision except floor plants; decor never takes focus.

func _build_decor() -> void:
	var b: Vector3 = ROOM_POSITIONS["bedroom"]
	var h: Vector3 = ROOM_POSITIONS["hall"]
	var k: Vector3 = ROOM_POSITIONS["kitchen"]
	var o: Vector3 = ROOM_POSITIONS["office"]
	var t: Vector3 = ROOM_POSITIONS["bathroom"]
	# Rugs (y=0.02 clears the floor; edges slide under furniture).
	_prop("rugRectangle.glb", b + Vector3(-0.3, 0.02, 0.3), 0.0, 1.3)
	_prop("rugRound.glb", h + Vector3(0.6, 0.02, 0.8), 0.0, 1.8)
	_prop("rugRound.glb", k + Vector3(-0.5, 0.02, 0.2), 0.0, 1.6)
	_prop("rugRectangle.glb", o + Vector3(-0.8, 0.02, -0.5), 0.0, 1.3)
	# Floor plants in dead corners.
	_prop("pottedPlant.glb", h + Vector3(2.5, 0, 2.5), 0.0, 1.6)
	_prop("pottedPlant.glb", b + Vector3(1.8, 0, 1.5), 0.0, 1.6)
	_solid(h + Vector3(2.5, 0.4, 2.5), Vector3(0.35, 0.8, 0.35))
	_solid(b + Vector3(1.8, 0.4, 1.5), Vector3(0.35, 0.8, 0.35))
	# Tabletop clutter (auto-seated on furniture tops).
	_prop("books.glb", o + Vector3(-1.5, 0.76, -1.61), 0.3, 2.5)
	_prop("books.glb", b + Vector3(1.3, 0.62, -1.4), -0.2, 2.5)
	_prop("plantSmall1.glb", k + Vector3(1.55, 0.9, -1.2), 0.0, 2.0)
	# Wall lamps: mesh + warm shade glow (the mesh itself is unlit plastic).
	_wall_lamp(b + Vector3(-1.5, 1.85, -1.89), 0.0)
	_wall_lamp(h + Vector3(-1.8, 2.35, 2.89), PI)
	_wall_lamp(o + Vector3(-2.14, 1.9, -0.5), PI / 2.0)
	_wall_lamp(t + Vector3(-0.2, 1.9, -1.39), 0.0)
	# Kitchen ceiling dome (top kisses the implied 3.0 ceiling).
	_prop("lampSquareCeiling.glb", k + Vector3(0, 2.54, 0), 0.0, 2.0)
	_emissive(k + Vector3(0, 2.5, 0), Vector3(0.2, 0.03, 0.2), Color(1.0, 0.8, 0.55))
	# Hall ceiling fan — dark spinning shape overhead.
	_fan = _prop("ceilingFan.glb", h + Vector3(0, 2.6, 0), 0.0, 2.0)
	# Wainscot + wallpaper bands (thin boxes proud of the inner faces).
	_wainscot_wall(b, _half("bedroom"), "z", -1.0, Color(0.35, 0.28, 0.3))
	_wainscot_wall(b, _half("bedroom"), "x", -1.0, Color(0.35, 0.28, 0.3))
	_wainscot_wall(o, _half("office"), "z", -1.0, Color(0.3, 0.32, 0.28))

## Sconce on a wall: lamp mesh (back at the face) + warm shade quad.
func _wall_lamp(pos: Vector3, rot_y: float) -> void:
	_prop("lampWall.glb", pos, rot_y, 1.5)
	var fwd := Basis(Vector3.UP, rot_y) * Vector3(0, 0, 1)
	_emissive(pos + fwd * 0.1 + Vector3(0, 0.02, 0), Vector3(0.28, 0.16, 0.03),
		Color(1.0, 0.72, 0.42))

## Wood wainscot (0-1m) + muted wallpaper band above, on one wall.
func _wainscot_wall(base: Vector3, hz: Vector2, axis: String, dir_sign: float, paper: Color) -> void:
	if axis == "z":
		var length := hz.x * 2.0
		var z := base.z + dir_sign * (hz.y + 0.0)
		var s := -dir_sign  # step back into the room
		_box(self, Vector3(base.x, 0.5, z + s * 0.02), Vector3(length, 1.0, 0.04), WOOD_COL)
		_box(self, Vector3(base.x, 1.02, z + s * 0.03), Vector3(length, 0.07, 0.06), WOOD_COL)
		_box(self, Vector3(base.x, 2.0, z + s * 0.01), Vector3(length, 1.95, 0.02), paper)
	else:
		var length2 := hz.y * 2.0
		var x := base.x + dir_sign * (hz.x + 0.0)
		var s2 := -dir_sign
		_box(self, Vector3(x + s2 * 0.02, 0.5, base.z), Vector3(0.04, 1.0, length2), WOOD_COL)
		_box(self, Vector3(x + s2 * 0.03, 1.02, base.z), Vector3(0.06, 0.07, length2), WOOD_COL)
		_box(self, Vector3(x + s2 * 0.01, 2.0, base.z), Vector3(0.02, 1.95, length2), paper)

# --- runtime -----------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _fan:
		_fan.rotation.y += delta * 3.0
	if _tv_on and _tv_mat:
		_tv_mat.emission = Color(randf_range(0.5, 0.9), randf_range(0.5, 0.9), randf_range(0.55, 0.95))
		_tv_mat.emission_energy_multiplier = randf_range(0.6, 1.4)
	if _window_mat:
		_refresh_window()

func _refresh_window() -> void:
	if not _window_mat:
		return
	if _is_night:
		_window_mat.emission = Color(0.55, 0.08, 0.05)
		_window_mat.emission_energy_multiplier = 0.7 + 0.3 * sin(_time * 1.7)
	else:
		_window_mat.emission = Color(0.45, 0.5, 0.55)
		_window_mat.emission_energy_multiplier = 1.0
