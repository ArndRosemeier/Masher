class_name RunManager
extends Node
## Owns create-UI → generate → spawn → death back to create.

const _EnemyDef := preload("res://scripts/enemies/enemy_def.gd")
const _Abilities := preload("res://scripts/progression/ability_catalog.gd")

@export var player_scene: PackedScene
@export var enemy_scene: PackedScene

@onready var world_root: Node3D = $"../World"
@onready var entities: Node3D = $"../Entities"
@onready var hud: CanvasLayer = $"../HUD"

var _create_ui: CanvasLayer
var _dungeon: Node3D
var _player: Node
var _pending_params: DungeonGenParams
var _spawn_rng := RandomNumberGenerator.new()


func _ready() -> void:
	if get_script() == null:
		const Loud := preload("res://scripts/core/loud_error.gd")
		Loud.fatal("Boot", "RunManager script failed to attach", get_tree())
		return
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
	if hud.has_method("clear_dungeon_map"):
		hud.clear_dungeon_map()
	GameState.reset_for_new_run()
	_create_ui.hide_create()

	if use_fixed_poc:
		var source := FixedLevelSource.new()
		_dungeon = source.build_dungeon()
		GameState.store_params(null, 0)
		_spawn_rng.seed = 1
		world_root.add_child(_dungeon)
		DungeonGenValidator.validate_or_assert(_dungeon, "FixedPOC")
		_finish_spawn(true)
		return

	assert(params != null, "Generated run requires DungeonGenParams")
	var gen := HybridDungeonGenerator.new(params)
	_dungeon = gen.build_dungeon()
	GameState.store_params(params, gen.resolved_seed())
	_spawn_rng.seed = gen.resolved_seed()
	world_root.add_child(_dungeon)
	DungeonGenValidator.validate_or_assert(_dungeon, "HybridGen")
	_finish_spawn(false)


func _finish_spawn(fixed_poc: bool) -> void:
	_spawn_player()
	_spawn_enemies()
	AudioManager.start_ambient()
	if hud.has_method("bind_dungeon_map"):
		hud.bind_dungeon_map()
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
	_player = player_scene.instantiate()
	entities.add_child(_player)
	(_player as Node3D).global_position = spawn.global_position + Vector3(0.0, 0.1, 0.0)
	_player.connect("died", _on_player_died)
	_player.connect("health_changed", _on_player_health_changed)
	_player.connect("mana_changed", _on_player_mana_changed)
	_player.connect("stamina_changed", _on_player_stamina_changed)
	_player.connect("interact_hint_changed", _on_interact_hint_changed)
	_player.connect("toast_message", _on_toast)
	var inv: Node = _player.get_node("Inventory")
	var prog: Node = _player.get_node("Progression")
	var hp: Node = _player.get_node("Health")
	var mp: Node = _player.get_node("Mana")
	var sp: Node = _player.get_node("Stamina")
	inv.connect("changed", _on_inventory_changed)
	prog.connect("ranks_changed", _on_hotbar_changed)
	prog.connect("hotbar_changed", _on_hotbar_changed)
	_on_player_health_changed(int(hp.get("current")), int(hp.get("max_health")))
	_on_player_mana_changed(float(mp.get("current")), float(mp.get("max_value")))
	_on_player_stamina_changed(float(sp.get("current")), float(sp.get("max_value")))
	_on_inventory_changed()
	_on_hotbar_changed()


func _spawn_enemies() -> void:
	var markers := _markers_in_dungeon(ModuleContract.GROUP_ENEMY_SPAWN)
	for marker in markers:
		var enemy: Node3D = enemy_scene.instantiate()
		entities.add_child(enemy)
		enemy.global_position = marker.global_position + Vector3(0.0, 0.1, 0.0)
		enemy.call("apply_def", _EnemyDef.pick_random(_spawn_rng))


func _on_player_health_changed(current: int, maximum: int) -> void:
	if hud.has_method("set_health"):
		hud.set_health(current, maximum)


func _on_player_mana_changed(current: float, maximum: float) -> void:
	if hud.has_method("set_mana"):
		hud.set_mana(current, maximum)


func _on_player_stamina_changed(current: float, maximum: float) -> void:
	if hud.has_method("set_stamina"):
		hud.set_stamina(current, maximum)


func _on_interact_hint_changed(text: String) -> void:
	if hud.has_method("set_interact_hint"):
		hud.set_interact_hint(text)


func _on_toast(text: String) -> void:
	if hud.has_method("show_toast"):
		hud.show_toast(text)


func _on_inventory_changed() -> void:
	if _player == null or not hud.has_method("set_inventory"):
		return
	var inv: Node = _player.get_node("Inventory")
	hud.set_inventory(
		inv.call("stacks"),
		int(inv.get("selected_index")),
		bool(_player.get("inventory_open"))
	)


func _on_hotbar_changed() -> void:
	if _player == null or not hud.has_method("set_hotbar"):
		return
	var prog: Node = _player.get_node("Progression")
	var hotbar: Array = prog.get("hotbar")
	var labels: Array[String] = []
	for i in hotbar.size():
		var id: StringName = hotbar[i]
		if id == &"":
			labels.append("%d: —" % (i + 1))
			continue
		var def = _Abilities.by_id(id)
		var rank: int = int(prog.call("rank_of", id))
		var label_name: String = def.display_name if def != null else String(id)
		labels.append("%d: %s %s" % [i + 1, label_name, _roman(rank)])
	hud.set_hotbar(labels)


func _roman(n: int) -> String:
	match n:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
		5:
			return "V"
	return str(n)


func _on_player_died() -> void:
	GameState.set_phase(GameState.RunPhase.DEAD)
	if _player != null and _player.has_method("set_input_enabled"):
		_player.call("set_input_enabled", false)
	if hud.has_method("show_dead"):
		hud.show_dead()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
