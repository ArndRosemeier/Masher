class_name RoomSpecParser
extends RefCounted
## Parses layered ASCII room text into RoomSpec. Errors are loud.

const META_KEYS := ["id", "cell", "layer_height", "open"]


static func parse_text(text: String, source_name: String = "room") -> RoomSpec:
	var spec := RoomSpec.new()
	spec.id = StringName(source_name)
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var i := 0
	var current_layer := -1
	var layer_rows: Array[String] = []

	while i < lines.size():
		var raw: String = lines[i]
		var line := raw.strip_edges()
		i += 1
		if line.is_empty():
			continue
		if line.begins_with("layer "):
			if current_layer >= 0:
				_commit_layer(spec, current_layer, layer_rows, source_name)
				layer_rows.clear()
			var parts := line.split(" ", false)
			assert(parts.size() >= 2, "%s: bad layer header '%s'" % [source_name, line])
			current_layer = int(parts[1])
			assert(
				current_layer == spec.layers.size(),
				"%s: layers must be contiguous from 0 (got %d, expected %d)" % [source_name, current_layer, spec.layers.size()]
			)
			continue
		if _is_meta_line(line):
			_parse_meta(spec, line)
			continue
		assert(current_layer >= 0, "%s: map row before any 'layer N'" % source_name)
		layer_rows.append(line)

	if current_layer >= 0:
		_commit_layer(spec, current_layer, layer_rows, source_name)

	assert(spec.layers.size() > 0, "%s: no layers defined" % source_name)
	assert(spec.width > 0 and spec.depth > 0, "%s: empty map" % source_name)
	return spec


static func parse_file(path: String) -> RoomSpec:
	assert(FileAccess.file_exists(path), "Room file missing: %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Cannot open room file: %s" % path)
	var text := f.get_as_text()
	var id := path.get_file().get_basename()
	return parse_text(text, id)


static func _is_meta_line(line: String) -> bool:
	if not line.begins_with("#"):
		return false
	var body := line.substr(1).strip_edges()
	if not body.contains(":"):
		return false
	var key := body.split(":")[0].strip_edges()
	return key in META_KEYS


static func _parse_meta(spec: RoomSpec, line: String) -> void:
	var body := line.substr(1).strip_edges()
	if body.begins_with("id:"):
		spec.id = StringName(body.substr(3).strip_edges())
	elif body.begins_with("cell:"):
		spec.cell_size = float(body.substr(5).strip_edges())
	elif body.begins_with("layer_height:"):
		spec.layer_height = float(body.substr(13).strip_edges())
	elif body.begins_with("open:"):
		spec.open_dirs.clear()
		var dirs := body.substr(5).strip_edges().split(",", false)
		for d in dirs:
			var token := String(d).strip_edges().to_upper()
			match token:
				"N":
					spec.open_dirs.append(ModuleContract.Dir.N)
				"E":
					spec.open_dirs.append(ModuleContract.Dir.E)
				"S":
					spec.open_dirs.append(ModuleContract.Dir.S)
				"W":
					spec.open_dirs.append(ModuleContract.Dir.W)
				"U":
					spec.open_dirs.append(ModuleContract.Dir.U)
				"D":
					spec.open_dirs.append(ModuleContract.Dir.D)
				"":
					pass
				_:
					assert(false, "Unknown open dir '%s'" % token)


static func _commit_layer(spec: RoomSpec, _level: int, rows: Array[String], source_name: String) -> void:
	assert(rows.size() > 0, "%s: layer has no rows" % source_name)
	var width := rows[0].length()
	assert(width > 0, "%s: empty row" % source_name)
	var grid: Array = []
	for r in rows.size():
		var row: String = rows[r]
		assert(
			row.length() == width,
			"%s: jagged row %d (len %d, expected %d)" % [source_name, r, row.length(), width]
		)
		var cells: Array = []
		for c in width:
			var ch := String(row[c])
			var kind: int = RoomCells.from_char(ch)
			assert(
				kind != RoomCells.Kind.EMPTY or ch == ".",
				"%s: unknown char '%s' at %d,%d" % [source_name, ch, c, r]
			)
			cells.append(kind)
		grid.append(cells)
	if spec.width == 0:
		spec.width = width
		spec.depth = rows.size()
	else:
		assert(width == spec.width, "%s: layer width mismatch" % source_name)
		assert(rows.size() == spec.depth, "%s: layer depth mismatch" % source_name)
	spec.layers.append(grid)
