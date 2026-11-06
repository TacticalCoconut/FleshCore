# FleshCore - developer reference

*FleshCore Beta v0.1 · this file ships in the mod folder*

FleshCore voxelises playable-race actors into lattices of cells,
forged at runtime from each actor's own meshes, and removes the cells a wound reaches; the
pieces fall, and the death rule decides whether the actor lives. It is a library: it ships debug
spells for testing, and other mods call `FL_Api`.

## Requirements

| | |
|---|---|
| **Required** | Skyrim SE/AE 1.6.1170 · SKSE64 2.2.6+ · PapyrusUtil · powerofthree's Papyrus Extender · PrismaUI (the HQ, the mod's own menu) · SkyUI (the MCM) · RaceMenu (marks on skin) |
| **Detected, optional** | Acheron · Dismembering Framework |
| **Masters** | `Skyrim.esm` only. FleshCore is not ESL-flagged. |

## Using it from your mod - the whole pattern

```papyrus
If Game.IsPluginInstalled("FleshCore.esp") && FL_Api.CoreActive() && FL_Api.Targetable(target)
    FL_Api.Wound(target, "decapitate")
Else
    ; whatever you did before FleshCore
EndIf
```

Three rules make the dependency **soft**:

1. **Ask `Game.IsPluginInstalled("FleshCore.esp")` first**, before any `FL_Api` call. The file
   test needs no script. Behind that gate, `FL_Api` calls are safe.
2. **Never declare a FleshCore Form as a property.** Reach records by
   `Game.GetFormFromFile(<local id>, "FleshCore.esp")` if you need one directly.
3. **Never add `FleshCore.esp` as a master.** Nothing in this reference needs it.

