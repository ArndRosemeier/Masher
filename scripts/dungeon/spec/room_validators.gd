class_name RoomValidators
extends RefCounted
## Structural / stair / reachability checks. Returns error strings (empty = ok).


static func validate(spec: RoomSpec, require_player: bool = false, require_exit: bool = false) -> PackedStringArray:
	var errors: PackedStringArray = []
	errors.append_array(_validate_shape(spec))
	if not errors.is_empty():
		return errors
	errors.append_array(_validate_markers(spec, require_player, require_exit))
	errors.append_array(_validate_stairs(spec))
	errors.append_array(_validate_openings(spec))
	errors.append_array(_validate_reachability(spec, require_player, require_exit))
	return errors


static func validate_or_assert(spec: RoomSpec, require_player: bool = false, require_exit: bool = false) -> void:
	var errors := validate(spec, require_player, require_exit)
	if not errors.is_empty():
		for e in errors:
			push_error("[%s] %s" % [spec.id, e])
		assert(false, "RoomSpec validation failed for %s (%d errors)" % [spec.id, errors.size()])


static func _validate_shape(spec: RoomSpec) -> PackedStringArray:
	var errors: PackedStringArray = []
	if spec.layer_count() < 1:
		errors.append("no layers")
	if spec.width < 2 or spec.depth < 2:
		errors.append("map too small")
	if spec.cell_size <= 0.0 or spec.layer_height <= 0.0:
		errors.append("invalid cell/layer_height")
	return errors


static func _validate_markers(spec: RoomSpec, require_player: bool, require_exit: bool) -> PackedStringArray:
	var errors: PackedStringArray = []
	var players := 0
	var exits := 0
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				var k: int = spec.get_cell(level, x, z)
				if k == RoomCells.Kind.PLAYER:
					players += 1
				elif k == RoomCells.Kind.EXIT:
					exits += 1
	if require_player and players != 1:
		errors.append("expected exactly 1 player spawn, got %d" % players)
	if require_exit and exits != 1:
		errors.append("expected exactly 1 exit, got %d" % exits)
	if players > 1:
		errors.append("multiple player spawns")
	if exits > 1:
		errors.append("multiple exits")
	return errors


static func _validate_stairs(spec: RoomSpec) -> PackedStringArray:
	var errors: PackedStringArray = []
	var runs := StairDetector.detect(spec)
	for run in runs:
		if run.level + 1 >= spec.layer_count():
			errors.append("stair on top layer %d has no upper layer" % run.level)
			continue
		if run.length() < 2:
			errors.append("stair run too short")
			continue
		# Upper footprint must not be floor surface (baker owns stair column).
		for c in run.cells:
			var upper: int = spec.get_cell(run.level + 1, c.x, c.y)
			if RoomCells.is_floor_surface(upper):
				errors.append("upper floor blocks stair column at %s layer %d" % [c, run.level + 1])
			if upper == RoomCells.Kind.WALL:
				errors.append("wall blocks stair column at %s" % c)
		# Top must touch walkable floor surface on upper layer.
		var top := run.top()
		var touched := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = top + d
			if RoomCells.is_floor_surface(spec.get_cell(run.level + 1, n.x, n.y)):
				touched = true
				break
		if not touched:
			errors.append("stair top %s layer %d has no upper landing floor" % [top, run.level + 1])
		# Bottom must touch walkable floor on lower layer.
		var bottom := run.bottom()
		var bottom_ok := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n2: Vector2i = bottom + d
			if RoomCells.is_floor_surface(spec.get_cell(run.level, n2.x, n2.y)):
				bottom_ok = true
				break
		if not bottom_ok:
			errors.append("stair bottom %s layer %d has no lower floor access" % [bottom, run.level])
	return errors


static func _validate_openings(spec: RoomSpec) -> PackedStringArray:
	var errors: PackedStringArray = []
	for dir in spec.open_dirs:
		var found := false
		match dir:
			ModuleContract.Dir.N:
				for x in spec.width:
					if _edge_open(spec, x, 0):
						found = true
			ModuleContract.Dir.S:
				for x in spec.width:
					if _edge_open(spec, x, spec.depth - 1):
						found = true
			ModuleContract.Dir.W:
				for z in spec.depth:
					if _edge_open(spec, 0, z):
						found = true
			ModuleContract.Dir.E:
				for z in spec.depth:
					if _edge_open(spec, spec.width - 1, z):
						found = true
		if not found:
			errors.append("open %s has no walkable edge gap on layer 0" % ModuleContract.dir_name(dir))
	return errors


static func _edge_open(spec: RoomSpec, x: int, z: int) -> bool:
	## Doorways must be walkable floor (not void) so players don't fall through.
	return RoomCells.is_walkable(spec.get_cell(0, x, z))


static func _validate_reachability(spec: RoomSpec, require_player: bool, require_exit: bool) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not require_player:
		return errors
	var start := _find_kind(spec, RoomCells.Kind.PLAYER)
	if start == Vector3i(-1, -1, -1):
		return errors
	var runs := StairDetector.detect(spec)
	var reached := _flood_walkable(spec, start, runs)
	if require_exit:
		var exit_pos := _find_kind(spec, RoomCells.Kind.EXIT)
		if exit_pos != Vector3i(-1, -1, -1) and not reached.has(exit_pos):
			errors.append("exit unreachable from player spawn")
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if spec.get_cell(level, x, z) == RoomCells.Kind.ENEMY:
					var key := Vector3i(level, x, z)
					if not reached.has(key):
						errors.append("enemy spawn unreachable at %s" % key)
	return errors


static func _find_kind(spec: RoomSpec, kind: int) -> Vector3i:
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if spec.get_cell(level, x, z) == kind:
					return Vector3i(level, x, z)
	return Vector3i(-1, -1, -1)


static func _flood_walkable(spec: RoomSpec, start: Vector3i, runs: Array[StairRun]) -> Dictionary:
	## Keys: Vector3i(level, x, z)
	var reached: Dictionary = {}
	var stack: Array[Vector3i] = [start]
	while not stack.is_empty():
		var cur: Vector3i = stack.pop_back()
		if reached.has(cur):
			continue
		var level := cur.x
		var x := cur.y
		var z := cur.z
		var kind: int = spec.get_cell(level, x, z)
		if not RoomCells.is_walkable(kind):
			continue
		reached[cur] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var nz: int = z + d.y
			if spec.in_bounds(nx, nz) and RoomCells.is_walkable(spec.get_cell(level, nx, nz)):
				stack.append(Vector3i(level, nx, nz))
		if kind == RoomCells.Kind.STAIR:
			for run in runs:
				if run.level != level:
					continue
				var on_run := false
				for c in run.cells:
					if c.x == x and c.y == z:
						on_run = true
						break
				if not on_run:
					continue
				for c2 in run.cells:
					stack.append(Vector3i(level, c2.x, c2.y))
				var top := run.top()
				if x == top.x and z == top.y:
					for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var ux: int = top.x + d2.x
						var uz: int = top.y + d2.y
						if RoomCells.is_floor_surface(spec.get_cell(level + 1, ux, uz)):
							stack.append(Vector3i(level + 1, ux, uz))
		if RoomCells.is_floor_surface(kind):
			for run in runs:
				if run.level + 1 != level:
					continue
				var top2 := run.top()
				if absi(x - top2.x) + absi(z - top2.y) == 1:
					stack.append(Vector3i(run.level, top2.x, top2.y))
	return reached
