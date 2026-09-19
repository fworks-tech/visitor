# SplashScreen.gd
# CRT power-on effect → title → auto-transition to MainMenu.
extends Control

@onready var crt_rect: ColorRect = $CRTBackground
@onready var title_label: Label = $TitleVBox/TitleLabel
@onready var subtitle_label: Label = $TitleVBox/SubtitleLabel
@onready var transition_timer: Timer = $TransitionTimer

const MAIN_MENU_PATH := "res://scenes/core/MainMenu.tscn"
const TRANSITION_DELAY := 3.0

func _ready() -> void:
	GameManager.change_state(GameManager.GameState.SPLASH)
	_initial_power_on()

func _initial_power_on() -> void:
	# Screen starts "off" (black), CRT scan line sweeps in, title flickers on.
	crt_rect.color = Color(0, 0, 0, 1)
	title_label.modulate.a = 0.0
	subtitle_label.modulate.a = 0.0

	var tween := create_tween()
	# CRT scan-line sweep: bright horizontal line expands to full screen
	tween.tween_property(crt_rect, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Title flickers on like a tube warming up — two stutters then solid
	tween.tween_callback(func(): title_label.modulate.a = 0.6)
	tween.tween_interval(0.1)
	tween.tween_callback(func(): title_label.modulate.a = 0.1)
	tween.tween_interval(0.15)
	tween.tween_callback(func(): title_label.modulate.a = 1.0)
	tween.parallel().tween_property(subtitle_label, "modulate:a", 1.0, 1.2)

	transition_timer.wait_time = TRANSITION_DELAY
	transition_timer.timeout.connect(_go_to_menu)
	transition_timer.start()

func _go_to_menu() -> void:
	GameManager.change_state(GameManager.GameState.MENU)
	SceneManager.change_scene(MAIN_MENU_PATH)

func _input(event: InputEvent) -> void:
	# Allow tap/click/any key to skip the splash
	if event is InputEventScreenTouch or event is InputEventMouseButton or (event is InputEventKey and event.pressed):
		_go_to_menu()
