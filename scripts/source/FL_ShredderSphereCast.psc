Scriptname FL_ShredderSphereCast extends ActiveMagicEffect
{SHREDDER SPHERE -- the cast, which does nothing but put the field down.

 Self-targeted, so the spell always fires whether or not the crosshair is on
 anybody: an aimed spell that hits nothing produces no magic effect at all,
 and a trap you can only place by hitting someone with it is not a trap.

 WHERE IT LANDS. On whatever the crosshair is resting on, if that is close
 enough to be what was meant; otherwise straight ahead of the caster on the
 ground, Distance out. Skyrim's heading is measured from +Y, so forward is
 (sin, cos) and not the (cos, sin) the reflex writes -- the same convention
 the burst script's rings are built on.

 DISTANCE IS DELIBERATELY LONGER THAN THE FIELD'S OWN OUTER RADIUS. The caster is
 catchable by their own spells, so nothing here excludes them -- but
 a field dropped exactly one outer radius away would swallow them on every cast
 before they could take a step, which is a different thing from being catchable.
 It lands just outside its own reach and they can walk into it if they want to.}

Activator Property Mark = None Auto
{FL_ShredderSphere_Mark -- the invisible Activator carrying FL_ShredderSphere
 and its tuning. Set on the record.}

Float Property Distance = 700.0 Auto
{How far ahead of the caster the field is set, when the crosshair is on
 nothing. Just outside the field's own 512 outer radius.}

Float Property MinDistance = 320.0 Auto
{HOW CLOSE THE CROSSHAIR IS ALLOWED TO PUT IT, and why this exists.

 The crosshair test used to be an upper bound alone: whatever the crosshair was
 resting on within Distance was where the field went. A crosshair resting on a
 barrel, an urn, a chair or a follower two feet away therefore dropped the field
 INSIDE its own 128-unit inner shell, centred on the caster, and a quarter of a
 second later it took them apart where they stood. The caster may be caught by
 their own spells, but not killed by aiming at furniture. Closer than
 this, the crosshair is ignored and the field goes out in front instead.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    Actor who = akCaster
    If !who
        who = akTarget
    EndIf
    If !who
        Return
    EndIf
    If !Mark
        Debug.Trace("[FleshCore] shredder sphere: Mark not set on the record -- nothing placed")
        Return
    EndIf
    ; The same gate every FleshCore cast keeps. A field that cannot cut is not
    ; worth the polling, and the notification is how a disarmed engine is seen.
    If !FL_Wound.CoreActive()
        Debug.Notification("[FleshCore] engine not armed")
        Return
    EndIf
    ObjectReference r = who.PlaceAtMe(Mark, 1, true, false)
    If !r
        Debug.Trace("[FleshCore] shredder sphere: could not place the field")
        Return
    EndIf
    ObjectReference at = Game.GetCurrentCrosshairRef()
    If at && who.GetDistance(at) <= Distance && who.GetDistance(at) >= MinDistance
        r.MoveTo(at, 0.0, 0.0, 0.0, false)
    Else
        Float ang = who.GetAngleZ()
        r.MoveTo(who, Math.Sin(ang) * Distance, Math.Cos(ang) * Distance, 0.0, false)
    EndIf
    Debug.Notification("[FleshCore] shredder sphere set")
EndEvent
