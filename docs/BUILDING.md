# Building FleshCore

## The plugin

You need MinGW-w64 with C++17 support (`x86_64-w64-mingw32-g++`, GCC 13). From `src/`:

```bash
x86_64-w64-mingw32-g++ -O2 -std=c++17 -I . -shared -static -static-libgcc -static-libstdc++ \
    -Wl,--subsystem,windows flesh.cpp lattice.cpp chunknif.cpp windiag.cpp \
    -o FleshCore.dll -lpsapi -lwinmm
```

The plugin uses neither CommonLibSSE nor the Address Library. Most engine offsets are in `src/facts.h`, each with its source; `flesh.cpp` and `windiag.cpp` hard-code a few more (import-table slots and the like). All of them are for runtime 1.6.1170 only.

`CMakeLists.txt` lists the same sources.

## The scripts

Compile `scripts/source` with Caprica or the Creation Kit's compiler, against the headers for SKSE, SkyUI, PapyrusUtil, powerofthree's Papyrus Extender, and RaceMenu; with Caprica, add each of those header folders with a further `-i` option.

```bash
caprica -g skyrim --ignorecwd --allow-unknown-events 1 -i scripts/source -f TESV_Papyrus_Flags.flg -o scripts scripts/source
```

`FL_MCM.psc` declares a mod-event handler as an Event, hence `--allow-unknown-events 1`.

`FL_MCM.psc` also calls SkyUI's `OnConfigManagerReady`, the handler for the menu manager's ready event, so the menu registers as soon as its script starts or a game loads. SkyUI's public `SKI_ConfigBase.psc` header does not declare that event; append these two lines to the copy of the header the scripts are compiled against:

```papyrus
event OnConfigManagerReady(string a_eventName, string a_strArg, float a_numArg, Form a_sender)
endEvent
```

An empty stub in `scripts/source` stands in for an optional mod's menu script: `FL_Watch` declares a local of that type, and the type has to resolve for the scripts to compile.

## Tests

The unit tests build with MinGW and run on Windows. From `test/`:

```bash
x86_64-w64-mingw32-g++ -std=c++17 -O2 -include array -I ../src -static -static-libgcc -static-libstdc++ \
    -o trunk_test.exe trunk_test.cpp ../src/lattice.cpp
```

`blast_test.cpp` builds the same way.
