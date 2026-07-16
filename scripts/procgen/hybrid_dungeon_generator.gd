class_name HybridDungeonGenerator
extends LevelSource
## Size-aware multilayer hybrid: place authored modules inside a 3D harness.


class Placement:
	var module_id: StringName = &""
	var cell: Vector2i = Vector2i.ZERO
	var level: int = 0
	var footprint: Vector2i = Vector2i.ONE
	var layer_span: int = 1
	var open_dirs: Array[ModuleContract.Dir] = []
	var opts: Dictionary = {}
	var role: String = ""


class ModuleInfo:
	var module_id: StringName = &""
	var footprint: Vector2i = Vector2i.ONE
	var layer_span: int = 1
	var capable_opens: Array[ModuleContract.Dir] = []
	## Dir -> Array[int] of local layers that have a walkable edge opening.
	var open_layers: Dictionary = {}


var params: DungeonGenParams

var _occ: Dictionary = {} ## Vector3i(gx, level, gz) -> true
var _placements: Array[Placement] = []
var _catalog: Dictionary = {} ## StringName -> ModuleInfo
var _resolved_seed: int = 0


func _init(p_params: DungeonGenParams = null) -> void:
	params = p_params if p_params != null else DungeonGenParams.from_preset(DungeonGenParams.Preset.SMALL)


func build_dungeon() -> Node3D:
	assert(params != null, "HybridDungeonGenerator: params required")
	params.clamp_meters()
	_occ.clear()
	_placements.clear()
	_ensure_catalog()

	var rng := RandomNumberGenerator.new()
	if params.seed_value == 0:
		rng.randomize()
	else:
		rng.seed = params.seed_value
	_resolved_seed = int(rng.seed)

	var root := Node3D.new()
	root.name = "DungeonRoot"

	if not _place_start(rng):
		LoudError.report(
			"HybridGen",
			"Could not place a start module in harness %dx%dx%d" % [
				params.grid_w(), params.grid_d(), params.floor_count()
			]
		)
		return root

	_grow_path(rng)
	_place_side_rooms(rng)
	_ensure_exit(rng)
	_compute_openings()

	for p in _placements:
		var opts := p.opts.duplicate()
		opts["force_open_dirs"] = true
		var room := RoomFactory.build(p.module_id, p.open_dirs, opts)
		room.grid_cell = p.cell
		room.vertical_level = p.level
		room.position = ModuleContract.grid_to_world(p.cell, p.level)
		root.add_child(room)

	root.set_meta("seed", _resolved_seed)
	root.set_meta("width_m", params.width_m)
	root.set_meta("depth_m", params.depth_m)
	root.set_meta("height_m", params.height_m)

	var players := _count_in_group(root, ModuleContract.GROUP_PLAYER_SPAWN)
	var exits := _count_in_group(root, ModuleContract.GROUP_EXIT)
	if players <= 0:
		LoudError.report("HybridGen", "Generated dungeon has no player_spawn marker")
	if exits <= 0:
		LoudError.report("HybridGen", "Generated dungeon has no exit marker")
	return root


func resolved_seed() -> int:
	return _resolved_seed


func _ensure_catalog() -> void:
	if not _catalog.is_empty():
		return
	for id in [&"atrium", &"undercroft", &"stair_test", &"corridor", &"combat", &"exit"]:
		var path := "res://rooms/%s.room.txt" % String(id)
		if not FileAccess.file_exists(path):
			continue
		var spec := RoomSpecParser.parse_file(path)
		var info := ModuleInfo.new()
		info.module_id = id
		info.footprint = spec.footprint_cells()
		info.layer_span = maxi(1, spec.layer_count())
		info.capable_opens = spec.open_dirs.duplicate()
		info.open_layers = _scan_open_layers(spec)
		_catalog[id] = info


func _info(id: StringName) -> ModuleInfo:
	return _catalog.get(id) as ModuleInfo


