# GameOver.gd
# Ending display — reason, outcome, restart / main menu.
extends Control

@onready var ending_title: Label = $EndingVBox/EndingTitle
@onready var ending_text: RichTextLabel = $EndingVBox/EndingText
@onready var restart_btn: Button = $EndingVBox/ButtonsHBox/RestartButton
@onready var menu_btn: Button = $EndingVBox/ButtonsHBox/MenuButton

const MAIN_MENU_PATH := "res://scenes/core/MainMenu.tscn"
const INSPECTION_SCENE_PATH := "res://scenes/gameplay/InspectionScene.tscn"

func _ready() -> void:
	GameManager.change_state(GameManager.GameState.GAME_OVER)
	AudioManager.play_ending_music(str(FlagsManager.get_flag("ending_id", "pariah")))
	if GameManager.has_method("get_ending_display"):
		var info: Dictionary = GameManager.get_ending_display()
		ending_title.text = str(info.get("title", "THE NIGHT ENDS"))
		ending_text.text = str(info.get("text", ""))
	else:
		ending_title.text = "THE NIGHT ENDS"
		ending_text.text = "Day %d. Trust %d. Corruption %d." % [
			GameManager.current_day, GameManager.trust_value, GameManager.corruption_value
		]

	restart_btn.pressed.connect(_on_restart)
	menu_btn.pressed.connect(_on_menu)

func _on_restart() -> void:
	SaveManager.delete_save()
	GameManager.start_new_game()
	VisitorManager.reset_history()
	GameManager.start_night_phase()
	VisitorManager.prepare_night_queue(GameManager.current_day)
	SceneManager.change_scene(INSPECTION_SCENE_PATH)

func _on_menu() -> void:
	SceneManager.change_scene(MAIN_MENU_PATH)
