class_name LootChest
extends Node3D
## Interactable chest — opens once and rolls books into inventory (or world).

const GROUP := &"loot_chest"
const _LootTable := preload("res://scripts/loot/loot_table.gd")

const OPEN_ANGLE_DEG := -110.0
const OPEN_DURATION := 0.4

var opened: bool = false
var _player_near: bool = false
var _rng := RandomNumberGenerator.new()
var _lid: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	_ensure_trigger()
	_lid = _find_lid()
	assert(_lid != null, "LootChest: missing chest lid mesh (expected *lid* under Mesh)")


func is_player_in_range() -> bool:
	return _player_near and not opened


func try_interact(player: Node) -> void:
	if opened:
		return
	assert(player != null, "LootChest.try_interact: null player")
	var inv = player.get_node_or_null("Inventory")
	assert(inv != null and inv.has_method("add_item"), "LootChest: player inventory")
	opened = true
	var drops: Array[StringName] = _LootTable.roll_chest(_rng)
	for item_id in drops:
		inv.add_item(item_id, 1)
	AudioManager.play_ui()
	_play_open()


func _ensure_trigger() -> void:
	if has_node("Trigger"):
		return
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.8
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_player_near = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_player_near = false


func _play_open() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_lid, "rotation:x", deg_to_rad(OPEN_ANGLE_DEG), OPEN_DURATION)


func _find_lid() -> Node3D:
	for node in find_children("*lid*", "Node3D", true, false):
		return node as Node3D
	return null