func _place_start(rng: RandomNumberGenerator) -> bool:
	## Atrium is a strong start, but not mandatory — otherwise every Small run feels
	## like the same POC. ~60% atrium when it fits; otherwise stair_test / corridor.
	var atrium: ModuleInfo = _info(&"atrium")
	var atrium_fits := (
		atrium != null
		and _can_place(Vector2i.ZERO, 0, atrium.footprint, atrium.layer_span)
		and _has_exit_margin(atrium.footprint)
	)
	if atrium_fits and rng.randf() < 0.6:
		_commit(_make_placement(&"atrium", Vector2i.ZERO, 0, {"decor": true}, "start"))
		var under: ModuleInfo = _info(&"undercroft")
		if under != null and _can_place(Vector2i.ZERO, -1, under.footprint, under.layer_span):
			_commit(
				_make_placement(&"undercroft", Vector2i.ZERO, -1, {"decor": true}, "undercroft")
			)
		return true

	var stair: ModuleInfo = _info(&"stair_test")
	if stair != null and _can_place(Vector2i.ZERO, 0, stair.footprint, stair.layer_span):
		_commit(
			_make_placement(
				&"stair_test",
				Vector2i.ZERO,
				0,
				{"decor": true, "player_spawn": true},
				"start"
			)
		)
		return true

	if atrium_fits:
		## stair_test didn't fit; fall back to atrium rather than failing.
		_commit(_make_placement(&"atrium", Vector2i.ZERO, 0, {"decor": true}, "start"))
		var under2: ModuleInfo = _info(&"undercroft")
		if under2 != null and _can_place(Vector2i.ZERO, -1, under2.footprint, under2.layer_span):
			_commit(
				_make_placement(&"undercroft", Vector2i.ZERO, -1, {"decor": true}, "undercroft")
			)
		return true

	if _can_place(Vector2i.ZERO, 0, Vector2i.ONE, 1):
		_commit(
			_make_placement(
				&"corridor",
				Vector2i.ZERO,
				0,
				{"decor": true, "player_spawn": true},
				"start"
			)
		)
		return true
	return false


func _grow_path(rng: RandomNumberGenerator) -> void:
	var target := params.path_length_target()
	var cursor: Placement = _placements[0]
	var path_nodes: Array[Placement] = [cursor]
	## Current 1×1 modules only support E/W door gaps in ASCII.
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.E,
		ModuleContract.Dir.W,
	]

	var guards := 0
	while path_nodes.size() < target - 1 and guards < 200:
		guards += 1
		var placed := false

		if rng.randf() < 0.22 and params.floor_count() >= 3:
			if _try_place_stair_hop(rng, cursor, path_nodes):
				cursor = path_nodes[path_nodes.size() - 1]
				continue

		_shuffle(dirs, rng)
		for dir in dirs:
			var next := _attach_cell_from(cursor, dir)
			var id: StringName = (
				&"combat" if path_nodes.size() == maxi(1, int(target / 2)) else &"corridor"
			)
			var info: ModuleInfo = _info(id)
			if info == null:
				continue
			## Attach at a world level where THIS module actually has a doorway —
			## never float a corridor beside an atrium roof with no exit.
			var attach_lv := _attach_level_for(cursor, dir)
			if not _can_place(next, attach_lv, info.footprint, info.layer_span):
				continue
			var opts := {"decor": true}
			if id == &"combat":
				opts["enemy_spawns"] = 2
			var p := _make_placement(id, next, attach_lv, opts, "path")
			_commit(p)
			path_nodes.append(p)
			cursor = p
			placed = true
			break

		if placed:
			continue

		## Backtrack from earlier nodes.
		var progressed := false
		for i in range(path_nodes.size() - 1, -1, -1):
			var node: Placement = path_nodes[i]
			_shuffle(dirs, rng)
			for dir2 in dirs:
				var next2 := _attach_cell_from(node, dir2)
				var info2: ModuleInfo = _info(&"corridor")
				if info2 == null:
					continue
				var lv2 := _attach_level_for(node, dir2)
				if not _can_place(next2, lv2, info2.footprint, info2.layer_span):
					continue
				var p2 := _make_placement(&"corridor", next2, lv2, {"decor": true}, "path")
				_commit(p2)
				path_nodes.append(p2)
				cursor = p2
				progressed = true
				break
			if progressed:
				break
		if not progressed:
			break