`FleshCore_Example.psc` ships in `Scripts\Source\` and is this pattern plus one event handler,
a registry rule, a trigger row and a `WhyNot` line - about a hundred and twenty lines.

## `FL_Api` - every function is `Global`

| function | returns | meaning |
|---|---|---|
| `IsInstalled()` | Bool | `FleshCore.esp` is in the load order |
| `VersionString()` | String | the engine's version, e.g. `"0.1 Beta"`; `""` if the SKSE plugin did not load |
| `CoreActive()` | Bool | the engine is armed. False for the first second or two of a session |
| `Has(String feature)` | Bool | this build carries the feature token - see below |
| `Features()` | String | all tokens, space-separated |
| `Targetable(Actor)` | Bool | FleshCore will take this actor: a playable race, an adult vampire race of `Skyrim.esm` or the Afflicted, either sex, never a child |
| `WhyRefused(Actor)` | Int | `0` accepted · `1` no base record · `2` a race FleshCore does not cut, or a child (child race, `IsChild()` or child voice type) · `3` record names no sex |
| `Wound(Actor, String kind)` | Bool | cast a named wound; true = cast, **not** taken (the event says) |
| `Restore(Actor)` | Bool | put every piece back |
| `Cast(Actor, Int localId)` | Bool | any FleshCore spell by local id, source and target both the actor |
| `SetNoKill(Actor, Bool)` | - | add / remove an actor from the never-kill list |
| `NoKill(Actor)` | Bool | whether they are in it |
| `SetInt(Actor, String key, Int value, String caller, Int prio = 0)` | - | set one registry rule for one actor - see below |
| `ClearKey(Actor, String key, String caller)` | - | withdraw this caller's rule; other callers' stand |
| `GetInt(Actor, String key)` | Int | the winning value, `-1` if no one set one |
| `WhoSet(Actor, String key)` | String | the caller whose rule is in force, `""` if none |
| `WhyNot(Actor)` | String | why FleshCore would not wound them right now - see below |
| `AddTrigger(caller, Actor scope, type, kind, Float thr, form, Float size, Int depth, parts = "-", anchor = "-", nokill = false, prio = 0)` | Int | add a trigger row - see below. Returns its id |
| `AddTriggerEx(caller, Actor scope, type, kind, Float thr, String columns, prio = 0)` | Int | the same with the whole column list as one `\|`-string |
| `RemoveTrigger(caller, Int id)` / `ClearTriggers(caller)` | - | take rows back |
| `Triggers(caller)` | String | your rows, one per line |
| `AddTriggerForEffect(caller, scope, MagicEffect, kind, thr, columns, prio = 0)` / `AddTriggerForKeyword(caller, scope, Keyword, kind, thr, columns, prio = 0)` | Int | rows against one effect (`mgef:`) or a keyword on a weapon or effect (`kw:`) |
| **Commands** | | every one returns a **ticket** (> 0) answered by `FL_Done`, or a negative code |
| `WoundPart(caller, Actor, form, size, depth, part, anchor = "centre", nokill = false)` | Int | a wound on one named part, no record in the plugin |
| `WoundEx(caller, Actor, columns)` / `WoundAt(caller, Actor, x, y, z, columns)` | Int | the thirteen columns; at a world point |
| `Detonate(caller, Actor, altMark = false)` | Int | the standard detonate wound as a command: size 12, depth 3, at the centre |
| `RestoreParts(caller, Actor, parts = "all", layermask = 0)` | Int | put parts back (`all` + 0 = whole) |
| `Heal(caller, Actor, cellsPerSec = 4.0)` / `StopHeal(caller, Actor)` | Int | regrow them over time |
| `Drain(caller, Actor, cellsPerSec = 4.0, seconds = 30.0, parts = "-", anchor = "-")` / `StopDrain(caller, Actor)` | Int | a **feed**: so many cells a second off them, one bite a second at the anchor of the named parts, for up to `seconds` or until stopped - what the Voxel Drain spell does, by command |
| `Vortex(caller, ObjectReference marker, radius, seconds, wavesPerSec, columns)` / `EndVortex(caller, ticket)` | Int | a sphere that wounds what is inside it, once per wave |
| `AskState(caller, Actor)` | Int | answered by `FL_State` - alive, parts lost, parts remaining, layers gone |
| `Ping(caller)` | Int | answered by `FL_Ping` |
| `Columns(form, size, depth, parts = "-", anchor = "-", nokill = false, count = 1, cells = 34, budget = 12, layers = 0, nosever = false, kick = 0, mark = 0)` | String | builds the column list |
| **Rules** | | |
| `AddEffectRule(caller, part, maxRemainPct, Spell ability, prio = 0)` / `RemoveEffectRule` / `ClearEffectRules` | Int | behaviour abilities by attachment - see below |
| `SetScalar(Actor, Float factor, caller)` / `ClearScalar` / `EffectiveScalar` / `ScalarContributors` | - | the per-actor scalar (0.1..10 each, product) |
| **Readers** | | |
| `BodyState(Actor)` | String | the last `FL_Wounded` payload naming them, `""` if none or restored |
| `PartRemaining(partsRemain, part)` / `PartBit(part)` / `PartInMask(mask, part)` | Int / Bool | payload helpers |
| `EffectiveVulnHP` `EffectiveImmune` `EffectiveNoLethal(Actor, origin)` `EffectiveLimbsToDie` `EffectiveHeadFatal` `EffectiveTrunkFatal` `EffectiveLimbFatal` | | what is in force for them |
| `CodeName(Int)` / `Diagnose(Actor)` | String / Int | names a code; one trace line with everything |
| **Shards** | | |
| `EnableShardActivation(caller, on)` / `EffectiveShardActivation()` | - | pieces can be activated while any caller votes yes |
| `ShardProvenance(ref)` `ShardVictim` `ShardPart` `ShardLayers` `ShardCells` `ShardIsSection` | | what a piece is |
| `ConsumeShard(caller, ref, Actor by)` / `PlacedShards()` | Int / ObjectReference[] | take a piece; the live ring |
| `Field(String s, Int n)` | String | column `n` of a `\|`-payload, `""` past the end |

**Kinds** (all self-delivery, the only shape proven to land on a target cast at itself):
`decapitate` `detonate` `bisect` `splatter` `armoffl` `armoffr` `legoffl` `legoffr`.
Anything else: `Cast()` with a local id from the table below. Aimed spells
(the twelve `Take*` limb spells, `Decapitate 0x87A`) may not land when self-cast. `Cast()` refuses
`0x894` / `0x8A9` (reserved records) with a Papyrus log line and returns false.

## Feature tokens - `FleshCore.features.txt`

Written when the engine arms, deleted every launch, one line, space-separated. Ask `Has()`
before using anything optional; a build that lacks a token simply lacks the feature.

`api` `wound` `restore` `lethality` `event` `grants` `panel` `mcm` `decals` `state` `nolethal`
`registry` `whynot` `trig` `vulnhp` `cmd` `events` `vortex` `heal` `window` `magic` `drain` `scalar`
`verdict` `scenes` `effects` `shards` `plugin` `per` `hq` `drainspell` `armour`

A token is added with the feature it names and is not removed or renamed.

## The events - from the engine, relayed by the watcher

All in SKSE's `(String eventName, String strArg, Float numArg, Form sender)` shape, sent **from
the sender** (the victim, the command's target, or the `FL_GrantQuest` quest when there is none),
about one tick (100 ms) after the engine wrote them. FormIDs inside `strArg` are signed decimals
(`Game.GetFormEx(id as Int)`); `numArg` carries wound numbers and tickets, never a FormID.

| event | sender | numArg | strArg |
|---|---|---|---|
| `FL_Wounded` | victim | wound seq | `origin\|form\|caller\|cellsTaken\|layers\|partsTouched\|partsRemain\|partsLostMask\|flags\|x,y,z` - once per wound that changed them, before the pieces are placed and before any kill |
| `FL_PartLost` | victim | wound seq | `part\|partsLostMask\|flags` - once per part freshly lost |
| `FL_Restored` | victim | ticket (0 for a spell) | `parts\|layermask\|caller` |
| `FL_Done` | the command's target | ticket | `verb\|caller\|result\|detail` |
| `FL_State` | the actor | ticket | `alive\|partsLostMask\|partsRemain\|layersGone\|lastSeq\|origin` |
| `FL_Declined` | victim | 0 | `origin\|reason\|caller\|value` - `immune` / `vulnhp` (once per body per cooldown), `verdict` / `nolethal` (once per wound), `who` (the HQ's who-may-be-cut gate), `player` (the HQ's player layers allow none of the wound's), `armour` (reserved: armour turns no wound in this release) |
| `FL_Ping` | the quest | ticket | `caller` |
| `FL_Resync` | the quest | 0 | `""` once after the engine arms |
| `FL_ShardActivated` (Papyrus) | the actor who touched it | 0 | `shardId\|victimId\|part\|layers\|cells\|section` |
| `FL_ShardConsumed` (Papyrus) | the consumer's actor | 0 | the same, then `\|caller` |

`origin`: 0 spell · 1 hit · 2 command · 3 vortex · 4 drain · 5 scene. `partsRemain` is
`part:pct,…` for every part not at 100 % - attachment, the loss rule's own number.
`FL_Done` results: 0 done · 1 immune · 2 no body · 3 nothing to take · 4 expired · 5
cancelled · 6 unsupported form · 7 bad argument · 8 not found.

**The flags word** (`FL_Wounded` column 8, and the wound file's): bit 0 they come apart (a
kill unless held) · bit 1 the trunk · bits 2-7 kick · 8-9 mark · 10 nokill (the wound's own) ·
11 a death was suppressed by a never-kill rule · 12 head freshly lost · 13 a limb freshly lost ·
14 the trunk freshly lost · 15-18 limbs lost so far. Read them by division.

**SKSE plugin consumers** register `RegisterListener(handle, "FleshCore", cb)` and receive
`FCWoundedMsg` (type 1) and `FCPartLostMsg` (type 2) beside the Papyrus events; the structs are
in `flesh.cpp` beside `FlushOutbox` and are versioned (`version = 1`).

## The compact event - `FleshCore_Wound`

A lighter companion to `FL_Wounded`, sent for every wound, **from the victim** (`sender` is their Form), before the kill, so a handler
sees them alive.

```papyrus
RegisterForModEvent("FleshCore_Wound", "OnFleshCoreWound")

