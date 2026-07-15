class_name Health
extends Node

signal changed(current: int, maximum: int)
signal depleted

@export var max_health: int = 50

var current: int


func _ready() -> void:
	current = max_health
	changed.emit(current, max_health)


func apply_damage(amount: int) -> void:
	if current <= 0:
		return
	current = maxi(0, current - amount)
	changed.emit(current, max_health)
	if current <= 0:
		depleted.emit()


func reset() -> void:
	current = max_health
	changed.emit(current, max_health)
