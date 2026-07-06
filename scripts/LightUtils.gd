class_name LightUtils
extends RefCounted

# Stateless dark-room light geometry, shared by Main and LevelEditor (each passes its
# own player position + already-filtered powered LightSource nodes, so the room-scoping
# divergence stays in the scene). A LightSource node exposes get_light_pos() and the
# LIGHT_RADIUS const.

# Light list for the darkness overlay: the player's own light plus every powered
# LightSource in `sources`.
static func gather_lights(player_pos: Vector2, player_radius: float, sources: Array) -> Array:
	var lights: Array = [{"pos": player_pos, "radius": player_radius}]
	for ls in sources:
		lights.append({"pos": ls.get_light_pos(), "radius": ls.LIGHT_RADIUS})
	return lights

# Away-from-light push at `world_pos` from the given LightSource nodes ONLY (the
# player's light never repels). Hysteresis: an actor already fleeing keeps being pushed
# out to `exit_radius`; an actor at rest is only pushed once it is inside a source's own
# LIGHT_RADIUS. Each source's contribution grows the deeper in the point sits, so the
# result points the strongest way out. Vector2.ZERO ⇒ clear of the light, stop fleeing.
static func object_flee_vector(world_pos: Vector2, sources: Array, exit_radius: float, fleeing: bool) -> Vector2:
	var flee := Vector2.ZERO
	for ls in sources:
		var away: Vector2 = world_pos - ls.get_light_pos()
		var d := away.length()
		var threshold: float = exit_radius if fleeing else float(ls.LIGHT_RADIUS)
		if d < threshold:
			if d < 0.001:
				away = Vector2.RIGHT
				d = 0.001
			flee += away / d * (threshold - d)
	return flee
