extends Node2D

# ──────────────────────────────────────────────
#  Constants
# ──────────────────────────────────────────────
const TILE_SIZE = 32
const ROOM_COLS = 25
const ROOM_ROWS = 12
const ROOM_W = ROOM_COLS * TILE_SIZE
const ROOM_H = ROOM_ROWS * TILE_SIZE
const WALL_SOURCE_ID = 1

const PLAY_COLS = ROOM_COLS - 1  # 0–23
const PLAY_ROWS = ROOM_ROWS - 1  # 0–10

const PlayerScene = preload("res://scenes/player/Player.tscn")
const ProngScene = preload("res://scenes/player/Prong.tscn")
const ElectricBeamScene = preload("res://scenes/player/ElectricBeam.tscn")

const SCENE_MAP = {
	"PushBlock":        "res://scenes/objects/PushBlock.tscn",
	"Nut":              "res://scenes/objects/Nut.tscn",
	"Screw":            "res://scenes/objects/Screw.tscn",
	"PassBlock":        "res://scenes/objects/PassBlock.tscn",
	"LightningBlocker": "res://scenes/objects/LightningBlocker.tscn",
	"Door":             "res://scenes/objects/Door.tscn",
	"FloorPanel":       "res://scenes/objects/FloorPanel.tscn",
	"FloorPanelNeg":    "res://scenes/objects/FloorPanel.tscn",
	"KeyDoor":          "res://scenes/objects/KeyDoor.tscn",
	"Key":              "res://scenes/objects/Key.tscn",
	"FanRight":         "res://scenes/objects/FanRight.tscn",
	"FanLeft":          "res://scenes/objects/FanLeft.tscn",
	"FanUp":            "res://scenes/objects/FanUp.tscn",
	"FanDown":          "res://scenes/objects/FanDown.tscn",
	"WindTurbine":      "res://scenes/objects/WindTurbine.tscn",
	"WindBlock":        "res://scenes/objects/WindBlock.tscn",
	"DustPile":         "res://scenes/objects/DustPile.tscn",
	"BreakableWall":    "res://scenes/objects/BreakableWall.tscn",
	"WaterEnemy":       "res://scenes/enemies/WaterEnemy.tscn",
	"BounceEnemy":      "res://scenes/enemies/BounceEnemy.tscn",
	"SpiderEnemy":      "res://scenes/enemies/SpiderEnemy.tscn",
}

const PALETTE_SPRITES = {
	"Wires":            "res://Sprites/ui/Circuit_Sprite_Sheet.webp",
	"Wall":             "res://Sprites/environment/wall1.png",
	"Player":           "res://Sprites/player/Spark_Front_Idle.webp",
	"PushBlock":        "res://Sprites/objects/SD_Card_block.png",
	"Nut":              "res://Sprites/objects/washer_block.png",
	"Screw":            "res://Sprites/objects/screw.png",
	"PassBlock":        "res://Sprites/objects/switch_open2.png",
	"LightningBlocker": "res://Sprites/objects/resistor_small.png",
	"Door":             "res://Sprites/objects/switch_closed.png",
	"FloorPanel":       "res://Sprites/objects/positive.png",
	"FloorPanelNeg":    "res://Sprites/objects/negative.png",
	"KeyDoor":          "res://Sprites/objects/locked_door1.png",
	"Key":              "res://Sprites/objects/Key_File.webp",
	"FanRight":         "res://Sprites/objects/Fan_Right.png",
	"FanLeft":          "res://Sprites/objects/Fan_Left.png",
	"FanUp":            "res://Sprites/objects/Fan_Back.png",
	"FanDown":          "res://Sprites/objects/Fan_Front.png",
	"WindTurbine":      "res://Sprites/objects/placeholder.png",
	"WindBlock":        "res://Sprites/objects/Dust_Pile.png",
	"DustPile":         "res://Sprites/objects/Dust_Pile_Alternate.png",
	"BreakableWall":    "res://Sprites/objects/wall_breakable.png",
	"KeyBreakableWall": "res://Sprites/objects/wall_breakable.png",
	"WaterEnemy":       "res://Sprites/enemies/Front_Idle1.png",
	"BounceEnemy":      "res://Sprites/enemies/Front_Idle1.png",
	"SpiderEnemy":      "res://Sprites/enemies/Front_Idle1.png",
}

# ──────────────────────────────────────────────
#  Enums
# ──────────────────────────────────────────────
enum Mode { BUILD, PLACING, PLAY }

# ──────────────────────────────────────────────
#  Node refs
# ──────────────────────────────────────────────
@onready var camera: Camera2D                  = $Camera2D
@onready var border_walls_tilemap: TileMapLayer = $EditorRoom/BorderWalls
@onready var walls_tilemap: TileMapLayer        = $EditorRoom/Walls
@onready var floor_tilemap: TileMapLayer        = $EditorRoom/FloorLayer
@onready var y_sort_root: Node2D               = $EditorRoom/YSortRoot
@onready var ghost_sprite: Sprite2D            = $EditorRoom/GhostSprite
@onready var player_marker: Sprite2D           = $EditorRoom/PlayerMarker
@onready var grid_overlay: Node2D              = $GridOverlay
@onready var top_bar: HBoxContainer            = $EditorUI/TopBar
@onready var palette_panel: PanelContainer     = $EditorUI/Palette
@onready var palette_list: GridContainer       = $EditorUI/Palette/List
@onready var props_panel: PanelContainer       = $EditorUI/PropertiesPanel
@onready var props_list: VBoxContainer         = $EditorUI/PropertiesPanel/List
@onready var toast_label: Label                = $EditorUI/Toast
@onready var placing_hint: Label               = $EditorUI/PlacingHint

# ──────────────────────────────────────────────
#  State
# ──────────────────────────────────────────────
var mode: int = Mode.BUILD
var selected_type: String = "Wires"
var selected_object: Node = null
var placing_wall: bool = false
var _palette_buttons: Dictionary = {}

var placed_objects: Array = []
var player_spawn_pos: Vector2i = Vector2i(-1, -1)

# Drag placement
var _drag_placing: bool = false
var _drag_deleting: bool = false
var _drag_visited: Array = []

# Floor tile batching — grows during drag, flushed on release
var _floor_paint_batch: Array[Vector2i] = []
var _floor_erase_batch: Array[Vector2i] = []

# Ghost sprite caching
var _ghost_tex_type: String = ""

