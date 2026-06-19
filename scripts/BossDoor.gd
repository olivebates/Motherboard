extends Node2D

const TILE_SIZE = 32
const ROOM_WIDTH = 25
const ROOM_HEIGHT = 12

# Groups whose members count as a "boss" for sealing purposes.
const BOSS_GROUPS = ["water_boss", "bounce_boss"]

var _opened := false
var grid_pos: Vector2i:
	get: return GridUtils.to_grid(position)
var start_grid_pos: Vector2i:
	get: return GridUtils.to_grid(position)

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("boss_doors")

func _process(_delta: float) -> void:
	# Seal the room only while a living boss remains in it; open as soon as the
	# room has no living boss (whether defeated or never present).
	if _opened:
		return
	if not _room_has_living_boss():
		open()

func _room_has_living_boss() -> bool:
	var my_room := _door_room()
	for group in BOSS_GROUPS:
		for boss in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(boss) or boss.get("_dead"):
				continue
			if boss._get_home_room() == my_room:
				return true
	return false

func _door_room() -> Vector2i:
	var gp := get_grid_pos()
	return Vector2i(floori(float(gp.x) / ROOM_WIDTH), floori(float(gp.y) / ROOM_HEIGHT))

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func get_collision_rect() -> Rect2:
	return Rect2(position.x, position.y, float(TILE_SIZE), float(TILE_SIZE))

func open() -> void:
	_opened = true
	SaveManager.notify_boss_door_opened(start_grid_pos)
	queue_free()

func reset() -> void:
	if _opened:
		queue_free()
