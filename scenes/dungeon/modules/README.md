Room modules are built at runtime by `RoomFactory` (KayKit meshes + collision hulls + markers).

This keeps the POC and future procgen on one code path. Prefab `.tscn` modules can be added later if hand-authoring becomes useful; they must still expose `ModuleContract` connectors and spawn groups.
