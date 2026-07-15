extends SceneTree
## Headless: parse/validate/bake every rooms/*.room.txt and probe walkable cells.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dir := DirAccess.open("res://rooms")
	if dir == null:
		push_error("Missing res://rooms")
		quit(1)
		return

	var files: PackedStringArray = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".room.txt"):
			files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	assert(files.size() > 0, "No room files found")

	var failed := 0
	for file in files:
		var path := "res://rooms/%s" % file
		var require_player := file.begins_with("atrium") or file.begins_with("stair")
		var require_exit := file.begins_with("exit")
		# Full dungeon rooms with P or E set flags from content after parse
		var spec := RoomSpecParser.parse_file(path)
		var has_p := false
		var has_e := false
		for level in spec.layer_count():
			for z in spec.depth:
				for x in spec.width:
					var k: int = spec.get_cell(level, x, z)
					if k == RoomCells.Kind.PLAYER:
						has_p = true
					elif k == RoomCells.Kind.EXIT:
						has_e = true
		require_player = has_p
		require_exit = has_e

		var errors := RoomValidators.validate(spec, require_player, require_exit)
		if not errors.is_empty():
			failed += 1
			for e in errors:
				push_error("[%s] %s" % [file, e])
			continue

		var room := RoomBaker.bake(spec)
		root.add_child(room)
		await physics_frame
		await physics_frame
		var probe_errors := RoomBaker.probe_walkable(room, spec)
		if not probe_errors.is_empty():
			failed += 1
			for e in probe_errors:
				push_error("[%s] %s" % [file, e])
		else:
			print("OK ", file)
		room.free()

	if failed > 0:
		print("ROOMS_FAIL ", failed)
		quit(1)
	else:
		print("ROOMS_OK ", files.size())
		quit(0)
