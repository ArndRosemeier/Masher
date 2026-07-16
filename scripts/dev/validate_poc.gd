extends SceneTree
## Headless smoke test: build fixed + generated dungeons, check markers.

const Validator := preload("res://scripts/procgen/dungeon_gen_validator.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: PackedStringArray = []

	var fixed := FixedLevelSource.new().build_dungeon()
	root.add_child(fixed)
	await process_frame

	var player_spawns := _count_under(fixed, ModuleContract.GROUP_PLAYER_SPAWN)
	var enemy_spawns := _count_under(fixed, ModuleContract.GROUP_ENEMY_SPAWN)
	var chests := _count_under(fixed, &"loot_chest")
	if player_spawns != 1:
		errors.append("Fixed: expected 1 player spawn, got %d" % player_spawns)
	if enemy_spawns < 1:
		errors.append("Fixed: expected enemy spawns, got %d" % enemy_spawns)
	if chests < 1:
		errors.append("Fixed: expected loot chests, got %d" % chests)

	fixed.free()

	## Prefer the dedicated dungeon-gen validator for hybrid runs.
	var params := DungeonGenParams.from_preset(DungeonGenParams.Preset.SMALL)
	params.seed_value = 12345
	var gen := HybridDungeonGenerator.new(params).build_dungeon()
	root.add_child(gen)
	await process_frame
	var gen_errors: PackedStringArray = Validator.validate(gen)
	for e in gen_errors:
		errors.append("Generated: %s" % e)
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
