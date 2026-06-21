extends Node

signal doors_update(id: String, open: bool)
signal shake_requested(strength: float)

var prongs: Array = []
const MAX_PRONGS := 2
var beam_blocked := false
var last_activator_pos: Vector2 = Vector2.ZERO

var _abilities: Dictionary = {}

func grant_ability(ability: String) -> void:
	_abilities[ability] = true

func has_ability(ability: String) -> bool:
	return _abilities.get(ability, false)

func get_abilities() -> Dictionary:
	return _abilities.duplicate()

func set_abilities(d: Dictionary) -> void:
	_abilities = d.duplicate()

var floor_panels: Dictionary = {}
var doors: Dictionary = {}
var wind_powered_ids: Array = []
var floor_switch_ids: Array = []
var capacitor_ids: Array = []
# World-space beam points of conductors (nuts/screws) the active beam currently
# chains through. A conductor sitting on a floor panel activates that panel, same
# as a prong. Refreshed by Main/LevelEditor._update_beam each time the beam changes.
var beam_conductor_points: Array = []

func register_floor_panel(grid_pos: Vector2i, id: String, id2: String = "") -> void:
	var ids: Array = [id]
	if id2 != "":
		ids.append(id2)
	floor_panels[grid_pos] = ids

func unregister_floor_panel(grid_pos: Vector2i) -> void:
	floor_panels.erase(grid_pos)

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

func set_floor_switch(switch_id: String, active: bool) -> void:
	if active:
		if switch_id not in floor_switch_ids:
			floor_switch_ids.append(switch_id)
	else:
		floor_switch_ids.erase(switch_id)
	evaluate_puzzle()

func set_capacitor(capacitor_id: String, powered: bool) -> void:
	if powered:
		if capacitor_id not in capacitor_ids:
			capacitor_ids.append(capacitor_id)
	else:
		capacitor_ids.erase(capacitor_id)
	evaluate_puzzle()

func set_wind_power(turbine_id: String, powered: bool) -> void:
	if powered:
		if turbine_id not in wind_powered_ids:
			wind_powered_ids.append(turbine_id)
	else:
		wind_powered_ids.erase(turbine_id)
	evaluate_puzzle()

func set_beam_conductors_from_path(path: Array) -> void:
	beam_conductor_points.clear()
	for entry in path:
		if entry is Node2D and entry.has_method("get_beam_point"):
			beam_conductor_points.append(entry.get_beam_point())

func clear_scene_state() -> void:
	prongs.clear()
	doors.clear()
	floor_panels.clear()
	wind_powered_ids.clear()
	floor_switch_ids.clear()
	capacitor_ids.clear()
	beam_conductor_points.clear()
	beam_blocked = false

const PANEL_ACTIVATION_RADIUS := 24.0

func _panel_near(world_pos: Vector2) -> Vector2i:
	for gp in floor_panels:
		var panel_center := Vector2(gp.x * 32 + 16, gp.y * 32 + 16)
		if world_pos.distance_to(panel_center) <= PANEL_ACTIVATION_RADIUS:
			return gp
	return Vector2i(-999999, -999999)

func evaluate_puzzle() -> void:
	var ids_to_open: Array = []

	if not beam_blocked and prongs.size() == MAX_PRONGS \
			and is_instance_valid(prongs[0]["node"]) and is_instance_valid(prongs[1]["node"]):
		# Each prong AND each conductor (nut/screw) the beam chains through that sits
		# on a floor panel activates that panel. A door id opens when two or more
		# distinct activated panels share it (the classic case: a prong on each of two
		# panels sharing an id; now a chained nut on a panel counts the same).
		var points: Array = [prongs[0]["node"].circuit_pos, prongs[1]["node"].circuit_pos]
		points.append_array(beam_conductor_points)
		var active_panels: Array = []
		for pt in points:
			var panel := _panel_near(pt)
			if floor_panels.has(panel) and panel not in active_panels:
				active_panels.append(panel)
		var id_panel_count: Dictionary = {}
		for panel in active_panels:
			for id in floor_panels[panel]:
				id_panel_count[id] = id_panel_count.get(id, 0) + 1
		for id in id_panel_count:
			if id_panel_count[id] >= 2 and id not in ids_to_open:
				ids_to_open.append(id)

	for id in wind_powered_ids:
		if id not in ids_to_open:
			ids_to_open.append(id)

	for id in floor_switch_ids:
		if id not in ids_to_open:
			ids_to_open.append(id)

	for id in capacitor_ids:
		if id not in ids_to_open:
			ids_to_open.append(id)

	for id in doors:
		doors_update.emit(id, id in ids_to_open)

func get_prong_world_positions() -> Array:
	var positions: Array = []
	for p in prongs:
		if is_instance_valid(p["node"]):
			positions.append(p["node"].circuit_pos)
	return positions

# Prong positions plus any conductor (nut/screw) the beam chains through — every
# point that can activate a floor panel. Used by FloorPanel for its active state.
func get_activation_points() -> Array:
	var points := get_prong_world_positions()
	points.append_array(beam_conductor_points)
	return points

func get_prong_positions() -> Array:
	var positions: Array = []
	for p in prongs:
		if is_instance_valid(p["node"]):
			positions.append(p["grid_pos"])
	return positions
