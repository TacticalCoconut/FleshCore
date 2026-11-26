Scriptname FL_GrinderSpells extends Quest
{Spawn Grinder and Grinder Hook: the player has them while the MCM's Grinder
 Spells toggle is on (the default) and Leash Framework is ready, and not
 otherwise. Rides on FL_HooksQuest beside FL_Effects, so FleshCore_GameReload
 reaches it on every load.}

Spell Property SpawnSpell Auto
Spell Property HookSpell Auto

; Leash Framework 1.1.8.0 as SKSE reports it: major * 2^24 + minor * 2^16 +
; patch * 16 + build (read from its DLL's SKSEPlugin_Version export).
Int Property TESTED_VERSION = 16842880 AutoReadOnly

; ---- WHAT IT KEEPS (StorageUtil, on None, so the MCM can read it) ----------
;
;   FL_GrinderState       1 ready; 2 Leash Framework not installed; 3 Leash.esm
;                         installed but its SKSE plugin did not load or does not
;                         answer. 0 = this script has not run yet (no MCM rows).
;   FL_GrinderSpellsOn    the player's choice; unset means on.
;   FL_SpawnGrinderSpell  the two spells, so the MCM can give or take them
;   FL_GrindHookSpell   without naming this script or a record of the plugin.
;   FL_GrinderVersionSeen the Leash Framework version last warned about.
;
; No cross-script call from OnInit: it only books the first check.

Event OnInit()
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
    RegisterForSingleUpdate(4.0)
EndEvent

; FL_Watch registers this quest for the event and sends it once per load.
Event OnFleshCoreReload(String eventName, String strArg, Float numArg, Form sender)
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    Sync()
EndEvent

; The gate in front of every FL_LeashBridge call: Leash.esm installed, its SKSE
; plugin loaded (SKSE answers -1 for a plugin that did not load), and the last
; probe did not find its functions silent.
Bool Function ChainReady() Global
    If !Game.IsPluginInstalled("Leash.esm")
        Return false
    EndIf
    If SKSE.GetPluginVersion("LeashFramework") <= 0
        Return false
    EndIf
    Return StorageUtil.GetIntValue(None, "FL_GrinderState", 0) != 3
EndFunction

; major.minor.patch.build out of the packed number.
String Function VersionText(Int aiVersion) Global
    If aiVersion <= 0
        Return "none"
    EndIf
    Int major = aiVersion / 16777216
    Int minor = (aiVersion / 65536) % 256
    Int patch = (aiVersion / 16) % 4096
    Int build = aiVersion % 16
    Return major + "." + minor + "." + patch + "." + build
EndFunction

; Once per load: works out whether Leash Framework is ready, writes it down for
; the MCM, and gives or takes the two spells to match.
Function Sync()
    Int st = 2
    Int ver = SKSE.GetPluginVersion("LeashFramework")
    If Game.IsPluginInstalled("Leash.esm")
        st = 3
        If ver > 0
            ; The probe only reads: no chain is made or cut.
            If FL_LeashBridge.Answers()
                st = 1
            EndIf
        EndIf
    EndIf
    Int was = StorageUtil.GetIntValue(None, "FL_GrinderState", 0)
    StorageUtil.SetIntValue(None, "FL_GrinderState", st)
    StorageUtil.SetFormValue(None, "FL_SpawnGrinderSpell", SpawnSpell)
    StorageUtil.SetFormValue(None, "FL_GrindHookSpell", HookSpell)
    If st == 1
        Debug.Trace("[FleshCore] grinder: Leash Framework " + VersionText(ver) + " (" + ver + "), tested with " + VersionText(TESTED_VERSION) + "; its functions answer")
        ; A version other than the tested one is used, never refused: one note per version.
        If ver != TESTED_VERSION && StorageUtil.GetIntValue(None, "FL_GrinderVersionSeen", 0) != ver
            StorageUtil.SetIntValue(None, "FL_GrinderVersionSeen", ver)
            Debug.Notification("FleshCore: Leash Framework " + VersionText(ver) + " is not the version the Grinder Hook was tested with (1.1.8.0). The hook may behave differently.")
        EndIf
    ElseIf st != was
        If st == 2
            Debug.Trace("[FleshCore] grinder: Leash Framework is not installed; the grinder spells are off")
        Else
            Debug.Trace("[FleshCore] grinder: Leash.esm is installed but Leash Framework's SKSE plugin did not load or does not answer (version " + ver + "); the grinder spells are off")
        EndIf
    EndIf
    Give(st == 1 && StorageUtil.GetIntValue(None, "FL_GrinderSpellsOn", 1) != 0)
EndFunction

Function Give(Bool abOn)
    Actor p = Game.GetPlayer()
    If p == None
        Return
    EndIf
    Int added = GiveOne(p, SpawnSpell, abOn) + GiveOne(p, HookSpell, abOn)
    If added > 0
        Debug.Notification("FleshCore: Spawn Grinder and Grinder Hook are in your Conjuration spells.")
    EndIf
EndFunction

Int Function GiveOne(Actor p, Spell s, Bool abOn)
    If s == None
        Return 0
    EndIf
    If abOn && !p.HasSpell(s)
        p.AddSpell(s, false)
        Return 1
    ElseIf !abOn && p.HasSpell(s)
        p.RemoveSpell(s)
    EndIf
    Return 0
EndFunction
