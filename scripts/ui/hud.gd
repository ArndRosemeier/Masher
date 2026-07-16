extends CanvasLayer
## Runtime HUD. Map stack is preloaded so F1 does not depend on a stale global-class cache.

const MapModelScript := preload("res://scripts/ui/dungeon_map_model.gd")
const MapCanvasScript := preload("res://scripts/ui/dungeon_map_canvas.gd")
const LoudErrorScript := preload("res://scripts/core/loud_error.gd")

@onready var health_bar: ProgressBar = $Root/HealthBar
@onready var health_label: Label = $Root/HealthLabel
@onready var banner: Label = $Root/Banner
@onready var hint: Label = $Root/Hint
@onready var interact_hint: Label = $Root/InteractHint

var _map_modal: Control
var _map_title: Label
var _map_canvas: Control ## DungeonMapCanvas instance (Control to avoid class-cache parse breaks)
var _map_legend: Label
var _map_fit_btn: Button
var _map_open: bool = false
var _mono: Font


func _ready() -> void:
	show_playing()
	interact_hint.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_ensure_map_action()
	_mono = _make_mono_font()
	if not _build_map_modal():
		LoudErrorScript.report("HUD", "Dungeon map modal failed to build — F1 will not work")
		return
	layer = 20
	print("HUD: dungeon map ready (F1)")


func _ensure_map_action() -> void:
	## Runtime bind so F1 works even if project.godot action failed to load.
	if not InputMap.has_action("toggle_ascii_map"):
		InputMap.add_action("toggle_ascii_map")
	for existing in InputMap.action_get_events("toggle_ascii_map"):
		InputMap.action_erase_event("toggle_ascii_map", existing)
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.physical_keycode = KEY_F1
	InputMap.action_add_event("toggle_ascii_map", key)


func _is_toggle_map_pressed(event: InputEvent) -> bool:
	if event.is_action_pressed("toggle_ascii_map"):
		return true
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return (
		key.keycode == KEY_F1
		or key.physical_keycode == KEY_F1
		or key.key_label == KEY_F1
	)


func _input(event: InputEvent) -> void:
	if _is_toggle_map_pressed(event):
		toggle_ascii_map()
		get_viewport().set_input_as_handled()
		return
	if not _map_open:
		return
	if event.is_action_pressed("toggle_mouse") or event.is_action_pressed("ui_cancel"):
		_close_ascii_map()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_HOME or key.physical_keycode == KEY_HOME:
			_fit_map_canvas()
			get_viewport().set_input_as_handled()


func set_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "HP %d / %d" % [current, maximum]


func set_interact_hint(text: String) -> void:
	if text.is_empty():
		interact_hint.visible = false
		interact_hint.text = ""
	else:
		interact_hint.text = text
		interact_hint.visible = true


func show_menu() -> void:
	banner.visible = false
	hint.text = "Set harness size · Generate a multilayer run"
	hint.visible = true
	set_interact_hint("")
	health_bar.visible = false
	health_label.visible = false


func show_playing() -> void:
	banner.visible = false
	health_bar.visible = true
	health_label.visible = true
	hint.text = "Mouse look · LMB attack · Space jump · E doors · F1 map · Esc free cursor"
	hint.visible = true
	set_interact_hint("")


func set_run_info(seed_value: int, module_count: int, fixed_poc: bool = false) -> void:
	## Surfaced so a generated run is visibly distinct from Fixed POC.
	if fixed_poc:
		hint.text = "Fixed POC · %d modules · F1 map · Esc free cursor" % module_count
	else:
		hint.text = (
			"Seed %d · %d modules · Mouse look · LMB · Space · E · F1 map"
			% [seed_value, module_count]
		)
	hint.visible = true


func show_dead() -> void:
	banner.text = "You died"
	banner.visible = true
	hint.text = "Press R to return to create"
	hint.visible = true
	set_interact_hint("")


func show_won() -> void:
	banner.text = "Dungeon cleared"
	banner.visible = true
	hint.text = "Press R to return to create"
	hint.visible = true
	set_interact_hint("")


func toggle_ascii_map() -> void:
	if _map_open:
		_close_ascii_map()
	else:
		_open_ascii_map()


