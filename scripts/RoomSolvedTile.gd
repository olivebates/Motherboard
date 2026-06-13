extends Node2D

var _triggered := false

func _ready() -> void:
	add_to_group("room_solved_tiles")
	$Sprite2D.visible = false
	z_index = -10
	var room = _get_room()
	if SaveManager.is_room_solved(room):
		_triggered = true

func _get_room() -> Vector2i:
	var gp = get_grid_pos()
	return Vector2i(floori(float(gp.x) / 25.0), floori(float(gp.y) / 12.0))

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func _process(_delta: float) -> void:
	if _triggered:
		return
	var main = get_tree().current_scene
	if main == null or not main.has_method("_is_static_solid"):
		return
	var player = main.player
	if player == null:
		return
	var player_gp = Vector2i(floori(player.get_body_center().x / 32.0), floori(player.get_body_center().y / 32.0))
	if player_gp == get_grid_pos():
		_trigger()

func _trigger() -> void:
	_triggered = true
	var room = _get_room()
	for tile in get_tree().get_nodes_in_group("room_solved_tiles"):
		if tile._get_room() == room and not tile._triggered:
			return
	SaveManager.notify_room_solved(room)
	AudioManager.play_sfx("snap")
	GameManager.shake_requested.emit(2.0)
