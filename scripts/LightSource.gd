extends Node2D

# Floor object that emits light in a dark room while powered. It is wired up exactly
# like a Door (registers its `id` with GameManager and listens to doors_update), but
# instead of opening it lights a LIGHT_RADIUS circle around itself — the darkness
# overlay (Main / LevelEditor) queries the "light_sources" group and reads is_powered().

const LIGHT_RADIUS := 112.0

@export var id: String = ""

var _powered := false

func _ready() -> void:
	add_to_group("light_sources")
	if id != "":
		GameManager.register_door(self, id)
	GameManager.doors_update.connect(_on_doors_update)
	_apply_powered()

func _exit_tree() -> void:
	if id != "":
		GameManager.unregister_door(self, id)

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func is_powered() -> bool:
	return _powered

# World-space center of the emitted light (tile center).
func get_light_pos() -> Vector2:
	return position + Vector2(16.0, 16.0)

func _on_doors_update(door_id: String, powered: bool) -> void:
	if door_id != id:
		return
	_powered = powered
	_apply_powered()

func _apply_powered() -> void:
	# Subtle brighten of the pad sprite while powered so it reads as "on" even in the light.
	$Sprite2D.modulate = Color(1.0, 1.0, 1.0) if _powered else Color(0.6, 0.6, 0.6)

func reset() -> void:
	_powered = false
	_apply_powered()
