extends Node2D

const TILE_SIZE := 32
const WORLD_OFFSET := 0
const ROOM_WIDTH := 25
const ROOM_HEIGHT := 12
const ROOM_PIXEL_WIDTH := ROOM_WIDTH * TILE_SIZE
const ROOM_PIXEL_HEIGHT := ROOM_HEIGHT * TILE_SIZE
const CAMERA_TWEEN_DURATION := 0.25
const CAMERA_MARGIN := Vector2(16.0, 16.0)

@onready var wall_tilemap: TileMapLayer = $Walls
@export var pass_tilemap: TileMapLayer

var current_room := Vector2i(0, 0)
var room_entry_positions: Dictionary = {}
var _cam_tween: Tween = null
var _shake_amount := 0.0
var _resetting := false

@onready var player: Node2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var electric_beam: Node2D = $ElectricBeam

var reset_effect: Node
var map_overlay: Node
var ability_message: Node
var _color_tween: Tween = null

var _tab_canvas: CanvasLayer
var _tab_label: Label

const ProngScene = preload("res://scenes/player/Prong.tscn")
const DoorBallScene = preload("res://scripts/DoorBall.gd")

const ResetEffectScene = preload("res://scripts/ResetEffect.gd")
const SplashScreenScene = preload("res://scripts/SplashScreen.gd")
const MapOverlayScene = preload("res://scripts/MapOverlay.gd")
const AbilityMessageScene = preload("res://scripts/AbilityMessage.gd")

const Y_SORT_GROUPS := [
	"players",
	"prongs",
	"doors",
	"lightning_blockers",
	"key_doors",
	"push_blocks",
	"pass_blocks",
	"keys",
	"teleport_panels",
	"screws",
	"enemies",
	"breakable_walls",
	"fans",
	"dust_piles",
	"wind_turbines",
]

func _ready() -> void:
	_setup_y_sort_children()
	room_entry_positions[Vector2i(0, 0)] = Vector2i(2, 2)
	reset_effect = ResetEffectScene.new()
	add_child(reset_effect)
	ability_message = AbilityMessageScene.new()
	add_child(ability_message)
	reset_effect.color = modulate
	map_overlay = MapOverlayScene.new()
	add_child(map_overlay)
	map_overlay.setup(self, wall_tilemap)
	map_overlay.teleport_requested.connect(_on_teleport_requested)
	map_overlay.visit(current_room)
	camera.position = _room_center(Vector2i(0, 0))
	GameManager.shake_requested.connect(_trigger_shake)
	_tab_canvas = CanvasLayer.new()
	_tab_canvas.layer = 5
	add_child(_tab_canvas)
	_tab_label = Label.new()
	_tab_label.text = "TAB"
	_tab_label.visible = false
	_tab_label.add_theme_color_override("font_color", modulate)
	_tab_label.add_theme_font_size_override("font_size", 11)
	_tab_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_tab_label.add_theme_constant_override("outline_size", 2)
	_tab_canvas.add_child(_tab_label)
	queue_redraw()
	var start_anchor := _get_anchor_for_room(current_room)
	if start_anchor != null:
		modulate = start_anchor.color
		reset_effect.color = modulate
		room_entry_positions[current_room] = Vector2i(floori(start_anchor.position.x / TILE_SIZE), floori(start_anchor.position.y / TILE_SIZE))
		if start_anchor.music != "":
			AudioManager.set_music(start_anchor.music)
	if not SaveManager.skip_splash:
		var splash := SplashScreenScene.new()
		add_child(splash)
		player.lock_movement()
	_setup_mute_buttons()


var _music_btn: Button
var _sfx_btn: Button
var _btn_border_styles: Array[StyleBoxFlat] = []
var _btn_hover_styles: Array[StyleBoxFlat] = []
var _last_btn_color := Color.WHITE