func _try_place_stair_hop(
	rng: RandomNumberGenerator,
	cursor: Placement,
	path_nodes: Array[Placement]
) -> bool:
	var stair: ModuleInfo = _info(&"stair_test")
	if stair == null:
		return false
	## stair_test ASCII opens east; prefer attaching on E/W at a real doorway level.
	var dirs: Array[ModuleContract.Dir] = [ModuleContract.Dir.E, ModuleContract.Dir.W]
	_shuffle(dirs, rng)
	for dir in dirs:
		var origin := _attach_cell_from(cursor, dir)
		var base_lv := _attach_level_for(cursor, dir)
		if base_lv + stair.layer_span - 1 > params.max_level():
			continue
		if not _can_place(origin, base_lv, stair.footprint, stair.layer_span):
			continue
		var p := _make_placement(
			&"stair_test",
			origin,
			base_lv,
			{"decor": true, "clear_player": true},
			"stair"
		)
		_commit(p)
		path_nodes.append(p)
		return true
	return false


func _place_side_rooms(rng: RandomNumberGenerator) -> void:
	var want := params.side_room_target()
	var path_only: Array[Placement] = []
	for p in _placements:
		if p.role == "path" or p.role == "start" or p.role == "stair":
			path_only.append(p)
	if path_only.size() < 1:
		return
	var attempts := 0
	var placed := 0
	var dirs: Array[ModuleContract.Dir] = [ModuleContract.Dir.E, ModuleContract.Dir.W]
	while placed < want and attempts < 60:
		attempts += 1
		var base: Placement = path_only[rng.randi_range(0, path_only.size() - 1)]
		var dir: ModuleContract.Dir = dirs[rng.randi_range(0, dirs.size() - 1)]
		var cell := _attach_cell_from(base, dir)
		var info: ModuleInfo = _info(&"combat")
		if info == null:
			continue
		var lv := _attach_level_for(base, dir)
		if not _can_place(cell, lv, info.footprint, info.layer_span):
			continue
		_commit(
			_make_placement(&"combat", cell, lv, {"decor": true, "enemy_spawns": 1}, "side")
		)
		placed += 1


func _ensure_exit(rng: RandomNumberGenerator) -> void:
	for p in _placements:
		if p.module_id == &"exit" or bool(p.opts.get("exit", false)):
			return

	var start_cell := _placements[0].cell
	var best: Placement = null
	var best_d := -1
	for p in _placements:
		if p.role == "undercroft" or p.role == "start":
			continue
		var d: int = absi(p.cell.x - start_cell.x) + absi(p.cell.y - start_cell.y)
		if d > best_d:
			best_d = d
			best = p

	if best != null and best.module_id == &"corridor":
		_uncommit(best)
		_commit(
			_make_placement(
				&"exit", best.cell, best.level, {"decor": true, "exit": true}, "exit"
			)
		)
		return

	var anchors: Array[Placement] = []
	if best != null:
		anchors.append(best)
	for p in _placements:
		if p.role == "undercroft" or p == best:
			continue
		anchors.append(p)
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.E,
		ModuleContract.Dir.W,
		ModuleContract.Dir.S,
		ModuleContract.Dir.N,
	]
	for anchor in anchors:
		_shuffle(dirs, rng)
		for dir in dirs:
			if not _can_open(anchor, dir):
				continue
			var cell := _attach_cell_from(anchor, dir)
			var info: ModuleInfo = _info(&"exit")
			if info == null:
				continue
			var lv := _attach_level_for(anchor, dir)
			if not _can_place(cell, lv, info.footprint, info.layer_span):
				continue
			_commit(
				_make_placement(&"exit", cell, lv, {"decor": true, "exit": true}, "exit")
			)
			return

	## Last resort: mark the farthest reachable module as the exit (not undercroft).
	for p in _placements:
		if p.role == "undercroft" or p.role == "start":
			continue
		p.opts["exit"] = true
		p.role = "exit"
		return

	LoudError.report("HybridGen", "Failed to place an exit module in the harness")


func _make_placement(
	id: StringName,
	cell: Vector2i,
	level: int,
	opts: Dictionary,
	role: String
) -> Placement:
	var info: ModuleInfo = _info(id)
	var p := Placement.new()
	p.module_id = id
	p.cell = cell
	p.level = level
	p.footprint = info.footprint if info != null else Vector2i.ONE
	p.layer_span = info.layer_span if info != null else 1
	p.opts = opts
	p.role = role
	return p


