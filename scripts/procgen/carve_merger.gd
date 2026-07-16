class_name CarveMerger
extends RefCounted
## Applies intentional footprint overlaps: clear geometry in the guest's overlapped
## cells and open the host's overlapped cells so the union reads as one irregular room.


static func apply(placements: Array) -> void:
	## Writes carve_* arrays into each Placement.opts for RoomFactory.
	for p_variant in placements:
		var p = p_variant
		if p == null:
			continue
		if not p.opts.has("carve_empty_ascii"):
			p.opts["carve_empty_ascii"] = []
		if not p.opts.has("carve_open_ascii"):
			p.opts["carve_open_ascii"] = []


static func plan_bite(
	guest: Variant,
	host: Variant,
	overlap_cells: Array,
	cells_per_module: int
) -> void:
	## overlap_cells: Array[Vector2i] of ground grid cells shared by guest+host.
	## Guest suppresses ASCII in those cells; host forces FLOOR there (opens walls).
	assert(guest != null and host != null, "CarveMerger.plan_bite requires guest+host")
	assert(cells_per_module > 0, "CarveMerger.plan_bite: cells_per_module")
	var guest_empty: Array = guest.opts.get("carve_empty_ascii", [])
	var host_open: Array = host.opts.get("carve_open_ascii", [])
	for cell_variant in overlap_cells:
		var gcell: Vector2i = cell_variant
		guest_empty.append_array(
			_ascii_cells_for_grid(guest.cell, gcell, guest.footprint, cells_per_module, guest.layer_span)
		)
		host_open.append_array(
			_ascii_cells_for_grid(host.cell, gcell, host.footprint, cells_per_module, host.layer_span)
		)
	guest.opts["carve_empty_ascii"] = guest_empty
	host.opts["carve_open_ascii"] = host_open
	guest.opts["carve_guest"] = true
	host.opts["carve_partner"] = true


static func _ascii_cells_for_grid(
	origin: Vector2i,
	grid_cell: Vector2i,
	footprint: Vector2i,
	cells_per_module: int,
	layer_span: int
) -> Array:
	## Returns Vector3i(local_level, ascii_x, ascii_z) covering one grid cell inside footprint.
	var out: Array = []
	var lx := grid_cell.x - origin.x
	var lz := grid_cell.y - origin.y
	if lx < 0 or lz < 0 or lx >= footprint.x or lz >= footprint.y:
		return out
	var x0 := lx * cells_per_module
	var z0 := lz * cells_per_module
	for level in layer_span:
		for z in cells_per_module:
			for x in cells_per_module:
				out.append(Vector3i(level, x0 + x, z0 + z))
	return out


static func apply_to_spec(spec: RoomSpec, opts: Dictionary) -> void:
	## Mutate spec before validate/seal/bake.
	for cell_variant in opts.get("carve_empty_ascii", []):
		var c: Vector3i = cell_variant
		if c.x < 0 or c.x >= spec.layer_count():
			continue
		if not spec.in_bounds(c.y, c.z):
			continue
		## Never erase stair shafts / markers — only plain walls/floors.
		var kind: int = spec.get_cell(c.x, c.y, c.z)
		if (
			kind == RoomCells.Kind.PLAYER
			or kind == RoomCells.Kind.EXIT
			or kind == RoomCells.Kind.STAIR
			or kind == RoomCells.Kind.DOWN_STAIR
			or kind == RoomCells.Kind.SHAFT
		):
			continue
		spec.set_cell(c.x, c.y, c.z, RoomCells.Kind.EMPTY)
	for cell_variant2 in opts.get("carve_open_ascii", []):
		var c2: Vector3i = cell_variant2
		if c2.x < 0 or c2.x >= spec.layer_count():
			continue
		if not spec.in_bounds(c2.y, c2.z):
			continue
		var kind2: int = spec.get_cell(c2.x, c2.y, c2.z)
		if kind2 == RoomCells.Kind.WALL:
			spec.set_cell(c2.x, c2.y, c2.z, RoomCells.Kind.FLOOR)
