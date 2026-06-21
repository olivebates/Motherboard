extends Node2D

const TILE_SIZE = 32
const ROOM_WIDTH = 25
const ROOM_HEIGHT = 12

# Groups whose members count as a "boss" for sealing purposes.
const BOSS_GROUPS = ["water_boss", "bounce_boss"]

# Pop sprite-sheet played as the door disappears (7 frames of 32×32).
const POP_TEX = preload("res://Sprites/Effects/Pop-Sheet.webp")
const POP_FRAMES = 7
const POP_DURATION = 0.42

var _opened := false
var grid_pos: Vector2i:
	get: return GridUtils.to_grid(position)
var start_grid_pos: Vector2i:
	get: return GridUtils.to_grid(position)

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("boss_doors")

func _process(_delta: float) -> void:
	# Seal the room until its boss has fully fallen off screen and vanished (or there
	# was never a boss). A defeated boss still mid-death-arc keeps the door sealed.
	if _opened:
		return
	if not _room_has_living_boss():
		open()

func _room_has_living_boss() -> bool:
	var my_room := _door_room()
	for group in BOSS_GROUPS:
		for boss in get_tree().get_nodes_in_group(group):
			# Treat the boss as present until it has vanished (not just hit 0 HP), so
			# the door waits for the off-screen death arc to finish.
			if not is_instance_valid(boss) or boss.get("_vanished"):
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
	# Drop out of the solid set immediately so the player can pass, then play the
	# pop animation before the node is freed.
	remove_from_group("boss_doors")
	_sprite.texture = POP_TEX
	_sprite.hframes = POP_FRAMES
	_sprite.vframes = 1
	_sprite.frame = 0
	var tw := create_tween()
	tw.tween_property(_sprite, "frame", POP_FRAMES - 1, POP_DURATION).from(0)
	await tw.finished
	queue_free()

func reset() -> void:
	if _opened:
		queue_free()
