class_name EnemyController
extends CharacterBody3D

const _LootTable := preload("res://scripts/loot/loot_table.gd")
const _Kaykit := preload("res://scripts/dungeon/kaykit_paths.gd")

signal died

enum State { IDLE, CHASE, WINDUP, RECOVER, DEAD }

@export var move_speed: float = 2.6
@export var aggro_range: float = 12.0
@export var attack_range: float = 1.7
@export var attack_damage: int = 15
@export var windup_time: float = 0.55
@export var recover_time: float = 0.7
@export var max_health: int = 60

@onready var mesh_root: Node3D = $MeshRoot
@onready var telegraph: MeshInstance3D = $Telegraph
@onready var hitbox: Area3D = $Hitbox

var health: int
var enemy_def_id: StringName = &"skeleton_warrior"
var drop_chance: float = 0.35
var _state: State = State.IDLE
var _timer: float = 0.0
var _player: Node3D
var _alive: bool = true
var _rng := RandomNumberGenerator.new()
var _attack_tween: Tween
var _mesh_rest: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	_rng.randomize()
	health = max_health
	add_to_group(&"enemy")
	telegraph.visible = false
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	_mesh_rest = mesh_root.transform
	_try_bind_player()


func apply_def(def) -> void:
	assert(def != null, "EnemyController.apply_def: null")
	enemy_def_id = def.id
	max_health = def.max_health
	health = def.max_health
	move_speed = def.move_speed
	aggro_range = def.aggro_range
	attack_range = def.attack_range
	attack_damage = def.attack_damage
	windup_time = def.windup_time
	recover_time = def.recover_time
	drop_chance = def.drop_chance
	scale = Vector3.ONE * def.scale
	_swap_mesh(def.mesh_path, def.tint)


func is_alive() -> bool:
	return _alive


func apply_knockback(velocity_xz: Vector3) -> void:
	velocity += velocity_xz


func _swap_mesh(path: String, tint: Color) -> void:
	for child in mesh_root.get_children():
		child.queue_free()
	if not ResourceLoader.exists(path):
		const Loud := preload("res://scripts/core/loud_error.gd")
		Loud.report("EnemyController", "Missing mesh %s" % path)
		return
	var packed := load(path) as PackedScene
	assert(packed != null, "Enemy mesh failed to load: %s" % path)
	var inst := packed.instantiate() as Node3D
	inst.name = "Body"
	inst.transform = Transform3D(
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3.ZERO
	)
	mesh_root.add_child(inst)
	_apply_tint(inst, tint)


func _apply_tint(node: Node, tint: Color) -> void:
	## KayKit meshes use their own materials; elite/minion variants rely on scale.
	## Tint reserved for a later material-pass if we need stronger differentiation.
	if tint.is_equal_approx(Color.WHITE):
		return
	for child in node.get_children():
		_apply_tint(child, tint)


func _try_bind_player() -> void:
	var nodes := get_tree().get_nodes_in_group(&"player")
	if nodes.size() > 0:
		_player = nodes[0] as Node3D


func _blocked_by_closed_door(move_dir: Vector3) -> bool:
	## Don't press into a closed door; keep ~1.35m clearance from the panel.
	const DOOR_STANDOFF := 1.35
	const DoorScript := preload("res://scripts/dungeon/door.gd")
	for node in get_tree().get_nodes_in_group(DoorScript.GROUP):
		var door := node as Node3D
		if door == null or bool(door.get("is_open")):
			continue
		var to_door := door.global_position - global_position
		to_door.y = 0.0
		var door_dist := to_door.length()
		if door_dist > DOOR_STANDOFF + 0.6 or door_dist < 0.01:
			continue
		## Only stop when the door is ahead of our chase direction.
		if move_dir.dot(to_door.normalized()) < 0.35:
			continue
		if door_dist <= DOOR_STANDOFF:
			return true
	return false


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	if _player == null or not is_instance_valid(_player):
		_try_bind_player()
		return

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	match _state:
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			if global_position.distance_to(_player.global_position) <= aggro_range:
				_state = State.CHASE
		State.CHASE:
			var to_player := _player.global_position - global_position
			to_player.y = 0.0
			var dist := to_player.length()
			if dist <= attack_range:
				_begin_windup()
			elif dist <= aggro_range:
				var dir := to_player.normalized()
				## Stay off closed door panels so meshes don't poke through.
				if _blocked_by_closed_door(dir):
					velocity.x = 0.0
					velocity.z = 0.0
				else:
					velocity.x = dir.x * move_speed
					velocity.z = dir.z * move_speed
				if dir.length() > 0.01:
					look_at(global_position + dir, Vector3.UP)
			else:
				_state = State.IDLE
		State.WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			_timer -= delta
			_pulse_telegraph()
			if _timer <= 0.0:
				_do_attack()
		State.RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			_timer -= delta
			if _timer <= 0.0:
				_state = State.CHASE
				telegraph.visible = false
				if _attack_tween == null or not _attack_tween.is_running():
					mesh_root.transform = _mesh_rest
		State.DEAD:
			velocity = Vector3.ZERO

	move_and_slide()


