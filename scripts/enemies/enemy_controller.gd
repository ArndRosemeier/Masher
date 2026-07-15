class_name EnemyController
extends CharacterBody3D

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
var _state: State = State.IDLE
var _timer: float = 0.0
var _player: PlayerController
var _alive: bool = true
var _base_modulate := Color.WHITE


func _ready() -> void:
	health = max_health
	add_to_group(&"enemy")
	telegraph.visible = false
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	_try_bind_player()


func _try_bind_player() -> void:
	var nodes := get_tree().get_nodes_in_group(&"player")
	if nodes.size() > 0:
		_player = nodes[0] as PlayerController


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
		State.DEAD:
			velocity = Vector3.ZERO

	move_and_slide()


func _begin_windup() -> void:
	_state = State.WINDUP
	_timer = windup_time
	telegraph.visible = true
	telegraph.scale = Vector3.ONE * 0.6


func _pulse_telegraph() -> void:
	var t := 1.0 - clampf(_timer / windup_time, 0.0, 1.0)
	telegraph.scale = Vector3.ONE * lerpf(0.6, 1.4, t)
	var mat := telegraph.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(1.0, lerpf(0.8, 0.1, t), 0.1, 0.55)


func _do_attack() -> void:
	hitbox.monitoring = true
	await get_tree().create_timer(0.12).timeout
	if not _alive:
		return
	hitbox.monitoring = false
	_state = State.RECOVER
	_timer = recover_time
	telegraph.visible = false


func _on_hitbox_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		(body as PlayerController).take_damage(attack_damage, global_position)


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
	telegraph.visible = false
	hitbox.monitoring = false
	collision_layer = 0
	collision_mask = 0
	died.emit()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.35)
	tween.finished.connect(queue_free)
