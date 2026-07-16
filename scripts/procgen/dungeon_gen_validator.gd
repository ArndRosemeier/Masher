class_name DungeonGenValidator
extends RefCounted
## Structural checks for a built hybrid dungeon (modules already in the tree).
## Returns error strings; empty means OK. Loud on purpose — no soft skips.
##
## Perimeter rule: every walkable edge cell must be either a paired doorway or a
## baked DoorSeal. RoomBaker.seal_closed_edges turns unused exterior floors into
## `#` before bake so the F1 map matches 3D walls.


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
	errors.append_array(_validate_perimeter(rooms, model))
	errors.append_array(_validate_exterior_egress(rooms, model))
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
	if players != 1:
		errors.append("expected exactly 1 player_spawn, got %d" % players)

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
	var occ: Dictionary = {} ## Vector3i(gx, level, gz) -> RoomModule
	for room in rooms:
		var fp := room.spec.footprint_cells()
		for ly in room.spec.layer_count():
			var lv := room.vertical_level + ly
			for z in fp.y:
				for x in fp.x:
					var key := Vector3i(room.grid_cell.x + x, lv, room.grid_cell.y + z)
					if occ.has(key):
						var other: RoomModule = occ[key] as RoomModule
						if _carve_overlap_allowed(room, other):
							continue
						errors.append(
							"overlap at grid %s between %s and %s"
							% [str(key), other.module_id, room.module_id]
						)
					else:
						occ[key] = room
	return errors


static func _carve_overlap_allowed(a: RoomModule, b: RoomModule) -> bool:
	## Intentional CarveMerger unions may share footprint cells.
	return a.has_meta("carve_ok") and b.has_meta("carve_ok")


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


static func _validate_perimeter(rooms: Array[RoomModule], model: DungeonMapModel) -> PackedStringArray:
	## Contract with RoomBaker._add_doorframes: closed faces seal every walkable
	## edge cell; open faces leave exactly one doorway (paired) and seal the rest.
	var errors: PackedStringArray = []
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	for room in rooms:
		var spec: RoomSpec = room.spec
		var origin := _room_origin_cells(room)
		for dir in dirs:
			for level in spec.layer_count():
				var edge := _edge_walkable_cells(spec, level, dir)
				if edge.is_empty():
					continue
				var world_floor := room.vertical_level + level
				var face_open := _face_open(spec, dir, level)
				if face_open:
					var doorways := _doorway_cells_for_face(spec, dir, level, edge)
					for cell in edge:
						var seal_name := _seal_node_name(dir, level, cell)
						var has_seal := room.get_node_or_null(seal_name) != null
						if doorways.has(cell):
							if has_seal:
								errors.append(
									"%s L%d %s doorway %s is sealed (should be open)"
									% [room.module_id, world_floor, ModuleContract.dir_name(dir), str(cell)]
								)
							var world_cell := Vector2i(origin.x + cell.x, origin.y + cell.y)
							if not _has_paired_door(model, room.module_id, dir, world_floor, world_cell):
								errors.append(
									"%s L%d %s doorway %s has no paired peer (opens into abyss)"
									% [room.module_id, world_floor, ModuleContract.dir_name(dir), str(cell)]
								)
						elif not has_seal:
							errors.append(
								"%s L%d %s edge cell %s missing DoorSeal (non-doorway on open face)"
								% [room.module_id, world_floor, ModuleContract.dir_name(dir), str(cell)]
							)
				else:
					for cell in edge:
						var seal_name2 := _seal_node_name(dir, level, cell)
						if room.get_node_or_null(seal_name2) == null:
							errors.append(
								"%s L%d %s edge cell %s missing DoorSeal (closed face opens into abyss)"
								% [room.module_id, world_floor, ModuleContract.dir_name(dir), str(cell)]
							)
	return errors


