class_name CRTController
extends CanvasLayer

## Controller for CRT curvature/scanlines and VHS distortion shaders.

@export var crt_rect_path: NodePath = "CRTRect"
@export var vhs_rect_path: NodePath = "VHSLayer/VHSRect"

@onready var crt_rect: ColorRect = get_node_or_null(crt_rect_path)
@onready var vhs_rect: ColorRect = get_node_or_null(vhs_rect_path)

var _crt_material: ShaderMaterial
var _vhs_material: ShaderMaterial

var _base_glitch_intensity: float = 0.15
var _base_scanline: float = 0.18
var _base_vignette: float = 0.35
var _is_powered_on: bool = true
var _active_glitch_tween: Tween = null

func _ready() -> void:
	layer = 100
	if crt_rect and crt_rect.material is ShaderMaterial:
		_crt_material = crt_rect.material as ShaderMaterial
	if vhs_rect and vhs_rect.material is ShaderMaterial:
		_vhs_material = vhs_rect.material as ShaderMaterial
	if _crt_material:
		_base_scanline = float(_crt_material.get_shader_parameter("scanline_opacity"))
		_base_vignette = float(_crt_material.get_shader_parameter("vignette_intensity"))
	SettingsManager.settings_changed.connect(apply_crt_settings)
	apply_crt_settings()

## Reads crt_effect_enabled/crt_intensity from SettingsManager (live via settings_changed).
func apply_crt_settings() -> void:
	var enabled := bool(SettingsManager.get_setting("crt_effect_enabled", true))
	var intensity := clampf(float(SettingsManager.get_setting("crt_intensity", 0.8)), 0.0, 1.0)
	visible = _is_powered_on and enabled
	if _crt_material:
		_crt_material.set_shader_parameter("scanline_opacity", _base_scanline * intensity)
		_crt_material.set_shader_parameter("vignette_intensity", _base_vignette * intensity)

## Adjusts base VHS glitch intensity (0.0 to 1.0).
## Call this when a visitor is suspicious, infected, or wrong.
func set_glitch_intensity(value: float) -> void:
	_base_glitch_intensity = clamp(value, 0.0, 1.0)
	if _vhs_material:
		_vhs_material.set_shader_parameter("glitch_intensity", _base_glitch_intensity)

## Triggers a temporary intense glitch spike for the specified duration in seconds.
func trigger_glitch(duration: float = 0.5) -> void:
	if not _vhs_material:
		return

	if _active_glitch_tween and _active_glitch_tween.is_valid():
		_active_glitch_tween.kill()

	var peak_glitch: float = min(1.0, _base_glitch_intensity + 0.65)
	_vhs_material.set_shader_parameter("glitch_intensity", peak_glitch)

	_active_glitch_tween = create_tween()
	_active_glitch_tween.tween_method(
		func(val: float):
			if _vhs_material:
				_vhs_material.set_shader_parameter("glitch_intensity", val),
		peak_glitch,
		_base_glitch_intensity,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## CRT Power-On animation (expands vertically from a bright thin line).
func power_on(duration: float = 0.6) -> void:
	_is_powered_on = true
	visible = true

	if crt_rect:
		crt_rect.pivot_offset = crt_rect.size * 0.5
		crt_rect.scale = Vector2(1.0, 0.01)

		var tween := create_tween().set_parallel(true)
		tween.tween_property(crt_rect, "scale", Vector2(1.0, 1.0), duration)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_OUT)

		if _crt_material:
			var target := _base_scanline * clampf(float(SettingsManager.get_setting("crt_intensity", 0.8)), 0.0, 1.0)
			_crt_material.set_shader_parameter("scanline_opacity", 0.5)
			tween.tween_method(
				func(val: float):
					if _crt_material:
						_crt_material.set_shader_parameter("scanline_opacity", val),
				0.5,
				target,
				duration
			)

## CRT Power-Off animation (collapses down to a thin line and powers down).
func power_off(duration: float = 0.4) -> void:
	_is_powered_on = false

	if crt_rect:
		crt_rect.pivot_offset = crt_rect.size * 0.5
		var tween := create_tween()
		tween.tween_property(crt_rect, "scale", Vector2(1.0, 0.002), duration)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_IN)
		tween.tween_callback(func(): visible = false)