func _has_exit_margin(footprint: Vector2i) -> bool:
	return (
		params.grid_w() >= footprint.x + 1
		or params.grid_d() >= footprint.y + 1
	)


func _can_place(cell: Vector2i, level: int, footprint: Vector2i, layer_span: int) -> bool:
	var gw := params.grid_w()
	var gd := params.grid_d()
	var max_lv := params.max_level()
	if cell.x < 0 or cell.y < 0:
		return false
	if cell.x + footprint.x > gw or cell.y + footprint.y > gd:
		return false
	for ly in layer_span:
		var lv := level + ly
		## Harness floors are 0..max_lv; undercroft may use -1.
		if lv < -1 or lv > max_lv:
			return false
		for z in footprint.y:
			for x in footprint.x:
				if _occ.has(Vector3i(cell.x + x, lv, cell.y + z)):
					return false
	return true


func _commit(p: Placement) -> void:
	for ly in p.layer_span:
		var lv := p.level + ly
		for z in p.footprint.y:
			for x in p.footprint.x:
				_occ[Vector3i(p.cell.x + x, lv, p.cell.y + z)] = true
	_placements.append(p)


func _uncommit(p: Placement) -> void:
	for ly in p.layer_span:
		var lv := p.level + ly
		for z in p.footprint.y:
			for x in p.footprint.x:
				_occ.erase(Vector3i(p.cell.x + x, lv, p.cell.y + z))
	_placements.erase(p)


func _attach_cell_from(p: Placement, dir: ModuleContract.Dir) -> Vector2i:
	match dir:
		ModuleContract.Dir.E:
			return Vector2i(p.cell.x + p.footprint.x, p.cell.y + int(p.footprint.y / 2))
		ModuleContract.Dir.W:
			return Vector2i(p.cell.x - 1, p.cell.y + int(p.footprint.y / 2))
		ModuleContract.Dir.S:
			return Vector2i(p.cell.x + int(p.footprint.x / 2), p.cell.y + p.footprint.y)
		ModuleContract.Dir.N:
			return Vector2i(p.cell.x + int(p.footprint.x / 2), p.cell.y - 1)
	return p.cell


func _compute_openings() -> void:
	## Only mutual, template-capable links — never leave a door facing empty space.
	for p in _placements:
		p.open_dirs.clear()

	for i in _placements.size():
		for j in range(i + 1, _placements.size()):
			var a: Placement = _placements[i]
			var b: Placement = _placements[j]
			_link_horizontal(a, b)
			_link_vertical(a, b)


func _link_horizontal(a: Placement, b: Placement) -> void:
	if not _levels_overlap(a, b):
		return
	if a.cell.x + a.footprint.x == b.cell.x and _z_ranges_overlap(a, b):
		if _share_door_floor(a, ModuleContract.Dir.E, b, ModuleContract.Dir.W):
			_link_pair(a, ModuleContract.Dir.E, b, ModuleContract.Dir.W)
	elif b.cell.x + b.footprint.x == a.cell.x and _z_ranges_overlap(a, b):
		if _share_door_floor(b, ModuleContract.Dir.E, a, ModuleContract.Dir.W):
			_link_pair(b, ModuleContract.Dir.E, a, ModuleContract.Dir.W)
	elif a.cell.y + a.footprint.y == b.cell.y and _x_ranges_overlap(a, b):
		if _share_door_floor(a, ModuleContract.Dir.S, b, ModuleContract.Dir.N):
			_link_pair(a, ModuleContract.Dir.S, b, ModuleContract.Dir.N)
	elif b.cell.y + b.footprint.y == a.cell.y and _x_ranges_overlap(a, b):
		if _share_door_floor(b, ModuleContract.Dir.S, a, ModuleContract.Dir.N):
			_link_pair(b, ModuleContract.Dir.S, a, ModuleContract.Dir.N)


