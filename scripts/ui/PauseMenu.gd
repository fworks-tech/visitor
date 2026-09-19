# PauseMenu.gd
# Pause overlay — resume, settings, quit to menu.
extends CanvasLayer

signal resume_pressed
signal quit_to_menu_pressed

@onready var resume_btn: Button = $PausePanel/VBox/ResumeButton
@onready var settings_btn: Button = $PausePanel/VBox/SettingsButton
@onready var quit_btn: Button = $PausePanel/VBox/QuitButton

const MAIN_MENU_PATH := "res://scenes/core/MainMenu.tscn"

func _ready() -> void:
	visible = false
	resume_btn.pressed.connect(_on_resume)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		GameManager.change_state(GameManager.GameState.PAUSED)

func _on_resume() -> void:
	get_tree().paused = false
	visible = false
	emit_signal("resume_pressed")

func _on_settings() -> void:
	# Settings is embedded via pause; simplest approach: open as sub-scene later.
	# For now, route to the full settings scene.
	get_tree().paused = false
	SceneManager.change_scene("res://scenes/ui/Settings.tscn")

func _on_quit() -> void:
	get_tree().paused = false
	SaveManager.save_game()
	emit_signal("quit_to_menu_pressed")
	SceneManager.change_scene(MAIN_MENU_PATH)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()
