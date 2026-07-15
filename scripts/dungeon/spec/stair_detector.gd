class_name StairDetector
extends RefCounted
## Finds contiguous S runs and infers climb direction.


static func detect(spec: RoomSpec) -> Array[StairRun]:
	var runs: Array[StairRun] = []
	var visited: Dictionary = {}
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				var key := Vector3i(level, x, z)
				if visited.has(key):
					continue
				if spec.get_cell(level, x, z) != RoomCells.Kind.STAIR:
					continue
				var component := _flood(spec, level, x, z, visited)
				var run := _component_to_run(spec, level, component)
				runs.append(run)
	return runs


static func _flood(spec: RoomSpec, level: int, sx: int, sz: int, visited: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var stack: Array[Vector2i] = [Vector2i(sx, sz)]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var key := Vector3i(level, c.x, c.y)
		if visited.has(key):
			continue
		if spec.get_cell(level, c.x, c.y) != RoomCells.Kind.STAIR:
			continue
		visited[key] = true
		out.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if spec.in_bounds(n.x, n.y):
				stack.append(n)
	return out


static func _component_to_run(spec: RoomSpec, level: int, component: Array[Vector2i]) -> StairRun:
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
	var along_x := span_x >= span_z

	# Order candidates: ends of the line. Bottom = end with more walkable non-stair neighbors on this layer.
	var end_a: Vector2i
	var end_b: Vector2i
	if along_x:
		end_a = Vector2i(min_x, min_z)
		end_b = Vector2i(max_x, min_z)
	else:
		end_a = Vector2i(min_x, min_z)
		end_b = Vector2i(min_x, max_z)

	var score_a := _floor_touch_score(spec, level, end_a)
	var score_b := _floor_touch_score(spec, level, end_b)
	var bottom := end_a if score_a >= score_b else end_b
	var top := end_b if bottom == end_a else end_a

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


static func _floor_touch_score(spec: RoomSpec, level: int, cell: Vector2i) -> int:
	var score := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if not spec.in_bounds(n.x, n.y):
			continue
		var kind: int = spec.get_cell(level, n.x, n.y)
		if RoomCells.is_floor_surface(kind):
			score += 2
		elif RoomCells.is_walkable(kind):
			score += 1
	return score
