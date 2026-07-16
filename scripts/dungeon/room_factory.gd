class_name RoomFactory
extends RefCounted
## Builds rooms from ASCII specs (parse → validate → bake), then dresses with KayKit props.

const ROOMS_DIR := "res://rooms/"


static func build(
	module_id: StringName,
	open_dirs: Array[ModuleContract.Dir],
	opts: Dictionary = {}
) -> RoomModule:
	var path := "%s%s.room.txt" % [ROOMS_DIR, String(module_id)]
	assert(FileAccess.file_exists(path), "Missing room spec: %s" % path)

	var spec := RoomSpecParser.parse_file(path)
	## Procgen passes force_open_dirs so empty means "no doors" (never fall back to file meta).
	if bool(opts.get("force_open_dirs", false)):
		spec.open_dirs = open_dirs.duplicate()
	elif not open_dirs.is_empty():
		spec.open_dirs = open_dirs.duplicate()
	if opts.has("open_faces"):
		spec.open_faces = (opts["open_faces"] as Array).duplicate()
	if opts.has("doorway_cells"):
		spec.doorway_cells = (opts["doorway_cells"] as Dictionary).duplicate()

	if bool(opts.get("clear_player", false)):
		_clear_kind(spec, RoomCells.Kind.PLAYER)
	if bool(opts.get("player_spawn", false)):
		_ensure_marker(spec, RoomCells.Kind.PLAYER)
	if bool(opts.get("exit", false)):
		_ensure_marker(spec, RoomCells.Kind.EXIT)

	## Intentional overlap from hybrid carve pass (before validation).
	const Carve := preload("res://scripts/procgen/carve_merger.gd")
	Carve.apply_to_spec(spec, opts)

	var want_player := bool(opts.get("player_spawn", false))
	var want_exit := bool(opts.get("exit", false))
	## Honor markers present after optional inject/clear.
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				var k: int = spec.get_cell(level, x, z)
				if k == RoomCells.Kind.PLAYER:
					want_player = true
				elif k == RoomCells.Kind.EXIT:
					want_exit = true

	# Optional: inject enemy markers if opts request more than ASCII provides
	var enemy_count: int = int(opts.get("enemy_spawns", 0))
	if enemy_count > 0:
		_ensure_enemy_markers(spec, enemy_count)

	RoomValidators.validate_or_assert(spec, want_player, want_exit)
	## Close unused doorway gaps in the ASCII itself so map + walls agree.
	if not bool(opts.get("skip_edge_seal", false)):
		## Only host carve-opens need seal protection; emptied guest cells are void.
		RoomBaker.seal_closed_edges(spec, opts.get("carve_open_ascii", []))
	var room := RoomBaker.bake(spec)
	room.spec = spec
	room.add_to_group(ModuleContract.GROUP_MODULE)
	if (
		not (opts.get("carve_open_ascii", []) as Array).is_empty()
		or not (opts.get("carve_empty_ascii", []) as Array).is_empty()
	):
		room.set_meta("carve_ok", true)

	var dress := bool(opts.get("decor", true))
	if dress:
		_add_torches(room, spec)
		_add_sparse_decor(room, spec, module_id)
	if bool(opts.get("exit", false)) or want_exit:
		_place_exit_chest(room, spec)
	return room


static func _clear_kind(spec: RoomSpec, kind: int) -> void:
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if spec.get_cell(level, x, z) == kind:
					spec.set_cell(level, x, z, RoomCells.Kind.FLOOR)


static func _ensure_marker(spec: RoomSpec, kind: int) -> void:
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if spec.get_cell(level, x, z) == kind:
					return
	## Place on a central walkable floor cell of layer 0.
	var cx := spec.width / 2
	var cz := spec.depth / 2
	for z in spec.depth:
		for x in spec.width:
			var wx := (cx + x) % spec.width
			var wz := (cz + z) % spec.depth
			if RoomCells.is_floor_surface(spec.get_cell(0, wx, wz)):
				spec.set_cell(0, wx, wz, kind)
				return
	assert(false, "Cannot inject marker %d into %s" % [kind, spec.id])


