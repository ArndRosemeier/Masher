extends RefCounted
## World-space spell visuals (projectiles, rings, domes) + shared VFX kit.

const _Firebolt := preload("res://scripts/combat/spell_vfx_firebolt.gd")
const _Frost := preload("res://scripts/combat/spell_vfx_frost.gd")
const _Shield := preload("res://scripts/combat/spell_vfx_shield.gd")

const TEX_RADIAL := "res://assets/vfx/soft_radial.png"
const TEX_EMBER := "res://assets/vfx/soft_ember.png"
const TEX_NOISE := "res://assets/vfx/soft_noise.png"
const TEX_FLAKE := "res://assets/vfx/soft_flake.png"

const SHADER_FIRE := "res://shaders/vfx/fire_scroll.gdshader"
const SHADER_ICE := "res://shaders/vfx/ice_crystal.gdshader"
const SHADER_FROST_GROUND := "res://shaders/vfx/frost_ground.gdshader"


static func firebolt(host: Node, from: Vector3, to: Vector3) -> void:
	assert(host != null and host.is_inside_tree(), "SpellVfx.firebolt: host must be in tree")
	var root := _fx_root(host)
	var runner = _Firebolt.new()
	runner.name = "FireboltVfx"
	root.add_child(runner)
	runner.start(from, to)


static func frost_nova(host: Node, origin: Vector3, radius: float) -> void:
	assert(host != null and host.is_inside_tree(), "SpellVfx.frost_nova: host must be in tree")
	var root := _fx_root(host)
	var runner = _Frost.new()
	runner.name = "FrostNovaVfx"
	root.add_child(runner)
	runner.start(origin, radius)


static func arc_shield(host: Node3D, duration: float) -> void:
	assert(host != null and host.is_inside_tree(), "SpellVfx.arc_shield: host must be in tree")
	var existing := host.get_node_or_null("ArcShieldVfx")
	if existing != null:
		existing.queue_free()
	var runner = _Shield.new()
	runner.name = "ArcShieldVfx"
	host.add_child(runner)
	runner.start(duration)


static func _fx_root(host: Node) -> Node:
	var tree := host.get_tree()
	if tree.current_scene != null:
		return tree.current_scene
	return host


static func load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var loaded := load(path) as Texture2D
		if loaded != null:
			return loaded
	## Fallback before Godot has imported the PNG (or if .import is stale).
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path(path))
	assert(err == OK, "SpellVfx: failed to load texture %s (err %d)" % [path, err])
	return ImageTexture.create_from_image(img)


static func load_shader(path: String) -> Shader:
	var sh := load(path) as Shader
	assert(sh != null, "SpellVfx: missing shader %s" % path)
	return sh


static func make_mat(color: Color, emission: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = emission
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func make_shader_mat(shader_path: String, params: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load_shader(shader_path)
	for key in params:
		mat.set_shader_parameter(String(key), params[key])
	return mat


static func make_particle_draw_mat(texture: Texture2D, color: Color, additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.albedo_texture = texture
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 2.2 if additive else 1.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat


static func make_omni(color: Color, energy: float, range_m: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false
	return light


static func flicker_energy(base: float, time_sec: float, amount: float = 0.22) -> float:
	var a := sin(time_sec * 31.7)
	var b := sin(time_sec * 47.3 + 1.7)
	var c := sin(time_sec * 13.1 + 0.4)
	return base * (1.0 + (a * 0.45 + b * 0.35 + c * 0.2) * amount)


static func make_gpu_particles(
	amount: int,
	lifetime: float,
	process: ParticleProcessMaterial,
	draw_mat: Material,
	quad_size: float = 0.35,
	local_coords: bool = true
) -> GPUParticles3D:
	assert(process != null, "SpellVfx.make_gpu_particles: null process material")
	assert(draw_mat != null, "SpellVfx.make_gpu_particles: null draw material")
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 0.0
	particles.randomness = 0.35
	particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	particles.local_coords = local_coords
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	return particles


static func make_sphere(radius: float, color: Color, emission: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = make_mat(color, emission)
	return mi


static func make_box(size: Vector3, color: Color, emission: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = make_mat(color, emission)
	return mi


static func make_flame_core(width: float, height: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, height)
	mi.mesh = mesh
	var mat := make_shader_mat(
		SHADER_FIRE,
		{
			"noise_tex": load_tex(TEX_NOISE),
			"mask_tex": load_tex(TEX_EMBER),
			"intensity": 2.15,
			"dissolve": 0.38,
			"time_scale": 1.45,
		}
	)
	mi.material_override = mat
	## Quad faces -Z by default; bolt looks down -Z via look_at.
	mi.position = Vector3(0.0, 0.0, -height * 0.15)
	return mi


static func make_ice_mat(opacity: float = 0.85) -> ShaderMaterial:
	return make_shader_mat(
		SHADER_ICE,
		{
			"noise_tex": load_tex(TEX_NOISE),
			"opacity": opacity,
			"emission_strength": 2.6,
			"sparkle_amount": 0.65,
		}
	)


static func make_frost_ground_mat() -> ShaderMaterial:
	return make_shader_mat(
		SHADER_FROST_GROUND,
		{
			"noise_tex": load_tex(TEX_NOISE),
			"mask_tex": load_tex(TEX_RADIAL),
			"progress": 0.05,
			"fade": 1.0,
			"intensity": 1.65,
		}
	)
