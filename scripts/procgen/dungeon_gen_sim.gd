class_name DungeonGenSim
extends RefCounted
## Reusable generate → validate loop for hybrid dungeons.
##
## Call from a SceneTree/Node that can `await` frames (rooms must enter the tree
## before validation). Headless entry: `simulate_dungeon_gen.gd`.


class TrialResult:
	var label: String = ""
	var passed: bool = false
	var errors: PackedStringArray = []
	var preset_name: String = ""
	var seed_value: int = 0
	var resolved_seed: int = 0
	var module_count: int = 0
	var floors: Array[int] = []
	## Shape diagnostics (not hard failures unless Config.strict_shape).
	var fill_ratio: float = 0.0
	var aspect_ratio: float = 1.0
	var branchy_modules: int = 0
	var bbox_w: int = 0
	var bbox_d: int = 0
	var shape_notes: PackedStringArray = []


class BatchResult:
	var trials: Array[TrialResult] = []

	func passed_count() -> int:
		var n := 0
		for t in trials:
			if t.passed:
				n += 1
		return n

	func failed_count() -> int:
		return trials.size() - passed_count()

	func all_passed() -> bool:
		return failed_count() == 0

	## Groups identical error strings → occurrence count (sorted desc).
	func error_histogram() -> Array[Dictionary]:
		var counts: Dictionary = {}
		for t in trials:
			if t.passed:
				continue
			for e in t.errors:
				counts[e] = int(counts.get(e, 0)) + 1
		var rows: Array[Dictionary] = []
		for key_variant in counts.keys():
			rows.append({"error": String(key_variant), "count": int(counts[key_variant])})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["count"]) > int(b["count"])
		)
		return rows

	## Coarser buckets (text before first '(' or '@') for trend spotting.
	func error_family_histogram() -> Array[Dictionary]:
		var counts: Dictionary = {}
		for t in trials:
			if t.passed:
				continue
			for e in t.errors:
				var family := error_family(String(e))
				counts[family] = int(counts.get(family, 0)) + 1
		var rows: Array[Dictionary] = []
		for key_variant in counts.keys():
			rows.append({"family": String(key_variant), "count": int(counts[key_variant])})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["count"]) > int(b["count"])
		)
		return rows

	static func error_family(message: String) -> String:
		var cut := message.find(" @")
		if cut > 0:
			return message.substr(0, cut)
		cut = message.find(" at ")
		if cut > 0:
			return message.substr(0, cut)
		cut = message.find(" (")
		if cut > 0:
			return message.substr(0, cut)
		cut = message.find(" cell ")
		if cut > 0:
			return message.substr(0, cut)
		return message


class Config:
	## Presets to sample. Empty → TINY, SMALL, MEDIUM.
	var presets: Array = []
	## When non-empty, every preset × every seed (deterministic grid).
	var seeds: Array[int] = []
	## Random trials (ignored when seeds is non-empty). Spread across presets.
	var random_trials: int = 32
	## RNG seed for picking trial seeds / preset order. 0 → randomize once.
	var master_seed: int = 2026
	var include_fixed_poc: bool = false
	var stop_on_first_fail: bool = false
	## Print each trial line as it completes.
	var verbose: bool = true
	## When true, tube-like / underfilled layouts fail the trial.
	var strict_shape: bool = false
	var max_aspect_ratio: float = 3.5
	var min_fill_ratio: float = 0.22


static func default_presets() -> Array:
	return [
		DungeonGenParams.Preset.TINY,
		DungeonGenParams.Preset.SMALL,
		DungeonGenParams.Preset.MEDIUM,
	]


static func all_presets() -> Array:
	return [
		DungeonGenParams.Preset.TINY,
		DungeonGenParams.Preset.SMALL,
		DungeonGenParams.Preset.MEDIUM,
		DungeonGenParams.Preset.LARGE,
		DungeonGenParams.Preset.HUGE,
	]


static func default_grid_seeds() -> Array[int]:
	return [1, 2, 7, 42, 99, 123, 555, 2026]


