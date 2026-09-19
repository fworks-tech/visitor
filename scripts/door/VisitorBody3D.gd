class_name VisitorBody3D
extends Node3D

## The single source of truth for what an NPC looks like, everywhere:
## door diorama and house guests build the same body. A low-poly humanoid
## (legs optional) whose face is cropped from the visitor's own portrait
## and whose palette is sampled from it — Marcus looks like Marcus, in 3D.
## Physical signs attach as geometry; suspicion corrupts the face live.

const PHYSICAL_SIGN_IDS := ["s001", "s002", "s003", "s004", "s005", "s006",
	"s007", "s011", "s022", "s023", "s026", "s027", "s037"]
## Face band shared by all portraits: upper-center bust framing.
const FACE_UV := Rect2(0.34, 0.13, 0.28, 0.30)

var head: MeshInstance3D
var torso: MeshInstance3D
var jaw: MeshInstance3D
var mouth_open: MeshInstance3D
var hands: Array = []
var eyelids: Array = []
var eye_mats: Array = []
var skin_mats: Array = []
var skin_base: Color = Color(0.8, 0.74, 0.7)
var jaw_base_y: float = 0.0
var jaw_offset_x: float = 0.0
var face_mat: StandardMaterial3D
var reveal_face_tex: Texture2D

var _sign_ids: Array = []
var _shown_signs: Array = []
var _corruption: float = 0.0
var _time: float = 0.0
var _blink_timer: float = 2.0
var _blink_hold: float = 0.0
var _built: bool = false

func has_face() -> bool:
	return face_mat != null

