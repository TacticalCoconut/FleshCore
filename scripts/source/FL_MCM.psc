Scriptname FL_MCM extends SKI_ConfigBase
{FleshCore's MCM: what version everything is, and what key opens the HQ.

 DELIBERATELY SMALL. The body configuration lives in the HQ (the PrismaUI
 menu), which is the thing built for it -- a body
 outline you click, and the Combat page, where the weapon rows
 live with everything else that
 decides when a blow cuts. What is here is the two things you may need BEFORE
 the HQ will open: what is actually installed, and which key opens it. A
 hotkey you can only rebind from behind that hotkey is a door locked from the
 inside.

 Two details from SKI_ConfigBase.psc that matter here:


   * The remap event is OnKeyMapChangeST (state options) or
     OnOptionKeyMapChange (index options). There is NO `OnKeyMapChange`. The
     build compiles with --skyrim-allow-unknown-events-on-non-native-class=1, so
     that name would have compiled to a W7000 warning and a function the game
     never calls -- a hotkey page that looks finished and does nothing.
   * `Pages` and `ModName` are auto properties on a QUEST script, so they
     SERIALISE. OnConfigInit runs once ever. A save made against an older page
     list keeps it forever unless OnVersionUpdate reassigns, which is why the
     version gate below exists on day one rather than being added later.

 SkyUI is NOT a master of FleshCore.esp and must not become one: registration
 is a runtime call that hands SkyUI a pointer to this quest over a string-keyed
 mod event. Without SkyUI installed this script simply never loads, and nothing
 else in the mod notices.}

; The script's own version, for SKI_QuestBase's CheckVersion/OnVersionUpdate.
; Bump it whenever Pages changes, or existing saves keep the old page list.
Int Function GetVersion()
    Return 5
EndFunction

; ---- persisted state ----------------------------------------------------
;
; ZERO MEANS "THE PLAYER HAS NOT CHOSEN", and the config's PK row stands. It does
; NOT mean unmapped: -1 is unmapped, which is a choice and has to be told apart
; from never having made one. Papyrus gives a variable a save does not carry
; the type's default, so zero is the only safe spelling for "unset".
Int _panelKey = 0

; WEAPON ROWS LIVE IN THE HQ. Design note: the weapon voxel damage
; controls belong in a full, adjustable menu in the HQ, not in this MCM.
; The HQ's Combat page builds a row per weapon kind
; of its own,
; under "HQ", from the
; panel store, and the engine reads them without a file. Variables such as
; _swordTest and _swordFactor are not declared here:
; a save that carries them loads with them dropped, which is what Papyrus
; does with a variable a script no longer has. Rows under the reserved caller "MCM" cannot
; outlive a launch (the trigger file is cleared at every one), but a load
; still sweeps any "MCM" rows it finds, so none can stand
; beside the HQ's.

; ---- scratch, rebuilt on every page reset; never meaningful across one ----
Int _oidEngine  = -1
Int _oidScripts = -1
Int _oidPlugin  = -1
Int _oidPanel   = -1
Int _oidDouble  = -1

Event OnConfigInit()
    ModName = "FleshCore"
    SetPages()
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
EndEvent

Event OnFleshCoreReload(String eventName, String strArg, Float numArg, Form sender)
    {FL_Watch sends this from CheckLoad on every load, so the MCM's reload
     runs without FL_Watch ever naming a SkyUI type. Same body as the alias
     SkyUI documents for the purpose.}
    OnGameReload()
EndEvent

Bool Function HasAbilities()
    {The Abilities plugin is soft: its page appears only when it is in the
     load order, and nothing here names one of its types.}
    Return Game.IsPluginInstalled("FleshCore Abilities.esp")
EndFunction

Function SetPages()
    ; ONE FleshCore ENTRY IN THE MCM LIST. The Abilities plugin's
    ; test page lives here as a page of this menu when that plugin is present,
    ; rather than as a menu of its own: a large load order can carry more menus
    ; than SkyUI's 128-slot table, and every extra registrant is one more
    ; that can be dropped or misnamed on a heavy load.
    ; Two pages of FleshCore's own, Status and Controls; the weapon rows are on the HQ's
    ; Combat page.
    If HasAbilities()
        Pages = new String[3]
        Pages[2] = "Abilities"
    Else
        Pages = new String[2]
    EndIf
    Pages[0] = "Status"
    Pages[1] = "Controls"
EndFunction

Function RetireAbilitiesMenu()
    {A SEPARATE ABILITIES MENU IS TAKEN OFF THE LIST FROM HERE. The
     Abilities plugin's own MCM quest (0x80E) is left to retire itself, its page
     being on this menu -- but
     nothing of its own ever runs on a load (no player alias, and its
     SKICP_configManagerReady subscription answers "already registered" and
     calls nothing), so the companion script would have to call it by its SkyUI-derived
     type, which is the one thing a script outside the MCM must never name.
     This script is the MCM, SkyUI's types are its own parents, and it runs on
     every load (FleshCore_GameReload): the manager forgets the old menu, the
     old quest's subscriptions and menus go, and it stops. Once per save --
     a stopped 0x80E is one this already retired -- and nothing at all on a
     save that never had it or a load order without the plugin.}
    If !HasAbilities()
        Return
    EndIf
    Quest old = Game.GetFormFromFile(0x0000080E, "FleshCore Abilities.esp") as Quest
    If !old || !old.IsRunning()
        Return
    EndIf
    SKI_ConfigManager m = Quest.GetQuest("SKI_ConfigManagerInstance") as SKI_ConfigManager
    SKI_ConfigBase page = old as SKI_ConfigBase
    Int slot = -1
    If m && page
        slot = m.UnregisterMod(page)
    EndIf
    old.UnregisterForAllModEvents()
    old.UnregisterForAllMenus()
    old.Stop()
    Debug.Trace("[FleshCore] MCM: the separate Abilities menu is retired (manager slot " + slot + ") -- its page is here now")