var _toast_tween: Tween = null

# Play mode state
var _play_player: Node = null
var _play_beam: Node = null
var _play_spawn_pos: Vector2i = Vector2i(2, 2)
var _play_label: Label = null
var _play_auto_save_data: Dictionary = {}

var _music_btn: Button

# ──────────────────────────────────────────────
#  Wire mode
# ──────────────────────────────────────────────
const WIRE_BASE_COLORS = [
	Color(0.25, 0.50, 1.00),  # BLUE   → id1
	Color(1.00, 0.30, 0.30),  # RED    → id2
	Color(0.20, 0.85, 0.25),  # GREEN  → id3
	Color(1.00, 0.85, 0.10),  # YELLOW → id4
]
var _wire_mode: bool = false
var _wire_color_index: int = 0
var _wire_assignments: Dictionary = {}  # Node → int (color index)

func _setup_mute_button() -> void:
	var editor_ui := $EditorUI as CanvasLayer
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", 2)
	editor_ui.add_child(row)

	_music_btn = Button.new()
	_music_btn.text = "♪"
	_music_btn.focus_mode = Control.FOCUS_NONE
	_music_btn.add_theme_font_size_override("font_size", 9)
	var sn = _make_btn_style(Color.BLACK, Color.WHITE)
	var sh = _make_btn_style(Color.WHITE, Color.WHITE)
	_music_btn.add_theme_stylebox_override("normal", sn)
	_music_btn.add_theme_stylebox_override("hover", sh)
	_music_btn.add_theme_stylebox_override("pressed", sn)
	_music_btn.add_theme_stylebox_override("focus", sn)
	_music_btn.add_theme_color_override("font_color", Color.WHITE)
	_music_btn.add_theme_color_override("font_hover_color", Color.BLACK)
	_music_btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	_music_btn.add_theme_color_override("font_focus_color", Color.WHITE)
	_music_btn.pressed.connect(_on_music_mute_pressed)
	row.add_child(_music_btn)
	_update_music_btn()

func _make_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(1)
	return s

func _update_music_btn() -> void:
	if _music_btn == null:
		return
	_music_btn.modulate = Color(0.35, 0.35, 0.35) if AudioManager.is_music_muted() else Color.WHITE

func _on_music_mute_pressed() -> void:
	AudioManager.toggle_music_mute()
	_update_music_btn()

func _setup_play_label() -> void:
	var editor_ui = $EditorUI as CanvasLayer
	_play_label = Label.new()
	_play_label.text = "E: Wire    Q: Play"
	_play_label.add_theme_color_override("font_color", Color.WHITE)
	_play_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_play_label.add_theme_constant_override("outline_size", 2)
	_play_label.add_theme_font_size_override("font_size", 12)
	_play_label.anchor_left = 1.0
	_play_label.anchor_right = 1.0
	_play_label.anchor_top = 1.0
	_play_label.anchor_bottom = 1.0
	_play_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_play_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_play_label.offset_left = -160
	_play_label.offset_right = -8
	_play_label.offset_top = -26
	_play_label.offset_bottom = -8
	editor_ui.add_child(_play_label)

func _ready() -> void:
	AudioManager.set_music("LevelEditor")
	_setup_mute_button()
	camera.position = Vector2(ROOM_W / 2.0, ROOM_H / 2.0)
	camera.offset = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)

	ghost_sprite.centered = false
	ghost_sprite.visible = false
	ghost_sprite.z_index = 20
	ghost_sprite.modulate = Color(1, 1, 1, 0.45)

	player_marker.centered = false
	player_marker.visible = false
	player_marker.z_index = 15
	player_marker.texture = _first_frame_texture(PALETTE_SPRITES["Player"])
	var pt = player_marker.texture
	if pt:
		player_marker.scale = Vector2(TILE_SIZE / float(pt.get_width()), TILE_SIZE / float(pt.get_height()))

	grid_overlay.draw.connect(_draw_grid)
	grid_overlay.draw.connect(_draw_wire_overlay)

	$EditorUI/TopBar/ExitButton.pressed.connect(_on_exit_pressed)
	$EditorUI/TopBar/SaveButton.pressed.connect(_on_save_pressed)
	$EditorUI/TopBar/LoadButton.pressed.connect(_on_load_pressed)
	$EditorUI/TopBar/ExportButton.pressed.connect(_on_export_pressed)
	$EditorUI/TopBar/ImportButton.pressed.connect(_on_import_pressed)

	_build_palette()
	toast_label.visible = false
	placing_hint.visible = false
	_setup_play_label()

	_place_border_walls()
	_set_mode(Mode.BUILD)

func _place_border_walls() -> void:
	for col in range(-1, ROOM_COLS):
		border_walls_tilemap.set_cell(Vector2i(col, -1), WALL_SOURCE_ID, Vector2i(0, 0))
		border_walls_tilemap.set_cell(Vector2i(col, ROOM_ROWS - 1), WALL_SOURCE_ID, Vector2i(0, 0))
	for row in range(0, ROOM_ROWS - 1):
		border_walls_tilemap.set_cell(Vector2i(-1, row), WALL_SOURCE_ID, Vector2i(0, 0))
		border_walls_tilemap.set_cell(Vector2i(ROOM_COLS - 1, row), WALL_SOURCE_ID, Vector2i(0, 0))

# ──────────────────────────────────────────────
#  Palette
# ──────────────────────────────────────────────
func _first_frame_texture(path: String) -> Texture2D:
	var tex = load(path) as Texture2D
	if tex == null: return null
	if tex.get_width() <= 32 and tex.get_height() <= 32:
		return tex
	var atlas = AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, 0, 32, 32)
	return atlas

