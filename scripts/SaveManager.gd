extends Node

const AUTOSAVE_INTERVAL = 5.0
const SAVE_DIR = "user://"

var active_slot: int = -1
var _autosave_timer: float = 0.0
var _pending_data: Dictionary = {}
var skip_splash: bool = false

# Accumulated during gameplay (nodes that get freed need pre-death notification)
var _key_doors_opened: Array = []   # Array of [gx, gy]
var _boss_doors_opened: Array = []  # Array of [gx, gy]
var _boss_defeated: bool = false

# Status HUD
var _status_canvas: CanvasLayer = null
var _status_label: Label = null
var _status_tween: Tween = null

func notify_key_door_opened(gp: Vector2i) -> void:
	var entry = [gp.x, gp.y]
	if not _key_doors_opened.has(entry):
		_key_doors_opened.append(entry)

func notify_boss_door_opened(gp: Vector2i) -> void:
	var entry = [gp.x, gp.y]
	if not _boss_doors_opened.has(entry):
		_boss_doors_opened.append(entry)

func notify_boss_defeated() -> void:
	_boss_defeated = true

func _process(delta: float) -> void:
	if not _pending_data.is_empty():
		var main := get_tree().current_scene
		if main != null and main.is_node_ready():
			var d := _pending_data
			_pending_data = {}
			skip_splash = false
			call_deferred("_apply_load", d)
		return

	if active_slot == -1:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save(active_slot)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var digit := _keycode_to_digit(event.keycode)
	if digit == -1:
		return
	get_viewport().set_input_as_handled()
	var path := SAVE_DIR + "save_slot_%d.json" % digit
	if event.shift_pressed:
		# Delete the save file and deactivate slot
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			_show_status("Slot %d deleted" % digit)
		else:
			_show_status("Slot %d is empty" % digit)
		if active_slot == digit:
			active_slot = -1
			_autosave_timer = 0.0
		return
	if active_slot != digit:
		active_slot = digit
		_autosave_timer = 0.0
	if FileAccess.file_exists(path):
		load_slot(digit)
		_show_status("Loading slot %d..." % digit)
	else:
		_show_status("Slot %d selected (empty)" % digit)

func on_player_ready(save_enabled: bool) -> void:
	if save_enabled:
		return
	# Auto-mode: always use slot 1
	if active_slot != -1:
		return  # already set (e.g. we just loaded from slot 1)
	active_slot = 1
	_autosave_timer = 0.0
	var path := SAVE_DIR + "save_slot_1.json"
	if FileAccess.file_exists(path):
		call_deferred("load_slot", 1)

func _keycode_to_digit(keycode: Key) -> int:
	match keycode:
		KEY_1: return 1
		KEY_2: return 2
		KEY_3: return 3
		KEY_4: return 4
		KEY_5: return 5
		KEY_6: return 6
		KEY_7: return 7
		KEY_8: return 8
		KEY_9: return 9
	return -1

# ── Save ──────────────────────────────────────────────────────────────────────

