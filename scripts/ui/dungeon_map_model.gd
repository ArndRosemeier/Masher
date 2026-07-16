class_name DungeonMapModel
extends RefCounted
## Pure data model: composited ASCII floors + typed links from placed RoomModule specs.
## Used by DungeonMapCanvas (F1 map) and future dungeon editor tooling.


class FloorLayer:
	var floor_index: int = 0
	var min_x: int = 0
	var min_z: int = 0
	var max_x: int = 0
	var max_z: int = 0
	## Vector2i(wx,wz) -> single ASCII char
	var cells: Dictionary = {}
	## Vector2i(wx,wz) -> module id
	var owners: Dictionary = {}

	func width() -> int:
		return max_x - min_x + 1

	func depth() -> int:
		return max_z - min_z + 1

	func has_cell(key: Vector2i) -> bool:
		return cells.has(key)

	func get_char(key: Vector2i) -> String:
		return cells.get(key, " ")


class ModuleRef:
	var module_id: String = ""
	var grid_cell: Vector2i = Vector2i.ZERO
	var vertical_level: int = 0
	var origin_cells: Vector2i = Vector2i.ZERO ## world cell of local (0,0)
	var width: int = 0
	var depth: int = 0
	var layer_count: int = 0
	var open_dirs: Array[ModuleContract.Dir] = []


class VerticalLink:
	var kind: String = "" ## "up" | "down"
	var from_floor: int = 0
	var to_floor: int = 0
	var module_id: String = ""
	var world_cells: Array[Vector2i] = []
	## Preferred draw anchors (stair tread → landing), set during pairing.
	var from_anchor: Vector2i = Vector2i(-99999, -99999)
	var to_anchor: Vector2i = Vector2i(-99999, -99999)
	var label: String = ""
	var paired: bool = false


class DoorLink:
	var dir: ModuleContract.Dir = ModuleContract.Dir.E
	var floor_index: int = 0
	var module_id: String = ""
	var world_cell: Vector2i = Vector2i.ZERO
	var peer_module_id: String = ""
	var peer_world_cell: Vector2i = Vector2i.ZERO
	var paired: bool = false
	var label: String = ""


var floors: Dictionary = {} ## int -> FloorLayer
var floor_list: Array[int] = []
var modules: Array[ModuleRef] = []
var vertical_links: Array[VerticalLink] = []
var door_links: Array[DoorLink] = []
var cell_size: float = 2.0
var level_height: float = 4.0


static func collect_modules(tree: SceneTree) -> Array[RoomModule]:
	var out: Array[RoomModule] = []
	for node in tree.get_nodes_in_group(ModuleContract.GROUP_MODULE):
		var room := node as RoomModule
		if room != null and room.spec != null:
			out.append(room)
	if not out.is_empty():
		return out
	for node in tree.root.find_children("*", "RoomModule", true, false):
		var room2 := node as RoomModule
		if room2 != null and room2.spec != null:
			out.append(room2)
	return out


static func build(module_nodes: Array) -> DungeonMapModel:
	var model := DungeonMapModel.new()
	var room_list: Array[RoomModule] = []
	for item in module_nodes:
		var room := item as RoomModule
		if room != null and room.spec != null:
			room_list.append(room)
	if room_list.is_empty():
		return model

	model.cell_size = room_list[0].spec.cell_size
	model.level_height = room_list[0].spec.layer_height

	for room in room_list:
		var spec: RoomSpec = room.spec
		var origin := _world_origin_cells(room)
		var ref := ModuleRef.new()
		ref.module_id = String(room.module_id)
		ref.grid_cell = room.grid_cell
		ref.vertical_level = room.vertical_level
		ref.origin_cells = origin
		ref.width = spec.width
		ref.depth = spec.depth
		ref.layer_count = spec.layer_count()
		ref.open_dirs = spec.open_dirs.duplicate()
		model.modules.append(ref)

		for level in spec.layer_count():
			var world_floor := room.vertical_level + level
			var layer: FloorLayer = model.floors.get(world_floor) as FloorLayer
			if layer == null:
				layer = FloorLayer.new()
				layer.floor_index = world_floor
				model.floors[world_floor] = layer
			for z in spec.depth:
				for x in spec.width:
					var kind: int = spec.get_cell(level, x, z)
					var key := Vector2i(origin.x + x, origin.y + z)
					_stamp(layer, key, RoomCells.to_char(kind), ref.module_id)

		for run in StairDetector.detect(spec):
			var link := VerticalLink.new()
			link.module_id = ref.module_id
			link.from_floor = room.vertical_level + run.level
			if run.ascending:
				link.kind = "up"
				link.to_floor = link.from_floor + 1
				link.label = "%s  S^  F%d->F%d" % [link.module_id, link.from_floor, link.to_floor]
				## Approach at bottom, emerge at top.
				link.from_anchor = Vector2i(origin.x + run.bottom().x, origin.y + run.bottom().y)
				link.to_anchor = Vector2i(origin.x + run.top().x, origin.y + run.top().y)
			else:
				link.kind = "down"
				link.to_floor = link.from_floor - 1
				link.label = "%s  Dv  F%d->F%d" % [link.module_id, link.from_floor, link.to_floor]
				link.from_anchor = Vector2i(origin.x + run.top().x, origin.y + run.top().y)
				link.to_anchor = Vector2i(origin.x + run.bottom().x, origin.y + run.bottom().y)
			for c in run.cells:
				link.world_cells.append(Vector2i(origin.x + c.x, origin.y + c.y))
			model.vertical_links.append(link)

		for dir in spec.open_dirs:
			if ModuleContract.is_vertical(dir):
				continue
			for local_level in spec.layer_count():
				if not spec.open_faces.is_empty():
					var wanted := Vector2i(dir as int, local_level)
					var allowed := false
					for face_variant in spec.open_faces:
						if (face_variant as Vector2i) == wanted:
							allowed = true
							break
					if not allowed:
						continue
				var door_locals := _find_doorway_cells(spec, local_level, dir)
				for door_local in door_locals:
					var door := DoorLink.new()
					door.dir = dir
					door.floor_index = room.vertical_level + local_level
					door.module_id = ref.module_id
					door.world_cell = Vector2i(origin.x + door_local.x, origin.y + door_local.y)
					door.label = "%s  door %s L%d" % [
						ref.module_id, ModuleContract.dir_name(dir), door.floor_index
					]
					model.door_links.append(door)

	_pair_vertical_links(model)
	_pair_door_links(model)
	## One `+` per connection (E/S side only) — avoids `++` from both doorfaces.
	for door in model.door_links:
		if not door.paired:
			continue
		if door.dir != ModuleContract.Dir.E and door.dir != ModuleContract.Dir.S:
			continue
		var door_layer: FloorLayer = model.floors.get(door.floor_index) as FloorLayer
		if door_layer != null:
			_stamp(door_layer, door.world_cell, "+", door.module_id)

	model.floor_list.clear()
	for k in model.floors.keys():
		model.floor_list.append(int(k))
	model.floor_list.sort()
	return model


