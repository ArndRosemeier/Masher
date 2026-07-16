class_name RoomBaker
extends RefCounted
## Bakes a validated RoomSpec into a RoomModule (collision + visuals + markers).

const DOOR_SCENE := "res://scenes/dungeon/door.tscn"


static func bake(spec: RoomSpec) -> RoomModule:
	var room := RoomModule.new()
	room.name = String(spec.id)
	room.module_id = spec.id
	room.open_dirs = spec.open_dirs.duplicate()

	## Upper stair-column cells must stay open (no floor). Down-stair shafts are open
	## on their own layer. Lower ascending `S` cells still need a floor slab.
	var stair_skip_floor: Dictionary = {} ## Vector3i(level,x,z) -> true
	var runs := StairDetector.detect(spec)
	for run in runs:
		for c in run.cells:
			if run.ascending:
				stair_skip_floor[Vector3i(run.level + 1, c.x, c.y)] = true
			else:
				stair_skip_floor[Vector3i(run.level, c.x, c.y)] = true

	_add_floors(room, spec, stair_skip_floor)
	_add_walls(room, spec)
	_add_doorframes(room, spec)
	_bake_stairs(room, spec, runs)
	_add_ceiling(room, spec)
	_add_markers(room, spec)
	_add_connectors(room, spec)
	_add_doors(room, spec)
	_add_lights(room, spec)
	return room


## KayKit floor_tile_large is 4×4m; our ASCII cell is usually 2m → one tile covers 2×2 cells.
const KAYKIT_FLOOR_SIZE := 4.0
## Thin perimeter shells (also used by doorframes). `#` is no longer a solid 2m block.
const WALL_THICKNESS := 0.28


static func seal_closed_edges(spec: RoomSpec, extra_protected: Array = []) -> void:
	## Second pass before bake: turn exterior floor gaps that are not real doorways
	## into `#` so the F1 map matches 3D enclosure (DoorSeal alone left `.` on the map).
	var protected := _stair_landing_floors(spec)
	for cell_variant in extra_protected:
		var c: Vector3i = cell_variant
		protected[c] = true
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	for dir in dirs:
		for level in spec.layer_count():
			var edge := _edge_floor_cells(spec, level, dir)
			if edge.is_empty():
				continue
			var face_open := _face_open(spec, dir, level) and dir in spec.open_dirs
			var keep: Dictionary = {} ## Vector2i -> true
			if face_open:
				for dcell in _doorways_for_face(spec, dir, level, edge):
					keep[dcell] = true
			for cell in edge:
				if keep.has(cell):
					continue
				if protected.has(Vector3i(level, cell.x, cell.y)):
					continue
				spec.set_cell(level, cell.x, cell.y, RoomCells.Kind.WALL)


static func _stair_landing_floors(spec: RoomSpec) -> Dictionary:
	## Vector3i(level,x,z) → true. Keep stair approach + upper exit, then flood all
	## connected floors on that layer so sealing an open-face non-doorway rim cell
	## cannot cut the landing off from E/W doorways (stair_test shaft voids).
	var seeds: Dictionary = {}
	for run in StairDetector.detect(spec):
		var top: Vector2i = run.top()
		var bottom: Vector2i = run.bottom()
		var step: Vector2i = (top - bottom).sign()
		if run.ascending:
			var entry: Vector2i = bottom - step
			if spec.in_bounds(entry.x, entry.y):
				seeds[Vector3i(run.level, entry.x, entry.y)] = true
			if run.level + 1 < spec.layer_count():
				var exit_cell: Vector2i = top + step
				if spec.in_bounds(exit_cell.x, exit_cell.y):
					seeds[Vector3i(run.level + 1, exit_cell.x, exit_cell.y)] = true
		else:
			var approach: Vector2i = top + step
			if spec.in_bounds(approach.x, approach.y):
				seeds[Vector3i(run.level, approach.x, approach.y)] = true
	var out: Dictionary = {}
	var stack: Array[Vector3i] = []
	for key_variant in seeds.keys():
		var seed: Vector3i = key_variant
		if RoomCells.is_floor_surface(spec.get_cell(seed.x, seed.y, seed.z)):
			stack.append(seed)
	while not stack.is_empty():
		var key: Vector3i = stack.pop_back()
		if out.has(key):
			continue
		out[key] = true
		for d_variant in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var d: Vector2i = d_variant
			var nx: int = key.y + d.x
			var nz: int = key.z + d.y
			if not spec.in_bounds(nx, nz):
				continue
			if not RoomCells.is_floor_surface(spec.get_cell(key.x, nx, nz)):
				continue
			var nxt := Vector3i(key.x, nx, nz)
			if not out.has(nxt):
				stack.append(nxt)
	return out