EndFunction

; ---- the Abilities page ----------------------------------------
;
; Everything the old companion MCM did, on FleshCore's own menu.
; The spells are reached by local id in the Abilities plugin; the quest that
; casts and reports is 0x800 there, talked to only through StorageUtil keys
; it already reads (FCA_notify, FCA_rules, FCA_last).
Int _oidAbLast = -1
Int _oidAbRules = -1

Spell Function AbilitySpell(Int kind)
    If !HasAbilities()
        Return None
    EndIf
    If kind == 0
        Return Game.GetFormFromFile(0x00000809, "FleshCore Abilities.esp") as Spell
    ElseIf kind == 1
        Return Game.GetFormFromFile(0x0000080B, "FleshCore Abilities.esp") as Spell
    EndIf
    Return Game.GetFormFromFile(0x0000080D, "FleshCore Abilities.esp") as Spell
EndFunction

Bool Function HasAbilitySpell(Int kind)
    Spell s = AbilitySpell(kind)
    Actor p = Game.GetPlayer()
    If !s || !p
        Return false
    EndIf
    Return p.HasSpell(s)
EndFunction

Function GrantAbilitySpell(Int kind, Bool on)
    Spell s = AbilitySpell(kind)
    Actor p = Game.GetPlayer()
    If !s || !p
        Debug.Notification("FleshCore: the Abilities plugin's spell could not be resolved")
        Return
    EndIf
    If on && !p.HasSpell(s)
        p.AddSpell(s, false)
        Debug.Notification("FleshCore: " + s.GetName() + " added -- Magic menu, Destruction")
    ElseIf !on && p.HasSpell(s)
        p.RemoveSpell(s)
    EndIf
EndFunction

Event OnVersionUpdate(Int a_version)
    If a_version >= 1 && CurrentVersion < 1
        Debug.Trace("[FleshCore] MCM: updating to script version 1")
        ModName = "FleshCore"
        SetPages()
    EndIf
    If a_version >= 2 && CurrentVersion < 2
        Debug.Trace("[FleshCore] MCM: updating to script version 2")
        SetPages()
    EndIf
    If a_version >= 3 && CurrentVersion < 3
        Debug.Trace("[FleshCore] MCM: updating to script version 3")
        SetPages()
    EndIf
    If a_version >= 4 && CurrentVersion < 4
        Debug.Trace("[FleshCore] MCM: updating to script version 4")
        SetPages()
        SweepTestRows()
    EndIf
    If a_version >= 5 && CurrentVersion < 5
        Debug.Trace("[FleshCore] MCM: updating to script version 5")
        SetPages()
    EndIf
EndEvent

Function SweepTestRows()
    {Any row registered under the reserved caller "MCM" is withdrawn. Only
     when there is one: a load with none must not rewrite a file it has no
     rows in.}
    If !Game.IsPluginInstalled("FleshCore.esp")
        Return
    EndIf
    If FL_Api.Triggers("MCM") != ""
        FL_Api.ClearTriggers("MCM")
        Debug.Trace("[FleshCore] MCM: the old Test page's rows are withdrawn -- the HQ's Combat page owns them now")
    EndIf
EndFunction

; ---- what the engine says about itself ----------------------------------
;
; READ FROM THE DLL, NOT KEPT HERE. FleshCore.version.txt is written by the DLL
; once per session as `<version>|<panel state>`. A constant in this script would
; be a second copy of a number that already has one source, and a second
; copy drifts -- the banner and the plugin version data were merged into one
; #define in flesh.cpp for exactly that reason.
;
; A MISSING FILE IS THE MOST USEFUL ANSWER THERE IS: it means the DLL did not
; load, which is the first thing anyone debugging this mod needs to know and
; the one thing a hardcoded string could never tell them.
String[] Function EngineFacts()
    String[] out = new String[2]
    out[0] = ""
    out[1] = ""
    String raw = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.version.txt")
    If raw == ""
        Return out
    EndIf
    String[] bits = StringUtil.Split(raw, "|")
    If bits.Length >= 1
        out[0] = bits[0]
    EndIf
    If bits.Length >= 2
        out[1] = bits[1]
    EndIf
    Return out
EndFunction

FL_Watch Function Watcher()
    {FL_Watch rides on FL_GrantQuest, 0x835. By local id, the way every other
     script in this mod reaches a sibling: FormIDs never move here, so the id
     is a fact, and a property would be one more entry in this quest's script
     data for no gain.}
    Return Game.GetFormFromFile(0x00000835, "FleshCore.esp") as FL_Watch
EndFunction

; The key actually in force: the player's choice if they have made one, and
; otherwise whatever the config's PK row gave the watcher.
Int Function KeyInForce()
    If _panelKey != 0
        Return _panelKey
    EndIf
    FL_Watch w = Watcher()
    If w
        Return w.PanelKeyInUse()
    EndIf
    Return 0