## Generate one dungeon under `host`, validate, free. Must be awaited.
func run_trial(
	host: Node,
	params: DungeonGenParams,
	label: String = "",
	config: Config = null
) -> TrialResult:
	assert(host != null, "DungeonGenSim: host node required")
	assert(params != null, "DungeonGenSim: params required")
	var result := TrialResult.new()
	result.seed_value = params.seed_value
	result.label = label if not label.is_empty() else "seed=%d" % params.seed_value

	var gen := HybridDungeonGenerator.new(params)
	var dungeon := gen.build_dungeon()
	host.add_child(dungeon)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	result.resolved_seed = gen.resolved_seed()
	result.module_count = _module_count(dungeon)
	var rooms := _rooms(dungeon)
	var model := DungeonMapModel.build(rooms)
	result.floors = model.floor_list.duplicate()
	_fill_shape_metrics(result, rooms, params)
	result.errors = DungeonGenValidator.validate(dungeon)
	if config != null and config.strict_shape:
		for note in result.shape_notes:
			result.errors.append("shape: %s" % note)
	result.passed = result.errors.is_empty()

	dungeon.free()
	await host.get_tree().process_frame
	return result


## Fixed POC layout through the same validator. Must be awaited.
func run_fixed_poc(host: Node) -> TrialResult:
	assert(host != null, "DungeonGenSim: host node required")
	var result := TrialResult.new()
	result.label = "FixedPOC"
	result.preset_name = "FixedPOC"
	var dungeon := FixedLevelSource.new().build_dungeon()
	host.add_child(dungeon)
	await host.get_tree().process_frame
	result.module_count = _module_count(dungeon)
	result.floors = DungeonMapModel.build(_rooms(dungeon)).floor_list.duplicate()
	result.errors = DungeonGenValidator.validate(dungeon)
	result.passed = result.errors.is_empty()
	dungeon.free()
	await host.get_tree().process_frame
	return result


## Run a full batch from config. Must be awaited.
func run_batch(host: Node, config: Config) -> BatchResult:
	assert(host != null, "DungeonGenSim: host node required")
	assert(config != null, "DungeonGenSim: config required")
	var batch := BatchResult.new()
	var presets: Array = config.presets
	if presets.is_empty():
		presets = default_presets()

	if not config.seeds.is_empty():
		for preset_variant in presets:
			var preset: DungeonGenParams.Preset = preset_variant as DungeonGenParams.Preset
			for seed_value in config.seeds:
				var params := DungeonGenParams.from_preset(preset)
				params.seed_value = seed_value
				var label := "%s seed=%d" % [DungeonGenParams.preset_name(preset), seed_value]
				var trial := await run_trial(host, params, label, config)
				trial.preset_name = DungeonGenParams.preset_name(preset)
				batch.trials.append(trial)
				if config.verbose:
					_print_trial(trial)
				if config.stop_on_first_fail and not trial.passed:
					break
			if config.stop_on_first_fail and batch.failed_count() > 0:
				break
	else:
		var rng := RandomNumberGenerator.new()
		if config.master_seed == 0:
			rng.randomize()
		else:
			rng.seed = config.master_seed
		var n := maxi(1, config.random_trials)
		for i in n:
			var preset: DungeonGenParams.Preset = presets[rng.randi() % presets.size()] as DungeonGenParams.Preset
			var seed_value := int(rng.randi())
			if seed_value == 0:
				seed_value = 1
			var params := DungeonGenParams.from_preset(preset)
			params.seed_value = seed_value
			var label := "%s trial=%d seed=%d" % [
				DungeonGenParams.preset_name(preset), i + 1, seed_value
			]
			var trial := await run_trial(host, params, label, config)
			trial.preset_name = DungeonGenParams.preset_name(preset)
			batch.trials.append(trial)
			if config.verbose:
				_print_trial(trial)
			if config.stop_on_first_fail and not trial.passed:
				break

	if config.include_fixed_poc:
		var fixed := await run_fixed_poc(host)
		batch.trials.append(fixed)
		if config.verbose:
			_print_trial(fixed)

	return batch


static func print_batch_summary(batch: BatchResult) -> void:
	print("")
	print("=== DungeonGenSim summary ===")
	print(
		"trials=%d  passed=%d  failed=%d"
		% [batch.trials.size(), batch.passed_count(), batch.failed_count()]
	)
	_print_shape_aggregates(batch)
	if batch.failed_count() == 0:
		print("ALL PASSED")
		return

	print("")
	print("--- Failures ---")
	for t in batch.trials:
		if t.passed:
			continue
		print(
			"FAIL %s  modules=%d floors=%s resolved_seed=%d (%d errors)"
			% [t.label, t.module_count, str(t.floors), t.resolved_seed, t.errors.size()]
		)
		for e in t.errors:
			print("  · ", e)

	print("")
	print("--- Error families (why) ---")
	for row in batch.error_family_histogram():
		print("  %dx  %s" % [int(row["count"]), row["family"]])

	var exact := batch.error_histogram()
	if exact.size() <= 40:
		print("")
		print("--- Exact errors ---")
		for row2 in exact:
			print("  %dx  %s" % [int(row2["count"]), row2["error"]])
	else:
		print("")
		print("--- Exact errors (top 40) ---")
		for i in mini(40, exact.size()):
			var row3: Dictionary = exact[i]
			print("  %dx  %s" % [int(row3["count"]), row3["error"]])


