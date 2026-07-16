extends SceneTree


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var dungeon := FixedLevelSource.new().build_dungeon()
	root.add_child(dungeon)
	await process_frame
	await process_frame

	var spawns := get_nodes_in_group(ModuleContract.GROUP_PLAYER_SPAWN)
	var chests := get_nodes_in_group(&"loot_chest")
	var doors := get_nodes_in_group(&"door")
	print("SPAWNS ", spawns.size(), " y=", (spawns[0] as Node3D).global_position.y if spawns.size() else -1)
	print("CHESTS ", chests.size())
	print("DOORS ", doors.size())
	assert(spawns.size() == 1)
	## Spawn is on atrium ground floor so the first stairs climb UP.
	assert((spawns[0] as Node3D).global_position.y < 2.0)
	assert(chests.size() >= 1)
	assert(doors.size() >= 1)
	print("ATRIUM_OK")
	quit(0)
