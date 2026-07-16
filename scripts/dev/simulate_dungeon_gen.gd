extends SceneTree
## Headless dungeon generation simulation: generate → DungeonGenValidator → report.
##
## Usage:
##   godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd
##   godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd -- --grid
##   godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd -- --trials=64 --presets=all
##   godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd -- --trials=20 --master-seed=99 --stop-on-fail
##
## User args (after `--`):
##   --grid                 Fixed seed grid (CI-style), ignores --trials
##   --trials=N             Random trials (default 32)
##   --master-seed=N        RNG seed for random trials (0 = randomize)
##   --presets=tiny,small   Or `all` / `default`
##   --seeds=1,2,7          With --grid (default: built-in CI seeds)
##   --fixed-poc            Also validate FixedLevelSource
##   --stop-on-fail         Abort batch after first failure
##   --strict-shape         Fail tube-like / underfilled layouts
##   --quiet                Only print summary

const Sim := preload("res://scripts/procgen/dungeon_gen_sim.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var config := Sim.Config.new()
	config.verbose = not bool(args.get("quiet", false))
	config.stop_on_first_fail = bool(args.get("stop_on_fail", false))
	config.include_fixed_poc = bool(args.get("fixed_poc", false))
	config.strict_shape = bool(args.get("strict_shape", false))
	config.master_seed = int(args.get("master_seed", 2026))
	config.presets = args["presets"] as Array

	if bool(args.get("grid", false)):
		config.seeds = args["seeds"] as Array[int]
		config.random_trials = 0
		print(
			"DungeonGenSim GRID presets=",
			_preset_names(config.presets),
			" seeds=",
			config.seeds
		)
	else:
		config.seeds = []
		config.random_trials = int(args.get("trials", 32))
		print(
			"DungeonGenSim RANDOM trials=",
			config.random_trials,
			" master_seed=",
			config.master_seed,
			" presets=",
			_preset_names(config.presets)
		)

	var sim := Sim.new()
	var batch = await sim.run_batch(root, config)
	Sim.print_batch_summary(batch)

	if batch.all_passed():
		print("DUNGEON_SIM_OK ", batch.trials.size())
		quit(0)
	else:
		print("DUNGEON_SIM_FAIL ", batch.failed_count(), "/", batch.trials.size())
		quit(1)


func _parse_args(user_args: PackedStringArray) -> Dictionary:
	var out := {
		"grid": false,
		"trials": 32,
		"master_seed": 2026,
		"quiet": false,
		"stop_on_fail": false,
		"fixed_poc": false,
		"strict_shape": false,
		"presets": Sim.default_presets(),
		"seeds": Sim.default_grid_seeds(),
	}
	for raw in user_args:
		var arg := String(raw)
		if arg == "--grid":
			out["grid"] = true
		elif arg == "--quiet":
			out["quiet"] = true
		elif arg == "--stop-on-fail":
			out["stop_on_fail"] = true
		elif arg == "--fixed-poc":
			out["fixed_poc"] = true
		elif arg == "--strict-shape":
			out["strict_shape"] = true
		elif arg.begins_with("--trials="):
			out["trials"] = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--master-seed="):
			out["master_seed"] = int(arg.get_slice("=", 1))
		elif arg.begins_with("--presets="):
			out["presets"] = _parse_presets(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			out["seeds"] = _parse_int_list(arg.get_slice("=", 1))
		else:
			push_error("DungeonGenSim: unknown arg '%s'" % arg)
			assert(false, "Unknown simulate_dungeon_gen arg: %s" % arg)
	return out


func _parse_presets(token: String) -> Array:
	var t := token.strip_edges().to_lower()
	if t.is_empty() or t == "default":
		return Sim.default_presets()
	if t == "all":
		return Sim.all_presets()
	var out: Array = []
	for part in t.split(",", false):
		match String(part).strip_edges().to_lower():
			"tiny":
				out.append(DungeonGenParams.Preset.TINY)
			"small":
				out.append(DungeonGenParams.Preset.SMALL)
			"medium":
				out.append(DungeonGenParams.Preset.MEDIUM)
			"large":
				out.append(DungeonGenParams.Preset.LARGE)
			"huge":
				out.append(DungeonGenParams.Preset.HUGE)
			_:
				assert(false, "Unknown preset '%s'" % part)
	assert(not out.is_empty(), "No presets parsed from '%s'" % token)
	return out


func _parse_int_list(token: String) -> Array[int]:
	var out: Array[int] = []
	for part in token.split(",", false):
		out.append(int(String(part).strip_edges()))
	assert(not out.is_empty(), "Empty seed list")
	return out


func _preset_names(presets: Array) -> PackedStringArray:
	var names: PackedStringArray = []
	for p in presets:
		names.append(DungeonGenParams.preset_name(p as DungeonGenParams.Preset))
	return names
