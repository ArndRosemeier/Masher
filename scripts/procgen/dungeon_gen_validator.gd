class_name DungeonGenValidator
extends RefCounted
## Structural checks for a built hybrid dungeon (modules already in the tree).
## Returns error strings; empty means OK. Loud on purpose — no soft skips.


static func validate(dungeon_root: Node3D) -> PackedStringArray:
	assert(dungeon_root != null, "DungeonGenValidator: dungeon_root is null")
	var errors: PackedStringArray = []
	var rooms := _collect_rooms(dungeon_root)
	if rooms.is_empty():
		errors.append("no RoomModule children")
		return errors

	errors.append_array(_validate_markers(dungeon_root, rooms))
	errors.append_array(_validate_room_specs(rooms))
	errors.append_array(_validate_no_overlap(rooms))

	var model := DungeonMapModel.build(rooms)
	if model.floor_list.is_empty():
		errors.append("map model produced no floors")
		return errors

	errors.append_array(_validate_door_links(model))
	errors.append_array(_validate_vertical_links(model))
	errors.append_array(_validate_reachability(dungeon_root, model, rooms))
	return errors


static func validate_or_assert(dungeon_root: Node3D, context: String = "DungeonGen") -> void:
	var errors := validate(dungeon_root)
	if errors.is_empty():
		return
	for e in errors:
		push_error("[%s] %s" % [context, e])
	assert(false, "%s validation failed (%d errors)" % [context, errors.size()])


static func _collect_rooms(root: Node3D) -> Array[RoomModule]:
	var out: Array[RoomModule] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is RoomModule:
			var room := n as RoomModule
			if room.spec != null:
				out.append(room)
		for c in n.get_children():
			stack.append(c)
	return out