func _build_palette() -> void:
	for child in palette_list.get_children():
		child.queue_free()
	_palette_buttons.clear()

	var scene_keys = SCENE_MAP.keys()
	var bw_idx = scene_keys.find("BreakableWall")
	if bw_idx >= 0:
		scene_keys.insert(bw_idx + 1, "KeyBreakableWall")
	else:
		scene_keys.append("KeyBreakableWall")
	var types = ["Wires", "Wall", "Player"] + scene_keys
	palette_list.columns = 22

	for t in types:
		if t == "KeyBreakableWall":
			var container = Button.new()
			container.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			container.tooltip_text = t
			container.flat = false
			container.pressed.connect(func(): _select_type(t))
			var wall_rect = TextureRect.new()
			wall_rect.texture = _first_frame_texture("res://Sprites/objects/wall_breakable.png")
			wall_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			wall_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			wall_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			wall_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var key_rect = TextureRect.new()
			key_rect.texture = _first_frame_texture("res://Sprites/objects/Key_File.webp")
			key_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			key_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			key_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			key_rect.modulate = Color(1, 1, 1, 0.5)
			key_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(wall_rect)
			container.add_child(key_rect)
			palette_list.add_child(container)
			_palette_buttons[t] = container
		else:
			var btn = TextureButton.new()
			btn.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			if PALETTE_SPRITES.has(t):
				btn.texture_normal = _first_frame_texture(PALETTE_SPRITES[t])
			btn.tooltip_text = t
			btn.pressed.connect(func(): _select_type(t))
			palette_list.add_child(btn)
			_palette_buttons[t] = btn

	_highlight_palette(selected_type)

func _select_type(t: String) -> void:
	selected_type = t
	placing_wall = (t == "Wall")
	_highlight_palette(t)
	_apply_floor_fade(t == "Wires")
	_set_mode(Mode.PLACING)

func _highlight_palette(t: String) -> void:
	for type in _palette_buttons:
		var btn = _palette_buttons[type]
		var tint = Color(0.4, 0.85, 1.0) if type == t else Color(1, 1, 1)
		if type == "KeyBreakableWall":
			# Only tint the wall layer; key layer keeps its 50% alpha
			if btn.get_child_count() > 0:
				btn.get_child(0).modulate = tint
		else:
			btn.modulate = tint

func _apply_floor_fade(active: bool) -> void:
	var alpha = 0.2 if active else 1.0
	walls_tilemap.modulate.a = alpha
	y_sort_root.modulate.a = alpha
	player_marker.modulate.a = alpha
	# border_walls_tilemap stays at 1.0 always

# ──────────────────────────────────────────────
#  Mode switching
# ──────────────────────────────────────────────
func _set_mode(new_mode: int) -> void:
	mode = new_mode

	top_bar.visible = false
	palette_panel.visible = false
	props_panel.visible = false
	placing_hint.visible = false
	ghost_sprite.visible = false
	_drag_placing = false
	_drag_deleting = false
	_floor_paint_batch.clear()
	_floor_erase_batch.clear()

	match mode:
		Mode.BUILD:
			top_bar.visible = true
			palette_panel.visible = true
			props_panel.visible = selected_object != null
			_apply_floor_fade(false)
			_restore_objects()
			if _play_label:
				_play_label.text = "E: Wire    Q: Play"

		Mode.PLACING:
			placing_hint.text = "Space: Select Object"
			placing_hint.visible = true
			if _play_label:
				_play_label.text = "E: Wire    Q: Play"

		Mode.PLAY:
			_wire_mode = false
			if _play_label:
				_play_label.text = "Q: Edit"

# ──────────────────────────────────────────────
#  Process — ghost sprite update
# ──────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _web_waiting_upload:
		var content = JavaScriptBridge.eval("window._godotUploadContent")
		if typeof(content) == TYPE_STRING:
			_web_waiting_upload = false
			JavaScriptBridge.eval("window._godotUploadContent = undefined;")
			var data = JSON.parse_string(content)
			if data != null:
				_apply_level_data(data)
			else:
				_show_toast("Invalid level file!")

	if _wire_mode and mode != Mode.PLAY:
		grid_overlay.queue_redraw()

	if mode != Mode.PLACING:
		ghost_sprite.visible = false
		return

	var world_pos = get_global_mouse_position()
	var gp = world_to_grid(world_pos)
	var in_bounds = gp.x >= -1 and gp.x < ROOM_COLS and gp.y >= -1 and gp.y < ROOM_ROWS
	ghost_sprite.visible = in_bounds and selected_type != "Wires"

	if in_bounds:
		ghost_sprite.position = grid_to_world(gp)

		if _ghost_tex_type != selected_type:
			_ghost_tex_type = selected_type
			var tex_path = PALETTE_SPRITES.get(selected_type, "")
			if tex_path != "":
				var raw_tex = load(tex_path) as Texture2D
				var gw = raw_tex.get_width()
				var gh = raw_tex.get_height()
				if gw > 32 or gh > 32:
					ghost_sprite.region_enabled = true
					ghost_sprite.region_rect = Rect2(0, 0, 32, 32)
					ghost_sprite.texture = raw_tex
					ghost_sprite.scale = Vector2.ONE
				else:
					ghost_sprite.region_enabled = false
					ghost_sprite.texture = raw_tex
					ghost_sprite.scale = Vector2(TILE_SIZE / float(gw), TILE_SIZE / float(gh))
			else:
				ghost_sprite.texture = null

	if _drag_placing or _drag_deleting:
		_handle_drag_at(gp)

# ──────────────────────────────────────────────
#  Input
# ──────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_Q:
			if mode == Mode.PLAY:
				_exit_play_mode()
			else:
				_enter_play_mode()
			get_viewport().set_input_as_handled()
		KEY_R:
			if mode == Mode.PLAY:
				_reset_room()
				get_viewport().set_input_as_handled()
		KEY_E:
			if mode != Mode.PLAY:
				_toggle_wire_mode()
				get_viewport().set_input_as_handled()
		KEY_SPACE:
			if mode != Mode.PLAY:
				if _wire_mode:
					_cycle_wire_color()
				else:
					_set_mode(Mode.BUILD)
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if mode != Mode.PLAY:
				if _wire_mode:
					_toggle_wire_mode()
				else:
					_set_mode(Mode.BUILD)
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.PLAY:
		return
	if not (event is InputEventMouseButton):
		return

	var mb = event as InputEventMouseButton

	if _wire_mode:
		var gp = world_to_grid(get_global_mouse_position())
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var obj = _object_at(gp)
			if obj != null and obj.get("id") != null:
				_wire_assignments[obj] = _wire_color_index
				grid_overlay.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var obj = _object_at(gp)
			if obj != null and _wire_assignments.has(obj):
				_wire_assignments.erase(obj)
				grid_overlay.queue_redraw()
		return

	if mode == Mode.PLACING:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_placing = true
				_drag_visited.clear()
			else:
				_drag_placing = false
				_flush_floor_batches()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_drag_deleting = true
			else:
				_drag_deleting = false
				_flush_floor_batches()

	match mode:
		Mode.BUILD:
			_handle_build_click(mb)
		Mode.PLACING:
			if mb.pressed:
				var gp = world_to_grid(get_global_mouse_position())
				_handle_drag_at(gp)

