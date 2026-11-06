Scriptname FL_Probe Hidden
{THE INSTRUMENT: read-only probes of what the engine loaded.

 Diagnostics: probes and sensors that show what the engine
 actually holds, beside what the plugin asks for.
 Nothing here changes behaviour; every function reads and writes a
 log line and returns.

 WHAT IT IS FOR. FleshCore.dressing.log can show Papyrus
 calling EquipItem many times while the engine attaches the addon only a few
 times: the equip happens and mostly does not take, and everything between
 those two facts is invisible from Papyrus. These probes read that gap directly, from inside
 the running engine, through SKSE's record API:

   Race.GetSkin()                 their race's skin armour
   Armor.GetNumArmorAddons()      its armature, as the ENGINE holds it
   ArmorAddon.GetNthAdditionalRace / GetNumAdditionalRaces
                                  the race list, live -- previously readable
                                  only out of the ESP bytes
   ArmorAddon.GetSlotMask()       the slot the addon really claims
   ArmorAddon.GetModelPath()      the mesh it really points at
   Actor.GetWornForm(slotMask)    what is ACTUALLY on biped slot 61 right now

 An offline reading of the plugin sees only the record
 bytes on disk. This checks all of it against what the engine loaded, which is
 the one place the two can disagree.

 CALLERS: only FL_Watch.psc calls into this file, and only under
 ProbeVerbose. Nothing else refers to it, it
 owns no state, and it holds no properties -- deliberately, so that it never
 touches the ESP.}

; Biped slot 61 is bit 31, and the mask is asked of the ENGINE rather than
; computed here. Actor.psc says so beside GetWornForm -- "use
; Armor.GetMaskForSlot() to generate appropriate slotMask" -- and it removes a
; whole class of mistake: writing the literal by hand is how this first failed
; to compile, because Papyrus's Int is signed 32-bit, -2147483648 is parsed as
; unary minus applied to a literal that overflows it, and the result comes back
; a Float.
Int Function Slot61() Global
    Return Armor.GetMaskForSlot(61)
EndFunction

String Function Hex(Int v) Global
    {Papyrus has no format specifier. Eight nibbles, high to low.}
    String digits = "0123456789ABCDEF"
    String out = ""
    Int i = 28
    While i >= 0
        Int nib = Math.LogicalAnd(Math.RightShift(v, i), 15)
        out += StringUtil.GetNthChar(digits, nib)
        i -= 4
    EndWhile
    Return out
EndFunction

Function Write(String line) Global
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.probe.log", line + "\n", true, false)
EndFunction

Function Say(String tag, String line) Global
    Write(Utility.GetCurrentRealTime() + " [" + tag + "] " + line)
EndFunction

; ---------------------------------------------------------------- the records
Function DumpArmour(String tag, Armor a, String label) Global
    {Every addon of one armour: its slot, its mesh, and every race it names.
     This is the chain that decides whether anything attaches at all.}
    If !a
        Say(tag, label + " = NONE")
        Return
    EndIf
    Int n = a.GetNumArmorAddons()
    Say(tag, label + " '" + a.GetName() + "' id=" + Hex(a.GetFormID()) \
        + " slotmask=" + Hex(a.GetSlotMask()) + " addons=" + n)
    Int i = 0
    While i < n
        ArmorAddon aa = a.GetNthArmorAddon(i)
        If aa
            Int nr = aa.GetNumAdditionalRaces()
            Say(tag, "    addon[" + i + "] id=" + Hex(aa.GetFormID()) \
                + " slot=" + Hex(aa.GetSlotMask()) + " races=" + nr \
                + " female='" + aa.GetModelPath(false, true) + "'")
            ; The race list is dumped in full only for FleshCore's own addons -- a vanilla
            ; skin armature is twenty-odd addons of twenty-odd races and would
            ; bury the answer in six hundred lines.
            If StringUtil.Find(aa.GetModelPath(false, true), "FleshCore") >= 0
                Int r = 0
                String names = ""
                While r < nr
                    Race rc = aa.GetNthAdditionalRace(r)
                    If rc
                        names += rc.GetName() + "|"
                    Else
                        names += "?|"
                    EndIf
                    r += 1
                EndWhile
                Say(tag, "       races: " + names)
            EndIf
        Else
            Say(tag, "    addon[" + i + "] NULL")
        EndIf
        i += 1
    EndWhile