static func _edge_floor_cells(spec: RoomSpec, level: int, dir: ModuleContract.Dir) -> Array[Vector2i]:
	## Only plain floor — never seal over P/E/M/S/D/^ markers.
	var cells: Array[Vector2i] = []
	match dir:
		ModuleContract.Dir.E:
			for z in spec.depth:
				if spec.get_cell(level, spec.width - 1, z) == RoomCells.Kind.FLOOR:
					cells.append(Vector2i(spec.width - 1, z))
		ModuleContract.Dir.W:
			for z in spec.depth:
				if spec.get_cell(level, 0, z) == RoomCells.Kind.FLOOR:
					cells.append(Vector2i(0, z))
		ModuleContract.Dir.S:
			for x in spec.width:
				if spec.get_cell(level, x, spec.depth - 1) == RoomCells.Kind.FLOOR:
					cells.append(Vector2i(x, spec.depth - 1))
		ModuleContract.Dir.N:
			for x in spec.width:
				if spec.get_cell(level, x, 0) == RoomCells.Kind.FLOOR:
					cells.append(Vector2i(x, 0))
	return cells


static func _doorways_for_face(
	spec: RoomSpec,
	dir: ModuleContract.Dir,
	level: int,
	edge: Array[Vector2i]
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var key := Vector2i(dir as int, level)
	if spec.doorway_cells.has(key):
		for cell_variant in spec.doorway_cells[key] as Array:
			var cell: Vector2i = cell_variant
			if RoomCells.is_walkable(spec.get_cell(level, cell.x, cell.y)):
				out.append(cell)
		if not out.is_empty():
			return out
	if not edge.is_empty():
		out.append(_pick_doorway_cell(spec, edge))
	return out


static func _cell_needs_floor(kind: int) -> bool:
	## Floors cover walkable cells and `#` wall cells so recessed outer shells enlarge the room.
	return RoomCells.is_floor_surface(kind) or kind == RoomCells.Kind.WALL


static func _add_floors(room: RoomModule, spec: RoomSpec, stair_skip_floor: Dictionary) -> void:
	# Collision per cell (no visual seams). KayKit tiles are the visible top.
	# Underside meshes close the see-through gap when looking up from below
	# (KayKit GLBs are typically single-sided).
	# `stair_skip_floor` = open shaft / upper stairwell (no floor).
	var under_mat := StandardMaterial3D.new()
	under_mat.albedo_color = Color(0.12, 0.11, 0.1)
	under_mat.roughness = 0.95
	under_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if stair_skip_floor.has(Vector3i(level, x, z)):
					continue
				var kind: int = spec.get_cell(level, x, z)
				if not _cell_needs_floor(kind):
					continue
				var y := float(level) * spec.layer_height
				var center := Vector3((float(x) + 0.5) * spec.cell_size, y, (float(z) + 0.5) * spec.cell_size)
				var thickness := 0.2
				_box(
					room,
					"Floor_%d_%d_%d" % [level, x, z],
					Vector3(center.x, y - thickness * 0.5, center.z),
					Vector3(spec.cell_size, thickness, spec.cell_size)
				)
				## Visual slab so the floor reads as a ceiling from below.
				var under := MeshInstance3D.new()
				under.name = "FloorUnder_%d_%d_%d" % [level, x, z]
				var under_mesh := BoxMesh.new()
				under_mesh.size = Vector3(spec.cell_size, thickness, spec.cell_size)
				under.mesh = under_mesh
				under.material_override = under_mat
				under.position = Vector3(center.x, y - thickness * 0.5, center.z)
				room.add_child(under)

		_add_kaykit_floor_tiles(room, spec, level, stair_skip_floor)


static func _add_kaykit_floor_tiles(
	room: RoomModule,
	spec: RoomSpec,
	level: int,
	stair_skip_floor: Dictionary
) -> void:
	var cells_per_tile := int(round(KAYKIT_FLOOR_SIZE / spec.cell_size))
	if cells_per_tile < 1:
		push_error("cell_size %s cannot host KayKit floor tile %s" % [spec.cell_size, KAYKIT_FLOOR_SIZE])
		return
	var y := float(level) * spec.layer_height
	var tz := 0
	while tz < spec.depth:
		var tx := 0
		while tx < spec.width:
			if _floor_tile_block_needed(spec, level, tx, tz, cells_per_tile, stair_skip_floor):
				var tile_i := int(tx / cells_per_tile)
				var tile_j := int(tz / cells_per_tile)
				var path := KaykitPaths.FLOOR if (tile_i + tile_j) % 2 == 0 else KaykitPaths.FLOOR_ROCKS
				var skin := _instance(path)
				# Tile origin is center; cover [tx,tx+n) × [tz,tz+n) in cell space.
				var half := KAYKIT_FLOOR_SIZE * 0.5
				skin.position = Vector3(
					float(tx) * spec.cell_size + half,
					y,
					float(tz) * spec.cell_size + half
				)
				room.add_child(skin)
			tx += cells_per_tile
		tz += cells_per_tile


static func _floor_tile_block_needed(
	spec: RoomSpec,
	level: int,
	tx: int,
	tz: int,
	cells_per_tile: int,
	stair_skip_floor: Dictionary
) -> bool:
	## Only place a KayKit tile when the full footprint is solid floor — never span a shaft.
	var x1 := mini(tx + cells_per_tile, spec.width)
	var z1 := mini(tz + cells_per_tile, spec.depth)
	if x1 - tx < cells_per_tile or z1 - tz < cells_per_tile:
		return false
	for z in range(tz, z1):
		for x in range(tx, x1):
			if stair_skip_floor.has(Vector3i(level, x, z)):
				return false
			if not _cell_needs_floor(spec.get_cell(level, x, z)):
				return false
	return true


static func _add_walls(room: RoomModule, spec: RoomSpec) -> void:
	## `#` marks wall *support* cells. Bake thin shells on exposed faces only:
	## prefer void/out-of-bounds faces so the shell sits on the outer edge and the
	## rest of the `#` cell becomes usable floor (rooms feel larger; props fit).
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.22, 0.2, 0.18)
	wall_mat.roughness = 0.95
	var piece_i := 0
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if spec.get_cell(level, x, z) != RoomCells.Kind.WALL:
					continue
				for dir in _exposed_wall_faces(spec, level, x, z):
					_bake_wall_face(
						room,
						spec,
						level,
						x,
						z,
						dir,
						"Wall_%d_%d" % [level, piece_i],
						wall_mat
					)
					piece_i += 1


