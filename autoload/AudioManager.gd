# AudioManager.gd
# Silence-first horror soundscape (see docs/AUDIO_DIRECTION.md).
# Real playback over the 5-bus layout (Music/Ambient/Voice/SFX/CRT).
# All cues live in res://assets/audio/ — synthesized in-house by
# tools/audio_synth.py (license-clean, zero third-party samples).
extends Node

enum KnockPattern {
	LIGHT_TAP,
	URGENT_POUNDING,
	RHYTHMIC_KNOCK,
	HEAVY_THUD,
	SCRATCHING,
	RETURN_KNOCK,
	GROUP_ARRIVAL
}

const AUDIO_DIR := "res://assets/audio/"

# Designed base levels — user sliders (0-1) scale these, 1.0 = original mix.
const AMBIENT_BASE_DB := -12.0
const CRT_BASE_DB := -18.0

# SFX cue names -> file stems. Old call sites keep working via aliases.
const SFX_CUES := {
	"ui_click": "sfx_ui_click",
	"ui_hover": "sfx_ui_hover",
	"reveal_sign": "sfx_reveal_sign",
	"scanner_beep": "sfx_reveal_sign",      # alias
	"let_in": "sfx_decision_let_in",
	"door_latch": "sfx_decision_let_in",   # alias
	"turn_away": "sfx_decision_turn_away",
	"door_deny": "sfx_decision_turn_away", # alias
	"eliminate": "sfx_decision_eliminate",
	"gunshot": "sfx_decision_eliminate",   # alias
	"day_transition": "sfx_day_transition",
	"power_down": "sfx_power_down",
	"glitch_1": "sfx_glitch_1",
	"glitch_2": "sfx_glitch_2",
	"glitch_3": "sfx_glitch_3",
}

const KNOCK_FILES := {
	KnockPattern.LIGHT_TAP: "sfx_knock_4",       # small, quiet
	KnockPattern.URGENT_POUNDING: "sfx_knock_2",  # rapid frantic
	KnockPattern.RHYTHMIC_KNOCK: "sfx_knock_1",   # three firm
	KnockPattern.HEAVY_THUD: "sfx_knock_3",       # slow deliberate
	KnockPattern.SCRATCHING: "sfx_knock_6",       # subtle wrongness
	KnockPattern.RETURN_KNOCK: "sfx_knock_6",     # recognition trigger
	KnockPattern.GROUP_ARRIVAL: "sfx_knock_5",    # overlapping chaos
}

const AMBIENT_CUES := {
	"room": "ambient_room_tone",
	"city": "ambient_distant_city",
	"drone": "ambient_night_drone",
}

var _crt_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _knock_player: AudioStreamPlayer
var _glitch_player: AudioStreamPlayer
var _door_voice_player: AudioStreamPlayer
var _ui_player: AudioStreamPlayer

var audio_volumes: Dictionary = {
	"master": 0.8,
	"sfx": 1.0,
	"music": 0.6,
	"voice": 0.9,
	"ambient": 0.7,
	"crt": 0.4,
}

var _visitors_encountered: int = 0
var _ambient_suspended: bool = false


func _ready() -> void:
	_crt_player = AudioStreamPlayer.new()
	_ambient_player = AudioStreamPlayer.new()
	_music_player = AudioStreamPlayer.new()
	_sfx_player = AudioStreamPlayer.new()
	_knock_player = AudioStreamPlayer.new()
	_glitch_player = AudioStreamPlayer.new()
	_door_voice_player = AudioStreamPlayer.new()
	_ui_player = AudioStreamPlayer.new()

	for p in [_crt_player, _ambient_player, _music_player, _sfx_player,
			_knock_player, _glitch_player, _door_voice_player, _ui_player]:
		add_child(p)

	_crt_player.bus = &"CRT"
	_ambient_player.bus = &"Ambient"
	_music_player.bus = &"Music"
	_sfx_player.bus = &"SFX"
	_knock_player.bus = &"SFX"
	_glitch_player.bus = &"SFX"
	_door_voice_player.bus = &"Voice"
	_ui_player.bus = &"SFX"

	# Every Button in the game clicks on press, current and future — no
	# per-script wiring. Disabled buttons never emit, so this is inert until used.
	get_tree().node_added.connect(_on_node_added)

	# The CRT hum never stops — it's the sound of the system watching.
	_play_on(_crt_player, "ambient_crt_hum", true, db_to_linear(CRT_BASE_DB))
	start_night_ambience()
	print("[AudioManager] Silence-first horror audio system initialized.")


