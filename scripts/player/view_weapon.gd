extends Node3D
## First-person view weapon + cast / swing animations.

const _Vfx := preload("res://scripts/combat/spell_vfx.gd")

var _grip: Node3D
var _blade: MeshInstance3D
var _fx_root: Node3D
var _fx_mesh: MeshInstance3D
var _fx_particles: GPUParticles3D
var _charge_light: OmniLight3D
var _rest_xform: Transform3D
var _tween: Tween
var _fx_mode: StringName = &""


func _ready() -> void:
	_build()
	_rest_xform = _grip.transform


func play_melee() -> void:
	_kill_tween()
	_grip.transform = _rest_xform
	_blade.visible = true
	_hide_fx()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(0.35, 0.55, -0.2)), Vector3(0.05, 0.04, 0.08)),
		0.06
	)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(-0.55, -0.9, 0.35)), Vector3(-0.12, -0.18, -0.35)),
		0.12
	)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_grip, "transform", _rest_xform, 0.16)
	_tween.finished.connect(_on_done)


func play_ability(ability_id: StringName) -> void:
	match ability_id:
		&"firebolt":
			_play_firebolt_cast()
		&"frost_nova":
			_play_frost_cast()
		&"arc_shield":
			_play_shield_cast()
		&"power_strike":
			_play_heavy()
		&"whirlwind":
			_play_spin()
		&"bash":
			_play_thrust(Color(0.95, 0.85, 0.55), 0.14)
		_:
			play_melee()


func _play_firebolt_cast() -> void:
	_kill_tween()
	_grip.transform = _rest_xform
	_blade.visible = true
	_show_element_fx(&"fire", Vector3(0.22, -0.12, -0.7), 0.04)
	_charge_light.visible = true
	_charge_light.light_color = Color(1.0, 0.4, 0.1)
	_charge_light.light_energy = 0.0
	_charge_light.position = _fx_root.position
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(-0.55, 0.35, -0.2)), Vector3(0.08, 0.12, 0.05)),
		0.14
	)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.32, 0.18)
	_tween.parallel().tween_property(_charge_light, "light_energy", 5.5, 0.18)
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(0.15, 0.0, 0.0)), Vector3(0.0, -0.08, -0.65)),
		0.1
	)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.02, 0.08)
	_tween.parallel().tween_property(_charge_light, "light_energy", 0.0, 0.12)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_grip, "transform", _rest_xform, 0.18)
	_tween.finished.connect(_on_done)


func _play_frost_cast() -> void:
	_kill_tween()
	_grip.transform = _rest_xform
	_blade.visible = true
	_show_element_fx(&"ice", Vector3(0.0, -0.05, -0.55), 0.03)
	_charge_light.visible = true
	_charge_light.light_color = Color(0.45, 0.8, 1.0)
	_charge_light.light_energy = 0.0
	_charge_light.position = _fx_root.position
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(-0.9, 0.0, 0.0)), Vector3(0.0, 0.22, 0.0)),
		0.14
	)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.26, 0.14)
	_tween.parallel().tween_property(_charge_light, "light_energy", 4.0, 0.14)
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(0.85, 0.0, 0.0)), Vector3(0.0, -0.35, -0.2)),
		0.12
	)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.75, 0.16)
	_tween.parallel().tween_property(_charge_light, "light_energy", 7.0, 0.1)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_grip, "transform", _rest_xform, 0.2)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.02, 0.22)
	_tween.parallel().tween_property(_charge_light, "light_energy", 0.0, 0.22)
	_tween.finished.connect(_on_done)


func _play_shield_cast() -> void:
	_kill_tween()
	_grip.transform = _rest_xform
	_blade.visible = true
	_show_simple_fx(Color(0.4, 0.7, 1.0), Vector3(0.0, 0.05, -0.4), 0.05)
	_charge_light.visible = true
	_charge_light.light_color = Color(0.4, 0.75, 1.0)
	_charge_light.light_energy = 0.0
	_charge_light.position = _fx_root.position
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(0.35, 0.6, -0.8)), Vector3(0.2, 0.15, 0.05)),
		0.16
	)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.55, 0.22)
	_tween.parallel().tween_property(_charge_light, "light_energy", 4.5, 0.2)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_grip, "transform", _rest_xform, 0.22)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.02, 0.28)
	_tween.parallel().tween_property(_charge_light, "light_energy", 0.0, 0.28)
	_tween.finished.connect(_on_done)


