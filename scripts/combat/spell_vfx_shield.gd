extends Node3D
## Lingering arc-shield dome around the caster.

const _Vfx := preload("res://scripts/combat/spell_vfx.gd")

var _life: float = 0.0
var _max_life: float = 1.0
var _dome: MeshInstance3D
var _rim: MeshInstance3D
var _light: OmniLight3D
var _closing: bool = false


func start(duration: float) -> void:
	_max_life = maxf(0.4, duration)
	_life = _max_life
	position = Vector3(0.0, 0.95, 0.0)
	_dome = _Vfx.make_sphere(1.15, Color(0.35, 0.65, 1.0, 0.32), 2.0)
	add_child(_dome)
	_rim = _Vfx.make_sphere(1.25, Color(0.6, 0.9, 1.0, 0.16), 2.8)
	add_child(_rim)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.75, 1.0)
	_light.light_energy = 2.4
	_light.omni_range = 4.5
	add_child(_light)
	scale = Vector3.ONE * 0.15
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE, 0.3)


func _process(delta: float) -> void:
	if _closing:
		return
	_life -= delta
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.04
	_dome.scale = Vector3.ONE * pulse
	var fade := clampf(_life / _max_life, 0.0, 1.0)
	_light.light_energy = 2.4 * fade
	var dome_mat := _dome.material_override as StandardMaterial3D
	if dome_mat != null:
		dome_mat.albedo_color.a = 0.32 * fade
		dome_mat.emission_energy_multiplier = 2.0 * fade
	var rim_mat := _rim.material_override as StandardMaterial3D
	if rim_mat != null:
		rim_mat.albedo_color.a = 0.16 * fade
	if _life <= 0.0:
		_closing = true
		var out := create_tween()
		out.tween_property(self, "scale", Vector3.ONE * 1.3, 0.18)
		out.tween_callback(queue_free)
