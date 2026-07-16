extends Node

enum RunPhase { MENU, PLAYING, DEAD, WON }

signal phase_changed(phase: RunPhase)

var phase: RunPhase = RunPhase.MENU
var run_index: int = 0
var last_seed: int = 0
var last_params ## DungeonGenParams


func set_phase(next: RunPhase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func reset_for_new_run() -> void:
	phase = RunPhase.PLAYING
	run_index += 1
	phase_changed.emit(phase)


func store_params(params, resolved_seed: int) -> void:
	if params != null and params.has_method("duplicate_params"):
		last_params = params.duplicate_params()
	else:
		last_params = null
	last_seed = resolved_seed
	if last_params != null:
		last_params.seed_value = resolved_seed