func _flush_floor_batches() -> void:
	if _floor_paint_batch.size() > 0:
		floor_tilemap.set_cells_terrain_connect(_floor_paint_batch, 0, 0)
		_floor_paint_batch.clear()
	if _floor_erase_batch.size() > 0:
		floor_tilemap.set_cells_terrain_connect(_floor_erase_batch, 0, -1)
		_floor_erase_batch.clear()

func _handle_drag_at(gp: Vector2i) -> void:
	# Floor tiles: accumulate batch and call terrain connect incrementally
	if selected_type == "Wires":
		if gp.x >= 0 and gp.x < PLAY_COLS and gp.y >= 0 and gp.y < PLAY_ROWS:
			if _drag_placing and not (gp in _floor_paint_batch):
				_floor_paint_batch.append(gp)
				# Use ALL existing cells + new cell so neighbors outside the current drag are considered
				var all_cells: Array[Vector2i] = floor_tilemap.get_used_cells()
				if not (gp in all_cells):
					all_cells.append(gp)
				floor_tilemap.set_cells_terrain_connect(all_cells, 0, 0)
				# match_sides needs neighbors; if isolated cell got no tile, force a fallback
				if floor_tilemap.get_cell_source_id(gp) == -1:
					floor_tilemap.set_cell(gp, 0, Vector2i(2, 0))
			elif _drag_deleting and not (gp in _floor_erase_batch):
				_floor_erase_batch.append(gp)
				floor_tilemap.set_cells_terrain_connect(_floor_erase_batch, 0, -1)
		return

	if _drag_placing:
		if gp in _drag_visited:
			return
		_drag_visited.append(gp)
		if placing_wall:
			_place_wall(gp)
		else:
			_place_object(selected_type, gp)
	elif _drag_deleting:
		if placing_wall:
			walls_tilemap.erase_cell(gp)
		else:
			var existing = _object_at(gp)
			if existing:
				_delete_object(existing)
			if selected_type == "Player" and player_spawn_pos == gp:
				player_spawn_pos = Vector2i(-1, -1)
				player_marker.visible = false

func _handle_build_click(mb: InputEventMouseButton) -> void:
	var world_pos = get_global_mouse_position()
	var gp = world_to_grid(world_pos)
	if gp.x < 0 or gp.x >= ROOM_COLS or gp.y < 0 or gp.y >= ROOM_ROWS:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if placing_wall:
			_place_wall(gp)
		else:
			var existing = _object_at(gp)
			if existing:
				_select_object(existing)
			else:
				_place_object(selected_type, gp)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if placing_wall:
			walls_tilemap.erase_cell(gp)
		else:
			var existing = _object_at(gp)
			if existing:
				_delete_object(existing)
			if player_spawn_pos == gp:
				player_spawn_pos = Vector2i(-1, -1)
				player_marker.visible = false

# ──────────────────────────────────────────────
#  Object / tile placement
# ──────────────────────────────────────────────
func world_to_grid(wp: Vector2) -> Vector2i:
	return Vector2i(floori(wp.x / TILE_SIZE), floori(wp.y / TILE_SIZE))

func grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)

func _object_at(gp: Vector2i) -> Node:
	# Returns the last-added (top-most) object at this grid position
	var result: Node = null
	for entry in placed_objects:
		if entry.col == gp.x and entry.row == gp.y:
			result = entry.node
	return result

func _type_of(node: Node) -> String:
	for entry in placed_objects:
		if entry.node == node: return entry.type
	return ""

func _place_wall(gp: Vector2i) -> void:
	if gp.x < -1 or gp.x >= ROOM_COLS or gp.y < -1 or gp.y >= ROOM_ROWS:
		return
	walls_tilemap.set_cell(gp, WALL_SOURCE_ID, Vector2i(0, 0))

func _place_object(type: String, gp: Vector2i) -> void:
	if type == "Player":
		if gp.x < 0 or gp.x >= PLAY_COLS or gp.y < 0 or gp.y >= PLAY_ROWS:
			return
		player_spawn_pos = gp
		player_marker.position = grid_to_world(gp)
		player_marker.visible = true
		return

	if type == "KeyBreakableWall":
		_place_object("BreakableWall", gp)
		_place_object("Key", gp)
		return

	if gp.x < 0 or gp.x >= PLAY_COLS or gp.y < 0 or gp.y >= PLAY_ROWS:
		return
	if not SCENE_MAP.has(type):
		return

	var existing = _object_at(gp)
	if existing != null:
		# Only allow Key on top of BreakableWall
		if not (type == "Key" and _type_of(existing) == "BreakableWall"):
			return

	var inst = load(SCENE_MAP[type]).instantiate()
	inst.position = grid_to_world(gp)

	if type == "FloorPanelNeg" and inst.get("positive") != null:
		inst.positive = false

	y_sort_root.add_child(inst)

	# Must be after add_child: Key._ready() resets z_index to -5
	if type == "Key" and existing != null:
		inst.modulate.a = 0.5
		inst.z_index = 5

	# KeyDoor._count_keys() is deferred; pre-set _keys_total=1 so it never
	# auto-opens when placed with no keys present in the editor
	if type == "KeyDoor":
		inst._keys_total = 1

	placed_objects.append({ "node": inst, "type": type, "col": gp.x, "row": gp.y })

func _delete_object(node: Node) -> void:
	_wire_assignments.erase(node)
	for i in range(placed_objects.size() - 1, -1, -1):
		if placed_objects[i].node == node:
			placed_objects.remove_at(i)
			break
	if selected_object == node:
		selected_object = null
		props_panel.visible = false
	node.queue_free()

# ──────────────────────────────────────────────
#  Selection & properties panel
# ──────────────────────────────────────────────
func _select_object(node: Node) -> void:
	selected_object = node
	if mode == Mode.BUILD:
		props_panel.visible = true
		_rebuild_props()

func _rebuild_props() -> void:
	for child in props_list.get_children():
		child.queue_free()
	if selected_object == null:
		return
	var type = ""
	for entry in placed_objects:
		if entry.node == selected_object:
			type = entry.type
			break
	_add_prop_label("Type: " + type)
	if selected_object.get("id") != null:
		_add_prop_field("id", selected_object.id, func(v): selected_object.id = v)
	if selected_object.get("id2") != null:
		_add_prop_field("id2", selected_object.id2, func(v): selected_object.id2 = v)
	if selected_object.get("positive") != null:
		_add_prop_check("positive", selected_object.positive, func(v): selected_object.positive = v)

