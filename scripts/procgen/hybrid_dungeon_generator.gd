class_name HybridDungeonGenerator
extends LevelSource
## Size-aware multilayer hybrid: place authored modules inside a 3D harness.

const _CarveMerger := preload("res://scripts/procgen/carve_merger.gd")


class Placement:
	var module_id: StringName = &""
	var cell: Vector2i = Vector2i.ZERO
	var level: int = 0
	var footprint: Vector2i = Vector2i.ONE
	var layer_span: int = 1
	## World floor where the critical path leaves this module (stairs raise it).
	var path_floor: int = 0
	var open_dirs: Array[ModuleContract.Dir] = []
	## Vector2i(dir, local_level) — only these faces become real doors.
	var open_faces: Array = []
	## Vector2i(dir, local_level) -> Array[Vector2i] local doorways (wide rooms may
	## host several peers on one face).
	var doorway_cells: Dictionary = {}
	var opts: Dictionary = {}
	var role: String = ""
	## When set, this placement may occupy cells already owned by carve_host.
	var carve_host: Placement = null


class ModuleInfo:
	var module_id: StringName = &""
	var footprint: Vector2i = Vector2i.ONE
	var layer_span: int = 1
	var capable_opens: Array[ModuleContract.Dir] = []
	## Dir -> Array[int] of local layers that have a walkable edge opening.
	var open_layers: Dictionary = {}
	## Dir -> Dictionary local_level -> Vector2i doorway cell (ASCII coords).
	var doorways: Dictionary = {}
	## Dir -> Dictionary local_level -> Array[Vector2i] all walkable edge cells.
	var edge_walkables: Dictionary = {}
	var cells_per_module: int = 4


var params: DungeonGenParams

var _occ: Dictionary = {} ## Vector3i(gx, level, gz) -> Placement
var _placements: Array[Placement] = []
var _catalog: Dictionary = {} ## StringName -> ModuleInfo
var _resolved_seed: int = 0
var _stair_rises: int = 0


func _init(p_params: DungeonGenParams = null) -> void:
	params = p_params if p_params != null else DungeonGenParams.from_preset(DungeonGenParams.Preset.SMALL)


func build_dungeon() -> Node3D:
	assert(params != null, "HybridDungeonGenerator: params required")
	params.clamp_meters()
	_occ.clear()
	_placements.clear()
	_stair_rises = 0
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
	_grow_floor_clusters(rng)
	_place_side_rooms(rng)
	_place_loops(rng)
	_place_carve_bites(rng)
	_ensure_exit(rng)
	_compute_openings()
	_CarveMerger.apply(_placements)

	for p in _placements:
		var opts := p.opts.duplicate()
		opts["force_open_dirs"] = true
		opts["open_faces"] = p.open_faces.duplicate()
		opts["doorway_cells"] = p.doorway_cells.duplicate()
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
	for id in [&"atrium", &"undercroft", &"hall", &"stair_test", &"corridor", &"combat", &"exit"]:
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
		info.doorways = _scan_doorways(spec)
		info.edge_walkables = _scan_edge_walkables(spec)
		info.cells_per_module = maxi(1, int(round(ModuleContract.ROOM_SIZE / spec.cell_size)))
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
		var start_stair := _make_placement(
			&"stair_test",
			Vector2i.ZERO,
			0,
			{"decor": true, "player_spawn": true},
			"start"
		)
		_commit(start_stair)
		_stair_rises = 1
		var boot_nodes: Array[Placement] = [start_stair]
		_ensure_stair_foyer(start_stair, boot_nodes, rng)
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
	## Spread across the harness: branch from earlier nodes, turn often, fill area.
	## Stairs raise path_floor so later attachments continue on the upper storey.
	var target := params.path_module_target()
	var start: Placement = _placements[0]
	var path_nodes: Array[Placement] = [start]
	var last_dir: int = -1
	var streak := 0

	var guards := 0
	while path_nodes.size() < target and guards < 400:
		guards += 1
		var bases := _pick_growth_bases(path_nodes, rng)
		var placed := false
		for base in bases:
			var attach_lv := _attach_level_for(base, ModuleContract.Dir.E)
			var dirs := _ordered_growth_dirs(base, attach_lv, last_dir, streak, rng)
			for dir in dirs:
				var id := _pick_path_module(rng, path_nodes.size(), target, dir, attach_lv)
				if not _placement_accepts_attach(id, dir):
					id = &"corridor"
				if not _placement_accepts_attach(id, dir):
					continue
				## Stairs need headroom for their upper landing.
				if id == &"stair_test" and attach_lv + 1 > params.max_level():
					id = &"corridor"
				var next := _attach_cell_from(base, dir)
				var info: ModuleInfo = _info(id)
				if info == null:
					continue
				if not _can_place(next, attach_lv, info.footprint, info.layer_span):
					if id != &"corridor":
						id = &"corridor"
						info = _info(id)
						if (
							info == null
							or not _placement_accepts_attach(id, dir)
							or not _can_place(next, attach_lv, info.footprint, info.layer_span)
						):
							continue
					else:
						continue
				var opts := {"decor": true}
				if id == &"combat":
					opts["enemy_spawns"] = 2
				if id == &"stair_test":
					opts["clear_player"] = true
				var role := "stair" if id == &"stair_test" else "path"
				var p := _make_placement(id, next, attach_lv, opts, role)
				_commit(p)
				if id == &"stair_test":
					if not _ensure_stair_foyer(p, path_nodes, rng):
						## Stacked climb without an upper foothold → unreachable island.
						_uncommit(p)
						continue
					_stair_rises += 1
				path_nodes.append(p)
				if int(dir) == last_dir:
					streak += 1
				else:
					last_dir = int(dir)
					streak = 1
				placed = true
				break
			if placed:
				break
		if not placed:
			break