static func _validate_markers(root: Node3D, rooms: Array[RoomModule]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var players := _count_under(root, ModuleContract.GROUP_PLAYER_SPAWN)
	var exits := _count_under(root, ModuleContract.GROUP_EXIT)
	if players != 1:
		errors.append("expected exactly 1 player_spawn, got %d" % players)
	if exits < 1:
		errors.append("expected at least 1 exit, got %d" % exits)

	for room in rooms:
		if room.module_id == &"":
			errors.append("module at %s has empty module_id" % str(room.grid_cell))
		if room.spec == null:
			errors.append("module %s has null spec" % room.module_id)
	return errors


static func _validate_room_specs(rooms: Array[RoomModule]) -> PackedStringArray:
	var errors: PackedStringArray = []
	for room in rooms:
		var want_p := false
		var want_e := false
		for level in room.spec.layer_count():
			for z in room.spec.depth:
				for x in room.spec.width:
					var k: int = room.spec.get_cell(level, x, z)
					if k == RoomCells.Kind.PLAYER:
						want_p = true
					elif k == RoomCells.Kind.EXIT:
						want_e = true
		var room_errors := RoomValidators.validate(room.spec, want_p, want_e)
		for e in room_errors:
			errors.append("%s: %s" % [room.module_id, e])
	return errors


static func _validate_no_overlap(rooms: Array[RoomModule]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var occ: Dictionary = {} ## Vector3i(gx, level, gz) -> module_id
	for room in rooms:
		var fp := room.spec.footprint_cells()
		for ly in room.spec.layer_count():
			var lv := room.vertical_level + ly
			for z in fp.y:
				for x in fp.x:
					var key := Vector3i(room.grid_cell.x + x, lv, room.grid_cell.y + z)
					if occ.has(key):
						errors.append(
							"overlap at grid %s between %s and %s"
							% [str(key), occ[key], room.module_id]
						)
					else:
						occ[key] = room.module_id
	return errors


static func _validate_door_links(model: DungeonMapModel) -> PackedStringArray:
	## Every horizontal open must face a paired peer — no door into empty space.
	var errors: PackedStringArray = []
	for door in model.door_links:
		if door.paired:
			continue
		errors.append(
			"unpaired door %s at floor %d cell %s (opens into empty space)"
			% [door.label, door.floor_index, str(door.world_cell)]
		)
	return errors


static func _validate_vertical_links(model: DungeonMapModel) -> PackedStringArray:
	var errors: PackedStringArray = []
	for link in model.vertical_links:
		if link.kind == "down" and not link.paired:
			errors.append(
				"unpaired down-stair %s (no ^ landing on floor %d)"
				% [link.label, link.to_floor]
			)
		if link.kind == "up" and not link.paired:
			errors.append(
				"up-stair %s has no upper landing on floor %d" % [link.label, link.to_floor]
			)
	return errors


static func _validate_reachability(
	root: Node3D,
	model: DungeonMapModel,
	rooms: Array[RoomModule]
) -> PackedStringArray:
	var errors: PackedStringArray = []
	var spawn := _first_under(root, ModuleContract.GROUP_PLAYER_SPAWN)
	var exit_node := _first_under(root, ModuleContract.GROUP_EXIT)
	if spawn == null or exit_node == null:
		return errors

	var start_cell := DungeonMapModel.player_world_cell(spawn, model.cell_size)
	var start_floor := DungeonMapModel.player_world_floor(spawn, model.level_height)
	var exit_cell := DungeonMapModel.player_world_cell(exit_node, model.cell_size)
	var exit_floor := DungeonMapModel.player_world_floor(exit_node, model.level_height)

	if not _floor_has_walkable(model, start_floor, start_cell):
		## Marker may sit slightly above floor; snap to nearest walkable on that floor.
		start_cell = _nearest_walkable(model, start_floor, start_cell)
	if not _floor_has_walkable(model, exit_floor, exit_cell):
		exit_cell = _nearest_walkable(model, exit_floor, exit_cell)

	if start_cell.x <= -99990:
		errors.append("player spawn not on any walkable map cell (floor %d)" % start_floor)
		return errors
	if exit_cell.x <= -99990:
		errors.append("exit not on any walkable map cell (floor %d)" % exit_floor)
		return errors

	var reached := _flood(model, start_floor, start_cell)
	var exit_key := Vector3i(exit_floor, exit_cell.x, exit_cell.y)
	if not reached.has(exit_key):
		errors.append(
			"exit unreachable from player spawn (spawn F%d %s → exit F%d %s; reached %d cells)"
			% [start_floor, str(start_cell), exit_floor, str(exit_cell), reached.size()]
		)

	## Every module must contribute at least one reached walkable cell.
	for room in rooms:
		if room.module_id == &"undercroft":
			## Optional basement — reachable only via paired D/^ ; warn if open D exists unpaired (already checked).
			continue
		var touched := false
		var origin := Vector2i(
			int(round(room.position.x / model.cell_size)),
			int(round(room.position.z / model.cell_size))
		)
		for level in room.spec.layer_count():
			var fl := room.vertical_level + level
			for z in room.spec.depth:
				for x in room.spec.width:
					if not RoomCells.is_walkable(room.spec.get_cell(level, x, z)):
						continue
					var key := Vector3i(fl, origin.x + x, origin.y + z)
					if reached.has(key):
						touched = true
						break
				if touched:
					break
			if touched:
				break
		if not touched:
			errors.append(
				"module %s @%s L%d is not reachable from spawn"
				% [room.module_id, str(room.grid_cell), room.vertical_level]
			)
	return errors


static func _flood(model: DungeonMapModel, start_floor: int, start_cell: Vector2i) -> Dictionary:
	## Keys: Vector3i(floor, wx, wz)
	var reached: Dictionary = {}
	var stack: Array[Vector3i] = [Vector3i(start_floor, start_cell.x, start_cell.y)]

	## Door adjacency: from_cell+floor -> Array of Vector3i peers
	var door_adj: Dictionary = {}
	for door in model.door_links:
		if not door.paired:
			continue
		var a := Vector3i(door.floor_index, door.world_cell.x, door.world_cell.y)
		var b := Vector3i(door.floor_index, door.peer_world_cell.x, door.peer_world_cell.y)
		_adj_add(door_adj, a, b)
		_adj_add(door_adj, b, a)

	## Vertical: every stair/shaft cell on the from-floor reaches the landing
	## (and back). Anchors alone are not enough — climb ends at the top cell.
	var vert_adj: Dictionary = {}
	for link in model.vertical_links:
		if not link.paired:
			continue
		var land := Vector3i(link.to_floor, link.to_anchor.x, link.to_anchor.y)
		var endpoints: Array[Vector2i] = link.world_cells.duplicate()
		endpoints.append(link.from_anchor)
		for c in endpoints:
			var shaft := Vector3i(link.from_floor, c.x, c.y)
			_adj_add(vert_adj, shaft, land)
			_adj_add(vert_adj, land, shaft)

	while not stack.is_empty():
		var cur: Vector3i = stack.pop_back()
		if reached.has(cur):
			continue
		var fl := cur.x
		var cell := Vector2i(cur.y, cur.z)
		if not _is_traversable(model, fl, cell):
			continue
		reached[cur] = true

		for d_variant in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var d: Vector2i = d_variant
			var n: Vector2i = cell + d
			if _is_traversable(model, fl, n):
				stack.append(Vector3i(fl, n.x, n.y))

		if door_adj.has(cur):
			for peer in door_adj[cur]:
				stack.append(peer as Vector3i)
		## Also try door from any neighboring edge cell that is a door endpoint.
		for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO]:
			var dk := Vector3i(fl, cell.x + d2.x, cell.y + d2.y)
			if door_adj.has(dk):
				for peer2 in door_adj[dk]:
					stack.append(peer2 as Vector3i)

		if vert_adj.has(cur):
			for peer3 in vert_adj[cur]:
				stack.append(peer3 as Vector3i)
		for d3 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO]:
			var vk := Vector3i(fl, cell.x + d3.x, cell.y + d3.y)
			if vert_adj.has(vk):
				for peer4 in vert_adj[vk]:
					stack.append(peer4 as Vector3i)

	return reached


