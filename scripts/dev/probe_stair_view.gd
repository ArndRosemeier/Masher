extends SceneTree
## Bake atrium, measure stair step heights, raycast ceilings, save screenshots.


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var out_dir := "res://_tmp/stair_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.45, 0.5)
	e.ambient_light_energy = 0.8
	env.environment = e
	vp.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 35, 0)
	light.light_energy = 1.1
	vp.add_child(light)

	var opens: Array[ModuleContract.Dir] = [ModuleContract.Dir.E, ModuleContract.Dir.D]
	var room := RoomFactory.build(&"atrium", opens, {"decor": false})
	room.position = Vector3.ZERO
	room.vertical_level = 0
	vp.add_child(room)

	var under_opens: Array[ModuleContract.Dir] = [ModuleContract.Dir.U]
	var under := RoomFactory.build(&"undercroft", under_opens, {"decor": false})
	under.position = ModuleContract.grid_to_world(Vector2i.ZERO, -1)
	under.vertical_level = -1
	vp.add_child(under)

	await process_frame
	await process_frame

	var spec: RoomSpec = room.spec
	var report := FileAccess.open(
		ProjectSettings.globalize_path(out_dir.path_join("report.txt")),
		FileAccess.WRITE
	)
	_analyze_stairs(room, spec, report)
	_analyze_ceilings(room, spec, report)

	var cam := Camera3D.new()
	cam.current = true
	vp.add_child(cam)

	## Layer-1 west stairs: bottom (2,7) → top (2,3), dir N.
	var shots: Array = [
		{
			"name": "L1_stairs_from_south_bottom",
			"pos": Vector3(5.0, 5.2, 18.0),
			"look": Vector3(5.0, 6.5, 10.0),
		},
		{
			"name": "L1_stairs_from_north_top",
			"pos": Vector3(3.5, 7.5, 4.0),
			"look": Vector3(5.0, 5.0, 12.0),
		},
		{
			"name": "L1_stairs_side",
			"pos": Vector3(-2.0, 6.5, 10.0),
			"look": Vector3(5.0, 6.0, 10.0),
		},
		{
			"name": "L0_up_stairs_east",
			"pos": Vector3(14.0, 2.0, 12.0),
			"look": Vector3(12.0, 3.5, 12.0),
		},
		{
			"name": "ceiling_from_L1_rim",
			"pos": Vector3(3.0, 5.5, 20.0),
			"look": Vector3(3.0, 8.0, 16.0),
		},
		{
			"name": "atrium_well_overview",
			"pos": Vector3(22.0, 14.0, 22.0),
			"look": Vector3(10.0, 4.0, 10.0),
		},
	]

	for shot in shots:
		cam.global_position = shot["pos"]
		cam.look_at(shot["look"], Vector3.UP)
		await process_frame
		await process_frame
		var img: Image = vp.get_texture().get_image()
		var path := out_dir.path_join("%s.png" % shot["name"])
		img.save_png(ProjectSettings.globalize_path(path))
		report.store_string("SHOT %s -> %s\n" % [shot["name"], path])
		print("SHOT ", shot["name"])

	report.close()
	print("PROBE_DONE ", out_dir)
	quit(0)


func _analyze_stairs(room: RoomModule, spec: RoomSpec, report: FileAccess) -> void:
	var runs := StairDetector.detect(spec)
	for run in runs:
		report.store_string(
			(
				"RUN asc=%s level=%d dir=%s bottom=%s top=%s\n"
				% [
					run.ascending,
					run.level,
					ModuleContract.dir_name(run.dir),
					str(run.bottom()),
					str(run.top()),
				]
			)
		)
		var root_name := "Stairs_%s_L%d" % ["Up" if run.ascending else "Down", run.level]
		var root := room.get_node_or_null(root_name)
		if root == null:
			report.store_string("  MISSING NODE %s\n" % root_name)
			continue
		var step_ys: Array[float] = []
		var step_zs: Array[float] = []
		var step_xs: Array[float] = []
		for child in root.get_children():
			if not String(child.name).begins_with("Step_"):
				continue
			## Prefer mesh visual position
			var p: Vector3 = (child as Node3D).position
			step_ys.append(p.y)
			step_zs.append(p.z)
			step_xs.append(p.x)
		if step_ys.is_empty():
			report.store_string("  no Step_* meshes\n")
			continue
		## Sort by index via name
		var indexed: Array = []
		for child in root.get_children():
			var nm := String(child.name)
			if nm.begins_with("Step_"):
				indexed.append([int(nm.get_slice("_", 1)), (child as Node3D).position])
		indexed.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		var y0: float = indexed[0][1].y
		var y1: float = indexed[indexed.size() - 1][1].y
		var z0: float = indexed[0][1].z
		var z1: float = indexed[indexed.size() - 1][1].z
		report.store_string(
			(
				"  steps=%d firstY=%.3f lastY=%.3f dY=%.3f firstZ=%.3f lastZ=%.3f dZ=%.3f\n"
				% [indexed.size(), y0, y1, y1 - y0, z0, z1, z1 - z0]
			)
		)
		var climbs_along_dir := (y1 - y0) > 0.5
		report.store_string(
			"  mesh_rises_along_run_dir=%s (expected true for ascending)\n" % climbs_along_dir
		)
		print(
			"RUN L",
			run.level,
			" asc=",
			run.ascending,
			" dY=",
			y1 - y0,
			" dZ=",
			z1 - z0,
			" rises=",
			climbs_along_dir
		)


func _analyze_ceilings(room: RoomModule, spec: RoomSpec, report: FileAccess) -> void:
	var space := room.get_world_3d().direct_space_state
	report.store_string("CEILING RAYS (from 0.5m above each walkable cell, up 6m)\n")
	var misses := 0
	var checks := 0
	for level in mini(2, spec.layer_count()):
		for z in spec.depth:
			for x in spec.width:
				var kind: int = spec.get_cell(level, x, z)
				if not RoomCells.is_floor_surface(kind) and kind != RoomCells.Kind.WALL:
					continue
				## Skip open well / shafts
				if kind == RoomCells.Kind.SHAFT or kind == RoomCells.Kind.DOWN_STAIR:
					continue
				if level + 1 < spec.layer_count():
					var above: int = spec.get_cell(level + 1, x, z)
					if above == RoomCells.Kind.EMPTY:
						continue ## intentional atrium void
				checks += 1
				var from := room.to_global(
					Vector3(
						(float(x) + 0.5) * spec.cell_size,
						float(level) * spec.layer_height + 0.5,
						(float(z) + 0.5) * spec.cell_size
					)
				)
				var to := from + Vector3(0.0, 6.0, 0.0)
				var q := PhysicsRayQueryParameters3D.create(from, to)
				q.collision_mask = 1
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					misses += 1
					if misses <= 12:
						report.store_string(
							"  MISS ceiling above L%d (%d,%d) kind=%s\n"
							% [level, x, z, RoomCells.to_char(kind)]
						)
	report.store_string("CEILING misses=%d / checks=%d\n" % [misses, checks])
	print("CEILING misses=", misses, "/", checks)
