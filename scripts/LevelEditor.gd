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
	"FloorSwitch":      "res://scenes/objects/FloorSwitch.tscn",
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
	"NanoDroid":        "res://scenes/objects/NanoDroid.tscn",
	"Hole":             "res://scenes/objects/Hole.tscn",
	"Capacitor":        "res://scenes/objects/Capacitor.tscn",
	"LightSource":      "res://scenes/objects/LightSource.tscn",
	"WaterEnemy":       "res://scenes/enemies/WaterEnemy.tscn",
	"BounceEnemy":      "res://scenes/enemies/BounceEnemy.tscn",
	"SpiderEnemy":      "res://scenes/enemies/SpiderEnemy.tscn",
	"ExitPoint":        "res://scenes/objects/ExitPoint.tscn",
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
	"Door":             "res://Sprites/objects/door.webp",
	"FloorPanel":       "res://Sprites/objects/positive.png",
	"FloorPanelNeg":    "res://Sprites/objects/negative.png",
	"FloorSwitch":      "res://Sprites/objects/Switch-Sheet.webp",
	"KeyDoor":          "res://Sprites/objects/KeyDoor.webp",
	"Key":              "res://Sprites/objects/Key_File.webp",
	"FanRight":         "res://Sprites/objects/Fan_Right.png",
	"FanLeft":          "res://Sprites/objects/Fan_Left.png",
	"FanUp":            "res://Sprites/objects/Fan_Back.png",
	"FanDown":          "res://Sprites/objects/Fan_Front.png",
	"WindTurbine":      "res://Sprites/objects/placeholder.png",
	"WindBlock":        "res://Sprites/objects/Dust_Pile.png",
	"NanoDroid":        "res://Sprites/objects/Nanobot_Back_Idle.png",
	"Hole":             "res://Sprites/objects/Holes/hole1.png",
	"Capacitor":        "res://Sprites/objects/Capaciter-Sheet.webp",
	"LightSource":      "res://Sprites/objects/floor_switch.png",
	"DustPile":         "res://Sprites/objects/Dust_Pile_Alternate.png",
	"BreakableWall":    "res://Sprites/objects/wall_breakable.png",
	"KeyBreakableWall": "res://Sprites/objects/wall_breakable.png",
	"KeyDustPile":      "res://Sprites/objects/Dust_Pile_Alternate.png",
	"WaterEnemy":       "res://Sprites/enemies/Front_Idle1.png",
	"BounceEnemy":      "res://Sprites/enemies/BounceFront.png",
	"SpiderEnemy":      "res://Sprites/enemies/spider_small.png",
	"ExitPoint":        "res://Sprites/objects/teleport_closed.png",
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

# Playtest-only "dark room" preview. The toggle above the palette turns it on; the
# overlay (shared DarknessOverlay component) only runs while playtesting.
var _darkness: DarknessOverlay
var _dark_toggle: CheckBox

var placed_objects: Array = []
var player_spawn_pos: Vector2i = Vector2i(-1, -1)

# Drag placement
var _drag_placing: bool = false
var _drag_deleting: bool = false
var _drag_visited: Array = []

# Keyboard delete (holding X deletes under the cursor like a right-click drag)
var _x_deleting: bool = false

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
# Bottom-left editing controls hint (Z/X/C), shown while placing in BUILD/PLACING
var _controls_label: Label = null
var _play_auto_save_data: Dictionary = {}

var _music_btn: Button

# Undo system
var _undo_stack: Array = []
const MAX_UNDO = 50
var _drag_undo_batch: Array = []
var _batching_undo: bool = false

# Object dragging in BUILD mode
var _obj_drag_node: Node = null
var _obj_drag_start_gp: Vector2i = Vector2i.ZERO
var _obj_drag_active: bool = false
var _obj_drag_is_wall: bool = false