static func _exposed_wall_faces(spec: RoomSpec, level: int, x: int, z: int) -> Array[ModuleContract.Dir]:
	var exterior: Array[ModuleContract.Dir] = []
	var interior: Array[ModuleContract.Dir] = []
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	for dir in dirs:
		var n := _neighbor_cell(spec, level, x, z, dir)
		if n == RoomCells.Kind.WALL:
			continue
		if n < 0 or n == RoomCells.Kind.EMPTY:
			exterior.append(dir)
		else:
			interior.append(dir)
	if not exterior.is_empty():
		return exterior
	return interior


static func _neighbor_cell(spec: RoomSpec, level: int, x: int, z: int, dir: ModuleContract.Dir) -> int:
	## Returns cell kind, or -1 when out of bounds.
	var nx := x
	var nz := z
	match dir:
		ModuleContract.Dir.N:
			nz -= 1
		ModuleContract.Dir.S:
			nz += 1
		ModuleContract.Dir.W:
			nx -= 1
		ModuleContract.Dir.E:
			nx += 1
	if not spec.in_bounds(nx, nz):
		return -1
	return spec.get_cell(level, nx, nz)


static func _bake_wall_face(
	room: RoomModule,
	spec: RoomSpec,
	level: int,
	x: int,
	z: int,
	dir: ModuleContract.Dir,
	name: String,
	wall_mat: StandardMaterial3D
) -> void:
	var cs := spec.cell_size
	var t := WALL_THICKNESS
	var wall_h := spec.layer_height
	var x0 := float(x) * cs
	var z0 := float(z) * cs
	var y_mid := float(level) * spec.layer_height + wall_h * 0.5
	var center := Vector3.ZERO
	var size := Vector3.ZERO
	match dir:
		ModuleContract.Dir.N:
			center = Vector3(x0 + cs * 0.5, y_mid, z0 + t * 0.5)
			size = Vector3(cs, wall_h, t)
		ModuleContract.Dir.S:
			center = Vector3(x0 + cs * 0.5, y_mid, z0 + cs - t * 0.5)
			size = Vector3(cs, wall_h, t)
		ModuleContract.Dir.W:
			center = Vector3(x0 + t * 0.5, y_mid, z0 + cs * 0.5)
			size = Vector3(t, wall_h, cs)
		ModuleContract.Dir.E:
			center = Vector3(x0 + cs - t * 0.5, y_mid, z0 + cs * 0.5)
			size = Vector3(t, wall_h, cs)
	_wall_piece(room, name, center, size, wall_mat)


## Must match scenes/dungeon/door.tscn panel (1.6 × 2.5) with small clearance.
const DOOR_OPEN_WIDTH := 1.64
const DOOR_OPEN_HEIGHT := 2.52
const DOOR_WALL_THICKNESS := WALL_THICKNESS
const MAX_STEP_HEIGHT := 0.22
const MIN_STEP_DEPTH := 0.28


static func _add_doorframes(room: RoomModule, spec: RoomSpec) -> void:
	## Walkable edge cells punch a full-height hole unless we shell them.
	## Open faces: one door gap + seals on the rest of that edge.
	## Closed faces (including upper stair landings with no procgen link): seal ALL
	## walkable edge cells so players can't stroll into the abyss.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.22, 0.2, 0.18)
	wall_mat.roughness = 0.95

	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]
	for dir in dirs:
		for level in spec.layer_count():
			var edge := _edge_walkable_cells(spec, level, dir)
			if edge.is_empty():
				continue
			if _face_open(spec, dir, level) and dir in spec.open_dirs:
				var doorways := _doorways_for_face(spec, dir, level, edge)
				var door_set: Dictionary = {}
				for doorway in doorways:
					door_set[doorway] = true
					_bake_doorframe_cell(room, spec, level, doorway, dir, wall_mat)
				for cell in edge:
					if door_set.has(cell):
						continue
					_bake_edge_seal_wall(room, spec, level, cell, dir, wall_mat)
			else:
				for cell in edge:
					_bake_edge_seal_wall(room, spec, level, cell, dir, wall_mat)


static func _face_open(spec: RoomSpec, dir: ModuleContract.Dir, level: int) -> bool:
	## Procgen supplies open_faces so upper-storey ASCII gaps don't become doors into void.
	if spec.open_faces.is_empty():
		return true
	var key := Vector2i(dir as int, level)
	for face_variant in spec.open_faces:
		var face: Vector2i = face_variant
		if face == key:
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
	assert(not candidates.is_empty(), "doorway pick requires candidates")
	var mid := Vector2(float(spec.width) * 0.5, float(spec.depth) * 0.5)
	var best := candidates[0]
	var best_d := INF
	for c in candidates:
		var d := Vector2(float(c.x) + 0.5, float(c.y) + 0.5).distance_squared_to(mid)
		if d < best_d:
			best_d = d
			best = c
	return best


static func _door_shell_center(spec: RoomSpec, cell: Vector2i, dir: ModuleContract.Dir) -> Vector3:
	## Center of a thin wall slab on the outer face of an edge cell (y filled by caller).
	var cs := spec.cell_size
	var t := DOOR_WALL_THICKNESS
	var cx := (float(cell.x) + 0.5) * cs
	var cz := (float(cell.y) + 0.5) * cs
	match dir:
		ModuleContract.Dir.E:
			return Vector3(float(spec.width) * cs - t * 0.5, 0.0, cz)
		ModuleContract.Dir.W:
			return Vector3(t * 0.5, 0.0, cz)
		ModuleContract.Dir.S:
			return Vector3(cx, 0.0, float(spec.depth) * cs - t * 0.5)
		ModuleContract.Dir.N:
			return Vector3(cx, 0.0, t * 0.5)
	return Vector3(cx, 0.0, cz)


static func _bake_edge_seal_wall(
	room: RoomModule,
	spec: RoomSpec,
	level: int,
	cell: Vector2i,
	dir: ModuleContract.Dir,
	wall_mat: StandardMaterial3D
) -> void:
	var t := DOOR_WALL_THICKNESS
	var wall_h := spec.layer_height
	var cs := spec.cell_size
	var face := _door_shell_center(spec, cell, dir)
	var y0 := float(level) * spec.layer_height
	var size := Vector3(t, wall_h, cs)
	match dir:
		ModuleContract.Dir.N, ModuleContract.Dir.S:
			size = Vector3(cs, wall_h, t)
	_wall_piece(
		room,
		"DoorSeal_%s_L%d_%d_%d" % [ModuleContract.dir_name(dir), level, cell.x, cell.y],
		Vector3(face.x, y0 + wall_h * 0.5, face.z),
		size,
		wall_mat
	)


static func _bake_doorframe_cell(
	room: RoomModule,
	spec: RoomSpec,
	level: int,
	cell: Vector2i,
	dir: ModuleContract.Dir,
	wall_mat: StandardMaterial3D
) -> void:
	var cs := spec.cell_size
	var t := DOOR_WALL_THICKNESS
	var wall_h := spec.layer_height
	var face := _door_shell_center(spec, cell, dir)
	var y0 := float(level) * spec.layer_height
	var x0 := float(cell.x) * cs
	var z0 := float(cell.y) * cs

	var hole_w := mini(DOOR_OPEN_WIDTH, cs - 0.08)
	var hole_h := mini(DOOR_OPEN_HEIGHT, wall_h - 0.05)
	var side := (cs - hole_w) * 0.5
	var lintel_h := wall_h - hole_h
	var tag := "%s_L%d" % [ModuleContract.dir_name(dir), level]

	if lintel_h > 0.05:
		var lintel_size := Vector3(t, lintel_h, cs)
		if dir == ModuleContract.Dir.N or dir == ModuleContract.Dir.S:
			lintel_size = Vector3(cs, lintel_h, t)
		_wall_piece(
			room,
			"DoorLintel_%s" % tag,
			Vector3(face.x, y0 + hole_h + lintel_h * 0.5, face.z),
			lintel_size,
			wall_mat
		)

	if side > 0.04:
		match dir:
			ModuleContract.Dir.E, ModuleContract.Dir.W:
				_wall_piece(
					room,
					"DoorJambA_%s" % tag,
					Vector3(face.x, y0 + hole_h * 0.5, z0 + side * 0.5),
					Vector3(t, hole_h, side),
					wall_mat
				)
				_wall_piece(
					room,
					"DoorJambB_%s" % tag,
					Vector3(face.x, y0 + hole_h * 0.5, z0 + cs - side * 0.5),
					Vector3(t, hole_h, side),
					wall_mat
				)
			ModuleContract.Dir.N, ModuleContract.Dir.S:
				_wall_piece(
					room,
					"DoorJambA_%s" % tag,
					Vector3(x0 + side * 0.5, y0 + hole_h * 0.5, face.z),
					Vector3(side, hole_h, t),
					wall_mat
				)
				_wall_piece(
					room,
					"DoorJambB_%s" % tag,
					Vector3(x0 + cs - side * 0.5, y0 + hole_h * 0.5, face.z),
					Vector3(side, hole_h, t),
					wall_mat
				)


static func _wall_piece(
	room: RoomModule,
	name: String,
	pos: Vector3,
	size: Vector3,
	wall_mat: StandardMaterial3D
) -> void:
	_box(room, name, pos, size)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = wall_mat
	mesh.position = pos
	room.add_child(mesh)


static func _bake_stairs(room: RoomModule, spec: RoomSpec, runs: Array[StairRun]) -> void:
	## ASCII `S` rises one layer; `D` descends one layer_height (level connector).
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.28, 0.16)
	mat.roughness = 0.9

	for run in runs:
		var root := Node3D.new()
		root.name = "Stairs_%s_L%d" % ["Up" if run.ascending else "Down", run.level]
		room.add_child(root)

		var rise := spec.layer_height
		var run_len := float(run.length()) * spec.cell_size
		var steps := maxi(
			int(ceil(rise / MAX_STEP_HEIGHT)),
			int(ceil(run_len / MIN_STEP_DEPTH))
		)
		var step_h := rise / float(steps)
		var step_d := run_len / float(steps)
		var width := spec.cell_size
		## Ascending: stand on layer floor and climb up. Descending: shaft opens at
		## layer floor; steps drop to the level below (sibling module / undercroft).
		var base_y := float(run.level) * spec.layer_height
		if not run.ascending:
			base_y -= spec.layer_height

		var bottom := run.bottom()
		var axis := ModuleContract.dir_vector(run.dir)
		var origin := Vector3(
			(float(bottom.x) + 0.5) * spec.cell_size,
			base_y,
			(float(bottom.y) + 0.5) * spec.cell_size
		)
		origin -= axis * (spec.cell_size * 0.5)

		## Treads are visual only. CharacterBody3D has no step-up logic, so
		## per-tread collision boxes read as walls and block the climb.
		for i in steps:
			var along := step_d * (float(i) + 0.5)
			var center := origin + axis * along
			var tread_top := base_y + step_h * float(i + 1)
			center.y = tread_top - step_h * 0.5
			var depth := step_d + 0.02
			var size := Vector3(width, step_h, depth) if absf(axis.z) > 0.5 else Vector3(depth, step_h, width)

			var mesh := MeshInstance3D.new()
			mesh.name = "Step_%d" % i
			var box := BoxMesh.new()
			box.size = size
			mesh.mesh = box
			mesh.material_override = mat
			mesh.position = center
			root.add_child(mesh)

		_add_stair_ramp(root, mat, origin, axis, run_len, rise, width)


