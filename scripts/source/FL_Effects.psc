Scriptname FL_Effects extends Quest
{LEGIBILITY AND BEHAVIOUR. FleshCore's own listener for
 its events, on FL_HooksQuest (0x948):
   * FL_Wounded  -> the FL_WoundedFX ability goes on them (the per-actor
                    marker a has_magic_effect condition can read), and the
                    EFFECT RULES are evaluated over the event's partsRemain
                    column: rows (part, maxRemainPct, ability, prio) added by
                    FL_Api.AddEffectRule -- the ability is on them while the
                    part's attachment is BELOW the percentage.
   * FL_Restored -> everything comes off.
 Parts a rule may name: any lattice part name, or leg / arm / head / trunk
 (either leg, either arm, the head, chest-or-abdomen). No idle is ever
 forced: abilities only, per standard warning about animating actors.
 A head wound also staggers them (the Dazed row's other half), by animation
 event, only if they are not dead, not animating a scene and not paralysed.}

Event OnInit()
    Rearm()
EndEvent

Function Rearm()
    RegisterForModEvent("FL_Wounded", "OnFLWounded")
    RegisterForModEvent("FL_Restored", "OnFLRestored")
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
EndFunction

Event OnFleshCoreReload(String eventName, String strArg, Float numArg, Form sender)
    Rearm()
EndEvent

Spell Function WoundedFX()
    Return Game.GetFormFromFile(0x0000094A, "FleshCore.esp") as Spell
EndFunction

Event OnFLWounded(String eventName, String strArg, Float numArg, Form sender)
    Actor target = sender as Actor
    If !target
        Return
    EndIf
    Spell fx = WoundedFX()
    If fx && !target.HasSpell(fx)
        target.AddSpell(fx, false)
    EndIf
    String touched = FL_Api.Field(strArg, 5)
    String remain = FL_Api.Field(strArg, 6)
    Evaluate(target, remain)
    If Remaining(remain, "leg") < 34 && !target.IsDead() && target != Game.GetPlayer()
        ; An NPC whose thigh or calf has been severed cannot walk on air; force bleedout/knockdown
        target.SetNoBleedoutRecovery(true)
        target.PushActorAway(target, 0.5)
        Float curHP = target.GetActorValue("Health")
        If curHP > 0.0
            target.DamageActorValue("Health", curHP + 50.0)
        EndIf
    ElseIf StringUtil.Find("," + touched + ",", ",head,") >= 0 && !target.IsDead() && !target.IsInKillMove()
        ; a head wound dazes them: a short stagger, no idle forced
        target.SetAnimationVariableFloat("staggerDirection", 0.5)
        target.SetAnimationVariableFloat("StaggerMagnitude", 0.3)
        Debug.SendAnimationEvent(target, "staggerStart")
    EndIf
EndEvent

Event OnFLRestored(String eventName, String strArg, Float numArg, Form sender)
    Actor target = sender as Actor
    If !target
        Return
    EndIf
    target.SetNoBleedoutRecovery(false)
    If Game.IsPluginInstalled("FEC.esp")
        FEC_Utility.AssignPermanentDeathEffect(target, -1)
        FEC_Utility.AssignTemporaryDeathEffect(target, -1)
        FEC_Utility.SendFECResetEvent(target, 0, true)
        FEC_Utility.SendFECResetEvent(target, 1, true)
        FEC_Utility.ResetHead(target)
        PO3_SKSEFunctions.RemoveAllModItems(target, "FEC.esp", false)
        PO3_SKSEFunctions.StopAllShaders(target)
        PO3_SKSEFunctions.ResetActor3D(target, "po3_FEC")
        PO3_SKSEFunctions.SetSkinAlpha(target, 1.0)
        target.SetAlpha(1.0, false)
    EndIf
    Spell fx = WoundedFX()
    If fx && target.HasSpell(fx)
        target.RemoveSpell(fx)
    EndIf
    Int n = StorageUtil.StringListCount(self, "FC_effect_rules")
    Int i = 0
    While i < n
        String[] f = StringUtil.Split(StorageUtil.StringListGet(self, "FC_effect_rules", i), "|")
        If f.Length >= 5
            Spell s = StorageUtil.GetFormValue(self, "FC_effect_spell_" + f[1]) as Spell
            If s && target.HasSpell(s)
                target.RemoveSpell(s)
            EndIf
        EndIf
        i += 1
    EndWhile
EndEvent

Int Function Remaining(String remain, String part)
    {The lowest attachment among the parts a rule name covers.}
    If part == "leg"
        Return Lowest(remain, "lthigh", "lcalf", "rthigh", "rcalf")
    ElseIf part == "arm"
        Return Lowest(remain, "lupperarm", "lforearm", "rupperarm", "rforearm")
    ElseIf part == "trunk"
        Return Lowest(remain, "chest", "abdomen", "chest", "abdomen")
    EndIf
    Return FL_Api.PartRemaining(remain, part)
EndFunction

Int Function Lowest(String remain, String a, String b, String c, String d)
    Int v = FL_Api.PartRemaining(remain, a)
    Int w = FL_Api.PartRemaining(remain, b)
    If w < v
        v = w
    EndIf
    w = FL_Api.PartRemaining(remain, c)
    If w < v
        v = w
    EndIf
    w = FL_Api.PartRemaining(remain, d)
    If w < v
        v = w
    EndIf
    Return v
EndFunction

Function Evaluate(Actor target, String remain)
    Int n = StorageUtil.StringListCount(self, "FC_effect_rules")
    Int i = 0
    While i < n
        String[] f = StringUtil.Split(StorageUtil.StringListGet(self, "FC_effect_rules", i), "|")
        If f.Length >= 5
            Spell s = StorageUtil.GetFormValue(self, "FC_effect_spell_" + f[1]) as Spell
            If s
                Bool want = Remaining(remain, f[2]) < (f[3] as Int)
                If want && !target.HasSpell(s)
                    target.AddSpell(s, false)
                    Debug.Trace("[FleshCore] effects: " + f[0] + " rule " + f[1] + " puts " + s.GetName() + " on " + target)
                ElseIf !want && target.HasSpell(s)
                    target.RemoveSpell(s)
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction
