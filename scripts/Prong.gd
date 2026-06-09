extends Node2D

var grid_pos: Vector2i:
	get:
		return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

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
	_body.position = _body_offset

func setup(pixel_pos: Vector2) -> void:
	position = YSortHitboxBottom.root_pos_from_hitbox_center(pixel_pos, _body_offset, _hitbox_offset)
	_sprite.position = YSortHitboxBottom.SPRITE_OFFSET
	_sprite.scale = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(1.3, 1.3), 0.08)
	tween.tween_property(_sprite, "scale", Vector2.ONE, 0.07)

func apply_clear_shrink(s: float) -> void:
	var half := Vector2(16.0, 16.0)
	if _sprite.texture:
		half = _sprite.texture.get_size() * 0.5
	_sprite.scale = Vector2(s, s)
	_sprite.position = YSortHitboxBottom.SPRITE_OFFSET + half * (1.0 - s)
