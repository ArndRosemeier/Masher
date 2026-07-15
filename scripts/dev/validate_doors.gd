extends SceneTree

func _initialize() -> void:
	var err := OK
	var door_scene := load("res://scenes/dungeon/door.tscn")
	if door_scene == null:
		push_error("door scene null")
		quit(1)
		return
	print("DOOR_SCENE_OK")
	var dungeon := FixedLevelSource.new().build_dungeon()
	root.add_child(dungeon)
	# Force ready
	await create_timer(0.1).timeout
	var doors := get_nodes_in_group(&"door")
	print("DOOR_COUNT ", doors.size())
	if doors.size() < 1:
		quit(1)
		return
	print("DOOR_OK")
	quit(0)