# Playtest "SPACE" prompt shown above the player while on an open ExitPoint
var _space_label: Label = null

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
	_play_label.offset_left = -172
	_play_label.offset_right = -20
	_play_label.offset_top = -38
	_play_label.offset_bottom = -20
	editor_ui.add_child(_play_label)

	# "SPACE" prompt above the player while standing on an open ExitPoint
	_space_label = Label.new()
	_space_label.text = "SPACE"
	_space_label.visible = false
	_space_label.add_theme_color_override("font_color", Color.WHITE)
	_space_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_space_label.add_theme_constant_override("outline_size", 2)
	_space_label.add_theme_font_size_override("font_size", 11)
	editor_ui.add_child(_space_label)

	# Bottom-left editing controls hint (visible while placing, hidden during playtest)
	_controls_label = Label.new()
	_controls_label.text = "Z: Undo\nX: Delete\nC: Copy Tile"
	_controls_label.add_theme_color_override("font_color", Color.WHITE)
	_controls_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_controls_label.add_theme_constant_override("outline_size", 2)
	_controls_label.add_theme_font_size_override("font_size", 12)
	_controls_label.anchor_left = 0.0
	_controls_label.anchor_right = 0.0
	_controls_label.anchor_top = 1.0
	_controls_label.anchor_bottom = 1.0
	_controls_label.grow_horizontal = Control.GROW_DIRECTION_END
	_controls_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_controls_label.offset_left = 20
	_controls_label.offset_right = 160
	_controls_label.offset_top = -76
	_controls_label.offset_bottom = -20
	editor_ui.add_child(_controls_label)

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
	_setup_dark_toggle()
	toast_label.visible = false
	placing_hint.visible = false
	_setup_play_label()

	_darkness = DarknessOverlay.new()
	add_child(_darkness)
	# Keep the editor UI (incl. the "SPACE" exit prompt) above the dark overlay (layer 40).
	($EditorUI as CanvasLayer).layer = 50

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
	scene_keys.erase("ExitPoint")  # placed manually right after Player
	var bw_idx = scene_keys.find("BreakableWall")
	if bw_idx >= 0:
		scene_keys.insert(bw_idx + 1, "KeyBreakableWall")
	else:
		scene_keys.append("KeyBreakableWall")
	var dp_idx = scene_keys.find("DustPile")
	if dp_idx >= 0:
		scene_keys.insert(dp_idx + 1, "KeyDustPile")
	else:
		scene_keys.append("KeyDustPile")
	var types = ["Wires", "Wall", "Player", "ExitPoint"] + scene_keys
	palette_list.columns = 22

	for t in types:
		if t == "KeyBreakableWall" or t == "KeyDustPile":
			# Two-layer icon: the destructible base with a faded key on top.
			var base_path = PALETTE_SPRITES["BreakableWall"] if t == "KeyBreakableWall" else PALETTE_SPRITES["DustPile"]
			var container = Button.new()
			container.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			container.flat = false
			container.pressed.connect(func(): _select_type(t))
			var base_rect = TextureRect.new()
			base_rect.texture = _first_frame_texture(base_path)
			base_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			base_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			base_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			base_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var key_rect = TextureRect.new()
			key_rect.texture = _first_frame_texture("res://Sprites/objects/Key_File.webp")
			key_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			key_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			key_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			key_rect.modulate = Color(1, 1, 1, 0.5)
			key_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(base_rect)
			container.add_child(key_rect)
			palette_list.add_child(container)
			_palette_buttons[t] = container
		elif t == "KeyDoor":
			var kd_container = Button.new()
			kd_container.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			kd_container.clip_contents = true
			kd_container.flat = false
			kd_container.pressed.connect(func(): _select_type(t))
			var kd_raw = load(PALETTE_SPRITES["KeyDoor"]) as Texture2D
			var kd_atlas = AtlasTexture.new()
			kd_atlas.atlas = kd_raw
			kd_atlas.region = Rect2(0, 0, 32, 42)
			var kd_rect = TextureRect.new()
			kd_rect.texture = kd_atlas
			kd_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			kd_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			kd_rect.anchor_left = 0.0
			kd_rect.anchor_right = 1.0
			kd_rect.anchor_top = 1.0
			kd_rect.anchor_bottom = 1.0
			kd_rect.offset_top = -42
			kd_rect.offset_bottom = 0
			kd_rect.offset_left = 0
			kd_rect.offset_right = 0
			kd_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			kd_container.add_child(kd_rect)
			palette_list.add_child(kd_container)
			_palette_buttons[t] = kd_container
		elif t == "Capacitor":
			# 32×48 sheet; show the first frame bottom-anchored (top 16px clipped)
			var cap_container = Button.new()
			cap_container.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			cap_container.clip_contents = true
			cap_container.flat = false
			cap_container.pressed.connect(func(): _select_type(t))
			var cap_raw = load(PALETTE_SPRITES["Capacitor"]) as Texture2D
			var cap_atlas = AtlasTexture.new()
			cap_atlas.atlas = cap_raw
			cap_atlas.region = Rect2(0, 0, 32, 48)
			var cap_rect = TextureRect.new()
			cap_rect.texture = cap_atlas
			cap_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cap_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			cap_rect.anchor_left = 0.0
			cap_rect.anchor_right = 1.0
			cap_rect.anchor_top = 1.0
			cap_rect.anchor_bottom = 1.0
			cap_rect.offset_top = -48
			cap_rect.offset_bottom = 0
			cap_rect.offset_left = 0
			cap_rect.offset_right = 0
			cap_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cap_container.add_child(cap_rect)
			palette_list.add_child(cap_container)
			_palette_buttons[t] = cap_container
		elif t == "BounceEnemy":
			# 64×64 sprite shown bottom-center anchored, scaled to fit the cell
			var be_container = Button.new()
			be_container.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			be_container.clip_contents = true
			be_container.flat = false
			be_container.pressed.connect(func(): _select_type(t))
			var be_rect = TextureRect.new()
			be_rect.texture = load(PALETTE_SPRITES["BounceEnemy"]) as Texture2D
			be_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			be_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			be_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			be_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			be_container.add_child(be_rect)
			palette_list.add_child(be_container)
			_palette_buttons[t] = be_container
		else:
			var btn = TextureButton.new()
			btn.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			if PALETTE_SPRITES.has(t):
				btn.texture_normal = _first_frame_texture(PALETTE_SPRITES[t])
			btn.pressed.connect(func(): _select_type(t))
			if t == "SpiderEnemy":
				var img = load(PALETTE_SPRITES["SpiderEnemy"]).get_image()
				img.rotate_90(CLOCKWISE)
				btn.texture_normal = ImageTexture.create_from_image(img)
			palette_list.add_child(btn)
			_palette_buttons[t] = btn

	_highlight_palette(selected_type)

