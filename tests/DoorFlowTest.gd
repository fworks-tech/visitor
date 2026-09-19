extends Node

## In-game headless test harness for the front-door flow. Triggered by the
## `--door-test` CLI flag (see GameManager._ready). Runs as a real scene-tree
## node so autoload identifiers resolve — `--script` mode cannot compile
## scene scripts that reference autoloads.
##
##   godot --headless --path <project> -- --door-test
##
## Simulates: knock -> listen -> examine -> ask -> study -> decide LET IN,
## then TURN AWAY on the next visitor, then night-complete. Any data-shape
## mismatch (dialogue_chain, reveal_on_inspection, signs) fails loudly here.

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

	# Simulate post-start_night_phase state: day set, queue prepared.
	GameManager.current_day = 1
	VisitorManager.prepare_night_queue(1)
	VisitorManager.current_visitor_index = 0
	print("INFO db=%d queue=%d day=%d" % [VisitorManager.visitor_database.size(), VisitorManager.night_queue.size(), GameManager.current_day])

	var packed: PackedScene = load("res://scenes/gameplay/InspectionScene.tscn")
	var scene := packed.instantiate() as InspectionScene
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. A visitor is actually at the door, with a real portrait.
	check(not scene.current_visitor.is_empty(), "visitor loaded at door")
	check(scene.diorama.has_model(), "3D figure built (no placeholder)")
	check(scene.portrait_art.texture != null, "visitor PNG art shown at door")
	check(scene.question_story_btn.visible, "listen offered first")
	check(not scene.inspect_btn.visible, "examine hidden until heard")
	check(not scene.let_in_btn.visible, "judgment hidden until earned")
	check(scene.status_label.text != "", "opening beat shown as dialogue")
	print("INFO door shows: ", scene.current_visitor.get("name", "?"), " | ", scene.status_label.text.left(80))

	var beats: Array = scene.current_visitor.get("dialogue_chain", [])
	var signs: Array = scene.current_visitor.get("assigned_signs", [])
	print("INFO beats=%d signs=%d reveal=%s" % [beats.size(), signs.size(), str(scene.current_visitor.get("reveal_on_inspection", "")).left(50)])

	# 2. Conversation verbs work on the real data shapes.
	scene._on_question_story_pressed()  # LISTEN
	check(scene.line_index == 1, "listen advances dialogue")
	check(scene.inspect_btn.visible, "examine unlocks after listening")
	scene._on_inspect_physical_pressed()  # EXAMINE
	check(scene.revealed_signs == 1, "examine reveals a sign")
	check(scene.let_in_btn.visible, "judgment unlocks after probing")
	check(scene.suspicion_level > 0.1, "suspicion (and face corruption) rises")
	scene._on_question_wounds_pressed()  # ASK
	check(scene.asked_about_marks, "ask draws out the reveal")
	scene._on_test_reaction_pressed()  # STUDY
	check(scene.studied_face, "study registers the gaze")

	# 3. The decision actually reaches the sim (flags, trust, house guests).
	var trust_before: int = GameManager.trust_value
	var hist_before: int = VisitorManager.decision_history.size()
	scene._on_let_in_pressed()
	await get_tree().create_timer(2.5).timeout  # decision delay -> next visitor
	check(VisitorManager.decision_history.size() == hist_before + 1, "decision recorded in history")
	check(GameManager.trust_value != trust_before, "trust moved after decision")
	print("INFO trust %d -> %d" % [trust_before, GameManager.trust_value])

	# 4. Second visitor, then night-complete.
	if scene.current_visitor.is_empty():
		check(false, "second visitor present (queue had >= 2)")
	else:
		print("INFO second visitor: ", scene.current_visitor.get("name", "?"))
		scene._on_turn_away_pressed()
		await get_tree().create_timer(2.5).timeout
	check(scene.current_visitor.is_empty(), "queue exhausted after 2 decisions")
	check(not scene.portrait_art.visible, "portrait hidden when door empty")
	check(scene.end_night_btn.visible, "RETURN HOME offered at night end")
	check(VisitorManager.night_completed == false, "night_completed still false before RETURN HOME")
	scene._on_end_night_pressed()
	check(VisitorManager.night_completed, "night_completed set on RETURN HOME")

	print("RESULT %d failures" % failures.size())
	for f in failures:
		print("FAILED: ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)
