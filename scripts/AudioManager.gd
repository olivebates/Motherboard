extends Node

const _SFX_FILES := {
	"character_death": "res://Sounds/sfx/Character_Death.ogg",
	"electric_fail":   "res://Sounds/sfx/Electric_Fail.ogg",
	"electric_noise":  "res://Sounds/sfx/Electric_Noise1.ogg",
	"electric_spawn":  "res://Sounds/sfx/Electric_Spawn.ogg",
	"plant_stake":     "res://Sounds/sfx/Plant_Stake1.ogg",
	"water_death":     "res://Sounds/sfx/Water_Death.ogg",
	"snap":            "res://Sounds/sfx/snap.ogg",
}

const _MUSIC_FILES := {
	"Orange": "res://Sounds/music/Motherboard_Level_Loop.ogg",
	"Yellow": "res://Sounds/music/Motherboard_Title_Loop.ogg",
}

const MUSIC_FADE := 1.0
const MUSIC_START_FADE := 3.0

const _PREFS_PATH := "user://audio_prefs.json"

var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _current_music: String = ""
var _music_started := false
var _music_muted := false
var _sfx_muted := false

func _ready() -> void:
	for key in _SFX_FILES:
		var p := AudioStreamPlayer.new()
		p.stream = load(_SFX_FILES[key])
		add_child(p)
		_sfx[key] = p

	(_sfx["electric_noise"].stream as AudioStreamOggVorbis).loop = true
	(_sfx["electric_noise"] as AudioStreamPlayer).volume_db = -26.1
	(_sfx["snap"] as AudioStreamPlayer).volume_db = -14.0

	for key in _MUSIC_FILES:
		var p := AudioStreamPlayer.new()
		var stream := load(_MUSIC_FILES[key]) as AudioStreamOggVorbis
		stream.loop = true
		p.stream = stream
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_music[key] = p

	_load_prefs()

func play_sfx(key: String) -> void:
	if _sfx_muted:
		return
	if _sfx.has(key):
		_sfx[key].play()

func start_beam_noise() -> void:
	if _sfx_muted:
		return
	var p := _sfx["electric_noise"] as AudioStreamPlayer
	if not p.playing:
		p.play()

func stop_beam_noise() -> void:
	(_sfx["electric_noise"] as AudioStreamPlayer).stop()

func set_music(key: String) -> void:
	if key == _current_music:
		return
	var fade_in := MUSIC_START_FADE if not _music_started else MUSIC_FADE
	_music_started = true
	if _current_music != "" and _music.has(_current_music) and not _music_muted:
		var old_key := _current_music
		var t := create_tween()
		t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		t.tween_property(_music[old_key], "volume_db", -30.0, MUSIC_FADE)
		t.tween_callback(func(): _music[old_key].volume_db = -80.0)
	if key != "" and _music.has(key) and not _music_muted:
		_music[key].volume_db = -30.0
		var t := create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		t.tween_property(_music[key], "volume_db", 0.0, fade_in)
	_current_music = key

func is_music_muted() -> bool:
	return _music_muted

func is_sfx_muted() -> bool:
	return _sfx_muted

func toggle_music_mute() -> bool:
	_music_muted = not _music_muted
	for key in _music:
		(_music[key] as AudioStreamPlayer).volume_db = -80.0
	if not _music_muted and _current_music != "" and _music.has(_current_music):
		(_music[_current_music] as AudioStreamPlayer).volume_db = 0.0
	_save_prefs()
	return _music_muted

func toggle_sfx_mute() -> bool:
	_sfx_muted = not _sfx_muted
	if _sfx_muted:
		for key in _sfx:
			(_sfx[key] as AudioStreamPlayer).stop()
	_save_prefs()
	return _sfx_muted

func _save_prefs() -> void:
	var f := FileAccess.open(_PREFS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"music_muted": _music_muted, "sfx_muted": _sfx_muted}))

func _load_prefs() -> void:
	if not FileAccess.file_exists(_PREFS_PATH):
		return
	var f := FileAccess.open(_PREFS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return
	_music_muted = data.get("music_muted", false)
	_sfx_muted = data.get("sfx_muted", false)