# Checkbox above the palette (bottom-left) that makes the room dark during playtests.
func _setup_dark_toggle() -> void:
	_dark_toggle = CheckBox.new()
	_dark_toggle.text = "Dark"
	_dark_toggle.focus_mode = Control.FOCUS_NONE
	_dark_toggle.add_theme_font_size_override("font_size", 11)
	_dark_toggle.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dark_toggle.offset_left = 12
	_dark_toggle.offset_right = 172
	_dark_toggle.offset_top = -112
	_dark_toggle.offset_bottom = -86
	($EditorUI as CanvasLayer).add_child(_dark_toggle)

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
		if type == "KeyBreakableWall" or type == "KeyDustPile":
			# Only tint the base layer; key layer keeps its 50% alpha
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
	if _dark_toggle != null:
		_dark_toggle.visible = new_mode == Mode.BUILD
	_drag_placing = false
	_drag_deleting = false
	if _x_deleting:
		_x_deleting = false
		_commit_drag_undo_batch()
	_floor_paint_batch.clear()
	_floor_erase_batch.clear()
	if _obj_drag_node != null and is_instance_valid(_obj_drag_node):
		_obj_drag_node.visible = true
	if _obj_drag_is_wall and _obj_drag_active:
		# Restore a wall whose drag was interrupted by a mode switch
		walls_tilemap.set_cell(_obj_drag_start_gp, WALL_SOURCE_ID, Vector2i(0, 0))
	_obj_drag_node = null
	_obj_drag_is_wall = false
	_obj_drag_active = false

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

	if _controls_label:
		# Only while actively placing tiles (PLACING) — not when the palette is open
		# (BUILD), in wire mode, or playtesting.
		_controls_label.visible = mode == Mode.PLACING and not _wire_mode

	_update_space_label()

	if _darkness != null and _darkness.visible and mode == Mode.PLAY:
		_darkness.update_lights(camera, _gather_lights())

	# Holding X deletes whatever is under the cursor, like a right-click drag
	if _process_x_delete():
		return

	# Object/wall drag (BUILD or PLACING mode)
	if (mode == Mode.BUILD or mode == Mode.PLACING) and _is_dragging():
		_process_obj_drag()
		return

	if mode != Mode.PLACING:
		ghost_sprite.visible = false
		return

	var world_pos = get_global_mouse_position()
	var gp = world_to_grid(world_pos)
	var in_bounds = gp.x >= -1 and gp.x < ROOM_COLS and gp.y >= -1 and gp.y < ROOM_ROWS
	ghost_sprite.visible = in_bounds and selected_type != "Wires"

	if in_bounds:
		ghost_sprite.position = _ghost_position_for(selected_type, gp)

		if _ghost_tex_type != selected_type:
			_ghost_tex_type = selected_type
			_apply_ghost_texture(selected_type)

	if _drag_placing or _drag_deleting:
		_handle_drag_at(gp)

func _process_x_delete() -> bool:
	# While X is held (BUILD/PLACING, not wire mode), delete the tile under the
	# cursor each frame — same behavior as holding right-click. Returns true while
	# active so _process skips ghost/drag handling.
	var held = Input.is_key_pressed(KEY_X) and mode != Mode.PLAY and not _wire_mode \
			and not _is_dragging() and not _drag_placing and not _drag_deleting
	if held:
		if not _x_deleting:
			_x_deleting = true
			_begin_drag_undo_batch()
		_delete_at(world_to_grid(get_global_mouse_position()))
		ghost_sprite.visible = false
		return true
	if _x_deleting:
		_x_deleting = false
		_commit_drag_undo_batch()
		_flush_floor_batches()
	return false

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
			if mode == Mode.PLAY:
				# Standing on an open ExitPoint ends the playtest
				if _player_on_exit_point():
					_exit_play_mode()
					get_viewport().set_input_as_handled()
			else:
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
		KEY_Z:
			if mode == Mode.PLAY:
				# Gameplay push undo/redo during a playtest (matches Main): Z undoes the
				# last block push, and again redoes it when there's nothing left to undo.
				if is_instance_valid(_play_player) and not _play_player.movement_locked:
					if _last_push != null:
						undo_last_push()
					elif _undo_push != null:
						redo_last_push()
				get_viewport().set_input_as_handled()
			else:
				_undo_last_action()
				get_viewport().set_input_as_handled()
		KEY_C:
			if mode != Mode.PLAY:
				_eyedropper_at(world_to_grid(get_global_mouse_position()))
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.PLAY:
		return
	if not (event is InputEventMouseButton):
		return

	var mb = event as InputEventMouseButton

	# Middle mouse = eyedropper: pick the type under the cursor and enter placement
	if mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
		_eyedropper_at(world_to_grid(get_global_mouse_position()))
		return

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
		var pgp = world_to_grid(get_global_mouse_position())
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Clicking an existing object/wall starts a drag-move instead of placing
				if selected_type != "Wires" and _try_start_drag(pgp):
					return
				_drag_deleting = false  # cancel any stuck delete drag
				_drag_placing = true
				_drag_visited.clear()
				_begin_drag_undo_batch()
			else:
				if _is_dragging():
					_finalize_obj_drag()
					return
				_drag_placing = false
				_commit_drag_undo_batch()
				_flush_floor_batches()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_drag_placing = false  # cancel any stuck place drag
				_drag_deleting = true
				_begin_drag_undo_batch()
			else:
				_drag_deleting = false
				_commit_drag_undo_batch()
				_flush_floor_batches()

	match mode:
		Mode.BUILD:
			_handle_build_click(mb)
		Mode.PLACING:
			if mb.pressed and not _is_dragging():
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
	if _drag_placing:
		# Floor tiles: accumulate batch and call terrain connect incrementally
		if selected_type == "Wires":
			_place_floor_at(gp)
			return
		if gp in _drag_visited:
			return
		_drag_visited.append(gp)
		if placing_wall:
			_place_wall(gp)
		else:
			# Objects drag-paint once per empty tile; _place_object skips occupied tiles
			_place_object(selected_type, gp)
	elif _drag_deleting:
		_delete_at(gp)

