class_name RoomFactory
extends RefCounted
## Builds procgen-ready room modules from KayKit pieces + collision hulls.


static func build(
	module_id: StringName,
	open_dirs: Array[ModuleContract.Dir],
	opts: Dictionary = {}
) -> RoomModule:
	var room := RoomModule.new()
	room.name = String(module_id)
	room.module_id = module_id
	room.open_dirs = open_dirs.duplicate()

	_add_floor(room)
	_add_walls(room, open_dirs)
	_add_connectors(room, open_dirs)
	_add_doors(room, open_dirs)
	_add_ceiling_blocker(room)

	if bool(opts.get("player_spawn", false)):
		_add_marker(room, "PlayerSpawn", ModuleContract.GROUP_PLAYER_SPAWN, Vector3(ModuleContract.ROOM_SIZE * 0.5, 0.0, ModuleContract.ROOM_SIZE * 0.5))

	var enemy_count: int = int(opts.get("enemy_spawns", 0))
	for i in enemy_count:
		var offset := Vector3(
			ModuleContract.ROOM_SIZE * (0.35 + 0.15 * float(i % 2)),
			0.0,
			ModuleContract.ROOM_SIZE * (0.35 + 0.2 * float(i / 2))
		)
		_add_marker(room, "EnemySpawn_%d" % i, ModuleContract.GROUP_ENEMY_SPAWN, offset)

	if bool(opts.get("exit", false)):
		_add_marker(room, "Exit", ModuleContract.GROUP_EXIT, Vector3(ModuleContract.ROOM_SIZE * 0.5, 0.0, ModuleContract.ROOM_SIZE * 0.55))
		_place_prop(room, KaykitPaths.CHEST, Vector3(ModuleContract.ROOM_SIZE * 0.5, 0.0, ModuleContract.ROOM_SIZE * 0.7), 0.0, true)

	if bool(opts.get("decor", true)):
		_add_sparse_decor(room, open_dirs, module_id)

	_add_torches(room, open_dirs)
	return room


static func _add_floor(room: RoomModule) -> void:
	var large := 4.0
	for x in 2:
		for z in 2:
			var path := KaykitPaths.FLOOR if (x + z) % 2 == 0 else KaykitPaths.FLOOR_ROCKS
			var inst := _instance_mesh(path)
			inst.position = Vector3(x * large + large * 0.5, 0.0, z * large + large * 0.5)
			room.add_child(inst)

	var body := StaticBody3D.new()
	body.name = "FloorCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ModuleContract.ROOM_SIZE, 0.2, ModuleContract.ROOM_SIZE)
	shape.shape = box
	shape.position = Vector3(ModuleContract.ROOM_SIZE * 0.5, -0.1, ModuleContract.ROOM_SIZE * 0.5)
	body.add_child(shape)
	room.add_child(body)


static func _add_walls(room: RoomModule, open_dirs: Array[ModuleContract.Dir]) -> void:
	var half := ModuleContract.ROOM_SIZE * 0.5
	var wall_height := 3.5
	var wall_thickness := 0.35

	var specs: Array[Dictionary] = [
		{"dir": ModuleContract.Dir.N, "pos": Vector3(half, wall_height * 0.5, 0.0), "size": Vector3(ModuleContract.ROOM_SIZE, wall_height, wall_thickness), "yaw": 0.0},
		{"dir": ModuleContract.Dir.S, "pos": Vector3(half, wall_height * 0.5, ModuleContract.ROOM_SIZE), "size": Vector3(ModuleContract.ROOM_SIZE, wall_height, wall_thickness), "yaw": PI},
		{"dir": ModuleContract.Dir.W, "pos": Vector3(0.0, wall_height * 0.5, half), "size": Vector3(wall_thickness, wall_height, ModuleContract.ROOM_SIZE), "yaw": PI * 0.5},
		{"dir": ModuleContract.Dir.E, "pos": Vector3(ModuleContract.ROOM_SIZE, wall_height * 0.5, half), "size": Vector3(wall_thickness, wall_height, ModuleContract.ROOM_SIZE), "yaw": -PI * 0.5},
	]

	for spec in specs:
		var dir: ModuleContract.Dir = spec["dir"]
		var is_open := dir in open_dirs
		_place_wall_visuals(room, dir, is_open, float(spec["yaw"]))

		if is_open:
			_add_doorway_collision(room, dir, wall_height, wall_thickness)
		else:
			var body := StaticBody3D.new()
			body.name = "Wall_%s" % ModuleContract.dir_name(dir)
			body.collision_layer = 1
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = spec["size"]
			shape.shape = box
			body.position = spec["pos"]
			body.add_child(shape)
			room.add_child(body)


