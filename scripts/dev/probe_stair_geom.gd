extends SceneTree
## Geometry-only stair/ceiling probe (no SubViewport — headless-safe).


func _init() -> void:
	var opens: Array[ModuleContract.Dir] = [ModuleContract.Dir.E, ModuleContract.Dir.D]
	var room := RoomFactory.build(&"atrium", opens, {"decor": false})
	root.add_child(room)
	var spec: RoomSpec = room.spec

	print("=== STAIR MESHES ===")
	for run in StairDetector.detect(spec):
		var root_name := "Stairs_%s_L%d" % ["Up" if run.ascending else "Down", run.level]
		var node := room.get_node_or_null(root_name)
		print(
			"RUN asc=", run.ascending,
			" L", run.level,
			" dir=", ModuleContract.dir_name(run.dir),
			" bottom=", run.bottom(),
			" top=", run.top()
		)
		if node == null:
			print("  MISSING ", root_name)
			continue
		var indexed: Array = []
		for child in node.get_children():
			var nm := String(child.name)
			if nm.begins_with("Step_"):
				indexed.append([int(nm.get_slice("_", 1)), (child as Node3D).position])
		indexed.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		if indexed.is_empty():
			print("  no steps")
			continue
		var a: Vector3 = indexed[0][1]
		var b: Vector3 = indexed[indexed.size() - 1][1]
		print(
			"  steps=", indexed.size(),
			" Y ", a.y, " -> ", b.y, " dY=", b.y - a.y,
			" Z ", a.z, " -> ", b.z, " dZ=", b.z - a.z,
			" X ", a.x, " -> ", b.x
		)
		print("  rises_with_run=", (b.y - a.y) > 0.5)

	print("=== CEILING GAPS (no floor above walkable cell) ===")
	var gaps := 0
	for level in range(spec.layer_count() - 1):
		for z in spec.depth:
			for x in spec.width:
				var kind: int = spec.get_cell(level, x, z)
				if not RoomCells.is_floor_surface(kind) and kind != RoomCells.Kind.WALL:
					continue
				var above: int = spec.get_cell(level + 1, x, z)
				## Intentional open well / shaft
				if above == RoomCells.Kind.EMPTY:
					continue
				if above == RoomCells.Kind.DOWN_STAIR or above == RoomCells.Kind.SHAFT:
					continue
				## Upper stair column void is intentional
				if kind == RoomCells.Kind.STAIR:
					continue
				## Has solid above?
				if (
					RoomCells.is_floor_surface(above)
					or above == RoomCells.Kind.WALL
					or above == RoomCells.Kind.STAIR
				):
					continue
				gaps += 1
				if gaps <= 20:
					print("  GAP L", level, "->", level + 1, " (", x, ",", z, ") below=", RoomCells.to_char(kind), " above=", RoomCells.to_char(above))
	print("GAP_COUNT ", gaps)

	print("=== VISUAL CEILING MESHES ===")
	var ceilings := 0
	for child in room.get_children():
		if String(child.name).begins_with("Ceiling_"):
			ceilings += 1
	print("Ceiling_* count=", ceilings, " (only top slab today)")

	## Map model links vs run ascending
	var model := DungeonMapModel.build([room])
	print("=== MAP LINKS ===")
	for link in model.vertical_links:
		print(
			link.label,
			" paired=", link.paired,
			" kind=", link.kind,
			" from=", link.from_anchor,
			" to=", link.to_anchor
		)
	print("DONE")
	quit(0)
