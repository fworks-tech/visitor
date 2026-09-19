# Settings.gd
# Audio/text settings with sliders. Persists via SettingsManager.
extends Control

@onready var music_slider: HSlider = $SettingsVBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $SettingsVBox/SfxRow/SfxSlider
@onready var voice_slider: HSlider = $SettingsVBox/VoiceRow/VoiceSlider
@onready var text_speed_slider: HSlider = $SettingsVBox/TextSpeedRow/TextSpeedSlider
@onready var crt_toggle: CheckButton = $SettingsVBox/CrtRow/CrtToggle
@onready var crt_intensity_slider: HSlider = $SettingsVBox/CrtIntensityRow/CrtIntensitySlider
@onready var brightness_slider: HSlider = $SettingsVBox/BrightnessRow/BrightnessSlider
@onready var language_option: OptionButton = $SettingsVBox/LanguageRow/LanguageOption
@onready var back_btn: Button = $SettingsVBox/BackButton

const MAIN_MENU_PATH := "res://scenes/core/MainMenu.tscn"
const LANGUAGES := ["en", "pt_BR"]

func _ready() -> void:
	music_slider.value = SettingsManager.get_setting("music_volume", 0.7)
	sfx_slider.value = SettingsManager.get_setting("sfx_volume", 1.0)
	voice_slider.value = SettingsManager.get_setting("voice_volume", 0.9)
	text_speed_slider.value = SettingsManager.get_setting("text_speed", 0.03)
	crt_toggle.button_pressed = SettingsManager.get_setting("crt_effect_enabled", true)
	crt_intensity_slider.value = SettingsManager.get_setting("crt_intensity", 0.8)
	brightness_slider.value = SettingsManager.get_setting("brightness", 1.0)
	language_option.selected = maxi(0, LANGUAGES.find(str(SettingsManager.get_setting("language", "en"))))

	music_slider.value_changed.connect(func(v): _set_setting("music_volume", v))
	sfx_slider.value_changed.connect(func(v): _set_setting("sfx_volume", v))
	voice_slider.value_changed.connect(func(v): _set_setting("voice_volume", v))
	text_speed_slider.value_changed.connect(func(v): _set_setting("text_speed", v))
	crt_toggle.toggled.connect(func(p): SettingsManager.set_setting("crt_effect_enabled", p))
	crt_intensity_slider.value_changed.connect(func(v): _set_setting("crt_intensity", v))
	brightness_slider.value_changed.connect(func(v): _set_setting("brightness", v))
	language_option.item_selected.connect(func(i): SettingsManager.set_setting("language", LANGUAGES[i]))

	back_btn.pressed.connect(_on_back)

func _set_setting(key: String, value: float) -> void:
	SettingsManager.set_setting(key, value)

func _on_back() -> void:
	SceneManager.change_scene(MAIN_MENU_PATH)