func _setup_mute_buttons() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 60
	add_child(canvas)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", 2)
	canvas.add_child(row)

	_music_btn = _make_mute_button("♪")
	_music_btn.pressed.connect(_on_music_mute_pressed)
	row.add_child(_music_btn)

	_sfx_btn = _make_mute_button("SFX")
	_sfx_btn.pressed.connect(_on_sfx_mute_pressed)
	row.add_child(_sfx_btn)

	_update_mute_button(_music_btn, AudioManager.is_music_muted())
	_update_mute_button(_sfx_btn, AudioManager.is_sfx_muted())
	_refresh_mute_button_colors(modulate)
	call_deferred("_equalize_button_sizes")

func _equalize_button_sizes() -> void:
	var w := maxf(_music_btn.size.x, _sfx_btn.size.x)
	var h := maxf(_music_btn.size.y, _sfx_btn.size.y)
	_music_btn.custom_minimum_size = Vector2(w, h)
	_sfx_btn.custom_minimum_size = Vector2(w, h)

func _make_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(1)
	return s

func _make_mute_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 9)
	var c := modulate
	var sn := _make_btn_style(Color.BLACK, c)
	var sh := _make_btn_style(c, c)
	var sp := _make_btn_style(Color.BLACK, c)
	var sf := _make_btn_style(Color.BLACK, c)
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", sf)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", Color.BLACK)
	btn.add_theme_color_override("font_pressed_color", c)
	btn.add_theme_color_override("font_focus_color", c)
	_btn_border_styles.append_array([sn, sp, sf])
	_btn_hover_styles.append(sh)
	return btn

func _refresh_mute_button_colors(c: Color) -> void:
	for s in _btn_border_styles:
		s.border_color = c
	for s in _btn_hover_styles:
		s.bg_color = c
		s.border_color = c
	for btn in [_music_btn, _sfx_btn]:
		if btn == null:
			continue
		btn.add_theme_color_override("font_color", c)
		btn.add_theme_color_override("font_pressed_color", c)
		btn.add_theme_color_override("font_focus_color", c)

func _update_mute_button(btn: Button, muted: bool) -> void:
	btn.modulate = Color(0.35, 0.35, 0.35) if muted else Color.WHITE

func _on_music_mute_pressed() -> void:
	_update_mute_button(_music_btn, AudioManager.toggle_music_mute())

func _on_sfx_mute_pressed() -> void:
	_update_mute_button(_sfx_btn, AudioManager.toggle_sfx_mute())


func _setup_y_sort_children() -> void:
	if wall_tilemap == null:
		return
	wall_tilemap.y_sort_enabled = true
	y_sort_enabled = false
	var reparented := {}
	for group_name in Y_SORT_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is Node2D or node.get_parent() != self:
				continue
			if reparented.has(node):
				continue
			reparented[node] = true
			node.reparent(wall_tilemap, true)

func _process(delta: float) -> void:
	_shake_amount = lerpf(_shake_amount, 0.0, 20.0 * delta)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amount
	_update_tab_label()
	if modulate != _last_btn_color:
		_last_btn_color = modulate
		_refresh_mute_button_colors(modulate)

func _update_tab_label() -> void:
	if _tab_label == null:
		return
	var show := can_teleport_from_panel()
	_tab_label.visible = show
	if show:
		_tab_label.add_theme_color_override("font_color", modulate)
		# Follow visual_pos (sprite lerp anchor) and sit above the sprite top (-16) with extra gap
		var world_pos := Vector2(player.visual_pos.x, player.visual_pos.y - 16.0 - 14.0)
		var screen_pos := world_pos - camera.position - camera.offset + Vector2(400.0, 192.0)
		_tab_label.position = screen_pos - Vector2(_tab_label.size.x * 0.5, 0.0)

func _trigger_shake(strength: float) -> void:
	_shake_amount = strength

func shoot_door_ball(from: Vector2, to: Vector2, on_arrive: Callable) -> void:
	var ball = DoorBallScene.new()
	add_child(ball)
	ball.launch(from, to, on_arrive)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_room") and not player.movement_locked:
		_reset_room()

