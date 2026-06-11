extends Node

const _SFX_FILES := {
	"character_death": "res://Sounds/Character_Death.ogg",
	"electric_fail":   "res://Sounds/Electric_Fail.ogg",
	"electric_noise":  "res://Sounds/Electric_Noise1.ogg",
	"electric_spawn":  "res://Sounds/Electric_Spawn.ogg",
	"plant_stake":     "res://Sounds/Plant_Stake1.ogg",
	"water_death":     "res://Sounds/Water_Death.ogg",
	"snap":            "res://Sounds/snap.ogg",
}

const _MUSIC_FILES := {
	"Orange": "res://Sounds/Motherboard_Level_Loop.ogg",
	"Yellow": "res://Sounds/Motherboard_Title_Loop.ogg",
}

const MUSIC_FADE := 1.0
const MUSIC_START_FADE := 3.0

var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _current_music: String = ""
var _music_started := false

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

func play_sfx(key: String) -> void:
	if _sfx.has(key):
		_sfx[key].play()

func start_beam_noise() -> void:
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
	if _current_music != "" and _music.has(_current_music):
		var old_key := _current_music
		var t := create_tween()
		t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		t.tween_property(_music[old_key], "volume_db", -30.0, MUSIC_FADE)
		t.tween_callback(func(): _music[old_key].volume_db = -80.0)
	if key != "" and _music.has(key):
		_music[key].volume_db = -30.0
		var t := create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		t.tween_property(_music[key], "volume_db", 0.0, fade_in)
	_current_music = key
