class_name Health
extends Node
## Integer hit points with slow regen and loud depletion.

signal changed(current: int, maximum: int)
signal depleted

@export var max_health: int = 50
## Slow passive recovery (HP per second). Fractional amounts accumulate.
@export var regen_per_sec: float = 2.0
## After taking damage, regen waits this long before resuming.
@export var damage_regen_pause: float = 2.5

var current: int = 0
var regen_paused: float = 0.0
var _regen_accum: float = 0.0


func _ready() -> void:
	if current <= 0:
		current = max_health
	changed.emit(current, max_health)


func _process(delta: float) -> void:
	regen_paused = maxf(0.0, regen_paused - delta)
	if regen_paused > 0.0:
		return
	if current <= 0 or current >= max_health or regen_per_sec <= 0.0:
		return
	_regen_accum += regen_per_sec * delta
	if _regen_accum < 1.0:
		return
	var amount := int(_regen_accum)
	_regen_accum -= float(amount)
	heal(amount)


func apply_damage(amount: int) -> void:
	assert(amount >= 0, "Health.apply_damage: negative amount")
	if current <= 0:
		return
	current = maxi(0, current - amount)
	regen_paused = maxf(regen_paused, damage_regen_pause)
	_regen_accum = 0.0
	changed.emit(current, max_health)
	if current <= 0:
		depleted.emit()


func heal(amount: int) -> void:
	assert(amount >= 0, "Health.heal: negative amount")
	if amount <= 0:
		return
	if current <= 0:
		return
	current = mini(max_health, current + amount)
	changed.emit(current, max_health)


func set_max_health(value: int, heal_gained: bool = false) -> void:
	assert(value > 0, "Health.set_max_health: max must be > 0")
	var gained := value - max_health
	max_health = value
	if heal_gained and gained > 0:
		current = mini(max_health, current + gained)
	else:
		current = mini(current, max_health)
	if current <= 0:
		current = max_health
	changed.emit(current, max_health)


func reset() -> void:
	current = max_health
	_regen_accum = 0.0
	regen_paused = 0.0
	changed.emit(current, max_health)