Event OnFleshCoreWound(String eventName, String strArg, Float numArg, Form sender)
    Actor target = sender as Actor
    Int flags = FL_Api.Field(strArg, 0) as Int   ; bit 0: they come apart (a kill unless held)
    ;                                              bit 1: the trunk
    ;                                              bit 11 (2048): they would have died and a
    ;                                              never-kill rule said no
    String pieces  = FL_Api.Field(strArg, 1)      ; pieces forged
    String severed = FL_Api.Field(strArg, 2)      ; separate sections they are in now
EndEvent
```

`numArg` is the flags word again. **Payload columns only ever grow, at the end** - read by
index, never by splitting yourself.

## Never kill - three levels, first answer wins

A wound that "does not count" is opened, takes its flesh, drops its pieces, updates the
tally and fires the event. The **only** thing that changes is that its losses are not fed to
the death rule. The target can still die of the *next* wound, from an origin that counts.

1. **The registry** - `FL_Api.SetNoKill(target, true)`. A mod that names an actor has said they
   do not die of FleshCore wounds until it takes their name back. Outranks everything,
   including the player exemption. **Per session**: cleared at every launch, so set it when
   your scene starts and clear it when it ends.
2. **The wound's own column** - a `W` row's optional column 15, `nokill`.
3. **The origin** - the config's `NL <spell> <hit> <player>` row, also the HQ's *Wounds
   that never kill* toggles. `player 0` exempts the player from levels 2 and 3.

## The registry - per-actor rules any mod may set

`FL_Api.SetInt(target, key, value, "YourMod", prio)`. One line per (actor, key, caller) in
`FleshCore.registry.txt`; the engine re-reads it every half second and consults it where the
rule matters. **One winner per (actor, key)**: the highest `prio`, ties to the later line;
`immune` is *any true wins* - a mod that says they are immune is not out-voted by one that says
they are not. `GetInt` and `WhoSet` read the same arbitration back. **Per session**: cleared at
every launch, so set rules when your scene starts and clear them when it ends.

| key | value | honoured by |
|---|---|---|
| `immune` | `1` = FleshCore never touches them: no pre-warm, no spell, no blow | the engine, every path, and `FL_Api.Wound`/`Cast` |
| `losslimb` | limb parts they can lose before the death rule fires, `1..16` - overrides the config's `D` row for them | the engine, at the verdict |
| `losstrunk` | trunk parts, same | the engine |
| `losshead` | head, same | the engine |
| `vulnhp` | only wound them at or below this health %, `1..100` | `FL_Api.Wound`/`Cast`, and the engine's own **hit path**: a blow above the threshold is declined and logged once per cooldown. FleshCore's own spells cast by hand ignore it (they are debug tools). |

Caller ids are yours: 1-24 of `[A-Za-z0-9_]`. `FleshCore`, `FL`, `MCM` and `-` are reserved.
`Restore` ignores `immune` and `vulnhp`: putting them back is never a wound.

## The trigger table - blows become wounds by row

This is the combat integration: with it, FleshCore acts without a debug spell. A blow on an
eligible actor is **typed by what swung** and **measured against the rows**; one row per
(type, kind, threshold); **one wound per blow**, the most demanding row that passes.

```papyrus
Int id = FL_Api.AddTrigger("MyMod", target, "slash", "pct", 15.0, "slabz", 5.0, 3)   ; them alone
FL_Api.AddTrigger("MyMod", None, "blunt", "abs", 30.0, "bite", 12.0, 2)             ; everyone
FL_Api.ClearTriggers("MyMod")                                                       ; when your scene ends
```

| column | values |
|---|---|
| `type` | `blunt` (mace, warhammer, any bash) · `slash` (sword, dagger, axe, greatsword, battleaxe) · `pierce` (bow, crossbow) · `any` · `kw:<KeywordEditorID>` - a keyword on the weapon (or on the effect), so your own damage type needs no FormID · **the weapon itself**: `sword` `dagger` `waraxe` `mace` `greatsword` `battleaxe` `warhammer` `bow` `crossbow`, by the record's animation type (a bound weapon is the kind its record is) - a bash matches no weapon kind, it is `blunt` and **`bash`**, its own type · `fire` `frost` `shock` `shout` `werewolf` `drain` typed from a **hostile** effect's record when it lands (resist value, keyword, archetype) and `mgef:<runtime FormID>` naming one effect (`AddTriggerForEffect` builds it). **`unarmed` and `staff` are accepted and never fire:** see below. |
| `kind` / `thr` | `any` every blow of that type (for a magic type: every apply) · `pct` one blow ≥ `thr` % of their max health · `abs` one blow ≥ `thr` points · **`per`** every blow of that type, and the wound's *size* is `thr` units per point of damage, `0 < thr ≤ 10`, never under the row's own size, never over 40 - on a magic type it never fires on the apply, which carries no damage: the damage the effect took from their health over one element cooldown sizes it · `winpct` / `winabs` the damage of that type within `window` seconds (0.5-60, default 6), summed on the tick, once per window · `drain` `thr` cells per second for `window` seconds (0.5-120, default 8) after each apply of a matching effect. |
| `form size depth parts anchor nokill` | the W row's own columns; `AddTriggerEx` takes all thirteen: `form\|size\|count\|cells\|budget\|depth\|layers\|parts\|anchor\|sweep\|kick\|mark\|nokill` |
| `scope` | `None` = everyone; an actor = them alone |
| `prio` | FleshCore's own config rows are `-1`, so any row you add outranks them at `0`. Higher wins; a row naming them beats one naming everyone; then the higher threshold. |

Size scales with the blow: at twice the threshold the wound is up to twice the size (cap ×3); a
`per` row's size is the damage's instead. Rows are **per session** - cleared at every launch,
like the registry. A blow within the `H` row's cooldown of their last cut (900 ms shipped) is
not measured at all, whatever the row.

**The HQ's Combat page** is a consumer of this table and nothing more.
While *The HQ owns combat* is
on, the engine builds one row per weapon kind and magic type the page has switched on **for
each trigger it has on** (any number of the six kinds at once - a blow that passes more
than one opens the biggest of the wounds they would make; a blow that opened a wound is not
summed over time again), owner `HQ`, prio 5, from `panel.json`, and the config's own `T` rows
and the `H` fallback stand down
(the page can keep the `T` rows). **Your registered rows always stand**; at prio 6 or above they
outrank the HQ's. The page's *gates* apply to every row of every owner: who a blow may cut (the
player, a follower, an essential or protected NPC, anyone else - asked by the hit path and the
typed-magic path only, never of a spell, a command, a scene or a vortex; `FL_Declined … who`),
the health % above which no blow cuts (a registry `vulnhp` on them outranks it), which blows count
(every one, or power and sneak only - a row's `blows` column, always 0 for yours), and its reset
clocks (after so long without a new wound, or their health back above N %, they heal back through
the heal machinery or are put back whole; `FL_Restored … all|0|HQ`). `HQ` is reserved like `MCM`.

**How the engine reads a blow.** `TESHitEvent` carries no damage and no position; the DLL reads
the target's own `HitData` and their health through the actor-value owner (`facts.h`, *THE BLOW*,
two sources each) and **uses them only once they agree with the event**: the
HitData's weapon must be the event's weapon, its power/sneak/bash bits the event's, and the impact
point within reach of them. A blow whose numbers do not agree can only fire `any` rows, and the
log says why. A registry `vulnhp` on them declines every blow above that health %.

**FleshCore's defaults** (`T` rows, prio −1, `HK 0` turns the whole table off): blunt ≥ 25 %
-> bite 10 depth 2 · slash ≥ 25 % -> horizontal slab 5 depth 3 · pierce ≥ 25 % -> bore 7 depth 3.
Below the threshold, the `H` row applies (`H 0` shipped: nothing).

**What a hit of the player's needs.** A threshold in damage is a fixed number and the player's
damage is not, so a hit of the player's counts for `damage / (1 + perLevel × (level - 1))` on every `pct`, `abs`,
`winpct` and `winabs` row, whoever owns the row, and in the magic sample. `perLevel` is the HQ's Player power
scaling, `power.perLevel`, default 20 (% a level), and 0 turns it off. At the default, level 50 counts a hit for
about a tenth of its damage. NPCs' hits keep the thresholds as set. An `any` row on a physical blow is unaffected:
"every blow" means every blow. The HQ's magic rows, `any` included, keep their floor of a point and one per cent of
max health, and that floor reads the counted damage. A sample one of the player's effects had a hand in counts as the
player's. The HQ's `per` trigger sizes a physical wound and does not open one, for any attacker: from the row's own
weapon type, a `pct` or `abs` row must pass as well, unless neither is on. A registered or config `per` row, and a
magic one, is not affected by this. The level is read from the player's base record and logged once per level:
`[HIT] the player is level N: their hits need X times the damage to voxelize`.

**Two hits never voxelise.** An **unarmed blow** does not open a wound, whatever a row, the
`H` row or a window asks: the hit sink refuses it ahead of all of them, and the health it takes is not
counted as an untyped blow. That covers anything the game
types hand-to-hand, so a creature's claws and bites and a beast form's attacks are unarmed too, and a
hostile *effect* one of them applies is still magic and still answers the magic rows. A **staff's bolt**
is a spell: the blow is refused, and the effect it applies answers the magic rows. A bash with a staff
is a bash.

**What a blow may become.** Every physical blow, from the HQ, a config row or a row you
registered, is bounded by what swung, after the row and the slider have had their say:

| Weapon | Largest bite or bore radius (units) | A slab's share of the reach |
|---|---|---|
| `dagger` | 4 | 0.20 |
| `sword` | 6 | 0.30 |
| `waraxe` | 7 | 0.25 |
| `greatsword` | 9 | 1.00 |
| `battleaxe` | 10 | 0.50 |
| `mace` | 7 | 0.30 |
| `warhammer` | 10 | 0.50 |
| `bow` | 3 | 0.20 |
| `crossbow` | 4 | 0.20 |
| `bash` | 5.25 | 0.20 |

The reach is the HQ's `w.weapon.reach` (12 to 40 units with the slider, `0` hands it to the config),
capped by column 4 of the config's `CL` row, which is in **units**. A bite, a bore or a slab's reach is never held below half a cell: a
coarse lattice has nothing finer to give. A blow with no weapon record takes its kind's row: a slash `sword`, a
blunt `mace`, a pierce `bow`. This bounds how big a wound is and nothing else: when one opens, how deep
it goes and what kills them are the rows' and the lethality page's, and FleshCore does not touch a
weapon's damage, speed or stagger. The HQ's `w.weapon.form` is `-1` by default, each weapon its own form
(a blade a slab, a mace and a bash a bite, an arrow a bore); any other value puts that form on every
weapon, within these limits. Each wound logs which limit it met: `  <weapon>: <form> size <r>, reach <u>`.

## Armour - classified and reported, not applied

In this release no wound is weighed against armour: physical weapons deal full flesh damage. What is
classified is what they are wearing **over a spot**, not the slot: the engine reads their
biped (which item each worn shape belongs to, `facts.h` *THE ACTOR'S BIPED*, cross-checked through
each shape's own parent chain), classes each item once, and asks the lattice cells within the reach
(8 units shipped) of the spot which worn shapes still have their outer layer there. The
hardest class there wins; **a hole a wound has cut covers nothing.** The HQ's out-of-combat tester reports it.

| class | what | `AR` slash | `AR` pierce | `AR` blunt | `AR` magic |
|---|---|---|---|---|---|
| `hard` | heavy armour; light armour of metal, glass, scales, dragon scale, chitin, stalhrim, bonemold, Nordic, Falmer | ×0.5 | ×0.5 | ×1.5 | ×1 |
| `soft` | every other light armour - leather, hide, fur, studded, the guild leathers | ×1.5 | ×1.5 | ×0.5 | ×0.5 |
| `clothing` | armour type *Clothing* | ×1 | ×1 | ×1 | ×1 |
| none | jewellery (`ArmorJewelry`, `Clothing{Ring,Necklace,Circlet}`), hair-only slots, FleshCore's own records | - | - | - | - |

Families: **slash** = swords, daggers, war axes, greatswords, battleaxes, the `werewolf` magic type;
**pierce** = arrows and bolts; **blunt** = maces, warhammers, any bash; **magic** = fire,
frost, shock, shouts, drains, a staff's spell, any other hostile effect. An untyped blow (a health
drop nothing accounts for) is no family and is never weighed.

The `AR` row's twelve numbers are parsed and logged but **not applied to wounds** in this release:
a wound's size, piece budget and depth, a drain's bite, and the damage a `pct`, `abs`, `winpct` or
`winabs` row reads do not change with what they wear, and armour turns no wound (`FL_Declined … armour`
is reserved).

The config's `AR` row is the switch, the reach the classification uses and the twelve numbers;
`AM <hard|soft|cloth|none> <Keyword…>` rows class any
item carrying a keyword before the built-in rule (a mod's own material keyword, a heavy fur).
The HQ has no Armour card in this release. Ask `Has("armour")`.

## Commands - a wound with no record

`FL_Api.WoundPart("MyMod", target, "slabz", 5.0, 3, "lthigh")` opens a horizontal cut through the
middle of their left thigh; `WoundAt` lands at a world point (their nearest flesh to it);
`RestoreParts`, `Heal`, `Drain` (a feed - `FL_Done` 0 armed, then a bite a second, each an
`FL_Wounded` of origin 4, until `seconds` or `StopDrain`; a second `Drain` on them re-arms the same
feed; the registry scalar scales the rate), `Vortex` and `AskState` are the rest of the verbs. Every call returns a
**ticket** and the engine answers with `FL_Done` on the target about a tick later - from the
game's own thread, one wound at a time, two per tick at most. `immune` refuses a command (result
1); `vulnhp` and the scalar do **not** apply to commands: they are deliberate. A part name the
engine does not know refuses the command (result 7, `bad argument`, the name in the detail)
rather than reading as every part.

**Part names.** Fifteen parts, one key each, and the key is what every payload carries
(`partsTouched`, `partsRemain`, `FL_PartLost`, `FL_Restored`, `FL_State`) and what `PartBit`
lists: `head` `chest` `abdomen` `lupperarm` `lforearm` `lhand` `rupperarm` `rforearm` `rhand`
`lthigh` `lcalf` `lfoot` `rthigh` `rcalf` `rfoot`. Wherever you *name* a part - a `parts`
column, `WoundPart`, `RestoreParts`, an effect rule - the key or the config file's spelling
(`left thigh`, `upper torso`, `left lower leg`) is accepted, case-insensitively, comma-separated.

## Effect rules - behaviour by attachment

`FL_Api.AddEffectRule("MyMod", "leg", 60, myLimpAbility)` - while either leg is attached at less
than 60 %, the ability is on them; it comes off above it and on `FL_Restored`. Parts: any part
name, or `leg` / `arm` / `head` / `trunk`. Abilities only, never a forced idle. The marker ability
`FL_WoundedFX` (0x94A) is on every actor FleshCore has wounded and not restored - the one per-actor
channel a `has_magic_effect` condition or a SkyrimNet prompt can read.


## Shards - pieces with provenance

Every piece carries `victimId|part|layers|cells|section` under `FC_prov`; `ShardProvenance` and
its readers give it back. `EnableShardActivation("MyMod", true)` lets pieces be activated; touching
one sends `FL_ShardActivated` from the actor who touched it; **the condition is yours**  - 
werewolf form, a ring, a faction - and `ConsumeShard("MyMod", piece, by)` takes it (sends
`FL_ShardConsumed`, runs the piece's own undertaker). A piece nobody consumes lives its 45 s (a
severed section 300 s) -- or less: the cfg's `LP maxLive shardLife sectionLife` row
(default `LP 35 45 300`) caps how many pieces lie about at once, every victim's together, and the
OLDEST are deleted first when a new piece is born over the cap. The HQ's **Pieces kept
on the ground** slider (Engine page, 0-300) overrides `maxLive` once it is moved, and live: the DLL
writes the slider's number to `FleshCore.pieces.txt` (empty until it is moved, so the `LP` row
stands, read on every load), and `FL_Watch` hands it to `FL_Chunk` on every load and within about
four seconds of a change, clearing the floor down to a lowered cap within a few seconds (32 pieces
every four beats). Every piece joins the ring whether or not a cap is set. A new wound is not
trimmed at the cap, so old pieces make room for new ones; the DLL cuts a wound to one piece only when
twice the cap are already out. A loaded save keeps its pieces' ring (it lives in the co-save); a
load clears nothing unless the HQ's cap is below what the save has down, and then the oldest are
cleared down to it. A consumer that wants a piece should
take it promptly; `FL_ShardConsumed` is unaffected. `LP 0 ...` = no cap.

## `WhyNot` - one word, resolved in the engine's own order

| word | meaning |
|---|---|
| `ok` | they would be wounded |
| `noplugin` | `FleshCore.esp` is not loaded |
| `notarmed` | the engine has not armed yet this session |
| `ineligible:N` | `WhyRefused`'s own code: 1 no base · 2 race or child · 3 no sex |
| `immune:C` | a registry rule, `C` the caller |
| `vulnhp:N` | their health is above `N` %, the registry's threshold |
| `nobody` | eligible, but the engine has not built them yet. A wound **still lands** - they are built on the first blow - so this is a fact about cost, not outcome |

Existing words keep their meaning; new ones may be added. Read the word before the colon with
`StringUtil.Split(why, ":")[0]`.

## Files the engine writes (read-only to you)

| file | meaning |
|---|---|
| `Data\SKSE\Plugins\FleshCore.active.txt` | exists ⇔ armed. Deleted every launch. |
| `…\FleshCore.features.txt` | the tokens. Same lifetime. |
| `…\FleshCore.version.txt` | `<version>\|<HQ state>` |
| `…\FleshCore.grants.txt` | which debug spells the player has, one decimal local id per line. The HQ edits it; the watcher enforces it. |
| `…\FleshCore.nokill.txt` | the never-kill list, one decimal FormID per line as Papyrus writes it. Cleared every launch. `FL_Api.SetNoKill` is the writer. |
| `…\FleshCore.registry.txt` | `<formID>\|<key>\|<value>\|<caller>\|<prio>`, one per line. Cleared every launch. `FL_Api.SetInt`/`ClearKey` are the writers. |
| `…\FleshCore.bodies.txt` | the actors the engine holds a lattice for, one signed decimal FormID per line, rewritten every half second. `WhyNot` reads it. |
| `…\FleshCore.triggers.txt` | registered trigger rows, `caller\|id\|scope\|type\|kind\|thr\|window\|<13 wound columns>\|prio`. Cleared every launch. `FL_Api.AddTrigger` is the writer. The HQ's own rows are not in it - they are built in the engine from `panel.json`. |
| `…\FleshCore.scalars.txt` | `formID\|factor\|caller`. Cleared every launch. `FL_Api.SetScalar` is the writer. |
| `…\FleshCore.cmd<N>.txt` | one command each, written by `FL_Api`, read and deleted by the engine on its next tick. |
| `…\FleshCore.ev<N>.txt` | one event each, written by the engine, relayed by the watcher in order; swept at launch and at every load. |

## The debug spells

Fifty-six spells, all in `FL_SpellList`, **none granted by default on a fresh install**.
The HQ (double-tap `.`, PrismaUI) grants and revokes; the MCM
shows the version and rebinds the key. They exist so you can watch the engine work - your mod
should call `FL_Api`, not hand them to the player. The grant list is one file,
`FleshCore.grants.txt` (one decimal local id per line), and it alone decides: the HQ's
Grant / Revoke writes it, and the watcher syncs the loaded save's spellbook to it - listed and
missing is added, unlisted and present is removed - on every load, every minute, and within
seconds of the file changing. A missing file is created empty (nothing seeds it from a spellbook),
so a save that holds these spells with no file loses them on the first beat, and whatever the file
lists reaches any save that loads: the file is per install, not per save.

Exactly one effect is flagged hostile, Voxel Drain's `0x94B` (Hostile + Detrimental, archetype
Absorb -- the one absorb): it is the vanilla vampire drain, and it must be hostile, because the
typed-magic sink (see the trigger table: "typed from a **hostile** effect's record") ignores any effect without
that flag and types this one `drain` by its MagicVampireDrain keyword. Casting `0x94C` on an NPC is
an attack like the vanilla drain; every other FleshCore spell raises no alarm.

Local ids: `0x87A` Decapitate · `0x896` DecapitateSelf · `0x87C`/`0x87E` Restore /
RestoreSelf · `0x880` Detonate · `0x89E` DetonateSelf · `0x829`/`0x856` Bisect / Self ·
`0x842`/`0x84F` Splatter / Self · `0x8A0 0x8A2 0x8A4 0x8A6` ArmOffL/R LegOffL/R Self ·
`0x8AB`-`0x8C1` the twelve `Take*` limb spells (aimed) · `0x94C` **Voxel Drain**
(effect `0x94B`): the vampire's drain - its beam, its absorb of health at the vanilla
magnitude - that also feeds on their flesh from the neck down, one bite a second, while the beam
holds; a `DR` config row (`DR 2379 4.0 30 chest top`) makes the effect a feed, and the effect's
own script (`FL_Drain`) ends it on `OnEffectFinish`. The full list is the plugin's `SPEL`
records; every editor id is `FL_<Name>_Spell`.

Not in `FL_SpellList` (the plugin only appends records): `0x846`, `0x852`, `0x882`, `0x885`,
`0x888`, `0x88A`, `0x894`, and `0x8A9` are reserved records kept for append-only FormID layout
stability; the HQ does not list or grant them, and the watcher removes them from the player's spellbook.

## Compatibility

- **FormIDs do not move.** FleshCore only appends records, so a local id in this document
  keeps its record.
- **`FL_Api` functions are kept.** New ones may be added; none is removed or renamed without a note in the changelog.
- **Event payloads only grow, at the end.** `Field()` is the reader.
- **Feature tokens are kept.**
- **Return codes keep their meaning**; new ones may be added.
- **Not promised:** the config's row letters, the wound files' format, `panel.json`, the
  DLL's log lines, and anything reached other than through `FL_Api` and the event.

## What is not here

FleshCore has no mod-event dispatcher transport (the files cost one
100 ms tick each way and are the method this plugin already uses), no per-condition shard records with
their own activate text, and no swing-direction column (`dir`) in the trigger table, which the
engine could read from the attack data but does not yet.
