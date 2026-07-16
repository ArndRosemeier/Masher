class_name PlayerController
extends CharacterBody3D

signal died
signal health_changed(current: int, maximum: int)
signal mana_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal interact_hint_changed(text: String)
signal toast_message(text: String)

@export var move_speed: float = 5.0
@export var mouse_sensitivity: float = 0.0025
@export var jump_velocity: float = 4.2
@export var attack_damage: int = 25
@export var attack_range: float = 2.2
@export var attack_cooldown: float = 0.45
@export var invuln_time: float = 0.55

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var attack_ray: RayCast3D = $CameraPivot/Camera3D/AttackRay
@onready var weapon_flash: OmniLight3D = $CameraPivot/Camera3D/WeaponFlash
@onready var view_weapon: Node3D = $CameraPivot/Camera3D/ViewWeapon
## Typed as Node so boot works before global class_name cache refreshes.
@onready var health: Node = $Health
@onready var mana: Node = $Mana
@onready var stamina: Node = $Stamina
@onready var inventory: Node = $Inventory
@onready var progression: Node = $Progression
@onready var caster: Node = $AbilityCaster

var inventory_open: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _attack_cd: float = 0.0
var _invuln: float = 0.0
var _alive: bool = true
var _footstep_cd: float = 0.0
var _input_enabled: bool = true
var _last_interact_hint: String = ""


func _ready() -> void:
	add_to_group(&"player")
	attack_ray.target_position = Vector3(0.0, 0.0, -attack_range)
	attack_ray.enabled = true
	weapon_flash.visible = false
	health.set("max_health", 100)
	health.set("regen_per_sec", 2.0)
	health.set("damage_regen_pause", 2.5)
	health.call("reset")
	mana.call("set_max", 100.0, true)
	mana.set("regen_per_sec", 7.0)
	stamina.call("set_max", 100.0, true)
	stamina.set("regen_per_sec", 14.0)
	caster.call("setup", self, progression, mana, stamina)
	health.connect("changed", _on_health_changed)
	health.connect("depleted", _die)
	mana.connect("changed", func(c: float, m: float) -> void: mana_changed.emit(c, m))
	stamina.connect("changed", func(c: float, m: float) -> void: stamina_changed.emit(c, m))
	inventory.connect("toast", func(msg: String) -> void: toast_message.emit(msg))
	progression.connect("toast", func(msg: String) -> void: toast_message.emit(msg))
	caster.connect("cast_failed", func(reason: String) -> void: toast_message.emit(reason))
	caster.connect("cast_ok", _on_cast_ok)
	_on_health_changed(int(health.get("current")), int(health.get("max_health")))
	mana_changed.emit(float(mana.get("current")), float(mana.get("max_value")))
	stamina_changed.emit(float(stamina.get("current")), float(stamina.get("max_value")))
	_ensure_ability_actions()
	call_deferred("_capture_mouse")