static func _add_stair_ramp(
	root: Node3D,
	mat: StandardMaterial3D,
	origin: Vector3,
	axis: Vector3,
	run_len: float,
	rise: float,
	width: float
) -> void:
	## Slope reaches full height before the cell edge, then a flat top runs into
	## the landing. The wedge's only vertical face sits under the landing floor
	## (past `endp`) so the capsule never meets a wall at the top seam.
	var lat := Vector3(axis.z, 0.0, -axis.x)
	var hw := width * 0.5
	var start := origin
	var endp := origin + axis * run_len
	## Reach full height ~0.5m before the seam (capsule radius is 0.35).
	var flat_start := origin + axis * maxf(run_len - 0.55, run_len * 0.7)
	var pad := endp + axis * 0.85
	var top := Vector3(0.0, rise, 0.0)

	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([
		start - lat * hw,
		start + lat * hw,
		pad - lat * hw,
		pad + lat * hw,
		flat_start - lat * hw + top,
		flat_start + lat * hw + top,
		pad - lat * hw + top,
		pad + lat * hw + top,
	])
	var body := StaticBody3D.new()
	body.name = "StairRamp"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = wedge
	body.add_child(col)
	root.add_child(body)

	var prism := PrismMesh.new()
	prism.left_to_right = 1.0
	prism.size = Vector3(run_len, rise, width)
	var prism_inst := MeshInstance3D.new()
	prism_inst.name = "StairWedge"
	prism_inst.mesh = prism
	prism_inst.material_override = mat
	prism_inst.basis = Basis(axis, Vector3.UP, axis.cross(Vector3.UP))
	prism_inst.position = origin + axis * (run_len * 0.5) + Vector3(0.0, rise * 0.5, 0.0)
	root.add_child(prism_inst)


static func _add_ceiling(room: RoomModule, spec: RoomSpec) -> void:
	## Per-cell ceiling so `^` / `D` shafts stay open for vertical connectors.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.16, 0.14, 0.12)
	wall_mat.roughness = 0.95
	var top_level := spec.layer_count() - 1
	var y := float(spec.layer_count()) * spec.layer_height + 0.1
	var cs := spec.cell_size
	var thickness := 0.25
	for z in spec.depth:
		for x in spec.width:
			var kind: int = spec.get_cell(top_level, x, z)
			if not RoomCells.blocks_ceiling(kind):
				continue
			# Also leave ceiling open above any down-stair shaft on lower layers of this room.
			var shaft_below := false
			for level in spec.layer_count():
				var k2: int = spec.get_cell(level, x, z)
				if k2 == RoomCells.Kind.DOWN_STAIR or k2 == RoomCells.Kind.SHAFT:
					shaft_below = true
					break
			if shaft_below:
				continue
			var center := Vector3((float(x) + 0.5) * cs, y, (float(z) + 0.5) * cs)
			_wall_piece(
				room,
				"Ceiling_%d_%d" % [x, z],
				center,
				Vector3(cs, thickness, cs),
				wall_mat
			)


static func _add_markers(room: RoomModule, spec: RoomSpec) -> void:
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				var kind: int = spec.get_cell(level, x, z)
				var pos := spec.cell_center(level, x, z) + Vector3(0.0, 0.15, 0.0)
				match kind:
					RoomCells.Kind.PLAYER:
						_marker(room, "PlayerSpawn", ModuleContract.GROUP_PLAYER_SPAWN, pos)
					RoomCells.Kind.EXIT:
						_marker(room, "Exit", ModuleContract.GROUP_EXIT, pos)
					RoomCells.Kind.ENEMY:
						pos = _enemy_spawn_pos(spec, level, x, z)
						_marker(room, "EnemySpawn_%d_%d_%d" % [level, x, z], ModuleContract.GROUP_ENEMY_SPAWN, pos)