func _reset_room() -> void:
	if _resetting:
		return
	_resetting = true
	player.lock_movement()
	AudioManager.play_sfx("character_death")
	reset_effect.play()
	var rx0 := current_room.x * ROOM_WIDTH
	var ry0 := current_room.y * ROOM_HEIGHT
	for fan in get_tree().get_nodes_in_group("fans"):
		var fgp: Vector2i = fan.start_grid_pos
		if fgp.x >= rx0 and fgp.x < rx0 + ROOM_WIDTH and fgp.y >= ry0 and fgp.y < ry0 + ROOM_HEIGHT:
			fan.prepare_reset()
	await reset_effect.peaked
	for p in GameManager.prongs.duplicate():
		var gp: Vector2i = p["grid_pos"]
		if gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT:
			GameManager.remove_prong(p["node"])
			p["node"].queue_free()
	_update_beam()
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var sgp: Vector2i = block.start_grid_pos
		if sgp.x >= rx0 and sgp.x < rx0 + ROOM_WIDTH and sgp.y >= ry0 and sgp.y < ry0 + ROOM_HEIGHT:
			block.reset()
	for fan in get_tree().get_nodes_in_group("fans"):
		var fgp: Vector2i = fan.start_grid_pos
		if fgp.x >= rx0 and fgp.x < rx0 + ROOM_WIDTH and fgp.y >= ry0 and fgp.y < ry0 + ROOM_HEIGHT:
			fan.reset()
	for wall in get_tree().get_nodes_in_group("breakable_walls"):
		var wgp: Vector2i = wall.get_grid_pos()
		if wgp.x >= rx0 and wgp.x < rx0 + ROOM_WIDTH and wgp.y >= ry0 and wgp.y < ry0 + ROOM_HEIGHT:
			wall.reset()
	for door in get_tree().get_nodes_in_group("key_doors"):
		var dgp: Vector2i = door.get_grid_pos()
		if dgp.x >= rx0 and dgp.x < rx0 + ROOM_WIDTH and dgp.y >= ry0 and dgp.y < ry0 + ROOM_HEIGHT:
			door.reset()
	for key in get_tree().get_nodes_in_group("keys"):
		var kgp: Vector2i = key.start_grid_pos
		if kgp.x >= rx0 and kgp.x < rx0 + ROOM_WIDTH and kgp.y >= ry0 and kgp.y < ry0 + ROOM_HEIGHT:
			key.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var egp := Vector2i(floori(enemy._start_pos.x / TILE_SIZE), floori(enemy._start_pos.y / TILE_SIZE))
		if egp.x >= rx0 and egp.x < rx0 + ROOM_WIDTH and egp.y >= ry0 and egp.y < ry0 + ROOM_HEIGHT:
			if enemy.is_in_group("boss_spawned_enemies"):
				enemy.queue_free()
			else:
				enemy.reset()
	for dust in get_tree().get_nodes_in_group("dust_piles"):
		var dgp: Vector2i = dust.get_grid_pos()
		if dgp.x >= rx0 and dgp.x < rx0 + ROOM_WIDTH and dgp.y >= ry0 and dgp.y < ry0 + ROOM_HEIGHT:
			dust.reset()
	for turbine in get_tree().get_nodes_in_group("wind_turbines"):
		var tgp: Vector2i = turbine.get_grid_pos()
		if tgp.x >= rx0 and tgp.x < rx0 + ROOM_WIDTH and tgp.y >= ry0 and tgp.y < ry0 + ROOM_HEIGHT:
			turbine.reset()
	player.reset_to(room_entry_positions.get(current_room, Vector2i(2, 2)))
	await reset_effect.done
	_resetting = false
	player.unlock_movement()

func tile_rect(grid_pos: Vector2i) -> Rect2:
	return Rect2(
		grid_pos.x * TILE_SIZE,
		grid_pos.y * TILE_SIZE,
		float(TILE_SIZE),
		float(TILE_SIZE)
	)

