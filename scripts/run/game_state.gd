extends Node

enum RunPhase { PLAYING, DEAD, WON }

signal phase_changed(phase: RunPhase)

var phase: RunPhase = RunPhase.PLAYING
var run_index: int = 1
var last_seed: int = 0


func set_phase(next: RunPhase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func reset_for_new_run() -> void:
	phase = RunPhase.PLAYING
	run_index += 1
	phase_changed.emit(phase)