EndFunction

Event OnPageReset(String a_page)
    If a_page == "" || a_page == "Status"
        String[] eng = EngineFacts()
        SetTitleText("FleshCore")
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("What is installed")

        String engine = eng[0]
        If engine == ""
            engine = "NOT LOADED"
        EndIf
        _oidEngine = AddTextOption("Engine (SKSE plugin)", engine, OPTION_FLAG_DISABLED)

        _oidScripts = AddTextOption("Scripts", "0.1 Beta", OPTION_FLAG_DISABLED)

        ; The plugin is proven by resolving a record out of it rather than by
        ; asking whether a file exists: a plugin present but not ENABLED
        ; answers yes to the file question and no to this one.
        String plugin = "NOT LOADED"
        If Game.GetFormFromFile(0x000008C3, "FleshCore.esp")
            plugin = "loaded"
        EndIf
        _oidPlugin = AddTextOption("Plugin (FleshCore.esp)", plugin, OPTION_FLAG_DISABLED)

        String panel = eng[1]
        If panel == ""
            panel = "unknown -- the engine did not say"
        EndIf
        _oidPanel = AddTextOption("HQ (the PrismaUI menu)", panel, OPTION_FLAG_DISABLED)

    ElseIf a_page == "Controls"
        SetTitleText("Controls")
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("The HQ")
        AddKeyMapOptionST("PANELKEY", "Open the HQ", KeyInForce(), OPTION_FLAG_WITH_UNMAP)

        Int ms = 300
        FL_Watch w = Watcher()
        If w
            ms = w.PanelDoubleMs()
        EndIf
        _oidDouble = AddTextOption("Double-tap within", ms + " ms", OPTION_FLAG_DISABLED)
        AddEmptyOption()
        AddTextOption("Weapons, triggers, who may be cut, resets:", "", OPTION_FLAG_DISABLED)
        AddTextOption("the HQ's Combat page", "", OPTION_FLAG_DISABLED)
        If Game.IsPluginInstalled("SkyrimNet.esp")
            AddEmptyOption()
            AddHeaderOption("SkyrimNet Integration")
            AddToggleOptionST("FCSNON", "Notify SkyrimNet of FleshCore wounds & dismemberments", StorageUtil.GetIntValue(None, "FC_SkyrimNetOn", 1) != 0)
            AddToggleOptionST("FCSNDIRECT", "Trigger spoken reactions on severe/fatal wounds", StorageUtil.GetIntValue(None, "FC_SkyrimNetDirect", 1) != 0)
        EndIf

        SetCursorPosition(1)
        AddHeaderOption("Combat Intensity Spectrum")
        Int curPreset = StorageUtil.GetIntValue(None, "FC_PresetId", 50)
        Int sliderVal = curPreset
        If sliderVal < 0
            sliderVal = StorageUtil.GetIntValue(None, "FC_PresetBase", 50)
        EndIf
        If sliderVal < 0 || sliderVal > 100
            sliderVal = 50
        EndIf
        If curPreset < 0
            AddSliderOptionST("FCPRESET", "Combat Intensity (Custom)", sliderVal as Float, "Custom ({0}%)")
        Else
            AddSliderOptionST("FCPRESET", "Combat Intensity", sliderVal as Float, "{0}%")
        EndIf
        AddTextOption("Intensity Tier:", PresetLabel(curPreset), OPTION_FLAG_DISABLED)
        AddTextOption("Voxelization:", PresetWhatItDoes(curPreset), OPTION_FLAG_DISABLED)
        AddTextOption("Survivability:", PresetHowItPlays(curPreset), OPTION_FLAG_DISABLED)

        AddEmptyOption()
        AddHeaderOption("Out-of-Combat Layer & Magic Progression Tester")
        Int tIdx = StorageUtil.GetIntValue(None, "FC_TestTargetIdx", 0)
        Int pIdx = StorageUtil.GetIntValue(None, "FC_TestPartIdx", 0)
        Int fIdx = StorageUtil.GetIntValue(None, "FC_TestFamIdx", 0)
        AddMenuOptionST("FCTESTTARGET", "Test Target", TestTargetLabel(tIdx))
        AddMenuOptionST("FCTESTPART", "Body Part Patch", TestPartLabel(pIdx))
        AddMenuOptionST("FCTESTFAM", "Strike Type", TestFamLabel(fIdx))
        AddTextOptionST("FCTESTSTRIKE", "Test Strike on Patch", "STRIKE")
        AddTextOptionST("FCTESTRESTORE", "Restore Target Body & Armour", "RESTORE")
        String rep = StorageUtil.GetStringValue(None, "FC_LastTestReport", "(none yet)")
        AddTextOption("Last Test Report:", "", OPTION_FLAG_DISABLED)
        AddTextOption(rep, "", OPTION_FLAG_DISABLED)

    ElseIf a_page == "Abilities"
        SetTitleText("FleshCore Abilities")
        SetCursorFillMode(TOP_TO_BOTTOM)
        AddHeaderOption("Test spells (aim at someone, cast; never fatal)")
        AddToggleOptionST("ABLEG", "Cripple Leg -- left thigh under 60% (Limping)", HasAbilitySpell(0))
        AddToggleOptionST("ABARM", "Cripple Arm -- left upper arm under 60% (Weak Arm)", HasAbilitySpell(1))
        AddToggleOptionST("ABHEAD", "Daze Head -- head under 80% (Dazed)", HasAbilitySpell(2))
        AddEmptyOption()
        AddHeaderOption("Survivable Decapitation (FleshCore)")
        AddToggleOptionST("ABDECAPMODE", "Daze Head spell casts Survivable Decapitation", StorageUtil.GetIntValue(None, "FCA_head_decap", 0) != 0)
        AddTextOptionST("ABDECAPTARGET", "Survivable Decapitate: Crosshair Target", "cast")
        AddTextOptionST("ABDECAPSELF", "Survivable Decapitate: Yourself", "cast")
        AddTextOptionST("ABRESTORE", "Restore FleshCore Body (Crosshair or Self)", "restore")
        AddEmptyOption()
        AddHeaderOption("Results")
        AddToggleOptionST("ABNOTIFY", "Say the result on screen", StorageUtil.GetIntValue(None, "FCA_notify", 1) != 0)
        String rules = "not yet"
        If StorageUtil.GetIntValue(None, "FCA_rules", 0) != 0
            rules = "registered"
        EndIf
        _oidAbRules = AddTextOption("Effect rules", rules, OPTION_FLAG_DISABLED)
        String last = StorageUtil.GetStringValue(None, "FCA_last", "")
        If last == ""
            last = "(nothing cast yet)"
        EndIf
        _oidAbLast = AddTextOption("Last cast", "", OPTION_FLAG_DISABLED)
        AddTextOption(last, "", OPTION_FLAG_DISABLED)
        If Game.IsPluginInstalled("FleshCore Guillotine.esp")
            AddEmptyOption()
            AddHeaderOption("FleshCore Bisecting Guillotine")
            AddToggleOptionST("ABGUILSPELL", "Spawn Bisecting Guillotine spell", HasGuillotineSpell())
            AddTextOptionST("ABGUILSPAWN", "Spawn Bisecting Guillotine at your feet now", "spawn")
        EndIf
    EndIf