func _link_vertical(a: Placement, b: Placement) -> void:
	if not _xz_overlap(a, b):
		return
	if a.level + a.layer_span == b.level:
		_link_pair(a, ModuleContract.Dir.U, b, ModuleContract.Dir.D)
	elif b.level + b.layer_span == a.level:
		_link_pair(b, ModuleContract.Dir.U, a, ModuleContract.Dir.D)


func _link_pair(
	a: Placement,
	dir_a: ModuleContract.Dir,
	b: Placement,
	dir_b: ModuleContract.Dir
) -> void:
	if not _can_open(a, dir_a) or not _can_open(b, dir_b):
		return
	_add_open(a, dir_a)
	_add_open(b, dir_b)


func _can_open(p: Placement, dir: ModuleContract.Dir) -> bool:
	var info: ModuleInfo = _info(p.module_id)
	if info == null:
		return false
	if info.capable_opens.is_empty():
		return false
	return dir in info.capable_opens


func _levels_overlap(a: Placement, b: Placement) -> bool:
	var a0 := a.level
	var a1 := a.level + a.layer_span - 1
	var b0 := b.level
	var b1 := b.level + b.layer_span - 1
	return a0 <= b1 and b0 <= a1


func _x_ranges_overlap(a: Placement, b: Placement) -> bool:
	return a.cell.x < b.cell.x + b.footprint.x and b.cell.x < a.cell.x + a.footprint.x


func _z_ranges_overlap(a: Placement, b: Placement) -> bool:
	return a.cell.y < b.cell.y + b.footprint.y and b.cell.y < a.cell.y + a.footprint.y


func _xz_overlap(a: Placement, b: Placement) -> bool:
	return _x_ranges_overlap(a, b) and _z_ranges_overlap(a, b)


func _add_open(p: Placement, dir: ModuleContract.Dir) -> void:
	if dir in p.open_dirs:
		return
	if not _can_open(p, dir):
		return
	p.open_dirs.append(dir)


func _count_in_group(root: Node, group: StringName) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_in_group(group):
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _scan_open_layers(spec: RoomSpec) -> Dictionary:
	var out := {}
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	for dir in dirs:
		var layers: Array[int] = []
		for level in spec.layer_count():
			if _layer_has_edge_open(spec, level, dir):
				layers.append(level)
		if not layers.is_empty():
			out[dir] = layers
	return out


func _layer_has_edge_open(spec: RoomSpec, level: int, dir: ModuleContract.Dir) -> bool:
	match dir:
		ModuleContract.Dir.E:
			for z in spec.depth:
				if RoomCells.is_walkable(spec.get_cell(level, spec.width - 1, z)):
					return true
		ModuleContract.Dir.W:
			for z in spec.depth:
				if RoomCells.is_walkable(spec.get_cell(level, 0, z)):
					return true
		ModuleContract.Dir.S:
			for x in spec.width:
				if RoomCells.is_walkable(spec.get_cell(level, x, spec.depth - 1)):
					return true
		ModuleContract.Dir.N:
			for x in spec.width:
				if RoomCells.is_walkable(spec.get_cell(level, x, 0)):
					return true
	return false


func _attach_level_for(p: Placement, dir: ModuleContract.Dir) -> int:
	## World level of a real doorway on `p` facing `dir`. Multi-layer modules must
	## not advertise a roof-side exit unless ASCII has an opening on that layer.
	var info: ModuleInfo = _info(p.module_id)
	if info == null:
		return p.level
	var layers: Array = info.open_layers.get(dir, [])
	if layers.is_empty():
		return p.level
	return p.level + int(layers[layers.size() - 1])


func _share_door_floor(
	a: Placement,
	dir_a: ModuleContract.Dir,
	b: Placement,
	dir_b: ModuleContract.Dir
) -> bool:
	var info_a: ModuleInfo = _info(a.module_id)
	var info_b: ModuleInfo = _info(b.module_id)
	if info_a == null or info_b == null:
		return false
	var layers_a: Array = info_a.open_layers.get(dir_a, [])
	var layers_b: Array = info_b.open_layers.get(dir_b, [])
	for la_variant in layers_a:
		var world_a := a.level + int(la_variant)
		for lb_variant in layers_b:
			if world_a == b.level + int(lb_variant):
				return true
	return false
