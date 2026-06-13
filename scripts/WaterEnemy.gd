extends "res://scripts/Enemy.gd"

var boss_spawned := false

const MAX_HP := 25
const HEALTH_BAR_OFFSET_Y := -10.0

const _ROOM_PX_W = 25 * 32
const _ROOM_PX_H = 12 * 32

var hp := MAX_HP

func _ready() -> void:
	super._ready()
	add_to_group("water_enemies")
	if boss_spawned:
		add_to_group("boss_spawned_enemies")
	call_deferred("_register_health_bar")

func get_max_hp() -> int:
	return MAX_HP

func _register_health_bar() -> void:
	if is_in_group("water_boss"):
		return
	if _main == null:
		_main = get_tree().current_scene as Node2D
	if _main == null:
		call_deferred("_register_health_bar")
		return
	Utils.create_sprite_health_bar(self, TILE_SIZE, HEALTH_BAR_OFFSET_Y)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Utils.remove_sprite_health_bar(self)

func _get_home_room() -> Vector2i:
	return Vector2i(floori(_start_pos.x / _ROOM_PX_W), floori(_start_pos.y / _ROOM_PX_H))

func _in_current_room() -> bool:
	return _get_home_room() == _main.current_room

func _health_bar_visible() -> bool:
	return not _dead and _in_current_room() and not _main.map_overlay._open

func _update_health_bar() -> void:
	if _main == null:
		return
	Utils.update_sprite_health_bar(self, hp, get_max_hp(), _health_bar_visible())

func _handle_beam() -> void:
	if _main.electric_beam.active and _main.electric_beam.is_point_on_beam(get_center(), BEAM_RADIUS):
		hp -= 1
		_main._trigger_shake(2.0)
		if hp <= 0:
			hp = 0
			_die()

func _die() -> void:
	super._die()
	AudioManager.play_sfx("water_death")

func _process(delta: float) -> void:
	_update_health_bar()
	if not _in_current_room():
		return
	_eject_from_solid()
	if _main.map_overlay._open:
		return
	super._process(delta)

func reset() -> void:
	super.reset()
	hp = get_max_hp()