func _add_prop_label(text: String) -> void:
	var lbl = Label.new(); lbl.text = text; props_list.add_child(lbl)

func _add_prop_field(name: String, value: String, on_change: Callable) -> void:
	var hbox = HBoxContainer.new()
	var lbl = Label.new(); lbl.text = name + ":"; lbl.custom_minimum_size = Vector2(60, 0)
	var edit = LineEdit.new(); edit.text = value; edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(on_change)
	hbox.add_child(lbl); hbox.add_child(edit); props_list.add_child(hbox)

func _add_prop_check(name: String, value: bool, on_change: Callable) -> void:
	var check = CheckBox.new(); check.text = name; check.button_pressed = value
	check.toggled.connect(on_change); props_list.add_child(check)

# ──────────────────────────────────────────────
#  Draw callbacks
# ──────────────────────────────────────────────
func _draw_grid() -> void:
	var grid_color = Color(1, 1, 1, 0.08)
	var border_color = Color(1, 1, 1, 0.3)
	for col in range(ROOM_COLS + 1):
		grid_overlay.draw_line(Vector2(col * TILE_SIZE, 0), Vector2(col * TILE_SIZE, ROOM_H), grid_color)
	for row in range(ROOM_ROWS + 1):
		grid_overlay.draw_line(Vector2(0, row * TILE_SIZE), Vector2(ROOM_W, row * TILE_SIZE), grid_color)
	grid_overlay.draw_rect(Rect2(0, 0, ROOM_W, ROOM_H), border_color, false, 2.0)

# ──────────────────────────────────────────────
#  Object reset
# ──────────────────────────────────────────────
func _restore_objects() -> void:
	for entry in placed_objects:
		var node = entry.node
		if node.has_method("reset"):
			node.reset()
		else:
			node.position = grid_to_world(Vector2i(entry.col, entry.row))
		# Restore Key-on-BreakableWall transparency
		if entry.type == "Key":
			var others = []
			for e in placed_objects:
				if e.col == entry.col and e.row == entry.row and e.node != node:
					others.append(e)
			if others.size() > 0:
				node.modulate.a = 0.5
				node.z_index = 5
			else:
				node.modulate.a = 1.0

# ──────────────────────────────────────────────
#  Save / Load
# ──────────────────────────────────────────────
var _web_waiting_upload: bool = false

func _build_level_data() -> Dictionary:
	var data = { "walls": [], "objects": [], "floor": [] }
	if player_spawn_pos != Vector2i(-1, -1):
		data["player_spawn"] = { "col": player_spawn_pos.x, "row": player_spawn_pos.y }
	for cell in walls_tilemap.get_used_cells():
		var src = walls_tilemap.get_cell_source_id(cell)
		var atlas = walls_tilemap.get_cell_atlas_coords(cell)
		data.walls.append({ "col": cell.x, "row": cell.y, "source_id": src, "atlas_x": atlas.x, "atlas_y": atlas.y })
	for cell in floor_tilemap.get_used_cells():
		data.floor.append({ "col": cell.x, "row": cell.y })
	for entry in placed_objects:
		var node = entry.node
		var obj = { "type": entry.type, "col": entry.col, "row": entry.row }
		if node.get("id") != null: obj["id"] = node.id
		if node.get("id2") != null: obj["id2"] = node.id2
		if node.get("positive") != null: obj["positive"] = node.positive
		data.objects.append(obj)
	var wire_data = {}
	for node in _wire_assignments:
		if is_instance_valid(node):
			for entry in placed_objects:
				if entry.node == node:
					wire_data[str(entry.col) + "," + str(entry.row)] = _wire_assignments[node]
					break
	data["wire_assignments"] = wire_data
	return data

func _apply_level_data(data: Dictionary) -> void:
	for entry in placed_objects:
		entry.node.queue_free()
	placed_objects.clear()
	walls_tilemap.clear()
	floor_tilemap.clear()
	player_spawn_pos = Vector2i(-1, -1)
	player_marker.visible = false
	selected_object = null
	props_panel.visible = false

	if data.has("player_spawn"):
		player_spawn_pos = Vector2i(data.player_spawn.col, data.player_spawn.row)
		player_marker.position = grid_to_world(player_spawn_pos)
		player_marker.visible = true

	if data.has("walls"):
		for w in data.walls:
			walls_tilemap.set_cell(Vector2i(w.col, w.row), w.source_id, Vector2i(w.atlas_x, w.atlas_y))

	if data.has("floor"):
		var cells: Array[Vector2i] = []
		for f in data.floor:
			cells.append(Vector2i(f.col, f.row))
		if cells.size() > 0:
			floor_tilemap.set_cells_terrain_connect(cells, 0, 0)

	if data.has("objects"):
		for obj in data.objects:
			if not SCENE_MAP.has(obj.type):
				continue
			var inst = load(SCENE_MAP[obj.type]).instantiate()
			inst.position = grid_to_world(Vector2i(obj.col, obj.row))
			if obj.type == "FloorPanelNeg" and inst.get("positive") != null:
				inst.positive = false
			if inst.get("id") != null and obj.has("id"): inst.id = obj.id
			if inst.get("id2") != null and obj.has("id2"): inst.id2 = obj.id2
			if inst.get("positive") != null and obj.has("positive"): inst.positive = obj.positive
			y_sort_root.add_child(inst)
			placed_objects.append({ "node": inst, "type": obj.type, "col": obj.col, "row": obj.row })

	# Restore Key-on-BreakableWall visuals (must be after add_child so _ready has run)
	for entry in placed_objects:
		if entry.type == "Key":
			for other in placed_objects:
				if other.col == entry.col and other.row == entry.row and other.node != entry.node:
					entry.node.modulate.a = 0.5
					entry.node.z_index = 5
					break

	_wire_assignments.clear()
	if data.has("wire_assignments"):
		for key in data["wire_assignments"]:
			var parts = (key as String).split(",")
			var col = int(parts[0])
			var row = int(parts[1])
			for entry in placed_objects:
				if entry.col == col and entry.row == row and entry.node.get("id") != null:
					_wire_assignments[entry.node] = data["wire_assignments"][key]
					break

	_show_toast("Loaded!")

