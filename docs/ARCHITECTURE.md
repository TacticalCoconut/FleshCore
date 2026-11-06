# How FleshCore works

## The two halves

**The plugin (`src/`)** does the geometry: it reads bodies, keeps their lattices, decides what a wound takes and rewrites what the game draws.

**The scripts (`scripts/source/`)** do what only Papyrus can do from outside the engine, such as equipping the interior, placing pieces, relaying events and serving the public API in `FL_Api`.

The two talk through small numbered files in `Data/SKSE/Plugins`. That costs one 100 ms tick each way. `FL_Watch` is the script end of it.

## A body

When an actor loads, or first takes a blow, the plugin reads their meshes into a `flesh::Lattice` (`lattice.h`). Each cell knows which triangles fall inside it, on which layer:

| Layer | Bit | Contents |
|---|---|---|
| Skin | `0x01` | The outer surface |
| Fat | `0x02` | Subcutaneous tissue |
| Muscle | `0x04` | The fill behind it |
| Bone | `0x08` | The skeleton |
| Armour | `0x10` | What they wear there |

Clothed bodies need an interior that the game would not otherwise draw. `FL_Watch` equips it through the skin-fill armour, on biped slot 61.

## A wound

1. A hit, a magic effect or a command names a form, a size and a depth. Trigger rows from the config, the HQ or another mod decide which.
2. `Lattice::Select` picks the cells. `armour_bits.h` says what they wear at that spot (hard, soft or clothing); in this release that is reported, not used to resize the wound.
3. The chosen cells lose their layers. `Redraw` hides the triangles those cells held.
4. Whatever no longer connects to the main mass is a section. `chunknif.cpp` forges each one into a NIF under a recycled name in `meshes/FleshCore/runtime`, and the piece is placed in the world.
5. The death rule reads what was lost, and the registry, the panel and the config have their say.

## Files

| File | Job |
|---|---|
| `src/flesh.cpp` | The engine: sinks, bodies, wounds, redraw, the panel bridge |
| `src/lattice.cpp`, `lattice.h` | The lattice, its forms and its sections |
| `src/chunknif.cpp`, `chunknif.h` | Forging pieces as NIFs |
| `src/armour_bits.h` | What a worn item is made of, and whether it covers a spot |
| `src/redraw_bits.h` | The pure parts of the redraw |
| `src/facts.h` | Engine offsets, each with where it was read from |
| `src/windiag.cpp`, `windiag.h` | Stall and window diagnostics |
| `scripts/source/FL_Api.psc` | The public API |
| `scripts/source/FL_Watch.psc` | The script side of the engine |
| `scripts/source/FL_Chunk.psc` | A placed piece |
| `scripts/source/DC_Api.psc` | Marks on skin and surfaces |
