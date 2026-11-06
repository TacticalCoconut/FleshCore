Scriptname FL_Knockout extends ActiveMagicEffect
{KNOCKOUT -- they go down and are never offered the chance to rise.

 The mechanism lives in FL_KO_Hold; the note at the top of that file explains
 why the first attempt could not have worked and what replaced it. This is the
 aimed spell that calls it.

 THIS FILE STRIPS NO PROTECTION, because stripping it does real and
 lasting damage to a save.

 The old knockout called ActorBase.SetProtected(false) and SetEssential(false)
 on every target. ActorBase is the BASE FORM, not the actor -- ActorBase.psc's
 own GetDeadCount is documented as "the number of actors of this type that have
 been killed", which is only meaningful because one base backs many actors. So
 clearing those flags on a generic guard did not un-essential ONE guard. It
 un-essentialed every actor sharing that base, permanently, for the life of the
 save.

 It was copied out of FL_Wound's kill path, where clearing the flags is right
 because the point there is to make a kill LAND. A knockout has no kill to
 land. It bought nothing, and it cost that.

 It also actively broke the old mechanism: the flags it cleared are exactly the
 ones that give an actor a bleedout to be held in.}

Quest Property Register = None Auto
{FL_KO_Hold. Holds the state and the watchdog.}

Float Property Shove = 1.0 Auto
{The push that turns a fold into a fall. Small: the point is the ragdoll.}

Float Property Seconds = 3600.0 Auto
{The watchdog's deadline: one in-real-life
 hour. One hour is safe to give now in a way it was not before -- nothing this
 spell does defers a kill, so an expired hold leaves nobody invulnerable.}

Bool Property FreezeAI = false Auto
{RETIRED, AND FALSE IN THE PLUGIN. Switching the target's AI off was
 the earlier hold, and a later test showed what it does: the
 behaviour graph stops where it is (statues mid-get-up, A-poses), the queued
 ragdoll never runs, and a death started with the AI off never completes.
 FL_KO_Hold no longer reads this -- the hold is the Paralysis actor value now,
 see the note at the top of that file -- and the plugin's copy was set to
 False so the record does not claim something the code does not do. It is
 still passed, because PutDown's signature is bound by position.}

Float Property Settle = 0.0 Auto
{RETIRED. It was the wait between the push and the AI freeze; there
 is no freeze, so there is nothing to wait for. Still passed, for the same
 reason as FreezeAI; nothing reads it.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    If !akTarget
        Return
    EndIf
    FL_KO_Hold reg = Register as FL_KO_Hold
    If !reg
        ; NOT SILENT. An unwired Register is a plugin defect and the caster
        ; should hear it, not watch nothing happen.
        Debug.Notification("[FleshCore] knockout is not wired up")
        Return
    EndIf
    If akTarget.IsDead()
        Debug.Notification("[FleshCore] the target is already dead")
        Return
    EndIf
    If reg.IsHeld(akTarget)
        Debug.Notification("[FleshCore] already knocked out")
        Return
    EndIf
    ; NO FLAG CLEARING. See the note above. They are left exactly as they were.
    ; FreezeAI and Settle are retired and ignored -- passed only because the
    ; call is bound by position.
    If reg.PutDown(akTarget, akCaster, Seconds, Shove, FreezeAI, Settle)
        Debug.Notification("[FleshCore] knocked out")
    Else
        ; THE REGISTER REFUSED THEM AND THE PLAYER IS TOLD. The old hold's
        ; worst lie was "already knocked out" on a target standing up straight.
        Debug.Notification("[FleshCore] the knockout did not take")
    EndIf
EndEvent