func _save_level(filename: String) -> void:
	var json_str = JSON.stringify(_build_level_data(), "\t")
	if OS.get_name() == "Web":
		_web_download(filename + ".json", json_str)
		_show_toast("Downloaded: " + filename)
	else:
		DirAccess.make_dir_recursive_absolute("user://levels")
		var file = FileAccess.open("user://levels/" + filename + ".json", FileAccess.WRITE)
		if file:
			file.store_string(json_str)
			file.close()
			_show_toast("Saved: " + filename)
		else:
			_show_toast("Save failed!")

func _load_level(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		_show_toast("Load failed!")
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null:
		_show_toast("Invalid level file!")
		return
	_apply_level_data(data)

func _web_download(filename: String, content: String) -> void:
	# Escape backticks and backslashes so the content is safe inside a JS template literal
	var safe = content.replace("\\", "\\\\").replace("`", "\\`").replace("$", "\\$")
	JavaScriptBridge.eval("""
(function() {
	var data = `""" + safe + """`;
	var blob = new Blob([data], {type: 'application/json'});
	var url = URL.createObjectURL(blob);
	var a = document.createElement('a');
	a.href = url; a.download = '""" + filename + """';
	document.body.appendChild(a); a.click();
	document.body.removeChild(a); URL.revokeObjectURL(url);
})();
""")

func _web_upload() -> void:
	_web_waiting_upload = true
	JavaScriptBridge.eval("""
(function() {
	window._godotUploadContent = undefined;
	var input = document.createElement('input');
	input.type = 'file'; input.accept = '.json';
	input.onchange = function(e) {
		var reader = new FileReader();
		reader.onload = function(ev) { window._godotUploadContent = ev.target.result; };
		reader.readAsText(e.target.files[0]);
	};
	document.body.appendChild(input); input.click(); document.body.removeChild(input);
})();
""")

# ──────────────────────────────────────────────
#  UI helpers
# ──────────────────────────────────────────────
func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.visible = true
	if _toast_tween: _toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): toast_label.visible = false; toast_label.modulate.a = 1.0)

func _on_exit_pressed() -> void:
	SaveManager.load_quicksave()

func _make_dialog_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	return lbl

func _on_save_pressed() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Save Level"
	var vbox = VBoxContainer.new()
	var edit = LineEdit.new()
	edit.text = "my_level"
	vbox.add_child(_make_dialog_label("Level name:"))
	vbox.add_child(edit)
	dialog.add_child(vbox)
	dialog.get_ok_button().text = "Save"
	add_child(dialog)
	dialog.popup_centered(Vector2(300, 120))
	await dialog.confirmed
	var fname = edit.text.strip_edges()
	if fname != "":
		_save_level(fname)
	dialog.queue_free()

func _on_load_pressed() -> void:
	if OS.get_name() == "Web":
		_web_upload()
		return
	var dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.current_dir = "user://levels"
	dialog.filters = ["*.json ; Level Files"]
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Load Level"
	add_child(dialog)
	dialog.popup_centered(Vector2(600, 400))
	var selected = await dialog.file_selected
	if selected != "":
		_load_level(selected)
	dialog.queue_free()

func _encode_level_data(data: Dictionary) -> String:
	var json_str = JSON.stringify(data)
	var bytes = json_str.to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(compressed)

func _decode_level_string(encoded: String) -> Dictionary:
	var compressed = Marshalls.base64_to_raw(encoded)
	var decompressed = compressed.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	if decompressed.size() == 0:
		return {}
	var data = JSON.parse_string(decompressed.get_string_from_utf8())
	if data == null:
		return {}
	return data

func _on_export_pressed() -> void:
	var data = _build_level_data()
	if OS.get_name() != "Web":
		_save_level("export")
	var encoded = _encode_level_data(data)

	var dialog = AcceptDialog.new()
	dialog.title = "Export Level"
	var vbox = VBoxContainer.new()
	var edit = TextEdit.new()
	edit.text = encoded
	edit.custom_minimum_size = Vector2(480, 140)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_make_dialog_label("Copy this export code:"))
	vbox.add_child(edit)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered(Vector2(520, 220))
	edit.select_all()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _on_import_pressed() -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Import Level"
	var vbox = VBoxContainer.new()
	var edit = TextEdit.new()
	edit.custom_minimum_size = Vector2(480, 140)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_make_dialog_label("Paste export code:"))
	vbox.add_child(edit)
	dialog.add_child(vbox)
	dialog.get_ok_button().text = "Import"
	add_child(dialog)
	dialog.popup_centered(Vector2(520, 220))
	await dialog.confirmed
	var encoded = edit.text.strip_edges()
	dialog.queue_free()
	if encoded == "":
		return
	var data = _decode_level_string(encoded)
	if data.is_empty():
		_show_toast("Invalid export code!")
		return
	_apply_level_data(data)

# ──────────────────────────────────────────────
#  Player compatibility interface
# ──────────────────────────────────────────────
var current_room: Vector2i = Vector2i(0, 0)

func tile_rect(gp: Vector2i) -> Rect2:
	return Rect2(gp.x * TILE_SIZE, gp.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)

func _is_static_solid(gp: Vector2i) -> bool:
	if walls_tilemap == null: return false
	if walls_tilemap.get_cell_source_id(gp) >= 0 or border_walls_tilemap.get_cell_source_id(gp) >= 0:
		return true
	for door in get_tree().get_nodes_in_group("doors"):
		if not door.is_open and door.get_grid_pos() == gp:
			return true
	for door in get_tree().get_nodes_in_group("key_doors"):
		if door.get_grid_pos() == gp:
			return true
	for blocker in get_tree().get_nodes_in_group("lightning_blockers"):
		if blocker.get_grid_pos() == gp:
			return true
	for screw in get_tree().get_nodes_in_group("screws"):
		if screw.get_grid_pos() == gp:
			return true
	for wall in get_tree().get_nodes_in_group("breakable_walls"):
		if not wall._destroyed and wall.get_grid_pos() == gp:
			return true
	for dust in get_tree().get_nodes_in_group("dust_piles"):
		if not dust._destroyed and dust.get_grid_pos() == gp:
			return true
	for turbine in get_tree().get_nodes_in_group("wind_turbines"):
		if turbine.get_grid_pos() == gp:
			return true
	for edoor in get_tree().get_nodes_in_group("enemy_doors"):
		if not edoor.is_open and edoor.get_grid_pos() == gp:
			return true
	return false

