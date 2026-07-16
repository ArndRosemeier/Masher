class_name RoomCells
extends RefCounted
## ASCII cell legend for layered room specs.

enum Kind {
	WALL,
	EMPTY,
	FLOOR,
	STAIR,
	DOWN_STAIR,
	SHAFT,
	PLAYER,
	EXIT,
	ENEMY,
}


static func to_char(kind: Kind) -> String:
	match kind:
		Kind.WALL:
			return "#"
		Kind.EMPTY:
			return " "
		Kind.FLOOR:
			return "."
		Kind.STAIR:
			return "S"
		Kind.DOWN_STAIR:
			return "D"
		Kind.SHAFT:
			return "^"
		Kind.PLAYER:
			return "P"
		Kind.EXIT:
			return "E"
		Kind.ENEMY:
			return "M"
	return "?"


static func from_char(ch: String) -> Kind:
	match ch:
		"#":
			return Kind.WALL
		" ":
			return Kind.EMPTY
		".", "X", "+":
			## `.` is floor. `X`/`+` remain accepted aliases for older room files.
			return Kind.FLOOR
		"S":
			return Kind.STAIR
		"D":
			return Kind.DOWN_STAIR
		"^":
			return Kind.SHAFT
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
	return (
		kind == Kind.FLOOR
		or kind == Kind.STAIR
		or kind == Kind.DOWN_STAIR
		or kind == Kind.SHAFT
		or kind == Kind.PLAYER
		or kind == Kind.EXIT
		or kind == Kind.ENEMY
	)


static func is_floor_surface(kind: Kind) -> bool:
	## Flat floor colliders. Ascending `S` keeps a slab under treads; `D` is an open shaft.
	return (
		kind == Kind.FLOOR
		or kind == Kind.STAIR
		or kind == Kind.SHAFT
		or kind == Kind.PLAYER
		or kind == Kind.EXIT
		or kind == Kind.ENEMY
	)


static func is_up_stair(kind: Kind) -> bool:
	return kind == Kind.STAIR


static func is_down_stair(kind: Kind) -> bool:
	return kind == Kind.DOWN_STAIR


static func blocks_ceiling(kind: Kind) -> bool:
	## Shaft / down-stair cells leave the ceiling open for vertical connectors.
	return kind != Kind.EMPTY and kind != Kind.DOWN_STAIR and kind != Kind.SHAFT
