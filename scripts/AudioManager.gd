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
	"Orange":      "res://Sounds/music/Motherboard_Level_Loop.ogg",
	"Yellow":      "res://Sounds/music/PlaceholderMusic/Yellow.mp3",
	"Blue":        "res://Sounds/music/PlaceholderMusic/Blue.mp3",
	"Red":         "res://Sounds/music/PlaceholderMusic/Red.mp3",
	"LevelEditor": "res://Sounds/music/PlaceholderMusic/LevelEditor.mp3",
	"Boss":        "res://Sounds/music/PlaceholderMusic/Boss.mp3",
}

const MUSIC_FADE := 1.0
const MUSIC_START_FADE := 3.0

const _MUSIC_VOLUME := {
	"Boss": -6.0,
	"Red":  -7.0,
}

const _PREFS_PATH := "user://audio_prefs.json"

var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _music_tweens: Dictionary = {}
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
	(_sfx["electric_noise"] as AudioStreamPlayer).volume_db = -29.1
	(_sfx["snap"] as AudioStreamPlayer).volume_db = -14.0
	(_sfx["character_death"] as AudioStreamPlayer).volume_db = -12.0
	(_sfx["plant_stake"] as AudioStreamPlayer).volume_db = -8.0

	for key in _MUSIC_FILES:
		var p := AudioStreamPlayer.new()
		var stream = load(_MUSIC_FILES[key])
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
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

	# Kill all in-progress tweens so they don't fight over volume_db
	for k in _music_tweens:
		if _music_tweens[k] != null:
			_music_tweens[k].kill()
	_music_tweens.clear()

	# Silence any track that is neither the outgoing nor the incoming one
	for k in _music:
		if k != _current_music and k != key:
			(_music[k] as AudioStreamPlayer).volume_db = -80.0

	var old_key := _current_music
	_current_music = key

	if old_key != "" and _music.has(old_key) and not _music_muted:
		var t := create_tween()
		t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		t.tween_property(_music[old_key], "volume_db", -80.0, MUSIC_FADE)
		_music_tweens[old_key] = t

	if key != "" and _music.has(key) and not _music_muted:
		var target_db = _MUSIC_VOLUME.get(key, 0.0)
		_music[key].volume_db = -30.0
		var t := create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		t.tween_property(_music[key], "volume_db", target_db, fade_in)
		_music_tweens[key] = t

func is_music_muted() -> bool:
	return _music_muted

func is_sfx_muted() -> bool:
	return _sfx_muted

func toggle_music_mute() -> bool:
	_music_muted = not _music_muted
	for key in _music:
		(_music[key] as AudioStreamPlayer).volume_db = -80.0
	if not _music_muted and _current_music != "" and _music.has(_current_music):
		(_music[_current_music] as AudioStreamPlayer).volume_db = _MUSIC_VOLUME.get(_current_music, 0.0)
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