EndEvent

Spell Function GuillotineSpell()
    If !Game.IsPluginInstalled("FleshCore Guillotine.esp")
        Return None
    EndIf
    Return Game.GetFormFromFile(0x00000803, "FleshCore Guillotine.esp") as Spell
EndFunction

Bool Function HasGuillotineSpell()
    Spell s = GuillotineSpell()
    Actor p = Game.GetPlayer()
    Return s != None && p != None && p.HasSpell(s)
EndFunction

State ABGUILSPELL
    Event OnSelectST()
        Spell s = GuillotineSpell()
        Actor p = Game.GetPlayer()
        If !s || !p
            Return
        EndIf
        If p.HasSpell(s)
            p.RemoveSpell(s)
            SetToggleOptionValueST(false)
        Else
            p.AddSpell(s, false)
            SetToggleOptionValueST(true)
        EndIf
    EndEvent
    Event OnHighlightST()
        SetInfoText("Adds or removes the Spawn Bisecting Guillotine spell (Alteration, self-cast).")
    EndEvent
EndState

State ABGUILSPAWN
    Event OnSelectST()
        Form guil = Game.GetFormFromFile(0x00000801, "FleshCore Guillotine.esp")
        Actor p = Game.GetPlayer()
        If !guil || !p
            ShowMessage("Could not resolve FCG_BisectGuillotine_BoxTie (0x801) in FleshCore Guillotine.esp.", false)
            Return
        EndIf
        ObjectReference dummy = p.PlaceAtMe(Game.GetFormFromFile(0x000D19BA, "Skyrim.esm"))
        If dummy
            dummy.SetAngle(0.0, 0.0, p.GetAngleZ())
            dummy.PlaceAtMe(guil)
            dummy.Delete()
            ShowMessage("Bisecting Guillotine spawned at your feet. Close the menu to use it.", false)
        EndIf
    EndEvent
    Event OnHighlightST()
        SetInfoText("Immediately places a levelled FleshCore Bisecting Guillotine at your feet.")
    EndEvent
EndState

State ABDECAPMODE
    Event OnSelectST()
        Bool on = StorageUtil.GetIntValue(None, "FCA_head_decap", 0) == 0
        If on
            StorageUtil.SetIntValue(None, "FCA_head_decap", 1)
        Else
            StorageUtil.SetIntValue(None, "FCA_head_decap", 0)
        EndIf
        SetToggleOptionValueST(on)
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FCA_head_decap", 0)
        SetToggleOptionValueST(false)
    EndEvent
    Event OnHighlightST()
        SetInfoText("When enabled, casting the Daze Head spell in-game performs a Survivable FleshCore Decapitation on the crosshair target (or on yourself if no actor is under the crosshair) instead of only opening the skull to 80%.")
    EndEvent
EndState

State ABDECAPTARGET
    Event OnSelectST()
        Actor target = Game.GetCurrentCrosshairRef() as Actor
        If !target
            ShowMessage("No actor under the crosshair. Aim at an NPC and try again.", false)
            Return
        EndIf
        FL_Api.SetNoKill(target, true)
        FL_Api.SetInt(target, "headfatal", 0, "ADT", 100)
        If FL_Api.Wound(target, "decapitate")
            ShowMessage("Survivable Decapitation queued on " + target.GetDisplayName() + ". Close the menu to watch it land.", false)
        Else
            ShowMessage("FleshCore refused Decapitate on " + target.GetDisplayName() + " (" + FL_Api.WhyNot(target) + ").", false)
        EndIf
    EndEvent
    Event OnHighlightST()
        SetInfoText("Sever the crosshair actor's head through FleshCore with SetNoKill and headfatal=0 active so they survive headless.")
    EndEvent
