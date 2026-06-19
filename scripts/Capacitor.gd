extends Node2D

# Beam-charged capacitor. Sprite sheet is 256×48 (8 frames of 32×48). The bottom
# 32×32 of each frame sits in the object's tile; the top 16px bleed into the tile
# above. Frame 0 = idle/uncharged. While the electric beam crosses its tile the
# animation charges forward toward the last frame and holds there; once the beam
# leaves it slowly discharges back to frame 0. While it is off frame 0 it powers
# every object that shares its id (doors, fans, etc.) like a FloorSwitch.

@export var id: String = ""

const FRAMES = 8
const CHARGE_TIME = 0.7    # seconds to charge from first to last frame (beam on)
const DISCHARGE_TIME = 8.0 # seconds to discharge back to the first frame (beam off)

var _progress = 0.0  # 0.0 = first frame, 1.0 = last frame
var _powered = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("capacitors")
	_apply_frame()

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func get_center() -> Vector2:
	return GridUtils.tile_center(position)

func reset() -> void:
	_progress = 0.0
	if _powered:
		_powered = false
		if id != "":
			GameManager.set_capacitor(id, false)
	_apply_frame()

func _hitbox_rect() -> Rect2:
	# The hitbox is the bottom 32×32 tile (the top 16px of the sprite bleed upward).
	return Rect2(position, Vector2(32.0, 32.0))

func _process(delta: float) -> void:
	var beam = get_tree().current_scene.electric_beam
	var on_beam = beam != null and beam.active and beam.is_rect_on_beam(_hitbox_rect())
	if on_beam:
		_progress = minf(_progress + delta / CHARGE_TIME, 1.0)
	else:
		_progress = maxf(_progress - delta / DISCHARGE_TIME, 0.0)
	_apply_frame()
	_update_power()

func _frame_index() -> int:
	return clampi(int(round(_progress * (FRAMES - 1))), 0, FRAMES - 1)

func _apply_frame() -> void:
	if sprite != null:
		sprite.frame = _frame_index()

func _update_power() -> void:
	if id == "":
		return
	# Powered whenever the capacitor is not resting on the first frame.
	var powered = _frame_index() > 0
	if powered != _powered:
		_powered = powered
		GameManager.last_activator_pos = get_center()
		GameManager.set_capacitor(id, powered)
