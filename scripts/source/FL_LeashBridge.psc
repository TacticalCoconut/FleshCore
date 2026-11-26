Scriptname FL_LeashBridge Hidden
{The one script that calls Leash Framework (Leash.esm and its SKSE plugin).
 Global functions only, attached to no record: it loads only when called, and
 nothing calls it unless FL_GrinderSpells.ChainReady() said yes first.}

; ---- WHY THIS SCRIPT EXISTS ------------------------------------------------
;
; Leash Framework is a SOFT dependency of FleshCore. FleshCore.esp does not list
; Leash.esm as a master, and no other FleshCore script names a Leash Framework
; function. Every caller asks FL_GrinderSpells.ChainReady() first (Leash.esm is
; installed, its SKSE plugin loaded, and the load-time probe got an answer).
; Without Leash Framework nothing ever calls in here, so nothing is logged.
;
; Every chain made here is a world-position chain from a grinder to the neck of
; the one on the Grinder Hook. Every cut follows one fixed order, the one that
; kept Leash Framework 1.1.8 from crashing on rope cuts:
;   1. frame sync (Papyrus Tweaks' fast mode off for the rest of the call),
;   2. the framework's ragdoll pull switched off,
;   3. slack: the longest length raised first (the shortest may not exceed it),
;   4. half a second, so no pull or ragdoll hold is running when the cut lands,
;   5. frame sync again, the cut, and a 0.15 s settle before anything moves or
;      kills the body.
; Nothing is ever cut for nothing: a cut returns at once when there is no chain.
;
; Leash Framework's own header is the only documentation it ships; the
; behaviour relied on here, with its line numbers in LeashFramework.psc 1.1.8:
;   - a world-position chain has no holder (GetLeashHolder answers None), and
;     DisconnectLeash(None, actor) takes it off (lines 129-135);
;   - an actor is the chained end of one chain at most (line 70);
;   - lengths answer -1.0 when there is no chain (lines 222-229): the probe.

; Papyrus Tweaks' "speed up native calls" runs native calls on the script thread
; at once, while the main thread may be drawing the same chain. DisableFastMode
; puts the rest of the calling event back on the frame.
Bool Function FrameSync() Global
    If SKSE.GetPluginVersion("PapyrusTweaks") > 0
        Return PapyrusTweaks.DisableFastMode()
    EndIf
    Return false
EndFunction

; The load-time probe. Read only: it makes and cuts nothing. With no chain on
; the player, Leash Framework answers -1.0 for the shortest length; a native that
; is not answering gives the type's default, 0.0.
Bool Function Answers() Global
    Actor p = Game.GetPlayer()
    If p == None
        Return false
    EndIf
    If LeashFramework.IsLeashed(p)
        Return true
    EndIf
    Return LeashFramework.GetMinLeashLength(p) == -1.0
EndFunction

; True while the actor is the chained end of any chain, ours or another mod's.
Bool Function IsHeld(Actor akActor) Global
    If akActor == None
        Return false
    EndIf
    Return LeashFramework.IsLeashed(akActor)
EndFunction

; The hook chain: Leash Framework's long world chain from the grinder's nip
; (afX, afY, afZ in akCell) to the neck, with the framework's ragdoll pull on and
; its teleport recovery off. The chain is noted on the actor (FL_HookChain), so a
; later cut does not rest on IsLeashed alone.
Bool Function HookChain(Actor akActor, Cell akCell, Float afX, Float afY, Float afZ, Float afMin, Float afMax) Global
    If akActor == None
        Return false
    EndIf
    FrameSync()
    Bool ok = LeashFramework.ApplyStandaloneLeashAtPosition(akActor, akCell, afX, afY, afZ, "Leash/world_chain_long.nif", "NPC Neck [Neck]", "", "Leash1_", afMin, afMax, false)
    If !ok
        ; The first refusal in a save is written down; LeashFramework.log names the reason.
        If StorageUtil.AdjustIntValue(None, "FL_HookChainFails", 1) == 1
            Debug.Trace("[FleshCore] grinder: Leash Framework would not make the hook chain on " + akActor + " - LeashFramework.log says why")
        EndIf
        Return false
    EndIf
    StorageUtil.SetIntValue(akActor, "FL_HookChain", 1)
    FrameSync()
    LeashFramework.SetRagdollOverride(akActor, 1)
    LeashFramework.SetTeleportOverride(akActor, 0)
    Return true
EndFunction

; The reel: a shorter chain pulls them closer.
Bool Function SetReach(Actor akActor, Float afMax) Global
    If akActor == None
        Return false
    EndIf
    FrameSync()
    Return LeashFramework.SetMaxLeashLength(akActor, afMax)
EndFunction

; Steps 2 and 3 of a cut for one chained end, without the wait.
Function SlackOne(Actor akActor) Global
    LeashFramework.SetRagdollOverride(akActor, 0)
    Float curMax = LeashFramework.GetMaxLeashLength(akActor)
    If curMax > 0.0
        LeashFramework.SetMaxLeashLength(akActor, curMax + 400.0)
        LeashFramework.SetMinLeashLength(akActor, curMax + 350.0)
    EndIf
EndFunction

; Steps 2 to 4 of every cut. Call only while the actor is the chained end.
Function Slacken(Actor akActor) Global
    SlackOne(akActor)
    Utility.Wait(0.5)
EndFunction

; Takes our hook chain off, and only it: chains the actor holds, and a chain
; someone holds on them, stay on.
Function CutHookChain(Actor akActor) Global
    If akActor == None
        Return
    EndIf
    Bool noted = StorageUtil.GetIntValue(akActor, "FL_HookChain", 0) != 0
    FrameSync()
    Bool held = LeashFramework.IsLeashed(akActor) && LeashFramework.GetLeashHolder(akActor) == None
    If !held && !noted
        Return
    EndIf
    If held != noted
        Debug.Trace("[FleshCore] grinder: " + akActor + " - Leash Framework says chained " + held + ", FleshCore noted " + noted + "; cutting anyway")
    EndIf
    If held
        Slacken(akActor)
        FrameSync()
    EndIf
    LeashFramework.DisconnectLeash(None, akActor)
    StorageUtil.UnsetIntValue(akActor, "FL_HookChain")
    If LeashFramework.IsLeashed(akActor) && LeashFramework.GetLeashHolder(akActor) == None
        Debug.Trace("[FleshCore] grinder: the hook chain was still on " + akActor + " right after the cut")
    EndIf
    Utility.Wait(0.15)
EndFunction

; Takes off only the chain the actor is on (another mod's), so the hook chain can
; go on; chains the actor holds stay on.
Function CutHeldEnd(Actor akActor) Global
    If akActor == None
        Return
    EndIf
    FrameSync()
    If !LeashFramework.IsLeashed(akActor)
        Return
    EndIf
    Actor holder = LeashFramework.GetLeashHolder(akActor)
    Slacken(akActor)
    FrameSync()
    LeashFramework.DisconnectLeash(holder, akActor)
    StorageUtil.UnsetIntValue(akActor, "FL_HookChain")
    Utility.Wait(0.15)
EndFunction

; Before a grind or a kill: every chain comes off the actor, the one they are on
; and any they hold, because nothing of Leash Framework's may hang on a body
; FleshCore is about to take apart. Returns at once when there is none.
; The chains they hold get the same safe order as the one they are on: the far
; end of each (someone else, on that chain) has its ragdoll pull switched off and
; its chain slackened, then one half-second wait for all of them, then the cut.
Function CutAll(Actor akActor) Global
    If akActor == None
        Return
    EndIf
    Bool noted = StorageUtil.GetIntValue(akActor, "FL_HookChain", 0) != 0
    FrameSync()
    Bool held = LeashFramework.IsLeashed(akActor)
    Bool holds = LeashFramework.IsLeashHolder(akActor)
    If !held && !holds && !noted
        Return
    EndIf
    Bool slackened = false
    If held
        SlackOne(akActor)
        slackened = true
    EndIf
    If holds
        Actor[] ends = LeashFramework.GetLeashedActors(akActor)
        Int i = 0
        While i < ends.Length
            If ends[i] != None && ends[i] != akActor
                SlackOne(ends[i])
                slackened = true
            EndIf
            i += 1
        EndWhile
    EndIf
    If slackened
        Utility.Wait(0.5)
        FrameSync()
    EndIf
    LeashFramework.UnleashAll(akActor)
    StorageUtil.UnsetIntValue(akActor, "FL_HookChain")
    Utility.Wait(0.15)
EndFunction
