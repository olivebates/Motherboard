extends Node2D

const TILE_SIZE := 32
const WORLD_OFFSET := 0
const ROOM_WIDTH := 25
const ROOM_HEIGHT := 12
const ROOM_PIXEL_WIDTH := ROOM_WIDTH * TILE_SIZE
const ROOM_PIXEL_HEIGHT := ROOM_HEIGHT * TILE_SIZE
const CAMERA_TWEEN_DURATION := 0.25
const CAMERA_MARGIN := Vector2(16.0, 16.0)
# Pushable-object room bounds, asymmetric per edge. Positive = inset (block must stay
# that many px inside the border); negative = outset (block may extend that many px
# past the border). Left/top use NEAR, right/bottom use FAR.
const PUSH_ROOM_MARGIN_NEAR := 1.0    # left/top: 1px in from the border (edge tile off-limits)
const PUSH_ROOM_MARGIN_FAR := -1.0    # right/bottom: 1px past the border (edge tile reachable)

@onready var wall_tilemap: TileMapLayer = $Walls
@export var pass_tilemap: TileMapLayer

var current_room := Vector2i(0, 0)
var room_entry_positions: Dictionary = {}
var _cam_tween: Tween = null
var _shake_amount := 0.0
var _resetting := false
var _last_push = null
var _undo_push = null

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
	"enemy_doors",
	"nanodroids",
	"capacitors",
]

func _ready() -> void:
	_setup_y_sort_children()
	current_room = Vector2i(
		floori(float(player.grid_pos.x) / ROOM_WIDTH),
		floori(float(player.grid_pos.y) / ROOM_HEIGHT)
	)
	room_entry_positions[current_room] = player.grid_pos
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
	camera.position = _room_center(current_room)
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
		var post_splash_color := modulate
		modulate = Color.WHITE
		splash.tree_exited.connect(func(): modulate = post_splash_color)
	_setup_settings_button()


var _settings_btn: Button = null
var _settings_canvas: CanvasLayer = null
var _settings_panel: Control = null
var _settings_panel_bg: StyleBoxFlat = null
var _dim_btn: Button = null
var _settings_open: bool = false
var _settings_tween: Tween = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _confirm_panel: Control = null
var _settings_btn_styles: Array[StyleBoxFlat] = []
var _settings_hover_styles: Array[StyleBoxFlat] = []
var _settings_btns: Array[Button] = []
var _settings_labels: Array[Label] = []
var _settings_seps: Array[HSeparator] = []
var _settings_slider_fills: Array[StyleBoxFlat] = []
var _settings_slider_tracks: Array[StyleBoxFlat] = []
var _settings_sliders: Array[HSlider] = []
var _settings_outer_bg: StyleBoxFlat = null
var _last_btn_color := Color.WHITE

class _EscapeHandler extends Node:
	var main_ref: Node
	func _unhandled_input(event: InputEvent) -> void:
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		if event.keycode != KEY_ESCAPE:
			return
		if main_ref._settings_open:
			main_ref._close_settings()
		elif not main_ref.player.movement_locked:
			main_ref._open_settings()
		get_viewport().set_input_as_handled()
const _PANEL_W := 260.0
const _PANEL_H := 238.0
const _PANEL_OPEN_X = (800.0 - _PANEL_W) / 2.0
const _PANEL_Y = (384.0 - _PANEL_H) / 2.0
const _PANEL_CLOSED_X = 820.0

func _setup_settings_button() -> void:
	_settings_canvas = CanvasLayer.new()
	_settings_canvas.layer = 60
	_settings_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_settings_canvas)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", 2)
	row.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_canvas.add_child(row)

	_settings_btn = _make_ui_button("Settings")
	_settings_btn.pressed.connect(_open_settings)
	row.add_child(_settings_btn)

	_dim_btn = Button.new()
	_dim_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_dim_btn.focus_mode = Control.FOCUS_NONE
	_dim_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim_style := StyleBoxFlat.new()
	dim_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_dim_btn.add_theme_stylebox_override("normal", dim_style)
	_dim_btn.add_theme_stylebox_override("hover", dim_style)
	_dim_btn.add_theme_stylebox_override("pressed", dim_style)
	_dim_btn.add_theme_stylebox_override("focus", dim_style)
	_dim_btn.visible = false
	_dim_btn.pressed.connect(_close_settings)
	_settings_canvas.add_child(_dim_btn)

	var esc_handler := _EscapeHandler.new()
	esc_handler.main_ref = self
	esc_handler.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_canvas.add_child(esc_handler)

	_build_settings_panel()
	_refresh_settings_colors(modulate)

