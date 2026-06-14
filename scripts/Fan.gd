extends Node2D

@export var id: String = ""
@export var direction: Vector2i = Vector2i(1, 0)

const TILE_SIZE := 32
const ROOM_WIDTH := 25
const ROOM_HEIGHT := 12
const PARTICLE_SPEED_MIN := 40.0
const PARTICLE_SPEED_MAX := 65.0
const PARTICLE_Z_INDEX := 10
const AIRFLOW_HALF_BAND := TILE_SIZE * 0.5

const PUSH_INTERVAL := 0.8

const SLIDE_DURATION := 0.15

static var _block_last_pushed: Dictionary = {}

var _blocks_in_airflow: Dictionary = {}

var _on := false
var _airflow_end_local := Vector2.ZERO
var _particles: CPUParticles2D
var _particle_dist := -1.0
var grid_pos: Vector2i = Vector2i.ZERO
var start_grid_pos: Vector2i = Vector2i.ZERO
var _slide_tween: Tween = null
var _sliding := false
var _hold_particles := false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("fans")
	add_to_group("push_blocks")
	add_to_group("nuts")
	start_grid_pos = Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))
	grid_pos = start_grid_pos
	position = Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)
	GameManager.register_door(self, id)
	GameManager.doors_update.connect(_on_doors_update)
	_particles = _create_dust_particles()
	sprite.add_child(_particles)

func _exit_tree() -> void:
	GameManager.unregister_door(self, id)
	if _particles:
		_particles.emitting = false

func get_grid_pos() -> Vector2i:
	return grid_pos

func get_collision_rect() -> Rect2:
	return Rect2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE, float(TILE_SIZE), float(TILE_SIZE))

func push(dir: Vector2i) -> void:
	var old_world := Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)
	grid_pos += dir
	var new_world := Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)
	position = new_world
	sprite.position = old_world - new_world
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_SINE)
	_sliding = true
	_slide_tween.tween_property(sprite, "position", Vector2.ZERO, SLIDE_DURATION)
	_slide_tween.tween_callback(func(): _sliding = false)

func reset() -> void:
	if _slide_tween:
		_slide_tween.kill()
	_sliding = false
	_hold_particles = false
	_blocks_in_airflow.clear()
	grid_pos = start_grid_pos
	position = Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)
	sprite.position = Vector2.ZERO
	_clear_particles()

func prepare_reset() -> void:
	_hold_particles = true
	_blocks_in_airflow.clear()
	_clear_particles()

func get_beam_point() -> Vector2:
	return global_position + sprite.position + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)

func is_active() -> bool:
	return _on

func _on_doors_update(door_id: String, open: bool) -> void:
	if door_id == id:
		_on = open
		if not _on:
			_clear_particles()

func _get_airflow_end_world() -> Vector2:
	var gp = get_grid_pos()
	var room = Vector2i(floori(float(gp.x) / ROOM_WIDTH), floori(float(gp.y) / ROOM_HEIGHT))
	var rx0 = room.x * ROOM_WIDTH
	var ry0 = room.y * ROOM_HEIGHT
	var cur = gp + direction
	while cur.x >= rx0 and cur.x < rx0 + ROOM_WIDTH and cur.y >= ry0 and cur.y < ry0 + ROOM_HEIGHT:
		cur += direction
	var end_tile = cur - direction
	return Vector2(end_tile.x * TILE_SIZE + 16.0, end_tile.y * TILE_SIZE + 16.0)

func is_position_in_airflow(world_pos: Vector2) -> bool:
	if not _on:
		return false
	var gp = get_grid_pos()
	var room = Vector2i(floori(float(gp.x) / ROOM_WIDTH), floori(float(gp.y) / ROOM_HEIGHT))
	var rx0 = room.x * ROOM_WIDTH
	var ry0 = room.y * ROOM_HEIGHT
	var pos_tile = Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))

	if direction.x != 0:
		if pos_tile.y != gp.y:
			return false
		if direction.x > 0:
			return pos_tile.x > gp.x and pos_tile.x < rx0 + ROOM_WIDTH
		else:
			return pos_tile.x < gp.x and pos_tile.x >= rx0
	else:
		if pos_tile.x != gp.x:
			return false
		if direction.y > 0:
			return pos_tile.y > gp.y and pos_tile.y < ry0 + ROOM_HEIGHT
		else:
			return pos_tile.y < gp.y and pos_tile.y >= ry0

func _process(delta: float) -> void:
	if not _on or _hold_particles:
		return
	_airflow_end_local = _get_airflow_end_world() - position
	_update_particles()
	_push_blocks_in_airflow()

func _push_blocks_in_airflow() -> void:
	var main = get_tree().current_scene
	var now := Time.get_ticks_msec() / 1000.0
	var current_bids: Dictionary = {}

	for block in get_tree().get_nodes_in_group("wind_pushable"):
		if not is_position_in_airflow(block.get_collision_rect().get_center()):
			continue
		var bid := block.get_instance_id()
		current_bids[bid] = true

		if not _blocks_in_airflow.has(bid):
			_blocks_in_airflow[bid] = now
			continue

		if now - _blocks_in_airflow[bid] < PUSH_INTERVAL:
			continue
		if now - _block_last_pushed.get(bid, -INF) < PUSH_INTERVAL:
			continue
		var dest: Vector2i = block.grid_pos + direction
		if main.can_push_block_to(dest):
			_block_last_pushed[bid] = now
			_blocks_in_airflow[bid] = now
			block.push(direction)

	for bid in _blocks_in_airflow.keys():
		if not current_bids.has(bid):
			_blocks_in_airflow.erase(bid)

func _create_dust_particles() -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.z_as_relative = false
	particles.z_index = PARTICLE_Z_INDEX
	particles.local_coords = true
	particles.emitting = false
	particles.one_shot = false
	particles.spread = 0.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.color = Color.WHITE
	return particles

func _stop_particles() -> void:
	_particle_dist = -1.0
	if _particles:
		_particles.emitting = false

func _clear_particles() -> void:
	_particle_dist = -1.0
	if is_instance_valid(_particles):
		_particles.queue_free()
	_particles = _create_dust_particles()
	sprite.add_child(_particles)

func _update_particles() -> void:
	if _sliding:
		return
	var fan_center := Vector2(16.0, 16.0)
	var end_local := _airflow_end_local
	var dir_norm := Vector2(direction).normalized()
	var total_dist := (end_local - fan_center).length()
	if total_dist < 1.0:
		_stop_particles()
		return

	if is_equal_approx(total_dist, _particle_dist) and _particles.emitting:
		return
	_particle_dist = total_dist

	_particles.position = fan_center + dir_norm * (total_dist * 0.5)
	_particles.direction = dir_norm

	if absi(direction.x) > 0:
		_particles.emission_rect_extents = Vector2(total_dist * 0.5, AIRFLOW_HALF_BAND)
	else:
		_particles.emission_rect_extents = Vector2(AIRFLOW_HALF_BAND, total_dist * 0.5)

	var avg_speed := (PARTICLE_SPEED_MIN + PARTICLE_SPEED_MAX) * 0.5
	_particles.lifetime = total_dist / avg_speed
	_particles.initial_velocity_min = PARTICLE_SPEED_MIN
	_particles.initial_velocity_max = PARTICLE_SPEED_MAX
	_particles.amount = clampi(int(total_dist / 3.0), 48, 180)
	if not _particles.emitting:
		_particles.preprocess = _particles.lifetime
		_particles.emitting = true
