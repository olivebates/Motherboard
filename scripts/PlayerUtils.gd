class_name PlayerUtils

## Stateless helpers for player-vs-world queries and shared player-driven sequences
## (mirrors the other static-helper utils). The player implements get_push_hitbox()
## -> Rect2 (its world hitbox).

## True if the player's hitbox overlaps the given world rect — e.g. standing on an
## open panel / exit point.
static func standing_on(rect: Rect2, player: Node) -> bool:
	return rect.intersects(player.get_push_hitbox())

## True if the player is giving movement input AND its hitbox overlaps rect grown
## by margin — i.e. actively pressing into a panel to open it.
static func is_pressing_into(rect: Rect2, player: Node, margin: float) -> bool:
	var input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input.length_squared() == 0.0:
		return false
	return rect.grow(margin).intersects(player.get_push_hitbox())

## Prong-to-prong teleport sequence shared by Main and LevelEditor: lock → depart
## animation → spawn SFX → place at the other prong → arrive animation → unlock.
static func teleport_between_prongs(player: Node, target_center: Vector2) -> void:
	player.lock_movement()
	await player.play_teleport()
	AudioManager.play_sfx("electric_spawn", 0.0)
	player.move_to_center(target_center)
	await player.play_teleport(true)
	player.unlock_movement()
