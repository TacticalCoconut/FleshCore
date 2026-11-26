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
 forced: abilities only, because an idle forced on an actor who is already
 animating breaks what they are doing.
 A head wound also staggers them (the Dazed row's other half), by animation
 event, only if they are not dead and not in a kill move.}

Event OnInit()
    Rearm()
EndEvent

Function Rearm()
    RegisterForModEvent("FL_Wounded", "OnFLWounded")
    RegisterForModEvent("FL_PartLost", "OnFLPartLost")
    RegisterForModEvent("FL_BoneCrack", "OnFLBoneCrack")
    RegisterForModEvent("FL_Restored", "OnFLRestored")
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
EndFunction

Event OnFleshCoreReload(String eventName, String strArg, Float numArg, Form sender)
    Rearm()
EndEvent

Spell Function WoundedFX()
    Return Game.GetFormFromFile(0x0000094A, "FleshCore.esp") as Spell
EndFunction

Sound Function BoneCrackSound()
    Return Game.GetFormFromFile(0x00000F41, "FleshCore.esp") as Sound
EndFunction

Event OnFLBoneCrack(String eventName, String strArg, Float numArg, Form sender)
    Actor target = sender as Actor
    If !target || !target.Is3DLoaded()
        Return
    EndIf
    Sound snd = BoneCrackSound()
    If snd
        snd.Play(target)
    EndIf
EndEvent

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
    If StringUtil.Find("," + touched + ",", ",head,") >= 0 && !target.IsDead() && !target.IsInKillMove()
        ; a head wound dazes them: a short stagger, no idle forced
        target.SetAnimationVariableFloat("staggerDirection", 0.5)
        target.SetAnimationVariableFloat("StaggerMagnitude", 0.3)
        Debug.SendAnimationEvent(target, "staggerStart")
    EndIf
EndEvent

Event OnFLPartLost(String eventName, String strArg, Float numArg, Form sender)
    Actor target = sender as Actor
    If !target
        Return
    EndIf
    String partKey = FL_Api.Field(strArg, 0)
    Int lostMask = FL_Api.Field(strArg, 1) as Int
    Int flags = FL_Api.Field(strArg, 2) as Int
    If partKey == "head" && Game.IsPluginInstalled("Next-Gen Decapitations.esp")
        If NGDecapitations.IsDecapitated(target)
            NGDecapitations.RemoveHead(target)
        EndIf
    EndIf
    Bool lethal = (flags % 2 == 1) && ((flags / 2048) % 2 == 0) && !FL_Api.NoKill(target)
    If !target.IsDead() && !lethal
        Bool lMajor = Math.LogicalAnd(lostMask, 3072) != 0
        Bool rMajor = Math.LogicalAnd(lostMask, 24576) != 0
        Bool lAny = lMajor || (Math.LogicalAnd(lostMask, 4096) != 0)
        Bool rAny = rMajor || (Math.LogicalAnd(lostMask, 32768) != 0)
        Float desired = 0.0
        If lAny && rAny
            desired = -85.0
        ElseIf lMajor || rMajor
            desired = -65.0
        ElseIf lAny || rAny
            desired = -35.0
        EndIf
        Float prev = StorageUtil.GetFloatValue(target, "FC_SpeedPenalty", 0.0)
        If desired != prev
            Float delta = desired - prev
            target.ModActorValue("SpeedMult", delta)
            StorageUtil.SetFloatValue(target, "FC_SpeedPenalty", desired)
            target.DamageActorValue("CarryWeight", 0.1)
            target.RestoreActorValue("CarryWeight", 0.1)
            target.EvaluatePackage()
        EndIf
        Actor player = Game.GetPlayer()
        If desired <= -85.0 && prev > -85.0
            If target != player && !target.IsInKillMove()
                target.SetNoBleedoutRecovery(true)
                If player
                    player.PushActorAway(target, 1.5)
                EndIf
                Debug.SendAnimationEvent(target, "BleedOutStart")
            ElseIf target == player && !target.IsInKillMove()
                target.SetAnimationVariableFloat("staggerDirection", 0.5)
                target.SetAnimationVariableFloat("StaggerMagnitude", 0.6)
                Debug.SendAnimationEvent(target, "staggerStart")
            EndIf
        ElseIf desired <= -65.0 && prev > -65.0
            If !target.IsInKillMove()
                If target != player && player
                    player.PushActorAway(target, 1.2)
                ElseIf target == player
                    target.SetAnimationVariableFloat("staggerDirection", 0.5)
                    target.SetAnimationVariableFloat("StaggerMagnitude", 0.4)
                    Debug.SendAnimationEvent(target, "staggerStart")
                EndIf
            EndIf
        EndIf
    EndIf
EndEvent

Event OnFLRestored(String eventName, String strArg, Float numArg, Form sender)
    Actor target = sender as Actor
    If !target
        Return
    EndIf
    Float prev = StorageUtil.GetFloatValue(target, "FC_SpeedPenalty", 0.0)
    If prev != 0.0
        If FL_Api.Field(strArg, 0) != "resurrect"
            target.ModActorValue("SpeedMult", -prev)
            target.DamageActorValue("CarryWeight", 0.1)
            target.RestoreActorValue("CarryWeight", 0.1)
            target.EvaluatePackage()
        EndIf
        StorageUtil.UnsetFloatValue(target, "FC_SpeedPenalty")
    EndIf
    target.SetNoBleedoutRecovery(false)
    If target != Game.GetPlayer() && target.IsBleedingOut()
        Debug.SendAnimationEvent(target, "BleedOutStop")
    EndIf
    If Game.IsPluginInstalled("Dismembering Framework.esm") && DismemberingFramework.IsDismembered(target)
        DismemberingFramework.ResetActorLimbs(target)
    EndIf
    ; FEC marks only the dead, so only the dead, the down and the resurrected are
    ; cleaned: the cleanup resets their 3D (PO3 ResetActor3D), and a Restore must
    ; not do that to a living actor still on their feet (same rule as FL_Watch).
    If Game.IsPluginInstalled("FEC.esp") && (FL_Api.Field(strArg, 0) == "resurrect" || target.IsDead() || target.IsBleedingOut() || target.IsUnconscious())
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
