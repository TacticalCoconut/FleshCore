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
    If !akTarget || !Register
        Return
    EndIf
    FL_KO_Hold reg = Register as FL_KO_Hold
    If !reg
        Return
    EndIf
    If !reg.IsHeld(akTarget)
        ; NOT AN ERROR, AND NOT SILENT. Curing somebody who is merely lying
        ; there for another reason -- Acheron has defeated them, another mod is
        ; holding them down, they are dead -- must not pretend to have done something.
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
