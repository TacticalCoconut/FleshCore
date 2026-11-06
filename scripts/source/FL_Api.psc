Scriptname FL_Api Hidden
{FleshCore's public surface. Everything a third-party mod should call is here,
 and nothing here will be renamed or removed -- see THE CONTRACT below.

 SOFT DEPENDENCY BY DESIGN. Every function is Global, so a
 consumer never holds a FleshCore Form and never needs FleshCore.esp as a
 master. Gate on IsInstalled() first: if FleshCore.esp is not loaded, this
 script's .pex is not on disk either, and a call would fail at runtime -- so
 the caller's guard is what keeps the dependency soft. The shape is:

     If FL_Api.IsInstalled() && FL_Api.CoreActive() && FL_Api.Targetable(target)
         FL_Api.Wound(target, "decapitate")
     Else
         ; your fallback
     EndIf

 THE CONTRACT:
   * Every function here is permanent. New ones may be added; none removed
     or renamed.
   * Local FormIDs published in the reference are permanent. FleshCore only
     ever appends records (the plugin's own law).
   * Event payloads are '|'-separated and only ever GROW, at the end. Read
     them by index with Field() and a missing column comes back "".
   * Feature tokens are permanent: added the version a feature ships, never
     removed, never renamed. Ask Has() before using anything optional.
   * The config's row letters, the wound files, and anything reached other
     than through this script are NOT promised.

 REQUIRES: SKSE, PapyrusUtil, powerofthree's Papyrus Extender, PrismaUI, SkyUI,
 RaceMenu. DETECTS (works without): Acheron, Dismembering Framework.}

; ---- presence -------------------------------------------------------------

Bool Function IsInstalled() Global
    {FleshCore.esp is in the load order. Ask this FIRST and gate every other
     call on it -- see the header.}
    Return Game.IsPluginInstalled("FleshCore.esp")
EndFunction

String Function VersionString() Global
    {The engine's own version, e.g. "0.1 Beta", read from what the DLL wrote this
     session. "" means the SKSE plugin did not load -- which is the single most
     useful thing to know when nothing else works.}
    String raw = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.version.txt")
    If raw == ""
        Return ""
    EndIf
    Return Field(raw, 0)
EndFunction

Bool Function CoreActive() Global
    {The engine is armed: the DLL loaded, read its config, and validated its
     records against the live form table. Wounds do nothing until this is
     true. It is false for the first second or two of every session.}
    Return FL_Wound.CoreActive()
EndFunction

; ---- capability -----------------------------------------------------------

Bool Function Has(String feature) Global
    {Whether THIS build carries a feature, by token. Read from
     FleshCore.features.txt, which the DLL writes at arm time and deletes on
     every launch, so a stale file cannot claim a feature that is not there.
     Tokens so far: api wound restore lethality event grants panel mcm decals
     state nolethal registry whynot trig vulnhp cmd events vortex heal window
     magic drain scalar verdict scenes effects shards plugin per
     hq drainspell.
     A consumer that asks before using degrades instead of failing.}
    If feature == ""
        Return false
    EndIf
    String all = Features()
    If all == ""
        Return false
    EndIf
    ; Whole-token match: "wound" must not be found inside "woundat".
    Return StringUtil.Find(" " + all + " ", " " + feature + " ") >= 0
EndFunction

String Function Features() Global
    {The whole feature list, space-separated, for a log line. "" until armed.}
    String raw = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.features.txt")
    Return raw
EndFunction

; ---- eligibility ----------------------------------------------------------

Bool Function Targetable(Actor akActor) Global
    {Whether FleshCore will take this actor at all: a playable race, an adult
     vampire race of Skyrim.esm or the Afflicted, of either sex; never a child.}
    Return FL_Wound.Targetable(akActor)
EndFunction

Int Function WhyRefused(Actor akActor) Global
    {0 accepted, 1 no base record, 2 a race FleshCore does not cut, or a child (child race,
     IsChild() or child voice type), 3 the record names no sex. Permanent codes; new ones may be added above 3.}
    Return FL_Wound.WhyRefused(akActor)
EndFunction

; ---- doing things ---------------------------------------------------------

Bool Function Wound(Actor akActor, String kind) Global
    {Open a named wound on an actor. Returns true if the spell was cast --
     NOT that they were taken: the engine decides that on its own thread a
     frame later, and says so through the FleshCore_Wound event.

     KINDS (all self-delivery, the only shape proven to land on a
     target cast at itself):
       decapitate  detonate  bisect  splatter
       armoffl  armoffr  legoffl  legoffr
       grind  shredderrune  shreddersphere  knockout  kocure
     Unknown kind: returns false and says so in the Papyrus log. For anything
     else in the plugin, Cast() takes a local id directly.}
    Int id = KindToLocal(kind)
    If id <= 0
        Debug.Trace("[FleshCore] FL_Api.Wound: unknown kind '" + kind + "' -- see FL_Api.psc for the list")
        Return false
    EndIf
    Return Cast(akActor, id)
EndFunction

Bool Function Restore(Actor akActor) Global
    {Put every piece of them back. Self-delivery.}
    Return Cast(akActor, 0x0000087E)
EndFunction

Bool Function Cast(Actor akActor, Int localId) Global
    {Cast any FleshCore spell at an actor by its local id, source and target
     both the actor -- the idiom FL_Grind ships.
     Aimed spells (the twelve Take* limb spells, Decapitate 0x87A) may not
     land when cast this way; prefer their Self twins where one exists.
     Returns true if the spell resolved and was cast.}
    If !akActor || localId <= 0
        Return false
    EndIf
    If localId == 0x894 || localId == 0x8A9
        ; THE SEQUENCE IS INERT:
        ; its effect is a no-op, so a caller is told here instead of casting
        ; something that does nothing.
        Debug.Trace("[FleshCore] FL_Api.Cast: 0x894/0x8A9 (the Sequence) is retired -- not cast")
        Return False
    EndIf
    If !IsInstalled()
        Return false
    EndIf
    ; THE REGISTRY, ON THE CONSUMER PATH. immune the engine would
    ; refuse anyway; vulnhp it cannot judge, so this is where it is judged.
    ; Restore (0x87C/0x87E) is exempt: putting them back is never a wound.
    If localId != 0x87C && localId != 0x87E
        String who = ""
        If Winner(akActor, "immune", who) > 0
            Debug.Trace("[FleshCore] FL_Api.Cast: " + akActor + " is immune (set by " + who + ") -- not cast")
            Return false
        EndIf
        Int vh = GetInt(akActor, "vulnhp")
        If vh > 0 && akActor.GetActorValuePercentage("Health") * 100.0 > (vh as Float)
            Debug.Trace("[FleshCore] FL_Api.Cast: " + akActor + " is above the vulnhp threshold of " + vh + "% -- not cast")
            Return false
        EndIf
    EndIf
    Spell sp = Game.GetFormFromFile(localId, "FleshCore.esp") as Spell
    If !sp
        Debug.Trace("[FleshCore] FL_Api.Cast: 0x" + localId + " is not a spell in this FleshCore.esp")
        Return false
    EndIf
    sp.Cast(akActor, akActor)
    Return true
EndFunction

Int Function KindToLocal(String kind) Global
    {The kind table. Local ids are permanent (the plugin only appends), so
     these are facts, not configuration. Case-insensitive: Papyrus string
     comparison already is.

     Additional alias kinds resolve records kept in the plugin for
     append-only FormID stability. The base mod does not grant those
     reserved spells to the player (they are not in FL_SpellList or
     the HQ), but the records remain in the plugin so existing callers
     continue to resolve them.}
    If kind == "decapitate"
        Return 0x00000896
    ElseIf kind == "detonate"
        Return 0x0000089E
    ElseIf kind == "detonatealt"
        Return 0x00000885
    ElseIf kind == "bisect"
        Return 0x00000856
    ElseIf kind == "splatter"
        Return 0x0000084F
    ElseIf kind == "altmark"
        Return 0x00000852
    ElseIf kind == "armoffl"
        Return 0x000008A0
    ElseIf kind == "armoffr"
        Return 0x000008A2
    ElseIf kind == "legoffl"
        Return 0x000008A4
    ElseIf kind == "legoffr"
        Return 0x000008A6
    ElseIf kind == "altmark2"          ; additive alias of "the alt mark": same record 0x852, same promise
        Return 0x00000852
    ElseIf kind == "detonatealt2"      ; additive alias of "the alt burst": same record 0x885
        Return 0x00000885
    EndIf
    Return 0
EndFunction

; ---- never kill ----------------------------------------------------
;
; Design note: a toggle that excludes the death trigger (for
; NPCs and the player) when voxelisation comes from certain actions. This is the
; registry -- the first of three levels, and the one a mod uses. Name an actor
; here and no FleshCore wound kills them until you take their name back: the
; flesh still comes off, the pieces still drop, the event still fires, and the
; death rule alone is told to look away. The other two levels are the config's
; (a W row's nokill column, and the NL row's per-origin flags).
;
; PER SESSION. The engine clears the file at every launch, so a scene that
; crashed cannot leave them unkillable into the next game. Set it when your
; scene starts, clear it when your scene ends.

Function SetNoKill(Actor akActor, Bool abOn) Global
    {Add or remove an actor from the never-kill registry. Takes effect on the
     next wound; nothing already in flight is revisited.}
    If !akActor
        Return
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.nokill.txt"
    String id = "" + akActor.GetFormID()
    String cur = MiscUtil.ReadFromFile(path)
    Bool listed = StringUtil.Find("\n" + cur + "\n", "\n" + id + "\n") >= 0
    If abOn && !listed
        MiscUtil.WriteToFile(path, id + "\n", true, false)
    ElseIf !abOn && listed
        String[] lines = StringUtil.Split(cur, "\n")
        String out = ""
        Int i = 0
        While i < lines.Length
            If lines[i] != "" && lines[i] != id
                out += lines[i] + "\n"
            EndIf
            i += 1
        EndWhile
        MiscUtil.WriteToFile(path, out, false, false)
    EndIf
EndFunction

Bool Function NoKill(Actor akActor) Global
    {Whether an actor is in the registry right now.}
    If !akActor
        Return false
    EndIf
    String cur = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.nokill.txt")
    Return StringUtil.Find("\n" + cur + "\n", "\n" + akActor.GetFormID() + "\n") >= 0
EndFunction

; ---- the registry --------------------------------------------------
;
; Per-actor rules any mod may set, with a caller id and a
; priority, arbitrated one winner per (actor, key). The file is
; FleshCore.registry.txt, one line per entry:
;
;     <formID>|<key>|<value>|<caller>|<prio>
;
; The engine reads it every half second and consults it where the rule
; matters. KEYS, all Int:
;   immune      1 = FleshCore never touches them (any true wins)
;   losslimb    limb parts lost before death, 1..16 -- overrides the D row
;   losstrunk   trunk parts, same
;   losshead    head, same
;   headfatal   0/1 -- whether losing their head kills them (over the panel)
;   trunkfatal  0/1 -- the trunk
;   limbfatal   0/1 -- a limb
;   limbstodie  N   -- a limb kills only once N limbs are gone (1..12)
;   vulnhp      only wound them at or below this health %, 1..100. Honoured by
;               FL_Api.Wound / Cast (the consumer path) and by
;               the engine's own hit path (a blow above it is declined and
;               logged once per cooldown). Spells cast by hand ignore it.
; CALLER IDS are yours: 1-24 of [A-Za-z0-9_]. `FleshCore`, `FL`, `MCM` and
; `-` are reserved. PER SESSION: cleared at every launch.