func _play_thrust(flash: Color, duration: float) -> void:
	_kill_tween()
	_grip.transform = _rest_xform
	_blade.visible = true
	_show_simple_fx(flash, Vector3(0.0, 0.12, -0.55), 0.08)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(-0.15, 0.0, 0.0)), Vector3(0.0, -0.05, -0.55)),
		duration * 0.45
	)
	_tween.set_ease(Tween.EASE_IN)
	_tween.tween_property(_grip, "transform", _rest_xform, duration * 0.55)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.02, duration * 0.55)
	_tween.finished.connect(_on_done)


func _play_heavy() -> void:
	_kill_tween()
	_grip.transform = _rest_xform
	_blade.visible = true
	_hide_fx()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(-1.1, 0.2, 0.1)), Vector3(0.05, 0.25, 0.05)),
		0.12
	)
	_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(
		_grip,
		"transform",
		_rest_xform * Transform3D(Basis.from_euler(Vector3(0.7, -0.15, 0.0)), Vector3(-0.05, -0.35, -0.4)),
		0.14
	)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_grip, "transform", _rest_xform, 0.18)
	_tween.finished.connect(_on_done)


func _play_spin() -> void:
	_kill_tween()
	_grip.transform = _rest_xform
	_blade.visible = true
	_show_simple_fx(Color(0.9, 0.9, 0.75), Vector3(0.0, 0.12, -0.55), 0.12)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_LINEAR)
	var mid := _rest_xform * Transform3D(Basis.from_euler(Vector3(0.2, TAU * 0.5, 0.3)), Vector3(0.0, -0.1, -0.2))
	var end_spin := _rest_xform * Transform3D(Basis.from_euler(Vector3(0.1, TAU, 0.0)), Vector3(0.0, -0.05, -0.15))
	_tween.tween_property(_grip, "transform", mid, 0.16)
	_tween.tween_property(_grip, "transform", end_spin, 0.16)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_grip, "transform", _rest_xform, 0.12)
	_tween.parallel().tween_property(_fx_root, "scale", Vector3.ONE * 0.02, 0.12)
	_tween.finished.connect(_on_done)


func _show_element_fx(mode: StringName, pos: Vector3, scale_start: float) -> void:
	_fx_mode = mode
	_fx_root.visible = true
	_fx_root.scale = Vector3.ONE * scale_start
	_fx_root.position = pos
	_fx_mesh.visible = true
	if mode == &"fire":
		_fx_mesh.mesh = _make_flame_quad_mesh(0.9, 1.2)
		_fx_mesh.material_override = _Vfx.make_shader_mat(
			_Vfx.SHADER_FIRE,
			{
				"noise_tex": _Vfx.load_tex(_Vfx.TEX_NOISE),
				"mask_tex": _Vfx.load_tex(_Vfx.TEX_EMBER),
				"intensity": 2.0,
				"dissolve": 0.38,
				"time_scale": 1.6,
			}
		)
		_fx_mesh.rotation_degrees = Vector3(0.0, 0.0, 0.0)
		_configure_hand_particles(true, Color(1.0, 0.5, 0.12, 1.0))
	else:
		_fx_mesh.mesh = _make_sphere_mesh(0.45)
		_fx_mesh.material_override = _Vfx.make_ice_mat(0.7)
		_configure_hand_particles(false, Color(0.7, 0.9, 1.0, 1.0))
	_fx_particles.emitting = true
	_fx_particles.restart()


func _show_simple_fx(color: Color, pos: Vector3, scale_start: float) -> void:
	_fx_mode = &"simple"
	_fx_root.visible = true
	_fx_root.scale = Vector3.ONE * scale_start
	_fx_root.position = pos
	_fx_mesh.visible = true
	_fx_mesh.mesh = _make_sphere_mesh(0.5)
	_fx_mesh.material_override = _Vfx.make_mat(Color(color.r, color.g, color.b, 0.55), 2.8)
	_fx_particles.emitting = false


