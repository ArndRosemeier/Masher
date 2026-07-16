extends Node3D
## Frost nova: ground frost disc, cold mist, crystal shards, sparkles, cool light.

const _Vfx := preload("res://scripts/combat/spell_vfx.gd")


func start(origin: Vector3, radius: float) -> void:
	var center := origin + Vector3(0.0, 0.04, 0.0)
	var r := maxf(radius, 1.0)

	var ground := MeshInstance3D.new()
	var ground_mesh := QuadMesh.new()
	ground_mesh.size = Vector2(r * 2.2, r * 2.2)
	ground.mesh = ground_mesh
	ground.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var ground_mat := _Vfx.make_frost_ground_mat()
	ground.material_override = ground_mat
	add_child(ground)
	ground.global_position = center + Vector3(0.0, 0.02, 0.0)

	var mist := _make_mist(r)
	add_child(mist)
	mist.global_position = center + Vector3(0.0, 0.35, 0.0)
	mist.emitting = true
	mist.restart()

	var sparkles := _make_sparkles(r)
	add_child(sparkles)
	sparkles.global_position = center + Vector3(0.0, 0.5, 0.0)
	sparkles.emitting = true
	sparkles.restart()

	var light := _Vfx.make_omni(Color(0.5, 0.82, 1.0), 7.5, r * 2.6)
	add_child(light)
	light.global_position = center + Vector3(0.0, 1.0, 0.0)

	var shards: Array[MeshInstance3D] = []
	var shard_count := 14
	for i in shard_count:
		var ang := TAU * float(i) / float(shard_count) + randf_range(-0.12, 0.12)
		var dist := r * randf_range(0.35, 0.95)
		var shard := _make_shard()
		add_child(shard)
		var base := center + Vector3(cos(ang) * 0.2, 0.02, sin(ang) * 0.2)
		shard.global_position = base
		shard.scale = Vector3(0.05, 0.05, 0.05)
		shard.rotation_degrees = Vector3(
			randf_range(-18.0, 18.0),
			rad_to_deg(ang) + randf_range(-25.0, 25.0),
			randf_range(-12.0, 12.0)
		)
		shards.append(shard)
		shard.set_meta("target_pos", center + Vector3(cos(ang) * dist, randf_range(0.15, 0.55), sin(ang) * dist))
		shard.set_meta("target_scale", Vector3(
			randf_range(0.7, 1.25),
			randf_range(1.1, 1.9),
			randf_range(0.7, 1.25)
		))

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_frost_progress.bind(ground_mat), 0.05, 1.05, 0.36)
	tween.tween_property(light, "light_energy", 0.0, 0.85)
	for shard in shards:
		var tip: Vector3 = shard.get_meta("target_pos")
		var scl: Vector3 = shard.get_meta("target_scale")
		tween.tween_property(shard, "global_position", tip, 0.32)
		tween.tween_property(shard, "scale", scl, 0.22)
		tween.tween_property(shard, "rotation_degrees:y", shard.rotation_degrees.y + randf_range(-40.0, 40.0), 0.4)

	tween.set_parallel(false)
	tween.tween_interval(0.12)
	tween.set_parallel(true)
	tween.tween_method(_set_frost_fade.bind(ground_mat), 1.0, 0.0, 0.45)
	for shard in shards:
		_fade_ice_shard(tween, shard, 0.4)
	tween.set_parallel(false)
	tween.tween_interval(0.2)
	tween.tween_callback(func() -> void:
		mist.emitting = false
		sparkles.emitting = false
	)
	tween.tween_interval(0.35)
	tween.tween_callback(queue_free)


func _set_frost_progress(mat: ShaderMaterial, value: float) -> void:
	mat.set_shader_parameter("progress", value)


func _set_frost_fade(mat: ShaderMaterial, value: float) -> void:
	mat.set_shader_parameter("fade", value)


func _fade_ice_shard(tween: Tween, shard: MeshInstance3D, duration: float) -> void:
	var mat := shard.material_override as ShaderMaterial
	if mat == null:
		return
	mat = mat.duplicate() as ShaderMaterial
	shard.material_override = mat
	var start_opacity := float(mat.get_shader_parameter("opacity"))
	tween.tween_method(_set_ice_opacity.bind(mat), start_opacity, 0.0, duration)
	tween.tween_property(shard, "scale", shard.scale * Vector3(1.05, 0.35, 1.05), duration)


func _set_ice_opacity(mat: ShaderMaterial, value: float) -> void:
	mat.set_shader_parameter("opacity", value)


func _make_shard() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	## Pointy crystal: tapered box via prism-ish proportions.
	var mesh := PrismMesh.new()
	mesh.size = Vector3(
		randf_range(0.12, 0.22),
		randf_range(0.45, 0.85),
		randf_range(0.12, 0.22)
	)
	mi.mesh = mesh
	mi.material_override = _Vfx.make_ice_mat(0.88)
	return mi


func _make_mist(radius: float) -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.25
	proc.direction = Vector3(0.0, 0.35, 0.0)
	proc.spread = 180.0
	proc.initial_velocity_min = radius * 2.0
	proc.initial_velocity_max = radius * 3.4
	proc.gravity = Vector3(0.0, 0.85, 0.0)
	proc.damping_min = 2.4
	proc.damping_max = 4.5
	proc.scale_min = 0.75
	proc.scale_max = 1.7
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(0.75, 0.92, 1.0, 0.75),
		Color(0.45, 0.75, 1.0, 0.4),
		Color(0.3, 0.5, 0.7, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp

	var draw := _Vfx.make_particle_draw_mat(
		_Vfx.load_tex(_Vfx.TEX_RADIAL),
		Color(0.65, 0.88, 1.0, 0.85),
		false
	)
	var particles := _Vfx.make_gpu_particles(48, 0.65, proc, draw, 0.55, false)
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.visibility_aabb = AABB(Vector3(-radius * 2.5, -2, -radius * 2.5), Vector3(radius * 5.0, 6, radius * 5.0))
	return particles


func _make_sparkles(radius: float) -> GPUParticles3D:
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = radius * 0.7
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 180.0
	proc.initial_velocity_min = 0.4
	proc.initial_velocity_max = 2.2
	proc.gravity = Vector3(0.0, -0.4, 0.0)
	proc.scale_min = 0.2
	proc.scale_max = 0.55
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.7, 0.9, 1.0, 0.8),
		Color(0.4, 0.7, 1.0, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp

	var draw := _Vfx.make_particle_draw_mat(
		_Vfx.load_tex(_Vfx.TEX_FLAKE),
		Color(0.85, 0.95, 1.0, 1.0),
		true
	)
	var particles := _Vfx.make_gpu_particles(40, 0.55, proc, draw, 0.2, false)
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.visibility_aabb = AABB(Vector3(-radius * 2.0, -2, -radius * 2.0), Vector3(radius * 4.0, 6, radius * 4.0))
	return particles
