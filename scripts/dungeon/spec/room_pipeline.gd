class_name RoomPipeline
extends RefCounted
## Parse → validate → bake for ASCII room specs.


static func build_from_file(
	path: String,
	require_player: bool = false,
	require_exit: bool = false,
	open_override: Array[ModuleContract.Dir] = []
) -> RoomModule:
	var spec := RoomSpecParser.parse_file(path)
	if not open_override.is_empty():
		spec.open_dirs = open_override.duplicate()
	RoomValidators.validate_or_assert(spec, require_player, require_exit)
	return RoomBaker.bake(spec)


static func build_from_text(
	text: String,
	source_name: String,
	require_player: bool = false,
	require_exit: bool = false
) -> RoomModule:
	var spec := RoomSpecParser.parse_text(text, source_name)
	RoomValidators.validate_or_assert(spec, require_player, require_exit)
	return RoomBaker.bake(spec)