func _place_floor_at(gp: Vector2i) -> void:
	if gp.x < 0 or gp.x >= PLAY_COLS or gp.y < 0 or gp.y >= PLAY_ROWS:
		return
	if gp in _floor_paint_batch:
		return
	var had_floor = floor_tilemap.get_cell_source_id(gp) >= 0
	_floor_paint_batch.append(gp)
	# Use ALL existing cells + new cell so neighbors outside the current drag are considered
	var all_cells: Array[Vector2i] = floor_tilemap.get_used_cells()
	if not (gp in all_cells):
		all_cells.append(gp)
	floor_tilemap.set_cells_terrain_connect(all_cells, 0, 0)
	# match_sides needs neighbors; if isolated cell got no tile, force a fallback
	if floor_tilemap.get_cell_source_id(gp) == -1:
		floor_tilemap.set_cell(gp, 0, Vector2i(2, 0))
	if not had_floor:
		_push_undo({"kind": "floor", "col": gp.x, "row": gp.y, "placed": true})

func _erase_floor_at(gp: Vector2i) -> void:
	if gp in _floor_erase_batch:
		return
	var had_floor = floor_tilemap.get_cell_source_id(gp) >= 0
	_floor_erase_batch.append(gp)
	floor_tilemap.set_cells_terrain_connect(_floor_erase_batch, 0, -1)
	if had_floor:
		_push_undo({"kind": "floor", "col": gp.x, "row": gp.y, "placed": false})

func _delete_at(gp: Vector2i) -> void:
	# Delete whatever is at the cell, regardless of the selected tool:
	# objects first, then walls, then floor wires, then the player spawn marker
	var existing = _object_at(gp)
	if existing:
		_delete_object(existing)
	elif walls_tilemap.get_cell_source_id(gp) >= 0:
		walls_tilemap.erase_cell(gp)
		_push_undo({"kind": "wall", "col": gp.x, "row": gp.y, "placed": false})
	elif gp.x >= 0 and gp.x < PLAY_COLS and gp.y >= 0 and gp.y < PLAY_ROWS \
			and floor_tilemap.get_cell_source_id(gp) >= 0:
		_erase_floor_at(gp)
	elif player_spawn_pos == gp:
		player_spawn_pos = Vector2i(-1, -1)
		player_marker.visible = false

func _handle_build_click(mb: InputEventMouseButton) -> void:
	# Finalize drag on left release (allow outside bounds)
	if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _is_dragging():
			_finalize_obj_drag()
		return

	var world_pos = get_global_mouse_position()
	var gp = world_to_grid(world_pos)
	if gp.x < 0 or gp.x >= ROOM_COLS or gp.y < 0 or gp.y >= ROOM_ROWS:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		# Clicking an existing object/wall starts a potential drag-move
		if _try_start_drag(gp):
			return
		# Empty cell: seamlessly switch into placement mode
		_enter_placing_from_build(false, gp)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		# Right-clicking seamlessly switches into placement mode (delete);
		# this also deletes any object/wall already at the clicked cell
		_enter_placing_from_build(true, gp)

func _enter_placing_from_build(is_delete: bool, gp: Vector2i) -> void:
	# Seamless transition from BUILD (select) mode into PLACING mode on grid click
	_set_mode(Mode.PLACING)
	_apply_floor_fade(selected_type == "Wires")
	if is_delete:
		_drag_deleting = true
	else:
		_drag_placing = true
		_drag_visited.clear()
	_begin_drag_undo_batch()
	_handle_drag_at(gp)

# ──────────────────────────────────────────────
#  Object / tile placement
# ──────────────────────────────────────────────
func world_to_grid(wp: Vector2) -> Vector2i:
	return GridUtils.to_grid(wp)

func grid_to_world(gp: Vector2i) -> Vector2:
	return GridUtils.to_world(gp)

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
	var was_present = walls_tilemap.get_cell_source_id(gp) >= 0
	walls_tilemap.set_cell(gp, WALL_SOURCE_ID, Vector2i(0, 0))
	if not was_present:
		_push_undo({"kind": "wall", "col": gp.x, "row": gp.y, "placed": true})

