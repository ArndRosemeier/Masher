extends SceneTree
## Headless CI suite: fixed seed grid + Fixed POC + seal regression.
## Broader random simulation: `simulate_dungeon_gen.gd` / `DungeonGenSim`.
##
## Usage:
##   godot --headless --path . -s res://scripts/dev/validate_dungeon_gen.gd

const Validator := preload("res://scripts/procgen/dungeon_gen_validator.gd")
const Sim := preload("res://scripts/procgen/dungeon_gen_sim.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var checked := 0

	var config := Sim.Config.new()
	config.presets = Sim.default_presets()
	config.seeds = Sim.default_grid_seeds()
	config.include_fixed_poc = true
	config.verbose = true
	var sim := Sim.new()
	var batch = await sim.run_batch(root, config)
	checked += batch.trials.size()
	failed += batch.failed_count()
	if batch.failed_count() > 0:
		Sim.print_batch_summary(batch)

	## Regression: unsealed walkable edges (upper-floor abyss) must fail loudly.
	checked += 1
	if _regression_unsealed_edge_is_caught():
		print("OK  RegressionUnsealedEdge")
	else:
		failed += 1
		print("FAIL RegressionUnsealedEdge")

	if failed > 0:
		print("DUNGEON_GEN_FAIL ", failed, "/", checked)
		quit(1)
	else:
		print("DUNGEON_GEN_OK ", checked)
		quit(0)


func _regression_unsealed_edge_is_caught() -> bool:
	## Skip ASCII seal, bake with DoorSeals, then strip L1 seals — validator must fail.
	var opens: Array[ModuleContract.Dir] = [ModuleContract.Dir.W, ModuleContract.Dir.E]
	var open_faces: Array = [Vector2i(ModuleContract.Dir.W as int, 0), Vector2i(ModuleContract.Dir.E as int, 0)]
	var room := RoomFactory.build(
		&"stair_test",
		opens,
		{
			"force_open_dirs": true,
			"open_faces": open_faces,
			"decor": false,
			"clear_player": true,
			"skip_edge_seal": true,
		}
	)
	var reg_root := Node3D.new()
	reg_root.name = "RegressionRoot"
	root.add_child(reg_root)
	reg_root.add_child(room)
	var to_strip: Array[Node] = []
	for child in room.get_children():
		var n := String(child.name)
		if n.begins_with("DoorSeal_E_L1") or n.begins_with("DoorSeal_W_L1"):
			to_strip.append(child)
	for node in to_strip:
		node.free()
	var removed := to_strip.size()
	if removed == 0:
		push_error("RegressionUnsealedEdge: expected L1 DoorSeal nodes to strip")
		reg_root.free()
		return false
	var errors: PackedStringArray = Validator.validate(reg_root)
	reg_root.free()
	var abyss := 0
	for e in errors:
		if e.contains("DoorSeal") or e.contains("abyss"):
			abyss += 1
	if abyss == 0:
		push_error("RegressionUnsealedEdge: validator missed unsealed L1 edges; errors=%s" % str(errors))
		return false
	return true
