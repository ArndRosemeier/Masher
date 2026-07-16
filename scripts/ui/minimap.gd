class_name Minimap
extends Control
## Always-on corner map: current world floor only, fogged to explored cells.

const MapModelScript := preload("res://scripts/ui/dungeon_map_model.gd")

const PAD := 8.0
const TITLE_H := 18.0
const CELL_MIN := 4.0
const CELL_MAX := 10.0
const REVEAL_RADIUS := 5
const VISION_RADIUS := 4

var _model ## DungeonMapModel
var _exploration ## MapExploration
var _player_cell := Vector2i(-99999, -99999)
var _player_floor := -99999
var _mono: Font


func _init() -> void:
	_mono = _make_mono_font()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(200.0, 200.0)


func set_model(model) -> void:
	assert(model != null, "Minimap.set_model: null model")
	_model = model
	queue_redraw()


func set_exploration(exploration) -> void:
	assert(exploration != null, "Minimap.set_exploration: null exploration")
	_exploration = exploration
	queue_redraw()


func clear() -> void:
	_model = null
	_exploration = null
	_player_cell = Vector2i(-99999, -99999)
	_player_floor = -99999
	queue_redraw()


func sync_player(player: Node3D) -> void:
	## Reveal around the player on their current floor and redraw.
	if _model == null or _exploration == null or player == null:
		return
	var cell: Vector2i = MapModelScript.player_world_cell(player, _model.cell_size)
	var floor_i: int = MapModelScript.player_world_floor(player, _model.level_height)
	_player_cell = cell
	_player_floor = floor_i
	var layer = _model.floors.get(floor_i)
	if layer != null:
		_exploration.reveal_around(floor_i, cell, REVEAL_RADIUS, layer)
	queue_redraw()


func _make_mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	return font


func _draw() -> void:
	if _mono == null:
		_mono = _make_mono_font()
	var bg := Color(0.05, 0.06, 0.08, 0.82)
	var border := Color(0.45, 0.55, 0.4, 0.85)
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.5)

	var title := "Map"
	if _player_floor != -99999:
		title = "Floor %+d" % _player_floor
	draw_string(
		_mono,
		Vector2(PAD, PAD + 12.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(0.88, 0.84, 0.68)
	)

	if _model == null or _exploration == null:
		_draw_centered("—")
		return

	var layer = _model.floors.get(_player_floor)
	if layer == null:
		_draw_centered("void")
		return
	if _exploration.explored_count(_player_floor) == 0:
		_draw_centered("unexplored")
		return

	var bounds: Rect2i = _exploration.explored_bounds(_player_floor)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_draw_centered("unexplored")
		return

	var grid_origin := Vector2(PAD, PAD + TITLE_H)
	var avail := size - grid_origin - Vector2(PAD, PAD)
	if avail.x < 8.0 or avail.y < 8.0:
		return

	var cell_w := clampf(avail.x / float(bounds.size.x), CELL_MIN, CELL_MAX)
	var cell_h := clampf(avail.y / float(bounds.size.y), CELL_MIN, CELL_MAX)
	var cell := minf(cell_w, cell_h)
	var grid_w := float(bounds.size.x) * cell
	var grid_h := float(bounds.size.y) * cell
	var offset := grid_origin + Vector2((avail.x - grid_w) * 0.5, (avail.y - grid_h) * 0.5)

	for z in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var key := Vector2i(x, z)
			if not _exploration.is_explored(_player_floor, key):
				continue
			if not layer.has_cell(key):
				continue
			var ch: String = layer.get_char(key)
			var in_vision := _chebyshev(key, _player_cell) <= VISION_RADIUS
			var is_player := key == _player_cell
			var col := _cell_color(ch, is_player, in_vision)
			var rect := Rect2(
				offset + Vector2(float(x - bounds.position.x) * cell, float(z - bounds.position.y) * cell),
				Vector2(cell - 0.5, cell - 0.5)
			)
			draw_rect(rect, col, true)

	## Player pip on top even if the cell was already tinted.
	if (
		_player_cell.x >= bounds.position.x
		and _player_cell.x < bounds.position.x + bounds.size.x
		and _player_cell.y >= bounds.position.y
		and _player_cell.y < bounds.position.y + bounds.size.y
	):
		var pip := offset + Vector2(
			float(_player_cell.x - bounds.position.x) * cell + cell * 0.5,
			float(_player_cell.y - bounds.position.y) * cell + cell * 0.5
		)
		var r := maxf(cell * 0.35, 2.0)
		draw_circle(pip, r, Color(1.0, 0.88, 0.25))
		draw_circle(pip, r, Color(0.15, 0.12, 0.05), false, 1.0)


func _draw_centered(msg: String) -> void:
	var fs := 12
	var tw := _mono.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2((size.x - tw.x) * 0.5, (size.y + TITLE_H) * 0.5)
	draw_string(_mono, pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.55, 0.58, 0.52))


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _cell_color(ch: String, is_player: bool, in_vision: bool) -> Color:
	if is_player:
		return Color(1.0, 0.85, 0.25)
	var base: Color
	match ch:
		"#":
			base = Color(0.42, 0.45, 0.48)
		"S":
			base = Color(0.35, 0.78, 0.9)
		"D":
			base = Color(0.9, 0.5, 0.3)
		"^":
			base = Color(0.65, 0.4, 0.9)
		"P", "E", "M":
			base = Color(0.9, 0.7, 0.35)
		"+":
			base = Color(0.9, 0.78, 0.3)
		".":
			base = Color(0.4, 0.48, 0.38)
		" ":
			base = Color(0.12, 0.13, 0.15)
		_:
			base = Color(0.55, 0.58, 0.52)
	if not in_vision:
		return Color(base.r * 0.45, base.g * 0.45, base.b * 0.45, 0.85)
	return base
