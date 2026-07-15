class_name RoomModule
extends Node3D
## Runtime room module: geometry + connector/spawn markers (procgen-ready).

@export var module_id: StringName = &"room"
@export var open_dirs: Array[ModuleContract.Dir] = []

var _connectors: Dictionary = {} ## Dir -> Marker3D


func _ready() -> void:
	add_to_group(ModuleContract.GROUP_MODULE)


func register_connector(dir: ModuleContract.Dir, marker: Marker3D) -> void:
	_connectors[dir] = marker
	marker.add_to_group(ModuleContract.GROUP_CONNECTOR)
	marker.set_meta("dir", dir)


func get_connector(dir: ModuleContract.Dir) -> Marker3D:
	return _connectors.get(dir) as Marker3D


func has_opening(dir: ModuleContract.Dir) -> bool:
	return dir in open_dirs
