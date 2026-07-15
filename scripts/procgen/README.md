# Procgen (post-POC ready)

Room modules are built by `RoomFactory` and obey `ModuleContract`:

- Grid cell size: `ModuleContract.ROOM_SIZE` (8m)
- Openings via `Connector_N/E/S/W` markers
- Gameplay markers: groups `player_spawn`, `enemy_spawn`, `exit`

`FixedLevelSource` hand-places modules for the POC.
`RoomGraphGenerator` assembles the same modules from a seedable graph.

Switch modes on `Main` (`level_mode` export): `Fixed` (default) or `Generated`.
