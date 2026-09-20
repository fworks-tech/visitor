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

## Floor offsets: each floor is 3.2m above the one below.
const FLOOR_Y := {"ground": 0.0, "second": 3.2, "attic": 6.4, "basement": -3.2}

## Rooms sized like what they are: hall is the hub, bathroom is tight.
const ROOM_POSITIONS := {
	"hall": Vector3(0, 0, 0),
	"bedroom": Vector3(-6.25, 0, 0),
	"kitchen": Vector3(6.0, 0, 0),
	"office": Vector3(0, 0, -6.0),
	"bathroom": Vector3(0, 0, 5.5),
}

## Upper/lower floors unlock as days progress.
const SECOND_FLOOR_ROOMS := {
	"hall_up": Vector3(0, 0, 0),
	"storage": Vector3(-6.25, 0, 0),
	"guest_room": Vector3(6.0, 0, 0),
}
const SECOND_FLOOR_SIZES := {
	"hall_up": Vector2(6, 6),
	"storage": Vector2(4, 4),
	"guest_room": Vector2(4, 4),
}
const SECOND_FLOOR_DOORS := {
	"hall_up": {"n": false, "s": false, "e": true, "w": true},
	"storage": {"e": true},
	"guest_room": {"w": true},
}

const ATTIC_ROOMS := {
	"attic_hall": Vector3(0, 0, 0),
	"attic_storage": Vector3(-6.25, 0, 0),
}
const ATTIC_SIZES := {
	"attic_hall": Vector2(6, 6),
	"attic_storage": Vector2(4, 4),
}
const ATTIC_DOORS := {
	"attic_hall": {"n": false, "s": false, "e": true, "w": false},
	"attic_storage": {"e": true},
}

