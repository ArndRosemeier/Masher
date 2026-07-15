class_name FixedLevelSource
extends LevelSource
## Hand-assembled POC layout using the same modules procgen will place.
##
## Layout (cells on ModuleContract grid):
##   (0,0) start  --E-- (1,0) corridor --E-- (2,0) combat --E-- (3,0) corridor --E-- (4,0) exit


func build_dungeon() -> Node3D:
	var root := Node3D.new()
	root.name = "DungeonRoot"

	_place(root, Vector2i(0, 0), &"start", [ModuleContract.Dir.E], {"player_spawn": true, "decor": true})
	_place(root, Vector2i(1, 0), &"corridor", [ModuleContract.Dir.W, ModuleContract.Dir.E], {"decor": true})
	_place(root, Vector2i(2, 0), &"combat", [ModuleContract.Dir.W, ModuleContract.Dir.E], {"enemy_spawns": 2, "decor": true})
	_place(root, Vector2i(3, 0), &"corridor", [ModuleContract.Dir.W, ModuleContract.Dir.E], {"decor": true})
	_place(root, Vector2i(4, 0), &"exit", [ModuleContract.Dir.W], {"exit": true, "decor": true})

	return root


func _place(
	root: Node3D,
	cell: Vector2i,
	id: StringName,
	open_dirs: Array,
	opts: Dictionary
) -> void:
	var typed_open: Array[ModuleContract.Dir] = []
	for d in open_dirs:
		typed_open.append(d as ModuleContract.Dir)
	var room: RoomModule = RoomFactory.build(id, typed_open, opts)
	room.position = ModuleContract.grid_to_world(cell)
	root.add_child(room)
