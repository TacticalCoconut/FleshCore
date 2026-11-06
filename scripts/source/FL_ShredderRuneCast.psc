Scriptname FL_ShredderRuneCast extends ActiveMagicEffect
{SHREDDER RUNE -- the cast, which does nothing but arm the trap.

 Self-targeted for the same reason FL_ShredderSphereCast is: a rune is placed
 ON THE GROUND, and an aimed spell that meets no actor raises no effect to
 place it with.

 It lands where a vanilla rune lands: on the surface the crosshair is resting
 on if there is one in reach, and otherwise a stride or two ahead of the
 caster at their own feet height, which is the ground they are standing on.}

Activator Property Mark = None Auto
{FL_ShredderRune_Mark -- the invisible Activator carrying FL_ShredderRune.
 Set on the record.}

Float Property Distance = 256.0 Auto
{How far ahead the rune is laid when the crosshair is on nothing. About three
 and a half metres -- vanilla rune range.}

Float Property MinDistance = 160.0 Auto
{The near bound on the crosshair, for the reason given in FL_ShredderSphereCast:
 an upper bound alone lets a crosshair resting on something underfoot lay the
 rune on the caster's own boots, where its 96-unit trigger catches them on the
 very next poll. Closer than this the crosshair is ignored and the rune goes out
 in front.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    Actor who = akCaster
    If !who
        who = akTarget
    EndIf
    If !who
        Return
    EndIf
    If !Mark
        Debug.Trace("[FleshCore] shredder rune: Mark not set on the record -- nothing placed")
        Return
    EndIf
    If !FL_Wound.CoreActive()
        Debug.Notification("[FleshCore] engine not armed")
        Return
    EndIf
    ObjectReference r = who.PlaceAtMe(Mark, 1, true, false)
    If !r
        Debug.Trace("[FleshCore] shredder rune: could not place the rune")
        Return
    EndIf
    ObjectReference at = Game.GetCurrentCrosshairRef()
    If at && who.GetDistance(at) <= Distance * 2.0 && who.GetDistance(at) >= MinDistance
        r.MoveTo(at, 0.0, 0.0, 0.0, false)
    Else
        Float ang = who.GetAngleZ()
        r.MoveTo(who, Math.Sin(ang) * Distance, Math.Cos(ang) * Distance, 0.0, false)
    EndIf
    Debug.Notification("[FleshCore] shredder rune armed")
EndEvent