func _is_static_solid(grid_pos: Vector2i) -> bool:
	if wall_tilemap != null and wall_tilemap.get_cell_source_id(grid_pos) != -1:
		return true
	for door in get_tree().get_nodes_in_group("doors"):
		if not door.is_open and door.get_grid_pos() == grid_pos:
			return true
	for blocker in get_tree().get_nodes_in_group("lightning_blockers"):
		if blocker.get_grid_pos() == grid_pos:
			return true
	for door_block in get_tree().get_nodes_in_group("key_doors"):
		if door_block.get_grid_pos() == grid_pos:
			return true
	for panel in get_tree().get_nodes_in_group("teleport_panels"):
		if not panel.is_open and panel.get_grid_pos() == grid_pos:
			return true
	for screw in get_tree().get_nodes_in_group("screws"):
		if screw.get_grid_pos() == grid_pos:
			return true
	for wall in get_tree().get_nodes_in_group("breakable_walls"):
		if not wall._destroyed and wall.get_grid_pos() == grid_pos:
			return true
	for boss_door in get_tree().get_nodes_in_group("boss_doors"):
		if boss_door.get_grid_pos() == grid_pos:
			return true
	for dust in get_tree().get_nodes_in_group("dust_piles"):
		if not dust._destroyed and dust.get_grid_pos() == grid_pos:
			return true
	for turbine in get_tree().get_nodes_in_group("wind_turbines"):
		if turbine.get_grid_pos() == grid_pos:
			return true
	return false

func is_blocked(grid_pos: Vector2i) -> bool:
	if _is_static_solid(grid_pos):
		return true
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.grid_pos == grid_pos:
			return true
	return false

