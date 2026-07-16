# Procgen

Modules are built by `RoomFactory` and obey `ModuleContract`:

- Grid cell size: `ModuleContract.ROOM_SIZE` (8 m)
- Vertical step: `ModuleContract.LEVEL_HEIGHT` (4 m)
- Openings via connector markers (`N/E/S/W/U/D`)
- Gameplay markers: groups `player_spawn`, `enemy_spawn`, `exit`

## Hybrid generator (default)

`HybridDungeonGenerator` places authored rooms inside a 3D harness:

1. Start stack: `atrium` + `undercroft` when they fit (else `stair_test` / 1×1)
2. **2D branched growth** toward underfilled space (N/E/S/W), sized by harness *area*
3. **Stairs raise the path floor** — upper landings grow real room clusters (not orphan balconies)
4. **Basement cluster** — undercroft grows corridor/combat/hall neighbors on level `-1`
5. Side rooms + loop fillers on every occupied storey (including `-1`)
6. `open_dirs` / `open_faces` / doorway cells from adjacency (no exit win room)
7. `CarveMerger` bites: intentional 1-cell overlaps (guest empties shared ASCII, host opens it)
8. Stacked stair climbs up to `max_stair_rises` with upper foyers + floor clusters
9. Loot chests in combat/hall rooms; dive ends on death (books / mana / stamina combat)

Params: `DungeonGenParams` (width/depth/height in meters → module grid + floor count).

## Validation

`DungeonGenValidator` checks a built dungeon root:

- exactly one `player_spawn`
- every module `RoomSpec` passes `RoomValidators`
- no footprint overlaps (except intentional `carve_ok` unions)
- every horizontal door faces a paired peer (no door into void)
- up/down stair links have landings
- **perimeter / abyss:** every walkable edge cell is either a paired doorway or a baked `DoorSeal`
- Runs automatically on every playable generate / Fixed POC via `RunManager`
- all modules (including undercroft + basement) reachable from spawn on the F1 map graph

Headless CI suite (fixed seeds × Tiny/Small/Medium + Fixed POC + seal regression):

```text
godot --headless --path . -s res://scripts/dev/validate_dungeon_gen.gd
```

Generation simulation (`DungeonGenSim` — reusable generate → validate loop):

```text
godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd
godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd -- --grid --fixed-poc
godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd -- --trials=64 --presets=all
godot --headless --path . -s res://scripts/dev/simulate_dungeon_gen.gd -- --trials=24 --strict-shape
simulate_dungeon_gen.bat --trials=40 --presets=tiny,small,medium
```

Failures print per-trial errors plus an aggregated "why" histogram (error families).
Each trial also reports `fill` / `aspect` / bbox shape metrics (`--strict-shape` fails tube-like runs).

## Creation UI

Boot shows `CreateRunUI` (presets Tiny→Huge, meter spinboxes, seed).
**Generate** starts a run. After death/win, **R** returns to create (params kept).
**Fixed POC (dev)** still builds `FixedLevelSource` for regression.

## Deprecated

`RoomGraphGenerator` delegates to the hybrid generator (Small preset).
`FixedLevelSource` remains for the editor FixedPOC scene and validators.
