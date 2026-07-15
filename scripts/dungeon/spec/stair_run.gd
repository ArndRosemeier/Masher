class_name StairRun
extends RefCounted
## Contiguous stair cells on a lower layer, rising one level along a cardinal axis.

var level: int = 0
var cells: Array[Vector2i] = [] ## in run order from bottom → top
var dir: ModuleContract.Dir = ModuleContract.Dir.N


func length() -> int:
	return cells.size()


func bottom() -> Vector2i:
	return cells[0]


func top() -> Vector2i:
	return cells[cells.size() - 1]
