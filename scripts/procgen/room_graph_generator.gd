class_name RoomGraphGenerator
extends LevelSource
## POST-POC room-graph generator: places the same RoomFactory modules on a seedable grid.
##
## Algorithm: grow a linear-ish path with optional side combat rooms, always
## start → … → exit. Uses ModuleContract connectors/openings.

@export var seed_value: int = 0
@export var path_length: int = 6 ## number of cells including start/exit
@export var side_rooms: int = 1


func _init(p_seed: int = 0, p_path_length: int = 6, p_side_rooms: int = 1) -> void:
	seed_value = p_seed
	path_length = maxi(4, p_path_length)
	side_rooms = maxi(0, p_side_rooms)


func build_dungeon() -> Node3D:
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var root := Node3D.new()
	root.name = "DungeonRoot"

	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var occupied: Dictionary = {Vector2i.ZERO: true}
	var dirs: Array[ModuleContract.Dir] = [
		ModuleContract.Dir.N,
		ModuleContract.Dir.E,
		ModuleContract.Dir.S,
		ModuleContract.Dir.W,
	]

	# Main path
	while cells.size() < path_length:
		var current := cells[cells.size() - 1]
		var order := dirs.duplicate()
		_shuffle(order, rng)
		var placed := false
		for dir in order:
			var next := current + _dir_to_cell(dir)
			if occupied.has(next):
				continue
			cells.append(next)
			occupied[next] = true
			placed = true
			break
		if not placed:
			# Stuck: branch from an earlier cell
			var progressed := false
			for i in range(cells.size() - 1, -1, -1):
				current = cells[i]
				order = dirs.duplicate()
				_shuffle(order, rng)
				for dir in order:
					var next2 := current + _dir_to_cell(dir)
					if occupied.has(next2):
						continue
					cells.append(next2)
					occupied[next2] = true
					progressed = true
					break
				if progressed:
					break
			if not progressed:
				break

	# Side combat rooms off the middle of the path
	var side_cells: Array[Vector2i] = []
	var attempts := 0
	while side_cells.size() < side_rooms and attempts < 40:
		attempts += 1
		var idx := rng.randi_range(1, maxi(1, cells.size() - 2))
		var base: Vector2i = cells[idx]
		var dir: ModuleContract.Dir = dirs[rng.randi_range(0, dirs.size() - 1)]
		var side := base + _dir_to_cell(dir)
		if occupied.has(side):
			continue
		side_cells.append(side)
		occupied[side] = true

	var openings := _compute_openings(cells, side_cells)

	# Start
	var start_cell := cells[0]
	var start_room := RoomFactory.build(
		&"start",
		openings[start_cell],
		{"player_spawn": true, "decor": true}
	)
	start_room.position = ModuleContract.grid_to_world(start_cell)
	root.add_child(start_room)

	# Middle path
	for i in range(1, cells.size() - 1):
		var cell := cells[i]
		var is_combat := i == int(cells.size() / 2)
		var id: StringName = &"combat" if is_combat else &"corridor"
		var opts := {"decor": true}
		if is_combat:
			opts["enemy_spawns"] = 2
		var room := RoomFactory.build(id, openings[cell], opts)
		room.position = ModuleContract.grid_to_world(cell)
		root.add_child(room)

	# Exit
	var exit_cell := cells[cells.size() - 1]
	var exit_room := RoomFactory.build(
		&"exit",
		openings[exit_cell],
		{"exit": true, "decor": true}
	)
	exit_room.position = ModuleContract.grid_to_world(exit_cell)
	root.add_child(exit_room)

	# Side rooms
	for cell in side_cells:
		var room := RoomFactory.build(
			&"combat",
			openings[cell],
			{"enemy_spawns": 1, "decor": true}
		)
		room.position = ModuleContract.grid_to_world(cell)
		root.add_child(room)

	root.set_meta("seed", rng.seed)
	return root


func _compute_openings(path: Array[Vector2i], sides: Array[Vector2i]) -> Dictionary:
	var all_cells: Array[Vector2i] = path.duplicate()
	all_cells.append_array(sides)
	var set: Dictionary = {}
	for c in all_cells:
		set[c] = true

	var result: Dictionary = {}
	for cell in all_cells:
		var opens: Array[ModuleContract.Dir] = []
		for dir in [ModuleContract.Dir.N, ModuleContract.Dir.E, ModuleContract.Dir.S, ModuleContract.Dir.W]:
			var neighbor := cell + _dir_to_cell(dir)
			if set.has(neighbor):
				opens.append(dir)
		result[cell] = opens
	return result


func _dir_to_cell(dir: ModuleContract.Dir) -> Vector2i:
	match dir:
		ModuleContract.Dir.N:
			return Vector2i(0, -1)
		ModuleContract.Dir.E:
			return Vector2i(1, 0)
		ModuleContract.Dir.S:
			return Vector2i(0, 1)
		ModuleContract.Dir.W:
			return Vector2i(-1, 0)
	return Vector2i.ZERO


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
