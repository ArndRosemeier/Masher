class_name AbilityCaster
extends Node
## Casts hotbar abilities using mana (spells) or stamina (skills).

const _Abilities := preload("res://scripts/progression/ability_catalog.gd")
const _AbilityDef := preload("res://scripts/progression/ability_def.gd")
const _Loud := preload("res://scripts/core/loud_error.gd")
const _SpellVfx := preload("res://scripts/combat/spell_vfx.gd")

const FIREBOLT_RANGE := 18.0

signal cast_failed(reason: String)
signal cast_ok(ability_id: StringName, rank: int)
signal shield_changed(seconds_left: float)

var player: Node
var progression: Node
var mana: Node
var stamina: Node

var _cooldowns: Dictionary = {} ## StringName -> float remaining
var _shield_time: float = 0.0
var _shield_absorb: int = 0


func setup(p_player: Node, p_progression: Node, p_mana: Node, p_stamina: Node) -> void:
	player = p_player
	progression = p_progression
	mana = p_mana
	stamina = p_stamina


func _process(delta: float) -> void:
	var keys := _cooldowns.keys()
	for key_variant in keys:
		var id: StringName = key_variant
		_cooldowns[id] = float(_cooldowns[id]) - delta
		if float(_cooldowns[id]) <= 0.0:
			_cooldowns.erase(id)
	if _shield_time > 0.0:
		_shield_time = maxf(0.0, _shield_time - delta)
		shield_changed.emit(_shield_time)
		if _shield_time <= 0.0:
			_shield_absorb = 0


func try_cast_slot(slot: int) -> void:
	assert(progression != null and player != null, "AbilityCaster not setup")
	var hotbar: Array = progression.get("hotbar")
	if slot < 0 or slot >= hotbar.size():
		return
	var ability_id: StringName = hotbar[slot]
	if ability_id == &"":
		cast_failed.emit("Empty hotbar slot")
		return
	try_cast(ability_id)


func try_cast(ability_id: StringName) -> void:
	var def = _Abilities.by_id(ability_id)
	if def == null:
		return
	var rank: int = int(progression.call("rank_of", ability_id))
	if rank <= 0:
		cast_failed.emit("Not learned")
		return
	if float(_cooldowns.get(ability_id, 0.0)) > 0.0:
		cast_failed.emit("On cooldown")
		return
	var cost: float = float(def.cost_at(rank))
	if def.kind == _AbilityDef.Kind.SPELL:
		if not bool(mana.call("can_afford", cost)):
			cast_failed.emit("Not enough mana")
			return
		mana.call("spend", cost)
	else:
		if not bool(stamina.call("can_afford", cost)):
			cast_failed.emit("Not enough stamina")
			return
		stamina.call("spend", cost)
	_cooldowns[ability_id] = float(def.cooldown_at(rank))
	_execute(def, rank)
	cast_ok.emit(ability_id, rank)


func absorb_damage(amount: int) -> int:
	## Returns damage that still applies after shield.
	if _shield_time <= 0.0 or _shield_absorb <= 0:
		return amount
	var blocked := mini(amount, _shield_absorb)
	_shield_absorb -= blocked
	if _shield_absorb <= 0:
		_shield_time = 0.0
		shield_changed.emit(0.0)
	return amount - blocked


func _execute(def, rank: int) -> void:
	match def.id:
		&"firebolt":
			_cast_firebolt(def.damage_at(rank))
		&"frost_nova":
			_cast_nova(def.damage_at(rank), def.radius_at(rank), true)
		&"arc_shield":
			_shield_time = 4.0 + float(rank) * 0.75
			_shield_absorb = 25 + rank * 15
			shield_changed.emit(_shield_time)
			var p3 := player as Node3D
			if p3 != null:
				_SpellVfx.arc_shield(p3, _shield_time)
		&"power_strike":
			_cast_melee_burst(def.damage_at(rank), 2.6 + float(rank) * 0.15, false)
		&"whirlwind":
			_cast_nova(def.damage_at(rank), def.radius_at(rank), false)
		&"bash":
			_cast_melee_burst(def.damage_at(rank), 2.4, true)
		_:
			_Loud.report("AbilityCaster", "No execute handler for %s" % String(def.id))


func _cast_firebolt(damage: int) -> void:
	AudioManager.play_swing()
	var p3 := player as Node3D
	var cam: Camera3D = p3.get_node("CameraPivot/Camera3D")
	var from := (
		cam.global_position
		+ (-cam.global_transform.basis.z * 0.45)
		+ (cam.global_transform.basis.x * 0.18)
		+ (-cam.global_transform.basis.y * 0.12)
	)
	var dir := -cam.global_transform.basis.z
	var far := cam.global_position + dir * FIREBOLT_RANGE
	var hit := _ray_query(cam.global_position, far)
	var impact: Vector3 = far
	var enemy: Node = null
	if not hit.is_empty():
		impact = hit.position as Vector3
		enemy = _find_enemy(hit.collider)
	_SpellVfx.firebolt(p3, from, impact)
	## Land damage with the impact burst, not on cast.
	var flight := clampf(from.distance_to(impact) / 26.0, 0.14, 0.5)
	await player.get_tree().create_timer(flight).timeout
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("is_alive") and bool(enemy.call("is_alive")):
		enemy.call("take_damage", damage, p3.global_position)
		AudioManager.play_hit()


func _cast_melee_burst(damage: int, reach: float, knock_hard: bool) -> void:
	AudioManager.play_swing()
	var p3 := player as Node3D
	var forward := -p3.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	for node in player.get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null or not enemy.has_method("is_alive") or not bool(enemy.call("is_alive")):
			continue
		var to := enemy.global_position - p3.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > reach or dist < 0.01:
			continue
		if to.normalized().dot(forward) < 0.25:
			continue
		enemy.call("take_damage", damage, p3.global_position)
		if knock_hard and enemy.has_method("apply_knockback"):
			enemy.call("apply_knockback", to.normalized() * 8.0)
		AudioManager.play_hit()


func _cast_nova(damage: int, radius: float, frost: bool) -> void:
	AudioManager.play_swing()
	var p3 := player as Node3D
	if frost:
		_SpellVfx.frost_nova(p3, p3.global_position, radius)
	for node in player.get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null or not enemy.has_method("is_alive") or not bool(enemy.call("is_alive")):
			continue
		var dist := p3.global_position.distance_to(enemy.global_position)
		if dist > radius:
			continue
		enemy.call("take_damage", damage, p3.global_position)
		AudioManager.play_hit()


func _ray_query(from: Vector3, to: Vector3) -> Dictionary:
	var space := (player as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	## World geometry (1) + enemies (4), skip player (2).
	q.collision_mask = 1 | 4
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [(player as CollisionObject3D).get_rid()]
	return space.intersect_ray(q)


func _find_enemy(node: Object) -> Node:
	var n := node as Node
	while n != null:
		if n.is_in_group(&"enemy"):
			return n
		n = n.get_parent()
	return null