static func player_world_cell(player: Node3D, cell_size: float = 2.0) -> Vector2i:
	if player == null:
		return Vector2i(-99999, -99999)
	var p := player.global_position
	return Vector2i(int(floor(p.x / cell_size)), int(floor(p.z / cell_size)))


static func player_world_floor(player: Node3D, level_height: float = 4.0) -> int:
	## Works for the player capsule (~+0.8) and spawn/exit markers (~+0.15).
	## A small positive bias stops move_and_slide sink (y ≈ -0.05) from reporting
	## the floor below.
	if player == null:
		return -99999
	return int(floor((player.global_position.y + 0.5) / level_height))


static func _world_origin_cells(room: RoomModule) -> Vector2i:
	var cs := room.spec.cell_size
	return Vector2i(
		int(round(room.position.x / cs)),
		int(round(room.position.z / cs))
	)


static func _stamp(layer: FloorLayer, key: Vector2i, ch: String, owner_id: String) -> void:
	if layer.cells.is_empty():
		layer.min_x = key.x
		layer.max_x = key.x
		layer.min_z = key.y
		layer.max_z = key.y
	else:
		layer.min_x = mini(layer.min_x, key.x)
		layer.max_x = maxi(layer.max_x, key.x)
		layer.min_z = mini(layer.min_z, key.y)
		layer.max_z = maxi(layer.max_z, key.y)
	if layer.cells.has(key):
		var prev: String = layer.cells[key]
		if _char_priority(ch) < _char_priority(prev):
			return
	layer.cells[key] = ch
	layer.owners[key] = owner_id


static func _char_priority(ch: String) -> int:
	match ch:
		"P", "E", "M":
			return 5
		"+":
			return 4 ## map door mark (overwrites floor/edge walkable)
		"S", "D", "^":
			return 3
		"#":
			return 2
		".":
			return 1 ## floor
		" ":
			return 0 ## void
	return 0


static func _pair_vertical_links(model: DungeonMapModel) -> void:
	for link in model.vertical_links:
		var dest: FloorLayer = model.floors.get(link.to_floor) as FloorLayer
		if dest == null:
			link.label += "  [no floor]"
			link.paired = false
			continue
		if link.kind == "down":
			var shaft := _find_neighbor_char(dest, link.to_anchor, "^")
			if shaft != Vector2i(-99999, -99999):
				link.to_anchor = shaft
				link.paired = true
				link.label += "  <-> ^"
			else:
				link.paired = false
				link.label += "  [unpaired]"
		else:
			## Up stairs: column above is void; land on adjacent floor on the upper panel.
			var land := _find_landing(dest, link.to_anchor)
			if land != Vector2i(-99999, -99999):
				link.to_anchor = land
				link.paired = true
			else:
				link.paired = false
				link.label += "  [no landing]"


static func _find_neighbor_char(layer: FloorLayer, center: Vector2i, ch: String) -> Vector2i:
	if layer.get_char(center) == ch:
		return center
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = center + d
		if layer.get_char(n) == ch:
			return n
	return Vector2i(-99999, -99999)