static func _add_doorway_collision(
	room: RoomModule,
	dir: ModuleContract.Dir,
	wall_height: float,
	wall_thickness: float
) -> void:
	var gap := 1.9
	var side := (ModuleContract.ROOM_SIZE - gap) * 0.5

	var positions: Array[Vector3] = []
	var sizes: Array[Vector3] = []
	match dir:
		ModuleContract.Dir.N, ModuleContract.Dir.S:
			var z := 0.0 if dir == ModuleContract.Dir.N else ModuleContract.ROOM_SIZE
			positions = [
				Vector3(side * 0.5, wall_height * 0.5, z),
				Vector3(ModuleContract.ROOM_SIZE - side * 0.5, wall_height * 0.5, z),
			]
			sizes = [
				Vector3(side, wall_height, wall_thickness),
				Vector3(side, wall_height, wall_thickness),
			]
		ModuleContract.Dir.E, ModuleContract.Dir.W:
			var x := 0.0 if dir == ModuleContract.Dir.W else ModuleContract.ROOM_SIZE
			positions = [
				Vector3(x, wall_height * 0.5, side * 0.5),
				Vector3(x, wall_height * 0.5, ModuleContract.ROOM_SIZE - side * 0.5),
			]
			sizes = [
				Vector3(wall_thickness, wall_height, side),
				Vector3(wall_thickness, wall_height, side),
			]

	for i in positions.size():
		var body := StaticBody3D.new()
		body.name = "Doorjamb_%s_%d" % [ModuleContract.dir_name(dir), i]
		body.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = sizes[i]
		shape.shape = box
		body.position = positions[i]
		body.add_child(shape)
		room.add_child(body)


static func _place_wall_visuals(room: RoomModule, dir: ModuleContract.Dir, is_open: bool, yaw: float) -> void:
	var count := 4
	var step := ModuleContract.ROOM_SIZE / float(count)
	for i in count:
		var t := (float(i) + 0.5) * step
		var pos := Vector3.ZERO
		match dir:
			ModuleContract.Dir.N:
				pos = Vector3(t, 0.0, 0.0)
			ModuleContract.Dir.S:
				pos = Vector3(t, 0.0, ModuleContract.ROOM_SIZE)
			ModuleContract.Dir.W:
				pos = Vector3(0.0, 0.0, t)
			ModuleContract.Dir.E:
				pos = Vector3(ModuleContract.ROOM_SIZE, 0.0, t)

		# Open sides use an open frame mesh (not a baked-closed doorway).
		var center_slot := i == 1 or i == 2
		var path: String
		if is_open and center_slot:
			if i == 2:
				continue
			path = KaykitPaths.WALL_DOORWAY_SIDES
		else:
			path = KaykitPaths.WALL

		var inst := _instance_mesh(path)
		inst.position = pos
		inst.rotation.y = yaw
		room.add_child(inst)


static func _add_doors(room: RoomModule, open_dirs: Array[ModuleContract.Dir]) -> void:
	## One door per shared edge: only place on E/S openings so adjacent rooms don't double up.
	var door_scene := load(KaykitPaths.DOOR_SCENE) as PackedScene
	if door_scene == null:
		push_error("Door scene missing: %s" % KaykitPaths.DOOR_SCENE)
		return

	for dir in open_dirs:
		if dir != ModuleContract.Dir.E and dir != ModuleContract.Dir.S:
			continue
		var door_node := door_scene.instantiate()
		if door_node == null:
			push_error("Failed to instantiate door")
			continue
		var door := door_node as Door
		if door == null:
			push_error("Door scene root is not a Door")
			door_node.queue_free()
			continue
		door.name = "Door_%s" % ModuleContract.dir_name(dir)
		door.position = ModuleContract.connector_local_position(dir)
		match dir:
			ModuleContract.Dir.E:
				door.rotation.y = -PI * 0.5
				door.open_angle_deg = -95.0
			ModuleContract.Dir.S:
				door.rotation.y = PI
				door.open_angle_deg = -95.0
			_:
				pass
		room.add_child(door)