func _open_ascii_map() -> void:
	if _map_modal == null or _map_canvas == null:
		_fail_map("Map UI was not built (see earlier HUD error)")
		return

	var modules: Array = MapModelScript.collect_modules(get_tree())
	if modules.is_empty():
		_fail_map("No RoomModule specs found in the scene tree")
		return

	var model = MapModelScript.build(modules)
	if model == null:
		_fail_map("DungeonMapModel.build returned null")
		return
	if model.floor_list.is_empty():
		_fail_map("DungeonMapModel.build produced no floors from %d modules" % modules.size())
		return

	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var pcell: Vector2i = MapModelScript.player_world_cell(player, model.cell_size)
	var pfloor: int = MapModelScript.player_world_floor(player, model.level_height)

	_map_title.text = "Dungeon map   ·   %d floors   ·   wheel zoom · drag pan · Home fit · F1/Esc close" % model.floor_list.size()
	_map_legend.text = _legend_text(model)
	if not _map_canvas.has_method("set_model"):
		_fail_map("Map canvas missing set_model() — wrong script attached?")
		return
	_map_canvas.call("set_model", model, pcell, pfloor)

	_map_open = true
	_map_modal.visible = true
	_map_modal.move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_player_input(false)
	call_deferred("_fit_map_after_layout")
	print(
		"HUD: opened dungeon map floors=",
		model.floor_list,
		" modules=",
		modules.size(),
		" vertical_links=",
		model.vertical_links.size(),
		" door_links=",
		model.door_links.size()
	)


func _fail_map(message: String) -> void:
	banner.text = "Map error: %s" % message
	banner.visible = true
	LoudErrorScript.report("DungeonMap", message)


func _fit_map_after_layout() -> void:
	await get_tree().process_frame
	if _map_open:
		_fit_map_canvas()


func _fit_map_canvas() -> void:
	if _map_canvas != null and _map_canvas.has_method("fit_view"):
		_map_canvas.call("fit_view")


func _close_ascii_map() -> void:
	_map_open = false
	if _map_modal != null:
		_map_modal.visible = false
	_set_player_input(true)
	if GameState.phase == GameState.RunPhase.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_player_input(enabled: bool) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as PlayerController
	if player != null:
		player.set_input_enabled(enabled)


func _make_mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	return font


func _legend_text(model) -> String:
	var vlines: PackedStringArray = []
	for link in model.vertical_links:
		vlines.append(link.label)
	var doors := 0
	var paired_doors := 0
	for door in model.door_links:
		doors += 1
		if door.paired:
			paired_doors += 1
	var parts: PackedStringArray = [
		"# wall  . floor  (space) void  + door  S up-stair  D down-stair  ^ shaft  @ you",
		"curve overlay = vertical link between stacked floors (S^ / Dv)",
		"vertical links: %d   ·   door cells (+): %d (%d paired)" % [
			model.vertical_links.size(),
			doors,
			paired_doors / 2,
		],
	]
	if not vlines.is_empty():
		parts.append("  " + "  |  ".join(vlines))
	return "\n".join(parts)


func _build_map_modal() -> bool:
	_map_modal = Control.new()
	_map_modal.name = "MapModal"
	_map_modal.visible = false
	_map_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_map_modal)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.03, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_modal.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 28.0
	panel.offset_top = 28.0
	panel.offset_right = -28.0
	panel.offset_bottom = -28.0
	_map_modal.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	_map_title = Label.new()
	_map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_title.add_theme_font_size_override("font_size", 20)
	_map_title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	header.add_child(_map_title)

	_map_canvas = MapCanvasScript.new() as Control
	if _map_canvas == null:
		push_error("HUD: MapCanvasScript.new() returned null")
		return false
	_map_canvas.name = "DungeonMapCanvas"
	_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.custom_minimum_size = Vector2(200, 200)

	_map_fit_btn = Button.new()
	_map_fit_btn.text = "Fit (Home)"
	_map_fit_btn.pressed.connect(_fit_map_canvas)
	header.add_child(_map_fit_btn)

	vbox.add_child(_map_canvas)

	_map_legend = Label.new()
	_map_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_legend.add_theme_font_override("font", _mono)
	_map_legend.add_theme_font_size_override("font_size", 12)
	_map_legend.add_theme_color_override("font_color", Color(0.72, 0.75, 0.68))
	vbox.add_child(_map_legend)
	return true
