extends Node2D

const RADIUS := 5.0
const DURATION := 0.28

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color.WHITE)

func launch(from: Vector2, to: Vector2, on_arrive: Callable) -> void:
	position = from
	z_index = 20
	var t = create_tween()
	t.tween_property(self, "position", to, DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func():
		on_arrive.call()
		queue_free()
	)