const BASEMENT_ROOMS := {
	"basement_hall": Vector3(0, 0, 0),
	"generator_room": Vector3(-6.25, 0, 0),
	"cellar": Vector3(6.0, 0, 0),
}
const BASEMENT_SIZES := {
	"basement_hall": Vector2(6, 6),
	"generator_room": Vector2(4, 4),
	"cellar": Vector2(4, 4),
}
const BASEMENT_DOORS := {
	"basement_hall": {"n": false, "s": false, "e": true, "w": true},
	"generator_room": {"e": true},
	"cellar": {"w": true},
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
var _focus_boxes: Dictionary = {}
var _fan: Node3D
const WOOD_COL := Color(0.25, 0.18, 0.12)
var _lights: Dictionary = {}
var _lamp_lights: Array = []
var _tv_mat: StandardMaterial3D
var _window_mat: StandardMaterial3D
var _tv_on: bool = false
var _is_night: bool = false
var _time: float = 0.0
var _figures_root: Node3D
var _cab_hinges: Array = []
var _cab_bodies: Array = []
var _drawer: Node3D
var _drawer_open: bool = false
var _cabinets_open: bool = false
var _tap_on: bool = false
var _tap_streak: MeshInstance3D
var _tap_mat: StandardMaterial3D

## Multi-floor state: which floors are accessible (drives collision + interactables).
var _unlocked_floors: Array = ["ground"]
var _current_floor: String = "ground"
var _obstacle_props: Array = []

func _ready() -> void:
	_build_environment()
	_compute_unlocked_floors()
	_build_house()
	_build_collisions()
	_build_obstacles()
	_build_interactables()
	_spawn_player()
	_figures_root = Node3D.new()
	add_child(_figures_root)

## Computes which floors are accessible based on the current day.
func _compute_unlocked_floors() -> void:
	var floors := ["ground"]
	var day: int = GameManager.current_day
	if day >= 3:
		floors.append("second")
	if day >= 5:
		floors.append("attic")
	if day >= 7:
		floors.append("basement")
	_unlocked_floors = floors
	_current_floor = "ground"

## Sets which floors are accessible. Rebuilds collisions + interactables to match.
func set_unlocked_floors(floors: Array) -> void:
	_unlocked_floors = floors.duplicate()
	_current_floor = "ground"
	# Clear existing collisions and obstacles, rebuild for new floor set.
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	_build_collisions()
	_build_obstacles()
	_build_interactables()
	if player != null:
		player.position = ROOM_POSITIONS["bedroom"] + Vector3(0.2, FLOOR_Y["ground"] + 0.05, 1.2)

func get_room_at(pos: Vector3) -> String:
	var best := "hall"
	var best_d := 1e9
	for room in ROOM_POSITIONS:
		var d: float = Vector2(pos.x - ROOM_POSITIONS[room].x, pos.z - ROOM_POSITIONS[room].z).length()
		if d < best_d:
			best_d = d
			best = room
	return best

## The focus the crosshair actually points at. Statics: the camera ray must
## pierce the interactable's captured surface box AND not be blocked by a
## wall/solid before it (a plain AABB test would happily select the TV
## through the hall wall). Guests stay on the proximity+cone model: moving
## point targets with no registered surface.
func get_focus(cam_pos: Vector3, cam_fwd: Vector3) -> Dictionary:
	var ray_to := cam_pos + cam_fwd * 2.4
	var hits: Array = []
	for it in _interactables:
		var box: AABB = it.get("box",
			AABB(it["pos"] - Vector3(0.2, 0.2, 0.2), Vector3(0.4, 0.4, 0.4)))
		var t := _ray_box_t(cam_pos, ray_to, box)
		if t >= 0.0 and 2.4 * t >= 0.2:
			hits.append([t, it])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	for h in hits:
		var t: float = h[0]
		var hit_pos: Vector3 = cam_pos + cam_fwd * (2.4 * t)
		if _occluded(cam_pos, hit_pos):
			continue
		return _focus_with_guests(cam_pos, cam_fwd, h[1], 2.4 * t)
	return _focus_with_guests(cam_pos, cam_fwd, {}, 2.4)

## Nearest static focus at static_d competes with the guest cone.
func _focus_with_guests(cam_pos: Vector3, cam_fwd: Vector3, static_it: Dictionary, static_d: float) -> Dictionary:
	var best: Dictionary = static_it
	var best_d := static_d
	for it in _guest_interactables:
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

## True when a static body (walls, furniture solids, floor) sits between the
## camera and the surface point. Endpoint is pulled 15cm short so boxes that
## grow flush into their own wall don't self-occlude.
func _occluded(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var to_pulled := to + (from - to).normalized() * 0.15
	var query := PhysicsRayQueryParameters3D.create(from, to_pulled)
	if player != null:
		query.exclude = [player.get_rid()]
	return not space.intersect_ray(query).is_empty()

## Slab-method ray vs AABB: entry fraction along [from, to], -1 on miss.
func _ray_box_t(from: Vector3, to: Vector3, box: AABB) -> float:
	var dir := to - from
	var tmin := 0.0
	var tmax := 1.0
	for axis in 3:
		var o := from[axis]
		var d := dir[axis]
		var mn := box.position[axis]
		var mx := box.position[axis] + box.size[axis]
		if absf(d) < 0.0001:
			if o < mn or o > mx:
				return -1.0
		else:
			var t1 := (mn - o) / d
			var t2 := (mx - o) / d
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin if tmax >= 0.0 else -1.0

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

## World-space merged AABB of an instanced prop's own meshes.
func _world_box(n: Node3D) -> AABB:
	var acc := [AABB(), false]
	if n is MeshInstance3D:
		acc = [n.global_transform * (n as MeshInstance3D).get_aabb(), true]
	for child in n.get_children():
		_accum_box(child, n.global_transform, acc)
	return acc[0]

## Interactable entry; attaches the captured visual surface box when the
## room builder registered one (get_focus ray-tests it instead of cone).
func _it(id: String, pos: Vector3, label: String) -> Dictionary:
	var entry := {"id": id, "pos": pos, "label": label}
	if _focus_boxes.has(id):
		entry["box"] = _focus_boxes[id]
	return entry

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
	# Ground floor.
	_solid(Vector3(0, -0.15, 0), Vector3(24, 0.3, 24))
	_floor_collisions_for(FLOOR_Y["ground"], ROOM_POSITIONS, ROOM_SIZES, DOORS)
	if _unlocked_floors.has("second"):
		_floor_collisions_for(FLOOR_Y["second"], SECOND_FLOOR_ROOMS, SECOND_FLOOR_SIZES, SECOND_FLOOR_DOORS)
	if _unlocked_floors.has("attic"):
		_floor_collisions_for(FLOOR_Y["attic"], ATTIC_ROOMS, ATTIC_SIZES, ATTIC_DOORS)
	if _unlocked_floors.has("basement"):
		_solid(Vector3(0, FLOOR_Y["basement"] - 0.15, 0), Vector3(24, 0.3, 24))
		_floor_collisions_for(FLOOR_Y["basement"], BASEMENT_ROOMS, BASEMENT_SIZES, BASEMENT_DOORS)
	_build_bridges()
	_build_furniture_solids()

func _floor_collisions_for(y_off: float, rooms: Dictionary, sizes: Dictionary, doors: Dictionary) -> void:
	for room in rooms:
		var base := Vector3(rooms[room].x, y_off, rooms[room].z)
		var sz: Vector2 = sizes.get(room, Vector2(4, 4))
		var hz := sz * 0.5
		var drs: Dictionary = doors.get(room, {})
		_solid_wall(base, hz, "z", -1.0, bool(drs.get("n", false)))
		_solid_wall(base, hz, "z", 1.0, bool(drs.get("s", false)))
		_solid_wall(base, hz, "x", -1.0, bool(drs.get("w", false)))
		_solid_wall(base, hz, "x", 1.0, bool(drs.get("e", false)))


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
	_solid(b + Vector3(-1.3, 0.31, 1.75), Vector3(1.6, 0.62, 0.5))
	_solid(b + Vector3(-0.85, 0.25, -1.6), Vector3(0.7, 0.5, 0.5))
	_solid(k + Vector3(1.55, 0.45, 0), Vector3(1.0, 0.9, 2.9))
	_solid(k + Vector3(-1.71, 0.6, -1.5), Vector3(0.6, 1.2, 0.9))
	_solid(o + Vector3(-1.0, 0.4, -1.61), Vector3(1.6, 0.8, 0.9))
	_solid(o + Vector3(-1.0, 0.3, -0.9), Vector3(0.5, 0.6, 0.5))
	_solid(o + Vector3(1.5, 0.9, 1.72), Vector3(1.0, 1.8, 0.5))
	_solid(t + Vector3(1.27, 0.4, -0.2), Vector3(0.5, 0.8, 0.55))
	_solid(t + Vector3(-1.1, 0.36, 1.11), Vector3(0.5, 0.7, 0.78))

func _build_interactables() -> void:
	var b: Vector3 = ROOM_POSITIONS["bedroom"]
	var h: Vector3 = ROOM_POSITIONS["hall"]
	var k: Vector3 = ROOM_POSITIONS["kitchen"]
	var o: Vector3 = ROOM_POSITIONS["office"]
	var t: Vector3 = ROOM_POSITIONS["bathroom"]
	_interactables = [
		_it("bed", b + Vector3(-1.72, 0.7, -0.8), "SLEEP"),
		_it("tv", b + Vector3(-1.3, 1.0, 1.75), "WATCH TV"),
		_it("radio", b + Vector3(-0.85, 0.6, -1.6), "TURN ON RADIO"),
		_it("front_door", h + Vector3(-1.8, 1.5, 2.9), "FRONT DOOR"),
		_it("window", h + Vector3(1.8, 1.8, -2.9), "LOOK OUT THE WINDOW"),
		_it("scavenge", k + Vector3(1.55, 0.9, 0.0), "SCAVENGE PANTRY"),
		_it("cabinet", k + Vector3(1.7, 1.75, 0.0), "OPEN CABINET"),
		_it("drawer", k + Vector3(0.85, 0.55, -1.0), "PULL DRAWER"),
		_it("tap", k + Vector3(1.6, 1.15, 0.0), "TURN ON TAP"),
		_it("fortify", o + Vector3(-0.9, 1.2, -1.9), "FORTIFY WINDOWS"),
		_it("mirror", t + Vector3(1.4, 1.7, -0.2), "MIRROR — CHECK YOURSELF"),
	]
	# Stairs connect floors when unlocked.
	if _unlocked_floors.has("second"):
		_interactables.append(_it("stairs_up", h + Vector3(2.5, 1.0, 0.0), "STAIRS UP — SECOND FLOOR"))
	if _unlocked_floors.has("basement"):
		_interactables.append(_it("stairs_down", h + Vector3(2.5, 1.0, 1.5), "STAIRS DOWN — BASEMENT"))
	# Second floor interactables.
	if _unlocked_floors.has("second"):
		var sy := FLOOR_Y["second"]
		_interactables.append(_it("stairs_down_from_second", Vector3(2.5, sy + 1.0, 0.0), "STAIRS DOWN — GROUND FLOOR"))
		_interactables.append(_it("scavenge_storage", Vector3(-6.25, sy + 0.9, 0.0), "SEARCH STORAGE ROOM"))
		_interactables.append(_it("guest_room_bed", Vector3(6.0, sy + 0.7, -0.8), "GUEST ROOM — REST"))
		if _unlocked_floors.has("attic"):
			_interactables.append(_it("ladder_up", Vector3(2.5, sy + 1.0, 1.5), "LADDER UP — ATTIC"))
	# Attic interactables.
	if _unlocked_floors.has("attic"):
		var ay := FLOOR_Y["attic"]
		_interactables.append(_it("ladder_down", Vector3(2.5, ay + 1.0, 0.0), "LADDER DOWN — SECOND FLOOR"))
		_interactables.append(_it("search_attic", Vector3(-6.25, ay + 0.9, 0.0), "SEARCH ATTIC STORAGE"))
	# Basement interactables.
	if _unlocked_floors.has("basement"):
		var by := FLOOR_Y["basement"]
		_interactables.append(_it("stairs_up_from_basement", Vector3(2.5, by + 1.0, 0.0), "STAIRS UP — GROUND FLOOR"))
		_interactables.append(_it("generator", Vector3(-6.25, by + 0.9, 0.0), "CHECK GENERATOR"))
		_interactables.append(_it("cellar_search", Vector3(6.0, by + 0.9, 0.0), "SEARCH CELLAR"))

## Adds visual + collision obstacles on locked paths. The geometry (marker
## boxes, barricade props) is always visible, but collision blocks the player
## until the floor unlocks. Ground floor: stairs_up (day 3), basement door (day 7).
## Second floor: attic hatch (day 5).
func _build_obstacles() -> void:
	# Clear previous obstacle props.
	for p in _obstacle_props:
		if is_instance_valid(p):
			p.queue_free()
	_obstacle_props = []
	# Stairs to second floor: blocked until day 3.
	if not _unlocked_floors.has("second"):
		var h: Vector3 = ROOM_POSITIONS["hall"]
		var barricade_1: Node3D = _bprop("barricade-window-a.glb", h + Vector3(2.5, 0.9, 0.0), PI / 2.0, 1.4)
		if barricade_1 != null:
			_obstacle_props.append(barricade_1)
		_solid(Vector3(2.5, 1.0, 0.0), Vector3(0.3, 2.0, 1.6))
	# Basement door: locked until day 7.
	if not _unlocked_floors.has("basement"):
		var h: Vector3 = ROOM_POSITIONS["hall"]
		var barricade_2: Node3D = _bprop("barricade-window-a.glb", h + Vector3(2.5, 0.9, 1.8), PI / 2.0, 1.4)
		if barricade_2 != null:
			_obstacle_props.append(barricade_2)
		_solid(Vector3(2.5, 1.0, 1.5), Vector3(0.3, 2.0, 1.2))
	# Attic hatch: on second floor, blocked until day 5.
	if _unlocked_floors.has("second") and not _unlocked_floors.has("attic"):
		var sy := FLOOR_Y["second"]
		var barricade_3: Node3D = _bprop("barricade-window-a.glb", Vector3(2.5, sy + 0.9, 1.5), PI / 2.0, 1.0)
		if barricade_3 != null:
			_obstacle_props.append(barricade_3)
		_solid(Vector3(2.5, sy + 1.0, 1.5), Vector3(0.3, 0.6, 1.0))

func set_mood(day: bool) -> void:
	_is_night = not day
	var energy := 2.2 if day else 1.1
	var tint := Color(1.0, 0.92, 0.8) if day else Color(0.9, 0.6, 0.55)
	for l in _lights.values():
		l.light_energy = energy
		l.light_color = tint
	for l in _lamp_lights:
		l.light_energy = 0.9 if day else 0.5
	_refresh_window()

func set_tv_on(on: bool) -> void:
	_tv_on = on


func toggle_cabinets() -> bool:
	_cabinets_open = not _cabinets_open
	for h in _cab_hinges:
		var hinge_sign: float = h.get_meta("hinge_sign")
		h.rotation.y = hinge_sign * PI / 2.0 if _cabinets_open else 0.0
	_set_label("cabinet", "CLOSE CABINET" if _cabinets_open else "OPEN CABINET")
	return _cabinets_open


func toggle_drawer() -> bool:
	_drawer_open = not _drawer_open
	if _drawer != null:
		_drawer.position.x += -0.3 if _drawer_open else 0.3
	_set_label("drawer", "CLOSE DRAWER" if _drawer_open else "PULL DRAWER")
	return _drawer_open


func toggle_tap() -> bool:
	_tap_on = not _tap_on
	if _tap_streak != null:
		_tap_streak.visible = _tap_on
	if _tap_on:
		AudioManager.play_tap()
	else:
		AudioManager.stop_tap()
	_set_label("tap", "TURN OFF TAP" if _tap_on else "TURN ON TAP")
	return _tap_on


func _set_label(id: String, label: String) -> void:
	for it in _interactables:
		if str(it.get("id", "")) == id:
			it["label"] = label
			return

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
		var turned := bool(g.get("turned", false))
		if turned:
			body.set_corruption(1.0)
		_guest_bodies[str(g.get("id", ""))] = body
		_guest_interactables.append({"id": "guest", "pos": pos + Vector3(0, 1.0, 0),
			"label": ("TURNED — " if turned else "") + str(g.get("name", "GUEST")).to_upper(), "guest": g})

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
	var mi := _mesh(parent, mesh, _wall_material() if col == WALL_COL else _mat(col))
	mi.name = "box_%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	mi.position = pos
	return mi

## Shared wall material: faint noise grain so flat walls don't read as
## untextured slabs. Noise averages mid-grey, so the tint doubles to keep
## the mean at WALL_COL.
var _wall_mat: StandardMaterial3D

func _wall_material() -> StandardMaterial3D:
	if _wall_mat != null:
		return _wall_mat
	_wall_mat = _mat(WALL_COL)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.6
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	_wall_mat.albedo_texture = tex
	_wall_mat.albedo_color = Color(WALL_COL.r * 2.0, WALL_COL.g * 2.0, WALL_COL.b * 2.0)
	_wall_mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return _wall_mat

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
	_build_floor_at("ground", FLOOR_Y["ground"], ROOM_POSITIONS, ROOM_SIZES, DOORS)
	_build_bedroom()
	_build_hall()
	_build_kitchen()
	_build_office()
	_build_bathroom()
	_build_decor()
	_build_structure()
	# Stairs to second floor: always visible, blocked by obstacle until day 3.
	_box(self, Vector3(2.5, FLOOR_Y["ground"] + 0.05, 0.0), Vector3(1.5, 0.1, 1.5), DOOR_COL)
	# Basement door: always visible, locked until day 7.
	_box(self, Vector3(2.5, FLOOR_Y["ground"] + 0.05, 1.5), Vector3(1.5, 0.1, 1.0), DOOR_COL)
	if _unlocked_floors.has("second"):
		_build_floor_at("second", FLOOR_Y["second"], SECOND_FLOOR_ROOMS, SECOND_FLOOR_SIZES, SECOND_FLOOR_DOORS)
		_build_second_floor()
	if _unlocked_floors.has("attic"):
		_build_floor_at("attic", FLOOR_Y["attic"], ATTIC_ROOMS, ATTIC_SIZES, ATTIC_DOORS)
		_build_attic()
	if _unlocked_floors.has("basement"):
		_build_floor_at("basement", FLOOR_Y["basement"], BASEMENT_ROOMS, BASEMENT_SIZES, BASEMENT_DOORS)
		_build_basement()

## Builds floor geometry (floor slab + walls + ceiling + lights) for a set of rooms at a Y offset.
func _build_floor_at(floor_name: String, y_off: float, rooms: Dictionary, sizes: Dictionary, doors: Dictionary) -> void:
	for room in rooms:
		var base := Vector3(rooms[room].x, y_off, rooms[room].z)
		var sz: Vector2 = sizes.get(room, Vector2(4, 4))
		var hz := sz * 0.5
		_box(self, base + Vector3(0, -0.1, 0), Vector3(hz.x * 2.0, 0.2, hz.y * 2.0), FLOOR_COL)
		_wall(base, hz, "z", -1.0, doors.get(room, {}).get("n", false))
		_wall(base, hz, "z", 1.0, doors.get(room, {}).get("s", false))
		_wall(base, hz, "x", -1.0, doors.get(room, {}).get("w", false))
		_wall(base, hz, "x", 1.0, doors.get(room, {}).get("e", false))
		var light := OmniLight3D.new()
		light.position = base + Vector3(0, 2.6, 0)
		light.omni_range = 12.0
		light.light_energy = 2.2
		add_child(light)
		_lights[room] = light

## Wall builder — called by _build_floor_at for any floor.
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
	var bed := _prop("bedSingle.glb", base + Vector3(-1.72, 0, -0.8), 0.0, 1.7)
	_prop("pillow.glb", base + Vector3(-1.72, 0.62, -1.5), 0.0, 1.7)
	_prop("sideTable.glb", base + Vector3(-0.85, 0, -1.6), 0.0, 1.2)
	# Cabinet flush on the south wall (facing the bed), front into the room.
	_prop("cabinetTelevision.glb", base + Vector3(-1.3, 0, 1.75), PI, 2.0)
	# Screen stands on the cabinet top (0.62), mid-stand, panel facing the bed.
	var tv_pair: Array = _emissive(base + Vector3(-1.3, 1.02, 1.75), Vector3(1.4, 0.8, 0.08), Color(0.1, 0.12, 0.15))
	_tv_mat = tv_pair[1]
	var radio := _prop("radio.glb", base + Vector3(-0.85, 0.46, -1.6), 0.0, 1.5)
	# Salvaged radiator hugging the north wall — shelter heating.
	_pack_prop("radiator small", base + Vector3(0.9, 0, -1.88), -PI / 2.0)
	_focus_boxes["bed"] = _world_box(bed).grow(0.15)
	_focus_boxes["tv"] = _world_box(tv_pair[0] as Node3D).grow(0.06)
	_focus_boxes["radio"] = _world_box(radio).grow(0.12)

func _build_hall() -> void:
	var base: Vector3 = ROOM_POSITIONS["hall"]
	_build_window(base + Vector3(1.8, 1.8, -2.94))
	# Real door leaf in the frame — the slab read as a hole in the wall.
	_bprop("door-rotate-square-a.glb", base + Vector3(-1.8, 0, 2.96), PI / 2.0, 1.0)
	var doorframe := _prop("doorwayFront.glb", base + Vector3(-1.8, 0, 2.9), 0.0, 2.1)
	_focus_boxes["front_door"] = _world_box(doorframe).grow(0.1)
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
	_focus_boxes["window"] = _world_box(win[0] as Node3D).grow(0.08)
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
	var sink := _prop("kitchenSink.glb", base + Vector3(1.55, 0, 0.0), -PI / 2.0, 2.0)
	var cab_n := _prop("kitchenCabinet.glb", base + Vector3(1.55, 0, -1.0), -PI / 2.0, 2.0)
	_prop("kitchenCabinet.glb", base + Vector3(1.55, 0, 1.0), -PI / 2.0, 2.0)
	# Fridge flush on the west wall (depth 0.58 scaled).
	_prop("kitchenFridgeSmall.glb", base + Vector3(-1.71, 0, -1.5), PI / 2.0, 2.0)
	# Hospital storage flush on the west wall, wall unit stacked on its base.
	_atomic("cupboard_bottom.glb", base + Vector3(-1.8, 0, 0.6), PI / 2.0)
	_atomic("cupboard_top.glb", base + Vector3(-1.85, 0.69, 0.6), PI / 2.0)
	# Serving counter flush on the south wall (depth 1.38).
	_pack_prop("caffetaria_001", base + Vector3(-0.3, 0, 1.31), PI)
	# --- kitchen realism: wall cabinets, drawer, tap --------------------------
	# Procedural add-ons wear the set's own paint (sampled GLB finishes —
	# flat Kenney materials, no textures) instead of the generic WOOD_COL.
	var cab_tint := _finish(cab_n, WOOD_COL)
	var sink_tint := _finish(sink, Color(0.5, 0.48, 0.45))
	_wall_cabinet(base + Vector3(1.825, 1.75, -1.0), 1.0, cab_tint)
	_wall_cabinet(base + Vector3(1.825, 1.75, 1.0), -1.0, cab_tint)
	_drawer = Node3D.new()
	_drawer.name = "kinematic_drawer"
	_drawer.position = base + Vector3(0.94, 0.55, -1.0)
	add_child(_drawer)
	_box(_drawer, Vector3.ZERO, Vector3(0.36, 0.28, 0.7), cab_tint)
	_box(_drawer, Vector3(-0.19, 0, 0), Vector3(0.02, 0.05, 0.18), cab_tint.darkened(0.45))
	# Faucet rides its own unscaled rig (NOT a sink child — the sink prop is
	# scaled x2, which once launched the tap halfway to the ceiling).
	var rig := Node3D.new()
	rig.name = "tap_rig"
	add_child(rig)
	_box(rig, base + Vector3(1.85, 1.13, 0.0), Vector3(0.06, 0.30, 0.06), sink_tint)
	_box(rig, base + Vector3(1.77, 1.26, 0.0), Vector3(0.22, 0.05, 0.05), sink_tint)
	var streak := _box(rig, base + Vector3(1.68, 1.04, 0.0), Vector3(0.035, 0.40, 0.035), Color(0, 0, 0))
	var water := _mat(Color(0.2, 0.4, 0.38))
	water.emission_enabled = true
	water.emission = Color(0.35, 0.8, 0.7)
	water.emission_energy_multiplier = 0.9
	streak.material_override = water
	streak.visible = false
	_tap_streak = streak
	_tap_mat = water
	var cab_box: AABB = _world_box(_cab_bodies[0]).merge(_world_box(_cab_bodies[1]))
	cab_box.position.x -= 0.62
	cab_box.size.x += 0.62
	_focus_boxes["cabinet"] = cab_box
	_focus_boxes["drawer"] = AABB(base + Vector3(0.40, 0.35, -1.41), Vector3(0.78, 0.5, 0.82))
	_focus_boxes["tap"] = AABB(base + Vector3(1.30, 0.80, -0.18), Vector3(0.62, 0.62, 0.36))
	# Scavenge box is explicit: the grown sink-GLB box would swallow the
	# tap/cabinet rays. ymax 1.23 threads the needle — above the sink-look
	# x-entry (1.21) so SCAVENGE wins its pose, below the tap-look top-entry
	# (1.47, past the tap box at 1.42) so TAP wins its own.
	_focus_boxes["scavenge"] = AABB(base + Vector3(0.90, -0.30, -0.73), Vector3(1.15, 1.529, 1.46))


## First imported finish under a prop, so procedural add-ons match the set.
func _finish(prop: Node3D, fallback: Color) -> Color:
	if prop == null:
		return fallback
	var stack: Array = [prop]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var m: Material = (cur as MeshInstance3D).get_active_material(0)
			if m is StandardMaterial3D:
				return (m as StandardMaterial3D).albedo_color
		stack.append_array(cur.get_children())
	return fallback


## Wall cabinet (armário aéreo): procedural shell + one hinged door leaf.
## hinge_sign +1: hinge on the +z edge, leaf opens swinging -X; -1 mirrored.
func _wall_cabinet(center: Vector3, hinge_sign: float, tint: Color) -> void:
	var cab := Node3D.new()
	cab.position = center
	add_child(cab)
	_box(cab, Vector3(0, 0.325, 0), Vector3(0.35, 0.05, 1.2), tint)
	_box(cab, Vector3(0, -0.325, 0), Vector3(0.35, 0.05, 1.2), tint)
	_box(cab, Vector3(0, 0, 0.575), Vector3(0.35, 0.7, 0.05), tint)
	_box(cab, Vector3(0, 0, -0.575), Vector3(0.35, 0.7, 0.05), tint)
	_box(cab, Vector3(0.155, 0, 0), Vector3(0.04, 0.7, 1.2), tint)
	_box(cab, Vector3(0.05, 0, 0), Vector3(0.02, 0.6, 1.08), tint.darkened(0.6))
	var hinge := Node3D.new()
	hinge.set_meta("hinge_sign", hinge_sign)
	hinge.position = Vector3(-0.155, 0, hinge_sign * 0.56)
	cab.add_child(hinge)
	_box(hinge, Vector3(-0.02, 0, -hinge_sign * 0.54), Vector3(0.04, 0.66, 1.08), tint)
	_cab_hinges.append(hinge)
	_cab_bodies.append(cab)

func _build_office() -> void:
	var base: Vector3 = ROOM_POSITIONS["office"]
	_prop("desk.glb", base + Vector3(-1.0, 0, -1.61), 0.0, 2.0)
	_prop("chairDesk.glb", base + Vector3(-1.0, 0, -0.9), PI, 1.6)
	_prop("bookcaseOpen.glb", base + Vector3(1.5, 0, 1.72), 0.0, 2.0)
	# Second workstation flush on the east wall (length 2.38 along it).
	_pack_prop("office table", base + Vector3(1.05, 0, -0.4), PI / 2.0)
	_pack_prop("chim chair_001", base + Vector3(-0.45, 0, -0.4), PI / 2.0)
	_box(self, base + Vector3(-0.6, 1.9, -1.95), Vector3(2.6, 0.2, 0.1), DOOR_COL)
	_box(self, base + Vector3(-1.2, 1.4, -1.95), Vector3(2.6, 0.2, 0.1), DOOR_COL)

func _build_bathroom() -> void:
	var base: Vector3 = ROOM_POSITIONS["bathroom"]
	# The north wall is mostly door gap — sink and mirror live on the east
	# wall, facing west into the room (sink depth 0.46 scaled).
	_prop("bathroomSink.glb", base + Vector3(1.27, 0, -0.2), -PI / 2.0, 1.6)
	var mirror_pair: Array = _emissive(base + Vector3(1.475, 1.7, -0.2), Vector3(0.05, 1.0, 0.8), Color(0.4, 0.5, 0.55))
	_focus_boxes["mirror"] = _world_box(mirror_pair[0] as Node3D).grow(0.06)
	_prop("toilet.glb", base + Vector3(-1.1, 0, 1.11), PI, 1.6)
	# Instrument tray clear of the doorway — triage kit by the west pier.
	_atomic("tray_1.glb", base + Vector3(-1.15, 0, -1.4), 0.0)

# --- second floor -------------------------------------------------------------

func _build_second_floor() -> void:
	var sy := FLOOR_Y["second"]
	# Storage room: crates and supplies.
	_prop("crate.glb", Vector3(-6.25, sy + 0.4, 0.0), 0.0, 1.5)
	_prop("crate.glb", Vector3(-6.25, sy + 0.4, 1.2), 0.0, 1.3)
	_prop("barrel.glb", Vector3(-5.0, sy + 0.5, -1.0), 0.0, 1.2)
	# Guest room: bed and side table.
	_prop("bedSingle.glb", Vector3(6.0, sy + 0.0, -0.8), 0.0, 1.7)
	_prop("sideTable.glb", Vector3(6.8, sy + 0.0, -1.6), 0.0, 1.2)
	# Hall_up: stairs down marker.
	_box(self, Vector3(2.5, sy + 0.05, 0.0), Vector3(1.5, 0.1, 1.5), DOOR_COL)
	# Attic hatch: always visible, blocked by obstacle until day 5.
	_box(self, Vector3(2.5, sy + 0.05, 1.5), Vector3(1.0, 0.1, 1.0), DOOR_COL)
	_focus_boxes["scavenge_storage"] = AABB(Vector3(-6.25, sy - 0.3, -0.73), Vector3(2.0, 1.5, 2.0))
	_focus_boxes["guest_room_bed"] = AABB(Vector3(6.0, sy + 0.3, -0.8), Vector3(1.5, 0.8, 2.0))

# --- attic --------------------------------------------------------------------

func _build_attic() -> void:
	var ay := FLOOR_Y["attic"]
	# Cramped storage: old furniture and boxes.
	_prop("cabinetTelevision.glb", Vector3(-6.25, ay + 0.0, 0.0), PI, 2.0)
	_prop("crate.glb", Vector3(-5.0, ay + 0.4, 1.0), 0.0, 1.2)
	_prop("rugRectangle.glb", Vector3(-6.25, ay + 0.02, 1.5), 0.0, 1.3)
	# Ladder access marker.
	_box(self, Vector3(2.5, ay + 0.05, 0.0), Vector3(1.0, 0.1, 1.0), DOOR_COL)
	_focus_boxes["search_attic"] = AABB(Vector3(-6.25, ay - 0.3, 0.0), Vector3(2.0, 1.5, 2.0))

# --- basement -----------------------------------------------------------------

func _build_basement() -> void:
	var by := FLOOR_Y["basement"]
	# Generator room: industrial equipment.
	_atomic("machine_1.glb", Vector3(-6.25, by + 0.0, 0.0), 0.0)
	_bprop("detail-pipe.glb", Vector3(-5.5, by + 1.5, -1.0), 0.0, 1.5)
	# Cellar: barrels and supplies.
	_prop("barrel.glb", Vector3(6.0, by + 0.5, 0.0), 0.0, 1.2)
	_prop("barrel.glb", Vector3(6.0, by + 0.5, 1.2), 0.0, 1.2)
	_prop("crate.glb", Vector3(5.0, by + 0.4, -1.0), 0.0, 1.3)
	# Stairs up marker.
	_box(self, Vector3(2.5, by + 0.05, 0.0), Vector3(1.5, 0.1, 1.5), DOOR_COL)
	_focus_boxes["generator"] = AABB(Vector3(-6.25, by - 0.3, 0.0), Vector3(2.0, 1.5, 2.0))
	_focus_boxes["cellar_search"] = AABB(Vector3(6.0, by - 0.3, 0.0), Vector3(2.0, 1.5, 2.0))

# --- structure: kit trim over the box shell ------------------------------------
# The 2m/2.4m kit modules don't match our 6x3m cells, so boxes stay structural
# and kit pieces land where they read: doors, barricades, baseboards, pipes.

func _build_structure() -> void:
	var h: Vector3 = ROOM_POSITIONS["hall"]
	var o: Vector3 = ROOM_POSITIONS["office"]
	var b: Vector3 = ROOM_POSITIONS["bedroom"]
	# Boarded office opening over the plank fortify: flat panel against the
	# wall face (rot PI/2 — rot 0 left it perpendicular, planks through the wall).
	var barricade := _bprop("barricade-window-a.glb", o + Vector3(-0.9, 0.95, -1.94), PI / 2.0, 1.2)
	_focus_boxes["fortify"] = _world_box(barricade).grow(0.1)
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
	# Patch plates flush on solid wall stretches (inner face + plate half-thick).
	_bprop("detail-pipe.glb", h + Vector3(2.7, 0, -2.7), 0.0, 1.5)
	_bprop("detail-pipe.glb", o + Vector3(2.1, 0, 1.5), 0.0, 1.5)
	_bprop("plating.glb", h + Vector3(-2.0, 1.1, -2.92), PI / 2.0, 1.5)
	_bprop("plating.glb", b + Vector3(2.18, 0.9, 1.55), 0.0, 1.2)

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
	_prop("plantSmall1.glb", k + Vector3(1.55, 0.9, -1.0), 0.0, 2.0)
	# Wall lamps: mesh + warm shade glow (the mesh itself is unlit plastic).
	_wall_lamp(b + Vector3(-1.5, 1.85, -1.89), 0.0)
	_wall_lamp(h + Vector3(-1.8, 2.35, 2.89), PI)
	_wall_lamp(o + Vector3(-2.14, 1.9, -0.5), PI / 2.0)
	_wall_lamp(t + Vector3(1.15, 1.9, -1.39), 0.0)
	# Kitchen ceiling dome (top kisses the implied 3.0 ceiling).
	_prop("lampSquareCeiling.glb", k + Vector3(0, 2.54, 0), 0.0, 2.0)
	_emissive(k + Vector3(0, 2.5, 0), Vector3(0.2, 0.03, 0.2), Color(1.0, 0.8, 0.55))
	# Hall ceiling fan — dark spinning shape overhead.
	_fan = _prop("ceilingFan.glb", h + Vector3(0, 2.6, 0), 0.0, 2.0)
	# Wainscot + wallpaper bands (thin boxes proud of the inner faces).
	_wainscot_wall(b, _half("bedroom"), "z", -1.0, Color(0.35, 0.28, 0.3))
	_wainscot_wall(b, _half("bedroom"), "x", -1.0, Color(0.35, 0.28, 0.3))
	_wainscot_wall(o, _half("office"), "z", -1.0, Color(0.3, 0.32, 0.28))

## Sconce on a wall: lamp mesh + warm shade quad seated just proud of the
## mesh's real front face (the old fixed 0.1m offset landed the glow INSIDE
## the mesh — lamps read as unlit plastic), plus a small omni so the wall
## around it actually receives light.
func _wall_lamp(pos: Vector3, rot_y: float) -> void:
	var lamp := _prop("lampWall.glb", pos, rot_y, 1.5)
	var fwd := Basis(Vector3.UP, rot_y) * Vector3(0, 0, 1)
	var reach := 0.14
	if lamp != null:
		var lb := _local_box_scaled(lamp, Basis.from_scale(Vector3.ONE * 1.5))
		reach = maxf(lb.size.z * 0.5, 0.06) + 0.02
	_emissive(pos + fwd * reach + Vector3(0, 0.02, 0), Vector3(0.28, 0.16, 0.03),
		Color(1.0, 0.72, 0.42))
	var light := OmniLight3D.new()
	light.position = pos + fwd * (reach + 0.3) + Vector3(0, 0.05, 0)
	light.omni_range = 2.2
	light.light_energy = 0.9
	light.light_color = Color(1.0, 0.78, 0.5)
	light.shadow_enabled = false
	add_child(light)
	_lamp_lights.append(light)

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
	if _tap_on and _tap_mat:
		_tap_mat.emission_energy_multiplier = randf_range(0.7, 1.1)
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