static func _adj_add(adj: Dictionary, a: Vector3i, b: Vector3i) -> void:
	if not adj.has(a):
		adj[a] = []
	(adj[a] as Array).append(b)


static func _is_traversable(model: DungeonMapModel, floor_index: int, cell: Vector2i) -> bool:
	var layer: DungeonMapModel.FloorLayer = model.floors.get(floor_index) as DungeonMapModel.FloorLayer
	if layer == null or not layer.has_cell(cell):
		return false
	var ch := layer.get_char(cell)
	match ch:
		"#", " ":
			return false
		_:
			return true


static func _floor_has_walkable(model: DungeonMapModel, floor_index: int, cell: Vector2i) -> bool:
	return _is_traversable(model, floor_index, cell)


static func _nearest_walkable(
	model: DungeonMapModel,
	floor_index: int,
	center: Vector2i
) -> Vector2i:
	var layer: DungeonMapModel.FloorLayer = model.floors.get(floor_index) as DungeonMapModel.FloorLayer
	if layer == null:
		return Vector2i(-99999, -99999)
	if _is_traversable(model, floor_index, center):
		return center
	var best := Vector2i(-99999, -99999)
	var best_d := INF
	for key_variant in layer.cells.keys():
		var key: Vector2i = key_variant
		if not _is_traversable(model, floor_index, key):
			continue
		var d := Vector2(float(key.x), float(key.y)).distance_squared_to(
			Vector2(float(center.x), float(center.y))
		)
		if d < best_d:
			best_d = d
			best = key
	return best


static func _count_under(ancestor: Node, group: StringName) -> int:
	var n := 0
	for node in ancestor.get_tree().get_nodes_in_group(group) if ancestor.is_inside_tree() else []:
		if ancestor.is_ancestor_of(node):
			n += 1
	if ancestor.is_inside_tree():
		return n
	## Offline / not-yet-in-tree: walk manually.
	n = 0
	var stack: Array[Node] = [ancestor]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_in_group(group):
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n


static func _first_under(ancestor: Node, group: StringName) -> Node3D:
	if ancestor.is_inside_tree():
		for node in ancestor.get_tree().get_nodes_in_group(group):
			if ancestor.is_ancestor_of(node):
				return node as Node3D
	var stack: Array[Node] = [ancestor]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_in_group(group):
			return node as Node3D
		for c in node.get_children():
			stack.append(c)
	return null
