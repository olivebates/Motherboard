extends Node

signal doors_update(id: String, open: bool)
signal shake_requested(strength: float)

var prongs: Array = []
const MAX_PRONGS := 2
var beam_blocked := false

var floor_panels: Dictionary = {}
var doors: Dictionary = {}

func register_floor_panel(grid_pos: Vector2i, id: String) -> void:
	floor_panels[grid_pos] = id

func register_door(door_node: Node, id: String) -> void:
	if not doors.has(id):
		doors[id] = []
	doors[id].append(door_node)

func unregister_door(door_node: Node, id: String) -> void:
	if doors.has(id):
		doors[id].erase(door_node)

func place_prong(prong_node: Node, grid_pos: Vector2i) -> void:
	prongs.append({"node": prong_node, "grid_pos": grid_pos})

func remove_prong(prong_node: Node) -> void:
	for i in range(prongs.size()):
		if prongs[i]["node"] == prong_node:
			prongs.remove_at(i)
			break

func clear_prongs() -> Array:
	var removed := prongs.duplicate()
	prongs.clear()
	return removed

const PANEL_ACTIVATION_RADIUS := 24.0

func _panel_id_near(world_pos: Vector2) -> String:
	for gp in floor_panels:
		var panel_center := Vector2(gp.x * 32 + 16, gp.y * 32 + 16)
		if world_pos.distance_to(panel_center) <= PANEL_ACTIVATION_RADIUS:
			return floor_panels[gp]
	return ""

func evaluate_puzzle() -> void:
	var ids_to_open: Array = []

	if not beam_blocked and prongs.size() == MAX_PRONGS:
		var world_a: Vector2 = prongs[0]["node"].position
		var world_b: Vector2 = prongs[1]["node"].position
		var id_a := _panel_id_near(world_a)
		var id_b := _panel_id_near(world_b)

		if id_a != "" and id_b != "" and id_a == id_b and prongs[0]["grid_pos"] != prongs[1]["grid_pos"]:
			ids_to_open.append(id_a)

	for id in doors:
		doors_update.emit(id, id in ids_to_open)

func get_prong_world_positions() -> Array:
	var positions: Array = []
	for p in prongs:
		positions.append(p["node"].position)
	return positions

func get_prong_positions() -> Array:
	var positions: Array = []
	for p in prongs:
		positions.append(p["grid_pos"])
	return positions
