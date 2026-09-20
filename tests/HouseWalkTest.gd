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
	check(scene.house3d._interactables.size() == 11, "11 static interactables registered")
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

	for aid in ["tv", "radio", "window", "front_door", "scavenge", "cabinet", "drawer", "tap", "fortify", "mirror"]:
		scene._do_interact({"id": aid})
		scene._on_popup_action("close")
	check(true, "static interactables dispatch without crashing")

	scene._do_interact({"id": "tap"})
	scene._on_popup_action("close")
	check(int(FlagsManager.get_flag("tap_day", 0)) == GameManager.current_day,
		"tap fills water once per day")

	var gpos: Vector3 = scene.house3d._guest_interactables[0]["pos"]
	var f := scene.house3d.get_focus(gpos + Vector3(0, 0, 1.0), Vector3(0, 0, -1))
	check(str(f.get("id", "")) == "guest", "guest focus resolves by proximity+gaze")
	scene._do_interact(f)
	check(scene.popup.visible, "guest interaction opens popup")
	scene._on_popup_action("close")

	GameManager.energy_left = 0
	scene._do_interact({"id": "bed"})
	check(GameManager.current_day == 2, "sleep advances to day 2")

	# Multi-floor: day 2 should NOT have stairs (unlocks day 3).
	var has_stairs := false
	for it in scene.house3d._interactables:
		if str(it.get("id", "")).begins_with("stairs"):
			has_stairs = true
	check(not has_stairs, "no stairs on day 2 (unlock day 3)")
	# Obstacle blocks the locked path.
	check(scene.house3d._obstacle_props.size() == 2, "2 obstacles on locked paths (stairs + basement)")

	# Unlock second floor and verify stairs appear.
	GameManager.current_day = 3
	scene.house3d.set_unlocked_floors(["ground", "second"])
	has_stairs = false
	var has_guest_bed := false
	for it in scene.house3d._interactables:
		var aid: String = str(it.get("id", ""))
		if aid == "stairs_up":
			has_stairs = true
		if aid == "guest_room_bed":
			has_guest_bed = true
	check(has_stairs, "stairs_up appears on day 3")
	check(has_guest_bed, "guest_room_bed appears on day 3")
	# Basement obstacle (ground) + attic obstacle (second floor) remain.
	check(scene.house3d._obstacle_props.size() == 2, "2 obstacles left (basement + attic locked)")

	# Guest room bed restores energy (day only).
	GameManager.change_state(GameManager.GameState.DAY)
	GameManager.energy_left = 1
	scene._do_interact({"id": "guest_room_bed"})
	check(GameManager.energy_left == 2, "guest bed restores 1 energy")

	# Unlock basement on day 7.
	GameManager.current_day = 7
	scene.house3d.set_unlocked_floors(["ground", "second", "attic", "basement"])
	var has_gen := false
	var has_cellar := false
	for it in scene.house3d._interactables:
		var aid: String = str(it.get("id", ""))
		if aid == "generator":
			has_gen = true
		if aid == "cellar_search":
			has_cellar = true
	check(has_gen, "generator appears on day 7")
	check(has_cellar, "cellar_search appears on day 7")
	# All paths clear when every floor is unlocked.
	check(scene.house3d._obstacle_props.size() == 0, "0 obstacles on day 7 (all floors unlocked)")

	VisitorManager.admitted_visitors.clear()
	print("RESULT %d failures" % failures.size())
	for x in failures:
		print("FAILED: ", x)
	get_tree().quit(1 if not failures.is_empty() else 0)