func _place_object(type: String, gp: Vector2i) -> void:
	if type == "Player":
		if gp.x < 0 or gp.x >= PLAY_COLS or gp.y < 0 or gp.y >= PLAY_ROWS:
			return
		if walls_tilemap.get_cell_source_id(gp) >= 0 or border_walls_tilemap.get_cell_source_id(gp) >= 0:
			return
		var prev = player_spawn_pos
		player_spawn_pos = gp
		player_marker.position = grid_to_world(gp)
		player_marker.visible = true
		_push_undo({"kind": "player_spawn", "new_col": gp.x, "new_row": gp.y,
					"prev_col": prev.x, "prev_row": prev.y})
		return

	if type == "KeyBreakableWall":
		_place_object("BreakableWall", gp)
		_place_object("Key", gp)
		return

	if type == "KeyDustPile":
		_place_object("DustPile", gp)
		_place_object("Key", gp)
		return

	if gp.x < 0 or gp.x >= PLAY_COLS or gp.y < 0 or gp.y >= PLAY_ROWS:
		return
	if not SCENE_MAP.has(type):
		return
	# Objects cannot be placed on top of walls
	if walls_tilemap.get_cell_source_id(gp) >= 0 or border_walls_tilemap.get_cell_source_id(gp) >= 0:
		return

	var existing = _object_at(gp)
	if existing != null:
		# Only allow Key on top of a destructible (BreakableWall or DustPile)
		if not (type == "Key" and _type_of(existing) in ["BreakableWall", "DustPile"]):
			return

	var inst = load(SCENE_MAP[type]).instantiate()
	inst.position = grid_to_world(gp)

	if type == "FloorPanelNeg" and inst.get("positive") != null:
		inst.positive = false

	y_sort_root.add_child(inst)

	# Make PassBlock visible in editor so designers can see placements
	_make_passblock_visible(inst, type)

	# Must be after add_child: Key._ready() resets z_index to -5
	if type == "Key" and existing != null:
		inst.modulate.a = 0.5
		inst.z_index = 5

	# KeyDoor._count_keys() is deferred; pre-set _keys_total=1 so it never
	# auto-opens when placed with no keys present in the editor
	if type == "KeyDoor":
		inst._keys_total = 1

	placed_objects.append({ "node": inst, "type": type, "col": gp.x, "row": gp.y })
	_push_undo({"kind": "place_obj", "node": inst, "type": type, "col": gp.x, "row": gp.y})

func _delete_object_no_undo(node: Node) -> void:
	_wire_assignments.erase(node)
	for i in range(placed_objects.size() - 1, -1, -1):
		if placed_objects[i].node == node:
			placed_objects.remove_at(i)
			break
	if selected_object == node:
		selected_object = null
		props_panel.visible = false
	node.queue_free()

func _delete_object(node: Node) -> void:
	var type = _type_of(node)
	var col = -1
	var row = -1
	for e in placed_objects:
		if e.node == node:
			col = e.col
			row = e.row
			break
	var id_val = node.get("id") if node.get("id") != null else ""
	var id2_val = node.get("id2") if node.get("id2") != null else ""
	var positive_val = node.get("positive") if node.get("positive") != null else true
	var wire_val = _wire_assignments.get(node, -1)
	_delete_object_no_undo(node)
	if type != "" and col >= 0:
		_push_undo({"kind": "delete_obj", "obj_type": type, "col": col, "row": row,
					"id": id_val, "id2": id2_val, "positive": positive_val, "wire": wire_val})

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
		# Restore PassBlock visibility for editor view
		_make_passblock_visible(node, entry.type)
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
	_undo_stack.clear()
	_drag_undo_batch.clear()
	_batching_undo = false

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
			_make_passblock_visible(inst, obj.type)
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
	return SerializeUtils.encode_dict(data)

func _decode_level_string(encoded: String) -> Dictionary:
	return SerializeUtils.decode_to_dict(encoded)

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
	return GridUtils.tile_rect(gp)

func _is_static_solid(gp: Vector2i, include_holes: bool = true) -> bool:
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
	for capacitor in get_tree().get_nodes_in_group("capacitors"):
		if capacitor.get_grid_pos() == gp:
			return true
	for ep in get_tree().get_nodes_in_group("exit_points"):
		if not ep.is_open and ep.get_grid_pos() == gp:
			return true
	if include_holes:
		for hole in get_tree().get_nodes_in_group("holes"):
			if hole.is_solid() and hole.get_grid_pos() == gp:
				return true
	return false

func _hole_at(gp: Vector2i) -> Node:
	for hole in get_tree().get_nodes_in_group("holes"):
		if hole.get_grid_pos() == gp:
			return hole
	return null

