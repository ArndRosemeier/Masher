# Procgen

Modules are built by `RoomFactory` and obey `ModuleContract`:

- Grid cell size: `ModuleContract.ROOM_SIZE` (8 m)
- Vertical step: `ModuleContract.LEVEL_HEIGHT` (4 m)
- Openings via connector markers (`N/E/S/W/U/D`)
- Gameplay markers: groups `player_spawn`, `enemy_spawn`, `exit`

## Hybrid generator (default)

`HybridDungeonGenerator` places authored rooms inside a 3D harness:

1. Start stack: `atrium` + `undercroft` when they fit (else `stair_test` / 1×1)
2. Horizontal path of `corridor` / `combat`, occasional `stair_test` hops
3. Side combat rooms + guaranteed `exit`
4. `open_dirs` from footprint adjacency (including vertical)

Params: `DungeonGenParams` (width/depth/height in meters → module grid + floor count).

## Validation

`DungeonGenValidator` checks a built dungeon root:

- exactly one `player_spawn`, at least one `exit`
- every module `RoomSpec` passes `RoomValidators`
- no footprint overlaps
- every horizontal door faces a paired peer (no door into void)
- up/down stair links have landings
- exit (and non-undercroft modules) reachable from spawn on the F1 map graph

Headless runner (presets × seeds + Fixed POC):

```text
godot --headless --path . -s res://scripts/dev/validate_dungeon_gen.gd
```

## Creation UI

Boot shows `CreateRunUI` (presets Tiny→Huge, meter spinboxes, seed).
**Generate** starts a run. After death/win, **R** returns to create (params kept).
**Fixed POC (dev)** still builds `FixedLevelSource` for regression.

## Deprecated

`RoomGraphGenerator` delegates to the hybrid generator (Small preset).
`FixedLevelSource` remains for the editor FixedPOC scene and validators.
