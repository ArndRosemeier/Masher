extends SceneTree
## Headless smoke test: build fixed + generated dungeons, check markers.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: PackedStringArray = []

	var fixed := FixedLevelSource.new().build_dungeon()
	root.add_child(fixed)
	await process_frame

	var player_spawns := _count_under(fixed, ModuleContract.GROUP_PLAYER_SPAWN)
	var enemy_spawns := _count_under(fixed, ModuleContract.GROUP_ENEMY_SPAWN)
	var exits := _count_under(fixed, ModuleContract.GROUP_EXIT)
	if player_spawns != 1:
		errors.append("Fixed: expected 1 player spawn, got %d" % player_spawns)
	if enemy_spawns < 1:
		errors.append("Fixed: expected enemy spawns, got %d" % enemy_spawns)
	if exits != 1:
		errors.append("Fixed: expected 1 exit, got %d" % exits)

	fixed.free()

	var gen := RoomGraphGenerator.new(12345, 6, 1).build_dungeon()
	root.add_child(gen)
	await process_frame
	if _count_under(gen, ModuleContract.GROUP_PLAYER_SPAWN) != 1:
		errors.append("Generated: missing player spawn")
	if _count_under(gen, ModuleContract.GROUP_EXIT) != 1:
		errors.append("Generated: missing exit")
	gen.free()

	if errors.is_empty():
		print("VALIDATE_OK")
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("VALIDATE_FAIL")
		quit(1)


func _count_under(ancestor: Node, group: StringName) -> int:
	var n := 0
	for node in get_nodes_in_group(group):
		if ancestor.is_ancestor_of(node):
			n += 1
	return n
