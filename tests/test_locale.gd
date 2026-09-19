extends SceneTree

## Locale smoke test. Run with:
##   godot --headless --path <project> --script res://tests/test_locale.gd
## Requires autoloads (SettingsManager loads locale/*.json at boot).

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame
	var key := "Night 1: The Threshold"
	TranslationServer.set_locale("en")
	var en_text: String = TranslationServer.translate(key)
	TranslationServer.set_locale("pt_BR")
	var pt_text: String = TranslationServer.translate(key)
	print("TEST en: ", en_text)
	print("TEST pt_BR: ", pt_text)
	var ok := en_text == key and pt_text == "Noite 1: O Limiar"
	print("TEST locales: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
