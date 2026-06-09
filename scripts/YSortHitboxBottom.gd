class_name YSortHitboxBottom

## Helpers for nodes whose root position is the hitbox bottom (Y-sort key).

const SPRITE_OFFSET := Vector2(-16.0, -16.0)

static func read_hitbox(hitbox: CollisionShape2D) -> Dictionary:
	var rect := hitbox.shape as RectangleShape2D
	var half_w := rect.size.x * 0.5
	var half_h := rect.size.y * 0.5
	return {
		"half_w": half_w,
		"half_h": half_h,
		"offset": hitbox.position,
	}

static func body_offset_from_hitbox(hitbox_offset: Vector2, half_h: float) -> Vector2:
	return Vector2(0.0, -(hitbox_offset.y + half_h))

static func hitbox_center_from_root(root_pos: Vector2, body_offset: Vector2, hitbox_offset: Vector2) -> Vector2:
	return root_pos + body_offset + hitbox_offset

static func root_pos_from_hitbox_center(center: Vector2, body_offset: Vector2, hitbox_offset: Vector2) -> Vector2:
	return center - body_offset - hitbox_offset
