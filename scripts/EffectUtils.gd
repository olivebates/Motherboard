class_name EffectUtils

## Stateless one-shot particle helper (mirrors the other static-helper utils).

## Spawn a fire-and-forget CPUParticles2D burst at pos under parent: it emits once
## immediately and frees itself after it finishes. Tunable via params (all
## optional, sensible defaults):
##   z_index, explosiveness, amount, lifetime, velocity_min, velocity_max,
##   gravity, scale_min, scale_max, color, direction, spread
static func spawn_burst(parent: Node, pos: Vector2, params: Dictionary) -> void:
	var p = CPUParticles2D.new()
	p.position = pos
	p.z_index = params.get("z_index", 10)
	p.one_shot = true
	p.explosiveness = params.get("explosiveness", 1.0)
	p.amount = params.get("amount", 16)
	p.lifetime = params.get("lifetime", 0.6)
	if params.has("direction"):
		p.direction = params["direction"]
	if params.has("spread"):
		p.spread = params["spread"]
	p.initial_velocity_min = params.get("velocity_min", 0.0)
	p.initial_velocity_max = params.get("velocity_max", 0.0)
	p.gravity = params.get("gravity", Vector2.ZERO)
	p.scale_amount_min = params.get("scale_min", 1.0)
	p.scale_amount_max = params.get("scale_max", 1.0)
	p.color = params.get("color", Color.WHITE)
	p.emitting = true
	parent.add_child(p)
	p.get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)
