extends SceneTree


func _initialize() -> void:
	var dungeon := FixedLevelSource.new().build_dungeon()
	root.add_child(dungeon)
	await create_timer(0.05).timeout

	var spawns := get_nodes_in_group(ModuleContract.GROUP_PLAYER_SPAWN)
	var exits := get_nodes_in_group(ModuleContract.GROUP_EXIT)
	var doors := get_nodes_in_group(&"door")
	print("SPAWNS ", spawns.size(), " y=", (spawns[0] as Node3D).global_position.y if spawns.size() else -1)
	print("EXITS ", exits.size())
	print("DOORS ", doors.size())
	assert(spawns.size() == 1)
	assert((spawns[0] as Node3D).global_position.y > 7.0)
	assert(exits.size() == 1)
	assert(doors.size() >= 1)
	print("ATRIUM_OK")
	quit(0)
