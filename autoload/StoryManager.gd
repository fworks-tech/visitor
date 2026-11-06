# StoryManager.gd
# Loads story.json and handles narrative events, survivor dialogues, and story progression.
extends Node

signal story_event_started(event_id: String, event_data: Dictionary)
signal dialogue_updated(speaker: String, text: String, emotion: String)
signal choices_presented(choices_array: Array)
signal story_event_ended(event_id: String)

var story_data: Dictionary = {}
var current_event_id: String = ""
var current_event_data: Dictionary = {}
var current_dialogue_index: int = 0

const STORY_FILE_PATH: String = "res://assets/data/story.json"
const DEMO_STORY_FILE_PATH: String = "res://assets/data/story_demo.json"

var demo_mode := false

func _ready() -> void:
	load_story_data()

func load_story_data() -> void:
	demo_mode = "--demo" in OS.get_cmdline_user_args() or OS.has_feature("demo")
	var path := DEMO_STORY_FILE_PATH if demo_mode else STORY_FILE_PATH
	if not FileAccess.file_exists(path):
		push_error("[StoryManager] story file not found at %s" % path)
		return
		
	var file := FileAccess.open(path, FileAccess.READ)
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_string)
	if error == OK and json.data is Dictionary:
		story_data = json.data
		print("[StoryManager] %s loaded successfully (%d events)." % [path.get_file(), story_data.get("events", {}).size()])
	else:
		push_error("[StoryManager] Failed to parse story.json: %s" % json.get_error_message())

func trigger_phase_event(day: int, phase: String) -> void:
	var event_key := "day%d_%s" % [day, phase]
	var events_dict: Dictionary = story_data.get("events", {})
	
	if events_dict.has(event_key):
		start_event(event_key)
	else:
		print_verbose("[StoryManager] No story event found for %s" % event_key)

func start_event(event_id: String) -> void:
	var events_dict: Dictionary = story_data.get("events", {})
	if not events_dict.has(event_id):
		push_warning("[StoryManager] Event %s not found" % event_id)
		return
		
	current_event_id = event_id
	current_event_data = events_dict[event_id]
	current_dialogue_index = 0
	
	story_event_started.emit(current_event_id, current_event_data)
	advance_dialogue()

func advance_dialogue() -> void:
	var dialogue_list: Array = current_event_data.get("dialogue", [])
	if current_dialogue_index < dialogue_list.size():
		var line: Dictionary = dialogue_list[current_dialogue_index]
		var speaker: String = line.get("speaker", "Unknown")
		var text: String = line.get("text", "")
		var emotion: String = line.get("emotion", "neutral")
		
		current_dialogue_index += 1
		dialogue_updated.emit(speaker, text, emotion)
	else:
		var choices: Array = current_event_data.get("choices", [])
		if choices.size() > 0:
			choices_presented.emit(choices)
		else:
			end_current_event()

func end_current_event() -> void:
	var finished_id := current_event_id
	current_event_id = ""
	current_event_data = {}
	current_dialogue_index = 0
	story_event_ended.emit(finished_id)
