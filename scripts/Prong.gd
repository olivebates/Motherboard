extends Node2D

# The root sits SORT_DROP px below the circuit point (the hitbox-bottom line a plain
# YSortHitboxBottom node would use) so the stake Y-sorts that much lower — i.e. it
# draws in front of the player once (prong sprite bottom − 4px) passes the player's
# feet. `circuit_pos` / `hitbox_center()` strip the drop back out so the beam, floor
# panels, grid and teleport logic keep using the real planted point.
const SORT_DROP := 8.0
const SORT_OFFSET := Vector2(0.0, SORT_DROP)

# Vertical sprite nudge above the tile-centered layout (purely visual; hitbox/grid unchanged).
const SPRITE_RAISE := Vector2(0.0, -2.0)

# The planted point (hitbox-bottom line) used by the circuit/puzzle code, with the
# Y-sort drop removed.
var circuit_pos: Vector2:
	get:
		return position - SORT_OFFSET

var grid_pos: Vector2i:
	get:
		return GridUtils.to_grid(circuit_pos)

@onready var _body: Node2D = $Body
@onready var _sprite: Sprite2D = $Body/Sprite2D
@onready var _hitbox: CollisionShape2D = $Body/Hitbox

var _half_w := 4.0
var _half_h := 4.0
var _hitbox_offset := Vector2(0.0, -4.0)
var _body_offset := Vector2.ZERO

func _ready() -> void:
	add_to_group("prongs")
	_sprite.centered = false
	var cfg := YSortHitboxBottom.read_hitbox(_hitbox)
	_half_w = cfg.half_w
	_half_h = cfg.half_h
	_hitbox_offset = cfg.offset
	_body_offset = YSortHitboxBottom.body_offset_from_hitbox(_hitbox_offset, _half_h)
	# Pull the body back up by the sort drop so the sprite/hitbox stay tile-centered
	# even though the root is dropped SORT_DROP px for depth sorting.
	_body.position = _body_offset - SORT_OFFSET

# World-space center of the hitbox (used by prong-to-prong teleport detection).
func hitbox_center() -> Vector2:
	return global_position - SORT_OFFSET + _body_offset + _hitbox_offset

func setup(pixel_pos: Vector2) -> void:
	# Appears at full size — the player's hammer-plant animation is the placement
	# flourish now (see Player.play_plant / Main.spawn_prong), so no grow tween here.
	position = YSortHitboxBottom.root_pos_from_hitbox_center(pixel_pos, _body_offset, _hitbox_offset) + SORT_OFFSET
	_sprite.position = YSortHitboxBottom.SPRITE_OFFSET + SPRITE_RAISE
	_sprite.scale = Vector2.ONE

func apply_clear_shrink(s: float) -> void:
	var half := Vector2(16.0, 16.0)
	if _sprite.texture:
		half = _sprite.texture.get_size() * 0.5
	_sprite.scale = Vector2(s, s)
	_sprite.position = YSortHitboxBottom.SPRITE_OFFSET + SPRITE_RAISE + half * (1.0 - s)