static func _find_landing(layer: FloorLayer, shaft_cell: Vector2i) -> Vector2i:
	## Prefer walkable floor next to the stair column (not void/wall).
	var best := Vector2i(-99999, -99999)
	var best_score := -1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO]:
		var n: Vector2i = shaft_cell + d
		if not layer.has_cell(n):
			continue
		var ch := layer.get_char(n)
		var score := 0
		match ch:
			".", "X", "+":
				score = 3
			"P", "E", "M":
				score = 4
			"S":
				score = 1
			"^":
				score = 2
			_:
				score = 0
		if score > best_score:
			best_score = score
			best = n
	if best_score <= 0:
		return Vector2i(-99999, -99999)
	return best


static func _pair_door_links(model: DungeonMapModel) -> void:
	## Multi-cell modules pick doorway cells at their own midpoints, so peers on a
	## shared edge can be several cells apart on the tangent axis. Pair by facing
	## + overlap on that edge, not by a tiny midpoint distance.
	for door in model.door_links:
		var opp := ModuleContract.opposite(door.dir)
		var best: DoorLink = null
		var best_d := INF
		for other in model.door_links:
			if other == door:
				continue
			if other.floor_index != door.floor_index:
				continue
			if other.dir != opp:
				continue
			if not _doors_face_across_gap(door, other):
				continue
			var d := _door_pair_distance(door, other)
			if d < best_d:
				best_d = d
				best = other
		if best != null:
			door.paired = true
			door.peer_module_id = best.module_id
			door.peer_world_cell = best.world_cell
			door.label += "  <-> %s" % best.module_id


static func _door_pair_distance(a: DoorLink, b: DoorLink) -> float:
	var ax := float(a.world_cell.x)
	var az := float(a.world_cell.y)
	var bx := float(b.world_cell.x)
	var bz := float(b.world_cell.y)
	match a.dir:
		ModuleContract.Dir.E:
			return absf(az - bz) + absf((ax + 1.0) - bx)
		ModuleContract.Dir.W:
			return absf(az - bz) + absf((ax - 1.0) - bx)
		ModuleContract.Dir.S:
			return absf(ax - bx) + absf((az + 1.0) - bz)
		ModuleContract.Dir.N:
			return absf(ax - bx) + absf((az - 1.0) - bz)
	return Vector2(ax, az).distance_to(Vector2(bx, bz))


static func _doors_face_across_gap(a: DoorLink, b: DoorLink) -> bool:
	## True when doorway cells face across the same gap on the same row/column.
	## Tangent must match exactly — slack caused "door into wall" (hole vs `#`).
	match a.dir:
		ModuleContract.Dir.E:
			return b.world_cell.x == a.world_cell.x + 1 and a.world_cell.y == b.world_cell.y
		ModuleContract.Dir.W:
			return b.world_cell.x == a.world_cell.x - 1 and a.world_cell.y == b.world_cell.y
		ModuleContract.Dir.S:
			return b.world_cell.y == a.world_cell.y + 1 and a.world_cell.x == b.world_cell.x
		ModuleContract.Dir.N:
			return b.world_cell.y == a.world_cell.y - 1 and a.world_cell.x == b.world_cell.x
	return false


static func _find_doorway_cells(spec: RoomSpec, level: int, dir: ModuleContract.Dir) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var key := Vector2i(dir as int, level)
	if spec.doorway_cells.has(key):
		for cell_variant in spec.doorway_cells[key] as Array:
			var cell: Vector2i = cell_variant
			if RoomCells.is_walkable(spec.get_cell(level, cell.x, cell.y)):
				out.append(cell)
		if not out.is_empty():
			return out
	var candidates: Array[Vector2i] = []
	match dir:
		ModuleContract.Dir.E:
			for z in spec.depth:
				if RoomCells.is_walkable(spec.get_cell(level, spec.width - 1, z)):
					candidates.append(Vector2i(spec.width - 1, z))
		ModuleContract.Dir.W:
			for z in spec.depth:
				if RoomCells.is_walkable(spec.get_cell(level, 0, z)):
					candidates.append(Vector2i(0, z))
		ModuleContract.Dir.S:
			for x in spec.width:
				if RoomCells.is_walkable(spec.get_cell(level, x, spec.depth - 1)):
					candidates.append(Vector2i(x, spec.depth - 1))
		ModuleContract.Dir.N:
			for x in spec.width:
				if RoomCells.is_walkable(spec.get_cell(level, x, 0)):
					candidates.append(Vector2i(x, 0))
	if candidates.is_empty():
		return out
	var mid := Vector2(float(spec.width) * 0.5, float(spec.depth) * 0.5)
	var best := candidates[0]
	var best_d := INF
	for c in candidates:
		var d := Vector2(float(c.x) + 0.5, float(c.y) + 0.5).distance_squared_to(mid)
		if d < best_d:
			best_d = d
			best = c
	out.append(best)
	return out