func get_player_blocking_rects(area: Rect2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var x0 := floori(area.position.x / TILE_SIZE)
	var x1 := floori((area.end.x - 0.001) / TILE_SIZE)
	var y0 := floori(area.position.y / TILE_SIZE)
	var y1 := floori((area.end.y - 0.001) / TILE_SIZE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var gp := Vector2i(x, y)
			if _is_static_solid(gp):
				rects.append(tile_rect(gp))
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var block_rect: Rect2 = block.get_collision_rect()
		if area.intersects(block_rect):
			rects.append(block_rect)
	return rects

func can_push_block_to(grid_pos: Vector2i) -> bool:
	if _is_static_solid(grid_pos):
		return false
	if get_push_block_at(grid_pos) != null:
		return false
	if has_pass_block_at(grid_pos):
		return false
	if pass_tilemap != null and pass_tilemap.get_cell_source_id(grid_pos) != -1:
		return false
	return true

func get_push_block_at_face(player_rect: Rect2, dir: Vector2i, from_point: Vector2) -> Node:
	const FACE_EPS := 0.1
	var closest: Node = null
	var closest_dist := INF
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var block_rect: Rect2 = block.get_collision_rect()
		if dir.x > 0:
			if absf(player_rect.end.x - block_rect.position.x) > FACE_EPS:
				continue
		elif dir.x < 0:
			if absf(player_rect.position.x - block_rect.end.x) > FACE_EPS:
				continue
		elif dir.y > 0:
			if absf(player_rect.end.y - block_rect.position.y) > FACE_EPS:
				continue
		elif absf(player_rect.position.y - block_rect.end.y) > FACE_EPS:
			continue
		var aligned := _rects_overlap_y(player_rect, block_rect) if dir.x != 0 else _rects_overlap_x(player_rect, block_rect)
		if not aligned:
			continue
		var dist := from_point.distance_squared_to(block_rect.get_center())
		if dist < closest_dist:
			closest_dist = dist
			closest = block
	return closest

func _rects_overlap_x(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x

func _rects_overlap_y(a: Rect2, b: Rect2) -> bool:
	return a.position.y < b.end.y and b.position.y < a.end.y

func has_pass_block_at(grid_pos: Vector2i) -> bool:
	for block in get_tree().get_nodes_in_group("pass_blocks"):
		if block.get_grid_pos() == grid_pos:
			return true
	return false

func get_push_block_at(grid_pos: Vector2i) -> Node:
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.grid_pos == grid_pos:
			return block
	return null

func check_room_transition(player_grid: Vector2i, player_pixel: Vector2 = Vector2.ZERO) -> void:
	var player_room := Vector2i(
		floori(float(player_grid.x) / ROOM_WIDTH),
		floori(float(player_grid.y) / ROOM_HEIGHT)
	)
	if player_room != current_room:
		if player_room.y > current_room.y:
			var boundary_y := (current_room.y + 1) * ROOM_HEIGHT * TILE_SIZE
			if player_pixel.y < boundary_y + 24.0:
				return
		if player_room.x > current_room.x:
			var boundary_x := (current_room.x + 1) * ROOM_WIDTH * TILE_SIZE
			if player_pixel.x < boundary_x + 24.0:
				return
		_transition_to_room(player_room)

func _transition_to_room(new_room: Vector2i) -> void:
	var direction := new_room - current_room
	room_entry_positions[new_room] = player.grid_pos + direction

	for p in GameManager.clear_prongs():
		p["node"].queue_free()
	_update_beam()

	# Delete boss-spawned enemies in the room being left
	var old_rx0 = current_room.x * ROOM_WIDTH
	var old_ry0 = current_room.y * ROOM_HEIGHT
	for enemy in get_tree().get_nodes_in_group("boss_spawned_enemies"):
		if not is_instance_valid(enemy):
			continue
		var egp = Vector2i(floori(enemy._start_pos.x / TILE_SIZE), floori(enemy._start_pos.y / TILE_SIZE))
		if egp.x >= old_rx0 and egp.x < old_rx0 + ROOM_WIDTH and egp.y >= old_ry0 and egp.y < old_ry0 + ROOM_HEIGHT:
			enemy.queue_free()

	current_room = new_room
	map_overlay.visit(current_room)

	var erx0 := current_room.x * ROOM_WIDTH
	var ery0 := current_room.y * ROOM_HEIGHT
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var egp := Vector2i(floori(enemy._start_pos.x / TILE_SIZE), floori(enemy._start_pos.y / TILE_SIZE))
		if egp.x >= erx0 and egp.x < erx0 + ROOM_WIDTH and egp.y >= ery0 and egp.y < ery0 + ROOM_HEIGHT:
			enemy.reset()

	var anchor := _get_anchor_for_room(new_room)
	if anchor != null and anchor.color != modulate:
		if _color_tween:
			_color_tween.kill()
		_color_tween = create_tween()
		_color_tween.tween_property(self, "modulate", anchor.color, CAMERA_TWEEN_DURATION)
		reset_effect.color = anchor.color
	if anchor != null and anchor.music != "":
		AudioManager.set_music(anchor.music)

	player.lock_movement()
	if _cam_tween:
		_cam_tween.kill()
	var target := _room_center(new_room)
	_cam_tween = create_tween()
	_cam_tween.set_ease(Tween.EASE_IN_OUT)
	_cam_tween.set_trans(Tween.TRANS_SINE)
	_cam_tween.tween_property(camera, "position", target, CAMERA_TWEEN_DURATION)
	_cam_tween.finished.connect(func(): player.unlock_movement())

func set_entry_position_from_anchor(room: Vector2i) -> void:
	var anchor := _get_anchor_for_room(room)
	if anchor != null:
		room_entry_positions[room] = Vector2i(floori(anchor.position.x / TILE_SIZE), floori(anchor.position.y / TILE_SIZE))

func _get_anchor_for_room(room: Vector2i) -> Node:
	var rx0 := room.x * ROOM_WIDTH
	var ry0 := room.y * ROOM_HEIGHT
	for anchor in get_tree().get_nodes_in_group("teleport_anchors"):
		var gp := Vector2i(floori(anchor.position.x / TILE_SIZE), floori(anchor.position.y / TILE_SIZE))
		if gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT:
			return anchor
	return null

func is_player_on_active_teleport_panel() -> bool:
	for panel in get_tree().get_nodes_in_group("teleport_panels"):
		if panel.is_player_standing_on(player):
			return true
	return false

func can_teleport_from_panel() -> bool:
	if not is_player_on_active_teleport_panel():
		return false
	var total_open := 0
	for panel in get_tree().get_nodes_in_group("teleport_panels"):
		if panel.is_open:
			total_open += 1
	if total_open < 2:
		return false
	return not get_open_teleport_panel_rooms().is_empty()

func get_open_teleport_panel_rooms() -> Array:
	var rooms: Array = []
	for panel in get_tree().get_nodes_in_group("teleport_panels"):
		if not panel.is_open or panel.one_way:
			continue
		var gp: Vector2i = panel.get_grid_pos()
		var room := Vector2i(floori(float(gp.x) / ROOM_WIDTH), floori(float(gp.y) / ROOM_HEIGHT))
		if not rooms.has(room):
			rooms.append(room)
	return rooms

func _get_open_panel_for_room(room: Vector2i) -> Node:
	var rx0 := room.x * ROOM_WIDTH
	var ry0 := room.y * ROOM_HEIGHT
	for panel in get_tree().get_nodes_in_group("teleport_panels"):
		if not panel.is_open:
			continue
		var gp: Vector2i = panel.get_grid_pos()
		if gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT:
			return panel
	return null

func _on_teleport_requested(room: Vector2i) -> void:
	reset_effect.play_teleport_buildup()
	# Defer so _close_map()'s player.unlock_movement() fires before we re-lock
	call_deferred("_complete_teleport", room)

func _complete_teleport(room: Vector2i) -> void:
	player.lock_movement()
	await get_tree().create_timer(0.4).timeout
	AudioManager.play_sfx("electric_spawn")

	var panel := _get_open_panel_for_room(room)
	var dest_gp: Vector2i
	if panel != null:
		dest_gp = panel.get_grid_pos()
		if is_blocked(dest_gp):
			dest_gp = _find_nearest_open_tile(dest_gp)
	else:
		var anchor := _get_anchor_for_room(room)
		if anchor == null:
			push_error("No teleport destination in room %s" % str(room))
			player.unlock_movement()
			reset_effect.cancel()
			return
		dest_gp = Vector2i(floori(anchor.position.x / TILE_SIZE), floori(anchor.position.y / TILE_SIZE))
		if is_blocked(dest_gp):
			dest_gp = _find_nearest_open_tile(dest_gp)

	player.reset_to(dest_gp)
	reset_effect.cancel()
	_transition_to_room(room)
	room_entry_positions[room] = dest_gp

func _find_nearest_open_tile(start: Vector2i) -> Vector2i:
	var visited := { start: true }
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current = queue.pop_front()
		if not is_blocked(current):
			return current
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n = current + d
			if not visited.has(n):
				visited[n] = true
				queue.append(n)
	return start

func _room_center(room: Vector2i) -> Vector2:
	return Vector2(
		WORLD_OFFSET + room.x * ROOM_PIXEL_WIDTH + ROOM_PIXEL_WIDTH / 2.0,
		WORLD_OFFSET + room.y * ROOM_PIXEL_HEIGHT + ROOM_PIXEL_HEIGHT / 2.0
	) + CAMERA_MARGIN

func spawn_prong(pixel_pos: Vector2) -> void:
	AudioManager.play_sfx("plant_stake")
	if GameManager.prongs.size() >= 2:
		var oldest = GameManager.prongs[0]
		GameManager.remove_prong(oldest["node"])
		var node: Node2D = oldest["node"]
		var tween := node.create_tween()
		tween.tween_method(node.apply_clear_shrink, 1.0, 0.0, 0.15)
		tween.tween_callback(node.queue_free)
	var prong := ProngScene.instantiate()
	wall_tilemap.add_child(prong)
	prong.setup(pixel_pos)
	GameManager.place_prong(prong, _world_to_grid(pixel_pos))
	_update_beam()
	_trigger_shake(5.0)

func _update_beam() -> void:
	var world_positions := GameManager.get_prong_world_positions()
	if world_positions.size() == 2:
		var path := _compute_beam_path(world_positions[0], world_positions[1])
		if path.is_empty():
			# No valid path — flash blockers on the direct line so the player sees what's in the way
			GameManager.beam_blocked = true
			GameManager.evaluate_puzzle()
			electric_beam.deactivate()
			var blocking := _get_beam_blockers(world_positions[0], world_positions[1])
			var flashing := _expand_connected_blockers(blocking)
			for b in get_tree().get_nodes_in_group("lightning_blockers"):
				b.set_blocking(b in flashing)
		else:
			GameManager.beam_blocked = false
			GameManager.evaluate_puzzle()
			electric_beam.activate(path)
			for b in get_tree().get_nodes_in_group("lightning_blockers"):
				b.set_blocking(false)
	else:
		GameManager.beam_blocked = false
		GameManager.evaluate_puzzle()
		electric_beam.deactivate()
		for b in get_tree().get_nodes_in_group("lightning_blockers"):
			b.set_blocking(false)

func _compute_beam_path(pos_a: Vector2, pos_b: Vector2) -> Array:
	var rx0 := current_room.x * ROOM_WIDTH
	var ry0 := current_room.y * ROOM_HEIGHT
	var nut_nodes: Array = []
	if GameManager.has_ability("chain"):
		for nut in get_tree().get_nodes_in_group("nuts"):
			var gp: Vector2i = nut.grid_pos
			if gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT:
				nut_nodes.append(nut)

	# Path stores Vector2 for prong endpoints and Node2D for nuts so ElectricBeam
	# can resolve nut positions each frame and follow the sliding sprite.
	return _nearest_first_beam(pos_a, pos_b, nut_nodes, [pos_a])

# Nearest-first DFS: at each hop, try candidates (nuts + target) sorted by distance
# from the current position, backtracking if a chosen nut leads to a dead end.
func _nearest_first_beam(current: Vector2, target: Vector2, remaining: Array, path: Array) -> Array:
	var candidates: Array = []

	if _get_beam_blockers(current, target).is_empty():
		candidates.append({"dist": current.distance_to(target), "is_target": true, "idx": -1})

	for i in range(remaining.size()):
		var nut_pos: Vector2 = remaining[i].get_beam_point()
		if _get_beam_blockers(current, nut_pos).is_empty():
			candidates.append({"dist": current.distance_to(nut_pos), "is_target": false, "idx": i})

	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])

	for c in candidates:
		if c["is_target"]:
			return path + [target]
		var i: int = c["idx"]
		var nut: Node2D = remaining[i]
		var nut_pos: Vector2 = nut.get_beam_point()
		var next_remaining := remaining.duplicate()
		next_remaining.remove_at(i)
		var result := _nearest_first_beam(nut_pos, target, next_remaining, path + [nut])
		if not result.is_empty():
			return result

	return []

func _expand_connected_blockers(seed: Array) -> Array:
	if seed.is_empty():
		return []
	var all_blockers := get_tree().get_nodes_in_group("lightning_blockers")
	var blocker_by_pos: Dictionary = {}
	for b in all_blockers:
		blocker_by_pos[b.get_grid_pos()] = b
	var result: Array = []
	var visited: Dictionary = {}
	var queue: Array = seed.duplicate()
	for b in queue:
		visited[b] = true
		result.append(b)
	while not queue.is_empty():
		var current = queue.pop_front()
		var gp: Vector2i = current.get_grid_pos()
		for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor_pos = gp + offset
			if blocker_by_pos.has(neighbor_pos):
				var neighbor = blocker_by_pos[neighbor_pos]
				if not visited.has(neighbor):
					visited[neighbor] = true
					result.append(neighbor)
					queue.append(neighbor)
	return result

func _get_beam_blockers(pos_a: Vector2, pos_b: Vector2) -> Array:
	var blocking: Array = []
	for b in get_tree().get_nodes_in_group("lightning_blockers"):
		var gp = b.get_grid_pos()
		var rect := Rect2(Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
		if _segment_intersects_rect(pos_a, pos_b, rect):
			blocking.append(b)
	return blocking

func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var c := [rect.position,
			  Vector2(rect.end.x, rect.position.y),
			  rect.end,
			  Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori((world_pos.x - WORLD_OFFSET) / TILE_SIZE),
		floori((world_pos.y - WORLD_OFFSET) / TILE_SIZE)
	)