EndFunction

Function Session(Armor interior) Global
    {Once per session: what the engine actually loaded for FleshCore's own records.}
    Write("")
    Say("SESSION", "==== FleshCore probe, realtime " + Utility.GetCurrentRealTime() + " ====")
    DumpArmour("SESSION", interior, "FL_Interior")
EndFunction

; ---------------------------------------------------------------- the actor
Function Snapshot(Actor a, Armor interior, String tag) Global
    {One line of everything that could stop them being dressed, plus the one
     question nothing has ever been able to answer: what is on slot 61.}
    If !a
        Say(tag, "actor NULL")
        Return
    EndIf
    ; ---- BOTH BASES, BECAUSE THE GATE AND THIS PROBE READ DIFFERENT ONES --
    ;
    ; Printing GetActorBase alone -- the EDITOR base, i.e. the template -- misleads,
    ; because FL_Wound.Targetable reads GetLeveledActorBase FIRST and falls back
    ; to the editor base. A refusal line could then show a template's placeholder
    ; race and sex (race='Fox' sex=0, say) as if the gate had seen them, while
    ; the base that actually failed never reaches the log.
    ;
    ; Both are printed, with IsPlayable, in exactly the order Targetable
    ; asks them -- so a GATE-not-targetable line says WHY on its own face
    ; instead of inviting the reader to assume.
    ActorBase lb = a.GetLeveledActorBase()
    ActorBase eb = a.GetActorBase()
    ActorBase ab = lb
    If !ab
        ab = eb
    EndIf
    String race = "?"
    Int sex = -1
    String play = "?"
    If ab
        Race rc = ab.GetRace()
        If rc
            race = rc.GetName()
            If rc.IsPlayable()
                play = "yes"
            Else
                play = "NO"
            EndIf
        EndIf
        sex = ab.GetSex()
    EndIf
    ; and the editor base beside it, so the two can be compared at a glance
    String erace = "-"
    Int esex = -1
    If eb
        Race erc = eb.GetRace()
        If erc
            erace = erc.GetName()
        EndIf
        esex = eb.GetSex()
    EndIf
    String basis = "levelled"
    If !lb
        basis = "EDITOR (no levelled base)"
    EndIf
    Form worn61 = a.GetWornForm(Slot61())
    String w61 = "NONE"
    If worn61
        w61 = "'" + worn61.GetName() + "' id=" + Hex(worn61.GetFormID())
        If interior && worn61 == interior as Form
            w61 += " <-- OURS"
        EndIf
    EndIf
    Armor body = a.GetEquippedArmorInSlot(32)
    String b32 = "NONE"
    If body
        b32 = "'" + body.GetName() + "' id=" + Hex(body.GetFormID())
    EndIf
    Int eq = 0
    If interior && a.IsEquipped(interior)
        eq = 1
    EndIf
    Int cnt = 0
    If interior
        cnt = a.GetItemCount(interior)
    EndIf
    Say(tag, "id=" + Hex(a.GetFormID()) + " '" + a.GetDisplayName() + "'" \
        + " race='" + race + "' sex=" + sex + " playable=" + play \
        + " [gate reads the " + basis + " base;" \
        + " editor base says race='" + erace + "' sex=" + esex + "]" \
        + " equipped=" + eq + " count=" + cnt \
        + " 3d=" + a.Is3DLoaded() + " dead=" + a.IsDead() \
        + " disabled=" + a.IsDisabled() \
        + " slot61=" + w61 + " slot32=" + b32)
EndFunction

Function Skin(Actor a, String tag) Global
    {Their race's skin armour and its whole armature. Heavy -- called ONCE per
     actor, the first time they are probed, and never again.}
    If !a
        Return
    EndIf
    ActorBase ab = a.GetActorBase()
    If !ab
        Return
    EndIf
    Race rc = ab.GetRace()
    If !rc
        Say(tag, "no race")
        Return
    EndIf
    Say(tag, "race '" + rc.GetName() + "' id=" + Hex(rc.GetFormID()))
    DumpArmour(tag, rc.GetSkin(), "  raceskin")
EndFunction