func _make_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(1)
	return s

func _make_ui_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
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
	_settings_btn_styles.append_array([sn, sp, sf])
	_settings_hover_styles.append(sh)
	_settings_btns.append(btn)
	return btn

func _refresh_settings_colors(c: Color) -> void:
	for s in _settings_btn_styles:
		s.border_color = c
	for s in _settings_hover_styles:
		s.bg_color = c
		s.border_color = c
	for btn in _settings_btns:
		if not is_instance_valid(btn):
			continue
		btn.add_theme_color_override("font_color", c)
		btn.add_theme_color_override("font_pressed_color", c)
		btn.add_theme_color_override("font_focus_color", c)
	if _settings_panel_bg != null:
		_settings_panel_bg.border_color = c
	for lbl in _settings_labels:
		if is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color", c)
	for sep in _settings_seps:
		if is_instance_valid(sep):
			sep.modulate = c
	for s in _settings_slider_fills:
		s.bg_color = c
	for s in _settings_slider_tracks:
		s.bg_color = Color(c.r, c.g, c.b, 0.25)
		s.border_color = Color(c.r, c.g, c.b, 0.5)
	if not _settings_sliders.is_empty():
		var grabber = _make_grabber_icon(c)
		for slider in _settings_sliders:
			if is_instance_valid(slider):
				slider.add_theme_icon_override("grabber", grabber)
				slider.add_theme_icon_override("grabber_highlight", grabber)
				slider.add_theme_icon_override("grabber_disabled", grabber)
	if _settings_outer_bg != null:
		_settings_outer_bg.border_color = c

