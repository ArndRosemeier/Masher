class_name RunManager
extends Node
## Owns create-UI → generate → spawn → death/win back to create.

@export var player_scene: PackedScene
@export var enemy_scene: PackedScene

@onready var world_root: Node3D = $"../World"
@onready var entities: Node3D = $"../Entities"
@onready var hud: CanvasLayer = $"../HUD"

var _create_ui: CanvasLayer
var _dungeon: Node3D
var _player: PlayerController
var _exit_area: Area3D
var _pending_params: DungeonGenParams


func _ready() -> void:
	if player_scene == null:
		player_scene = load("res://scenes/player/player.tscn") as PackedScene
	if enemy_scene == null:
		enemy_scene = load("res://scenes/enemies/enemy.tscn") as PackedScene

	if not _boot_create_ui():
		return

	GameState.set_phase(GameState.RunPhase.MENU)
	if hud.has_method("show_menu"):
		hud.show_menu()
	_create_ui.call_deferred("show_create", GameState.last_params)


func _boot_create_ui() -> bool:
	## Script parse failures used to leave a naked CanvasLayer and an empty world.
	const UI_SCRIPT := "res://scripts/ui/create_run_ui.gd"
	const UI_SCENE := "res://scenes/ui/create_run.tscn"
	const Loud := preload("res://scripts/core/loud_error.gd")

	var script_res := load(UI_SCRIPT)
	if script_res == null:
		Loud.fatal(
			"Boot",
			"Failed to load %s (parse/compile error). Check the console for SCRIPT ERROR." % UI_SCRIPT,
			get_tree()
		)
		return false

	var packed := load(UI_SCENE) as PackedScene
	if packed == null:
		Loud.fatal("Boot", "Missing or unloadable scene: %s" % UI_SCENE, get_tree())
		return false

	_create_ui = packed.instantiate() as CanvasLayer
	if _create_ui == null:
		Loud.fatal("Boot", "create_run.tscn did not instantiate a CanvasLayer", get_tree())
		return false
	if _create_ui.get_script() == null:
		Loud.fatal(
			"Boot",
			"CreateRunUI has no script attached — %s likely failed to compile." % UI_SCRIPT,
			get_tree()
		)
		return false
	if not _create_ui.has_signal("generate_requested") or not _create_ui.has_signal("fixed_poc_requested"):
		Loud.fatal(
			"Boot",
			"CreateRunUI is missing required signals (script did not apply).",
			get_tree()
		)
		return false
	if not _create_ui.has_method("show_create"):
		Loud.fatal("Boot", "CreateRunUI missing show_create()", get_tree())
		return false

	## Deferred: Main is still finishing _ready children setup.
	get_parent().add_child.call_deferred(_create_ui)
	_create_ui.generate_requested.connect(_on_generate_requested)
	_create_ui.fixed_poc_requested.connect(_on_fixed_poc_requested)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("restart_run"):
		return
	if GameState.phase == GameState.RunPhase.DEAD or GameState.phase == GameState.RunPhase.WON:
		AudioManager.play_ui()
		_return_to_create()


func _on_generate_requested(params: DungeonGenParams) -> void:
	_pending_params = params
	begin_run(params, false)


func _on_fixed_poc_requested() -> void:
	begin_run(null, true)


func begin_run(params: DungeonGenParams, use_fixed_poc: bool) -> void:
	_clear_world()
	GameState.reset_for_new_run()
	_create_ui.hide_create()

	if use_fixed_poc:
		var source := FixedLevelSource.new()
		_dungeon = source.build_dungeon()
		GameState.store_params(null, 0)
		world_root.add_child(_dungeon)
		_finish_spawn(true)
		return

	assert(params != null, "Generated run requires DungeonGenParams")
	var gen := HybridDungeonGenerator.new(params)
	_dungeon = gen.build_dungeon()
	GameState.store_params(params, gen.resolved_seed())
	world_root.add_child(_dungeon)
	_finish_spawn(false)


