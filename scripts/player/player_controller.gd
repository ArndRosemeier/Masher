class_name PlayerController
extends CharacterBody3D

signal died
signal health_changed(current: int, maximum: int)
signal interact_hint_changed(text: String)

@export var move_speed: float = 5.0
@export var mouse_sensitivity: float = 0.0025
@export var max_health: int = 100
@export var attack_damage: int = 25
@export var attack_range: float = 2.2
@export var attack_cooldown: float = 0.45
@export var invuln_time: float = 0.55

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var attack_ray: RayCast3D = $CameraPivot/Camera3D/AttackRay
@onready var weapon_flash: OmniLight3D = $CameraPivot/Camera3D/WeaponFlash

var health: int
var _yaw: float = 0.0
var _pitch: float = 0.0
var _attack_cd: float = 0.0
var _invuln: float = 0.0
var _alive: bool = true
var _footstep_cd: float = 0.0
var _input_enabled: bool = true
var _last_interact_hint: String = ""


func _ready() -> void:
	health = max_health
	add_to_group(&"player")
	attack_ray.target_position = Vector3(0.0, 0.0, -attack_range)
	attack_ray.enabled = true
	weapon_flash.visible = false
	health_changed.emit(health, max_health)
	# Capture after the window is ready — immediate capture in _ready often fails on Windows.
	call_deferred("_capture_mouse")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _input_enabled and _alive:
		_capture_mouse()


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not _input_enabled or not _alive:
		return

	# Click anywhere to re-capture if the cursor was freed (Esc / focus loss).
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch -= motion.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
		rotation.y = _yaw
		camera_pivot.rotation.x = _pitch
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_attack()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_capture_mouse()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not _alive:
		velocity = Vector3.ZERO
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var input_dir := Vector2.ZERO
	if _input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var basis_yaw := Basis(Vector3.UP, _yaw)
	var move := (basis_yaw * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	move_and_slide()

	if move.length() > 0.1 and is_on_floor():
		_footstep_cd -= delta
		if _footstep_cd <= 0.0:
			AudioManager.play_footstep()
			_footstep_cd = 0.42
	else:
		_footstep_cd = 0.0

	_update_interact_hint()


func _try_interact() -> void:
	var door := _nearest_door_in_range()
	if door != null:
		door.try_interact()


func _nearest_door_in_range() -> Door:
	var best: Door = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(Door.GROUP):
		var door := node as Door
		if door == null or not door.is_player_in_range():
			continue
		var dist := global_position.distance_to(door.global_position)
		if dist < best_dist:
			best_dist = dist
			best = door
	return best


func _update_interact_hint() -> void:
	var door := _nearest_door_in_range()
	var text := ""
	if door != null:
		text = "E — Close" if door.is_open else "E — Open"
	if text == _last_interact_hint:
		return
	_last_interact_hint = text
	interact_hint_changed.emit(text)


func _try_attack() -> void:
	if _attack_cd > 0.0:
		return
	_attack_cd = attack_cooldown
	AudioManager.play_swing()
	_flash_weapon()

	attack_ray.force_raycast_update()
	if attack_ray.is_colliding():
		var collider := attack_ray.get_collider()
		var enemy := _find_enemy(collider)
		if enemy != null:
			enemy.take_damage(attack_damage, global_position)
			AudioManager.play_hit()
			_hitstop()


func _find_enemy(node: Object) -> EnemyController:
	var n := node as Node
	while n != null:
		if n is EnemyController:
			return n as EnemyController
		n = n.get_parent()
	return null


func take_damage(amount: int, _from: Vector3) -> void:
	if not _alive or _invuln > 0.0:
		return
	health = maxi(0, health - amount)
	_invuln = invuln_time
	health_changed.emit(health, max_health)
	AudioManager.play_hurt()
	if health <= 0:
		_die()


func _die() -> void:
	_alive = false
	_input_enabled = false
	AudioManager.play_death()
	died.emit()


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if enabled:
		_capture_mouse()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _flash_weapon() -> void:
	weapon_flash.visible = true
	weapon_flash.light_energy = 2.5
	var tween := create_tween()
	tween.tween_property(weapon_flash, "light_energy", 0.0, 0.12)
	tween.finished.connect(func() -> void: weapon_flash.visible = false)


func _hitstop() -> void:
	Engine.time_scale = 0.15
	await get_tree().create_timer(0.05, true, false, true).timeout
	Engine.time_scale = 1.0
