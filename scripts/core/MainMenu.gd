# MainMenu.gd
# Main menu — New Game / Continue / Settings / Quit.
extends Control

@onready var new_game_btn: Button = $MenuVBox/NewGameButton
@onready var continue_btn: Button = $MenuVBox/ContinueButton
@onready var settings_btn: Button = $MenuVBox/SettingsButton
@onready var quit_btn: Button = $MenuVBox/QuitButton
@onready var version_label: Label = $VersionLabel

const INSPECTION_SCENE_PATH := "res://scenes/gameplay/InspectionScene.tscn"
const SETTINGS_SCENE_PATH := "res://scenes/ui/Settings.tscn"

func _ready() -> void:
	GameManager.change_state(GameManager.GameState.MENU)
	AudioManager.play_music("menu")  # the only music outside endings
	continue_btn.disabled = not SaveManager.has_save_file()
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

func _on_new_game() -> void:
	SaveManager.delete_save()  # fresh run wipes any old slot
	GameManager.start_new_game()  # start_night_phase routes to the house

func _on_continue() -> void:
	if SaveManager.load_game():
		# Route to the phase the save left off in
		match GameManager.current_state:
			GameManager.GameState.DAY, GameManager.GameState.NIGHT:
				SceneManager.change_scene(GameManager.HOUSE_SCENE_PATH)
			_:
				SceneManager.change_scene(INSPECTION_SCENE_PATH)
	else:
		continue_btn.disabled = true

func _on_settings() -> void:
	SceneManager.change_scene(SETTINGS_SCENE_PATH)

func _on_quit() -> void:
	get_tree().quit()
