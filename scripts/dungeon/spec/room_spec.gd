class_name RoomSpec
extends RefCounted
## Parsed layered ASCII room. Source of truth for bake + validation.

var id: StringName = &"room"
var cell_size: float = 2.0
var layer_height: float = 4.0
var open_dirs: Array[ModuleContract.Dir] = []
## Optional precise faces from procgen: Vector2i(dir, local_level).
## Empty means "every layer that has an ASCII gap for each open_dir" (hand-authored rooms).
var open_faces: Array = []
## Optional procgen door cells: Vector2i(dir, local_level) -> Array[Vector2i].
## When set, seal/bake/map keep all of them (wide modules can face several peers).
var doorway_cells: Dictionary = {}
## layers[level][z][x] -> RoomCells.Kind  (row z is north→south as written)
var layers: Array = []
var width: int = 0
var depth: int = 0


func layer_count() -> int:
	return layers.size()


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < width and z < depth


func get_cell(level: int, x: int, z: int) -> int:
	if level < 0 or level >= layers.size():
		return RoomCells.Kind.EMPTY
	if not in_bounds(x, z):
		return RoomCells.Kind.EMPTY
	return layers[level][z][x]


func set_cell(level: int, x: int, z: int, kind: int) -> void:
	layers[level][z][x] = kind


func world_size() -> Vector2:
	return Vector2(float(width) * cell_size, float(depth) * cell_size)


func cell_center(level: int, x: int, z: int) -> Vector3:
	return Vector3(
		(float(x) + 0.5) * cell_size,
		float(level) * layer_height,
		(float(z) + 0.5) * cell_size
	)


func footprint_cells() -> Vector2i:
	## How many ModuleContract ground cells this room occupies.
	var wx := world_size().x
	var wz := world_size().y
	return Vector2i(
		maxi(1, int(round(wx / ModuleContract.ROOM_SIZE))),
		maxi(1, int(round(wz / ModuleContract.ROOM_SIZE)))
	)
