extends Node2D

# Solid floor object that emits light in a dark room while powered. It is wired up
# exactly like a Door (registers its `id` with GameManager and listens to doors_update),
# but instead of opening it lights a LIGHT_RADIUS circle around itself — the darkness
# overlay (Main / LevelEditor) queries the "light_sources" group and reads is_powered().
#
# Solid: occupies its 32×32 tile (in both scenes' _is_static_solid, group "light_sources"
# is in Y_SORT_GROUPS so it depth-sorts against walls / the player).
#
# Sprite: LED_Light-Sheet.webp — 14 frames of 32×40 (hframes=14). Frame 0 is the unlit
# bulb; the LAST frame (LIT_FRAME) is the lit bulb, shown only while powered.

const LIGHT_RADIUS := 112.0
const HFRAMES := 14
const LIT_FRAME := 13          # last frame — the lit bulb, shown only while powered

@export var id: String = ""

var _powered := false

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("light_sources")
	_sprite.hframes = HFRAMES
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
	_sprite.frame = LIT_FRAME if _powered else 0

func reset() -> void:
	_powered = false
	_apply_powered()
