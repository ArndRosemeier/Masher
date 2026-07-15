class_name Door
extends Node3D
## Swinging door with collision. E / interact while in range toggles open/closed.

signal opened
signal closed

const GROUP := &"door"

@export var open_angle_deg: float = 95.0
@export var open_duration: float = 0.45
@export var start_closed: bool = true

var is_open: bool = false
var _busy: bool = false
var _players_in_range: int = 0

@onready var hinge: Node3D = $Hinge
@onready var body: StaticBody3D = $Hinge/Body
@onready var interact_area: Area3D = $InteractArea
@onready var sfx_open: AudioStreamPlayer3D = $SfxOpen
@onready var sfx_close: AudioStreamPlayer3D = $SfxClose


func _ready() -> void:
	add_to_group(GROUP)
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)
	is_open = not start_closed
	hinge.rotation.y = deg_to_rad(open_angle_deg) if is_open else 0.0
	_set_blocking(not is_open)


func is_player_in_range() -> bool:
	return _players_in_range > 0


func try_interact() -> bool:
	if not is_player_in_range() or _busy:
		return false
	toggle()
	return true


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open or _busy:
		return
	_busy = true
	_set_blocking(false)
	if sfx_open.stream:
		sfx_open.play()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(hinge, "rotation:y", deg_to_rad(open_angle_deg), open_duration)
	tween.finished.connect(_on_open_finished)


func close() -> void:
	if not is_open or _busy:
		return
	_busy = true
	if sfx_close.stream:
		sfx_close.play()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(hinge, "rotation:y", 0.0, open_duration)
	tween.finished.connect(_on_close_finished)


func _on_open_finished() -> void:
	is_open = true
	_busy = false
	opened.emit()


func _on_close_finished() -> void:
	is_open = false
	_busy = false
	_set_blocking(true)
	closed.emit()


func _set_blocking(blocking: bool) -> void:
	body.collision_layer = 1 if blocking else 0
	body.collision_mask = 0


func _on_body_entered(other: Node3D) -> void:
	if other.is_in_group(&"player"):
		_players_in_range += 1


func _on_body_exited(other: Node3D) -> void:
	if other.is_in_group(&"player"):
		_players_in_range = maxi(0, _players_in_range - 1)
