class_name MapExploration
extends RefCounted
## Per-floor fog of war: cells the player has revealed on each world floor.


## floor_index -> Dictionary[Vector2i, bool]
var _explored: Dictionary = {}


func clear() -> void:
	_explored.clear()


func is_explored(floor_index: int, cell: Vector2i) -> bool:
	var floor_map = _explored.get(floor_index)
	if floor_map == null:
		return false
	return (floor_map as Dictionary).has(cell)


func reveal_around(
	floor_index: int,
	center: Vector2i,
	radius: int,
	layer: DungeonMapModel.FloorLayer
) -> bool:
	## Marks every map cell within Chebyshev radius. Returns true if anything new was revealed.
	assert(layer != null, "MapExploration.reveal_around: null layer")
	assert(radius >= 0, "MapExploration.reveal_around: negative radius")
	var floor_map: Dictionary = _explored.get(floor_index, {}) as Dictionary
	if not _explored.has(floor_index):
		_explored[floor_index] = floor_map
	var changed := false
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dz)) > radius:
				continue
			var key := Vector2i(center.x + dx, center.y + dz)
			if not layer.has_cell(key):
				continue
			if floor_map.has(key):
				continue
			floor_map[key] = true
			changed = true
	return changed


func explored_bounds(floor_index: int) -> Rect2i:
	## Inclusive cell bounds of explored cells on this floor, or empty Rect2i if none.
	var floor_map = _explored.get(floor_index)
	if floor_map == null or (floor_map as Dictionary).is_empty():
		return Rect2i()
	var first := true
	var min_x := 0
	var max_x := 0
	var min_z := 0
	var max_z := 0
	for key_variant in (floor_map as Dictionary).keys():
		var key: Vector2i = key_variant
		if first:
			min_x = key.x
			max_x = key.x
			min_z = key.y
			max_z = key.y
			first = false
		else:
			min_x = mini(min_x, key.x)
			max_x = maxi(max_x, key.x)
			min_z = mini(min_z, key.y)
			max_z = maxi(max_z, key.y)
	return Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)


func explored_count(floor_index: int) -> int:
	var floor_map = _explored.get(floor_index)
	if floor_map == null:
		return 0
	return (floor_map as Dictionary).size()