func build(visitor: Dictionary, assigned_signs: Array, with_legs: bool) -> void:
	for c in get_children():
		c.queue_free()
	_reset_state()
	_sign_ids = []
	for s in assigned_signs:
		if s is Dictionary:
			_sign_ids.append(str(s.get("id", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(visitor.get("id", "x")))
	var tex := _portrait_tex(visitor)
	var pal := sample_palette(tex) if tex != null else {}
	_build_humanoid(rng, pal, with_legs)
	if tex != null:
		_build_face(tex)
		var reveal_path := str(visitor.get("reveal_portrait", ""))
		if reveal_path != "" and ResourceLoader.exists(reveal_path):
			var rt := load(reveal_path) as Texture2D
			if rt != null:
				reveal_face_tex = _face_atlas(rt)
	_built = true

func show_sign(sign_data: Dictionary) -> void:
	var sid := str(sign_data.get("id", ""))
	if sid == "" or sid in _shown_signs or not _built:
		return
	if sid in PHYSICAL_SIGN_IDS:
		_build_attachment(sid)
		_shown_signs.append(sid)

func set_corruption(v: float) -> void:
	_corruption = clampf(v, 0.0, 1.0)
	_apply_corruption()

func reveal() -> void:
	for sid in _sign_ids:
		if sid in PHYSICAL_SIGN_IDS and sid not in _shown_signs:
			_build_attachment(sid)
			_shown_signs.append(sid)
	if face_mat and reveal_face_tex:
		face_mat.albedo_texture = reveal_face_tex
	set_corruption(1.0)

func _reset_state() -> void:
	head = null
	torso = null
	jaw = null
	mouth_open = null
	hands.clear()
	eyelids.clear()
	eye_mats.clear()
	skin_mats.clear()
	face_mat = null
	reveal_face_tex = null
	_sign_ids.clear()
	_shown_signs.clear()
	_corruption = 0.0
	jaw_offset_x = 0.0

# --- portrait ---------------------------------------------------------------

func _portrait_tex(visitor: Dictionary) -> Texture2D:
	var path := str(visitor.get("portrait", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## Average color of a small patch — the portraits are monochrome green, so
## sampled cloth/skin/hair come out already graded for the scene.
static func sample_palette(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	if img == null:
		return {}
	return {
		"skin": _avg(img, Vector2(0.47, 0.27), 0.02),
		"coat": _avg(img, Vector2(0.5, 0.62), 0.05),
		"hair": _avg(img, Vector2(0.5, 0.05), 0.03),
	}

static func _avg(img: Image, uv: Vector2, half: float) -> Color:
	var w := float(img.get_width())
	var h := float(img.get_height())
	var acc := Color(0, 0, 0, 0)
	var n := 0.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var px := clampi(int((uv.x + dx * half / 2.0) * w), 0, img.get_width() - 1)
			var py := clampi(int((uv.y + dy * half / 2.0) * h), 0, img.get_height() - 1)
			acc += img.get_pixel(px, py)
			n += 1.0
	return acc / n if n > 0.0 else Color(0.5, 0.5, 0.5)

static func _face_atlas(tex: Texture2D) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2(FACE_UV.position * tex.get_size(), FACE_UV.size * tex.get_size())
	return a

func _build_face(tex: Texture2D) -> void:
	face_mat = StandardMaterial3D.new()
	face_mat.albedo_texture = _face_atlas(tex)
	face_mat.roughness = 0.95
	var quad := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.17, 0.18)
	quad.mesh = plane
	quad.material_override = face_mat
	# Painted over the head box, under the glowing 3D eyes.
	quad.position = Vector3(0, 1.585, 0.113)
	add_child(quad)

# --- construction -------------------------------------------------------------

func _mat(col: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _ball(pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _build_humanoid(rng: RandomNumberGenerator, pal: Dictionary, with_legs: bool) -> void:
	var suit := "s023" in _sign_ids
	var cloth: Color = pal.get("coat", Color(0.12, 0.12, 0.13))
	if pal.is_empty():
		cloth = Color(0.1, 0.16, 0.1) if suit else Color(
			rng.randf_range(0.08, 0.16), rng.randf_range(0.08, 0.14), rng.randf_range(0.08, 0.14))
	skin_base = pal.get("skin", Color(
		rng.randf_range(0.72, 0.84), rng.randf_range(0.68, 0.78), rng.randf_range(0.64, 0.74)))
	var pants: Color = (pal.get("coat", cloth) as Color).darkened(0.45)
	var skin := _mat(skin_base)
	var skin_dark := _mat(skin_base * 0.7)
	skin_mats = [skin, skin_dark]
	var shoulder_w := rng.randf_range(0.5, 0.62)
	var head_w := rng.randf_range(0.19, 0.23)
	var head_h := rng.randf_range(0.23, 0.26)
	var head_d := 0.22
	var asym := rng.randf_range(-0.012, 0.012)
	if "s027" in _sign_ids:
		asym += 0.02

	if with_legs:
		for side in [-1.0, 1.0]:
			_box(Vector3(side * 0.11, 0.42, 0), Vector3(0.13, 0.4, 0.15), _mat(pants))
			_box(Vector3(side * 0.11, 0.12, 0), Vector3(0.11, 0.28, 0.12), _mat(pants.darkened(0.2)))
			_box(Vector3(side * 0.11, 0.035, 0.03), Vector3(0.12, 0.07, 0.24), _mat(Color(0.05, 0.045, 0.05)))

	torso = _box(Vector3(0, 0.95, 0), Vector3(shoulder_w, 0.75, 0.32), _mat(cloth))
	_box(Vector3(0, 1.36, 0), Vector3(0.12, 0.1, 0.12), skin_dark)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (shoulder_w / 2.0 + 0.06), 0.95, 0.02),
			Vector3(0.11, 0.65, 0.13), _mat(cloth))
		hands.append(_box(Vector3(side * (shoulder_w / 2.0 + 0.06), 0.58, 0.03),
			Vector3(0.09, 0.12, 0.1), skin))

	head = _box(Vector3(0, 1.58, 0), Vector3(head_w, head_h, head_d), skin)
	jaw = _box(Vector3(0, 1.49, 0.005), Vector3(head_w * 0.9, 0.07, head_d * 0.95), skin_dark)
	jaw_base_y = 1.49
	mouth_open = _box(Vector3(0, 1.485, head_d * 0.48), Vector3(0.06, 0.05, 0.01), _mat(Color(0.01, 0.0, 0.0)))
	mouth_open.scale.y = 0.05
	# The painted portrait carries nose and mouth — skip the blocky ones then.
	_box(Vector3(0, 1.515, head_d / 2.0 + 0.002), Vector3(0.07, 0.012, 0.01), _mat(Color(0.25, 0.1, 0.1)))

	var eye_space := rng.randf_range(0.04, 0.055)
	for side in [-1.0, 1.0]:
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.02, 0.02, 0.025)
		em.emission_enabled = true
		em.emission = Color(0.5, 0.6, 0.58)
		em.emission_energy_multiplier = 0.5
		eye_mats.append(em)
		_ball(Vector3(side * eye_space + asym, 1.6, head_d / 2.0), 0.024, em)
		eyelids.append(_box(Vector3(side * eye_space + asym, 1.622, head_d / 2.0 + 0.004),
			Vector3(0.05, 0.008, 0.012), skin_dark))

	var hair_col: Color = pal.get("hair", Color(0.07, 0.06, 0.055))
	match rng.randi_range(0, 2):
		0:  # cropped cap
			_box(Vector3(0, 1.72, -0.01), Vector3(head_w + 0.04, 0.07, head_d + 0.02), _mat(hair_col))
		1:  # long, hangs at the sides
			var hair := _mat(hair_col)
			_box(Vector3(0, 1.68, -0.05), Vector3(head_w + 0.05, 0.06, 0.12), hair)
			for side in [-1.0, 1.0]:
				_box(Vector3(side * (head_w / 2.0 + 0.02), 1.5, -0.02),
					Vector3(0.05, 0.25, 0.1), hair)
		_:  # bald
			pass

	if suit or "s022" in _sign_ids:
		var hood := _mat(Color(0.09, 0.13, 0.08) if suit else Color(0.07, 0.07, 0.08))
		_box(Vector3(0, 1.78, -0.04), Vector3(head_w + 0.12, 0.08, head_d + 0.06), hood)
		for side in [-1.0, 1.0]:
			_box(Vector3(side * (head_w / 2.0 + 0.05), 1.6, -0.06),
				Vector3(0.06, 0.3, 0.12), hood)

	if "s005" in _sign_ids:
		jaw_offset_x = 0.03
		jaw.position.x = jaw_offset_x

func _build_attachment(sid: String) -> void:
	match sid:
		"s001":  # rash patches on cheek and neck
			var rash := _mat(Color(0.45, 0.12, 0.1))
			skin_mats.append(rash)
			for p in [Vector3(0.07, 1.56, 0.112), Vector3(-0.06, 1.6, 0.112),
					Vector3(0.03, 1.38, 0.062), Vector3(-0.04, 1.54, 0.112)]:
				_box(p, Vector3(0.03, 0.025, 0.008), rash)
		"s002":  # dark veins on neck and temple
			var vein := _mat(Color(0.05, 0.02, 0.06))
			for p in [Vector3(0.03, 1.36, 0.062), Vector3(-0.03, 1.36, 0.062),
					Vector3(0.1, 1.6, 0.05), Vector3(-0.1, 1.6, 0.05)]:
				_box(p, Vector3(0.012, 0.09, 0.006), vein)
		"s003":  # too many teeth, jaw hangs
			_box(Vector3(0, 1.5, 0.108), Vector3(0.075, 0.02, 0.012), _mat(Color(0.8, 0.78, 0.7)))
			jaw.position.y -= 0.02
			jaw_base_y = jaw.position.y
		"s004":  # two puncture marks on the neck
			var wound := _mat(Color(0.3, 0.03, 0.03))
			skin_mats.append(wound)
			for p in [Vector3(0.035, 1.37, 0.055), Vector3(0.055, 1.365, 0.05)]:
				var mesh := CylinderMesh.new()
				mesh.top_radius = 0.008
				mesh.bottom_radius = 0.008
				mesh.height = 0.012
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = wound
				mi.position = p
				mi.rotation.x = PI / 2.0
				add_child(mi)
		"s037":  # weeps black
			var tear := _mat(Color(0.01, 0.01, 0.015))
			for side in [-1.0, 1.0]:
				_box(Vector3(side * 0.048, 1.55, 0.108), Vector3(0.01, 0.07, 0.006), tear)

func _apply_corruption() -> void:
	var rot := skin_base.lerp(Color(0.4, 0.3, 0.3), _corruption)
	for m in skin_mats:
		m.albedo_color = rot if m.albedo_color.get_luminance() > 0.2 else m.albedo_color
	for em in eye_mats:
		em.emission = Color(0.5, 0.6, 0.58).lerp(Color(1.0, 0.08, 0.05), _corruption)
		em.emission_energy_multiplier = 0.5 + _corruption * 2.5
	if jaw:
		jaw.position.y = jaw_base_y - _corruption * 0.035
		jaw.position.x = jaw_offset_x + _corruption * 0.012
	if mouth_open:
		mouth_open.scale.y = 0.05 + _corruption * 0.95
	if head:
		head.rotation.z = _corruption * 0.09
	rotation.z = _corruption * 0.03

# --- idle life -----------------------------------------------------------------

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	rotation.y = sin(_time * 0.5) * 0.035
	var breathe_rate := 1.1
	var breathe_amp := 0.012
	if "s026" in _shown_signs:
		breathe_rate = 2.4
		breathe_amp = 0.05
	if torso:
		torso.scale.y = 1.0 + breathe_amp * sin(_time * breathe_rate)
	if "s011" in _shown_signs:
		for h in hands:
			h.position.x += sin(_time * 38.0) * 0.0009
	# Eyelids: synced slow blink when s006 shows, sparse blinks otherwise.
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_hold = 0.4 if "s006" in _shown_signs else 0.12
		_blink_timer = 6.0 if "s006" in _shown_signs else _time * 0.0 + 2.5 + fmod(_time, 2.0)
	if _blink_hold > 0.0:
		_blink_hold -= delta
		for lid in eyelids:
			lid.scale.y = 6.0
	else:
		for lid in eyelids:
			lid.scale.y = 1.0
