extends SceneTree
## Headless: generate hybrid dungeons across presets/seeds and run DungeonGenValidator.
##
## Usage:
##   godot --headless --path . -s res://scripts/dev/validate_dungeon_gen.gd

const Validator := preload("res://scripts/procgen/dungeon_gen_validator.gd")
const MapModel := preload("res://scripts/ui/dungeon_map_model.gd")

const SEEDS: Array[int] = [1, 2, 7, 42, 99, 123, 555, 2026]
const PRESETS: Array = [
	DungeonGenParams.Preset.TINY,
	DungeonGenParams.Preset.SMALL,
	DungeonGenParams.Preset.MEDIUM,
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var checked := 0

	for preset_variant in PRESETS:
		var preset: DungeonGenParams.Preset = preset_variant as DungeonGenParams.Preset
		for seed_value in SEEDS:
			checked += 1
			var label := "%s seed=%d" % [DungeonGenParams.preset_name(preset), seed_value]
			var params := DungeonGenParams.from_preset(preset)
			params.seed_value = seed_value
			var gen := HybridDungeonGenerator.new(params)
			var dungeon := gen.build_dungeon()
			root.add_child(dungeon)
			await process_frame
			await process_frame

			var errors: PackedStringArray = Validator.validate(dungeon)
			if errors.is_empty():
				print(
					"OK  ",
					label,
					" modules=",
					_module_count(dungeon),
					" floors=",
					MapModel.build(_rooms(dungeon)).floor_list,
					" resolved_seed=",
					gen.resolved_seed()
				)
			else:
				failed += 1
				push_error("FAIL %s (%d errors)" % [label, errors.size()])
				for e in errors:
					push_error("  · %s" % e)
				print("FAIL ", label, " errors=", errors.size())

			dungeon.free()
			await process_frame

	## Also validate the fixed POC once — same structural rules.
	checked += 1
	var fixed := FixedLevelSource.new().build_dungeon()
	root.add_child(fixed)
	await process_frame
	var fixed_errors: PackedStringArray = Validator.validate(fixed)
	if fixed_errors.is_empty():
		print("OK  FixedPOC")
	else:
		failed += 1
		for e in fixed_errors:
			push_error("  · %s" % e)
		print("FAIL FixedPOC errors=", fixed_errors.size())
	fixed.free()

	if failed > 0:
		print("DUNGEON_GEN_FAIL ", failed, "/", checked)
		quit(1)
	else:
		print("DUNGEON_GEN_OK ", checked)
		quit(0)


func _module_count(dungeon: Node3D) -> int:
	var n := 0
	for room in _rooms(dungeon):
		n += 1
	return n


func _rooms(dungeon: Node3D) -> Array:
	var out: Array = []
	var stack: Array = [dungeon]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is RoomModule and (n as RoomModule).spec != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
