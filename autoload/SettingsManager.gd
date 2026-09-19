# SettingsManager.gd
# Manages application settings: text speed, audio volumes, haptics/vibration, and CRT shaders.
extends Node

signal settings_changed

const CONFIG_PATH: String = "user://settings.cfg"
const LOCALE_DIR := "res://locale"
const SUPPORTED_LOCALES := ["en", "pt_BR"]

var text_speed: float = 0.03 # Seconds per character
var master_volume: float = 0.8
var sfx_volume: float = 1.0
var music_volume: float = 0.7
var voice_volume: float = 0.9
var ambient_volume: float = 0.8
var vibration_enabled: bool = true
var crt_effect_enabled: bool = true
var crt_intensity: float = 0.8
var green_monochrome_mode: bool = true
var brightness: float = 1.0
var language: String = "en"

var _dim_rect: ColorRect

func _ready() -> void:
	# Fullscreen dimmer (layer 99, below CRT overlay) — brightness only darkens.
	var dim_layer := CanvasLayer.new()
	dim_layer.layer = 99
	_dim_rect = ColorRect.new()
	_dim_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_rect.color = Color(0, 0, 0, 0)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim_layer.add_child(_dim_rect)
	add_child(dim_layer)
	load_locale_files()
	load_settings()

## Runtime locale loading: locale/*.json are plain {english: translated}
## maps (written by tools/extract_strings.py). Godot's CSV importer proved
## unreliable for these files, so Translations are built directly — no
## project.godot [internationalization] wiring, no .import round-trip.
func load_locale_files() -> void:
	for locale in SUPPORTED_LOCALES:
		var path := "%s/%s.json" % [LOCALE_DIR, locale]
		if not FileAccess.file_exists(path):
			push_warning("[SettingsManager] locale file missing: %s" % path)
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			push_warning("[SettingsManager] locale file unparsable: %s" % path)
			continue
		var t := Translation.new()
		t.set_locale(locale)
		for k in json.data:
			t.add_message(str(k), str(json.data[k]))
		TranslationServer.add_translation(t)
	print("[SettingsManager] %d locale files loaded." % SUPPORTED_LOCALES.size())

func apply_settings() -> void:
	AudioManager.set_volume("master", master_volume)
	AudioManager.set_volume("sfx", sfx_volume)
	AudioManager.set_volume("music", music_volume)
	AudioManager.set_volume("voice", voice_volume)
	AudioManager.set_volume("ambient", ambient_volume)

	if _dim_rect:
		_dim_rect.color.a = clampf(1.0 - brightness, 0.0, 0.8)
	TranslationServer.set_locale(language)

	settings_changed.emit()

func trigger_haptic_feedback(duration_ms: int = 50) -> void:
	if vibration_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "voice", voice_volume)
	config.set_value("audio", "ambient", ambient_volume)
	
	config.set_value("gameplay", "text_speed", text_speed)
	config.set_value("gameplay", "vibration", vibration_enabled)
	
	config.set_value("visuals", "crt_enabled", crt_effect_enabled)
	config.set_value("visuals", "crt_intensity", crt_intensity)
	config.set_value("visuals", "green_monochrome", green_monochrome_mode)
	config.set_value("visuals", "brightness", brightness)

	config.set_value("general", "language", language)
	
	config.save(CONFIG_PATH)
	apply_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(CONFIG_PATH)
	if err == OK:
		master_volume = config.get_value("audio", "master", 0.8)
		sfx_volume = config.get_value("audio", "sfx", 1.0)
		music_volume = config.get_value("audio", "music", 0.7)
		voice_volume = config.get_value("audio", "voice", 0.9)
		ambient_volume = config.get_value("audio", "ambient", 0.8)
		
		text_speed = config.get_value("gameplay", "text_speed", 0.03)
		vibration_enabled = config.get_value("gameplay", "vibration", true)
		
		crt_effect_enabled = config.get_value("visuals", "crt_enabled", true)
		crt_intensity = config.get_value("visuals", "crt_intensity", 0.8)
		green_monochrome_mode = config.get_value("visuals", "green_monochrome", true)
		brightness = config.get_value("visuals", "brightness", 1.0)

		language = config.get_value("general", "language", "en")
	
	apply_settings()
	
func get_setting(setting_name: String, fallback: Variant = null) -> Variant:
	match setting_name:
		"master_volume":
			return master_volume
		"sfx_volume":
			return sfx_volume
		"music_volume":
			return music_volume
		"voice_volume":
			return voice_volume
		"ambient_volume":
			return ambient_volume
		"text_speed":
			return text_speed
		"vibration_enabled":
			return vibration_enabled
		"crt_effect_enabled":
			return crt_effect_enabled
		"crt_intensity":
			return crt_intensity
		"green_monochrome_mode":
			return green_monochrome_mode
		"brightness":
			return brightness
		"language":
			return language
	push_warning("[SettingsManager] unknown setting: %s" % setting_name)
	return fallback

func set_setting(setting_name: String, value: Variant) -> void:
	match setting_name:
		"master_volume":
			master_volume = clampf(float(value), 0.0, 1.0)
		"sfx_volume":
			sfx_volume = clampf(float(value), 0.0, 1.0)
		"music_volume":
			music_volume = clampf(float(value), 0.0, 1.0)
		"voice_volume":
			voice_volume = clampf(float(value), 0.0, 1.0)
		"ambient_volume":
			ambient_volume = clampf(float(value), 0.0, 1.0)
		"text_speed":
			text_speed = clampf(float(value), 0.01, 0.1)
		"vibration_enabled":
			vibration_enabled = bool(value)
		"crt_effect_enabled":
			crt_effect_enabled = bool(value)
		"crt_intensity":
			crt_intensity = clampf(float(value), 0.0, 1.0)
		"green_monochrome_mode":
			green_monochrome_mode = bool(value)
		"brightness":
			brightness = clampf(float(value), 0.2, 1.0)
		"language":
			var lang := str(value)
			language = lang if lang in ["en", "pt_BR"] else "en"
		_:
			push_warning("[SettingsManager] unknown setting: %s" % setting_name)
			return
	save_settings()