func _on_node_added(node: Node) -> void:
	# TouchScreenButton deliberately not covered: it extends Node2D, not
	# BaseButton — virtual joysticks and movement buttons must stay silent.
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play_ui_cue.bind("ui_click"))


# ---------------------------------------------------------------- streams

func _stream(cue: String, loop: bool) -> AudioStream:
	var path := AUDIO_DIR + cue + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("[AudioManager] missing cue %s" % cue)
		return null
	var stream: AudioStream = load(path)
	if loop and stream is AudioStreamOggVorbis:
		stream.loop = true
	return stream


func _play_on(player: AudioStreamPlayer, cue: String, loop: bool, volume: float = 1.0) -> bool:
	var stream := _stream(cue, loop)
	if stream == null:
		return false
	player.stream = stream
	player.volume_db = linear_to_db(maxf(0.0001, volume))
	player.play()
	return true


# ---------------------------------------------------------------- ambience

func start_night_ambience() -> void:
	_play_on(_ambient_player, AMBIENT_CUES["room"], true, _ambient_level())
	_visitors_encountered = 0


func _ambient_level() -> float:
	return db_to_linear(AMBIENT_BASE_DB) * float(audio_volumes.get("ambient", 0.7))


func play_ambient(stream_path: String) -> void:
	# legacy API — direct stream path
	if ResourceLoader.exists(stream_path):
		var stream: AudioStream = load(stream_path)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		_ambient_player.stream = stream
		_ambient_player.volume_db = linear_to_db(audio_volumes["ambient"])
		_ambient_player.play()


func stop_ambient() -> void:
	_ambient_player.stop()


func visitor_encountered() -> void:
	# The night drone builds +1 dB per visitor — imperceptible tension.
	_visitors_encountered += 1
	_ambient_player.volume_db = linear_to_db(maxf(0.0001, _ambient_level())) \
		+ float(_visitors_encountered)


func suspend_ambience(seconds: float = 2.0) -> void:
	# Dynamic Silence: after a decision, ALL ambient drops out, then resumes.
	if _ambient_suspended:
		return
	_ambient_suspended = true
	_ambient_player.stop()
	get_tree().create_timer(seconds).timeout.connect(func():
		_ambient_suspended = false
		start_night_ambience()
		_ambient_player.volume_db += float(_visitors_encountered))


# ---------------------------------------------------------------- sfx

func play_sfx(sfx_name: String) -> void:
	var cue: String = SFX_CUES.get(sfx_name, sfx_name)
	_sfx_player.pitch_scale = randf_range(0.95, 1.05)
	_sfx_player.volume_db = linear_to_db(audio_volumes["sfx"])
	_play_on(_sfx_player, cue, false, audio_volumes["sfx"])


func play_ui_cue(cue_name: String) -> void:
	# Foreground cues (clicks, sign reveals, decisions) ride a dedicated
	# player: typewriter blips on the shared SFX player would otherwise cut
	# them off a few frames in (last-wins on a single AudioStreamPlayer).
	var cue: String = SFX_CUES.get(cue_name, cue_name)
	_play_on(_ui_player, cue, false, audio_volumes["sfx"])


func play_decision(decision: String) -> void:
	# A decision lands: its sound plays, then two seconds of total silence.
	play_ui_cue(decision)
	suspend_ambience(2.0)


func play_glitch(level: int) -> void:
	# 1 mild / 2 moderate / 3 severe — fire alongside CRT trigger_glitch()
	var cue := "glitch_%d" % clampi(level, 1, 3)
	if cue in SFX_CUES:
		_glitch_player.volume_db = linear_to_db(audio_volumes["sfx"])
		_play_on(_glitch_player, SFX_CUES[cue], false, audio_volumes["sfx"] * (0.6 + 0.2 * level))


