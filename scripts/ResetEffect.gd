extends CanvasLayer

signal peaked
signal done

const FADE_IN := 0.28
const FADE_OUT := 0.22

var color: Color = Color.WHITE

var _rect: ColorRect
var _mat: ShaderMaterial
var _tween: Tween
var _time := 0.0
var _active := false

const _SHADER := """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float noise_time = 0.0;
uniform float noise_seed = 0.0;
uniform vec3 tint_color = vec3(1.0, 1.0, 1.0);

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}
float rand1(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	float envelope = progress;

	// Horizontal glitch: some rows shift sideways
	float row4 = floor(FRAGCOORD.y / 4.0);
	float glitch_chance = rand1(row4 + floor(noise_time * 13.0));
	float glitch_px = step(0.80, glitch_chance) * rand1(row4 + noise_time * 3.7) * 20.0;

	// 2px chunky noise — seed is fully randomised each frame so static is never repeated
	vec2 noise_coord = floor((FRAGCOORD.xy + vec2(glitch_px, 0.0)) / 2.0);
	float noise = rand(noise_coord + vec2(noise_seed, noise_seed * 1.618));

	// Scanlines: every row has its own random speed and direction
	float row_r = rand1(FRAGCOORD.y * 57.3 + 0.5);
	float row_speed = (60.0 + row_r * 160.0) * (step(0.5, row_r) * 2.0 - 1.0);
	float scan = step(0.5, fract((FRAGCOORD.y + noise_time * row_speed) / 3.0));

	// Rare bright horizontal flash bars
	float bar_seed = rand1(floor(FRAGCOORD.y / 3.0) + floor(noise_time * 22.0));
	float bright_bar = step(0.955, bar_seed);

	float intensity = noise * 0.72 + scan * 0.14 + bright_bar;
	intensity = min(intensity, 1.0);
	COLOR = vec4(vec3(intensity * 0.88 + 0.12) * tint_color, envelope);
}
"""

func _ready() -> void:
	layer = 20
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.size = Vector2(800, 384)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = _SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect.material = _mat
	add_child(_rect)
	_rect.visible = false

func play() -> void:
	_active = true
	_time = randf() * 100.0
	_mat.set_shader_parameter("progress", 0.0)
	_mat.set_shader_parameter("noise_time", _time)
	_mat.set_shader_parameter("noise_seed", randf() * 1000.0)
	_mat.set_shader_parameter("tint_color", Vector3(color.r, color.g, color.b))
	_rect.visible = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float): _mat.set_shader_parameter("progress", v), 0.0, 1.0, FADE_IN)
	_tween.tween_callback(func(): peaked.emit())
	_tween.tween_interval(0.2)
	_tween.tween_method(func(v: float): _mat.set_shader_parameter("progress", v), 1.0, 0.0, FADE_OUT)
	_tween.tween_callback(func(): _rect.visible = false; _active = false; done.emit())

func play_teleport_buildup() -> void:
	_active = true
	_time = randf() * 100.0
	_mat.set_shader_parameter("progress", 0.0)
	_mat.set_shader_parameter("noise_time", _time)
	_mat.set_shader_parameter("noise_seed", randf() * 1000.0)
	_mat.set_shader_parameter("tint_color", Vector3(color.r, color.g, color.b))
	_rect.visible = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float): _mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.4)

func cancel() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	_rect.visible = false
	_active = false

func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	_mat.set_shader_parameter("noise_time", _time)
	# New random seed every frame so noise pixels never repeat or drift smoothly
	_mat.set_shader_parameter("noise_seed", randf() * 1000.0)