func _ensure_stair_foyer(
	stair: Placement,
	path_nodes: Array[Placement],
	rng: RandomNumberGenerator
) -> bool:
	## Guarantee at least one room on the upper landing before path growth continues.
	## Prefer E then S — stair_test's upper landing sits on the east/south rim past the shaft voids.
	var attach_lv := stair.path_floor
	if attach_lv <= stair.level:
		return false
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.N,
		ModuleContract.Dir.W,
	]
	if rng.randf() < 0.35:
		_shuffle(dirs, rng)
	for dir in dirs:
		if not _can_open_on_world_floor(stair, dir, attach_lv):
			continue
		var next := _attach_cell_from(stair, dir)
		var info: ModuleInfo = _info(&"corridor")
		if info == null:
			return false
		if not _can_place(next, attach_lv, info.footprint, info.layer_span):
			continue
		var foyer := _make_placement(&"corridor", next, attach_lv, {"decor": true}, "upper")
		foyer.path_floor = attach_lv
		_commit(foyer)
		path_nodes.append(foyer)
		return true
	return false


func _grow_floor_clusters(rng: RandomNumberGenerator) -> void:
	## After the spine, thicken each stair's upper floor so landings aren't orphans.
	var stairs: Array[Placement] = []
	for p in _placements:
		if p.module_id == &"stair_test" or p.role == "stair":
			stairs.append(p)
	for stair in stairs:
		var want := params.upper_cluster_target()
		var nodes: Array[Placement] = [stair]
		var guards := 0
		var placed := 0
		while placed < want and guards < 50:
			guards += 1
			var base: Placement = nodes[rng.randi_range(0, nodes.size() - 1)]
			var attach_lv := _attach_level_for(base, ModuleContract.Dir.E)
			if attach_lv <= stair.level:
				## Path never rose — nothing to cluster upstairs.
				break
			var dirs: Array[ModuleContract.Dir] = [
				ModuleContract.Dir.N,
				ModuleContract.Dir.E,
				ModuleContract.Dir.S,
				ModuleContract.Dir.W,
			]
			_shuffle(dirs, rng)
			var grew := false
			for dir in dirs:
				if not _can_open_on_world_floor(base, dir, attach_lv):
					continue
				var id: StringName = &"combat" if rng.randf() < 0.45 else &"corridor"
				if rng.randf() < 0.2 and _info(&"hall") != null and _placement_accepts_attach(&"hall", dir):
					id = &"hall"
				if not _placement_accepts_attach(id, dir):
					id = &"corridor"
				var next := _attach_cell_from(base, dir)
				var info: ModuleInfo = _info(id)
				if info == null:
					continue
				if not _can_place(next, attach_lv, info.footprint, info.layer_span):
					continue
				var opts := {"decor": true}
				if id == &"combat":
					opts["enemy_spawns"] = 1
				var p := _make_placement(id, next, attach_lv, opts, "upper")
				## Stay on this storey — don't chain stairs inside the cluster.
				p.path_floor = attach_lv
				_commit(p)
				nodes.append(p)
				placed += 1
				grew = true
				break
			if not grew:
				break