# ---------------------------------------------------------------- knocks

func play_knock_pattern(pattern: KnockPattern) -> void:
	var cue: String = KNOCK_FILES.get(pattern, "sfx_knock_1")
	_knock_player.volume_db = linear_to_db(audio_volumes["sfx"])
	_play_on(_knock_player, cue, false, audio_volumes["sfx"])


func play_visitor_knock(visitor: Dictionary) -> void:
	# Derive the knock from who is at the door (no authored field yet):
	# groups knock over each other, children barely knock, repeat visitors
	# knock the same way you remember, calm subjects take their time.
	if visitor.get("is_group", false):
		play_knock_pattern(KnockPattern.GROUP_ARRIVAL)
	elif visitor.get("is_child", false):
		play_knock_pattern(KnockPattern.LIGHT_TAP)
	elif visitor.get("recurring", false) and visitor.get("appearances", 1) > 1:
		play_knock_pattern(KnockPattern.RETURN_KNOCK)
	else:
		# Beats are plain strings; urgent punctuation sets the knock.
		var chain: Array = visitor.get("dialogue_chain", [])
		var first_beat := str(chain[0]) if chain.size() > 0 else ""
		if "!" in first_beat:
			play_knock_pattern(KnockPattern.URGENT_POUNDING)
		elif first_beat.length() < 40:
			play_knock_pattern(KnockPattern.HEAVY_THUD)
		else:
			play_knock_pattern(KnockPattern.RHYTHMIC_KNOCK)
	visitor_encountered()


# ---------------------------------------------------------------- voice + music

func play_door_voice(voice_type: String) -> void:
	# Muffled through-the-door voice — the Voice bus filter chain does the work.
	_door_voice_player.pitch_scale = randf_range(0.85, 1.15)
	_door_voice_player.volume_db = linear_to_db(maxf(0.0001, float(audio_volumes.get("voice", 0.9)) * 0.6))
	print("[AudioManager Voice] Muffled voice through door: %s" % voice_type)


func play_music(which: String) -> void:
	# "menu" or "ending_<name>" — music is rare; silence is the default.
	var cue := "music_menu" if which == "menu" else "music_ending_" + which
	_music_player.volume_db = linear_to_db(audio_volumes["music"])
	_play_on(_music_player, cue, true, audio_volumes["music"])


func stop_music() -> void:
	_music_player.stop()


func play_ending_music(ending_id: String) -> void:
	stop_music()
	var cue := "music_ending_" + ending_id
	if not ResourceLoader.exists(AUDIO_DIR + cue + ".ogg"):
		cue = "music_ending_pariah"
	_music_player.volume_db = linear_to_db(audio_volumes["music"])
	if not _play_on(_music_player, cue, true, audio_volumes["music"]):
		play_sfx("power_down")


func power_down() -> void:
	_play_on(_sfx_player, "sfx_power_down", false, audio_volumes["sfx"])


# ---------------------------------------------------------------- volumes

func set_volume(bus_name: String, volume_linear: float) -> void:
	var val := clampf(volume_linear, 0.0, 1.0)
	audio_volumes[bus_name] = val
	var db := linear_to_db(maxf(0.0001, val))
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		bus_idx = AudioServer.get_bus_index(bus_name.capitalize())
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db)
	# Buses may not exist (no bus layout yet) and loops keep playing,
	# so refresh live players directly.
	match bus_name:
		"ambient":
			if _ambient_player != null and _ambient_player.playing:
				_ambient_player.volume_db = linear_to_db(maxf(0.0001, _ambient_level())) + float(_visitors_encountered)
		"music":
			if _music_player != null and _music_player.playing:
				_music_player.volume_db = db
		"crt":
			if _crt_player != null and _crt_player.playing:
				_crt_player.volume_db = linear_to_db(maxf(0.0001, db_to_linear(CRT_BASE_DB) * val))
