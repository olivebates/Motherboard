extends Node2D

# Hole — a pit in the floor.
#
# While EMPTY the hole is a solid wall. Push a pushable object onto it and the
# object sinks in over SINK_TIME seconds, filling the hole and making the tile
# passable to the player, enemies and other pushable objects. A NanoDroid that
# walks in falls down it (and is destroyed) but the hole stays SOLID — it can
# still be filled by a pushable object afterward, which clears the droid sprite.
#
# Fill visuals: a Nut swaps the hole to hole_nut.png, a regular PushBlock swaps
# it to hole_filled.png, and any other object (or a fallen droid) is drawn on
# top of hole1.png.

const TILE_SIZE = 32
const SINK_TIME = 0.4

const TEX_EMPTY = preload("res://Sprites/objects/Holes/hole1.png")
const TEX_FILLED = preload("res://Sprites/objects/Holes/hole_filled.png")
const TEX_NUT = preload("res://Sprites/objects/Holes/hole_nut.png")

enum State { EMPTY, FILLING, FILLED, NANO }

@export var start_grid_pos: Vector2i = Vector2i.ZERO

var grid_pos: Vector2i = Vector2i.ZERO
var _state: int = State.EMPTY
var _main: Node = null
var _sink_time = 0.0
var _filling_actor: Node = null
# Pushable objects this hole has absorbed; kept alive so reset() can restore them.
var _consumed_blocks: Array = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var _overlay: Sprite2D = $Overlay

func _ready() -> void:
	add_to_group("holes")
	_main = get_tree().current_scene
	start_grid_pos = GridUtils.to_grid(position)
	grid_pos = start_grid_pos
	position = Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite.texture = TEX_EMPTY
	_overlay.centered = false
	_overlay.position = Vector2.ZERO
	_overlay.visible = false

func get_grid_pos() -> Vector2i:
	return grid_pos

func is_solid() -> bool:
	# Empty, mid-fill, and droid-filled holes block like a wall; only a hole
	# fully filled by a pushable object is passable.
	return _state != State.FILLED

func can_accept_block() -> bool:
	# A pushable object may be pushed into an empty hole or onto a droid-filled one.
	return _state == State.EMPTY or _state == State.NANO

func _process(delta: float) -> void:
	# Inert in the level editor BUILD state (the beam node only exists once a
	# playtest starts) so placing objects never triggers a fill.
	if _main == null or _main.get("electric_beam") == null:
		return
	match _state:
		State.EMPTY:
			_detect_block()
			if _state == State.EMPTY:
				_detect_droid()
		State.NANO:
			_detect_block()
		State.FILLING:
			_advance_fill(delta)

func _detect_block() -> void:
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.get("grid_pos") == grid_pos:
			_begin_fill(block)
			return

func _detect_droid() -> void:
	for droid in get_tree().get_nodes_in_group("nanodroids"):
		if droid._destroyed:
			continue
		var c: Vector2 = droid.get_center()
		var tile = Vector2i(floori(c.x / TILE_SIZE), floori(c.y / TILE_SIZE))
		if tile == grid_pos:
			_consume_droid(droid)
			return

func _begin_fill(block: Node) -> void:
	_state = State.FILLING
	_filling_actor = block
	_sink_time = 0.0
	# Pull it out of collision/beam queries immediately so it can't be pushed back
	# out mid-sink; the hole's FILLING state keeps the tile solid meanwhile.
	_absorb_block(block)

func _advance_fill(delta: float) -> void:
	if not is_instance_valid(_filling_actor):
		_state = State.EMPTY
		_filling_actor = null
		return
	_sink_time += delta
	if _sink_time >= SINK_TIME:
		_finalize_fill(_filling_actor)

func _finalize_fill(block: Node) -> void:
	_filling_actor = null
	_sink_time = 0.0
	# Any droid sprite previously drawn here is replaced by the pushable fill.
	_overlay.visible = false
	_overlay.texture = null

	match _block_kind(block):
		"nut":
			sprite.texture = TEX_NUT
		"block":
			sprite.texture = TEX_FILLED
		_:
			sprite.texture = TEX_EMPTY
			var bs = block.get_node_or_null("Sprite2D")
			if bs != null:
				_overlay.texture = bs.texture
				_overlay.visible = true
	block.visible = false
	_state = State.FILLED

func _consume_droid(droid: Node) -> void:
	# The droid falls in and is destroyed; the hole stays solid but now draws the
	# droid sprite. A pushable object can still be pushed in later to fill it.
	droid._destroyed = true
	if droid.sprite != null:
		_overlay.texture = droid.sprite.texture
		droid.sprite.visible = false
	_overlay.visible = true
	_state = State.NANO

func _absorb_block(block: Node) -> void:
	# Keep the node alive (so reset() can restore it) but pull it out of every
	# collision/beam query so the filled tile reads as floor and the object can't
	# be pushed back out. Visibility is handled by the caller (it stays visible
	# while sinking, then hidden once the hole is filled).
	block.remove_from_group("push_blocks")
	block.remove_from_group("nuts")
	if not _consumed_blocks.has(block):
		_consumed_blocks.append(block)

func _block_kind(block: Node) -> String:
	var scr = block.get_script()
	var path: String = scr.resource_path if scr != null else ""
	if path.ends_with("Nut.gd"):
		return "nut"
	if path.ends_with("PushBlock.gd"):
		return "block"
	return "other"

func reset() -> void:
	for block in _consumed_blocks:
		if not is_instance_valid(block):
			continue
		block.visible = true
		if not block.is_in_group("push_blocks"):
			block.add_to_group("push_blocks")
		if _block_kind(block) == "nut" and not block.is_in_group("nuts"):
			block.add_to_group("nuts")
		if block.has_method("reset"):
			block.reset()
	_consumed_blocks.clear()
	_state = State.EMPTY
	_filling_actor = null
	_sink_time = 0.0
	sprite.texture = TEX_EMPTY
	_overlay.visible = false
	_overlay.texture = null
