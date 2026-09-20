extends Node

## Store-asset grab: `godot --path . -- --screenshot` (NOT --headless: a real
## window is required for RenderingServer; it flashes and exits by itself).
## Builds the state for each shot from docs/STORE_LISTING.md, waits for the
## renderer to warm, and saves PNGs to user://screenshots/.

const MENU := "res://scenes/core/MainMenu.tscn"
const HOUSE := "res://scenes/house/HouseScene.tscn"
const DOOR := "res://scenes/gameplay/InspectionScene.tscn"

var _idx := 0

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	_next()

func _next() -> void:
	var names := ["01_splash", "02_menu", "03_door", "04_house_day1", "05_house_day3_stairs", "06_basement_day7"]
	if _idx >= names.size():
		print("[screenshot] done -> ", ProjectSettings.globalize_path("user://screenshots"))
		get_tree().quit()
		return
	GameManager.current_day = [1, 1, 1, 1, 3, 7][_idx]
	GameManager.tv_watched_today = true  # suppress the MORNING popup
	match _idx:
		1:
			SceneManager.change_scene(MENU, 0.0)
		2:
			GameManager.change_state(GameManager.GameState.NIGHT)
			VisitorManager.prepare_night_queue(1)
			VisitorManager.start_next_inspection()
			SceneManager.change_scene(DOOR, 0.0)
		3, 4, 5:
			# House3D computes unlocked floors from GameManager.current_day itself.
			GameManager.change_state(GameManager.GameState.DAY)
			SceneManager.change_scene(HOUSE, 0.0)
	await _settle()
	var img := get_tree().root.get_texture().get_image()
	var path: String = "user://screenshots/" + names[_idx] + ".png"
	img.save_png(path)
	print("[screenshot] " + path)
	_idx += 1
	_next()

func _settle() -> void:
	# Real time, not frames: the splash title fades in over ~1.2 s and frame
	# rate is uncapped in this harness.
	await get_tree().create_timer(1.6).timeout
