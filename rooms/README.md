# Room ASCII specs

Source of truth for geometry. Baked by `RoomPipeline` / `RoomFactory`.

| Char | Meaning |
|------|---------|
| `#` | Wall |
| `.` | Empty / void (fall-through) |
| `X` or `+` | Floor |
| `S` | Stair (straight run on lower layer only; upper footprint must be `.`) |
| `P` | Player spawn (floor) |
| `E` | Exit (floor) |
| `M` | Enemy spawn (floor) |

Meta header lines (`# id:`, `# cell:`, `# layer_height:`, `# open:`) are not map rows.
Wall rows like `####` are map data.