static func _add_connectors(room: RoomModule, open_dirs: Array[ModuleContract.Dir]) -> void:
	for dir in open_dirs:
		var marker := Marker3D.new()
		marker.name = "Connector_%s" % ModuleContract.dir_name(dir)
		marker.position = ModuleContract.connector_local_position(dir)
		room.add_child(marker)
		room.register_connector(dir, marker)


static func _add_marker(room: RoomModule, node_name: String, group: StringName, pos: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.position = pos
	marker.add_to_group(group)
	room.add_child(marker)


static func _add_ceiling_blocker(room: RoomModule) -> void:
	var body := StaticBody3D.new()
	body.name = "Ceiling"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ModuleContract.ROOM_SIZE, 0.2, ModuleContract.ROOM_SIZE)
	shape.shape = box
	shape.position = Vector3(ModuleContract.ROOM_SIZE * 0.5, 4.2, ModuleContract.ROOM_SIZE * 0.5)
	body.add_child(shape)
	room.add_child(body)


static func _add_torches(room: RoomModule, open_dirs: Array[ModuleContract.Dir]) -> void:
	var _unused := open_dirs
	var spots: Array[Vector3] = [
		Vector3(1.2, 2.2, 1.2),
		Vector3(ModuleContract.ROOM_SIZE - 1.2, 2.2, 1.2),
		Vector3(1.2, 2.2, ModuleContract.ROOM_SIZE - 1.2),
		Vector3(ModuleContract.ROOM_SIZE - 1.2, 2.2, ModuleContract.ROOM_SIZE - 1.2),
	]
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


static func _add_sparse_decor(room: RoomModule, open_dirs: Array[ModuleContract.Dir], module_id: StringName) -> void:
	var _unused := open_dirs
	if module_id == &"start":
		_place_prop(room, KaykitPaths.BANNER, Vector3(ModuleContract.ROOM_SIZE * 0.5, 0.0, 1.0), 0.0, false)
		_place_prop(room, KaykitPaths.COLUMN, Vector3(2.0, 0.0, 2.0), 0.0, true)
		_place_prop(room, KaykitPaths.COLUMN, Vector3(ModuleContract.ROOM_SIZE - 2.0, 0.0, 2.0), 0.0, true)
	elif module_id == &"combat":
		_place_prop(room, KaykitPaths.BARREL, Vector3(2.0, 0.0, ModuleContract.ROOM_SIZE - 2.0), 0.4, true)
		_place_prop(room, KaykitPaths.CRATE, Vector3(ModuleContract.ROOM_SIZE - 2.2, 0.0, 2.2), -0.3, true)
	elif module_id == &"corridor":
		_place_prop(room, KaykitPaths.BARREL, Vector3(ModuleContract.ROOM_SIZE * 0.5, 0.0, 2.0), 0.1, true)
	elif module_id == &"exit":
		_place_prop(room, KaykitPaths.BANNER, Vector3(ModuleContract.ROOM_SIZE * 0.5, 0.0, ModuleContract.ROOM_SIZE - 1.0), PI, false)
		_place_prop(room, KaykitPaths.COLUMN, Vector3(2.5, 0.0, ModuleContract.ROOM_SIZE - 2.5), 0.0, true)
		_place_prop(room, KaykitPaths.COLUMN, Vector3(ModuleContract.ROOM_SIZE - 2.5, 0.0, ModuleContract.ROOM_SIZE - 2.5), 0.0, true)


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
		push_warning("KayKit mesh missing: %s" % path)
		var stub := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1, 1, 1)
		stub.mesh = box
		return stub
	return packed.instantiate() as Node3D