EndState

State ABDECAPSELF
    Event OnSelectST()
        Actor p = Game.GetPlayer()
        If !p
            Return
        EndIf
        FL_Api.SetNoKill(p, true)
        FL_Api.SetInt(p, "headfatal", 0, "ADT", 100)
        If FL_Api.Wound(p, "decapitate")
            ShowMessage("Survivable Decapitation queued on yourself. Close the menu to watch it land.", false)
        Else
            ShowMessage("FleshCore refused Decapitate on player (" + FL_Api.WhyNot(p) + ").", false)
        EndIf
    EndEvent
    Event OnHighlightST()
        SetInfoText("Sever your own head through FleshCore with SetNoKill and headfatal=0 active so you survive headless.")
    EndEvent
EndState

State ABRESTORE
    Event OnSelectST()
        Actor who = Game.GetCurrentCrosshairRef() as Actor
        If !who
            who = Game.GetPlayer()
        EndIf
        If !who
            Return
        EndIf
        FL_Api.Restore(who)
        FL_Api.SetNoKill(who, false)
        FL_Api.ClearKey(who, "headfatal", "ADT")
        ShowMessage("Restored FleshCore body and cleared survivable-decapitation overrides on " + who.GetDisplayName() + ".", false)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Restores the crosshair actor's (or your own, if no actor is under the crosshair) FleshCore body and clears SetNoKill and headfatal overrides.")
    EndEvent
EndState

State ABLEG
    Event OnSelectST()
        Bool on = !HasAbilitySpell(0)
        GrantAbilitySpell(0, on)
        SetToggleOptionValueST(HasAbilitySpell(0))
    EndEvent
    Event OnDefaultST()
        GrantAbilitySpell(0, false)
        SetToggleOptionValueST(false)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Adds Cripple Leg to your Destruction spells. Aim at someone and cast: a bite through the target's left thigh, never fatal, that leaves the leg under 60% -- the line at which the Limping rule fires. The report says whether it did.")
    EndEvent
EndState

State ABARM
    Event OnSelectST()
        Bool on = !HasAbilitySpell(1)
        GrantAbilitySpell(1, on)
        SetToggleOptionValueST(HasAbilitySpell(1))
    EndEvent
    Event OnDefaultST()
        GrantAbilitySpell(1, false)
        SetToggleOptionValueST(false)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Adds Cripple Arm to your Destruction spells. A bite through the target's left upper arm, never fatal, that leaves the arm under 60% -- the Weak Arm rule's line.")
    EndEvent
EndState

State ABHEAD
    Event OnSelectST()
        Bool on = !HasAbilitySpell(2)
        GrantAbilitySpell(2, on)
        SetToggleOptionValueST(HasAbilitySpell(2))
    EndEvent
    Event OnDefaultST()
        GrantAbilitySpell(2, false)
        SetToggleOptionValueST(false)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Adds Daze Head to your Destruction spells. The target's head opened from the front, never fatal and never taken off, left under 80% -- the Dazed rule's line.")
    EndEvent
EndState

State ABNOTIFY
    Event OnSelectST()
        Bool on = StorageUtil.GetIntValue(None, "FCA_notify", 1) == 0
        If on
            StorageUtil.SetIntValue(None, "FCA_notify", 1)
        Else
            StorageUtil.SetIntValue(None, "FCA_notify", 0)
        EndIf
        SetToggleOptionValueST(on)
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FCA_notify", 1)
        SetToggleOptionValueST(true)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Every cast's result as a notification at the top-left. Off, it still goes to the Papyrus log and to the Last cast line here.")
    EndEvent
EndState

Event OnOptionHighlight(Int a_option)
    If a_option == _oidEngine
        SetInfoText("The version of FleshCore.dll, read from what the engine wrote this session. NOT LOADED means SKSE did not load the plugin at all.")
    ElseIf a_option == _oidScripts
        SetInfoText("The version of the Papyrus scripts. If this disagrees with the engine, one of the two did not deploy.")
    ElseIf a_option == _oidPlugin
        SetInfoText("Whether FleshCore.esp is loaded, checked by resolving a record from it: a file that is present but not enabled shows as NOT LOADED.")
    ElseIf a_option == _oidPanel
        SetInfoText("Whether the HQ is available. It needs PrismaUI installed and the PK row switched on.")
    ElseIf a_option == _oidDouble
        SetInfoText("How close together the two taps must be. Set by the PK row in FleshCore.cfg.txt.")
    ElseIf a_option == _oidAbLast
        SetInfoText("What the last test spell reported: the engine's answer, what is left of the part, and whether the target has the ability. Also in the Papyrus log as [FleshCore Abilities].")
    ElseIf a_option == _oidAbRules
        SetInfoText("Whether the Abilities plugin's three effect rules are registered with FleshCore this session. Re-registered on every load, once the engine says it has effects.")
    EndIf
EndEvent