func _begin_windup() -> void:
	_state = State.WINDUP
	_timer = windup_time
	telegraph.visible = true
	telegraph.scale = Vector3.ONE * 0.6
	_play_windup_anim()


func _pulse_telegraph() -> void:
	var t := 1.0 - clampf(_timer / windup_time, 0.0, 1.0)
	telegraph.scale = Vector3.ONE * lerpf(0.6, 1.4, t)
	var mat := telegraph.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(1.0, lerpf(0.8, 0.1, t), 0.1, 0.55)


func _do_attack() -> void:
	_play_strike_anim()
	hitbox.monitoring = true
	await get_tree().create_timer(0.12).timeout
	if not _alive:
		return
	hitbox.monitoring = false
	_state = State.RECOVER
	_timer = recover_time
	telegraph.visible = false


func _play_windup_anim() -> void:
	_kill_attack_tween()
	mesh_root.transform = _mesh_rest
	_attack_tween = create_tween()
	_attack_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	## Lean back / coil before the strike.
	var coiled := _mesh_rest * Transform3D(
		Basis.from_euler(Vector3(-0.35, 0.0, 0.0)),
		Vector3(0.0, 0.05, 0.18)
	)
	_attack_tween.tween_property(mesh_root, "transform", coiled, maxf(0.08, windup_time * 0.85))


func _play_strike_anim() -> void:
	_kill_attack_tween()
	_attack_tween = create_tween()
	_attack_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	var lunge := _mesh_rest * Transform3D(
		Basis.from_euler(Vector3(0.55, 0.0, 0.0)),
		Vector3(0.0, -0.02, -0.35)
	)
	_attack_tween.tween_property(mesh_root, "transform", lunge, 0.08)
	_attack_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(mesh_root, "transform", _mesh_rest, maxf(0.12, recover_time * 0.55))


func _kill_attack_tween() -> void:
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
	_attack_tween = null


func _on_hitbox_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player") and body.has_method("take_damage"):
		body.call("take_damage", attack_damage, global_position)


func take_damage(amount: int, from: Vector3) -> void:
	if not _alive:
		return
	health = maxi(0, health - amount)
	_flash_hurt()
	var knock := global_position - from
	knock.y = 0.0
	if knock.length() > 0.01:
		velocity += knock.normalized() * 4.5
	if health <= 0:
		_die()


func _flash_hurt() -> void:
	var tween := create_tween()
	tween.tween_property(mesh_root, "scale", Vector3.ONE * 1.08, 0.05)
	tween.tween_property(mesh_root, "scale", Vector3.ONE, 0.08)


func _die() -> void:
	_alive = false
	_state = State.DEAD
	_kill_attack_tween()
	mesh_root.transform = _mesh_rest
	telegraph.visible = false
	hitbox.monitoring = false
	collision_layer = 0
	collision_mask = 0
	_spawn_drops()
	died.emit()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.35)
	tween.finished.connect(queue_free)


func _spawn_drops() -> void:
	var drops: Array[StringName] = _LootTable.roll_enemy_drop(_rng, drop_chance)
	if drops.is_empty():
		return
	var packed := load(_Kaykit.BOOK_PICKUP_SCENE) as PackedScene
	assert(packed != null, "Missing book pickup scene")
	var parent := get_parent()
	if parent == null:
		return
	for item_id in drops:
		var book := packed.instantiate()
		parent.add_child(book)
		(book as Node3D).global_position = global_position + Vector3(0.0, 0.4, 0.0)
		if book.has_method("setup"):
			book.call("setup", item_id)
