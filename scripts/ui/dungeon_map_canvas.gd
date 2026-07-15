class_name DungeonMapCanvas
extends Control
## Pannable/zoomable exploded floor-stack view of a DungeonMapModel.
## Future editor: connect cell_clicked for selection/paint tools.

signal cell_clicked(floor_index: int, world_x: int, world_z: int)

const CHAR_W := 11.0
const CHAR_H := 16.0
const PANEL_PAD := 10.0
const PANEL_GAP := 48.0
const HEADER_H := 22.0
const MIN_ZOOM := 0.35
const MAX_ZOOM := 3.5

var _model: DungeonMapModel
var _player_cell := Vector2i(-99999, -99999)
var _player_floor := -99999
var _mono: Font

var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _drag_moved := false
var _drag_button := -1
var _drag_last := Vector2.ZERO

## floor_index -> panel top-left in content space (pre-transform)
var _panel_origins: Dictionary = {}
var _shared_min := Vector2i.ZERO
var _shared_max := Vector2i.ZERO
var _content_size := Vector2.ZERO


func _init() -> void:
	## Font must exist before any early redraw (set_model can run before _ready).
	_mono = _make_mono_font()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if _mono == null:
		_mono = _make_mono_font()
	focus_mode = Control.FOCUS_ALL


func set_model(model: DungeonMapModel, player_cell: Vector2i, player_floor: int) -> void:
	assert(model != null, "DungeonMapCanvas.set_model: model is null")
	if _mono == null:
		_mono = _make_mono_font()
	_model = model
	_player_cell = player_cell
	_player_floor = player_floor
	_recompute_layout()
	queue_redraw()


func fit_view() -> void:
	if _content_size.x <= 1.0 or _content_size.y <= 1.0:
		return
	var avail := size - Vector2(24.0, 24.0)
	if avail.x <= 1.0 or avail.y <= 1.0:
		return
	var zx := avail.x / _content_size.x
	var zy := avail.y / _content_size.y
	_zoom = clampf(minf(zx, zy), MIN_ZOOM, MAX_ZOOM)
	var scaled := _content_size * _zoom
	_pan = (size - scaled) * 0.5
	queue_redraw()


func _make_mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	return font


func _recompute_layout() -> void:
	_panel_origins.clear()
	_content_size = Vector2.ZERO
	if _model == null or _model.floor_list.is_empty():
		return

	_shared_min = Vector2i(999999, 999999)
	_shared_max = Vector2i(-999999, -999999)
	for fi in _model.floor_list:
		var layer: DungeonMapModel.FloorLayer = _model.floors[fi]
		_shared_min.x = mini(_shared_min.x, layer.min_x)
		_shared_min.y = mini(_shared_min.y, layer.min_z)
		_shared_max.x = maxi(_shared_max.x, layer.max_x)
		_shared_max.y = maxi(_shared_max.y, layer.max_z)

	var grid_w := float(_shared_max.x - _shared_min.x + 1) * CHAR_W
	var grid_h := float(_shared_max.y - _shared_min.y + 1) * CHAR_H
	var panel_w := grid_w + PANEL_PAD * 2.0
	var panel_h := HEADER_H + grid_h + PANEL_PAD * 2.0

	## Highest floor on top (lowest Y in content space).
	var y := 0.0
	var ordered: Array = _model.floor_list.duplicate()
	ordered.reverse()
	for fi_variant in ordered:
		var fi: int = int(fi_variant)
		_panel_origins[fi] = Vector2(0.0, y)
		y += panel_h + PANEL_GAP
	_content_size = Vector2(panel_w + 80.0, y - PANEL_GAP)


func _draw() -> void:
	if _mono == null:
		_mono = _make_mono_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09, 1.0), true)
	if _model == null or _model.floor_list.is_empty():
		_draw_empty()
		return

	draw_set_transform(_pan, 0.0, Vector2(_zoom, _zoom))

	var ordered: Array = _model.floor_list.duplicate()
	ordered.reverse()
	for fi in ordered:
		_draw_floor_panel(int(fi))

	## Doors are ASCII `+` on the grid (no overlay). Vertical links still span panels.
	_draw_vertical_links()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_empty() -> void:
	if _mono == null:
		_mono = _make_mono_font()
	var msg := "No dungeon map data"
	var fs := 18
	var tw := _mono.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_mono, (size - tw) * 0.5, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.65))