func get_player_blocking_rects(area: Rect2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var x0 = floori(area.position.x / TILE_SIZE)
	var x1 = floori((area.end.x - 0.001) / TILE_SIZE)
	var y0 = floori(area.position.y / TILE_SIZE)
	var y1 = floori((area.end.y - 0.001) / TILE_SIZE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _is_static_solid(Vector2i(x, y)):
				rects.append(tile_rect(Vector2i(x, y)))
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.has_method("get_collision_rect"):
			var br: Rect2 = block.get_collision_rect()
			if area.intersects(br): rects.append(br)
	return rects

func has_pass_block_at(gp: Vector2i) -> bool:
	for block in get_tree().get_nodes_in_group("pass_blocks"):
		if block.get_grid_pos() == gp:
			return true
	return false

func is_blocked(gp: Vector2i) -> bool:
	if _is_static_solid(gp):
		return true
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.grid_pos == gp:
			return true
	return false

func can_push_block_to(gp: Vector2i) -> bool:
	return not _is_static_solid(gp) and get_push_block_at(gp) == null and not has_pass_block_at(gp)

func get_push_block_at(gp: Vector2i) -> Node:
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.grid_pos == gp: return block
	return null

func get_push_block_at_face(player_rect: Rect2, dir: Vector2i, from_point: Vector2) -> Node:
	const FACE_EPS = 0.1
	var closest: Node = null
	var closest_dist = INF
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if not block.has_method("get_collision_rect"): continue
		var br: Rect2 = block.get_collision_rect()
		if dir.x > 0 and absf(player_rect.end.x - br.position.x) > FACE_EPS: continue
		elif dir.x < 0 and absf(player_rect.position.x - br.end.x) > FACE_EPS: continue
		elif dir.y > 0 and absf(player_rect.end.y - br.position.y) > FACE_EPS: continue
		elif dir.y < 0 and absf(player_rect.position.y - br.end.y) > FACE_EPS: continue
		var dist = from_point.distance_squared_to(br.get_center())
		if dist < closest_dist:
			closest_dist = dist
			closest = block
	return closest

func check_room_transition(_player_grid: Vector2i, _player_pixel: Vector2 = Vector2.ZERO) -> void: pass
func _trigger_shake(_strength: float) -> void: pass
func shoot_door_ball(_from: Vector2, _to: Vector2, callback: Callable) -> void: callback.call()

class _PlayerStub extends Node2D:
	func get_body_center() -> Vector2:
		return Vector2.ZERO
	func unlock_movement() -> void: pass
	func lock_movement() -> void: pass

var _stub_player: _PlayerStub = _PlayerStub.new()

var player: Node2D:
	get:
		if _play_player != null and is_instance_valid(_play_player):
			return _play_player
		return _stub_player

var electric_beam: Node:
	get: return _play_beam

# ──────────────────────────────────────────────
#  Play mode
# ──────────────────────────────────────────────
func _enter_play_mode() -> void:
	_play_auto_save_data = _build_level_data()
	if OS.get_name() != "Web":
		DirAccess.make_dir_recursive_absolute("user://levels")
		var file = FileAccess.open("user://levels/auto_save.json", FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(_play_auto_save_data, "\t"))
			file.close()

	_play_spawn_pos = player_spawn_pos if player_spawn_pos != Vector2i(-1, -1) else Vector2i(2, 2)

	_restore_objects()

	for node in _wire_assignments:
		if is_instance_valid(node) and node.get("id") != null:
			node.id = "id" + str(_wire_assignments[node] + 1)

	# Re-register everything because _ready() ran at placement time with empty IDs.
	# Floor panels: GameManager.floor_panels must reflect new IDs for evaluate_puzzle().
	for fp in get_tree().get_nodes_in_group("floor_panels"):
		if fp.get("id") != null:
			var gp = Vector2i(floori(fp.position.x / TILE_SIZE), floori(fp.position.y / TILE_SIZE))
			var id2_val = fp.id2 if fp.get("id2") != null else ""
			GameManager.register_floor_panel(gp, fp.id, id2_val)
	# Doors & fans: GameManager.doors keys must match the new IDs so doors_update fires correctly.
	GameManager.doors.clear()
	for node in get_tree().get_nodes_in_group("doors"):
		if node.get("id") != null and node.id != "":
			GameManager.register_door(node, node.id)
	for node in get_tree().get_nodes_in_group("fans"):
		if node.get("id") != null and node.id != "":
			GameManager.register_door(node, node.id)

	_play_beam = ElectricBeamScene.instantiate()
	add_child(_play_beam)

	_play_player = PlayerScene.instantiate()
	_play_player.start_with_push = true
	_play_player.start_with_chain = true
	_play_player.save_system_enabled = false
	y_sort_root.add_child(_play_player)
	_play_player.reset_to(_play_spawn_pos)
	GameManager.grant_ability("break")

	player_marker.visible = false

	for door in get_tree().get_nodes_in_group("key_doors"):
		door._keys_total = 0
		door.call_deferred("_count_keys")

	_set_mode(Mode.PLAY)

func _exit_play_mode() -> void:
	for p in GameManager.clear_prongs():
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	_update_beam()

	if is_instance_valid(_play_player):
		_play_player.queue_free()
	_play_player = null

	if is_instance_valid(_play_beam):
		_play_beam.queue_free()
	_play_beam = null

	GameManager.clear_scene_state()

	if _play_auto_save_data.size() > 0:
		_apply_level_data(_play_auto_save_data)
		toast_label.visible = false
	elif OS.get_name() != "Web":
		_load_level("user://levels/auto_save.json")

	player_marker.visible = player_spawn_pos != Vector2i(-1, -1)
	_set_mode(Mode.BUILD)

func spawn_prong(pixel_pos: Vector2) -> void:
	AudioManager.play_sfx("plant_stake")
	if GameManager.prongs.size() >= 2:
		var oldest = GameManager.prongs[0]
		GameManager.remove_prong(oldest["node"])
		var pnode: Node2D = oldest["node"]
		var tween = pnode.create_tween()
		tween.tween_method(pnode.apply_clear_shrink, 1.0, 0.0, 0.15)
		tween.tween_callback(pnode.queue_free)
	var prong = ProngScene.instantiate()
	y_sort_root.add_child(prong)
	prong.setup(pixel_pos)
	GameManager.place_prong(prong, world_to_grid(pixel_pos))
	_update_beam()

func _update_beam() -> void:
	if _play_beam == null or not is_instance_valid(_play_beam):
		return
	var world_positions = GameManager.get_prong_world_positions()
	if world_positions.size() == 2:
		var path = _compute_beam_path(world_positions[0], world_positions[1])
		if path.is_empty():
			GameManager.beam_blocked = true
			GameManager.evaluate_puzzle()
			_play_beam.deactivate()
			var blocking = _get_beam_blockers(world_positions[0], world_positions[1])
			var flashing = _expand_connected_blockers(blocking)
			for b in get_tree().get_nodes_in_group("lightning_blockers"):
				b.set_blocking(b in flashing)
		else:
			GameManager.beam_blocked = false
			GameManager.evaluate_puzzle()
			_play_beam.activate(path)
			for b in get_tree().get_nodes_in_group("lightning_blockers"):
				b.set_blocking(false)
	else:
		GameManager.beam_blocked = false
		GameManager.evaluate_puzzle()
		_play_beam.deactivate()
		for b in get_tree().get_nodes_in_group("lightning_blockers"):
			b.set_blocking(false)

func _reset_room() -> void:
	if _play_player == null or not is_instance_valid(_play_player):
		return
	_play_player.lock_movement()
	for p in GameManager.clear_prongs():
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	_update_beam()
	for entry in placed_objects:
		if is_instance_valid(entry.node) and entry.node.has_method("reset"):
			entry.node.reset()
	_play_player.reset_to(_play_spawn_pos)
	_play_player.unlock_movement()

func _compute_beam_path(pos_a: Vector2, pos_b: Vector2) -> Array:
	var nut_nodes: Array = []
	if GameManager.has_ability("chain"):
		for nut in get_tree().get_nodes_in_group("nuts"):
			nut_nodes.append(nut)
	return _nearest_first_beam(pos_a, pos_b, nut_nodes, [pos_a])

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
		var next_remaining = remaining.duplicate()
		next_remaining.remove_at(i)
		var result = _nearest_first_beam(nut_pos, target, next_remaining, path + [nut])
		if not result.is_empty():
			return result
	return []

func _get_beam_blockers(pos_a: Vector2, pos_b: Vector2) -> Array:
	var blocking: Array = []
	for b in get_tree().get_nodes_in_group("lightning_blockers"):
		var gp = b.get_grid_pos()
		var rect = Rect2(Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
		if _segment_intersects_rect(pos_a, pos_b, rect):
			blocking.append(b)
	return blocking

func _expand_connected_blockers(seed: Array) -> Array:
	if seed.is_empty():
		return []
	var blocker_by_pos: Dictionary = {}
	for b in get_tree().get_nodes_in_group("lightning_blockers"):
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

# ──────────────────────────────────────────────
#  Wire mode helpers
# ──────────────────────────────────────────────
func _toggle_wire_mode() -> void:
	if _wire_mode:
		_wire_mode = false
		_set_mode(Mode.BUILD)
	else:
		_set_mode(Mode.BUILD)
		_wire_mode = true
		top_bar.visible = false
		palette_panel.visible = false
		placing_hint.text = "Space: Cycle Color"
		placing_hint.visible = true
		if _play_label:
			_play_label.text = "E: Edit    Q: Play"
	grid_overlay.queue_redraw()

func _cycle_wire_color() -> void:
	var available = _get_available_color_indices()
	if available.is_empty():
		return
	var pos = available.find(_wire_color_index)
	_wire_color_index = available[(pos + 1) % available.size()] if pos >= 0 else available[0]
	grid_overlay.queue_redraw()

func _get_available_color_indices() -> Array:
	var used: Dictionary = {}
	for node in _wire_assignments:
		if is_instance_valid(node):
			used[_wire_assignments[node]] = true
	var result = used.keys()
	result.sort()
	var next = 0
	while used.has(next):
		next += 1
	result.append(next)
	return result

func _get_wire_color(idx: int) -> Color:
	if idx < WIRE_BASE_COLORS.size():
		return WIRE_BASE_COLORS[idx]
	var rng = RandomNumberGenerator.new()
	rng.seed = (idx + 1) * 7919
	return Color(rng.randf_range(0.3, 1.0), rng.randf_range(0.3, 1.0), rng.randf_range(0.3, 1.0))

func _draw_wire_overlay() -> void:
	if not _wire_mode or mode == Mode.PLAY:
		return

	# Group object centers by color index
	var color_groups: Dictionary = {}
	for node in _wire_assignments:
		if not is_instance_valid(node):
			continue
		var idx = _wire_assignments[node]
		if not color_groups.has(idx):
			color_groups[idx] = []
		color_groups[idx].append(node.position + Vector2(16.0, 16.0))

	# Draw shortest-path dotted lines for each color group
	for idx in color_groups:
		var pts: Array = color_groups[idx]
		if pts.size() < 2:
			continue
		var color = _get_wire_color(idx)
		var path = _wire_nearest_neighbor(pts)
		for i in range(path.size() - 1):
			grid_overlay.draw_dashed_line(path[i], path[i + 1], color, 1.5, 6.0)

	# Draw dots on top of lines
	for node in _wire_assignments:
		if not is_instance_valid(node):
			continue
		var color = _get_wire_color(_wire_assignments[node])
		var center = node.position + Vector2(16.0, 16.0)
		grid_overlay.draw_circle(center, 8.0, Color.BLACK)
		grid_overlay.draw_circle(center, 6.0, color)

	# Draw cursor
	var world_pos = get_global_mouse_position()
	var gp = world_to_grid(world_pos)
	if gp.x >= 0 and gp.x < PLAY_COLS and gp.y >= 0 and gp.y < PLAY_ROWS:
		var cur_color = _get_wire_color(_wire_color_index)
		var center = Vector2(gp.x * TILE_SIZE + 16.0, gp.y * TILE_SIZE + 16.0)
		grid_overlay.draw_circle(center, 6.0, Color.BLACK)
		grid_overlay.draw_circle(center, 4.5, cur_color)

func _wire_nearest_neighbor(points: Array) -> Array:
	var sorted = points.duplicate()
	sorted.sort_custom(func(a, b):
		if not is_equal_approx(a.x, b.x):
			return a.x < b.x
		return a.y < b.y)
	return sorted

func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var c = [rect.position,
			  Vector2(rect.end.x, rect.position.y),
			  rect.end,
			  Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false
