class_name StairRun
extends RefCounted
## Contiguous stair cells on a layer. Ascending rises into the next layer;
## descending drops one layer_height below (level connector into a room beneath).

var level: int = 0
var cells: Array[Vector2i] = [] ## in run order from bottom → top
var dir: ModuleContract.Dir = ModuleContract.Dir.N
var ascending: bool = true


func length() -> int:
	return cells.size()


func bottom() -> Vector2i:
	return cells[0]


func top() -> Vector2i:
	return cells[cells.size() - 1]