func _pick_growth_bases(
	path_nodes: Array[Placement],
	rng: RandomNumberGenerator
) -> Array[Placement]:
	## Tip-biased but usually branch from an earlier node so the graph fans out.
	var out: Array[Placement] = []
	if path_nodes.is_empty():
		return out
	var tip: Placement = path_nodes[path_nodes.size() - 1]
	if rng.randf() < 0.38:
		out.append(tip)
	var order: Array[Placement] = path_nodes.duplicate()
	_shuffle(order, rng)
	for node in order:
		if node.role == "undercroft":
			continue
		if not out.has(node):
			out.append(node)
		if out.size() >= mini(6, path_nodes.size()):
			break
	if not out.has(tip):
		out.append(tip)
	return out


func _ordered_growth_dirs(
	base: Placement,
	attach_lv: int,
	last_dir: int,
	streak: int,
	rng: RandomNumberGenerator
) -> Array[ModuleContract.Dir]:
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	## Score: prefer empty harness regions + soft turn bias.
	var scored: Array[Dictionary] = []
	for dir in dirs:
		if not _can_open_on_world_floor(base, dir, attach_lv):
			continue
		var next := _attach_cell_from(base, dir)
		var score := _growth_dir_score(next, dir, last_dir, streak, rng)
		scored.append({"dir": dir, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	var out: Array[ModuleContract.Dir] = []
	for row in scored:
		out.append(row["dir"] as ModuleContract.Dir)
	return out


func _growth_dir_score(
	next: Vector2i,
	dir: ModuleContract.Dir,
	last_dir: int,
	streak: int,
	rng: RandomNumberGenerator
) -> float:
	var gw := float(params.grid_w())
	var gd := float(params.grid_d())
	var score := rng.randf() * 0.35
	## Pull toward underfilled half of the harness (centroid of free cells ≈ center bias early).
	var cx := (gw - 1.0) * 0.5
	var cz := (gd - 1.0) * 0.5
	var occ_c := _occupied_centroid()
	## Prefer growing away from the current mass's centroid → spreads the blob.
	var away := Vector2(float(next.x) - occ_c.x, float(next.y) - occ_c.y)
	var toward_center := Vector2(cx - float(next.x), cz - float(next.y))
	score += away.length() * 0.15
	score += toward_center.length() * -0.02
	## Local emptiness around the target cell.
	score += float(_empty_neighbor_count(next)) * 0.45
	if int(dir) == last_dir:
		score -= 0.55 * float(streak)
		if streak >= 2:
			score -= 1.25
	## Slight preference for cardinal mix (discourage pure east runs).
	if dir == ModuleContract.Dir.E:
		score -= 0.08
	return score


func _occupied_centroid() -> Vector2:
	if _occ.is_empty():
		return Vector2(float(params.grid_w()) * 0.5, float(params.grid_d()) * 0.5)
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for key_variant in _occ.keys():
		var key: Vector3i = key_variant
		if key.y != 0 and key.y != -1:
			continue
		sx += float(key.x)
		sz += float(key.z)
		n += 1
	if n == 0:
		return Vector2(float(params.grid_w()) * 0.5, float(params.grid_d()) * 0.5)
	return Vector2(sx / float(n), sz / float(n))


func _empty_neighbor_count(cell: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = cell + d
		if c.x < 0 or c.y < 0 or c.x >= params.grid_w() or c.y >= params.grid_d():
			continue
		if not _occ.has(Vector3i(c.x, 0, c.y)):
			n += 1
	return n


func _placement_accepts_attach(id: StringName, from_base_dir: ModuleContract.Dir) -> bool:
	## New module must open toward the base (opposite of growth dir).
	var info: ModuleInfo = _info(id)
	if info == null:
		return false
	var need := ModuleContract.opposite(from_base_dir)
	return need in info.capable_opens


func _place_side_rooms(rng: RandomNumberGenerator) -> void:
	var want := params.side_room_target()
	var anchors: Array[Placement] = []
	for p in _placements:
		if p.role == "undercroft":
			continue
		anchors.append(p)
	if anchors.is_empty():
		return
	var attempts := 0
	var placed := 0
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	while placed < want and attempts < 120:
		attempts += 1
		var base: Placement = anchors[rng.randi_range(0, anchors.size() - 1)]
		_shuffle(dirs, rng)
		var dir: ModuleContract.Dir = dirs[0]
		var lv := _attach_level_for(base, dir)
		if not _can_open_on_world_floor(base, dir, lv):
			continue
		var cell := _attach_cell_from(base, dir)
		var id: StringName = &"combat" if rng.randf() < 0.7 else &"corridor"
		if not _placement_accepts_attach(id, dir):
			id = &"corridor"
		var info: ModuleInfo = _info(id)
		if info == null or not _placement_accepts_attach(id, dir):
			continue
		if not _can_place(cell, lv, info.footprint, info.layer_span):
			continue
		var opts := {"decor": true}
		if id == &"combat":
			opts["enemy_spawns"] = 1
		var side := _make_placement(id, cell, lv, opts, "side")
		side.path_floor = lv
		_commit(side)
		placed += 1


func _place_loops(rng: RandomNumberGenerator) -> void:
	## Fill empty cells that touch 2+ existing modules → cheap cycles / irregular blobs.
	var want := params.loop_attempt_target()
	var placed := 0
	var attempts := 0
	var levels: Array[int] = []
	for p in _placements:
		for ly in p.layer_span:
			var lv := p.level + ly
			if lv >= 0 and not levels.has(lv):
				levels.append(lv)
	if levels.is_empty():
		levels.append(0)
	while placed < want and attempts < 100:
		attempts += 1
		var lv: int = levels[rng.randi_range(0, levels.size() - 1)]
		var cell := Vector2i(rng.randi_range(0, params.grid_w() - 1), rng.randi_range(0, params.grid_d() - 1))
		if _occ.has(Vector3i(cell.x, lv, cell.y)):
			continue
		var touch := _adjacent_placements(cell, lv)
		if touch.size() < 2:
			continue
		var linkable := 0
		for nb in touch:
			var dir := _dir_from_to(nb, cell)
			if dir == ModuleContract.Dir.U:
				continue
			if _can_open_on_world_floor(nb, dir, lv):
				linkable += 1
		if linkable < 2:
			continue
		var info: ModuleInfo = _info(&"corridor")
		if info == null or not _can_place(cell, lv, info.footprint, info.layer_span):
			continue
		var loop_p := _make_placement(&"corridor", cell, lv, {"decor": true}, "loop")
		loop_p.path_floor = lv
		_commit(loop_p)
		placed += 1


func _adjacent_placements(cell: Vector2i, level: int) -> Array[Placement]:
	var out: Array[Placement] = []
	for p in _placements:
		if not _levels_overlap_level(p, level):
			continue
		## Orthogonally adjacent footprints (touching edge).
		var ax0 := p.cell.x
		var ax1 := p.cell.x + p.footprint.x
		var az0 := p.cell.y
		var az1 := p.cell.y + p.footprint.y
		var touches := (
			(cell.x == ax1 and cell.y >= az0 and cell.y < az1)
			or (cell.x == ax0 - 1 and cell.y >= az0 and cell.y < az1)
			or (cell.y == az1 and cell.x >= ax0 and cell.x < ax1)
			or (cell.y == az0 - 1 and cell.x >= ax0 and cell.x < ax1)
		)
		if touches:
			out.append(p)
	return out


func _levels_overlap_level(p: Placement, level: int) -> bool:
	return level >= p.level and level <= p.level + p.layer_span - 1


func _dir_from_to(from: Placement, to_cell: Vector2i) -> ModuleContract.Dir:
	var ax0 := from.cell.x
	var ax1 := from.cell.x + from.footprint.x
	var az0 := from.cell.y
	var az1 := from.cell.y + from.footprint.y
	if to_cell.x == ax1 and to_cell.y >= az0 and to_cell.y < az1:
		return ModuleContract.Dir.E
	if to_cell.x == ax0 - 1 and to_cell.y >= az0 and to_cell.y < az1:
		return ModuleContract.Dir.W
	if to_cell.y == az1 and to_cell.x >= ax0 and to_cell.x < ax1:
		return ModuleContract.Dir.S
	if to_cell.y == az0 - 1 and to_cell.x >= ax0 and to_cell.x < ax1:
		return ModuleContract.Dir.N
	return ModuleContract.Dir.U


func _place_carve_bites(rng: RandomNumberGenerator) -> void:
	## Intentional 1-cell footprint overlaps: guest empties shared ASCII, host opens it.
	var want := params.carve_bite_target()
	var placed := 0
	var attempts := 0
	while placed < want and attempts < 120:
		attempts += 1
		var hosts: Array[Placement] = []
		for p in _placements:
			if p.role == "undercroft" or p.module_id == &"exit":
				continue
			## Never bite stairs / multilayer — empties break shaft landings.
			if p.module_id == &"stair_test" or p.layer_span > 1:
				continue
			if p.footprint.x * p.footprint.y < 1:
				continue
			## Prefer larger hosts so a bite leaves host mass behind.
			if p.footprint.x + p.footprint.y >= 3 or p.module_id == &"hall":
				hosts.append(p)
		if hosts.is_empty():
			for p2 in _placements:
				if (
					p2.role == "undercroft"
					or p2.module_id == &"exit"
					or p2.module_id == &"stair_test"
					or p2.layer_span > 1
				):
					continue
				hosts.append(p2)
		if hosts.is_empty():
			return
		var host: Placement = hosts[rng.randi_range(0, hosts.size() - 1)]
		var guest_id: StringName = &"hall" if rng.randf() < 0.55 else &"combat"
		if _info(guest_id) == null:
			guest_id = &"corridor"
		var info: ModuleInfo = _info(guest_id)
		if info == null or info.footprint.x * info.footprint.y < 2:
			## Need exclusive + overlap cells; 1×1 guests empty entirely.
			if _info(&"hall") != null:
				guest_id = &"hall"
				info = _info(guest_id)
			else:
				continue
		if info == null or info.footprint.x * info.footprint.y < 2:
			continue
		var lv := host.level
		var dirs: Array[ModuleContract.Dir] = [
			ModuleContract.Dir.N,
			ModuleContract.Dir.E,
			ModuleContract.Dir.S,
			ModuleContract.Dir.W,
		]
		_shuffle(dirs, rng)
		var bit := false
		for dir in dirs:
			## Shift one cell into the host from a normal adjacent attach.
			var adj := _attach_cell_from(host, dir)
			var inset := adj
			match dir:
				ModuleContract.Dir.E:
					inset = Vector2i(adj.x - 1, adj.y)
				ModuleContract.Dir.W:
					inset = Vector2i(adj.x + 1, adj.y)
				ModuleContract.Dir.S:
					inset = Vector2i(adj.x, adj.y - 1)
				ModuleContract.Dir.N:
					inset = Vector2i(adj.x, adj.y + 1)
			if not _can_place_carve(inset, lv, info.footprint, info.layer_span, host):
				continue
			var opts := {"decor": true, "carve_empty_ascii": [], "carve_open_ascii": []}
			if guest_id == &"combat":
				opts["enemy_spawns"] = 1
			var guest := _make_placement(guest_id, inset, lv, opts, "carve")
			guest.carve_host = host
			guest.path_floor = lv
			_commit(guest)
			var overlap := _overlap_cells(guest, host)
			if overlap.is_empty():
				_uncommit(guest)
				continue
			_CarveMerger.plan_bite(guest, host, overlap, info.cells_per_module)
			placed += 1
			bit = true
			break
		if not bit:
			continue


func _ensure_exit(rng: RandomNumberGenerator) -> void:
	for p in _placements:
		if p.module_id == &"exit" or bool(p.opts.get("exit", false)):
			return

	var start_cell := _placements[0].cell
	## Prefer ground-floor exits — upper-only islands were winning "farthest" and
	## leaving the exit unreachable from spawn.
	var best: Placement = null
	var best_d := -1
	for p in _placements:
		if p.role == "undercroft" or p.role == "start":
			continue
		if p.level != 0:
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
		## Any module that occupies ground can host a ground-floor doorway.
		if p.level > 0:
			continue
		anchors.append(p)
	## Start last so we prefer farther anchors first, then fall back to spawn room.
	for p in _placements:
		if p.role == "start" and p.level == 0 and not anchors.has(p):
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
			## Always place the exit on ground, even if the path has climbed.
			var lv := 0
			if not _can_open_on_world_floor(anchor, dir, lv):
				continue
			var cell := _attach_cell_from(anchor, dir)
			var info: ModuleInfo = _info(&"exit")
			if info == null:
				continue
			if not _can_place(cell, lv, info.footprint, info.layer_span):
				continue
			var exit_p := _make_placement(&"exit", cell, lv, {"decor": true, "exit": true}, "exit")
			exit_p.path_floor = lv
			_commit(exit_p)
			return

	## Last resort: mark a ground module as the exit (including start).
	for p in _placements:
		if p.role == "undercroft":
			continue
		if p.level != 0:
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
	## Stairs raise the critical path onto their upper landing; other modules keep
	## the path on the floor where they were attached.
	p.path_floor = level
	if id == &"stair_test" and level + 1 <= params.max_level():
		p.path_floor = level + 1
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


func _can_place_carve(
	cell: Vector2i,
	level: int,
	footprint: Vector2i,
	layer_span: int,
	host: Placement
) -> bool:
	## Guest may share cells with host only; must keep ≥1 exclusive cell and ≥1 overlap.
	if host == null:
		return false
	var gw := params.grid_w()
	var gd := params.grid_d()
	var max_lv := params.max_level()
	if cell.x < 0 or cell.y < 0:
		return false
	if cell.x + footprint.x > gw or cell.y + footprint.y > gd:
		return false
	var overlap := 0
	var exclusive := 0
	for ly in layer_span:
		var lv := level + ly
		if lv < -1 or lv > max_lv:
			return false
		for z in footprint.y:
			for x in footprint.x:
				var key := Vector3i(cell.x + x, lv, cell.y + z)
				if not _occ.has(key):
					exclusive += 1
					continue
				var owner: Placement = _occ[key] as Placement
				if owner != host:
					return false
				overlap += 1
	return overlap > 0 and exclusive > 0


func _overlap_cells(guest: Placement, host: Placement) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for ly in guest.layer_span:
		var lv := guest.level + ly
		for z in guest.footprint.y:
			for x in guest.footprint.x:
				var gcell := Vector2i(guest.cell.x + x, guest.cell.y + z)
				var key := Vector3i(gcell.x, lv, gcell.y)
				var owner: Placement = _occ.get(key) as Placement
				if owner != host:
					continue
				if seen.has(gcell):
					continue
				seen[gcell] = true
				out.append(gcell)
	return out


func _commit(p: Placement) -> void:
	for ly in p.layer_span:
		var lv := p.level + ly
		for z in p.footprint.y:
			for x in p.footprint.x:
				var key := Vector3i(p.cell.x + x, lv, p.cell.y + z)
				if _occ.has(key):
					## Carve guest on host cells — keep host as occupancy owner.
					assert(
						p.carve_host != null and _occ[key] == p.carve_host,
						"HybridGen: unexpected occupancy collision at %s" % str(key)
					)
					continue
				_occ[key] = p
	_placements.append(p)


func _uncommit(p: Placement) -> void:
	for ly in p.layer_span:
		var lv := p.level + ly
		for z in p.footprint.y:
			for x in p.footprint.x:
				var key := Vector3i(p.cell.x + x, lv, p.cell.y + z)
				if _occ.get(key) == p:
					_occ.erase(key)
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
		p.open_faces.clear()
		p.doorway_cells.clear()

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
		_try_link_faces(a, ModuleContract.Dir.E, b, ModuleContract.Dir.W)
	elif b.cell.x + b.footprint.x == a.cell.x and _z_ranges_overlap(a, b):
		_try_link_faces(b, ModuleContract.Dir.E, a, ModuleContract.Dir.W)
	elif a.cell.y + a.footprint.y == b.cell.y and _x_ranges_overlap(a, b):
		_try_link_faces(a, ModuleContract.Dir.S, b, ModuleContract.Dir.N)
	elif b.cell.y + b.footprint.y == a.cell.y and _x_ranges_overlap(a, b):
		_try_link_faces(b, ModuleContract.Dir.S, a, ModuleContract.Dir.N)


func _try_link_faces(
	a: Placement,
	dir_a: ModuleContract.Dir,
	b: Placement,
	dir_b: ModuleContract.Dir
) -> void:
	if not _can_open(a, dir_a) or not _can_open(b, dir_b):
		return
	var matched := _matching_door_links(a, dir_a, b, dir_b)
	if matched.is_empty():
		return
	_add_open(a, dir_a)
	_add_open(b, dir_b)
	for link_variant in matched:
		var link: Dictionary = link_variant
		var la := int(link["la"])
		var lb := int(link["lb"])
		_add_open_face(a, dir_a, la)
		_add_open_face(b, dir_b, lb)
		_add_doorway_cell(a, dir_a, la, link["cell_a"] as Vector2i)
		_add_doorway_cell(b, dir_b, lb, link["cell_b"] as Vector2i)


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


func _can_open_on_world_floor(p: Placement, dir: ModuleContract.Dir, world_floor: int) -> bool:
	## Dir must be capable AND have a walkable edge on the local layer that maps to
	## world_floor (stops attaching to a stair's L0 when the path is on L1).
	if not _can_open(p, dir):
		return false
	var info: ModuleInfo = _info(p.module_id)
	if info == null:
		return false
	var local := world_floor - p.level
	if local < 0 or local >= p.layer_span:
		return false
	var layers: Array = info.open_layers.get(dir, [])
	return local in layers


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


func _add_open_face(p: Placement, dir: ModuleContract.Dir, local_level: int) -> void:
	var key := Vector2i(dir as int, local_level)
	for face_variant in p.open_faces:
		if (face_variant as Vector2i) == key:
			return
	p.open_faces.append(key)


func _add_doorway_cell(
	p: Placement,
	dir: ModuleContract.Dir,
	local_level: int,
	cell: Vector2i
) -> void:
	var key := Vector2i(dir as int, local_level)
	if not p.doorway_cells.has(key):
		var fresh: Array[Vector2i] = []
		p.doorway_cells[key] = fresh
	var arr: Array = p.doorway_cells[key]
	for existing_variant in arr:
		if (existing_variant as Vector2i) == cell:
			return
	arr.append(cell)


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


func _attach_level_for(p: Placement, _dir: ModuleContract.Dir) -> int:
	## Continue the path on the floor the path has actually reached — not every
	## ASCII layer that *could* host a door (that floated rooms onto unreachable floors).
	return p.path_floor


func _matching_door_links(
	a: Placement,
	dir_a: ModuleContract.Dir,
	b: Placement,
	dir_b: ModuleContract.Dir
) -> Array:
	## Dictionaries: {la, lb, cell_a, cell_b}. Exact face only (no tangent slack).
	var out: Array = []
	var info_a: ModuleInfo = _info(a.module_id)
	var info_b: ModuleInfo = _info(b.module_id)
	if info_a == null or info_b == null:
		return out
	var layers_a: Array = info_a.open_layers.get(dir_a, [])
	var layers_b: Array = info_b.open_layers.get(dir_b, [])
	var origin_a := Vector2i(a.cell.x * info_a.cells_per_module, a.cell.y * info_a.cells_per_module)
	var origin_b := Vector2i(b.cell.x * info_b.cells_per_module, b.cell.y * info_b.cells_per_module)
	for la_variant in layers_a:
		var la := int(la_variant)
		var world_lv := a.level + la
		for lb_variant in layers_b:
			var lb := int(lb_variant)
			if world_lv != b.level + lb:
				continue
			var pair := _pick_facing_edge_pair(
				info_a, dir_a, la, origin_a, info_b, dir_b, lb, origin_b, a, b
			)
			if pair.is_empty():
				continue
			out.append({
				"la": la,
				"lb": lb,
				"cell_a": pair["cell_a"],
				"cell_b": pair["cell_b"],
			})
	return out


func _pick_facing_edge_pair(
	info_a: ModuleInfo,
	dir_a: ModuleContract.Dir,
	la: int,
	origin_a: Vector2i,
	info_b: ModuleInfo,
	dir_b: ModuleContract.Dir,
	lb: int,
	origin_b: Vector2i,
	place_a: Placement = null,
	place_b: Placement = null
) -> Dictionary:
	var cells_a: Array = info_a.edge_walkables.get(dir_a, {}).get(la, [])
	var cells_b: Array = info_b.edge_walkables.get(dir_b, {}).get(lb, [])
	var mid_a: Vector2i = info_a.doorways.get(dir_a, {}).get(la, Vector2i(-1, -1))
	var mid_b: Vector2i = info_b.doorways.get(dir_b, {}).get(lb, Vector2i(-1, -1))
	## Prefer catalog mid-doors when they already face and survive carve empties.
	if mid_a != Vector2i(-1, -1) and mid_b != Vector2i(-1, -1):
		if (
			not _ascii_carved_empty(place_a, la, mid_a)
			and not _ascii_carved_empty(place_b, lb, mid_b)
			and _door_cells_face(dir_a, origin_a + mid_a, origin_b + mid_b)
		):
			return {"cell_a": mid_a, "cell_b": mid_b}
	for ca_variant in cells_a:
		var ca: Vector2i = ca_variant
		if _ascii_carved_empty(place_a, la, ca):
			continue
		var wa: Vector2i = origin_a + ca
		for cb_variant in cells_b:
			var cb: Vector2i = cb_variant
			if _ascii_carved_empty(place_b, lb, cb):
				continue
			var wb: Vector2i = origin_b + cb
			if _door_cells_face(dir_a, wa, wb):
				return {"cell_a": ca, "cell_b": cb}
	return {}


func _ascii_carved_empty(p: Placement, local_level: int, cell: Vector2i) -> bool:
	if p == null:
		return false
	for cell_variant in p.opts.get("carve_empty_ascii", []):
		var c: Vector3i = cell_variant
		if c.x == local_level and c.y == cell.x and c.z == cell.y:
			return true
	return false


func _door_cells_face(dir_a: ModuleContract.Dir, a: Vector2i, b: Vector2i) -> bool:
	match dir_a:
		ModuleContract.Dir.E:
			return b.x == a.x + 1 and a.y == b.y
		ModuleContract.Dir.W:
			return b.x == a.x - 1 and a.y == b.y
		ModuleContract.Dir.S:
			return b.y == a.y + 1 and a.x == b.x
		ModuleContract.Dir.N:
			return b.y == a.y - 1 and a.x == b.x
	return false


func _scan_doorways(spec: RoomSpec) -> Dictionary:
	var out := {}
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	for dir in dirs:
		var by_level := {}
		for level in spec.layer_count():
			var cell := _doorway_cell(spec, level, dir)
			if cell != Vector2i(-1, -1):
				by_level[level] = cell
		if not by_level.is_empty():
			out[dir] = by_level
	return out


func _scan_edge_walkables(spec: RoomSpec) -> Dictionary:
	var out := {}
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	for dir in dirs:
		var by_level := {}
		for level in spec.layer_count():
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
			if not cells.is_empty():
				by_level[level] = cells
		if not by_level.is_empty():
			out[dir] = by_level
	return out


func _doorway_cell(spec: RoomSpec, level: int, dir: ModuleContract.Dir) -> Vector2i:
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
		return Vector2i(-1, -1)
	var mid := Vector2(float(spec.width) * 0.5, float(spec.depth) * 0.5)
	var best := candidates[0]
	var best_d := INF
	for c in candidates:
		var d := Vector2(float(c.x) + 0.5, float(c.y) + 0.5).distance_squared_to(mid)
		if d < best_d:
			best_d = d
			best = c
	return best


func _pick_path_module(
	rng: RandomNumberGenerator,
	path_len: int,
	target: int,
	dir: ModuleContract.Dir,
	attach_lv: int
) -> StringName:
	## Mix halls / combat / stairs. Stairs only when the run axis matches and
	## there's vertical headroom for the landing.
	if path_len == maxi(1, int(target / 2)):
		return &"combat"
	var roll := rng.randf()
	if roll < 0.2 and _info(&"hall") != null and _placement_accepts_attach(&"hall", dir):
		return &"hall"
	if roll < 0.4:
		return &"combat"
	## Stacked climbs allowed up to max_stair_rises; foyer + floor clusters keep landings reachable.
	var can_stair := (
		_info(&"stair_test") != null
		and _stair_rises < params.max_stair_rises()
		and (dir == ModuleContract.Dir.E or dir == ModuleContract.Dir.W)
		and _placement_accepts_attach(&"stair_test", dir)
		and attach_lv + 1 <= params.max_level()
	)
	if roll < 0.68 and can_stair:
		return &"stair_test"
	return &"corridor"
