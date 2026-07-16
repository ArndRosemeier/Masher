extends CanvasLayer
## Boot / post-run creation screen: harness meters, presets, seed, Generate.

signal generate_requested(params: DungeonGenParams)
signal fixed_poc_requested

var _params: DungeonGenParams
var _width: SpinBox
var _depth: SpinBox
var _height: SpinBox
var _seed: SpinBox
var _summary: Label
var _updating: bool = false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_params = DungeonGenParams.from_preset(DungeonGenParams.Preset.SMALL)
	_params.seed_value = 0 ## 0 = randomize at generate time
	_build()
	_sync_from_params()
	visible = true


func show_create(params: DungeonGenParams = null) -> void:
	if params != null:
		_params = params.duplicate_params()
	visible = true
	_sync_from_params()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_create() -> void:
	visible = false


func current_params() -> DungeonGenParams:
	_read_into_params()
	return _params.duplicate_params()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.035, 0.045, 0.96)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 420)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var brand := Label.new()
	brand.text = "MASHER"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size", 42)
	brand.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	vbox.add_child(brand)

	var subtitle := Label.new()
	subtitle.text = "Create a multilayer dungeon"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.72, 0.68))
	vbox.add_child(subtitle)

	var preset_row := HBoxContainer.new()
	preset_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preset_row.add_theme_constant_override("separation", 8)
	vbox.add_child(preset_row)
	for preset in [
		DungeonGenParams.Preset.TINY,
		DungeonGenParams.Preset.SMALL,
		DungeonGenParams.Preset.MEDIUM,
		DungeonGenParams.Preset.LARGE,
		DungeonGenParams.Preset.HUGE,
	]:
		var btn := Button.new()
		btn.text = DungeonGenParams.preset_name(preset)
		btn.pressed.connect(_apply_preset.bind(preset as DungeonGenParams.Preset))
		preset_row.add_child(btn)

	var dims := GridContainer.new()
	dims.columns = 2
	dims.add_theme_constant_override("h_separation", 12)
	dims.add_theme_constant_override("v_separation", 8)
	vbox.add_child(dims)

	_width = _add_spin(dims, "Width (m)", 16, 256, 8)
	_depth = _add_spin(dims, "Depth (m)", 16, 256, 8)
	_height = _add_spin(dims, "Height (m)", 8, 64, 4)
	_seed = _add_spin(dims, "Seed (0 = random)", 0, 2147483647, 1)
	_seed.rounded = true

	_width.value_changed.connect(_on_dim_changed)
	_depth.value_changed.connect(_on_dim_changed)
	_height.value_changed.connect(_on_dim_changed)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_color_override("font_color", Color(0.78, 0.82, 0.72))
	vbox.add_child(_summary)

	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_theme_constant_override("separation", 10)
	vbox.add_child(seed_row)
	var rand_btn := Button.new()
	rand_btn.text = "Random seed"
	rand_btn.pressed.connect(_randomize_seed)
	seed_row.add_child(rand_btn)

	var gen_btn := Button.new()
	gen_btn.text = "Generate"
	gen_btn.custom_minimum_size = Vector2(0, 44)
	gen_btn.pressed.connect(_on_generate)
	vbox.add_child(gen_btn)

	var fixed_btn := Button.new()
	fixed_btn.text = "Fixed POC (dev)"
	fixed_btn.pressed.connect(func() -> void: fixed_poc_requested.emit())
	vbox.add_child(fixed_btn)


func _add_spin(grid: GridContainer, label: String, min_v: float, max_v: float, step: float) -> SpinBox:
	var lab := Label.new()
	lab.text = label
	grid.add_child(lab)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(spin)
	return spin


func _apply_preset(preset: DungeonGenParams.Preset) -> void:
	var seed_keep := int(_seed.value) if _seed != null else _params.seed_value
	_params = DungeonGenParams.from_preset(preset)
	_params.seed_value = seed_keep
	_sync_from_params()


func _randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed.value = rng.randi_range(1, 999999)


func _on_dim_changed(_v: float) -> void:
	if _updating:
		return
	_read_into_params()
	_summary.text = _params.summary_text()


func _sync_from_params() -> void:
	_updating = true
	_width.value = _params.width_m
	_depth.value = _params.depth_m
	_height.value = _params.height_m
	_seed.value = _params.seed_value
	_summary.text = _params.summary_text()
	_updating = false


func _read_into_params() -> void:
	_params.width_m = float(_width.value)
	_params.depth_m = float(_depth.value)
	_params.height_m = float(_height.value)
	_params.seed_value = int(_seed.value)
	_params.clamp_meters()


func _on_generate() -> void:
	_read_into_params()
	generate_requested.emit(_params.duplicate_params())
