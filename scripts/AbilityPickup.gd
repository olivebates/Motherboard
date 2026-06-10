extends Node2D

@export var ability: String = ""
@export var message: String = ""

var _collected := false
var _original_position: Vector2

const PICKUP_RADIUS := 16.0
const DRAW_RADIUS := 10.0

func _ready() -> void:
	add_to_group("ability_pickups")
	_original_position = position
	queue_redraw()

func _process(_delta: float) -> void:
	if _collected:
		return
	var player: Node2D = get_tree().get_first_node_in_group("players")
	if player == null:
		return
	var center := position + Vector2(16.0, 16.0)
	if center.distance_to(player.get_body_center()) <= PICKUP_RADIUS:
		_collect(player)

func _draw() -> void:
	if _collected:
		return
	draw_circle(Vector2(16.0, 16.0), DRAW_RADIUS, Color.WHITE)

func _collect(player: Node2D) -> void:
	_collected = true
	queue_redraw()

	if ability != "":
		GameManager.grant_ability(ability)

	var main: Node2D = get_tree().current_scene
	main.room_entry_positions[main.current_room] = player.grid_pos
	player.lock_movement()
	AbilityTutorial.play_intro(ability, player, main)

func reset() -> void:
	_collected = false
	queue_redraw()
