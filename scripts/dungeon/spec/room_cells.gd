class_name RoomCells
extends RefCounted
## ASCII cell legend for layered room specs.

enum Kind {
	WALL,
	EMPTY,
	FLOOR,
	STAIR,
	PLAYER,
	EXIT,
	ENEMY,
}


static func from_char(ch: String) -> Kind:
	match ch:
		"#":
			return Kind.WALL
		".":
			return Kind.EMPTY
		"X", "+":
			return Kind.FLOOR
		"S":
			return Kind.STAIR
		"P":
			return Kind.PLAYER
		"E":
			return Kind.EXIT
		"M":
			return Kind.ENEMY
		_:
			push_error("Unknown room cell char '%s'" % ch)
			return Kind.EMPTY


static func is_walkable(kind: Kind) -> bool:
	return kind == Kind.FLOOR or kind == Kind.STAIR or kind == Kind.PLAYER or kind == Kind.EXIT or kind == Kind.ENEMY


static func is_floor_surface(kind: Kind) -> bool:
	## Flat floor colliders. Stairs are included so the slab under the treads exists;
	## the baker still owns the step meshes themselves.
	return (
		kind == Kind.FLOOR
		or kind == Kind.STAIR
		or kind == Kind.PLAYER
		or kind == Kind.EXIT
		or kind == Kind.ENEMY
	)