static func _enemy_spawn_pos(spec: RoomSpec, level: int, x: int, z: int) -> Vector3:
	## Keep mobs off closed-door planes so meshes don't poke through the panel.
	var pos := spec.cell_center(level, x, z) + Vector3(0.0, 0.15, 0.0)
	var cs := spec.cell_size
	var inset := 1.85
	var max_x := float(spec.width) * cs
	var max_z := float(spec.depth) * cs
	for dir in spec.open_dirs:
		if ModuleContract.is_vertical(dir):
			continue
		if not _face_open(spec, dir, level):
			continue
		match dir:
			ModuleContract.Dir.N:
				pos.z = maxf(pos.z, inset)
			ModuleContract.Dir.S:
				pos.z = minf(pos.z, max_z - inset)
			ModuleContract.Dir.W:
				pos.x = maxf(pos.x, inset)
			ModuleContract.Dir.E:
				pos.x = minf(pos.x, max_x - inset)
	return pos


static func _add_connectors(room: RoomModule, spec: RoomSpec) -> void:
	var wx := float(spec.width) * spec.cell_size
	var wz := float(spec.depth) * spec.cell_size
	for dir in spec.open_dirs:
		var marker := Marker3D.new()
		marker.name = "Connector_%s" % ModuleContract.dir_name(dir)
		if ModuleContract.is_vertical(dir):
			var shaft := _find_vertical_shaft_cell(spec, dir)
			if shaft != Vector2i(-1, -1):
				var c := spec.cell_center(0, shaft.x, shaft.y)
				marker.position = Vector3(
					c.x,
					spec.layer_height if dir == ModuleContract.Dir.U else 0.0,
					c.z
				)
			else:
				marker.position = Vector3(wx * 0.5, 0.0, wz * 0.5)
		else:
			var door_level := _primary_door_level(spec, dir)
			var door_cell := _find_doorway_cell(spec, door_level, dir)
			var y := float(door_level) * spec.layer_height
			if door_cell != Vector2i(-1, -1):
				var c := spec.cell_center(door_level, door_cell.x, door_cell.y)
				match dir:
					ModuleContract.Dir.N:
						marker.position = Vector3(c.x, y, 0.0)
					ModuleContract.Dir.S:
						marker.position = Vector3(c.x, y, wz)
					ModuleContract.Dir.W:
						marker.position = Vector3(0.0, y, c.z)
					ModuleContract.Dir.E:
						marker.position = Vector3(wx, y, c.z)
			else:
				match dir:
					ModuleContract.Dir.N:
						marker.position = Vector3(wx * 0.5, y, 0.0)
					ModuleContract.Dir.S:
						marker.position = Vector3(wx * 0.5, y, wz)
					ModuleContract.Dir.W:
						marker.position = Vector3(0.0, y, wz * 0.5)
					ModuleContract.Dir.E:
						marker.position = Vector3(wx, y, wz * 0.5)
		room.add_child(marker)
		room.register_connector(dir, marker)


static func _find_vertical_shaft_cell(spec: RoomSpec, dir: ModuleContract.Dir) -> Vector2i:
	var mid := Vector2(float(spec.width) * 0.5, float(spec.depth) * 0.5)
	var best := Vector2i(-1, -1)
	var best_d := INF
	for z in spec.depth:
		for x in spec.width:
			var kind: int = spec.get_cell(0, x, z)
			var ok := (
				(dir == ModuleContract.Dir.D and RoomCells.is_down_stair(kind))
				or (dir == ModuleContract.Dir.U and kind == RoomCells.Kind.SHAFT)
			)
			if not ok:
				continue
			var d := Vector2(float(x) + 0.5, float(z) + 0.5).distance_squared_to(mid)
			if d < best_d:
				best_d = d
				best = Vector2i(x, z)
	return best


