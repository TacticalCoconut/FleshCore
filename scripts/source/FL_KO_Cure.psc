Scriptname FL_KO_Cure extends ActiveMagicEffect
{KNOCKOUT CURE -- the hold comes off and they get up.

 THE OLD CURE KILLED THEM. Field report: casting Knockout Cure killed the target and
 gave the player a bounty. That was not a cure bug as such -- it was the old
 knockout's deferred kill finally landing the moment the cure ended it, on a
 target who had been sitting at minus one health the whole time.

 Nothing in the new hold defers a kill and nothing takes their health away, so
 there is nothing for this to release into a death. FL_KO_Hold.LetUp puts the
 unconscious flag and the Paralysis value back to what they were before the
 hold -- clear and zero, for anybody the hold found standing -- and the engine
 stands them up out of the ragdoll by itself -- which is the second half
 of the design: the cure starts the target's attempt to get up, so they are
 not simply stuck waiting, and the engine does it rather than an animation
 event this file would have to guess at.}

Quest Property Register = None Auto
{FL_KO_Hold.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    ; ---- AND THE SCREEN, WHATEVER ELSE THIS CURE DOES ------------
    ;
    ; THE ESCAPE HATCH FOR A BLACK SCREEN. the retired quest holds the screen with
    ; FadeToBlackHoldImod for the hand-over to the scene framework, and every path out of a
    ; sequence removes it -- but the retired quest lives on a QUEST, and a quest
    ; script cannot be told that a save was loaded (FL_Watch's own note on
    ; OnPlayerLoadGame: it reaches ReferenceAlias, ActiveMagicEffect and the
    ; player's Actor script, never a Quest). So a save made during those few
    ; seconds, or a crash inside them, could in principle come back to a screen
    ; with nothing left running that would lift it.
    ;
    ; This effect is the spell already bound for exactly this shape of
    ; problem -- a stuck target that needs undoing -- and it is an ActiveMagicEffect, so
    ; it runs fresh every cast. Lifting the black is three lines and needs no
    ; reach into the quest: the record is the vanilla one, the removal is
    ; Bethesda's own (FerrySystemScript.psc), and Remove() on an imod
    ; that is not applied does nothing. It runs BEFORE every refusal below,
    ; because a screen nobody can see past is not the moment to be told that
    ; the target is not held by a knockout.
    ImageSpaceModifier hold = Game.GetFormFromFile(0xF756E, "Skyrim.esm") as ImageSpaceModifier
    If hold
        ImageSpaceModifier back = Game.GetFormFromFile(0xF756F, "Skyrim.esm") as ImageSpaceModifier
        If back
            hold.PopTo(back)
        EndIf
        hold.Remove()
    EndIf
    Game.FadeOutGame(false, true, 0.0, 0.5)

    If !akTarget || !Register
        Return
    EndIf
    FL_KO_Hold reg = Register as FL_KO_Hold
    If !reg
        Return
    EndIf
    If !reg.IsHeld(akTarget)
        ; NOT AN ERROR, AND NOT SILENT. Curing somebody who is merely lying
        ; there for another reason -- Acheron has defeated them, they are in a
        ; scene, they are dead -- must not pretend to have done something.
        Debug.Notification("[FleshCore] the target is not held by a knockout")
        Return
    EndIf
    If akTarget.IsDead()
        ; A held corpse. LetUp takes it off the register and leaves it lying;
        ; "released" would be a lie about a body.
        reg.LetUp(akTarget, false)
        Debug.Notification("[FleshCore] the target is dead -- nothing to release")
    ElseIf reg.LetUp(akTarget, true)
        Debug.Notification("[FleshCore] released")
    Else
        ; LetUp says no when a release is already under way for them -- or when
        ; their hour expired between the check above and this call.
        Debug.Notification("[FleshCore] the target is already being released")
    EndIf
EndEvent