Function SetInt(Actor akActor, String key, Int value, String caller, Int prio = 0) Global
    {Set one rule for one actor. Replaces this caller's earlier line for the
     same actor and key; other callers' lines stand and the priority decides.}
    If !akActor || key == "" || caller == ""
        Return
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.registry.txt"
    String id = "" + akActor.GetFormID()
    String out = Without(MiscUtil.ReadFromFile(path), id, key, caller)
    out += id + "|" + key + "|" + value + "|" + caller + "|" + prio + "\n"
    MiscUtil.WriteToFile(path, out, false, false)
EndFunction

Function ClearKey(Actor akActor, String key, String caller) Global
    {Withdraw this caller's rule for this actor and key. Other callers' stand.}
    If !akActor || key == "" || caller == ""
        Return
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.registry.txt"
    String out = Without(MiscUtil.ReadFromFile(path), "" + akActor.GetFormID(), key, caller)
    MiscUtil.WriteToFile(path, out, false, false)
EndFunction

String Function Without(String content, String id, String key, String caller) Global
    {The registry text with one caller's line for one (actor, key) taken out.
     Field-exact, so a caller named "1" cannot match a value of 1.}
    String[] lines = StringUtil.Split(content, "\n")
    String out = ""
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If !(f.Length >= 5 && f[0] == id && f[1] == key && f[3] == caller)
                out += lines[i] + "\n"
            EndIf
        EndIf
        i += 1
    EndWhile
    Return out
EndFunction

Int Function GetInt(Actor akActor, String key) Global
    {The winning value for this actor and key, or -1 if no one has set one.
     Same arbitration as the engine's: highest prio, ties to the later line;
     `immune` is any true wins.}
    String who = ""
    Return Winner(akActor, key, who)
EndFunction

String Function WhoSet(Actor akActor, String key) Global
    {The caller whose rule is in force for this actor and key, or "".}
    String who = ""
    Winner(akActor, key, who)
    Return who
EndFunction

Int Function Winner(Actor akActor, String key, String who) Global
    If !akActor || key == ""
        Return -1
    EndIf
    String id = "" + akActor.GetFormID()
    String[] lines = StringUtil.Split(MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.registry.txt"), "\n")
    Int best = -1
    Int bestPrio = 0
    Bool have = false
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If f.Length >= 5 && f[0] == id && f[1] == key
                Int v = f[2] as Int
                Int p = f[4] as Int
                Bool take = false
                If key == "immune"
                    take = (v != 0) || best <= 0
                Else
                    take = !have || p >= bestPrio
                EndIf
                If take
                    best = v
                    bestPrio = p
                    have = true
                    who = f[3]
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    Return best
EndFunction

; ---- the trigger table --------------------------------------------
;
; A blow on an actor is typed by what swung -- blunt, slash,
; pierce -- and measured against the rows: one row per (type, kind,
; threshold), one wound per blow, the most demanding row that passes. Config
; `T` rows are FleshCore's defaults at prio -1; a row you add here outranks
; them at prio 0 or above. The file is FleshCore.triggers.txt:
;
;   <caller>|<id>|<scope>|type|kind|thr|window|form|size|count|cells|budget|
;   depth|layers|parts|anchor|sweep|kick|mark|nokill|prio
;
; TYPES:  blunt slash pierce any  kw:<KeywordEditorID>
;         unarmed and staff parse and never fire: neither hit voxelises
;         fire frost shock shout werewolf drain (typed from a hostile effect's
;         record) and mgef:<runtime FormID> -- see AddTriggerForEffect
;         the weapon itself: sword dagger waraxe mace greatsword
;         battleaxe warhammer bow staff crossbow -- by the record's animation
;         type (a warhammer by its keyword; a bound weapon is the kind its
;         record is). A bash matches no weapon kind; `bash` is its
;         own type, any weapon or shield swung as one.
; THE HQ: the panel's Combat page builds rows of its own under the
;         owner "HQ" at prio 5 -- one per weapon kind and magic type it has
;         on -- and while it is on the config's T rows stand down (unless its
;         "keep the config's rows" switch is set); rows registered here always
;         stand. Its gates apply to EVERY row of every owner: who a blow may
;         cut (the player, a follower, an essential or protected NPC, anyone
;         else), the health % above which no blow cuts (a registry `vulnhp`
;         on them outranks it), and its reset clocks. "HQ" is reserved like
;         "MCM": do not register rows under it.
; KINDS:  any  = every blow of that type
;         pct  = one blow of at least thr % of their max health
;         abs  = one blow of at least thr points
;         per  = every blow of that type, and the wound's SIZE is thr units
;         per point of damage (0 < thr <= 10), never under the row's own size,
;         never over 40. It works on blows, and on a magic type too, sized by
;         the damage the effect took over one element cooldown.
;         winpct / winabs = the damage of that type in the last `window`
;         seconds (default 6), measured on the tick; drain = thr cells per
;         second for `window` seconds after each apply of a matching effect
; FORMS:  bite slabx slaby slabz borex borey borez scatter layerz diagf diags
; SCOPE:  None = everyone; an actor = them alone.
; SIZE scales past the threshold: a blow at twice the threshold opens a wound
; up to twice the size (capped at three times). A `per` row's size is the
; damage's instead.
; PER SESSION: cleared at every launch, like the registry.

Int Function AddTrigger(String caller, Actor scope, String type, String kind, Float thr, \
        String form, Float size, Int depth, String parts = "-", String anchor = "-", \
        Bool nokill = false, Int prio = 0) Global
    {The short form: form, size, depth, parts, anchor, nokill; count 1, cells 34,
     budget 12, layers from depth, no sweep flag, kick 0, mark 0 -- what the
     hit path itself uses. Returns the row's id (> 0) for RemoveTrigger, or 0
     if the row was not written.}
    String nk = "-"
    If nokill
        nk = "nokill"
    EndIf
    Return AddTriggerEx(caller, scope, type, kind, thr, form + "|" + size + "|1|34|12|" + depth \
        + "|0|" + parts + "|" + anchor + "|-|0|0|" + nk, prio)
EndFunction

Int Function AddTriggerEx(String caller, Actor scope, String type, String kind, Float thr, \
        String columns, Int prio = 0, Float window = 0.0) Global
    {The whole column list as one '|'-separated string, in the W row's order:
       form|size|count|cells|budget|depth|layers|parts|anchor|sweep|kick|mark|nokill
     sweep is the literal `nosever` or `-`; nokill is `nokill` or `-`.
     window (seconds) is for the winpct/winabs kinds (default 6) and drain
     (default 8: thr cells per second for that long after each apply).}
    If caller == "" || type == "" || kind == "" || columns == ""
        Return 0
    EndIf
    If window <= 0.0
        If kind == "drain"
            window = 8.0
        ElseIf kind == "winpct" || kind == "winabs"
            window = 6.0
        EndIf
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.triggers.txt"
    String cur = MiscUtil.ReadFromFile(path)
    String[] lines = StringUtil.Split(cur, "\n")
    Int best = 0
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If f.Length >= 2 && (f[1] as Int) > best
                best = f[1] as Int
            EndIf
        EndIf
        i += 1
    EndWhile
    Int id = best + 1
    String sc = "0"
    If scope
        sc = "" + scope.GetFormID()
    EndIf
    If cur != "" && StringUtil.Find(cur, "\n", StringUtil.GetLength(cur) - 1) < 0
        cur += "\n"
    EndIf
    cur += caller + "|" + id + "|" + sc + "|" + type + "|" + kind + "|" + thr + "|" + window + "|" + columns + "|" + prio + "\n"
    MiscUtil.WriteToFile(path, cur, false, false)
    Return id
EndFunction

Function RemoveTrigger(String caller, Int id) Global
    {Take one of your rows back. Other callers' rows stand.}
    If caller == "" || id <= 0
        Return
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.triggers.txt"
    String[] lines = StringUtil.Split(MiscUtil.ReadFromFile(path), "\n")
    String out = ""
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If !(f.Length >= 2 && f[0] == caller && (f[1] as Int) == id)
                out += lines[i] + "\n"
            EndIf
        EndIf
        i += 1
    EndWhile
    MiscUtil.WriteToFile(path, out, false, false)
EndFunction

Function ClearTriggers(String caller) Global
    {Take every one of your rows back -- what a mod does when its scene ends.}
    If caller == ""
        Return
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.triggers.txt"
    String[] lines = StringUtil.Split(MiscUtil.ReadFromFile(path), "\n")
    String out = ""
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If !(f.Length >= 1 && f[0] == caller)
                out += lines[i] + "\n"
            EndIf
        EndIf
        i += 1
    EndWhile
    MiscUtil.WriteToFile(path, out, false, false)
EndFunction

String Function Triggers(String caller) Global
    {Your rows as the file holds them, one per line, for a log.}
    String[] lines = StringUtil.Split(MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.triggers.txt"), "\n")
    String out = ""
    Int i = 0
    While i < lines.Length
        If lines[i] != "" && (caller == "" || StringUtil.Find(lines[i], caller + "|") == 0)
            out += lines[i] + "\n"
        EndIf
        i += 1
    EndWhile
    Return out
EndFunction

; ---- commands -----------------------------------------------------
;
; A command is one file, FleshCore.cmd<N>.txt, holding
;     <ticket>|<verb>|<caller>|<args...>\n#
; written whole in one call; the engine reads it on its next tick (100 ms),
; deletes it, runs it on the game's thread, and answers with FL_Done -- sent
; from the command's target (or this quest for a global verb):
;     FL_Done | sender = target | numArg = ticket | strArg = verb|caller|result|detail
; RESULTS: 0 done · 1 immune · 2 no body · 3 nothing to take · 4 expired
; (target gone, not armed) · 5 cancelled · 6 unsupported form · 7 bad
; argument · 8 not found. Every function here returns the ticket (> 0) it
; will be answered on, or a negative code for what it could see itself:
; -1 bad caller · -2 not installed · -4 no target · -5 bad name · -6 range.
;
; THE COLUMN LIST every wound verb takes, in the W row's order:
;     form|size|count|cells|budget|depth|layers|parts|anchor|sweep|kick|mark|nokill
; sweep is `nosever` or `-`; nokill is `nokill` or `-`; parts is a comma list
; of part names or `-`; anchor is centre/front/back/top/bottom/left/right
; (`aim` means centre for `wound`: there is no aim to consult).

Int Function NextTicket() Global
    Int t = StorageUtil.AdjustIntValue(None, "FC_ticket", 1)
    If t <= 0 || t > 16000000
        StorageUtil.SetIntValue(None, "FC_ticket", 1)
        t = 1
    EndIf
    Return t
EndFunction

Int Function Send(String verb, String caller, String args) Global
    {Write one command file. Returns the ticket.}
    If !IsInstalled()
        Return -2
    EndIf
    If caller == "" || StringUtil.GetLength(caller) > 24 || caller == "-"
        Return -1
    EndIf
    Int t = NextTicket()
    Int n = StorageUtil.AdjustIntValue(None, "FC_cmdseq", 1)
    String line = t + "|" + verb + "|" + caller
    If args != ""
        line += "|" + args
    EndIf
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.cmd" + n + ".txt", line + "\n#", false, false)
    Return t
EndFunction

String Function Columns(String form, Float size, Int depth, String parts = "-", String anchor = "-", \
        Bool nokill = false, Int count = 1, Int cells = 34, Int budget = 12, Int layers = 0, \
        Bool nosever = false, Int kick = 0, Int mark = 0) Global
    {Build the thirteen-column list from named arguments.}
    String sw = "-"
    If nosever
        sw = "nosever"
    EndIf
    String nk = "-"
    If nokill
        nk = "nokill"
    EndIf
    If parts == ""
        parts = "-"
    EndIf
    If anchor == ""
        anchor = "-"
    EndIf
    Return form + "|" + size + "|" + count + "|" + cells + "|" + budget + "|" + depth + "|" + layers \
        + "|" + parts + "|" + anchor + "|" + sw + "|" + kick + "|" + mark + "|" + nk
EndFunction

Int Function WoundPart(String caller, Actor akActor, String form, Float size, Int depth, String part, \
        String anchor = "centre", Bool nokill = false) Global
    {Open a wound on ONE named part of the body, at an anchor of that part, with no
     record in the plugin. Answered by FL_Done and FL_Wounded.}
    If !akActor
        Return -4
    EndIf
    Return WoundEx(caller, akActor, Columns(form, size, depth, part, anchor, nokill))
EndFunction

Int Function WoundEx(String caller, Actor akActor, String columns) Global
    {The whole column list. `aim` as the anchor is read as centre.}
    If !akActor
        Return -4
    EndIf
    If StringUtil.Split(columns, "|").Length != 13
        Return -6
    EndIf
    Return Send("wound", caller, akActor.GetFormID() + "|" + columns)
EndFunction

Int Function WoundAt(String caller, Actor akActor, Float x, Float y, Float z, String columns) Global
    {A wound at a WORLD point: it lands on their nearest flesh to it. The anchor
     column may be aim (`-`).}
    If !akActor
        Return -4
    EndIf
    If StringUtil.Split(columns, "|").Length != 13
        Return -6
    EndIf
    Return Send("woundat", caller, akActor.GetFormID() + "|" + x + "|" + y + "|" + z + "|" + columns)
EndFunction

Int Function Detonate(String caller, Actor akActor, Bool altMark = false) Global
    {A fixed detonate wound (size 12, depth 3, at the centre), as a command, with optional alt mark.}
    Int mark = 1
    If altMark
        mark = 2
    EndIf
    If !akActor
        Return -4
    EndIf
    Return WoundEx(caller, akActor, Columns("detonate", 12.0, 3, "-", "centre", false, 1, 34, 20, 0, false, 0, mark))
EndFunction

Int Function RestoreParts(String caller, Actor akActor, String parts = "all", Int layermask = 0) Global
    {Put parts of them back: `all` with layermask 0 makes the body whole through the
     same un-cut a Restore spell runs; anything else clears the named layers
     (bit 0 skin, 1 fat, 2 muscle, 3 bone; 0 = every layer) of the named
     parts and redraws. A dead target is not revived by this -- Revive() is.}
    If !akActor
        Return -4
    EndIf
    If parts == ""
        parts = "all"
    EndIf
    Return Send("restore", caller, akActor.GetFormID() + "|" + parts + "|" + layermask)
EndFunction

Int Function Heal(String caller, Actor akActor, Float cellsPerSec = 4.0) Global
    {Regrow them over time, innermost layer first, from living flesh outward.
     FL_Restored and FL_Done when they are whole.}
    If !akActor
        Return -4
    EndIf
    If cellsPerSec <= 0.0
        Return -6
    EndIf
    Return Send("heal", caller, akActor.GetFormID() + "|" + cellsPerSec)
EndFunction

Int Function StopHeal(String caller, Actor akActor) Global
    If !akActor
        Return -4
    EndIf
    Return Send("stopheal", caller, "" + akActor.GetFormID())
EndFunction

Int Function Drain(String caller, Actor akActor, Float cellsPerSec = 4.0, Float seconds = 30.0, \
        String parts = "-", String anchor = "-") Global
    {A FEED: take cellsPerSec cells a second from them, as one
     bite a second at the anchor of the named parts ('-' = anywhere; a part
     name or the API's key, comma-separated), for up to seconds -- or until
     StopDrain. Answered by FL_Done at once (0 armed, 1 immune, 4 not loaded,
     7 a part name the engine does not know); every bite raises FL_Wounded
     with origin 4 (drain). A second Drain on them re-arms the same feed. A registered
     scalar on them scales the rate as it scales a blow. cellsPerSec 0.1..100,
     seconds 0.5..600. What the Voxel Drain spell does, by command.}
    If !akActor
        Return -4
    EndIf
    If cellsPerSec < 0.1 || cellsPerSec > 100.0 || seconds < 0.5 || seconds > 600.0
        Return -6
    EndIf
    If parts == ""
        parts = "-"
    EndIf
    If anchor == ""
        anchor = "-"
    EndIf
    Return Send("drain", caller, akActor.GetFormID() + "|" + cellsPerSec + "|" + seconds + "|" + parts + "|" + anchor)
EndFunction

Int Function StopDrain(String caller, Actor akActor) Global
    {End the feed on them now, whoever armed it. FL_Done 0 stopped, 8 no
     drain on them.}
    If !akActor
        Return -4
    EndIf
    Return Send("stopdrain", caller, "" + akActor.GetFormID())
EndFunction

Int Function Vortex(String caller, ObjectReference marker, Float radius, Float seconds, Float wavesPerSec, String columns) Global
    {A sphere around a marker that wounds every built body inside it once per
     wave until it expires. The marker may move. Sixteen at most. FL_Done
     (result 0, detail = waves) when it expires; EndVortex answers 5.}
    If !marker
        Return -4
    EndIf
    If radius < 16.0 || radius > 4096.0 || seconds < 0.5 || seconds > 600.0 || wavesPerSec < 0.1 || wavesPerSec > 20.0
        Return -6
    EndIf
    If StringUtil.Split(columns, "|").Length != 13
        Return -6
    EndIf
    Return Send("vortex", caller, marker.GetFormID() + "|" + radius + "|" + seconds + "|" + wavesPerSec + "|" + columns)
EndFunction

Int Function EndVortex(String caller, Int ticket) Global
    If ticket <= 0
        Return -6
    EndIf
    Return Send("endvortex", caller, "" + ticket)
EndFunction

Int Function AskState(String caller, Actor akActor) Global
    {Ask the engine about them NOW. Answered by
       FL_State | sender = them | numArg = ticket
                | strArg = alive|partsLostMask|partsRemain|layersGone|lastSeq|origin
     alive 1 means the engine holds a lattice for them; 0 is "never built or
     forgotten", which BodyState() cannot tell from "whole".}
    If !akActor
        Return -4
    EndIf
    Return Send("state", caller, "" + akActor.GetFormID())
EndFunction

Int Function Ping(String caller) Global
    {Answered by FL_Ping from this quest with the ticket, when the engine's
     hook thread is alive and its task queue is being run.}
    Return Send("ping", caller, "")
EndFunction

; ---- readers ------------------------------------------------------

String Function BodyState(Actor akActor) Global
    {The last FL_Wounded payload naming them, verbatim, kept by the watcher;
     "" for a target never reported or restored since. Ask AskState() for a
     fresh answer from the engine (AskState).}
    If !akActor
        Return ""
    EndIf
    Return StorageUtil.GetStringValue(akActor, "FC_state", "")
EndFunction

Int Function PartRemaining(String partsRemain, String part) Global
    {From an FL_Wounded / FL_State partsRemain column ("lthigh:40,head:0"),
     the attachment percentage of one part; 100 when it is not listed.}
    If partsRemain == "" || part == ""
        Return 100
    EndIf
    String[] f = StringUtil.Split(partsRemain, ",")
    Int i = 0
    While i < f.Length
        String[] kv = StringUtil.Split(f[i], ":")
        If kv.Length == 2 && kv[0] == part
            Return kv[1] as Int
        EndIf
        i += 1
    EndWhile
    Return 100
EndFunction

Int Function PartBit(String part) Global
    {The bit a part occupies in partsLostMask / partsTouched masks: head 1,
     chest 2, abdomen 3, lupperarm 4, lforearm 5, lhand 6, rupperarm 7,
     rforearm 8, rhand 9, lthigh 10, lcalf 11, lfoot 12, rthigh 13, rcalf 14,
     rfoot 15; 0 for a name that is not a part. Masks are 1 << bit.}
    String[] names = new String[16]
    names[1] = "head"
    names[2] = "chest"
    names[3] = "abdomen"
    names[4] = "lupperarm"
    names[5] = "lforearm"
    names[6] = "lhand"
    names[7] = "rupperarm"
    names[8] = "rforearm"
    names[9] = "rhand"
    names[10] = "lthigh"
    names[11] = "lcalf"
    names[12] = "lfoot"
    names[13] = "rthigh"
    names[14] = "rcalf"
    names[15] = "rfoot"
    Int i = 1
    While i < 16
        If names[i] == part
            Return i
        EndIf
        i += 1
    EndWhile
    Return 0
EndFunction

Bool Function PartInMask(Int mask, String part) Global
    Int b = PartBit(part)
    If b <= 0
        Return false
    EndIf
    Return Math.LogicalAnd(mask, Math.LeftShift(1, b)) != 0
EndFunction

String Function CodeName(Int code) Global
    {The name of a return code or an FL_Done result.}
    If code == 0
        Return "ok"
    ElseIf code == -1
        Return "E_CALLER"
    ElseIf code == -2
        Return "E_NOTREADY"
    ElseIf code == -3
        Return "E_NOTARMED"
    ElseIf code == -4
        Return "E_TARGET"
    ElseIf code == -5
        Return "E_NAME"
    ElseIf code == -6
        Return "E_RANGE"
    ElseIf code == -7
        Return "E_FULL"
    ElseIf code == -8
        Return "E_NOTFOUND"
    ElseIf code > 0
        Return "ticket"
    EndIf
    Return "?"
EndFunction

Int Function Diagnose(Actor akActor) Global
    {One Debug.Trace line with everything a consumer needs to know about them
     and the running game, and the first failing code (0 when nothing fails).}
    String line = "[FleshCore] Diagnose: installed=" + IsInstalled() + " armed=" + CoreActive() \
        + " version=" + VersionString() + " features=" + Features()
    Int code = 0
    If !IsInstalled()
        code = -2
    ElseIf !CoreActive()
        code = -3
    EndIf
    If akActor
        line += " actor=" + akActor + " targetable=" + Targetable(akActor) + " whyrefused=" + WhyRefused(akActor) \
            + " whynot=" + WhyNot(akActor) + " immune=" + GetInt(akActor, "immune") + " vulnhp=" + GetInt(akActor, "vulnhp") \
            + " nokill=" + NoKill(akActor) + " state=" + BodyState(akActor)
        If code == 0 && !Targetable(akActor)
            code = -4
        EndIf
    EndIf
    Debug.Trace(line)
    Return code
EndFunction

; ---- scalars ------------------------------------
;
; One number per actor, the PRODUCT of every caller's contribution (each
; 0.1..10), default 1. The engine divides every trigger threshold by it and
; scales what a BLOW or a DRAIN does to them (size, budget, depth); spells,
; commands, vortexes and scene actions are deliberate and never scaled --
; a mod that wants its own command scaled reads EffectiveScalar and
; multiplies its own columns. Who computes the factor is you: a belt is
; worth 1.3 to one mod and 2.0 to another, and FleshCore has no opinion.
;     FleshCore.scalars.txt      <formID>|<factor>|<caller>

Function SetScalar(Actor akActor, Float factor, String caller) Global
    If !akActor || caller == "" || factor < 0.1 || factor > 10.0
        Return
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.scalars.txt"
    String id = "" + akActor.GetFormID()
    String out = ScalarsWithout(MiscUtil.ReadFromFile(path), id, caller)
    out += id + "|" + factor + "|" + caller + "\n"
    MiscUtil.WriteToFile(path, out, false, false)
EndFunction

Function ClearScalar(Actor akActor, String caller) Global
    If !akActor || caller == ""
        Return
    EndIf
    String path = "Data/SKSE/Plugins/FleshCore.scalars.txt"
    MiscUtil.WriteToFile(path, ScalarsWithout(MiscUtil.ReadFromFile(path), "" + akActor.GetFormID(), caller), false, false)
EndFunction

String Function ScalarsWithout(String content, String id, String caller) Global
    String[] lines = StringUtil.Split(content, "\n")
    String out = ""
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If !(f.Length >= 3 && f[0] == id && f[2] == caller)
                out += lines[i] + "\n"
            EndIf
        EndIf
        i += 1
    EndWhile
    Return out
EndFunction

Float Function EffectiveScalar(Actor akActor) Global
    {The product in force for them, clamped 0.1..10; 1.0 when nobody set one.}
    If !akActor
        Return 1.0
    EndIf
    String id = "" + akActor.GetFormID()
    String[] lines = StringUtil.Split(MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.scalars.txt"), "\n")
    Float p = 1.0
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If f.Length >= 3 && f[0] == id
                Float v = f[1] as Float
                If v >= 0.1 && v <= 10.0
                    p *= v
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    If p < 0.1
        p = 0.1
    ElseIf p > 10.0
        p = 10.0
    EndIf
    Return p
EndFunction

String Function ScalarContributors(Actor akActor) Global
    {"caller:factor" for every contribution on them, comma-separated.}
    If !akActor
        Return ""
    EndIf
    String id = "" + akActor.GetFormID()
    String[] lines = StringUtil.Split(MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.scalars.txt"), "\n")
    String out = ""
    Int i = 0
    While i < lines.Length
        If lines[i] != ""
            String[] f = StringUtil.Split(lines[i], "|")
            If f.Length >= 3 && f[0] == id
                If out != ""
                    out += ","
                EndIf
                out += f[2] + ":" + f[1]
            EndIf
        EndIf
        i += 1
    EndWhile
    Return out
EndFunction

; ---- typed magic rows ---------------------------------------------

Int Function AddTriggerForEffect(String caller, Actor scope, MagicEffect akEffect, String kind, Float thr, \
        String columns, Int prio = 0) Global
    {A row against ONE magic effect, by its runtime FormID (written for you as
     `mgef:<id>`). Fires when a hostile apply of that effect lands on a target
     the engine knows. `any` fires on the apply; `pct`/`abs` are measured
     from their health 300 ms later; `drain` arms thr cells/s for the row's
     window seconds (8 here; AddTriggerEx takes another).}
    If !akEffect
        Return 0
    EndIf
    Return AddTriggerEx(caller, scope, "mgef:" + akEffect.GetFormID(), kind, thr, columns, prio)
EndFunction

Int Function AddTriggerForKeyword(String caller, Actor scope, Keyword akKeyword, String kind, Float thr, \
        String columns, Int prio = 0) Global
    {A row against any weapon OR effect carrying a keyword, by editor id.}
    If !akKeyword
        Return 0
    EndIf
    Return AddTriggerEx(caller, scope, "kw:" + akKeyword.GetString(), kind, thr, columns, prio)
EndFunction

; ---- effective readers ---------------------------

Int Function EffectiveVulnHP(Actor akActor) Global
    {The vulnhp threshold in force for them, or 100 (always vulnerable).}
    Int v = GetInt(akActor, "vulnhp")
    If v <= 0 || v > 100
        Return 100
    EndIf
    Return v
EndFunction

Bool Function EffectiveImmune(Actor akActor) Global
    Return GetInt(akActor, "immune") > 0
EndFunction

Bool Function EffectiveNoLethal(Actor akActor, String origin) Global
    {Whether a wound from this origin (spell/hit/command/vortex/drain/scene)
     would be unable to kill them right now: the never-kill list, then the
     NL row's origin flags (spell, hit) as the config carries them, with the
     player exemption. Scene actions are commands and are never suppressed
     by origin -- a scene mod uses SetNoKill.}
    If !akActor
        Return false
    EndIf
    If NoKill(akActor)
        Return true
    EndIf
    Bool isPlayer = akActor == Game.GetPlayer()
    String cfg = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.cfg.txt")
    Int at = StringUtil.Find(cfg, "\nNL\t")
    If at < 0
        Return false
    EndIf
    String rest = StringUtil.SubString(cfg, at + 4, 32)
    String[] f = StringUtil.Split(StringUtil.Split(rest, "\n")[0], "\t")
    If f.Length < 3
        Return false
    EndIf
    If isPlayer && (f[2] as Int) == 0
        Return false
    EndIf
    If origin == "spell"
        Return (f[0] as Int) != 0
    ElseIf origin == "hit"
        Return (f[1] as Int) != 0
    EndIf
    Return false
EndFunction

Int Function EffectiveLimbsToDie(Actor akActor) Global
    Int v = GetInt(akActor, "limbstodie")
    If v < 1
        Return 1
    EndIf
    Return v
EndFunction

Int Function EffectiveHeadFatal(Actor akActor) Global
    {1 fatal, 0 not, -1 the panel's setting (no registry rule).}
    Int v = GetInt(akActor, "headfatal")
    If v < 0
        Return -1
    EndIf
    Return v
EndFunction

Int Function EffectiveTrunkFatal(Actor akActor) Global
    Int v = GetInt(akActor, "trunkfatal")
    If v < 0
        Return -1
    EndIf
    Return v
EndFunction

Int Function EffectiveLimbFatal(Actor akActor) Global
    Int v = GetInt(akActor, "limbfatal")
    If v < 0
        Return -1
    EndIf
    Return v
EndFunction

; ---- scene rules and effect rules -------
;
; Both live in StorageUtil on the hooks quest (FleshCore.esp 0x948) and are
; read by the scene script / FL_Effects there. Per save, not per session: a rule
; you add stays until you remove it; the abilities plugin re-registers its
; three on every load through FleshCore_GameReload, which is the pattern.

Quest Function HooksQuest() Global
    Return Game.GetFormFromFile(0x00000948, "FleshCore.esp") as Quest
EndFunction

Int Function NextRuleId() Global
    Quest q = HooksQuest()
    If !q
        Return 0
    EndIf
    Return StorageUtil.AdjustIntValue(q, "FC_ruleseq", 1)
EndFunction

Int Function AddSceneRule(String caller, String when, String partner, String tags, String target, String action, \
        Int n = 1, Float withinSec = 60.0, Int prio = 0, String columns = "") Global
    {when: end | stage | stageN. partner: any | creature | npc | player |
     race:<name>. tags: "" or a comma list the animation must carry. target:
     victim | player | nonplayer | all | random. action: a wound form name,
     detonate, the alt burst or none; `columns` (thirteen) overrides the
     action's default wound. Returns the rule id (> 0), or a negative code.}
    If caller == "" || StringUtil.GetLength(caller) > 24
        Return -1
    EndIf
    Quest q = HooksQuest()
    If !q
        Return -2
    EndIf
    If !(when == "end" || when == "stage" || when == "stageN")
        Return -5
    EndIf
    If !(partner == "any" || partner == "creature" || partner == "npc" || partner == "player" || StringUtil.Find(partner, "race:") == 0)
        Return -5
    EndIf
    If !(target == "victim" || target == "player" || target == "nonplayer" || target == "all" || target == "random")
        Return -5
    EndIf
    If columns != "" && StringUtil.Split(columns, "|").Length != 13
        Return -6
    EndIf
    If n < 1 || withinSec < 1.0
        Return -6
    EndIf
    If tags == ""
        tags = "-"
    EndIf
    If columns == ""
        columns = "-"
    EndIf
    Int id = NextRuleId()
    StorageUtil.StringListAdd(q, "FC_scene_rules", caller + "|" + id + "|" + when + "|" + partner + "|" + tags + "|" + target \
        + "|" + action + "|" + n + "|" + withinSec + "|" + prio + "|" + columns, false)
    Return id
EndFunction

Function RemoveSceneRule(String caller, Int id) Global
    Quest q = HooksQuest()
    If !q
        Return
    EndIf
    Int i = StorageUtil.StringListCount(q, "FC_scene_rules") - 1
    While i >= 0
        String[] f = StringUtil.Split(StorageUtil.StringListGet(q, "FC_scene_rules", i), "|")
        If f.Length >= 2 && f[0] == caller && (f[1] as Int) == id
            StorageUtil.StringListRemoveAt(q, "FC_scene_rules", i)
        EndIf
        i -= 1
    EndWhile
EndFunction

Function ClearSceneRules(String caller) Global
    Quest q = HooksQuest()
    If !q
        Return
    EndIf
    Int i = StorageUtil.StringListCount(q, "FC_scene_rules") - 1
    While i >= 0
        String[] f = StringUtil.Split(StorageUtil.StringListGet(q, "FC_scene_rules", i), "|")
        If f.Length >= 1 && f[0] == caller
            StorageUtil.StringListRemoveAt(q, "FC_scene_rules", i)
        EndIf
        i -= 1
    EndWhile
EndFunction

Int Function AddEffectRule(String caller, String part, Int maxRemainPct, Spell ability, Int prio = 0) Global
    {While `part` (a part name, or leg / arm / head / trunk) is attached at
     LESS than maxRemainPct, `ability` is on them; it comes off above it and
     on FL_Restored. Returns the rule id (> 0) or a negative code.}
    If caller == "" || StringUtil.GetLength(caller) > 24
        Return -1
    EndIf
    If !ability
        Return -4
    EndIf
    If maxRemainPct < 1 || maxRemainPct > 100 || part == ""
        Return -6
    EndIf
    Quest q = HooksQuest()
    If !q
        Return -2
    EndIf
    Int id = NextRuleId()
    StorageUtil.StringListAdd(q, "FC_effect_rules", caller + "|" + id + "|" + part + "|" + maxRemainPct + "|" + prio, false)
    StorageUtil.SetFormValue(q, "FC_effect_spell_" + id, ability)
    Return id
EndFunction

Function RemoveEffectRule(String caller, Int id) Global
    Quest q = HooksQuest()
    If !q
        Return
    EndIf
    Int i = StorageUtil.StringListCount(q, "FC_effect_rules") - 1
    While i >= 0
        String[] f = StringUtil.Split(StorageUtil.StringListGet(q, "FC_effect_rules", i), "|")
        If f.Length >= 2 && f[0] == caller && (f[1] as Int) == id
            StorageUtil.StringListRemoveAt(q, "FC_effect_rules", i)
            StorageUtil.UnsetFormValue(q, "FC_effect_spell_" + id)
        EndIf
        i -= 1
    EndWhile
EndFunction

Function ClearEffectRules(String caller) Global
    Quest q = HooksQuest()
    If !q
        Return
    EndIf
    Int i = StorageUtil.StringListCount(q, "FC_effect_rules") - 1
    While i >= 0
        String[] f = StringUtil.Split(StorageUtil.StringListGet(q, "FC_effect_rules", i), "|")
        If f.Length >= 2 && f[0] == caller
            StorageUtil.UnsetFormValue(q, "FC_effect_spell_" + f[1])
            StorageUtil.StringListRemoveAt(q, "FC_effect_rules", i)
        EndIf
        i -= 1
    EndWhile
EndFunction

String Function SceneRules(String caller = "") Global
    Quest q = HooksQuest()
    If !q
        Return ""
    EndIf
    String out = ""
    Int n = StorageUtil.StringListCount(q, "FC_scene_rules")
    Int i = 0
    While i < n
        String r = StorageUtil.StringListGet(q, "FC_scene_rules", i)
        If caller == "" || StringUtil.Find(r, caller + "|") == 0
            out += r + "\n"
        EndIf
        i += 1
    EndWhile
    Return out
EndFunction

; ---- shards --------------------------------------
;
; Every piece FleshCore places now carries its provenance under FC_prov:
;     <victimId>|<part>|<layers>|<cells>|<section>
; (part as the lattice's number, see PartBit; layers a mask; section 1 for
; a severed section). Activation is off unless a caller asks; when it is
; on, touching a piece sends FL_ShardActivated from the actor who touched
; it, and the CONDITION IS YOURS -- werewolf form, a ring, a faction -- and
; if you want the piece you call ConsumeShard, which sends FL_ShardConsumed
; and runs the piece's own undertaker.

Function EnableShardActivation(String caller, Bool on) Global
    {Per caller: a vote. The pieces can be activated while any caller has
     voted yes. A piece launched before the first vote stays blocked for its
     lifetime.}
    If caller == ""
        Return
    EndIf
    Bool had = StorageUtil.StringListHas(None, "FC_shardact_callers", caller)
    If on && !had
        StorageUtil.StringListAdd(None, "FC_shardact_callers", caller, false)
    ElseIf !on && had
        StorageUtil.StringListRemove(None, "FC_shardact_callers", caller, true)
    EndIf
    StorageUtil.SetIntValue(None, "FC_shardact", StorageUtil.StringListCount(None, "FC_shardact_callers"))
EndFunction

Bool Function EffectiveShardActivation() Global
    Return StorageUtil.GetIntValue(None, "FC_shardact", 0) > 0
EndFunction

String Function ShardProvenance(ObjectReference akShard) Global
    {"" for a piece that is not FleshCore's, or that was placed by an engine
     too old to record provenance -- the two cannot be told apart.}
    If !akShard
        Return ""
    EndIf
    Return StorageUtil.GetStringValue(akShard, "FC_prov", "")
EndFunction

Actor Function ShardVictim(ObjectReference akShard) Global
    String p = ShardProvenance(akShard)
    If p == ""
        Return None
    EndIf
    Return Game.GetFormEx(StringUtil.Split(p, "|")[0] as Int) as Actor
EndFunction

Int Function ShardPart(ObjectReference akShard) Global
    {The lattice part number (PartBit's numbering), 0 unknown.}
    String p = ShardProvenance(akShard)
    If p == ""
        Return 0
    EndIf
    String[] f = StringUtil.Split(p, "|")
    If f.Length < 2
        Return 0
    EndIf
    Return StringUtil.Split(f[1], ":")[0] as Int
EndFunction

Int Function ShardLayers(ObjectReference akShard) Global
    String p = ShardProvenance(akShard)
    If p == ""
        Return 0
    EndIf
    String[] f = StringUtil.Split(p, "|")
    If f.Length < 2
        Return 0
    EndIf
    String[] g = StringUtil.Split(f[1], ":")
    If g.Length < 2
        Return 0
    EndIf
    Return g[1] as Int
EndFunction

Int Function ShardCells(ObjectReference akShard) Global
    String p = ShardProvenance(akShard)
    If p == ""
        Return 0
    EndIf
    String[] f = StringUtil.Split(p, "|")
    If f.Length < 2
        Return 0
    EndIf
    String[] g = StringUtil.Split(f[1], ":")
    If g.Length < 3
        Return 0
    EndIf
    Return g[2] as Int
EndFunction

Bool Function ShardIsSection(ObjectReference akShard) Global
    String p = ShardProvenance(akShard)
    If p == ""
        Return false
    EndIf
    String[] f = StringUtil.Split(p, "|")
    If f.Length < 2
        Return false
    EndIf
    String[] g = StringUtil.Split(f[1], ":")
    If g.Length < 4
        Return false
    EndIf
    Return (g[3] as Int) != 0
EndFunction

Int Function ConsumeShard(String caller, ObjectReference akShard, Actor akBy) Global
    {Take the piece: validates it is FleshCore's and not already consumed,
     sends FL_ShardConsumed from akBy (strArg shardId|victimId|part|layers|
     cells|section|caller), and runs the piece's own undertaker. 0 done,
     -4 not FleshCore's or already gone, -1 bad caller.}
    If caller == ""
        Return -1
    EndIf
    If !akShard || ShardProvenance(akShard) == "" || StorageUtil.GetIntValue(akShard, "FC_consumed", 0) != 0
        Return -4
    EndIf
    StorageUtil.SetIntValue(akShard, "FC_consumed", 1)
    String[] f = StringUtil.Split(ShardProvenance(akShard), "|")
    String rest = f[0]
    If f.Length >= 2
        String[] g = StringUtil.Split(f[1], ":")
        Int i = 0
        While i < g.Length
            rest += "|" + g[i]
            i += 1
        EndWhile
    EndIf
    If akBy
        akBy.SendModEvent("FL_ShardConsumed", akShard.GetFormID() + "|" + rest + "|" + caller, 0.0)
    EndIf
    FL_Chunk ch = akShard as FL_Chunk
    If ch
        ch.Consume()
    Else
        akShard.Disable(true)
        akShard.Delete()
    EndIf
    Return 0
EndFunction

ObjectReference[] Function PlacedShards() Global
    {The pieces the watcher holds that have 3D, up to 32 (its ring).}
    FL_Watch w = Game.GetFormFromFile(0x00000835, "FleshCore.esp") as FL_Watch
    If !w
        Return None
    EndIf
    Return w.LiveShards()
EndFunction

; ---- whynot --------------------------------------------------------

String Function WhyNot(Actor akActor) Global
    {Why FleshCore would not wound this actor right now -- one word, with the
     deciding value after a colon where there is one. Resolved in the order
     the engine's own paths test it. Permanent words; new ones may be added.
       ok            they would be wounded
       noplugin      FleshCore.esp is not loaded
       notarmed      the engine has not armed yet this session
       ineligible:N  WhyRefused's own 1 no base / 2 race or child / 3 no sex
                     (the engine's refusal list is this same test, written down)
       immune:C      a mod's registry rule, C the caller
       vulnhp:N      their health is above N %, the registry's threshold
       nobody        they are eligible but the engine has not built them yet
     A wound on a `nobody` still lands -- the engine builds them on the first
     blow -- so it is a fact about cost, not about outcome.}
    If !akActor
        Return "ineligible:1"
    EndIf
    If !IsInstalled()
        Return "noplugin"
    EndIf
    If !CoreActive()
        Return "notarmed"
    EndIf
    Int r = WhyRefused(akActor)
    If r != 0
        Return "ineligible:" + r
    EndIf
    String id = "" + akActor.GetFormID()
    String who = ""
    If Winner(akActor, "immune", who) > 0
        Return "immune:" + who
    EndIf
    Int vh = GetInt(akActor, "vulnhp")
    If vh > 0 && akActor.GetActorValuePercentage("Health") * 100.0 > (vh as Float)
        Return "vulnhp:" + vh
    EndIf
    If StringUtil.Find("\n" + MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.bodies.txt") + "\n", "\n" + id + "\n") < 0
        Return "nobody"
    EndIf
    Return "ok"
EndFunction

; ---- reading events -------------------------------------------------------

String Function Field(String s, Int n) Global
    {Column n (from 0) of a '|'-separated payload, or "" past the end. Use
     this rather than splitting yourself: a payload only ever grows at the
     end, so an index that works today works forever.}
    If s == "" || n < 0
        Return ""
    EndIf
    String[] parts = StringUtil.Split(s, "|")
    If n >= parts.Length
        Return ""
    EndIf
    Return parts[n]
EndFunction

; ---- combat presets & out-of-combat layer/armour tester ------------

Int Function ApplyPreset(String caller, Int presetId) Global
    {Apply a Combat Intensity level from 0 (Disabled) through 50 (Finishing Blows)
     to 100 (Gorefest). Smoothly scales combat voxelisation likelihood and
     dismemberment non-survivability.}
    If presetId < 0 || presetId > 100
        Return -6
    EndIf
    Return Send("preset", caller, "" + presetId)
EndFunction

Int Function TestStrike(String caller, String targetSpec = "crosshair", String partName = "chest", \
        String family = "weapon", Float radius = 11.0) Global
    {Fire a non-hostile out-of-combat test strike against a specific body patch
     to inspect armour detection and progressive layer peeling (Armour -> Skin ->
     Flesh -> Bone) without aggroing or killing the target. Answered by
     FL_TestReport (strArg = human-readable report) and FL_Done.}
    If targetSpec == ""
        targetSpec = "crosshair"
    EndIf
    If partName == ""
        partName = "chest"
    EndIf
    If family == ""
        family = "weapon"
    EndIf
    If radius < 4.0
        radius = 4.0
    ElseIf radius > 30.0
        radius = 30.0
    EndIf
    Return Send("teststrike", caller, targetSpec + "|" + partName + "|" + family + "|" + radius)
EndFunction

Int Function TestRestore(String caller, String targetSpec = "crosshair") Global
    {Restore the out-of-combat test target's armour, skin, flesh, and bone.}
    If targetSpec == ""
        targetSpec = "crosshair"
    EndIf
    Return Send("testrestore", caller, targetSpec)
EndFunction

Function PlayVoice(String wavId, Actor speaker = None, Int baseVolPct = 100) Global
    {Play a pre-recorded .wav voice line from the configured voice directory
     asynchronously via FleshCore.dll's low-latency 3D stereo-panned audio channel, with
     3D distance attenuation, left/right stereo panning from `speaker` relative to the
     player's facing direction, and phoneme lip/jaw animation on `speaker`.}
    If wavId == ""
        Return
    EndIf
    Actor prevSpk = StorageUtil.GetFormValue(None, "FL_LastVoiceSpeaker") as Actor
    If prevSpk && prevSpk != speaker && prevSpk.Is3DLoaded()
        prevSpk.SetExpressionPhoneme(0, 0)
        prevSpk.SetExpressionPhoneme(1, 0)
        prevSpk.SetExpressionPhoneme(5, 0)
    EndIf
    Int vol = baseVolPct
    Int pan = 0
    If speaker
        Actor p = Game.GetPlayer()
        If p && speaker != p
            Float d = speaker.GetDistance(p)
            If d > 2600.0
                Return
            EndIf
            Float atten = 1.0
            If d > 250.0
                atten = 1.0 - ((d - 250.0) / 2350.0)
                If atten < 0.12
                    atten = 0.12
                EndIf
            EndIf
            Float dx = speaker.GetPositionX() - p.GetPositionX()
            Float dy = speaker.GetPositionY() - p.GetPositionY()
            Float horiz = Math.sqrt(dx * dx + dy * dy)
            If horiz > 15.0
                Float ang = p.GetAngleZ()
                Float rightDot = (dx * Math.cos(ang) - dy * Math.sin(ang)) / horiz
                Float fwdDot = (dx * Math.sin(ang) + dy * Math.cos(ang)) / horiz
                pan = (rightDot * 88.0) as Int
                If pan < -95
                    pan = -95
                ElseIf pan > 95
                    pan = 95
                EndIf
                If fwdDot < 0.0
                    atten = atten * (0.82 + 0.18 * (1.0 + fwdDot))
                EndIf
            EndIf
            vol = ((baseVolPct as Float) * atten) as Int
        EndIf
        If speaker != p && !speaker.IsDead() && speaker.Is3DLoaded()
            speaker.SetExpressionPhoneme(0, 55)
            speaker.SetExpressionPhoneme(1, 25)
            speaker.SetExpressionPhoneme(5, 25)
            StorageUtil.SetFormValue(None, "FL_LastVoiceSpeaker", speaker)
            StorageUtil.SetFloatValue(None, "FL_LastVoiceUntil", Utility.GetCurrentRealTime() + 7.5)
        EndIf
    EndIf
    If vol < 5
        vol = 5
    ElseIf vol > 200
        vol = 200
    EndIf
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.voice.txt", wavId + "|" + vol + "|" + pan, false, false)
EndFunction

Function StopVoice() Global
    {Immediately stop any playing pre-recorded voice line and reset speaker mouth phonemes.}
    Actor prevSpk = StorageUtil.GetFormValue(None, "FL_LastVoiceSpeaker") as Actor
    If prevSpk
        If prevSpk.Is3DLoaded()
            prevSpk.SetExpressionPhoneme(0, 0)
            prevSpk.SetExpressionPhoneme(1, 0)
            prevSpk.SetExpressionPhoneme(5, 0)
        EndIf
        StorageUtil.UnsetFormValue(None, "FL_LastVoiceSpeaker")
    EndIf
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.voice.txt", "STOP|0", false, false)
EndFunction


