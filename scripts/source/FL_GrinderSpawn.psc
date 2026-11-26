Scriptname FL_GrinderSpawn extends ActiveMagicEffect
{Spawn Grinder: puts a grinder 240 units in front of the caster, its feed side
 facing them, and starts it. One spawned grinder at a time: casting again
 removes the last one this spell made.}

Activator Property GrinderActivator Auto

Event OnEffectStart(Actor akTarget, Actor akCaster)
    Actor who = akCaster
    If who == None
        who = akTarget
    EndIf
    If who == None
        who = Game.GetPlayer()
    EndIf
    If who == None || GrinderActivator == None
        Return
    EndIf

    ; Only a grinder this spell made carries FL_GrinderSpawned, and only such a
    ; grinder is ever removed here.
    ObjectReference oldGrinder = StorageUtil.GetFormValue(None, "FL_GrinderActive") as ObjectReference
    If oldGrinder != None
        If StorageUtil.GetIntValue(oldGrinder, "FL_GrinderSpawned", 0) != 0
            oldGrinder.DisableNoWait()
            oldGrinder.Delete()
        EndIf
        StorageUtil.UnsetFormValue(None, "FL_GrinderActive")
    EndIf

    Float ang = who.GetAngleZ()
    Float ox = who.GetPositionX() + 240.0 * Math.Sin(ang)
    Float oy = who.GetPositionY() + 240.0 * Math.Cos(ang)
    Float oz = who.GetPositionZ()

    ObjectReference grinderRef = who.PlaceAtMe(GrinderActivator, 1, false, false)
    If grinderRef == None
        Debug.Notification("The grinder could not be placed here.")
        Return
    EndIf

    grinderRef.SetPosition(ox, oy, oz)
    grinderRef.SetAngle(0.0, 0.0, ang + 180.0)

    Int tries = 0
    While !grinderRef.Is3DLoaded() && tries < 20
        Utility.Wait(0.1)
        tries += 1
    EndWhile

    StorageUtil.SetFormValue(None, "FL_GrinderActive", grinderRef)
    StorageUtil.SetIntValue(grinderRef, "FL_GrinderSpawned", 1)
    FL_GrinderRef gs = grinderRef as FL_GrinderRef
    If gs != None
        gs.RequestPower(true)
    EndIf
    ; Only the low base (solid up to 44 under a 136-tall frame) can be aimed at,
    ; so the message says where to aim.
    Debug.Notification("Grinder placed. Aim at its base and activate it to switch it on or off.")
EndEvent