func get_player_blocking_rects(area: Rect2, include_holes: bool = true) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var x0 = floori(area.position.x / TILE_SIZE)
	var x1 = floori((area.end.x - 0.001) / TILE_SIZE)
	var y0 = floori(area.position.y / TILE_SIZE)
	var y1 = floori((area.end.y - 0.001) / TILE_SIZE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _is_static_solid(Vector2i(x, y), include_holes):
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
	var hole := _hole_at(gp)
	if hole != null and hole.can_accept_block():
		return true
	return not _is_static_solid(gp) and get_push_block_at(gp) == null and not has_pass_block_at(gp)

func get_push_block_at(gp: Vector2i) -> Node:
	return PushUtils.block_at(get_tree().get_nodes_in_group("push_blocks"), gp)

func get_push_block_at_face(player_rect: Rect2, dir: Vector2i, from_point: Vector2) -> Node:
	return PushUtils.block_at_face(get_tree().get_nodes_in_group("push_blocks"), player_rect, dir, from_point)

func check_room_transition(_player_grid: Vector2i, _player_pixel: Vector2 = Vector2.ZERO) -> void: pass
func _trigger_shake(_strength: float) -> void: pass

# Prong-to-prong teleport (player presses X near a prong). Shares Main's sequence
# so the X action doesn't error out during a playtest, where _main is the editor.
func teleport_between_prongs(target_center: Vector2) -> void:
	if _play_player == null or not is_instance_valid(_play_player):
		return
	await PlayerUtils.teleport_between_prongs(_play_player, target_center)

func shoot_door_ball(_from: Vector2, _to: Vector2, callback: Callable) -> void: callback.call()

# One-deep gameplay push history for the playtest (Z = undo / redo), mirroring Main.
# The geometry is shared via PushHistoryUtils; only the pointers live here.
var _last_push = null
var _undo_push = null

func record_push(block: Node, from_pos: Vector2i, dir: Vector2i) -> void:
	_last_push = {"block": block, "from": from_pos, "dir": dir}
	_undo_push = null

func undo_last_push() -> void:
	if _last_push == null:
		return
	if not is_instance_valid(_last_push.block):
		_last_push = null
		return
	if PushHistoryUtils.apply_undo(self, _last_push):
		_undo_push = _last_push
		_last_push = null

func redo_last_push() -> void:
	if _undo_push == null:
		return
	if not is_instance_valid(_undo_push.block):
		_undo_push = null
		return
	if PushHistoryUtils.apply_redo(self, _undo_push):
		_last_push = _undo_push
		_undo_push = null

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
	_last_push = null
	_undo_push = null

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
	# LightSources are powered like doors, so their ids must be registered too.
	for node in get_tree().get_nodes_in_group("light_sources"):
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

	if _darkness != null:
		_darkness.set_dark(_dark_toggle != null and _dark_toggle.button_pressed, false)

	_set_mode(Mode.PLAY)

func _exit_play_mode() -> void:
	if _darkness != null:
		_darkness.set_dark(false, false)
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

# Light circles for the darkness overlay during a playtest: the player plus any
# powered LightSource. Mirrors Main._gather_lights() (single room in the editor).
const PLAYER_LIGHT_RADIUS := 64.0

# Powered LightSource nodes (single editor room, so no room filter — the room-scoping
# divergence from Main._powered_light_sources() stays here in the scene).
func _powered_light_sources() -> Array:
	var out: Array = []
	for ls in get_tree().get_nodes_in_group("light_sources"):
		if is_instance_valid(ls) and ls.is_powered():
			out.append(ls)
	return out

func _gather_lights() -> Array:
	var player_pos: Vector2 = _play_player.get_body_center() if is_instance_valid(_play_player) else Vector2.ZERO
	return LightUtils.gather_lights(player_pos, PLAYER_LIGHT_RADIUS, _powered_light_sources())

# True while the playtest is running dark (mirrors Main.is_room_dark_active()).
func is_room_dark_active() -> bool:
	return _darkness != null and _darkness.is_dark()

# Away-from-light push at world_pos from powered LightSources only; Vector2.ZERO when
# not dark or clear. Mirrors Main.light_flee_vector().
func light_flee_vector(world_pos: Vector2, exit_radius: float, fleeing: bool) -> Vector2:
	if not is_room_dark_active():
		return Vector2.ZERO
	return LightUtils.object_flee_vector(world_pos, _powered_light_sources(), exit_radius, fleeing)

func _player_on_exit_point() -> bool:
	if _play_player == null or not is_instance_valid(_play_player):
		return false
	for ep in get_tree().get_nodes_in_group("exit_points"):
		if ep.is_player_standing_on(_play_player):
			return true
	return false

func _update_space_label() -> void:
	if _space_label == null:
		return
	var show = mode == Mode.PLAY and _player_on_exit_point()
	_space_label.visible = show
	if show:
		var p = _play_player
		# Sit above the player sprite top, matching the teleport "TAB" prompt
		var world_pos = Vector2(p.visual_pos.x, p.visual_pos.y - 16.0 - 14.0)
		var screen_pos = world_pos - camera.position - camera.offset + Vector2(400.0, 192.0)
		_space_label.position = screen_pos - Vector2(_space_label.size.x * 0.5, 0.0)

func _eyedropper_at(gp: Vector2i) -> void:
	# Pick the type under the cursor and switch into placement mode with it selected.
	# An object on top of a wire is preferred over the wire itself.
	var obj = _object_at(gp)
	if obj != null:
		_select_type(_type_of(obj))
	elif walls_tilemap.get_cell_source_id(gp) >= 0:
		_select_type("Wall")
	elif gp.x >= 0 and gp.x < PLAY_COLS and gp.y >= 0 and gp.y < PLAY_ROWS \
			and floor_tilemap.get_cell_source_id(gp) >= 0:
		_select_type("Wires")

func spawn_prong(pixel_pos: Vector2) -> void:
	AudioManager.play_sfx("plant_stake")
	# Swing the hammer first; the prong is only placed once the animation ends.
	await player.play_plant()
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
	var blockers := get_tree().get_nodes_in_group("lightning_blockers")
	var nuts := _gather_chain_nuts()
	var path: Array = []
	if world_positions.size() == 2:
		path = BeamUtils.best_beam_path(blockers, world_positions[0], world_positions[1], nuts)
	BeamUtils.apply_beam_result(_play_beam, blockers, world_positions, path)

func _reset_room() -> void:
	if _play_player == null or not is_instance_valid(_play_player):
		return
	_last_push = null
	_undo_push = null
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

func _gather_chain_nuts() -> Array:
	var nut_nodes: Array = []
	if GameManager.has_ability("chain"):
		for nut in get_tree().get_nodes_in_group("nuts"):
			nut_nodes.append(nut)
	return nut_nodes

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

# ──────────────────────────────────────────────
#  Undo system
# ──────────────────────────────────────────────
func _push_undo(entry: Dictionary) -> void:
	if _batching_undo:
		_drag_undo_batch.append(entry)
	else:
		_undo_stack.append(entry)
		if _undo_stack.size() > MAX_UNDO:
			_undo_stack.pop_front()

func _begin_drag_undo_batch() -> void:
	_batching_undo = true
	_drag_undo_batch.clear()

func _commit_drag_undo_batch() -> void:
	_batching_undo = false
	if not _drag_undo_batch.is_empty():
		_undo_stack.append({"kind": "batch", "entries": _drag_undo_batch.duplicate()})
		if _undo_stack.size() > MAX_UNDO:
			_undo_stack.pop_front()
	_drag_undo_batch.clear()

func _undo_last_action() -> void:
	if _undo_stack.is_empty():
		return
	var entry = _undo_stack.pop_back()
	_apply_undo_entry(entry)

func _apply_undo_entry(entry: Dictionary) -> void:
	match entry.kind:
		"wall":
			var gp = Vector2i(entry.col, entry.row)
			if entry.placed:
				walls_tilemap.erase_cell(gp)
			else:
				walls_tilemap.set_cell(gp, WALL_SOURCE_ID, Vector2i(0, 0))
		"floor":
			var gp = Vector2i(entry.col, entry.row)
			if entry.placed:
				floor_tilemap.set_cells_terrain_connect([gp], 0, -1)
			else:
				# Restore the erased floor cell, reconnecting it to its neighbors
				var all_cells: Array[Vector2i] = floor_tilemap.get_used_cells()
				if not (gp in all_cells):
					all_cells.append(gp)
				floor_tilemap.set_cells_terrain_connect(all_cells, 0, 0)
				if floor_tilemap.get_cell_source_id(gp) == -1:
					floor_tilemap.set_cell(gp, 0, Vector2i(2, 0))
		"place_obj":
			if is_instance_valid(entry.node):
				_delete_object_no_undo(entry.node)
		"delete_obj":
			if not SCENE_MAP.has(entry.obj_type):
				return
			var gp = Vector2i(entry.col, entry.row)
			var inst = load(SCENE_MAP[entry.obj_type]).instantiate()
			inst.position = grid_to_world(gp)
			if entry.obj_type == "FloorPanelNeg" and inst.get("positive") != null:
				inst.positive = false
			if inst.get("id") != null and entry.id != "": inst.id = entry.id
			if inst.get("id2") != null and entry.id2 != "": inst.id2 = entry.id2
			if inst.get("positive") != null: inst.positive = entry.positive
			y_sort_root.add_child(inst)
			_make_passblock_visible(inst, entry.obj_type)
			if entry.obj_type == "KeyDoor":
				inst._keys_total = 1
			placed_objects.append({"node": inst, "type": entry.obj_type, "col": entry.col, "row": entry.row})
			if entry.wire >= 0:
				_wire_assignments[inst] = entry.wire
		"player_spawn":
			if entry.prev_col == -1:
				player_spawn_pos = Vector2i(-1, -1)
				player_marker.visible = false
			else:
				player_spawn_pos = Vector2i(entry.prev_col, entry.prev_row)
				player_marker.position = grid_to_world(player_spawn_pos)
				player_marker.visible = true
		"move_obj":
			if is_instance_valid(entry.node):
				_move_object_to(entry.node, Vector2i(entry.from_col, entry.from_row), false)
		"batch":
			for i in range(entry.entries.size() - 1, -1, -1):
				_apply_undo_entry(entry.entries[i])

# ──────────────────────────────────────────────
#  Object / wall dragging (BUILD or PLACING mode)
# ──────────────────────────────────────────────
func _is_dragging() -> bool:
	return _obj_drag_node != null or _obj_drag_is_wall

func _try_start_drag(gp: Vector2i) -> bool:
	# Begin dragging an existing object (preferred) or wall at gp. Returns true if started.
	var obj = _object_at(gp)
	if obj != null:
		_obj_drag_node = obj
		_obj_drag_is_wall = false
		_obj_drag_start_gp = gp
		_obj_drag_active = false
		_ghost_tex_type = ""
		return true
	if walls_tilemap.get_cell_source_id(gp) >= 0:
		_obj_drag_node = null
		_obj_drag_is_wall = true
		_obj_drag_start_gp = gp
		_obj_drag_active = false
		_ghost_tex_type = ""
		return true
	return false

func _process_obj_drag() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Released outside window or canvas — finalize
		_finalize_obj_drag()
		return
	var world_pos = get_global_mouse_position()
	var gp = world_to_grid(world_pos)
	if gp != _obj_drag_start_gp:
		_obj_drag_active = true
	if _obj_drag_active:
		var drag_type = "Wall" if _obj_drag_is_wall else _type_of(_obj_drag_node)
		var in_bounds: bool
		if _obj_drag_is_wall:
			# Hide the original wall cell so only the ghost shows
			walls_tilemap.erase_cell(_obj_drag_start_gp)
			in_bounds = gp.x >= -1 and gp.x < ROOM_COLS and gp.y >= -1 and gp.y < ROOM_ROWS
		else:
			# Hide the real object so only the grid-snapped ghost is visible
			_obj_drag_node.visible = false
			in_bounds = gp.x >= 0 and gp.x < PLAY_COLS and gp.y >= 0 and gp.y < PLAY_ROWS
		ghost_sprite.visible = in_bounds
		if in_bounds:
			ghost_sprite.position = _ghost_position_for(drag_type, gp)
		if drag_type != "" and drag_type != _ghost_tex_type:
			_ghost_tex_type = drag_type
			_apply_ghost_texture_to(ghost_sprite, drag_type)

func _finalize_obj_drag() -> void:
	ghost_sprite.visible = false
	_ghost_tex_type = ""
	if _obj_drag_is_wall:
		var start = _obj_drag_start_gp
		if _obj_drag_active:
			var gp = world_to_grid(get_global_mouse_position())
			var in_bounds = gp.x >= -1 and gp.x < ROOM_COLS and gp.y >= -1 and gp.y < ROOM_ROWS
			var free = _object_at(gp) == null and walls_tilemap.get_cell_source_id(gp) < 0
			if gp != start and in_bounds and free:
				# Original cell was erased during drag; record the move as a batch
				_begin_drag_undo_batch()
				_push_undo({"kind": "wall", "col": start.x, "row": start.y, "placed": false})
				walls_tilemap.set_cell(gp, WALL_SOURCE_ID, Vector2i(0, 0))
				_push_undo({"kind": "wall", "col": gp.x, "row": gp.y, "placed": true})
				_commit_drag_undo_batch()
			else:
				# Invalid drop — restore the original wall cell
				walls_tilemap.set_cell(start, WALL_SOURCE_ID, Vector2i(0, 0))
	elif _obj_drag_node != null and is_instance_valid(_obj_drag_node):
		# Restore the real object that was hidden during the drag
		_obj_drag_node.visible = true
		if _obj_drag_active:
			var gp = world_to_grid(get_global_mouse_position())
			if gp != _obj_drag_start_gp:
				_move_object_to(_obj_drag_node, gp, true)
			else:
				_select_object(_obj_drag_node)
		else:
			_select_object(_obj_drag_node)
	_obj_drag_node = null
	_obj_drag_is_wall = false
	_obj_drag_active = false

func _move_object_to(node: Node, new_gp: Vector2i, push_to_undo: bool) -> void:
	if new_gp.x < 0 or new_gp.x >= PLAY_COLS or new_gp.y < 0 or new_gp.y >= PLAY_ROWS:
		return
	# Cannot drop objects on top of walls
	if walls_tilemap.get_cell_source_id(new_gp) >= 0 or border_walls_tilemap.get_cell_source_id(new_gp) >= 0:
		return
	var old_gp = Vector2i(-1, -1)
	for entry in placed_objects:
		if entry.node == node:
			old_gp = Vector2i(entry.col, entry.row)
			break
	if old_gp.x < 0 or old_gp == new_gp:
		return
	# Check if destination is occupied (only allow Key on top of a destructible)
	var existing = _object_at(new_gp)
	if existing != null and existing != node:
		var drag_type = _type_of(node)
		var existing_type = _type_of(existing)
		if not (drag_type == "Key" and existing_type in ["BreakableWall", "DustPile"]):
			return
	for entry in placed_objects:
		if entry.node == node:
			entry.col = new_gp.x
			entry.row = new_gp.y
			break
	node.position = grid_to_world(new_gp)
	if node.get("start_grid_pos") != null:
		node.start_grid_pos = new_gp
	if node.get("grid_pos") != null:
		node.grid_pos = new_gp
	if push_to_undo:
		_push_undo({"kind": "move_obj", "node": node,
					"from_col": old_gp.x, "from_row": old_gp.y,
					"to_col": new_gp.x, "to_row": new_gp.y})

# ──────────────────────────────────────────────
#  PassBlock visibility helper
# ──────────────────────────────────────────────
func _make_passblock_visible(node: Node, type: String) -> void:
	if type == "PassBlock" and node.has_node("Sprite2D"):
		var spr = node.get_node("Sprite2D")
		spr.visible = true
		spr.modulate = Color(1, 1, 1, 0.6)

# ──────────────────────────────────────────────
#  Ghost sprite helpers
# ──────────────────────────────────────────────
func _apply_ghost_texture(type: String) -> void:
	_apply_ghost_texture_to(ghost_sprite, type)

func _apply_ghost_texture_to(spr: Sprite2D, type: String) -> void:
	var tex_path = PALETTE_SPRITES.get(type, "")
	if tex_path == "":
		spr.texture = null
		return
	var raw_tex = load(tex_path) as Texture2D
	var gw = raw_tex.get_width()
	var gh = raw_tex.get_height()
	if type == "KeyDoor":
		# Show the full 32×42 first frame, bottom-anchored
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, 32, 42)
		spr.texture = raw_tex
		spr.scale = Vector2.ONE
	elif type == "Capacitor":
		# Show the first 32×48 frame, bottom-anchored
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, 32, 48)
		spr.texture = raw_tex
		spr.scale = Vector2.ONE
	elif type == "BounceEnemy":
		# Show the full 64×64 sprite (positioned bottom-center in _ghost_position_for)
		spr.region_enabled = false
		spr.texture = raw_tex
		spr.scale = Vector2.ONE
	elif gw > 32 or gh > 32:
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, 32, 32)
		spr.texture = raw_tex
		spr.scale = Vector2.ONE
	else:
		spr.region_enabled = false
		spr.texture = raw_tex
		spr.scale = Vector2(TILE_SIZE / float(gw), TILE_SIZE / float(gh))

func _ghost_position_for(type: String, gp: Vector2i) -> Vector2:
	var pos = grid_to_world(gp)
	if type == "KeyDoor":
		# 42px-tall sprite, bottom aligned to tile bottom (32 - 42 = -10)
		pos.y -= 10
	elif type == "Capacitor":
		# 48px-tall sprite, bottom aligned to tile bottom (32 - 48 = -16)
		pos.y -= 16
	elif type == "BounceEnemy":
		# 64×64 sprite: center horizontally on the tile and raise it so its
		# bottom-center sits at the tile bottom-center (-16 x, -32 y).
		pos.x -= 16
		pos.y -= 32
	return pos
