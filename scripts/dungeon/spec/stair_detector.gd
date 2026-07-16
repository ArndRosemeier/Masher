class_name StairDetector
extends RefCounted
## Finds contiguous S (up) and D (down) runs and infers climb direction.


static func detect(spec: RoomSpec) -> Array[StairRun]:
	var runs: Array[StairRun] = []
	runs.append_array(_detect_kind(spec, RoomCells.Kind.STAIR, true))
	runs.append_array(_detect_kind(spec, RoomCells.Kind.DOWN_STAIR, false))
	return runs


static func _detect_kind(spec: RoomSpec, kind: int, ascending: bool) -> Array[StairRun]:
	var runs: Array[StairRun] = []
	var visited: Dictionary = {}
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				var key := Vector3i(level, x, z)
				if visited.has(key):
					continue
				if spec.get_cell(level, x, z) != kind:
					continue
				var component := _flood(spec, level, x, z, kind, visited)
				var run := _component_to_run(spec, level, component, ascending)
				runs.append(run)
	return runs


static func _flood(
	spec: RoomSpec,
	level: int,
	sx: int,
	sz: int,
	kind: int,
	visited: Dictionary
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var stack: Array[Vector2i] = [Vector2i(sx, sz)]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var key := Vector3i(level, c.x, c.y)
		if visited.has(key):
			continue
		if spec.get_cell(level, c.x, c.y) != kind:
			continue
		visited[key] = true
		out.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if spec.in_bounds(n.x, n.y):
				stack.append(n)
	return out


static func _component_to_run(
	spec: RoomSpec,
	level: int,
	component: Array[Vector2i],
	ascending: bool
) -> StairRun:
	assert(component.size() >= 2, "Stair run too short at layer %d" % level)
	var min_x := component[0].x
	var max_x := component[0].x
	var min_z := component[0].y
	var max_z := component[0].y
	for c in component:
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y)
		max_z = maxi(max_z, c.y)
	var span_x := max_x - min_x
	var span_z := max_z - min_z
	assert(span_x == 0 or span_z == 0, "Stair run must be a straight line at layer %d" % level)
	assert(component.size() == maxi(span_x, span_z) + 1, "Stair run must be contiguous line at layer %d" % level)

	var run := StairRun.new()
	run.level = level
	run.ascending = ascending
	var along_x := span_x >= span_z

	# Ends of the line. Bottom = low end of the climb (more floor touch for up-stairs;
	# for down-stairs the high end is the approach from this layer's floor).
	var end_a: Vector2i
	var end_b: Vector2i
	if along_x:
		end_a = Vector2i(min_x, min_z)
		end_b = Vector2i(max_x, min_z)
	else:
		end_a = Vector2i(min_x, min_z)
		end_b = Vector2i(min_x, max_z)

	# Score both orientations by where the actual landings are: the entry needs
	# floor on this layer at the bottom, the exit needs floor on the layer above
	# at the top (ascending) or an approach floor at the top (descending).
	var score_ab := _orientation_score(spec, level, end_a, end_b, ascending)
	var score_ba := _orientation_score(spec, level, end_b, end_a, ascending)
	# Equal scores mean both orientations are equally valid (symmetric run) or
	# equally broken — the validators reject the latter with a loud error.
	# Tie-break deterministically: ascending climbs from the min end; descending
	# descends toward the min end (the shaft landing in the room below usually
	# sits at the low-coordinate side, e.g. atrium → undercroft).
	var a_is_bottom := score_ab > score_ba or (score_ab == score_ba and ascending)
	var bottom := end_a if a_is_bottom else end_b
	var top := end_b if a_is_bottom else end_a

	if along_x:
		run.dir = ModuleContract.Dir.E if top.x > bottom.x else ModuleContract.Dir.W
		var x := bottom.x
		var step := 1 if top.x > bottom.x else -1
		while true:
			run.cells.append(Vector2i(x, bottom.y))
			if x == top.x:
				break
			x += step
	else:
		run.dir = ModuleContract.Dir.S if top.y > bottom.y else ModuleContract.Dir.N
		var z := bottom.y
		var stepz := 1 if top.y > bottom.y else -1
		while true:
			run.cells.append(Vector2i(bottom.x, z))
			if z == top.y:
				break
			z += stepz
	return run


static func _orientation_score(
	spec: RoomSpec,
	level: int,
	bottom: Vector2i,
	top: Vector2i,
	ascending: bool
) -> int:
	## Ascending: entry floor on this layer straight before the bottom, exit floor
	## on the layer above straight past the top. Descending: approach floor on
	## this layer straight past the top (the bottom drops into the room below).
	var step := (top - bottom).sign()
	if ascending:
		var score := 0
		if _is_floor_at(spec, level, bottom - step):
			score += 1
		if _is_floor_at(spec, level + 1, top + step):
			score += 2
		return score
	return 1 if _is_floor_at(spec, level, top + step) else 0


static func _is_floor_at(spec: RoomSpec, level: int, cell: Vector2i) -> bool:
	if level >= spec.layer_count():
		return false
	if not spec.in_bounds(cell.x, cell.y):
		return false
	return RoomCells.is_floor_surface(spec.get_cell(level, cell.x, cell.y))