func _finish_spawn(fixed_poc: bool) -> void:
	_spawn_player()
	_spawn_enemies()
	_setup_exit()
	AudioManager.start_ambient()
	if hud.has_method("show_playing"):
		hud.show_playing()
	if hud.has_method("set_run_info"):
		var module_n := 0
		if _dungeon != null:
			for node in get_tree().get_nodes_in_group(ModuleContract.GROUP_MODULE):
				if _dungeon.is_ancestor_of(node):
					module_n += 1
		hud.set_run_info(GameState.last_seed, module_n, fixed_poc)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _return_to_create() -> void:
	_clear_world()
	AudioManager.stop_ambient()
	GameState.set_phase(GameState.RunPhase.MENU)
	if hud.has_method("show_menu"):
		hud.show_menu()
	var p: DungeonGenParams = GameState.last_params
	if p == null and _pending_params != null:
		p = _pending_params
	_create_ui.show_create(p)


func _clear_world() -> void:
	for child in world_root.get_children():
		world_root.remove_child(child)
		child.free()
	for child in entities.get_children():
		entities.remove_child(child)
		child.free()
	_player = null
	_dungeon = null
	_exit_area = null
	Engine.time_scale = 1.0


func _markers_in_dungeon(group: StringName) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(group):
		if _dungeon != null and _dungeon.is_ancestor_of(node):
			result.append(node as Node3D)
	return result


func _spawn_player() -> void:
	var markers := _markers_in_dungeon(ModuleContract.GROUP_PLAYER_SPAWN)
	assert(markers.size() > 0, "Level missing PlayerSpawn marker")
	var spawn := markers[0]
	_player = player_scene.instantiate() as PlayerController
	entities.add_child(_player)
	_player.global_position = spawn.global_position + Vector3(0.0, 0.1, 0.0)
	_player.died.connect(_on_player_died)
	_player.health_changed.connect(_on_player_health_changed)
	_player.interact_hint_changed.connect(_on_interact_hint_changed)
	_on_player_health_changed(_player.health, _player.max_health)


func _spawn_enemies() -> void:
	var markers := _markers_in_dungeon(ModuleContract.GROUP_ENEMY_SPAWN)
	for marker in markers:
		var enemy := enemy_scene.instantiate() as EnemyController
		entities.add_child(enemy)
		enemy.global_position = marker.global_position + Vector3(0.0, 0.1, 0.0)


func _setup_exit() -> void:
	var exits := _markers_in_dungeon(ModuleContract.GROUP_EXIT)
	assert(exits.size() > 0, "Level missing Exit marker")
	var exit_marker := exits[0]

	_exit_area = Area3D.new()
	_exit_area.name = "ExitTrigger"
	_exit_area.collision_layer = 0
	_exit_area.collision_mask = 2
	_exit_area.monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.4
	shape.shape = sphere
	_exit_area.add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.35
	sphere_mesh.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.9, 0.55)
	mat.emission_energy_multiplier = 2.5
	mat.albedo_color = Color(0.3, 0.7, 0.4, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.mesh = sphere_mesh
	mesh.material_override = mat
	_exit_area.add_child(mesh)

	entities.add_child(_exit_area)
	_exit_area.global_position = exit_marker.global_position + Vector3(0.0, 1.0, 0.0)
	_exit_area.body_entered.connect(_on_exit_body_entered)


func _on_exit_body_entered(body: Node3D) -> void:
	if GameState.phase != GameState.RunPhase.PLAYING:
		return
	if body is PlayerController:
		_on_player_won()


func _on_player_health_changed(current: int, maximum: int) -> void:
	if hud.has_method("set_health"):
		hud.set_health(current, maximum)


func _on_interact_hint_changed(text: String) -> void:
	if hud.has_method("set_interact_hint"):
		hud.set_interact_hint(text)


func _on_player_died() -> void:
	GameState.set_phase(GameState.RunPhase.DEAD)
	if _player:
		_player.set_input_enabled(false)
	if hud.has_method("show_dead"):
		hud.show_dead()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_won() -> void:
	GameState.set_phase(GameState.RunPhase.WON)
	AudioManager.play_exit()
	if _player:
		_player.set_input_enabled(false)
	if hud.has_method("show_won"):
		hud.show_won()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
