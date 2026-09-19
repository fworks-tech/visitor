class_name HousePlayer3D
extends CharacterBody3D

## First-person walker for the checkpoint apartment. WASD/arrows + mouse,
## no jump, no sprint — you shuffle through the dark like everyone else.
## The scene captures the mouse; popups release it (see HouseScene).

const SPEED := 2.6
const MOUSE_SENS := 0.0025
const STICK_SENS := 2.5
const FLASH_ENERGY := 3.0

var camera: Camera3D
var spot: SpotLight3D
var flashlight_on: bool = true
var yaw: float = 0.0
var pitch: float = 0.0
var _dip: float = 0.0
var _bob: float = 0.0
var _moving: bool = false
# Joystick virtual (toque) injeta movimento aqui; teclado/gamepad vêm do InputMap.
var touch_move := Vector2.ZERO
const SPOT_HOME := Vector3(0.15, -0.12, 0.0)

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	spot = SpotLight3D.new()
	spot.position = SPOT_HOME
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.light_energy = FLASH_ENERGY
	spot.spot_range = 14.0
	spot.spot_angle = 38.0
	spot.shadow_enabled = true
	camera.add_child(spot)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flashlight_toggle") or _is_key(event, KEY_F):
		_try_toggle()
		return
	if event.is_action_pressed("battery_swap") or _is_key(event, KEY_R):
		if GameManager.replace_battery():
			flashlight_on = true
			spot.visible = true
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		drag_look(m.relative * MOUSE_SENS)


# Arrasto de toque chama isto com delta em radianos; mouse converte antes.
func drag_look(delta_rad: Vector2) -> void:
	yaw -= delta_rad.x
	pitch = clampf(pitch - delta_rad.y, -1.2, 1.2)
	rotation.y = yaw
	camera.rotation.x = pitch


# Reserva caso o InputMap falhe: comportamento teclado idêntico ao anterior.
func _is_key(event: InputEvent, code: Key) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed \
		and not (event as InputEventKey).echo and (event as InputEventKey).physical_keycode == code

func _try_toggle() -> void:
	# A dead cell cannot be switched on — find a spare (R) first.
	if not flashlight_on and GameManager.flashlight_battery <= 0.0:
		return
	flashlight_on = not flashlight_on
	spot.visible = flashlight_on

func _process(delta: float) -> void:
	if spot == null or camera == null:
		return
	_apply_stick_look(delta)
	# Handheld sway while walking; settles when still.
	if _moving:
		_bob += delta * 7.0
	else:
		_bob = lerpf(_bob, roundf(_bob / PI) * PI, minf(1.0, delta * 6.0))
	var sway := 1.0 if _moving else 0.0
	spot.position = SPOT_HOME + Vector3(sin(_bob) * 0.025 * sway, abs(cos(_bob)) * 0.02 * sway, 0.0)
	if not spot.visible:
		return
	GameManager.drain_battery(delta)
	if GameManager.flashlight_battery <= 0.0:
		flashlight_on = false
		spot.visible = false
		return
	# Dying-battery flicker: steady when full, ragged when low.
	var charge: float = GameManager.flashlight_battery / 100.0
	if randf() < lerpf(0.015, 0.12, 1.0 - charge):
		_dip = 0.09
	var e := FLASH_ENERGY * (0.55 + 0.45 * charge) * randf_range(0.96, 1.04)
	if _dip > 0.0:
		_dip -= delta
		e *= 0.35
	spot.light_energy = e

# Stick direito (ações look_*): analógico com deadzone do InputMap.
func _apply_stick_look(delta: float) -> void:
	if not InputMap.has_action("look_right"):
		return
	var lx := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var ly := Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
	if lx == 0.0 and ly == 0.0:
		return
	drag_look(Vector2(lx, ly) * STICK_SENS * delta)


func _physics_process(delta: float) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") \
		if InputMap.has_action("move_forward") else Vector2.ZERO
	var ix := iv.x + touch_move.x
	var iz := iv.y + touch_move.y
	if ix == 0.0 and iz == 0.0 and not InputMap.has_action("move_forward"):
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			iz -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			iz += 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			ix += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			ix -= 1.0
	var mag := Vector2(ix, iz).length()
	if mag > 1.0:
		ix /= mag
		iz /= mag
	var dir := (global_transform.basis * Vector3(ix, 0, iz))
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	_moving = dir != Vector3.ZERO
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y -= 9.8 * delta
	move_and_slide()