func _configure_hand_particles(fire: bool, color: Color) -> void:
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 40.0 if fire else 70.0
	proc.initial_velocity_min = 0.2
	proc.initial_velocity_max = 0.9 if fire else 0.55
	proc.gravity = Vector3(0.0, 1.5 if fire else 0.2, 0.0)
	proc.scale_min = 0.25
	proc.scale_max = 0.7
	var grad := Gradient.new()
	if fire:
		grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 0.95, 0.55, 1.0),
			Color(1.0, 0.35, 0.05, 0.8),
			Color(0.2, 0.02, 0.0, 0.0),
		])
	else:
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(0.65, 0.88, 1.0, 0.7),
			Color(0.35, 0.55, 0.8, 0.0),
		])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	proc.color_ramp = ramp
	_fx_particles.process_material = proc
	var tex := _Vfx.load_tex(_Vfx.TEX_EMBER if fire else _Vfx.TEX_FLAKE)
	var draw := _Vfx.make_particle_draw_mat(tex, color, true)
	var quad := _fx_particles.draw_pass_1 as QuadMesh
	if quad != null:
		quad.material = draw


func _hide_fx() -> void:
	_fx_root.visible = false
	_fx_root.scale = Vector3.ONE * 0.02
	_fx_particles.emitting = false
	_charge_light.visible = false
	_charge_light.light_energy = 0.0
	_fx_mode = &""


func _build() -> void:
	_grip = Node3D.new()
	_grip.name = "Grip"
	_grip.position = Vector3(0.28, -0.28, -0.55)
	_grip.rotation_degrees = Vector3(12.0, -18.0, -8.0)
	add_child(_grip)

	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.05, 0.05, 0.28)
	handle.mesh = handle_mesh
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.22, 0.16, 0.12)
	handle.material_override = handle_mat
	handle.position = Vector3(0.0, 0.0, 0.08)
	_grip.add_child(handle)

	_blade = MeshInstance3D.new()
	_blade.name = "Blade"
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.04, 0.09, 0.55)
	_blade.mesh = blade_mesh
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.75, 0.78, 0.85)
	blade_mat.metallic = 0.7
	blade_mat.roughness = 0.35
	_blade.material_override = blade_mat
	_blade.position = Vector3(0.0, 0.02, -0.28)
	_grip.add_child(_blade)

	_fx_root = Node3D.new()
	_fx_root.name = "CastFx"
	_fx_root.visible = false
	_fx_root.scale = Vector3.ONE * 0.02
	add_child(_fx_root)

	_fx_mesh = MeshInstance3D.new()
	_fx_mesh.name = "CastMesh"
	_fx_mesh.mesh = _make_sphere_mesh(0.5)
	_fx_mesh.material_override = _Vfx.make_mat(Color(1.0, 1.0, 1.0, 0.45), 1.5)
	_fx_root.add_child(_fx_mesh)

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 35.0
	proc.initial_velocity_min = 0.15
	proc.initial_velocity_max = 0.6
	proc.gravity = Vector3(0.0, 1.0, 0.0)
	proc.scale_min = 0.3
	proc.scale_max = 0.7
	var draw := _Vfx.make_particle_draw_mat(
		_Vfx.load_tex(_Vfx.TEX_RADIAL),
		Color(1.0, 0.6, 0.2, 1.0),
		true
	)
	_fx_particles = _Vfx.make_gpu_particles(18, 0.35, proc, draw, 0.18, true)
	_fx_particles.name = "CastParticles"
	_fx_particles.emitting = false
	_fx_root.add_child(_fx_particles)

	_charge_light = OmniLight3D.new()
	_charge_light.name = "ChargeLight"
	_charge_light.light_energy = 0.0
	_charge_light.omni_range = 3.5
	_charge_light.visible = false
	add_child(_charge_light)


func _make_sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh


func _make_flame_quad_mesh(width: float, height: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, height)
	return mesh


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _on_done() -> void:
	_grip.transform = _rest_xform
	_hide_fx()
