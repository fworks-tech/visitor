class_name ApertureStage
extends Node3D

## A composable view stage: a 2D environment plate behind, the real 3D visitor
## body in front, and a one-pass aperture shader (fisheye, green grade, grain,
## mask). Drop it in a SubViewport and call set_view + set_visitor.
##
## The environment plate is unshaded so its photo lighting survives; the body
## gets a per-preset key/fill/rim so it sits in the same light. The green grade
## then unifies both, which is what makes the composite read as one image.

const POST_SHADER := "res://shaders/aperture_post.gdshader"

var camera: Camera3D
var _body: VisitorBody3D
var _backdrop: MeshInstance3D
var _backdrop_mat: StandardMaterial3D
var _post_layer: CanvasLayer
var _post_rect: ColorRect
var _post_mat: ShaderMaterial
var _key: OmniLight3D
var _fill: OmniLight3D
var _rim: OmniLight3D
var _world_env: WorldEnvironment
var _env_resource: Environment
var _preset: Dictionary = {}

func _ready() -> void:
	_build_camera()
	_build_lights()
	_build_backdrop()
	_build_environment()
	_build_post()

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.55, 1.35)
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 40.0
	add_child(camera)
	camera.current = true

func _build_lights() -> void:
	_key = OmniLight3D.new()
	_key.position = Vector3(0.6, 2.05, 1.2)
	_key.omni_range = 6.0
	_key.shadow_enabled = true
	_key.light_energy = 1.0
	add_child(_key)

	_fill = OmniLight3D.new()
	_fill.position = Vector3(-1.2, 1.45, 0.9)
	_fill.omni_range = 5.0
	_fill.light_energy = 0.25
	add_child(_fill)

	_rim = OmniLight3D.new()
	_rim.position = Vector3(0.0, 1.85, -1.1)
	_rim.omni_range = 4.0
	_rim.light_energy = 0.4
	add_child(_rim)

func _build_backdrop() -> void:
	_backdrop = MeshInstance3D.new()
	_backdrop.mesh = QuadMesh.new()
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop_mat = StandardMaterial3D.new()
	_backdrop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_backdrop_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_backdrop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_backdrop.material_override = _backdrop_mat
	add_child(_backdrop)

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.006, 0.005)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.36, 0.32)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env_resource = env
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	add_child(_world_env)

func _build_post() -> void:
	_post_layer = CanvasLayer.new()
	_post_layer.layer = 10
	add_child(_post_layer)

	# Copy the 3D viewport before the shader samples SCREEN_TEXTURE.
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_post_layer.add_child(copy)

	_post_rect = ColorRect.new()
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_rect.color = Color.WHITE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load(POST_SHADER)
	_post_rect.material = _post_mat
	_post_layer.add_child(_post_rect)
	_post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_resize_post)
	_resize_post()

func _resize_post() -> void:
	if _post_mat == null:
		return
	var size: Vector2i = get_viewport().size
	_post_mat.set_shader_parameter("aspect", float(size.x) / maxf(1.0, float(size.y)))

## Applies aperture + environment + visitor override. Does not build the body.
func set_view(aperture_id: String, environment_id: String, visitor_id: String = "") -> void:
	if camera == null:
		push_warning("ApertureStage.set_view called before ready")
		return
	_preset = ViewPresets.resolve(aperture_id, environment_id, visitor_id)
	_apply_camera()
	_apply_backdrop()
	_apply_lights()
	_apply_post()
	if _body:
		_apply_anchor()

func set_visitor(visitor: Dictionary, assigned_signs: Array = []) -> void:
	clear_visitor()
	if visitor.is_empty():
		return
	_body = VisitorBody3D.new()
	add_child(_body)
	_body.build(visitor, assigned_signs, false)
	_apply_anchor()

func _apply_anchor() -> void:
	if _body == null:
		return
	var a: Dictionary = _preset.get("anchor", {})
	_body.position = Vector3(
		float(a.get("x", 0.0)),
		float(a.get("y", 0.0)),
		float(a.get("z", 0.0)))
	_body.scale = Vector3.ONE * float(a.get("scale", 1.0))
	_body.rotation.y = deg_to_rad(float(a.get("yaw", 0.0)))

func clear_visitor() -> void:
	if _body:
		_body.queue_free()
		_body = null

func get_preset() -> Dictionary:
	return _preset.duplicate()

