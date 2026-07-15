extends Node3D
## Scene wrapper around FixedLevelSource for editor preview / plan layout.


func _ready() -> void:
	var dungeon := FixedLevelSource.new().build_dungeon()
	add_child(dungeon)