func _draw_floor_panel(floor_index: int) -> void:
	var layer: DungeonMapModel.FloorLayer = _model.floors[floor_index]
	var origin: Vector2 = _panel_origins[floor_index]
	var grid_w := float(_shared_max.x - _shared_min.x + 1) * CHAR_W
	var grid_h := float(_shared_max.y - _shared_min.y + 1) * CHAR_H
	var panel_w := grid_w + PANEL_PAD * 2.0
	var panel_h := HEADER_H + grid_h + PANEL_PAD * 2.0
	var rect := Rect2(origin, Vector2(panel_w, panel_h))

	var is_player_floor := floor_index == _player_floor
	var bg := Color(0.10, 0.12, 0.14, 0.95) if is_player_floor else Color(0.08, 0.09, 0.11, 0.88)
	var border := Color(0.55, 0.72, 0.42, 0.9) if is_player_floor else Color(0.28, 0.32, 0.36, 0.9)
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 2.0 if is_player_floor else 1.0)

	var title := "floor %+d" % floor_index
	if is_player_floor:
		title += "  ·  you are here"
	draw_string(
		_mono,
		origin + Vector2(PANEL_PAD, PANEL_PAD + 14.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.92, 0.86, 0.62) if is_player_floor else Color(0.7, 0.72, 0.68)
	)

	var grid_origin := origin + Vector2(PANEL_PAD, PANEL_PAD + HEADER_H)
	for z in range(_shared_min.y, _shared_max.y + 1):
		for x in range(_shared_min.x, _shared_max.x + 1):
			var key := Vector2i(x, z)
			var ch := " "
			if layer.has_cell(key):
				ch = layer.get_char(key)
			var is_player := is_player_floor and key == _player_cell
			if is_player:
				ch = "@"
			var col := _char_color(ch, is_player, is_player_floor and layer.has_cell(key))
			var pos := grid_origin + Vector2(
				float(x - _shared_min.x) * CHAR_W,
				float(z - _shared_min.y) * CHAR_H + CHAR_H - 3.0
			)
			draw_string(_mono, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _char_color(ch: String, is_player: bool, on_floor: bool) -> Color:
	if is_player:
		return Color(1.0, 0.85, 0.25)
	if not on_floor:
		return Color(0.18, 0.2, 0.22, 0.35)
	match ch:
		"#":
			return Color(0.55, 0.58, 0.62)
		"S":
			return Color(0.45, 0.85, 0.95)
		"D":
			return Color(0.95, 0.55, 0.35)
		"^":
			return Color(0.7, 0.45, 0.95)
		"P", "E", "M":
			return Color(0.95, 0.75, 0.4)
		"+":
			return Color(0.95, 0.82, 0.35)
		"X":
			return Color(0.65, 0.7, 0.55)
		".":
			return Color(0.45, 0.55, 0.42)
	return Color(0.75, 0.78, 0.72)


func _cell_center_content(floor_index: int, world_cell: Vector2i) -> Vector2:
	var origin: Vector2 = _panel_origins[floor_index]
	var grid_origin := origin + Vector2(PANEL_PAD, PANEL_PAD + HEADER_H)
	return grid_origin + Vector2(
		float(world_cell.x - _shared_min.x) * CHAR_W + CHAR_W * 0.5,
		float(world_cell.y - _shared_min.y) * CHAR_H + CHAR_H * 0.5
	)


func _draw_vertical_links() -> void:
	for link in _model.vertical_links:
		if link.world_cells.is_empty():
			continue
		if not _panel_origins.has(link.from_floor) or not _panel_origins.has(link.to_floor):
			continue
		var mid := link.world_cells[link.world_cells.size() / 2]
		var a := _cell_center_content(link.from_floor, mid)
		var b := _cell_center_content(link.to_floor, mid)
		var col := Color(0.35, 0.85, 0.95, 0.85) if link.kind == "up" else Color(0.95, 0.55, 0.35, 0.9)
		if not link.paired:
			col.a = 0.45
		var ctrl := Vector2((a.x + b.x) * 0.5 + 18.0, (a.y + b.y) * 0.5)
		_draw_bezier(a, ctrl, b, col, 2.5)
		var label_pos := ctrl + Vector2(6.0, -2.0)
		var short := "S^" if link.kind == "up" else "Dv"
		draw_string(_mono, label_pos, "%s %s" % [short, link.module_id], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_bezier(a: Vector2, ctrl: Vector2, b: Vector2, color: Color, width: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps := 16
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var u := 1.0 - t
		var p := u * u * a + 2.0 * u * t * ctrl + t * t * b
		pts.append(p)
	draw_polyline(pts, color, width, true)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.12)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.12)
			accept_event()
			return
		if (
			(mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE)
			and mb.pressed
		):
			_dragging = true
			_drag_moved = false
			_drag_button = mb.button_index
			_drag_last = mb.position
			accept_event()
			return
		if mb.button_index == _drag_button and not mb.pressed:
			if _dragging and not _drag_moved and mb.button_index == MOUSE_BUTTON_LEFT:
				_try_emit_cell_click(mb.position)
			_dragging = false
			_drag_button = -1
			accept_event()
			return

	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		var delta := mm.position - _drag_last
		if delta.length_squared() > 4.0:
			_drag_moved = true
		_pan += delta
		_drag_last = mm.position
		queue_redraw()
		accept_event()
		return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_HOME or key.physical_keycode == KEY_HOME:
			fit_view()
			accept_event()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := (screen_pos - _pan) / _zoom
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var after := (screen_pos - _pan) / _zoom
	_pan += (after - before) * _zoom
	queue_redraw()


func _try_emit_cell_click(screen_pos: Vector2) -> void:
	var content := (screen_pos - _pan) / _zoom
	var hit := _hit_test_cell(content)
	if hit.x != -99999:
		cell_clicked.emit(hit.z, hit.x, hit.y)


func _hit_test_cell(content_pos: Vector2) -> Vector3i:
	## Returns Vector3i(world_x, world_z, floor) or sentinel.
	if _model == null:
		return Vector3i(-99999, -99999, -99999)
	var ordered: Array = _model.floor_list.duplicate()
	ordered.reverse()
	for fi_variant in ordered:
		var fi: int = int(fi_variant)
		var origin: Vector2 = _panel_origins[fi]
		var grid_w := float(_shared_max.x - _shared_min.x + 1) * CHAR_W
		var grid_h := float(_shared_max.y - _shared_min.y + 1) * CHAR_H
		var grid_origin := origin + Vector2(PANEL_PAD, PANEL_PAD + HEADER_H)
		var local := content_pos - grid_origin
		if local.x < 0.0 or local.y < 0.0 or local.x >= grid_w or local.y >= grid_h:
			continue
		var wx := _shared_min.x + int(floor(local.x / CHAR_W))
		var wz := _shared_min.y + int(floor(local.y / CHAR_H))
		return Vector3i(wx, wz, fi)
	return Vector3i(-99999, -99999, -99999)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _model != null and not _model.floor_list.is_empty():
		## Keep view usable after modal layout settles.
		pass