static func _validate_exterior_egress(
	rooms: Array[RoomModule],
	model: DungeonMapModel
) -> PackedStringArray:
	## Map-level: any walkable cell whose cardinal neighbor is void must be a
	## paired doorway or have a DoorSeal. Module ids are not unique (many
	## stair_test copies), so ownership is resolved by footprint containment.
	var errors: PackedStringArray = []
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	var dir_delta: Dictionary = {
		ModuleContract.Dir.N: Vector2i(0, -1),
		ModuleContract.Dir.E: Vector2i(1, 0),
		ModuleContract.Dir.S: Vector2i(0, 1),
		ModuleContract.Dir.W: Vector2i(-1, 0),
	}

	for floor_index in model.floor_list:
		var layer: DungeonMapModel.FloorLayer = model.floors.get(floor_index) as DungeonMapModel.FloorLayer
		if layer == null:
			continue
		for key_variant in layer.cells.keys():
			var cell: Vector2i = key_variant
			if not _is_traversable(model, floor_index, cell):
				continue
			for dir in dirs:
				var delta: Vector2i = dir_delta[dir]
				var neighbor: Vector2i = cell + delta
				## Authored voids inside a footprint are stamped as ' '; only a
				## missing map cell is true exterior abyss.
				if _map_has_cell(model, floor_index, neighbor):
					continue
				if _has_paired_door_at(model, dir, floor_index, cell):
					continue
				var room := _room_containing_cell(rooms, floor_index, cell)
				if room == null:
					errors.append(
						"F%d cell %s faces void %s with no containing module"
						% [floor_index, str(cell), ModuleContract.dir_name(dir)]
					)
					continue
				var origin := _room_origin_cells(room)
				var local := Vector2i(cell.x - origin.x, cell.y - origin.y)
				var local_level := floor_index - room.vertical_level
				var seal_name := _seal_node_name(dir, local_level, local)
				if room.get_node_or_null(seal_name) == null:
					errors.append(
						"F%d cell %s (%s @%s) faces abyss to the %s — no paired door and no DoorSeal"
						% [
							floor_index,
							str(cell),
							room.module_id,
							str(room.grid_cell),
							ModuleContract.dir_name(dir),
						]
					)
	return errors


static func _room_containing_cell(
	rooms: Array[RoomModule],
	floor_index: int,
	cell: Vector2i
) -> RoomModule:
	for room in rooms:
		var spec: RoomSpec = room.spec
		if spec == null:
			continue
		var local_level := floor_index - room.vertical_level
		if local_level < 0 or local_level >= spec.layer_count():
			continue
		var origin := _room_origin_cells(room)
		var local := Vector2i(cell.x - origin.x, cell.y - origin.y)
		if not spec.in_bounds(local.x, local.y):
			continue
		if RoomCells.is_walkable(spec.get_cell(local_level, local.x, local.y)):
			return room
	return null


static func _map_has_cell(model: DungeonMapModel, floor_index: int, cell: Vector2i) -> bool:
	var layer: DungeonMapModel.FloorLayer = model.floors.get(floor_index) as DungeonMapModel.FloorLayer
	return layer != null and layer.has_cell(cell)


static func _face_open(spec: RoomSpec, dir: ModuleContract.Dir, level: int) -> bool:
	## Must match RoomBaker._face_open + open_dirs gate.
	if dir not in spec.open_dirs:
		return false
	if spec.open_faces.is_empty():
		return true
	var key := Vector2i(dir as int, level)
	for face_variant in spec.open_faces:
		if (face_variant as Vector2i) == key:
			return true
	return false


