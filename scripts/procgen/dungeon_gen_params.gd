class_name DungeonGenParams
extends RefCounted
## Harness + seed for HybridDungeonGenerator. Meters in; module grid derived.


enum Preset { TINY, SMALL, MEDIUM, LARGE, HUGE }

const MIN_WIDTH_M := 16.0
const MAX_WIDTH_M := 256.0
const MIN_DEPTH_M := 16.0
const MAX_DEPTH_M := 256.0
const MIN_HEIGHT_M := 8.0
const MAX_HEIGHT_M := 64.0

## seed 0 means randomize at generate time.
var seed_value: int = 0
var width_m: float = 40.0
var depth_m: float = 40.0
var height_m: float = 16.0


func grid_w() -> int:
	return maxi(2, int(floor(width_m / ModuleContract.ROOM_SIZE)))


func grid_d() -> int:
	return maxi(2, int(floor(depth_m / ModuleContract.ROOM_SIZE)))


func floor_count() -> int:
	## Multilayer from day one: at least 2 vertical levels in the harness.
	return maxi(2, int(floor(height_m / ModuleContract.LEVEL_HEIGHT)))


func min_level() -> int:
	## World vertical levels used: 0 .. floor_count-1 by default.
	## Undercroft may place at -1 when the start stack needs it and height allows.
	return 0


func max_level() -> int:
	return floor_count() - 1


func path_length_target() -> int:
	## Back-compat alias: spine module count from harness *area* (not w+d sausage).
	return path_module_target()


func path_module_target() -> int:
	## Fill a chunk of the ground-plane grid so large presets spread in 2D.
	var area := grid_w() * grid_d()
	return clampi(int(round(float(area) * 0.42)), 5, 56)


func side_room_target() -> int:
	## Branches / pockets — scales with area, not just floor count.
	var area := grid_w() * grid_d()
	return clampi(int(round(float(area) * 0.14)), 2, 20)


func loop_attempt_target() -> int:
	return clampi(path_module_target() / 3, 1, 12)


func upper_cluster_target() -> int:
	## Rooms to grow on a stair's upper floor (beyond the landing itself).
	return clampi(2 + floor_count(), 2, 6)


func lower_cluster_target() -> int:
	## Rooms to grow on the basement storey from the undercroft.
	## Slightly smaller than upper clusters — basement is optional flavor, not the spine.
	return clampi(2 + floor_count() / 2, 2, 5)


func max_stair_rises() -> int:
	## How many times the path may climb (0→1→2…). Capped by harness floors.
	return clampi(floor_count() - 1, 1, 3)


func carve_bite_target() -> int:
	## Intentional partial overlaps for irregular room unions.
	var area := grid_w() * grid_d()
	return clampi(int(round(float(area) * 0.06)), 1, 8)


func summary_text() -> String:
	return "Modules: %d×%d  ·  Floors: %d  ·  ~%.0f m³" % [
		grid_w(),
		grid_d(),
		floor_count(),
		width_m * depth_m * height_m,
	]


func duplicate_params() -> DungeonGenParams:
	var p := DungeonGenParams.new()
	p.seed_value = seed_value
	p.width_m = width_m
	p.depth_m = depth_m
	p.height_m = height_m
	return p


func clamp_meters() -> void:
	width_m = clampf(width_m, MIN_WIDTH_M, MAX_WIDTH_M)
	depth_m = clampf(depth_m, MIN_DEPTH_M, MAX_DEPTH_M)
	height_m = clampf(height_m, MIN_HEIGHT_M, MAX_HEIGHT_M)


static func from_preset(preset: Preset) -> DungeonGenParams:
	var p := DungeonGenParams.new()
	match preset:
		Preset.TINY:
			p.width_m = 24.0
			p.depth_m = 24.0
			p.height_m = 12.0
		Preset.SMALL:
			p.width_m = 40.0
			p.depth_m = 40.0
			p.height_m = 16.0
		Preset.MEDIUM:
			p.width_m = 64.0
			p.depth_m = 64.0
			p.height_m = 24.0
		Preset.LARGE:
			p.width_m = 96.0
			p.depth_m = 96.0
			p.height_m = 32.0
		Preset.HUGE:
			p.width_m = 128.0
			p.depth_m = 128.0
			p.height_m = 48.0
	p.clamp_meters()
	return p


static func preset_name(preset: Preset) -> String:
	match preset:
		Preset.TINY:
			return "Tiny"
		Preset.SMALL:
			return "Small"
		Preset.MEDIUM:
			return "Medium"
		Preset.LARGE:
			return "Large"
		Preset.HUGE:
			return "Huge"
	return "?"
