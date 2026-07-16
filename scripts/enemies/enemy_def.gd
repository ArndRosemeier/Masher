class_name EnemyDef
extends RefCounted

const _Self := preload("res://scripts/enemies/enemy_def.gd")
const _Kaykit := preload("res://scripts/dungeon/kaykit_paths.gd")
const _Loud := preload("res://scripts/core/loud_error.gd")

var id: StringName = &""
var display_name: String = ""
var mesh_path: String = ""
var max_health: int = 60
var move_speed: float = 2.6
var aggro_range: float = 12.0
var attack_range: float = 1.7
var attack_damage: int = 15
var windup_time: float = 0.55
var recover_time: float = 0.7
var scale: float = 1.0
var tint: Color = Color.WHITE
var drop_chance: float = 0.35


static func catalog() -> Array:
	var out: Array = []
	out.append(_make(
		&"skeleton_warrior",
		"Skeleton Warrior",
		_Kaykit.SKELETON_WARRIOR,
		70, 2.5, 14, 1.0, Color.WHITE, 0.4
	))
	out.append(_make(
		&"skeleton_minion",
		"Skeleton Minion",
		_Kaykit.SKELETON_MINION,
		40, 3.1, 10, 0.85, Color(0.85, 0.9, 0.8), 0.25
	))
	out.append(_make(
		&"skeleton_minion_elite",
		"Elite Minion",
		_Kaykit.SKELETON_MINION,
		90, 2.8, 18, 1.15, Color(0.95, 0.55, 0.45), 0.55
	))
	out.append(_make(
		&"skeleton_rogue",
		"Skeleton Rogue",
		_Kaykit.SKELETON_ROGUE,
		50, 3.6, 16, 0.95, Color(0.75, 0.85, 1.0), 0.4
	))
	out.append(_make(
		&"skeleton_mage",
		"Skeleton Mage",
		_Kaykit.SKELETON_MAGE,
		55, 2.2, 22, 1.0, Color(0.85, 0.7, 1.0), 0.5
	))
	return out


static func by_id(id: StringName):
	for def in catalog():
		if def.id == id:
			return def
	_Loud.report("EnemyDef", "Unknown enemy %s" % String(id))
	return null


static func pick_random(rng: RandomNumberGenerator):
	var all: Array = catalog()
	var weights := [30, 35, 8, 15, 12]
	var total := 0
	for w in weights:
		total += w
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for i in all.size():
		acc += weights[i]
		if roll < acc:
			return all[i]
	return all[0]


static func _make(
	id: StringName,
	display: String,
	mesh: String,
	hp: int,
	speed: float,
	dmg: int,
	scl: float,
	tint_color: Color,
	drop: float
):
	var d = _Self.new()
	d.id = id
	d.display_name = display
	d.mesh_path = mesh
	d.max_health = hp
	d.move_speed = speed
	d.attack_damage = dmg
	d.scale = scl
	d.tint = tint_color
	d.drop_chance = drop
	if id == &"skeleton_rogue":
		d.aggro_range = 14.0
		d.attack_range = 1.5
		d.windup_time = 0.35
		d.recover_time = 0.45
	elif id == &"skeleton_mage":
		d.aggro_range = 16.0
		d.attack_range = 2.2
		d.windup_time = 0.75
		d.recover_time = 0.9
	return d