static func _add_doors(room: RoomModule, spec: RoomSpec) -> void:
	var packed := load(DOOR_SCENE) as PackedScene
	if packed == null:
		return
	for dir in spec.open_dirs:
		if dir != ModuleContract.Dir.E and dir != ModuleContract.Dir.S:
			continue
		var any := false
		for level in spec.layer_count():
			if not _face_open(spec, dir, level):
				continue
			var door_cell := _find_doorway_cell(spec, level, dir)
			if door_cell == Vector2i(-1, -1):
				continue
			any = true
			var door := packed.instantiate() as Door
			if door == null:
				continue
			door.name = "Door_%s_L%d" % [ModuleContract.dir_name(dir), level]
			var pos := spec.cell_center(level, door_cell.x, door_cell.y)
			var y := float(level) * spec.layer_height
			match dir:
				ModuleContract.Dir.E:
					door.position = Vector3(float(spec.width) * spec.cell_size, y, pos.z)
					door.rotation.y = -PI * 0.5
					door.open_angle_deg = -95.0
				ModuleContract.Dir.S:
					door.position = Vector3(pos.x, y, float(spec.depth) * spec.cell_size)
					door.rotation.y = PI
					door.open_angle_deg = -95.0
				ModuleContract.Dir.W:
					door.position = Vector3(0.0, y, pos.z)
					door.rotation.y = PI * 0.5
					door.open_angle_deg = -95.0
				ModuleContract.Dir.N:
					door.position = Vector3(pos.x, y, 0.0)
					door.rotation.y = 0.0
					door.open_angle_deg = -95.0
			room.add_child(door)
		if not any:
			push_error("No doorway cell for open %s in %s" % [ModuleContract.dir_name(dir), spec.id])


static func _primary_door_level(spec: RoomSpec, dir: ModuleContract.Dir) -> int:
	## Highest local layer with an opening in `dir` (balcony exits beat ground).
	var best := 0
	var found := false
	for level in spec.layer_count():
		if not _edge_walkable_cells(spec, level, dir).is_empty():
			best = level
			found = true
	return best if found else 0


static func _find_doorway_cell(spec: RoomSpec, level: int, dir: ModuleContract.Dir) -> Vector2i:
	var candidates := _edge_walkable_cells(spec, level, dir)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return _pick_doorway_cell(spec, candidates)


static func _add_lights(room: RoomModule, spec: RoomSpec) -> void:
	var wx := float(spec.width) * spec.cell_size
	var wz := float(spec.depth) * spec.cell_size
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.35)
	light.light_energy = 1.8 + 0.4 * float(spec.layer_count())
	light.omni_range = maxf(wx, wz) * 0.7
	light.shadow_enabled = true
	light.position = Vector3(wx * 0.5, spec.layer_height * float(spec.layer_count()) * 0.55, wz * 0.5)
	room.add_child(light)


static func _marker(room: RoomModule, node_name: String, group: StringName, pos: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.position = pos
	marker.add_to_group(group)
	room.add_child(marker)


static func _box(parent: Node, name: String, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


static func _instance(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("KayKit mesh missing: %s" % path)
		var stub := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1, 1, 1)
		stub.mesh = box
		return stub
	return packed.instantiate() as Node3D


static func probe_walkable(room: RoomModule, spec: RoomSpec) -> PackedStringArray:
	## Downward rays above each walkable cell must hit world collision.
	var errors: PackedStringArray = []
	var space := room.get_world_3d()
	if space == null:
		errors.append("probe requires room in tree with World3D")
		return errors
	var state := space.direct_space_state
	var runs := StairDetector.detect(spec)
	var stair_upper: Dictionary = {}
	for run in runs:
		if not run.ascending:
			continue
		for c in run.cells:
			stair_upper[Vector3i(run.level + 1, c.x, c.y)] = true

	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				var kind: int = spec.get_cell(level, x, z)
				# Stair treads are thin strips; probe flat floors only. Stair runs are checked structurally.
				if (
					kind == RoomCells.Kind.STAIR
					or kind == RoomCells.Kind.DOWN_STAIR
					or stair_upper.has(Vector3i(level, x, z))
				):
					continue
				if not RoomCells.is_floor_surface(kind) and kind != RoomCells.Kind.WALL:
					continue
				# Start above this level's ceiling band so we never begin inside a stair step.
				var local_origin := Vector3(
					(float(x) + 0.5) * spec.cell_size,
					float(level) * spec.layer_height + spec.layer_height + 0.35,
					(float(z) + 0.5) * spec.cell_size
				)
				var origin := room.global_transform * local_origin
				var to := origin + Vector3(0.0, -(spec.layer_height + 0.8), 0.0)
				var query := PhysicsRayQueryParameters3D.create(origin, to)
				query.collision_mask = 1
				var hit := state.intersect_ray(query)
				if hit.is_empty():
					errors.append("probe miss at L%d (%d,%d)" % [level, x, z])
	return errors
