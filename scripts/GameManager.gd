extends Node

signal doors_update(id: String, open: bool)
signal shake_requested(strength: float)

var prongs: Array = []
const MAX_PRONGS := 2
var beam_blocked := false

var _abilities: Dictionary = {}

func grant_ability(ability: String) -> void:
	_abilities[ability] = true

func has_ability(ability: String) -> bool:
	return _abilities.get(ability, false)

var floor_panels: Dictionary = {}
var doors: Dictionary = {}

func register_floor_panel(grid_pos: Vector2i, id: String, id2: String = "") -> void:
	var ids: Array = [id]
	if id2 != "":
		ids.append(id2)
	floor_panels[grid_pos] = ids

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

func _panel_near(world_pos: Vector2) -> Vector2i:
	for gp in floor_panels:
		var panel_center := Vector2(gp.x * 32 + 16, gp.y * 32 + 16)
		if world_pos.distance_to(panel_center) <= PANEL_ACTIVATION_RADIUS:
			return gp
	return Vector2i(-999999, -999999)

func evaluate_puzzle() -> void:
	var ids_to_open: Array = []

	if not beam_blocked and prongs.size() == MAX_PRONGS:
		var world_a: Vector2 = prongs[0]["node"].position
		var world_b: Vector2 = prongs[1]["node"].position
		var panel_a := _panel_near(world_a)
		var panel_b := _panel_near(world_b)
		var ids_a: Array = floor_panels.get(panel_a, [])
		var ids_b: Array = floor_panels.get(panel_b, [])

		if not ids_a.is_empty() and not ids_b.is_empty() and panel_a != panel_b:
			for id in ids_a:
				if id in ids_b and id not in ids_to_open:
					ids_to_open.append(id)

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
