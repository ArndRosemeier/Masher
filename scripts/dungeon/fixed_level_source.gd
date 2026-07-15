class_name FixedLevelSource
extends LevelSource
## Hand-assembled POC layout using the same modules procgen will place.
##
## Layout:
##   undercroft 20x10 at vertical level -1 under the atrium (U/D shaft)
##   atrium 3x3 at (0,0) level 0 — multi-layer start with down-stairs
##   then east chain on level 0:
##   (3,1) corridor --E-- (4,1) combat --E-- (5,1) corridor --E-- (6,1) exit


func build_dungeon() -> Node3D:
	var root := Node3D.new()
	root.name = "DungeonRoot"

	# Vertical level connector: undercroft directly under atrium, shafts aligned at (2,5..8).
	_place(
		root,
		Vector2i(0, 0),
		-1,
		&"undercroft",
		[ModuleContract.Dir.U],
		{"decor": true}
	)
	_place(
		root,
		Vector2i(0, 0),
		0,
		&"atrium",
		[ModuleContract.Dir.E, ModuleContract.Dir.D],
		{"decor": true}
	)
	_place(root, Vector2i(3, 1), 0, &"corridor", [ModuleContract.Dir.W, ModuleContract.Dir.E], {"decor": true})
	_place(root, Vector2i(4, 1), 0, &"combat", [ModuleContract.Dir.W, ModuleContract.Dir.E], {"enemy_spawns": 2, "decor": true})
	_place(root, Vector2i(5, 1), 0, &"corridor", [ModuleContract.Dir.W, ModuleContract.Dir.E], {"decor": true})
	_place(root, Vector2i(6, 1), 0, &"exit", [ModuleContract.Dir.W], {"exit": true, "decor": true})

	return root


func _place(
	root: Node3D,
	cell: Vector2i,
	level: int,
	id: StringName,
	open_dirs: Array,
	opts: Dictionary
) -> void:
	var typed_open: Array[ModuleContract.Dir] = []
	for d in open_dirs:
		typed_open.append(d as ModuleContract.Dir)
	var room: RoomModule = RoomFactory.build(id, typed_open, opts)
	room.grid_cell = cell
	room.vertical_level = level
	room.position = ModuleContract.grid_to_world(cell, level)
	root.add_child(room)
