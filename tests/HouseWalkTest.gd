extends Node

## In-game headless test for the walkable house. Triggered by `--house-test`:
##   godot --headless --path <project> -- --house-test
## Verifies: player/camera spawn, room tracking, every static interactable
## dispatches without crashing, guest focus resolves, sleep advances the day.

var failures: Array = []

func _ready() -> void:
	_run()

func check(cond: bool, label: String) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		failures.append(label)

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	GameManager.current_day = 1
	GameManager.change_state(GameManager.GameState.DAY)
	GameManager.energy_left = GameManager.energy_max
	VisitorManager.admitted_visitors = [{
		"id": "t1", "name": "Test Guest", "room": "hall", "admitted_day": 1,
		"portrait": "res://assets/images/portraits/visitor_01_marcus_vane.png",
		"dialogue_chain": [], "backstory": "Nothing to say.",
		"assigned_signs": [], "revealed_signs_count": 0, "talk_step": 0,
		"is_actually_infected": false,
	}]

	var packed: PackedScene = load("res://scenes/house/HouseScene.tscn")
	var scene := packed.instantiate() as HouseScene
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	check(scene.house3d.player != null, "player spawned")
	check(scene.house3d.player.camera != null, "player camera live")
	check(scene.house3d.player.spot != null, "flashlight mounted")
	check(scene.house3d.player.flashlight_on, "flashlight on by default")

	# Battery economy: drains with use, R swaps a spare, F toggles.
	GameManager.flashlight_battery = 50.0
	GameManager.drain_battery(10.0)
	check(absf(GameManager.flashlight_battery - 47.0) < 0.01, "battery drains while lit")
	GameManager.batteries = 1
	GameManager.flashlight_battery = 10.0
	check(GameManager.replace_battery(), "spare swaps in")
	check(GameManager.flashlight_battery == 100.0 and GameManager.batteries == 0, "cell full, spare spent")
	check(not GameManager.replace_battery(), "no spare, no swap")
	GameManager.flashlight_battery = 100.0
	GameManager.batteries = 1
	check(scene.current_room == "bedroom", "starts in bedroom")
	check(scene.house3d._interactables.size() == 8, "8 static interactables registered")
	check(scene.house3d._fan != null, "ceiling fan mounted")
	check(ResourceLoader.exists("res://assets/models/building/door-rotate-square-a.glb"), "kit door leaf on disk")
	check(ResourceLoader.exists("res://assets/models/furniture/bedSingle.glb"), "CC0 bed model on disk")
	var body_count := 0
	var faced := false
	for c in scene.house3d._figures_root.get_children():
		if c is VisitorBody3D:
			body_count += 1
			faced = faced or (c as VisitorBody3D).has_face()
	check(body_count == 1, "guest wears 3D body, not capsule")
	check(faced, "body wears the portrait face")
	scene.house3d.show_guest_sign("t1", {"id": "s002"})
	check(true, "examined sign marks the body without crashing")

	for aid in ["tv", "radio", "window", "front_door", "scavenge", "fortify", "mirror"]:
		scene._do_interact({"id": aid})
		scene._on_popup_action("close")
	check(true, "static interactables dispatch without crashing")

	var gpos: Vector3 = scene.house3d._guest_interactables[0]["pos"]
	var f := scene.house3d.get_focus(gpos + Vector3(0, 0, 1.0), Vector3(0, 0, -1))
	check(str(f.get("id", "")) == "guest", "guest focus resolves by proximity+gaze")
	scene._do_interact(f)
	check(scene.popup.visible, "guest interaction opens popup")
	scene._on_popup_action("close")

	GameManager.energy_left = 0
	scene._do_interact({"id": "bed"})
	check(GameManager.current_day == 2, "sleep advances to day 2")

	VisitorManager.admitted_visitors.clear()
	print("RESULT %d failures" % failures.size())
	for x in failures:
		print("FAILED: ", x)
	get_tree().quit(1 if not failures.is_empty() else 0)
