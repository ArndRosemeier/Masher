class_name ResourcePool
extends Node
## Regenerating float pool (mana / stamina).

signal changed(current: float, maximum: float)

@export var max_value: float = 100.0
@export var regen_per_sec: float = 8.0

var current: float = 0.0
var regen_paused: float = 0.0


func _ready() -> void:
	current = max_value
	changed.emit(current, max_value)


func _process(delta: float) -> void:
	regen_paused = maxf(0.0, regen_paused - delta)
	if regen_paused > 0.0:
		return
	if current >= max_value:
		return
	current = minf(max_value, current + regen_per_sec * delta)
	changed.emit(current, max_value)


func can_afford(amount: float) -> bool:
	return current + 0.001 >= amount


func spend(amount: float, pause_regen: float = 0.35) -> void:
	assert(amount >= 0.0, "ResourcePool.spend: negative")
	assert(can_afford(amount), "ResourcePool.spend: cannot afford %.1f (have %.1f)" % [amount, current])
	current = maxf(0.0, current - amount)
	regen_paused = maxf(regen_paused, pause_regen)
	changed.emit(current, max_value)


func set_max(value: float, fill: bool = false) -> void:
	assert(value > 0.0, "ResourcePool.set_max: max must be > 0")
	max_value = value
	if fill:
		current = max_value
	else:
		current = minf(current, max_value)
	changed.emit(current, max_value)


func refill() -> void:
	current = max_value
	changed.emit(current, max_value)