State PANELKEY
    Event OnKeyMapChangeST(Int newKey, String conflictControl, String conflictName)
        ; ESC is 1 and never maps -- SkyUI's own ValidateKey refuses it, and a
        ; menu key bound to ESC is a menu you cannot leave.
        If newKey == 1
            Return
        EndIf
        If newKey != 0 && conflictControl != ""
            String msg = "That key is already used by \"" + conflictControl + "\""
            If conflictName != ""
                msg = msg + " (" + conflictName + ")"
            EndIf
            msg = msg + ".\n\nUse it for the panel anyway?"
            If !ShowMessage(msg, true, "$Yes", "$No")
                Return
            EndIf
        EndIf
        ; 0 from the unmap flag means the player cleared it. That is a CHOICE and
        ; is stored as -1, so it is not mistaken for "never chose" and silently
        ; overridden by the config on the next load.
        If newKey == 0
            _panelKey = -1
        Else
            _panelKey = newKey
        EndIf
        Push()
        SetKeyMapOptionValueST(newKey)
    EndEvent

    Event OnDefaultST()
        ; Back to the config's PK row, which is what "default" means here --
        ; not back to a number written twice.
        _panelKey = 0
        Push()
        SetKeyMapOptionValueST(KeyInForce())
    EndEvent

    Event OnHighlightST()
        SetInfoText("Double-tap this key to open the HQ. The default is the period key, set by the PK row in FleshCore.cfg.txt; clearing it here switches the hotkey off, and Reset puts the config back in charge.")
    EndEvent
EndState

Function Push()
    {Hand the choice to the watcher, which is what owns the registration.}
    FL_Watch w = Watcher()
    If w
        w.SetPanelKeyOverride(_panelKey)
    Else
        Debug.Trace("[FleshCore] MCM: FL_Watch could not be reached -- the key was stored but not applied until the next load")
    EndIf
EndFunction

Event OnConfigOpen()
    ; The engine file is re-read every time the menu is opened rather than
    ; cached: a session that swapped builds in the mod manager would otherwise show the
    ; version it saw first.
    ForcePageReset()
EndEvent

Event OnInit()
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
    If HasCombinedMenu()
        UnregisterFromSkyUI()
    Else
        Parent.OnGameReload()
        RegisterNow()
    EndIf
EndEvent

Event OnGameReload()
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
    If HasCombinedMenu()
        ; The combined menu owns the panel key there: pushing this menu's
        ; unused key would put the config's key back on every load.
        UnregisterFromSkyUI()
        Return
    EndIf
    Push()
    SweepTestRows()
    RetireAbilitiesMenu()
    Parent.OnGameReload()
    RegisterNow()
EndEvent