func save(slot: int) -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var player = main.player

	var data := {}

	data["player_pos"] = [player.position.x, player.position.y]
	data["current_room"] = [main.current_room.x, main.current_room.y]
	data["abilities"] = GameManager.get_abilities()

	var blocks := []
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.is_in_group("boss_doors"):
			continue
		blocks.append({
			"start": [block.start_grid_pos.x, block.start_grid_pos.y],
			"current": [block.grid_pos.x, block.grid_pos.y]
		})
	data["push_blocks"] = blocks

	var keys_collected := []
	for key in get_tree().get_nodes_in_group("keys"):
		if key._collected:
			keys_collected.append([key.start_grid_pos.x, key.start_grid_pos.y])
	data["keys_collected"] = keys_collected

	data["key_doors_opened"] = _key_doors_opened.duplicate()
	data["boss_doors_opened"] = _boss_doors_opened.duplicate()
	data["boss_defeated"] = _boss_defeated

	var panels_open := []
	for panel in get_tree().get_nodes_in_group("teleport_panels"):
		if panel.is_open:
			panels_open.append([panel.get_grid_pos().x, panel.get_grid_pos().y])
	data["teleport_panels_open"] = panels_open

	var enemies_state := []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_in_group("water_boss"):
			continue
		enemies_state.append({
			"start": [enemy._start_pos.x, enemy._start_pos.y],
			"dead": enemy._dead,
			"pos": [enemy.position.x, enemy.position.y]
		})
	data["enemies"] = enemies_state

	var visited := []
	if main.map_overlay != null:
		for room in main.map_overlay.get_visited():
			var rv := room as Vector2i
			visited.append([rv.x, rv.y])
	data["map_visited"] = visited

	var file := FileAccess.open(SAVE_DIR + "save_slot_%d.json" % slot, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# ── Load ──────────────────────────────────────────────────────────────────────

func load_slot(slot: int) -> void:
	var path := SAVE_DIR + "save_slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if not result is Dictionary:
		return
	active_slot = slot
	_autosave_timer = 0.0
	_key_doors_opened = []
	_boss_doors_opened = []
	_boss_defeated = false
	_pending_data = result
	skip_splash = true
	GameManager.clear_scene_state()
	get_tree().reload_current_scene()

func _apply_load(data: Dictionary) -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	var player = main.player

	# Restore tracker state from save
	_key_doors_opened = data.get("key_doors_opened", [])
	_boss_doors_opened = data.get("boss_doors_opened", [])
	_boss_defeated = data.get("boss_defeated", false)

	# Room + camera
	var room_arr = data.get("current_room", [0, 0])
	main.current_room = Vector2i(int(room_arr[0]), int(room_arr[1]))
	main.camera.position = _room_center(main.current_room)

	# Player position + ensure movement is unlocked
	var pos_arr = data.get("player_pos", [0.0, 0.0])
	player.position = Vector2(float(pos_arr[0]), float(pos_arr[1]))
	player.unlock_movement()

	# Abilities
	var abilities = data.get("abilities", {})
	GameManager.set_abilities(abilities)

	# Clear any prongs that might exist
	GameManager.clear_prongs()

	# Push blocks / nuts — snap to saved grid position
	var saved_blocks: Array = data.get("push_blocks", [])
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.is_in_group("boss_doors"):
			continue
		var sgp = block.start_grid_pos
		for entry in saved_blocks:
			var entry_start = Vector2i(int(entry["start"][0]), int(entry["start"][1]))
			if sgp == entry_start:
				var new_gp = Vector2i(int(entry["current"][0]), int(entry["current"][1]))
				block.grid_pos = new_gp
				block.position = Vector2(new_gp.x * 32, new_gp.y * 32)
				if block._tween:
					block._tween.kill()
				block.sprite.position = Vector2.ZERO
				break

	# Keys collected
	var saved_keys: Array = data.get("keys_collected", [])
	for key in get_tree().get_nodes_in_group("keys"):
		var kgp = key.start_grid_pos
		var is_collected = false
		for sk in saved_keys:
			if Vector2i(int(sk[0]), int(sk[1])) == kgp:
				is_collected = true
				break
		if is_collected:
			key._collected = true
			key.sprite.visible = false
			key.sprite.scale = Vector2.ONE

	# KeyDoors opened — set state silently (no animation/shake)
	for door in get_tree().get_nodes_in_group("key_doors"):
		var dgp = door.get_grid_pos()
		for od in _key_doors_opened:
			if Vector2i(int(od[0]), int(od[1])) == dgp:
				door._opened = true
				door.remove_from_group("key_doors")
				door.sprite.visible = false
				break

	# TeleportPanels open
	var saved_panels: Array = data.get("teleport_panels_open", [])
	for panel in get_tree().get_nodes_in_group("teleport_panels"):
		var pgp = panel.get_grid_pos()
		for sp in saved_panels:
			if Vector2i(int(sp[0]), int(sp[1])) == pgp:
				panel.is_open = true
				panel.queue_redraw()
				break

	# BossDoors — free ones that were opened (they permanently disappear)
	for door in get_tree().get_nodes_in_group("boss_doors"):
		var dgp = door.start_grid_pos
		for bd in _boss_doors_opened:
			if Vector2i(int(bd[0]), int(bd[1])) == dgp:
				door.queue_free()
				break

	# Boss defeated
	if _boss_defeated:
		for boss in get_tree().get_nodes_in_group("water_boss"):
			if is_instance_valid(boss):
				boss.queue_free()

	# Enemies — restore position and dead/alive state
	var saved_enemies: Array = data.get("enemies", [])
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_in_group("water_boss"):
			continue
		var esp = enemy._start_pos
		for se in saved_enemies:
			var se_start = Vector2(float(se["start"][0]), float(se["start"][1]))
			if esp.distance_to(se_start) < 1.0:
				enemy.position = Vector2(float(se["pos"][0]), float(se["pos"][1]))
				enemy._visual_pos = enemy.position
				if se.get("dead", false):
					enemy._dead = true
					enemy._sprite.visible = false
				break

	# Map visited rooms
	var visited = data.get("map_visited", [])
	var visited_dict := {}
	for rv in visited:
		visited_dict[Vector2i(int(rv[0]), int(rv[1]))] = true
	if main.map_overlay != null:
		main.map_overlay.set_visited(visited_dict)

	# Sync beam state
	main._update_beam()

	_show_status("Slot %d loaded" % active_slot)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _room_center(room: Vector2i) -> Vector2:
	return Vector2(room.x * 800.0 + 416.0, room.y * 384.0 + 208.0)

func _show_status(text: String) -> void:
	if _status_canvas == null:
		_status_canvas = CanvasLayer.new()
		_status_canvas.layer = 50
		add_child(_status_canvas)
		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", 11)
		_status_label.position = Vector2(4.0, 4.0)
		_status_canvas.add_child(_status_label)
	_status_label.text = text
	_status_label.modulate = Color.WHITE
	if _status_tween:
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_interval(1.5)
	_status_tween.tween_property(_status_label, "modulate:a", 0.0, 0.5)
