class_name LevelSource
extends RefCounted
## Yields a populated DungeonRoot. Fixed POC and procgen both implement this.


func build_dungeon() -> Node3D:
	push_error("LevelSource.build_dungeon() must be overridden")
	return Node3D.new()