Bool Function HasCombinedMenu()
    {an external combined menu mod shows these pages inside its own combined menu (the companion menu on
     its controller quest), so there this menu stays off SkyUI's list. Looked up by
     editor id, which FleshCore's plugin binding leaves alone.}
    Return Quest.GetQuest("FL_CombinedMenuQuest") != None
EndFunction

Function RegisterNow()
    {SkyUI's own reload above subscribes this menu to the manager's ready and
     reset events; this asks for the slot at once rather than waiting for the
     manager's next broadcast. Already registered with it, the call does nothing.}
    SKI_ConfigManager m = Quest.GetQuest("SKI_ConfigManagerInstance") as SKI_ConfigManager
    If m
        OnConfigManagerReady("SKICP_configManagerReady", "", 0.0, m)
    EndIf
EndFunction

Function UnregisterFromSkyUI()
    SKI_ConfigManager m = Quest.GetQuest("SKI_ConfigManagerInstance") as SKI_ConfigManager
    If m
        m.UnregisterMod(self)
    EndIf
    UnregisterForModEvent("SKICP_configManagerReady")
    UnregisterForModEvent("SKICP_configManagerReset")
EndFunction

State FCSNON
    Event OnSelectST()
        Bool on = StorageUtil.GetIntValue(None, "FC_SkyrimNetOn", 1) == 0
        If on
            StorageUtil.SetIntValue(None, "FC_SkyrimNetOn", 1)
        Else
            StorageUtil.SetIntValue(None, "FC_SkyrimNetOn", 0)
        EndIf
        SetToggleOptionValueST(on)
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FC_SkyrimNetOn", 1)
        SetToggleOptionValueST(true)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Informs SkyrimNet of grievous wounds, exploded bodies, bisections, lost limbs, and decapitations when SkyrimNet.esp is installed.")
    EndEvent
EndState

State FCSNDIRECT
    Event OnSelectST()
        Bool on = StorageUtil.GetIntValue(None, "FC_SkyrimNetDirect", 1) == 0
        If on
            StorageUtil.SetIntValue(None, "FC_SkyrimNetDirect", 1)
        Else
            StorageUtil.SetIntValue(None, "FC_SkyrimNetDirect", 0)
        EndIf
        SetToggleOptionValueST(on)
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FC_SkyrimNetDirect", 1)
        SetToggleOptionValueST(true)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Triggers immediate SkyrimNet DirectNarration spoken reactions when an actor suffers a severe wound, lost limb, bisection, decapitation, or body explosion.")
    EndEvent
EndState

String Function PresetLabel(Int lvl)
    If lvl < 0
        Return "Custom"
    ElseIf lvl == 0
        Return "Disabled (0%)"
    ElseIf lvl < 20
        Return "Subtle Scars (" + lvl + "%)"
    ElseIf lvl < 35
        Return "Skirmish Cuts (" + lvl + "%)"
    ElseIf lvl < 48
        Return "Heavy Skirmish (" + lvl + "%)"
    ElseIf lvl <= 52
        Return "Finishing Blows (" + lvl + "%)"
    ElseIf lvl < 70
        Return "Brutal Cleave (" + lvl + "%)"
    ElseIf lvl < 85
        Return "Visceral Carnage (" + lvl + "%)"
    EndIf
    Return "Gorefest (" + lvl + "%)"
EndFunction

String[] Function TestTargetList()
    String[] t = new String[2]
    t[0] = "Crosshair / Nearest NPC"
    t[1] = "Player (Self)"
    Return t
EndFunction

String Function TestTargetLabel(Int idx)
    If idx == 1
        Return "Player (Self)"
    EndIf
    Return "Crosshair / Nearest NPC"
EndFunction

String Function TestTargetCode(Int idx)
    If idx == 1
        Return "player"
    EndIf
    Return "crosshair"
EndFunction

String[] Function TestPartList()
    String[] p = new String[11]
    p[0] = "Chest (Breastplate)"
    p[1] = "Abdomen"
    p[2] = "Head (Helmet)"
    p[3] = "Left Upper Arm"
    p[4] = "Right Upper Arm"
    p[5] = "Left Forearm (Gauntlet)"
    p[6] = "Right Forearm"
    p[7] = "Left Thigh (Cuirass/Greaves)"
    p[8] = "Right Thigh"
    p[9] = "Left Calf (Boot)"
    p[10] = "Right Calf"
    Return p
EndFunction

String Function TestPartLabel(Int idx)
    String[] p = TestPartList()
    If idx < 0 || idx >= p.Length
        idx = 0
    EndIf
    Return p[idx]
EndFunction

String Function TestPartCode(Int idx)
    If idx == 1
        Return "abdomen"
    ElseIf idx == 2
        Return "head"
    ElseIf idx == 3
        Return "lupperarm"
    ElseIf idx == 4
        Return "rupperarm"
    ElseIf idx == 5
        Return "lforearm"
    ElseIf idx == 6
        Return "rforearm"
    ElseIf idx == 7
        Return "lthigh"
    ElseIf idx == 8
        Return "rthigh"
    ElseIf idx == 9
        Return "lcalf"
    ElseIf idx == 10
        Return "rcalf"
    EndIf
    Return "chest"
EndFunction

String[] Function TestFamList()
    String[] f = new String[6]
    f[0] = "Physical Weapon (Any Melee / Bow)"
    f[1] = "Fire Magic (Burns 1 layer per hit)"
    f[2] = "Frost Magic (Shatters 2 layers per hit)"
    f[3] = "Shock Magic (Arcs 3 layers deep)"
    f[4] = "Shout (Blasts 2 outer layers)"
    f[5] = "Werewolf (Mauls all 4 layers)"
    Return f
EndFunction

String Function TestFamLabel(Int idx)
    String[] f = TestFamList()
    If idx < 0 || idx >= f.Length
        idx = 0
    EndIf
    Return f[idx]
EndFunction

String Function TestFamCode(Int idx)
    If idx == 1
        Return "fire"
    ElseIf idx == 2
        Return "frost"
    ElseIf idx == 3
        Return "shock"
    ElseIf idx == 4
        Return "shout"
    ElseIf idx == 5
        Return "werewolf"
    EndIf
    Return "weapon"
EndFunction

String Function PresetWhatItDoes(Int lvl)
    If lvl < 0
        Return "Custom settings modified outside preset"
    ElseIf lvl == 0
        Return "Combat blows & hostile magic do not voxelise"
    ElseIf lvl < 20
        Return "Near-death power blows peel 1 layer (<=25% HP)"
    ElseIf lvl < 48
        Return "Progressive 1-stage peeling on wounded targets"
    ElseIf lvl <= 52
        Return "Wounds & 2-stage cleaves below 50% HP"
    ElseIf lvl < 70
        Return "Frequent 2-3 stage cleaves across skirmishes"
    ElseIf lvl < 85
        Return "Any-HP damage-scaled 3-stage visceral wounds"
    EndIf
    Return "Every hit & spell tears through all 4 layers"
EndFunction

String Function PresetHowItPlays(Int lvl)
    If lvl < 0
        Return "Custom dismemberment survivability rules"
    ElseIf lvl == 0
        Return "Head & Trunk fatal; all limbs survivable"
    ElseIf lvl < 20
        Return "Head & Trunk fatal; 4-5 limbs before death"
    ElseIf lvl < 35
        Return "Head, Trunk & Thighs fatal; 3-4 limbs to die"
    ElseIf lvl < 50
        Return "Head, Trunk & Legs fatal; arms survivable"
    ElseIf lvl <= 54
        Return "Head, Trunk, Legs & Upper Arms fatal (2 limbs)"
    ElseIf lvl < 70
        Return "All arm & leg shafts fatal; hands/feet survive"
    ElseIf lvl < 85
        Return "All limbs & feet fatal; only hands survivable"
    EndIf
    Return "All 15 body parts fatal on dismemberment"
EndFunction

String Function PresetFullInfo(Int lvl)
    Return PresetLabel(lvl) + " — VOXELIZATION: " + PresetWhatItDoes(lvl) + ". SURVIVABILITY: " + PresetHowItPlays(lvl) + ". (0% = Disabled, 50% = Finishing Blows, 100% = Gorefest)"
EndFunction

State FCPRESET
    Event OnSliderOpenST()
        Int cur = StorageUtil.GetIntValue(None, "FC_PresetId", 50)
        If cur < 0
            cur = StorageUtil.GetIntValue(None, "FC_PresetBase", 50)
        EndIf
        If cur < 0 || cur > 100
            cur = 50
        EndIf
        SetSliderDialogStartValue(cur as Float)
        SetSliderDialogDefaultValue(50.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(1.0)
    EndEvent
    Event OnSliderAcceptST(Float value)
        Int lvl = value as Int
        If lvl < 0
            lvl = 0
        ElseIf lvl > 100
            lvl = 100
        EndIf
        StorageUtil.SetIntValue(None, "FC_PresetId", lvl)
        StorageUtil.SetIntValue(None, "FC_PresetBase", lvl)
        SetSliderOptionValueST(lvl as Float, "{0}%")
        FL_Api.ApplyPreset("MCM", lvl)
        SetInfoText(PresetFullInfo(lvl))
        ForcePageReset()
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FC_PresetId", 50)
        StorageUtil.SetIntValue(None, "FC_PresetBase", 50)
        SetSliderOptionValueST(50.0, "{0}%")
        FL_Api.ApplyPreset("MCM", 50)
        SetInfoText(PresetFullInfo(50))
        ForcePageReset()
    EndEvent
    Event OnHighlightST()
        Int cur = StorageUtil.GetIntValue(None, "FC_PresetId", 50)
        SetInfoText(PresetFullInfo(cur))
    EndEvent
EndState

State FCTESTTARGET
    Event OnMenuOpenST()
        Int cur = StorageUtil.GetIntValue(None, "FC_TestTargetIdx", 0)
        SetMenuDialogStartIndex(cur)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(TestTargetList())
    EndEvent
    Event OnMenuAcceptST(Int index)
        If index < 0 || index > 1
            Return
        EndIf
        StorageUtil.SetIntValue(None, "FC_TestTargetIdx", index)
        SetMenuOptionValueST(TestTargetLabel(index))
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FC_TestTargetIdx", 0)
        SetMenuOptionValueST(TestTargetLabel(0))
    EndEvent
    Event OnHighlightST()
        SetInfoText("Select whether the out-of-combat test strike targets the actor under your crosshair (or nearest loaded NPC) or your own player character.")
    EndEvent
EndState

State FCTESTPART
    Event OnMenuOpenST()
        Int cur = StorageUtil.GetIntValue(None, "FC_TestPartIdx", 0)
        SetMenuDialogStartIndex(cur)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(TestPartList())
    EndEvent
    Event OnMenuAcceptST(Int index)
        If index < 0 || index > 10
            Return
        EndIf
        StorageUtil.SetIntValue(None, "FC_TestPartIdx", index)
        SetMenuOptionValueST(TestPartLabel(index))
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FC_TestPartIdx", 0)
        SetMenuOptionValueST(TestPartLabel(0))
    EndEvent
    Event OnHighlightST()
        SetInfoText("Select which body region patch to strike. Repeated strikes on the same patch progressively peel Armour -> Skin -> Flesh -> Bone.")
    EndEvent
EndState

State FCTESTFAM
    Event OnMenuOpenST()
        Int cur = StorageUtil.GetIntValue(None, "FC_TestFamIdx", 0)
        SetMenuDialogStartIndex(cur)
        SetMenuDialogDefaultIndex(0)
        SetMenuDialogOptions(TestFamList())
    EndEvent
    Event OnMenuAcceptST(Int index)
        If index < 0 || index > 5
            Return
        EndIf
        StorageUtil.SetIntValue(None, "FC_TestFamIdx", index)
        SetMenuOptionValueST(TestFamLabel(index))
    EndEvent
    Event OnDefaultST()
        StorageUtil.SetIntValue(None, "FC_TestFamIdx", 0)
        SetMenuOptionValueST(TestFamLabel(0))
    EndEvent
    Event OnHighlightST()
        SetInfoText("Select which weapon/magic family to simulate against the target's worn armour and exposed layers.")
    EndEvent
EndState

State FCTESTSTRIKE
    Event OnSelectST()
        String tCode = TestTargetCode(StorageUtil.GetIntValue(None, "FC_TestTargetIdx", 0))
        String pCode = TestPartCode(StorageUtil.GetIntValue(None, "FC_TestPartIdx", 0))
        String fCode = TestFamCode(StorageUtil.GetIntValue(None, "FC_TestFamIdx", 0))
        FL_Api.TestStrike("MCM", tCode, pCode, fCode, 11.0)
        ShowMessage("Test Strike queued (" + fCode + " on " + pCode + " -> " + tCode + ").\nClose the menu to watch the strike land and see the Armour/Layer report at the top-left.", false)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Queues a non-hostile test strike on the selected patch without aggroing or killing the target. Watch Armour -> Skin -> Flesh -> Bone peel stage by stage.")
    EndEvent
EndState

State FCTESTRESTORE
    Event OnSelectST()
        String tCode = TestTargetCode(StorageUtil.GetIntValue(None, "FC_TestTargetIdx", 0))
        FL_Api.TestRestore("MCM", tCode)
        ShowMessage("Restore queued for " + tCode + ". Close the menu to watch all armour, skin, flesh, and bone layers restore.", false)
    EndEvent
    Event OnHighlightST()
        SetInfoText("Restores the test target's worn armour, skin, flesh, and bone layers back to 100%.")
    EndEvent
EndState

