# Room ASCII specs

Source of truth for geometry. Baked by `RoomPipeline` / `RoomFactory`.

| Char | Meaning |
|------|---------|
| `#` | Wall (recessed outer shell; cell is still floored) |
| `.` | Empty / void (fall-through) |
| `X` or `+` | Floor |
| `S` | Up-stair (straight run on lower layer; upper footprint must be `.`) |
| `D` | Down-stair / level shaft (descends one `layer_height` into a room below) |
| `^` | Shaft floor (floor + open ceiling; up-landing for a room above) |
| `P` | Player spawn (floor) |
| `E` | Exit (floor) |
| `M` | Enemy spawn (floor) |

Meta header lines (`# id:`, `# cell:`, `# layer_height:`, `# open:`) are not map rows.
`# open:` accepts cardinal `N,E,S,W` and vertical `U,D` level connectors.
Wall rows like `####` are map data.