static func _print_shape_aggregates(batch: BatchResult) -> void:
	if batch.trials.is_empty():
		return
	var fill_sum := 0.0
	var aspect_sum := 0.0
	var tube_ish := 0
	var n := 0
	for t in batch.trials:
		if t.module_count <= 0:
			continue
		fill_sum += t.fill_ratio
		aspect_sum += t.aspect_ratio
		n += 1
		if t.aspect_ratio > 3.5 or t.fill_ratio < 0.22:
			tube_ish += 1
	if n == 0:
		return
	print(
		"shape  avg_fill=%.2f  avg_aspect=%.2f  tube_ish=%d/%d"
		% [fill_sum / float(n), aspect_sum / float(n), tube_ish, n]
	)


static func _print_trial(trial: TrialResult) -> void:
	var shape := " fill=%.2f aspect=%.2f %dx%d branchy=%d" % [
		trial.fill_ratio,
		trial.aspect_ratio,
		trial.bbox_w,
		trial.bbox_d,
		trial.branchy_modules,
	]
	if trial.passed:
		print(
			"OK  ",
			trial.label,
			" modules=",
			trial.module_count,
			" floors=",
			trial.floors,
			" resolved_seed=",
			trial.resolved_seed,
			shape
		)
	else:
		push_error("FAIL %s (%d errors)" % [trial.label, trial.errors.size()])
		for e in trial.errors:
			push_error("  · %s" % e)
		print("FAIL ", trial.label, " errors=", trial.errors.size(), shape)


static func _fill_shape_metrics(
	result: TrialResult,
	rooms: Array,
	params: DungeonGenParams
) -> void:
	var min_x := 999999
	var min_z := 999999
	var max_x := -999999
	var max_z := -999999
	var ground: Dictionary = {} ## Vector2i -> true (unique XZ coverage)
	var branchy := 0
	var mods_per_floor: Dictionary = {} ## int -> int
	for item in rooms:
		var room := item as RoomModule
		if room == null or room.spec == null:
			continue
		var fp := room.spec.footprint_cells()
		min_x = mini(min_x, room.grid_cell.x)
		min_z = mini(min_z, room.grid_cell.y)
		max_x = maxi(max_x, room.grid_cell.x + fp.x - 1)
		max_z = maxi(max_z, room.grid_cell.y + fp.y - 1)
		for z in fp.y:
			for x in fp.x:
				ground[Vector2i(room.grid_cell.x + x, room.grid_cell.y + z)] = true
		var horiz := 0
		for d in room.spec.open_dirs:
			if not ModuleContract.is_vertical(d):
				horiz += 1
		if horiz >= 3:
			branchy += 1
		for ly in room.spec.layer_count():
			var fl := room.vertical_level + ly
			mods_per_floor[fl] = int(mods_per_floor.get(fl, 0)) + 1
	var cells := ground.size()
	if cells <= 0 or max_x < min_x:
		return
	result.bbox_w = max_x - min_x + 1
	result.bbox_d = max_z - min_z + 1
	result.branchy_modules = branchy
	var short_axis := float(mini(result.bbox_w, result.bbox_d))
	var long_axis := float(maxi(result.bbox_w, result.bbox_d))
	result.aspect_ratio = long_axis / maxf(1.0, short_axis)
	var harness := maxi(1, params.grid_w() * params.grid_d())
	result.fill_ratio = float(cells) / float(harness)
	if result.aspect_ratio > 3.5:
		result.shape_notes.append(
			"aspect %.2f > 3.5 (bbox %dx%d — tube-like)"
			% [result.aspect_ratio, result.bbox_w, result.bbox_d]
		)
	if result.fill_ratio < 0.22:
		result.shape_notes.append(
			"fill %.2f < 0.22 (harness underused)" % result.fill_ratio
		)
	## Orphan upper: a floor above 0 that only exists as stair landings (1 module).
	for fl_variant in mods_per_floor.keys():
		var fl := int(fl_variant)
		if fl <= 0:
			continue
		if int(mods_per_floor[fl]) <= 1:
			result.shape_notes.append("orphan upper floor %d (only %d module)" % [
				fl, int(mods_per_floor[fl])
			])


static func _module_count(dungeon: Node3D) -> int:
	return _rooms(dungeon).size()


static func _rooms(dungeon: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [dungeon]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is RoomModule and (n as RoomModule).spec != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