static func _edge_walkable_cells(spec: RoomSpec, level: int, dir: ModuleContract.Dir) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	match dir:
		ModuleContract.Dir.E:
			for z in spec.depth:
				if RoomCells.is_walkable(spec.get_cell(level, spec.width - 1, z)):
					cells.append(Vector2i(spec.width - 1, z))
		ModuleContract.Dir.W:
			for z in spec.depth:
				if RoomCells.is_walkable(spec.get_cell(level, 0, z)):
					cells.append(Vector2i(0, z))
		ModuleContract.Dir.S:
			for x in spec.width:
				if RoomCells.is_walkable(spec.get_cell(level, x, spec.depth - 1)):
					cells.append(Vector2i(x, spec.depth - 1))
		ModuleContract.Dir.N:
			for x in spec.width:
				if RoomCells.is_walkable(spec.get_cell(level, x, 0)):
					cells.append(Vector2i(x, 0))
	return cells


static func _pick_doorway_cell(spec: RoomSpec, candidates: Array[Vector2i]) -> Vector2i:
	assert(not candidates.is_empty(), "DungeonGenValidator: doorway pick requires candidates")
	var mid := Vector2(float(spec.width) * 0.5, float(spec.depth) * 0.5)
	var best := candidates[0]
	var best_d := INF
	for c in candidates:
		var d := Vector2(float(c.x) + 0.5, float(c.y) + 0.5).distance_squared_to(mid)
		if d < best_d:
			best_d = d
			best = c
	return best


static func _doorway_cells_for_face(
	spec: RoomSpec,
	dir: ModuleContract.Dir,
	level: int,
	edge: Array[Vector2i]
) -> Dictionary:
	var out: Dictionary = {}
	var key := Vector2i(dir as int, level)
	if spec.doorway_cells.has(key):
		for cell_variant in spec.doorway_cells[key] as Array:
			out[cell_variant as Vector2i] = true
		if not out.is_empty():
			return out
	if not edge.is_empty():
		out[_pick_doorway_cell(spec, edge)] = true
	return out


static func _seal_node_name(dir: ModuleContract.Dir, level: int, cell: Vector2i) -> String:
	return "DoorSeal_%s_L%d_%d_%d" % [ModuleContract.dir_name(dir), level, cell.x, cell.y]


static func _room_origin_cells(room: RoomModule) -> Vector2i:
	var cs := room.spec.cell_size
	return Vector2i(
		int(round(room.position.x / cs)),
		int(round(room.position.z / cs))
	)


static func _has_paired_door(
	model: DungeonMapModel,
	module_id: StringName,
	dir: ModuleContract.Dir,
	floor_index: int,
	world_cell: Vector2i
) -> bool:
	var id := String(module_id)
	for door in model.door_links:
		if not door.paired:
			continue
		if door.floor_index != floor_index:
			continue
		if door.dir != dir:
			continue
		if door.module_id != id:
			continue
		if door.world_cell != world_cell:
			continue
		return true
	return false


static func _has_paired_door_at(
	model: DungeonMapModel,
	dir: ModuleContract.Dir,
	floor_index: int,
	world_cell: Vector2i
) -> bool:
	for door in model.door_links:
		if not door.paired:
			continue
		if door.floor_index != floor_index:
			continue
		if door.dir != dir:
			continue
		if door.world_cell == world_cell:
			return true
	return false


static func _validate_reachability(
	root: Node3D,
	model: DungeonMapModel,
	rooms: Array[RoomModule]
) -> PackedStringArray:
	var errors: PackedStringArray = []
	var spawn := _first_under(root, ModuleContract.GROUP_PLAYER_SPAWN)
	if spawn == null:
		errors.append("no player_spawn marker for reachability")
		return errors

	var start_cell := DungeonMapModel.player_world_cell(spawn, model.cell_size)
	var start_floor := DungeonMapModel.player_world_floor(spawn, model.level_height)

	if not _floor_has_walkable(model, start_floor, start_cell):
		## Marker may sit slightly above floor; snap to nearest walkable on that floor.
		start_cell = _nearest_walkable(model, start_floor, start_cell)

	if start_cell.x <= -99990:
		errors.append("player spawn not on any walkable map cell (floor %d)" % start_floor)
		return errors

	var reached := _flood(model, start_floor, start_cell)

	## Every module must contribute at least one reached walkable cell.
	for room in rooms:
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
