class_name VisitorDiorama3D
extends Node3D

## The door stage: lights, camera and an empty doorframe. The actor is a
## VisitorBody3D — the same body house guests wear, so an NPC looks like
## itself everywhere. Suspicion/corruption play on the shared body.

var camera: Camera3D
var _doorframe: Node3D
var _body: VisitorBody3D
var _world_env: WorldEnvironment
var _environment: Environment

func _ready() -> void:
	_build_environment()
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.15, 1.35)
	camera.fov = 55.0
	add_child(camera)
	camera.current = true
	_build_doorframe()
	_doorframe.visible = false

func has_model() -> bool:
	return _body != null

func show_visitor(visitor: Dictionary, assigned_signs: Array) -> void:
	clear_visitor()
	_body = VisitorBody3D.new()
	add_child(_body)
	_body.build(visitor, assigned_signs, false)
	_doorframe.visible = false
	# Steps into the light instead of popping in.
	_body.position.z = 2.2
	var tw := create_tween()
	tw.tween_property(_body, "position:z", 0.0, 1.2).set_trans(Tween.TRANS_SINE)

func clear_visitor() -> void:
	if _body:
		_body.queue_free()
		_body = null
	_doorframe.visible = true

func show_sign(sign_data: Dictionary) -> void:
	if _body:
		_body.show_sign(sign_data)

func set_corruption(v: float) -> void:
	if _body:
		_body.set_corruption(v)

func reveal() -> void:
	if _body:
		_body.reveal()
		# Jump scare: the lens punches in as the face turns.
		if camera:
			var tw := create_tween()
			tw.tween_property(camera, "fov", 47.0, 0.09)
			tw.tween_property(camera, "fov", 55.0, 0.4)

# --- stage ---------------------------------------------------------------------

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.008, 0.006)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.36, 0.4)
	env.ambient_light_energy = 0.14
	_environment = env
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	add_child(_world_env)
	var key := OmniLight3D.new()
	key.position = Vector3(0.4, 2.1, 1.6)
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 0.85
	key.omni_range = 6.0
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-0.9, 1.6, -0.7)
	rim.light_color = Color(0.25, 0.95, 0.7)
	rim.light_energy = 2.4
	rim.omni_range = 5.0
	add_child(rim)

## The aperture stage brings its own environment; only one may drive a viewport.
func set_environment_enabled(enabled: bool) -> void:
	if _world_env:
		_world_env.environment = _environment if enabled else null

func _build_doorframe() -> void:
	_doorframe = Node3D.new()
	add_child(_doorframe)
	var wood := _mat(Color(0.12, 0.09, 0.07))
	for x in [-0.55, 0.55]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, 2.2, 0.2)
		post.mesh = pm
		post.material_override = wood
		post.position = Vector3(x, 1.1, -0.4)
		_doorframe.add_child(post)
	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.22, 0.12, 0.2)
	lintel.mesh = lm
	lintel.material_override = wood
	lintel.position = Vector3(0, 2.2, -0.4)
	_doorframe.add_child(lintel)
