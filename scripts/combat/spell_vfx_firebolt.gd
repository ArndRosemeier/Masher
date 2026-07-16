extends Node3D
## Traveling stylized firebolt: flame core, ember trail, smoke, flicker light, impact.

const _Vfx := preload("res://scripts/combat/spell_vfx.gd")

var _from: Vector3
var _to: Vector3
var _t: float = 0.0
var _duration: float = 0.25
var _core: MeshInstance3D
var _core_side: MeshInstance3D
var _embers: GPUParticles3D
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _base_energy: float = 5.5
var _alive: bool = true


func start(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	var dist := from.distance_to(to)
	_duration = clampf(dist / 26.0, 0.14, 0.5)
	global_position = from

	_core = _Vfx.make_flame_core(0.55, 0.95)
	add_child(_core)
	_core_side = _Vfx.make_flame_core(0.45, 0.85)
	_core_side.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	add_child(_core_side)

	_embers = _make_ember_trail()
	add_child(_embers)
	_embers.emitting = true

	_smoke = _make_smoke_trail()
	add_child(_smoke)
	_smoke.emitting = true

	_light = _Vfx.make_omni(Color(1.0, 0.42, 0.1), _base_energy, 7.5)
	add_child(_light)

	if dist > 0.05:
		look_at(to, Vector3.UP)


func _process(delta: float) -> void:
	if not _alive:
		return
	_t += delta / _duration
	var u := clampf(_t, 0.0, 1.0)
	var eased := u * u
	global_position = _from.lerp(_to, eased)

	var pulse := 0.85 + sin(Time.get_ticks_msec() * 0.045) * 0.12
	_core.scale = Vector3(pulse, 1.0, 1.0) * lerpf(0.75, 1.25, u)
	_core_side.scale = Vector3(pulse * 0.9, 0.95, 1.0) * lerpf(0.7, 1.15, u)
	_light.light_energy = _Vfx.flicker_energy(_base_energy * lerpf(0.85, 1.35, u), Time.get_ticks_msec() * 0.001)

	if u >= 1.0:
		_alive = false
		_embers.emitting = false
		_smoke.emitting = false
		_impact()
		queue_free()


func _make_ember_trail() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.35, 1.0)
	proc.spread = 28.0
	proc.initial_velocity_min = 0.4
	proc.initial_velocity_max = 1.6
	proc.gravity = Vector3(0.0, 2.2, 0.0)
	proc.damping_min = 1.0
	proc.damping_max = 2.5
	proc.scale_min = 0.35
	proc.scale_max = 0.85
	proc.color = Color(1.0, 0.55, 0.12, 1.0)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.55, 1.0),
		Color(1.0, 0.35, 0.05, 0.85),
		Color(0.2, 0.02, 0.0, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp

	var draw := _Vfx.make_particle_draw_mat(
		_Vfx.load_tex(_Vfx.TEX_EMBER),
		Color(1.0, 0.55, 0.15, 1.0),
		true
	)
	var particles := _Vfx.make_gpu_particles(36, 0.32, proc, draw, 0.28, true)
	particles.position = Vector3(0.0, 0.0, 0.25)
	particles.amount_ratio = 1.0
	return particles


func _make_smoke_trail() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.6, 1.0)
	proc.spread = 40.0
	proc.initial_velocity_min = 0.15
	proc.initial_velocity_max = 0.7
	proc.gravity = Vector3(0.0, 1.4, 0.0)
	proc.damping_min = 0.4
	proc.damping_max = 1.2
	proc.scale_min = 0.6
	proc.scale_max = 1.4
	proc.color = Color(0.15, 0.05, 0.02, 0.55)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([
		Color(0.35, 0.12, 0.04, 0.4),
		Color(0.12, 0.05, 0.03, 0.25),
		Color(0.02, 0.01, 0.01, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp

	var draw := _Vfx.make_particle_draw_mat(
		_Vfx.load_tex(_Vfx.TEX_RADIAL),
		Color(0.25, 0.08, 0.03, 0.7),
		false
	)
	var particles := _Vfx.make_gpu_particles(22, 0.5, proc, draw, 0.42, true)
	particles.position = Vector3(0.0, 0.05, 0.35)
	return particles


func _impact() -> void:
	var parent := get_parent()
	assert(parent != null, "FireboltVfx._impact: missing parent")

	var flash := MeshInstance3D.new()
	var flash_mesh := QuadMesh.new()
	flash_mesh.size = Vector2(1.2, 1.2)
	flash.mesh = flash_mesh
	var flash_mat := _Vfx.make_particle_draw_mat(
		_Vfx.load_tex(_Vfx.TEX_RADIAL),
		Color(1.0, 0.7, 0.25, 1.0),
		true
	)
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash.material_override = flash_mat
	parent.add_child(flash)
	flash.global_position = _to

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.28
	ring.mesh = torus
	ring.material_override = _Vfx.make_mat(Color(1.0, 0.45, 0.08, 0.85), 5.0)
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.scale = Vector3.ONE * 0.2
	parent.add_child(ring)
	ring.global_position = _to

	var sparks := _make_impact_sparks()
	parent.add_child(sparks)
	sparks.global_position = _to
	sparks.emitting = true
	sparks.restart()

	var light := _Vfx.make_omni(Color(1.0, 0.4, 0.08), 11.0, 9.0)
	parent.add_child(light)
	light.global_position = _to

	var tween := parent.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.8, 0.18)
	tween.tween_property(ring, "scale", Vector3.ONE * 4.5, 0.28)
	tween.tween_property(light, "light_energy", 0.0, 0.45)
	var flash_c := flash_mat.albedo_color
	tween.tween_property(flash_mat, "albedo_color", Color(flash_c.r, flash_c.g, flash_c.b, 0.0), 0.22)
	tween.tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.22)
	var ring_mat := ring.material_override as StandardMaterial3D
	if ring_mat != null:
		tween.tween_property(ring_mat, "albedo_color", Color(1.0, 0.3, 0.05, 0.0), 0.3)
		tween.tween_property(ring_mat, "emission_energy_multiplier", 0.0, 0.3)
	tween.set_parallel(false)
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void:
		flash.queue_free()
		ring.queue_free()
		light.queue_free()
		sparks.queue_free()
	)


func _make_impact_sparks() -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.15
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 180.0
	proc.initial_velocity_min = 2.5
	proc.initial_velocity_max = 6.5
	proc.gravity = Vector3(0.0, -6.0, 0.0)
	proc.damping_min = 1.5
	proc.damping_max = 3.5
	proc.scale_min = 0.25
	proc.scale_max = 0.7
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.6, 1.0),
		Color(1.0, 0.4, 0.08, 0.9),
		Color(0.15, 0.02, 0.0, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp

	var draw := _Vfx.make_particle_draw_mat(
		_Vfx.load_tex(_Vfx.TEX_RADIAL),
		Color(1.0, 0.6, 0.2, 1.0),
		true
	)
	var particles := _Vfx.make_gpu_particles(36, 0.4, proc, draw, 0.22, false)
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	return particles