## Turns the whole stage (3D children, camera and post layer) on or off.
func set_active(active: bool) -> void:
	visible = active
	if _post_layer:
		_post_layer.visible = active
	if camera:
		camera.current = active
	# Only one WorldEnvironment may drive the viewport: hand it back to the
	# diorama when the aperture stage sleeps.
	if _world_env:
		_world_env.environment = _env_resource if active else null

func has_model() -> bool:
	return _body != null

func show_sign(sign_data: Dictionary) -> void:
	if _body:
		_body.show_sign(sign_data)

func set_corruption(v: float) -> void:
	if _body:
		_body.set_corruption(v)

func reveal() -> void:
	if _body:
		_body.reveal()
	if camera == null:
		return
	var base := camera.fov
	var tw := create_tween()
	tw.tween_property(camera, "fov", base * 0.85, 0.09)
	tw.tween_property(camera, "fov", base, 0.4)

func _apply_camera() -> void:
	var cam: Dictionary = _preset.get("camera", {})
	camera.position = Vector3(0, float(cam.get("height", 1.55)), float(cam.get("distance", 1.35)))
	camera.fov = float(cam.get("fov", 62.0))
	camera.rotation = Vector3.ZERO

func _apply_backdrop() -> void:
	var path := str(_preset.get("texture", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		_backdrop.visible = false
		return
	var tex := load(path) as Texture2D
	if tex == null:
		_backdrop.visible = false
		return
	_backdrop.visible = true
	_backdrop_mat.albedo_texture = tex

	var depth := float(_preset.get("depth", -6.0))
	var dist: float = camera.position.z - depth
	var vp_size: Vector2i = get_viewport().size
	var aspect: float = 16.0 / 9.0
	if vp_size.y > 0:
		aspect = float(vp_size.x) / float(vp_size.y)
	var h: float = 2.0 * dist * tan(deg_to_rad(camera.fov * 0.5))
	var w: float = h * aspect
	var quad := _backdrop.mesh as QuadMesh
	quad.size = Vector2(w, h)
	_backdrop.position = Vector3(0, camera.position.y, depth)

func _apply_lights() -> void:
	var light: Dictionary = _preset.get("light", {})
	_key.light_color = _as_color(light.get("key_color"), Color(1.0, 0.85, 0.7))
	_key.light_energy = float(light.get("key_energy", 1.0))
	_fill.light_color = _as_color(light.get("fill_color"), Color(0.25, 0.35, 0.3))
	_fill.light_energy = float(light.get("fill_energy", 0.2))
	_rim.light_color = _as_color(light.get("rim_color"), Color(0.2, 0.65, 0.5))
	_rim.light_energy = float(light.get("rim_energy", 0.3))

func _apply_post() -> void:
	if _post_mat == null:
		return
	_post_mat.set_shader_parameter("mask_shape", int(_preset.get("shape", 0)))
	_post_mat.set_shader_parameter("mask_center", _as_vec2(_preset.get("mask_center"), Vector2(0.5, 0.5)))
	_post_mat.set_shader_parameter("mask_size", _as_vec2(_preset.get("mask_size"), Vector2(0.92, 0.92)))
	_post_mat.set_shader_parameter("mask_softness", float(_preset.get("mask_softness", 0.02)))
	_post_mat.set_shader_parameter("fisheye", float(_preset.get("fisheye", 0.3)))
	_post_mat.set_shader_parameter("zoom", float(_preset.get("zoom", 1.05)))
	_post_mat.set_shader_parameter("tint", _as_color(_preset.get("tint"), Color(0.72, 0.86, 0.72)))
	_post_mat.set_shader_parameter("tint_mix", float(_preset.get("tint_mix", 0.55)))
	_post_mat.set_shader_parameter("grain", float(_preset.get("grain", 0.05)))
	_post_mat.set_shader_parameter("scanlines", float(_preset.get("scanlines", 0.06)))
	_post_mat.set_shader_parameter("vignette", float(_preset.get("vignette", 0.75)))
	_post_mat.set_shader_parameter("aberration", float(_preset.get("aberration", 0.002)))
	_post_mat.set_shader_parameter("tracking", float(_preset.get("tracking", 0.002)))
	_post_mat.set_shader_parameter("exposure", float(_preset.get("exposure", 1.0)))

func _as_color(v, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback

func _as_vec2(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback
