# Room ASCII specs

Source of truth for geometry. Baked by `RoomPipeline` / `RoomFactory`.

| Char | Meaning |
|------|---------|
| `#` | Wall (recessed outer shell; cell is still floored) |
| `.` | Floor (walkable) |
| ` ` (space) | Void / fall-through |
| `X` or `+` | Floor (legacy aliases; prefer `.`) |
| `S` | Up-stair (straight run on lower layer; upper footprint must be void). The run bakes as one walkable ramp: it needs floor on the same layer straight before its bottom cell and floor on the layer above straight past its top cell. |
| `+` | Map-only door mark (stamped on the E/S side of a paired connection; not authored in room files) |
| `D` | Down-stair / level shaft (descends one `layer_height` into a room below). Needs approach floor straight past its top cell on the same layer. |
| `^` | Shaft floor (floor + open ceiling; up-landing for a room above) |
| `P` | Player spawn (floor) |
| `E` | Exit (floor) |
| `M` | Enemy spawn (floor) |

Meta header lines (`# id:`, `# cell:`, `# layer_height:`, `# open:`) are not map rows.
`# open:` accepts cardinal `N,E,S,W` and vertical `U,D` level connectors.
Wall rows like `####` are map data.