static func _ensure_enemy_markers(spec: RoomSpec, count: int) -> void:
	var existing := 0
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if spec.get_cell(level, x, z) == RoomCells.Kind.ENEMY:
					existing += 1
	if existing >= count:
		return
	# Place on ground floor walkable cells away from edges
	var need := count - existing
	for z in range(1, spec.depth - 1):
		for x in range(1, spec.width - 1):
			if need <= 0:
				return
			if RoomCells.is_floor_surface(spec.get_cell(0, x, z)) and spec.get_cell(0, x, z) != RoomCells.Kind.ENEMY:
				if spec.get_cell(0, x, z) == RoomCells.Kind.FLOOR:
					spec.set_cell(0, x, z, RoomCells.Kind.ENEMY)
					need -= 1


static func _room_size(spec: RoomSpec) -> Vector2:
	return Vector2(float(spec.width) * spec.cell_size, float(spec.depth) * spec.cell_size)


static func _prop_pos(spec: RoomSpec, u: float, v: float, clearance: float = 0.9) -> Vector3:
	## Place inside the recessed shell (wall thickness + clearance from the outer wall).
	var size := _room_size(spec)
	var inset := RoomBaker.WALL_THICKNESS + clearance
	var min_span := inset * 2.0 + 0.2
	if size.x <= min_span or size.y <= min_span:
		return Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	return Vector3(
		lerpf(inset, size.x - inset, clampf(u, 0.0, 1.0)),
		0.0,
		lerpf(inset, size.y - inset, clampf(v, 0.0, 1.0))
	)


static func _add_torches(room: RoomModule, spec: RoomSpec) -> void:
	var spots: Array[Vector3] = [
		_prop_pos(spec, 0.0, 0.0, 0.55) + Vector3(0.0, 2.2, 0.0),
		_prop_pos(spec, 1.0, 0.0, 0.55) + Vector3(0.0, 2.2, 0.0),
		_prop_pos(spec, 0.0, 1.0, 0.55) + Vector3(0.0, 2.2, 0.0),
		_prop_pos(spec, 1.0, 1.0, 0.55) + Vector3(0.0, 2.2, 0.0),
	]
	var size := _room_size(spec)
	if size.x >= 16.0 or size.y >= 16.0:
		spots.append(_prop_pos(spec, 0.5, 0.0, 0.55) + Vector3(0.0, 2.2, 0.0))
		spots.append(_prop_pos(spec, 0.5, 1.0, 0.55) + Vector3(0.0, 2.2, 0.0))
		spots.append(_prop_pos(spec, 0.0, 0.5, 0.55) + Vector3(0.0, 2.2, 0.0))
		spots.append(_prop_pos(spec, 1.0, 0.5, 0.55) + Vector3(0.0, 2.2, 0.0))

	for spot in spots:
		var torch := _instance_mesh(KaykitPaths.TORCH)
		torch.position = Vector3(spot.x, 0.0, spot.z)
		room.add_child(torch)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.25)
		light.light_energy = 1.6
		light.omni_range = 7.5
		light.omni_attenuation = 1.4
		light.shadow_enabled = true
		light.position = spot
		room.add_child(light)


