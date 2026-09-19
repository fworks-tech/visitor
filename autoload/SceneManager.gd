# SceneManager.gd
# Handles smooth scene transitions with CRT scanline fade/glitch transition overlay.
extends Node

signal transition_started
signal transition_finished

var _overlay: CanvasLayer
var _color_rect: ColorRect
var _is_transitioning: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_create_transition_overlay()

func _create_transition_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	
	_color_rect = ColorRect.new()
	_color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_color_rect.color = Color(0, 0, 0, 0)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_overlay.add_child(_color_rect)
	add_child(_overlay)

func change_scene(scene_path: String, fade_duration: float = 0.4) -> void:
	if _is_transitioning:
		return
		
	_is_transitioning = true
	transition_started.emit()
	
	_color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Fade out (black overlay)
	var tween := create_tween()
	tween.tween_property(_color_rect, "color:a", 1.0, fade_duration)
	tween.tween_callback(func():
		var err := get_tree().change_scene_to_file(scene_path)
		if err != OK:
			push_error("[SceneManager] Failed to load scene: %s (Error code: %d)" % [scene_path, err])
			
		# Short delay at peak dark
		get_tree().create_timer(0.1).timeout.connect(func():
			var fade_in_tween := create_tween()
			fade_in_tween.tween_property(_color_rect, "color:a", 0.0, fade_duration)
			fade_in_tween.tween_callback(func():
				_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_is_transitioning = false
				transition_finished.emit()
			)
		)
	)
