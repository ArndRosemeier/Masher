extends SceneTree
## Headless regression: a player-sized capsule must be able to walk every stair
## ramp (up and down) without jumping. Fails loudly when a climb stalls.


class WalkCase:
	var label: String = ""
	var start: Vector3 = Vector3.ZERO
	var dir: Vector3 = Vector3.ZERO
	var frames: int = 300
	var expect_min_y: float = 0.0
	var expect_max_y: float = 0.0
	var with_undercroft: bool = false

	func _init(
		p_label: String,
		p_start: Vector3,
		p_dir: Vector3,
		p_frames: int,
		p_expect_min_y: float,
		p_expect_max_y: float,
		p_with_undercroft: bool = false
	) -> void:
		label = p_label
		start = p_start
		dir = p_dir
		frames = p_frames
		expect_min_y = p_expect_min_y
		expect_max_y = p_expect_max_y
		with_undercroft = p_with_undercroft


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var cases: Array[WalkCase] = [
		WalkCase.new(
			"stair_test L0 up", Vector3(2.5, 0.9, 3.0), Vector3(1.0, 0.0, 0.0), 240, 0.0, 4.0
		),
		WalkCase.new(
			"atrium L0 up east stair", Vector3(13.0, 0.9, 7.0), Vector3(0.0, 0.0, 1.0), 360, 0.0, 4.0
		),
		WalkCase.new(
			"atrium L1 up west stair", Vector3(5.0, 4.9, 17.0), Vector3(0.0, 0.0, -1.0), 360, 4.0, 8.0
		),
		WalkCase.new(
			"atrium D down to undercroft",
			Vector3(5.0, 0.9, 7.0),
			Vector3(0.0, 0.0, 1.0),
			360,
			-4.0,
			0.0,
			true
		),
		WalkCase.new(
			"atrium D up from undercroft",
			Vector3(5.0, -3.1, 16.0),
			Vector3(0.0, 0.0, -1.0),
			420,
			-4.0,
			0.0,
			true
		),
	]

	var failed := 0
	for c in cases:
		if not await _walk_case(c):
			failed += 1

	if failed > 0:
		print("STAIR_WALK_FAIL ", failed)
		quit(1)
	else:
		print("STAIR_WALK_OK ", cases.size())
		quit(0)


func _walk_case(c: WalkCase) -> bool:
	var room_id: StringName = &"stair_test" if c.label.begins_with("stair_test") else &"atrium"
	var opens: Array[ModuleContract.Dir] = []
	if room_id == &"stair_test":
		opens.assign([ModuleContract.Dir.W, ModuleContract.Dir.E])
	else:
		opens.assign([ModuleContract.Dir.E, ModuleContract.Dir.D])
	var room := RoomFactory.build(room_id, opens, {"decor": false, "clear_player": true})
	root.add_child(room)

	var under: RoomModule = null
	if c.with_undercroft:
		var under_opens: Array[ModuleContract.Dir] = [ModuleContract.Dir.U]
		under = RoomFactory.build(&"undercroft", under_opens, {"decor": false})
		under.position = ModuleContract.grid_to_world(Vector2i.ZERO, -1)
		root.add_child(under)

	## Same capsule + floor settings as scenes/player/player.tscn.
	## Start Y is capsule-center height (~floor + 0.9), matching prior cases.
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	shape.shape = capsule
	body.add_child(shape)
	body.collision_mask = 1
	body.floor_stop_on_slope = true
	body.floor_max_angle = 1.2
	body.floor_snap_length = 0.3
	root.add_child(body)
	body.global_position = c.start

	await physics_frame
	await physics_frame

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var max_y := -INF
	var min_y := INF
	for i in c.frames:
		if not body.is_on_floor():
			body.velocity.y -= gravity * (1.0 / 60.0)
		elif body.velocity.y < 0.0:
			body.velocity.y = 0.0
		body.velocity.x = c.dir.x * 5.0
		body.velocity.z = c.dir.z * 5.0
		body.move_and_slide()
		max_y = maxf(max_y, body.global_position.y)
		min_y = minf(min_y, body.global_position.y)
		await physics_frame

	## Capsule center rests ~0.8 above the floor; allow slack for landing bounce.
	## When the case starts already on a tread, min_y may be > expect_min_y.
	var reached_top := max_y >= c.expect_max_y + 0.55
	var reached_bottom := min_y <= c.expect_min_y + 1.5
	var climbed := max_y - min_y >= maxf(1.5, (c.expect_max_y - c.expect_min_y) * 0.5)
	## Climb-up cases must also clear the top seam (not stall on the last step).
	var cleared_seam := true
	if c.dir.length() > 0.01 and c.expect_max_y > c.expect_min_y:
		var along := c.dir.normalized()
		var progress := (body.global_position - c.start).dot(along)
		cleared_seam = progress > 1.0 or max_y >= c.expect_max_y + 0.7
	var ok := reached_top and (reached_bottom or climbed) and cleared_seam
	print(
		"%s %s | final=%s max_y=%.2f min_y=%.2f (expected floor span %.1f..%.1f)"
		% [
			"OK  " if ok else "FAIL",
			c.label,
			str(body.global_position),
			max_y,
			min_y,
			c.expect_min_y,
			c.expect_max_y,
		]
	)

	body.free()
	room.free()
	if under != null:
		under.free()
	await physics_frame
	return ok