func _ensure_ability_actions() -> void:
	for i in 4:
		var action := "ability_%d" % (i + 1)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for existing in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, existing)
		var key := InputEventKey.new()
		key.keycode = [KEY_1, KEY_2, KEY_3, KEY_4][i] as Key
		key.physical_keycode = key.keycode
		InputMap.action_add_event(action, key)
	if not InputMap.has_action("toggle_inventory"):
		InputMap.add_action("toggle_inventory")
		var inv_key := InputEventKey.new()
		inv_key.keycode = KEY_I
		inv_key.physical_keycode = KEY_I
		InputMap.action_add_event("toggle_inventory", inv_key)
	if not InputMap.has_action("read_book"):
		InputMap.add_action("read_book")
		var read_key := InputEventKey.new()
		read_key.keycode = KEY_ENTER
		read_key.physical_keycode = KEY_ENTER
		InputMap.action_add_event("read_book", read_key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _input_enabled and _alive and not inventory_open:
		_capture_mouse()


func _capture_mouse() -> void:
	if inventory_open:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not _input_enabled or not _alive:
		return

	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if inventory_open:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_mouse"):
			_toggle_inventory()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("read_book"):
			_read_selected_book()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var key := event as InputEventKey
			if key.keycode == KEY_UP or key.physical_keycode == KEY_UP:
				inventory.select_next(-1)
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_DOWN or key.physical_keycode == KEY_DOWN:
				inventory.select_next(1)
				get_viewport().set_input_as_handled()
		return

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
	elif event.is_action_pressed("jump") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if is_on_floor():
			velocity.y = jump_velocity
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_capture_mouse()
		get_viewport().set_input_as_handled()
	else:
		for i in 4:
			if event.is_action_pressed("ability_%d" % (i + 1)):
				caster.call("try_cast_slot", i)
				get_viewport().set_input_as_handled()
				return


func _physics_process(delta: float) -> void:
	if not _alive:
		velocity = Vector3.ZERO
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_invuln = maxf(0.0, _invuln - delta)

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var input_dir := Vector2.ZERO
	if _input_enabled and not inventory_open:
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


func _toggle_inventory() -> void:
	inventory_open = not inventory_open
	if inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_capture_mouse()
	_update_interact_hint()
	inventory.emit_signal("changed")
	toast_message.emit("Inventory open" if inventory_open else "Inventory closed")


func _read_selected_book() -> void:
	var item_id: StringName = inventory.call("selected_item_id")
	if item_id == &"":
		toast_message.emit("No book selected")
		return
	const Items := preload("res://scripts/progression/item_catalog.gd")
	const ItemDefScript := preload("res://scripts/progression/item_def.gd")
	const Abilities := preload("res://scripts/progression/ability_catalog.gd")
	var item = Items.by_id(item_id)
	if item == null:
		return
	if item.kind == ItemDefScript.Kind.SPELL_BOOK or item.kind == ItemDefScript.Kind.SKILL_BOOK:
		var ab = Abilities.by_id(item.ability_id)
		if ab != null and int(progression.call("rank_of", item.ability_id)) >= int(ab.max_rank):
			toast_message.emit("%s already max rank" % ab.display_name)
			return
	progression.call("read_book", item_id, health)
	inventory.call("remove_one", item_id)


func _try_interact() -> void:
	var chest := _nearest_chest_in_range()
	if chest != null and chest.has_method("try_interact"):
		chest.call("try_interact", self)
		return
	var book := _nearest_book_in_range()
	if book != null and book.has_method("try_pickup"):
		book.call("try_pickup", self)
		return
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


func _nearest_chest_in_range() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(&"loot_chest"):
		var chest := node as Node3D
		if chest == null or not chest.has_method("is_player_in_range"):
			continue
		if not bool(chest.call("is_player_in_range")):
			continue
		var dist := global_position.distance_to(chest.global_position)
		if dist < best_dist:
			best_dist = dist
			best = chest
	return best


func _nearest_book_in_range() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(&"book_pickup"):
		var book := node as Node3D
		if book == null:
			continue
		var dist := global_position.distance_to(book.global_position)
		if dist > 2.2:
			continue
		if dist < best_dist:
			best_dist = dist
			best = book
	return best


func _update_interact_hint() -> void:
	var text := ""
	if inventory_open:
		text = "↑↓ select · Enter Read · I close"
	else:
		var chest := _nearest_chest_in_range()
		if chest != null:
			text = "E — Open chest"
		elif _nearest_book_in_range() != null:
			text = "E — Take book"
		else:
			var door := _nearest_door_in_range()
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
	if view_weapon.has_method("play_melee"):
		view_weapon.call("play_melee")

	attack_ray.force_raycast_update()
	if attack_ray.is_colliding():
		var collider := attack_ray.get_collider()
		var enemy := _find_enemy(collider)
		if enemy != null and enemy.has_method("take_damage"):
			enemy.call("take_damage", attack_damage, global_position)
			AudioManager.play_hit()
			_hitstop()


func _on_cast_ok(ability_id: StringName, _rank: int) -> void:
	_flash_weapon()
	if view_weapon.has_method("play_ability"):
		view_weapon.call("play_ability", ability_id)


func _find_enemy(node: Object) -> Node:
	var n := node as Node
	while n != null:
		if n.is_in_group(&"enemy"):
			return n
		n = n.get_parent()
	return null


func take_damage(amount: int, _from: Vector3) -> void:
	if not _alive or _invuln > 0.0:
		return
	var remaining: int = int(caster.call("absorb_damage", amount))
	if remaining <= 0:
		_invuln = invuln_time * 0.35
		return
	_invuln = invuln_time
	health.call("apply_damage", remaining)
	AudioManager.play_hurt()


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


func _die() -> void:
	if not _alive:
		return
	_alive = false
	_input_enabled = false
	inventory_open = false
	AudioManager.play_death()
	died.emit()


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if enabled and not inventory_open:
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
