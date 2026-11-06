Scriptname FL_Decal extends ActiveMagicEffect
{THE ACTOR HALF, BACK WHERE IT BELONGS.

 The paint was once moved out to the marker on the reading that this never ran.
 A later log says otherwise:

     [DecalCore] FL_Decal DID fire, kind 0, target [Actor <...>]

 Direct delivery works. An Aimed effect whose projectile carries the Explosion
 flag DOES reach the actor it hits, and leaving this in as a one-line probe is
 the only reason that was ever found out. The older log was written before
 FL_Decal was installed.

 So the paint comes back here, and that fixes the thing the marker could never
 do properly: the marker asks WHO IS STANDING NEAREST, and near is not the same
 as hit. In play that painted bystanders and sometimes nobody. This is
 handed akTarget -- the target the engine says was struck -- and there is no
 guessing left in it.}

Int Property Kind = 0 Auto
{kind 0 or kind 1, set per spell on the magic effect.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    If akTarget == None
        Return
    EndIf

    ; NO AGGRO, AND THE RECORDS ALONE WERE NOT ENOUGH.
    ;
    ; The effect is not Hostile -- the same setting every wound spell here uses
    ; -- and that stops it being an ASSAULT. It does not stop the engine
    ; treating a projectile landing on them as a reason to fight, which is why
    ; spamming it started fights the records said were impossible. The wound
    ; spells never showed this because their targets do not live long enough to
    ; get angry.
    akTarget.StopCombatAlarm()
    akTarget.StopCombat()

    ; EVERY AREA THAT HAS SKIN, NOT JUST BODY AND FACE.
    ;
    ; Field report: some NPCs were not being marked. An overlay is painted
    ; into their SKIN, and skin under armour is not drawn -- so a fully-armoured
    ; NPC took the paint on their body and showed nothing, because the body was
    ; never on screen. RaceMenu's shipped skee64.ini gives
    ; body 6 layers, hands 3, feet 3, face 3, and bImmediateFace=0,
    ; which means a face overlay is not guaranteed to appear the moment it is
    ; written.
    ;
    ; Painting all four costs three extra calls and means whatever skin IS
    ; showing gets marked -- bare arms, bare feet, a face under an open helm.
    ; It does not solve armour, which needs the armour itself textured and is a
    ; different job; it stops the common case of a mark landing somewhere
    ; invisible while the log says it succeeded.
    If !DC_Api.PaintReady()
        Debug.Trace("[DecalCore] hit " + akTarget + " kind " + Kind \
                    + " -- NOT PAINTED: skee (RaceMenu) reports no plugin version," \
                    + " so there are no overlay layers to write to")
        Return
    EndIf

    Bool had = NiOverride.HasOverlays(akTarget)
    Int body  = DC_Api.Paint(akTarget, Kind, DC_Api.BODY(), 1.0)
    Int hands = DC_Api.Paint(akTarget, Kind, DC_Api.HANDS(), 1.0)
    Int feet  = DC_Api.Paint(akTarget, Kind, DC_Api.FEET(), 1.0)
    Int face  = DC_Api.Paint(akTarget, Kind, DC_Api.FACE(), 1.0)

    ; THE TRACE NAMES EVERY NUMBER A DIAGNOSIS NEEDS. When one of
    ; these comes back -1 the log says whether the actor had overlay nodes
    ; before Paint asked, and how many layers each area reports -- which separates
    ; "the race has no overlay support" from "every layer was already full"
    ; from "skee is not running" from the log alone.
    Debug.Trace("[DecalCore] hit " + akTarget + " kind " + Kind \
                + " hadOverlays=" + had \
                + " layers b/h/f/fa=" + DC_Api.LayerCount(DC_Api.BODY()) \
                + "/" + DC_Api.LayerCount(DC_Api.HANDS()) \
                + "/" + DC_Api.LayerCount(DC_Api.FEET()) \
                + "/" + DC_Api.LayerCount(DC_Api.FACE()) \
                + " painted b/h/f/fa=" + body + "/" + hands + "/" + feet + "/" + face)
EndEvent