static func _add_sparse_decor(room: RoomModule, spec: RoomSpec, module_id: StringName) -> void:
	match module_id:
		&"atrium":
			_place_prop(room, KaykitPaths.BANNER, _prop_pos(spec, 0.5, 0.0, 0.35), 0.0, false)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.12, 0.12), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.88, 0.12), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.12, 0.88), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.88, 0.88), 0.0, true)
			_place_prop(room, KaykitPaths.BARREL, _prop_pos(spec, 0.18, 0.82), 0.3, true)
			_place_prop(room, KaykitPaths.CRATE, _prop_pos(spec, 0.82, 0.78), -0.4, true)
		&"combat":
			_place_prop(room, KaykitPaths.BARREL, _prop_pos(spec, 0.15, 0.85), 0.4, true)
			_place_prop(room, KaykitPaths.CRATE, _prop_pos(spec, 0.85, 0.15), -0.3, true)
		&"corridor":
			_place_prop(room, KaykitPaths.BARREL, _prop_pos(spec, 0.5, 0.35), 0.1, true)
		&"hall":
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.2, 0.5), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.8, 0.5), 0.0, true)
			_place_prop(room, KaykitPaths.BANNER, _prop_pos(spec, 0.5, 0.0, 0.35), 0.0, false)
		&"exit":
			_place_prop(room, KaykitPaths.BANNER, _prop_pos(spec, 0.5, 1.0, 0.35), PI, false)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.2, 0.8), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.8, 0.8), 0.0, true)
		&"undercroft":
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.15, 0.2), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.85, 0.2), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.15, 0.8), 0.0, true)
			_place_prop(room, KaykitPaths.COLUMN, _prop_pos(spec, 0.85, 0.8), 0.0, true)
			_place_prop(room, KaykitPaths.BARREL, _prop_pos(spec, 0.35, 0.55), 0.4, true)
			_place_prop(room, KaykitPaths.CRATE, _prop_pos(spec, 0.65, 0.4), -0.2, true)
			_place_prop(room, KaykitPaths.BANNER, _prop_pos(spec, 0.5, 0.0, 0.35), 0.0, false)
		_:
			_place_prop(room, KaykitPaths.BARREL, _prop_pos(spec, 0.5, 0.5), 0.0, true)


static func _place_exit_chest(room: RoomModule, spec: RoomSpec) -> void:
	var pos := _prop_pos(spec, 0.5, 0.72)
	for level in spec.layer_count():
		for z in spec.depth:
			for x in spec.width:
				if spec.get_cell(level, x, z) == RoomCells.Kind.EXIT:
					var c := spec.cell_center(level, x, z)
					pos = _prop_pos(spec, c.x / _room_size(spec).x, 0.72)
	_place_prop(room, KaykitPaths.CHEST, pos, 0.0, true)


static func _place_prop(room: RoomModule, path: String, pos: Vector3, yaw: float, solid: bool) -> void:
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	root.position = pos
	root.rotation.y = yaw

	var inst := _instance_mesh(path)
	root.add_child(inst)

	if solid:
		var hull := _prop_hull_for(path)
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = hull["shape"]
		shape.position = hull["offset"]
		body.add_child(shape)
		root.add_child(body)

	room.add_child(root)


static func _prop_hull_for(path: String) -> Dictionary:
	var shape: Shape3D
	var offset := Vector3.ZERO
	if path == KaykitPaths.BARREL:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35
		cyl.height = 0.85
		shape = cyl
		offset = Vector3(0.0, 0.425, 0.0)
	elif path == KaykitPaths.CRATE:
		var box := BoxShape3D.new()
		box.size = Vector3(0.7, 0.7, 0.7)
		shape = box
		offset = Vector3(0.0, 0.35, 0.0)
	elif path == KaykitPaths.COLUMN:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35
		cyl.height = 3.2
		shape = cyl
		offset = Vector3(0.0, 1.6, 0.0)
	elif path == KaykitPaths.CHEST:
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 0.7, 0.7)
		shape = box
		offset = Vector3(0.0, 0.35, 0.0)
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(0.6, 0.6, 0.6)
		shape = box
		offset = Vector3(0.0, 0.3, 0.0)
	return {"shape": shape, "offset": offset}


static func _instance_mesh(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("KayKit mesh missing: %s" % path)
		var stub := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1, 1, 1)
		stub.mesh = box
		return stub
	return packed.instantiate() as Node3D