func _make_grabber_icon(c: Color) -> ImageTexture:
	var radius := 5
	var size := radius * 2 + 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size) * 0.5, float(size) * 0.5)
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
			img.set_pixel(x, y, c if d <= float(radius) else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

func _build_settings_panel() -> void:
	_settings_panel = Control.new()
	_settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_panel.position = Vector2(_PANEL_CLOSED_X, _PANEL_Y)
	_settings_panel.custom_minimum_size = Vector2(_PANEL_W, _PANEL_H)
	_settings_panel.size = Vector2(_PANEL_W, _PANEL_H)

	# Outermost border: 2px main color
	_settings_outer_bg = StyleBoxFlat.new()
	_settings_outer_bg.bg_color = Color.BLACK
	_settings_outer_bg.border_color = modulate
	_settings_outer_bg.set_border_width_all(2)
	_settings_outer_bg.set_content_margin_all(2)
	var panel_outer := PanelContainer.new()
	panel_outer.process_mode = Node.PROCESS_MODE_ALWAYS
	panel_outer.add_theme_stylebox_override("panel", _settings_outer_bg)
	panel_outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(panel_outer)

	# Middle border: 1px black
	var mid_bg := StyleBoxFlat.new()
	mid_bg.bg_color = Color.BLACK
	mid_bg.border_color = Color.BLACK
	mid_bg.set_border_width_all(1)
	mid_bg.set_content_margin_all(1)
	var panel_mid := PanelContainer.new()
	panel_mid.process_mode = Node.PROCESS_MODE_ALWAYS
	panel_mid.add_theme_stylebox_override("panel", mid_bg)
	panel_outer.add_child(panel_mid)

	# Inner border: 2px main color + content padding
	_settings_panel_bg = StyleBoxFlat.new()
	_settings_panel_bg.bg_color = Color.BLACK
	_settings_panel_bg.border_color = modulate
	_settings_panel_bg.set_border_width_all(2)
	_settings_panel_bg.set_content_margin_all(10)
	var panel_inner := PanelContainer.new()
	panel_inner.process_mode = Node.PROCESS_MODE_ALWAYS
	panel_inner.add_theme_stylebox_override("panel", _settings_panel_bg)
	panel_mid.add_child(panel_inner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel_inner.add_child(vbox)

	# Title row with X close button
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", modulate)
	_settings_labels.append(title)
	title_row.add_child(title)

	var close_btn := _make_ui_button("✕")
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(_close_settings)
	title_row.add_child(close_btn)
	close_btn.resized.connect(func():
		var h = close_btn.size.y
		if h > 0 and close_btn.custom_minimum_size.x != h:
			close_btn.custom_minimum_size = Vector2(h, h)
	)

	var sep1 := HSeparator.new()
	sep1.modulate = modulate
	_settings_seps.append(sep1)
	vbox.add_child(sep1)

	vbox.add_child(_make_slider_row("Music Volume", AudioManager.get_music_volume(), func(v): AudioManager.set_music_volume(v), true))
	vbox.add_child(_make_slider_row("SFX Volume", AudioManager.get_sfx_volume(), func(v): AudioManager.set_sfx_volume(v), false))

	var sep2 := HSeparator.new()
	sep2.modulate = modulate
	_settings_seps.append(sep2)
	vbox.add_child(sep2)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	var export_btn := _make_ui_button("Export Save")
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.pressed.connect(_on_export_save_pressed)
	save_row.add_child(export_btn)
	var import_btn := _make_ui_button("Import Save")
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_btn.pressed.connect(_on_import_save_pressed)
	save_row.add_child(import_btn)
	vbox.add_child(save_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var sep3 := HSeparator.new()
	sep3.modulate = modulate
	_settings_seps.append(sep3)
	vbox.add_child(sep3)

	var del_btn := _make_ui_button("Delete Save File")
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.pressed.connect(_on_delete_save_pressed)
	vbox.add_child(del_btn)

	_settings_panel.visible = false
	_settings_canvas.add_child(_settings_panel)

func _make_slider_row(label_text: String, initial_value: float, on_change: Callable, is_music: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", modulate)
	lbl.custom_minimum_size.x = 88
	_settings_labels.append(lbl)
	row.add_child(lbl)

	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(modulate.r, modulate.g, modulate.b, 0.25)
	track_style.border_color = Color(modulate.r, modulate.g, modulate.b, 0.5)
	track_style.set_border_width_all(1)
	_settings_slider_tracks.append(track_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = modulate
	_settings_slider_fills.append(fill_style)

	var slider := HSlider.new()
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 14
	slider.focus_mode = Control.FOCUS_NONE
	slider.add_theme_stylebox_override("slider", track_style)
	slider.add_theme_stylebox_override("grabber_area", fill_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_style)
	slider.value_changed.connect(on_change)
	if is_music:
		_music_slider = slider
	else:
		_sfx_slider = slider
		slider.drag_ended.connect(func(_changed: bool): AudioManager.play_sfx("plant_stake"))
	_settings_sliders.append(slider)
	row.add_child(slider)

	return row

func _open_settings() -> void:
	if _settings_open or _resetting:
		return
	_settings_open = true
	player.lock_movement()
	get_tree().paused = true
	_dim_btn.visible = true
	_settings_panel.visible = true
	if _music_slider != null:
		_music_slider.value = AudioManager.get_music_volume()
	if _sfx_slider != null:
		_sfx_slider.value = AudioManager.get_sfx_volume()
	if _settings_tween:
		_settings_tween.kill()
	_settings_tween = _settings_panel.create_tween()
	_settings_tween.set_ease(Tween.EASE_OUT)
	_settings_tween.set_trans(Tween.TRANS_SINE)
	_settings_tween.tween_property(_settings_panel, "position:x", _PANEL_OPEN_X, 0.25)

func _close_settings() -> void:
	if not _settings_open:
		return
	if _confirm_panel != null:
		_confirm_panel.queue_free()
		_confirm_panel = null
	if _settings_tween:
		_settings_tween.kill()
	_settings_tween = _settings_panel.create_tween()
	_settings_tween.set_ease(Tween.EASE_IN)
	_settings_tween.set_trans(Tween.TRANS_SINE)
	_settings_tween.tween_property(_settings_panel, "position:x", _PANEL_CLOSED_X, 0.2)
	_settings_tween.tween_callback(func():
		_settings_panel.visible = false
		_dim_btn.visible = false
		_settings_open = false
		get_tree().paused = false
		player.unlock_movement()
	)

func _on_export_save_pressed() -> void:
	var encoded = SaveManager.export_save_string()
	var dialog := AcceptDialog.new()
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "Export Save"
	var vbox := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Copy this save code:"
	lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(lbl)
	var edit := TextEdit.new()
	edit.text = encoded if encoded != "" else "(no save data)"
	edit.editable = false
	edit.custom_minimum_size = Vector2(440, 100)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(edit)
	dialog.add_child(vbox)
	_settings_canvas.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _on_import_save_pressed() -> void:
	var dialog := AcceptDialog.new()
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = "Import Save"
	dialog.get_ok_button().text = "Import"
	var vbox := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Paste save code:"
	lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(lbl)
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(440, 100)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(edit)
	dialog.add_child(vbox)
	_settings_canvas.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		var encoded = edit.text.strip_edges()
		if encoded == "":
			return
		get_tree().paused = false
		if not SaveManager.import_save_string(encoded):
			get_tree().paused = true
	)
	dialog.canceled.connect(dialog.queue_free)

func _on_delete_save_pressed() -> void:
	if _confirm_panel != null:
		return

	var c := modulate
	_confirm_panel = Control.new()
	_confirm_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cp_bg := StyleBoxFlat.new()
	cp_bg.bg_color = Color.BLACK
	cp_bg.border_color = c
	cp_bg.set_border_width_all(2)
	cp_bg.set_content_margin_all(12)

	var cp_panel := PanelContainer.new()
	cp_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	cp_panel.add_theme_stylebox_override("panel", cp_bg)
	cp_panel.custom_minimum_size = Vector2(220, 90)
	cp_panel.size = Vector2(220, 90)
	cp_panel.position = Vector2((800.0 - 220.0) / 2.0, (384.0 - 90.0) / 2.0)
	_confirm_panel.add_child(cp_panel)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 8)
	cp_panel.add_child(cvbox)

	var warn := Label.new()
	warn.text = "Delete all save data?"
	warn.add_theme_font_size_override("font_size", 10)
	warn.add_theme_color_override("font_color", c)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cvbox.add_child(warn)

	var warn2 := Label.new()
	warn2.text = "This cannot be undone."
	warn2.add_theme_font_size_override("font_size", 9)
	warn2.add_theme_color_override("font_color", c)
	warn2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cvbox.add_child(warn2)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cvbox.add_child(btn_row)

	var yes_btn := _make_ui_button("Yes, Delete")
	yes_btn.pressed.connect(_confirm_delete_save)
	btn_row.add_child(yes_btn)

	var no_btn := _make_ui_button("Cancel")
	no_btn.pressed.connect(func():
		_confirm_panel.queue_free()
		_confirm_panel = null
	)
	btn_row.add_child(no_btn)

	_settings_canvas.add_child(_confirm_panel)

func _confirm_delete_save() -> void:
	get_tree().paused = false
	SaveManager.delete_active_save()


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
	_shake_amount = lerpf(_shake_amount, 0.0, 9.0 * delta)
	camera.offset = Vector2(randf_range(-1.6, 1.6), randf_range(-1.6, 1.6)) * _shake_amount
	_update_tab_label()
	if modulate != _last_btn_color:
		_last_btn_color = modulate
		_refresh_settings_colors(modulate)

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
	if event is InputEventKey and event.pressed and not event.echo and not player.movement_locked:
		if event.keycode == KEY_Z:
			if _last_push != null:
				undo_last_push()
			elif _undo_push != null:
				redo_last_push()
	if event is InputEventKey and event.pressed and not event.echo:
		if Input.is_key_pressed(KEY_K) and Input.is_key_pressed(KEY_C):
			var other_keys = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_R,
							  KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
			var any_other = other_keys.any(func(k): return Input.is_key_pressed(k))
			if not any_other:
				SaveManager.save_quicksave()
				get_tree().change_scene_to_file("res://scenes/LevelEditor.tscn")

func record_push(block: Node, from_pos: Vector2i, dir: Vector2i) -> void:
	_last_push = {"block": block, "from": from_pos, "dir": dir}
	_undo_push = null

func undo_last_push() -> void:
	if _last_push == null:
		return
	var entry = _last_push
	var block = entry.block
	if not is_instance_valid(block):
		_last_push = null
		return
	var from_pos: Vector2i = entry.from
	var dir: Vector2i = entry.dir
	# Any actor (player, nanodroid, enemy) standing where the block is returning to
	# gets shoved one tile in -dir; if that tile is blocked, the undo is refused.
	var shoved := []
	for actor in _push_actors():
		if PushUtils.actor_tile(actor) == from_pos:
			shoved.append(actor)
	if not shoved.is_empty() and is_blocked(from_pos - dir):
		AudioManager.play_sfx("electric_fail")
		return
	_last_push = null
	_undo_push = entry
	var block_rect = Rect2(from_pos.x * TILE_SIZE, from_pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	for actor in shoved:
		PushUtils.displace_actor(actor, block_rect, dir)
	block.push_undo(from_pos)
	_trigger_shake(0.8)
	_update_beam()

# Actors that a returning/advancing block can shove, mirroring the player.
func _push_actors() -> Array:
	var actors := []
	if player != null and is_instance_valid(player):
		actors.append(player)
	for nd in get_tree().get_nodes_in_group("nanodroids"):
		if is_instance_valid(nd) and not nd._destroyed:
			actors.append(nd)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_dead():
			actors.append(e)
	return actors

func redo_last_push() -> void:
	if _undo_push == null:
		return
	var entry = _undo_push
	var block = entry.block
	if not is_instance_valid(block):
		_undo_push = null
		return
	var from_pos: Vector2i = entry.from
	var dir: Vector2i = entry.dir
	var dest = from_pos + dir
	if not can_push_block_to(dest):
		return
	# A block can't be redone onto a tile any actor is standing on.
	for actor in _push_actors():
		if PushUtils.actor_tile(actor) == dest:
			AudioManager.play_sfx("electric_fail")
			return
	_undo_push = null
	_last_push = entry
	block.push(dir)
	_trigger_shake(0.8)
	_update_beam()

func _reset_room() -> void:
	if _resetting:
		return
	_resetting = true
	player.lock_movement()
	AudioManager.play_sfx("character_death")
	var rx0 := current_room.x * ROOM_WIDTH
	var ry0 := current_room.y * ROOM_HEIGHT
	for fan in get_tree().get_nodes_in_group("fans"):
		var fgp: Vector2i = fan.start_grid_pos
		if fgp.x >= rx0 and fgp.x < rx0 + ROOM_WIDTH and fgp.y >= ry0 and fgp.y < ry0 + ROOM_HEIGHT:
			fan.prepare_reset()
	# Player plays its death animation in place; the static screen kicks in after the
	# 3rd frame and the world resets once the static has peaked.
	player.play_death()
	await player.death_static_cue
	reset_effect.play()
	await reset_effect.peaked
	_last_push = null
	_undo_push = null
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
	var room_solved := SaveManager.is_room_solved(current_room)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var egp := Vector2i(floori(enemy._start_pos.x / TILE_SIZE), floori(enemy._start_pos.y / TILE_SIZE))
		if egp.x >= rx0 and egp.x < rx0 + ROOM_WIDTH and egp.y >= ry0 and egp.y < ry0 + ROOM_HEIGHT:
			if enemy.is_in_group("boss_spawned_enemies"):
				enemy.queue_free()
			elif enemy.is_in_group("bounce_enemies"):
				# Bounce enemies don't respawn once killed, but a living one is moved
				# back to its starting position on any room reset.
				if not enemy.is_dead():
					enemy.reset()
			elif not room_solved:
				# Other enemies do not respawn in a completed room.
				enemy.reset()
	for dust in get_tree().get_nodes_in_group("dust_piles"):
		var dgp: Vector2i = dust.get_grid_pos()
		if dgp.x >= rx0 and dgp.x < rx0 + ROOM_WIDTH and dgp.y >= ry0 and dgp.y < ry0 + ROOM_HEIGHT:
			dust.reset()
	for turbine in get_tree().get_nodes_in_group("wind_turbines"):
		var tgp: Vector2i = turbine.get_grid_pos()
		if tgp.x >= rx0 and tgp.x < rx0 + ROOM_WIDTH and tgp.y >= ry0 and tgp.y < ry0 + ROOM_HEIGHT:
			turbine.reset()
	for switch in get_tree().get_nodes_in_group("floor_switches"):
		var sgp: Vector2i = switch.get_grid_pos()
		if sgp.x >= rx0 and sgp.x < rx0 + ROOM_WIDTH and sgp.y >= ry0 and sgp.y < ry0 + ROOM_HEIGHT:
			switch.reset()
	for edoor in get_tree().get_nodes_in_group("enemy_doors"):
		var egp: Vector2i = edoor.get_grid_pos()
		if egp.x >= rx0 and egp.x < rx0 + ROOM_WIDTH and egp.y >= ry0 and egp.y < ry0 + ROOM_HEIGHT:
			edoor.reset()
	for droid in get_tree().get_nodes_in_group("nanodroids"):
		var ngp: Vector2i = droid.start_grid_pos
		if ngp.x >= rx0 and ngp.x < rx0 + ROOM_WIDTH and ngp.y >= ry0 and ngp.y < ry0 + ROOM_HEIGHT:
			droid.reset()
	for hole in get_tree().get_nodes_in_group("holes"):
		var hgp: Vector2i = hole.get_grid_pos()
		if hgp.x >= rx0 and hgp.x < rx0 + ROOM_WIDTH and hgp.y >= ry0 and hgp.y < ry0 + ROOM_HEIGHT:
			hole.reset()
	for capacitor in get_tree().get_nodes_in_group("capacitors"):
		var cgp: Vector2i = capacitor.get_grid_pos()
		if cgp.x >= rx0 and cgp.x < rx0 + ROOM_WIDTH and cgp.y >= ry0 and cgp.y < ry0 + ROOM_HEIGHT:
			capacitor.reset()
	# Respawn under the static at its peak; reset_to() cuts the death animation short
	# if it hasn't finished playing yet.
	player.reset_to(room_entry_positions.get(current_room, Vector2i(2, 2)))
	# Reassemble at the new location by playing the death animation in reverse (3×)
	# as the static fades, then hand control back.
	await player.play_revive()
	_resetting = false
	player.unlock_movement()

func tile_rect(grid_pos: Vector2i) -> Rect2:
	return GridUtils.tile_rect(grid_pos)

func _is_static_solid(grid_pos: Vector2i, include_holes: bool = true) -> bool:
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
	for edoor in get_tree().get_nodes_in_group("enemy_doors"):
		if not edoor.is_open and edoor.get_grid_pos() == grid_pos:
			return true
	for capacitor in get_tree().get_nodes_in_group("capacitors"):
		if capacitor.get_grid_pos() == grid_pos:
			return true
	if include_holes:
		for hole in get_tree().get_nodes_in_group("holes"):
			if hole.is_solid() and hole.get_grid_pos() == grid_pos:
				return true
	return false

func _hole_at(grid_pos: Vector2i) -> Node:
	for hole in get_tree().get_nodes_in_group("holes"):
		if hole.get_grid_pos() == grid_pos:
			return hole
	return null

func is_blocked(grid_pos: Vector2i) -> bool:
	if _is_static_solid(grid_pos):
		return true
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.grid_pos == grid_pos:
			return true
	return false

func get_player_blocking_rects(area: Rect2, include_holes: bool = true) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var x0 := floori(area.position.x / TILE_SIZE)
	var x1 := floori((area.end.x - 0.001) / TILE_SIZE)
	var y0 := floori(area.position.y / TILE_SIZE)
	var y1 := floori((area.end.y - 0.001) / TILE_SIZE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var gp := Vector2i(x, y)
			if _is_static_solid(gp, include_holes):
				rects.append(tile_rect(gp))
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var block_rect: Rect2 = block.get_collision_rect()
		if area.intersects(block_rect):
			rects.append(block_rect)
	return rects

func _within_room_push_bounds(grid_pos: Vector2i) -> bool:
	# The block's 32×32 tile must sit inside its room's push bounds — inset
	# PUSH_ROOM_MARGIN_NEAR px on the left/top and PUSH_ROOM_MARGIN_FAR px on the
	# right/bottom — which keeps pushables from being shoved out through doorways.
	var room_x := floori(float(grid_pos.x) / ROOM_WIDTH)
	var room_y := floori(float(grid_pos.y) / ROOM_HEIGHT)
	var rx := WORLD_OFFSET + room_x * ROOM_PIXEL_WIDTH
	var ry := WORLD_OFFSET + room_y * ROOM_PIXEL_HEIGHT
	var left := rx + PUSH_ROOM_MARGIN_NEAR
	var top := ry + PUSH_ROOM_MARGIN_NEAR
	var right := rx + ROOM_PIXEL_WIDTH - PUSH_ROOM_MARGIN_FAR
	var bottom := ry + ROOM_PIXEL_HEIGHT - PUSH_ROOM_MARGIN_FAR
	var block_rect := Rect2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	return block_rect.position.x >= left and block_rect.position.y >= top \
			and block_rect.end.x <= right and block_rect.end.y <= bottom

func can_push_block_to(grid_pos: Vector2i) -> bool:
	if not _within_room_push_bounds(grid_pos):
		return false
	# An empty or droid-filled hole accepts a pushable object (it sinks in).
	var hole := _hole_at(grid_pos)
	if hole != null and hole.can_accept_block():
		return true
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
	return PushUtils.block_at_face(get_tree().get_nodes_in_group("push_blocks"), player_rect, dir, from_point)

func has_pass_block_at(grid_pos: Vector2i) -> bool:
	for block in get_tree().get_nodes_in_group("pass_blocks"):
		if block.get_grid_pos() == grid_pos:
			return true
	return false

func get_push_block_at(grid_pos: Vector2i) -> Node:
	return PushUtils.block_at(get_tree().get_nodes_in_group("push_blocks"), grid_pos)

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

func _transition_to_room(new_room: Vector2i, auto_unlock: bool = true) -> void:
	var direction := new_room - current_room
	room_entry_positions[new_room] = player.grid_pos + direction
	_last_push = null
	_undo_push = null

	for p in GameManager.clear_prongs():
		p["node"].queue_free()
	_update_beam()

	# Delete boss-spawned enemies in the room being left
	var old_rx0 = current_room.x * ROOM_WIDTH
	var old_ry0 = current_room.y * ROOM_HEIGHT

	for fan in get_tree().get_nodes_in_group("fans"):
		var fgp: Vector2i = fan.start_grid_pos
		if fgp.x >= old_rx0 and fgp.x < old_rx0 + ROOM_WIDTH and fgp.y >= old_ry0 and fgp.y < old_ry0 + ROOM_HEIGHT:
			fan._clear_particles()
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
	# Enemies do not respawn in a completed room.
	var entered_room_solved := SaveManager.is_room_solved(current_room)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if entered_room_solved:
			continue
		var egp := Vector2i(floori(enemy._start_pos.x / TILE_SIZE), floori(enemy._start_pos.y / TILE_SIZE))
		if egp.x >= erx0 and egp.x < erx0 + ROOM_WIDTH and egp.y >= ery0 and egp.y < ery0 + ROOM_HEIGHT:
			enemy.reset()
	for hole in get_tree().get_nodes_in_group("holes"):
		var hgp: Vector2i = hole.get_grid_pos()
		if hgp.x >= erx0 and hgp.x < erx0 + ROOM_WIDTH and hgp.y >= ery0 and hgp.y < ery0 + ROOM_HEIGHT:
			hole.reset()
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var sgp: Vector2i = block.start_grid_pos
		if sgp.x >= erx0 and sgp.x < erx0 + ROOM_WIDTH and sgp.y >= ery0 and sgp.y < ery0 + ROOM_HEIGHT:
			block.reset()

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
	if auto_unlock:
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
	await player.play_teleport()
	# Teleport-pad teleport is 30% quieter (linear) than the base electric_spawn SFX.
	AudioManager.play_sfx("electric_spawn", -3.1)

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
	_transition_to_room(room, false)
	room_entry_positions[room] = dest_gp
	await player.play_teleport(true)
	player.unlock_movement()

func teleport_between_prongs(target_center: Vector2) -> void:
	await PlayerUtils.teleport_between_prongs(player, target_center)

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
	# Swing the hammer first; the prong is only placed once the animation ends.
	await player.play_plant()
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
	GameManager.last_activator_pos = player.get_body_center()
	var path: Array = []
	if world_positions.size() == 2:
		path = _compute_beam_path(world_positions[0], world_positions[1])
	BeamUtils.apply_beam_result(electric_beam, get_tree().get_nodes_in_group("lightning_blockers"), world_positions, path)

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
	return BeamUtils.nearest_first_beam(get_tree().get_nodes_in_group("lightning_blockers"), pos_a, pos_b, nut_nodes, [pos_a])

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori((world_pos.x - WORLD_OFFSET) / TILE_SIZE),
		floori((world_pos.y - WORLD_OFFSET) / TILE_SIZE)
	)
