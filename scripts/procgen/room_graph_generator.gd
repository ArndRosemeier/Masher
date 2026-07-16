class_name RoomGraphGenerator
extends LevelSource
## Deprecated flat generator. Delegates to HybridDungeonGenerator (Small preset).


@export var seed_value: int = 0
@export var path_length: int = 6
@export var side_rooms: int = 1


func _init(p_seed: int = 0, _p_path_length: int = 6, _p_side_rooms: int = 1) -> void:
	seed_value = p_seed


func build_dungeon() -> Node3D:
	push_warning("RoomGraphGenerator is deprecated; use HybridDungeonGenerator")
	var params := DungeonGenParams.from_preset(DungeonGenParams.Preset.SMALL)
	params.seed_value = seed_value
	return HybridDungeonGenerator.new(params).build_dungeon()
