class_name ModuleContract
extends RefCounted
## Shared module contract for fixed POC layouts and future room-graph procgen.
##
## Grid: modules snap on a ROOM_SIZE cell. Connectors sit at edge midpoints.
## Gameplay must discover PlayerSpawn / EnemySpawn / Exit via groups — never
## hardcode world coordinates.

const TILE_SIZE := 2.0
const ROOM_TILES := 4
const ROOM_SIZE := TILE_SIZE * ROOM_TILES ## 8.0 meters

const GROUP_PLAYER_SPAWN := &"player_spawn"
const GROUP_ENEMY_SPAWN := &"enemy_spawn"
const GROUP_EXIT := &"exit"
const GROUP_CONNECTOR := &"connector"
const GROUP_MODULE := &"room_module"

enum Dir { N, E, S, W }


static func dir_vector(dir: Dir) -> Vector3:
	match dir:
		Dir.N:
			return Vector3(0.0, 0.0, -1.0)
		Dir.E:
			return Vector3(1.0, 0.0, 0.0)
		Dir.S:
			return Vector3(0.0, 0.0, 1.0)
		Dir.W:
			return Vector3(-1.0, 0.0, 0.0)
	return Vector3.ZERO


static func opposite(dir: Dir) -> Dir:
	match dir:
		Dir.N:
			return Dir.S
		Dir.E:
			return Dir.W
		Dir.S:
			return Dir.N
		Dir.W:
			return Dir.E
	return Dir.N


static func dir_name(dir: Dir) -> String:
	match dir:
		Dir.N:
			return "N"
		Dir.E:
			return "E"
		Dir.S:
			return "S"
		Dir.W:
			return "W"
	return "?"


static func grid_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * ROOM_SIZE, 0.0, float(cell.y) * ROOM_SIZE)


static func connector_local_position(dir: Dir) -> Vector3:
	var half := ROOM_SIZE * 0.5
	match dir:
		Dir.N:
			return Vector3(half, 0.0, 0.0)
		Dir.E:
			return Vector3(ROOM_SIZE, 0.0, half)
		Dir.S:
			return Vector3(half, 0.0, ROOM_SIZE)
		Dir.W:
			return Vector3(0.0, 0.0, half)
	return Vector3(half, 0.0, half)
