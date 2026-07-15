class_name RunManager
extends Node
## Owns dungeon load, spawning, death/exit → restart on the same level mode.

enum LevelMode { FIXED, GENERATED }

@export var level_mode: LevelMode = LevelMode.FIXED
@export var generated_seed: int = 42
@export var player_scene: PackedScene
@export var enemy_scene: PackedScene

@onready var world_root: Node3D = $"../World"
@onready var entities: Node3D = $"../Entities"
@onready var hud: CanvasLayer = $"../HUD"

var _dungeon: Node3D
var _player: PlayerController
var _exit_area: Area3D


func _ready() -> void:
	if player_scene == null:
		player_scene = load("res://scenes/player/player.tscn") as PackedScene
	if enemy_scene == null:
		enemy_scene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	start_run()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_run"):
		if GameState.phase != GameState.RunPhase.PLAYING:
			AudioManager.play_ui()
			restart_run()


func start_run() -> void:
	_clear_world()
	GameState.set_phase(GameState.RunPhase.PLAYING)

	var source: LevelSource
	match level_mode:
		LevelMode.FIXED:
			source = FixedLevelSource.new()
			GameState.last_seed = 0
		LevelMode.GENERATED:
			source = RoomGraphGenerator.new(generated_seed, 6, 1)
			GameState.last_seed = generated_seed

	_dungeon = source.build_dungeon()
	world_root.add_child(_dungeon)

	_spawn_player()
	_spawn_enemies()
	_setup_exit()

	AudioManager.start_ambient()
	if hud.has_method("show_playing"):
		hud.show_playing()


func restart_run() -> void:
	GameState.reset_for_new_run()
	# Keep seed for generated mode; bump for variety if desired
	if level_mode == LevelMode.GENERATED and generated_seed != 0:
		generated_seed += 1
	start_run()


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
	_exit_area.collision_mask = 2 ## player layer
	_exit_area.monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.4
	shape.shape = sphere
	_exit_area.add_child(shape)

	# Visual cue
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


func _on_player_won() -> void:
	GameState.set_phase(GameState.RunPhase.WON)
	AudioManager.play_exit()
	if _player:
		_player.set_input_enabled(false)
	if hud.has_method("show_won"):
		hud.show_won()
