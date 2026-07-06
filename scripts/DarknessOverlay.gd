class_name DarknessOverlay
extends CanvasLayer

# Self-contained "dark room" overlay shared by Main and LevelEditor (playtest).
# Owns a full-screen ColorRect running darkness.gdshader that blacks out the room
# except for soft circular light holes. Drive it each frame with update_lights();
# toggle the whole effect with set_dark() (fades the black in/out over FADE_DURATION).
#
# Layer 40 keeps it above the world (and the "TAB" prompt on layer 5) but below the
# save-status (50), settings (60), and black-tint (100) canvas layers, so menus and
# the room-colour tint are unaffected.

const DarknessShader = preload("res://shaders/darkness.gdshader")
const MAX_LIGHTS := 32
const FADE_DURATION := 0.15

var _mat: ShaderMaterial
var _rect: ColorRect
var _alpha := 0.0
var _target_alpha := 0.0

func _ready() -> void:
	layer = 40
	_mat = ShaderMaterial.new()
	_mat.shader = DarknessShader
	_mat.set_shader_parameter("darkness", 0.0)
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	visible = false

# Turn the darkness on/off. `fade` ramps the black in (or out) over FADE_DURATION;
# pass false to snap (e.g. when spawning straight into a dark room).
func set_dark(dark: bool, fade: bool = true) -> void:
	_target_alpha = 1.0 if dark else 0.0
	if not fade:
		_alpha = _target_alpha
		_mat.set_shader_parameter("darkness", _alpha)
	if dark:
		visible = true

func is_dark() -> bool:
	return _target_alpha > 0.0

# lights: Array of { "pos": Vector2 (world), "radius": float }. Converts each to the
# viewport-pixel space the shader samples in (same math as the "TAB"/"SPACE" prompts).
func update_lights(camera: Camera2D, lights: Array) -> void:
	var positions := PackedVector2Array()
	var radii := PackedFloat32Array()
	var cam_center := camera.position + camera.offset
	for l in lights:
		if positions.size() >= MAX_LIGHTS:
			break
		positions.append(Vector2(l["pos"]) - cam_center + Vector2(400.0, 192.0))
		radii.append(l["radius"])
	_mat.set_shader_parameter("light_count", positions.size())
	if positions.size() > 0:
		_mat.set_shader_parameter("lights", positions)
		_mat.set_shader_parameter("radii", radii)

func _process(delta: float) -> void:
	if _alpha == _target_alpha:
		if _alpha == 0.0:
			visible = false
		return
	_alpha = move_toward(_alpha, _target_alpha, delta / FADE_DURATION)
	_mat.set_shader_parameter("darkness", _alpha)
	if _alpha == 0.0:
		visible = false
