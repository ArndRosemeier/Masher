extends CanvasLayer
## Runtime HUD. Map stack is preloaded so F1 does not depend on a stale global-class cache.

const MapModelScript := preload("res://scripts/ui/dungeon_map_model.gd")
const MapCanvasScript := preload("res://scripts/ui/dungeon_map_canvas.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const ExplorationScript := preload("res://scripts/ui/map_exploration.gd")
const LoudErrorScript := preload("res://scripts/core/loud_error.gd")
const ItemCatalogScript := preload("res://scripts/progression/item_catalog.gd")

@onready var health_bar: ProgressBar = $Root/HealthBar
@onready var health_label: Label = $Root/HealthLabel
@onready var banner: Label = $Root/Banner
@onready var hint: Label = $Root/Hint
@onready var interact_hint: Label = $Root/InteractHint
@onready var root: Control = $Root

var mana_bar: ProgressBar
var mana_label: Label
var stamina_bar: ProgressBar
var stamina_label: Label
var hotbar_label: Label
var inventory_panel: PanelContainer
var inventory_label: Label
var toast_label: Label

var _map_modal: Control
var _map_title: Label
var _map_canvas: Control ## DungeonMapCanvas instance (Control to avoid class-cache parse breaks)
var _map_legend: Label
var _map_fit_btn: Button
var _map_open: bool = false
var _mono: Font
var _toast_timer: float = 0.0
var _minimap: Control ## Minimap instance
var _map_model ## DungeonMapModel cached for the active run
var _exploration ## MapExploration for fog of war


func _ready() -> void:
	show_playing()
	interact_hint.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process(true)
	_ensure_map_action()
	_mono = _make_mono_font()
	_build_vitals_ui()
	_build_minimap()
	if not _build_map_modal():
		LoudErrorScript.report("HUD", "Dungeon map modal failed to build — F1 will not work")
		return
	layer = 20
	print("HUD: dungeon map ready (F1)")


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and toast_label != null:
			toast_label.visible = false
	_sync_minimap()


func _build_vitals_ui() -> void:
	mana_bar = _make_bar(24.0, 84.0, Color(0.25, 0.45, 0.85))
	mana_label = _make_label(24.0, 112.0, "MP 100 / 100", Color(0.7, 0.8, 1.0))
	stamina_bar = _make_bar(24.0, 140.0, Color(0.35, 0.75, 0.4))
	stamina_label = _make_label(24.0, 168.0, "SP 100 / 100", Color(0.75, 0.9, 0.7))
	hotbar_label = _make_label(24.0, 200.0, "1: —  2: —  3: —  4: —", Color(0.85, 0.8, 0.65))
	hotbar_label.offset_right = 520.0

	toast_label = _make_label(0.0, 0.0, "", Color(0.95, 0.9, 0.7))
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 96.0
	toast_label.offset_bottom = 128.0
	toast_label.offset_left = -240.0
	toast_label.offset_right = 240.0
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.visible = false

	inventory_panel = PanelContainer.new()
	inventory_panel.visible = false
	inventory_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	inventory_panel.offset_left = -340.0
	inventory_panel.offset_top = -160.0
	inventory_panel.offset_right = -24.0
	inventory_panel.offset_bottom = 160.0
	root.add_child(inventory_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	inventory_panel.add_child(margin)
	inventory_label = Label.new()
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_label.add_theme_font_size_override("font_size", 14)
	inventory_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	margin.add_child(inventory_label)


func _make_bar(x: float, y: float, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.offset_left = x
	bar.offset_top = y
	bar.offset_right = x + 256.0
	bar.offset_bottom = y + 24.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	bar.add_theme_stylebox_override("fill", sb)
	root.add_child(bar)
	return bar


func _make_label(x: float, y: float, text: String, color: Color) -> Label:
	var label := Label.new()
	label.offset_left = x
	label.offset_top = y
	label.offset_right = x + 280.0
	label.offset_bottom = y + 24.0
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	root.add_child(label)
	return label


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


func set_mana(current: float, maximum: float) -> void:
	if mana_bar == null:
		return
	mana_bar.max_value = maximum
	mana_bar.value = current
	mana_label.text = "MP %d / %d" % [int(round(current)), int(round(maximum))]


func set_stamina(current: float, maximum: float) -> void:
	if stamina_bar == null:
		return
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_label.text = "SP %d / %d" % [int(round(current)), int(round(maximum))]


func set_hotbar(labels: Array) -> void:
	if hotbar_label == null:
		return
	var parts: PackedStringArray = []
	for label_variant in labels:
		parts.append(str(label_variant))
	hotbar_label.text = "   ".join(parts)


func set_inventory(stacks: Array, selected: int, open: bool) -> void:
	if inventory_panel == null:
		return
	inventory_panel.visible = open
	if not open:
		return
	var lines: PackedStringArray = ["Inventory (Enter Read · I close)", ""]
	if stacks.is_empty():
		lines.append("(empty)")
	else:
		for i in stacks.size():
			var stack: Dictionary = stacks[i]
			var item = ItemCatalogScript.by_id(stack["id"] as StringName)
			var item_name: String = item.display_name if item != null else String(stack["id"])
			var mark := ">" if i == selected else " "
			lines.append("%s %s x%d" % [mark, item_name, int(stack["count"])])
	inventory_label.text = "\n".join(lines)


func show_toast(text: String) -> void:
	if toast_label == null or text.is_empty():
		return
	toast_label.text = text
	toast_label.visible = true
	_toast_timer = 2.2


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
	_set_vitals_visible(false)
	clear_dungeon_map()
	if inventory_panel != null:
		inventory_panel.visible = false


func show_playing() -> void:
	banner.visible = false
	_set_vitals_visible(true)
	hint.text = "LMB melee · 1-4 abilities · I inventory · E interact · F1 map"
	hint.visible = true
	set_interact_hint("")
	if _minimap != null and _map_model != null:
		_minimap.visible = true


func bind_dungeon_map() -> void:
	## Call after the dungeon is in the tree so RoomModules are collectable.
	var modules: Array = MapModelScript.collect_modules(get_tree())
	assert(not modules.is_empty(), "HUD.bind_dungeon_map: no RoomModules in tree")
	_map_model = MapModelScript.build(modules)
	assert(_map_model != null, "HUD.bind_dungeon_map: build returned null")
	assert(not _map_model.floor_list.is_empty(), "HUD.bind_dungeon_map: no floors")
	_exploration = ExplorationScript.new()
	if _minimap != null:
		_minimap.call("set_model", _map_model)
		_minimap.call("set_exploration", _exploration)
		_minimap.visible = true
	_sync_minimap()


func clear_dungeon_map() -> void:
	_map_model = null
	_exploration = null
	if _minimap != null:
		_minimap.call("clear")
		_minimap.visible = false


func set_run_info(seed_value: int, module_count: int, fixed_poc: bool = false) -> void:
	if fixed_poc:
		hint.text = "Fixed POC · %d modules · LMB · 1-4 · I books · E · F1" % module_count
	else:
		hint.text = (
			"Seed %d · %d modules · LMB · 1-4 abilities · I inventory · E · F1"
			% [seed_value, module_count]
		)
	hint.visible = true


func show_dead() -> void:
	banner.text = "Dive ended"
	banner.visible = true
	hint.text = "Press R for a new run"
	hint.visible = true
	set_interact_hint("")
	if inventory_panel != null:
		inventory_panel.visible = false


func show_won() -> void:
	## Kept for API compatibility; win condition removed for now.
	banner.text = "Dive ended"
	banner.visible = true
	hint.text = "Press R for a new run"
	hint.visible = true
	set_interact_hint("")


func _set_vitals_visible(visible: bool) -> void:
	health_bar.visible = visible
	health_label.visible = visible
	if mana_bar != null:
		mana_bar.visible = visible
		mana_label.visible = visible
		stamina_bar.visible = visible
		stamina_label.visible = visible
		hotbar_label.visible = visible
	if _minimap != null:
		_minimap.visible = visible and _map_model != null


func _build_minimap() -> void:
	_minimap = MinimapScript.new() as Control
	assert(_minimap != null, "HUD: MinimapScript.new() returned null")
	_minimap.name = "Minimap"
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -236.0
	_minimap.offset_top = -236.0
	_minimap.offset_right = -24.0
	_minimap.offset_bottom = -24.0
	_minimap.visible = false
	root.add_child(_minimap)


func _sync_minimap() -> void:
	if _minimap == null or not _minimap.visible or _map_model == null or _exploration == null:
		return
	if GameState.phase != GameState.RunPhase.PLAYING:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	_minimap.call("sync_player", player)


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
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method("set_input_enabled"):
		player.call("set_input_enabled", enabled)


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
