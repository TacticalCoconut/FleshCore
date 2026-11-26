Scriptname FL_GrindHook extends ActiveMagicEffect
{Grinder Hook: a chain from the nearest grinder to the one hit, reeled in, and
 FleshCore's grind the moment they reach the spinning rollers. Every chain call
 goes through FL_LeashBridge, behind FL_GrinderSpells.ChainReady().}

Activator Property GrinderActivator Auto
Static Property XMarkerBase Auto
Sound Property Crunch Auto

; ---- HOW IT RUNS -----------------------------------------------------------
;
; The chain goes on at the nip between the rollers (70 above the grinder's base)
; with Leash Framework's ragdoll pull on, and is shortened 0.5 every 0.06 s down
; to 8. The first check that finds them in the rollers' contact box while the
; rollers bite grinds them. When the pull stops gaining ground for STALL_SECS (a
; door, a corner, a body that cannot walk) or 10 s pass, the winch finishes it:
; the chain comes off, then a MoveTo to the feed side and the grind. Rollers that
; never come up to speed in 10 s let go.
;
; When no chain can go on (Leash Framework fastens it to the "NPC Neck [Neck]"
; node, which a creature's skeleton does not have), the hook does not refuse
; them: the winch takes them as soon as the rollers bite, the same way.
;
; One owner for the body: every chain on them comes off (FL_LeashBridge, in the
; safe order) before FleshCore's grind or the kill, and the effect never moves
; them itself while the chain is on.
;
; Every path that ends the hook first takes the target into a local and clears
; _target, so an OnEffectFinish that runs during one of the waits finds nothing
; left to undo. Dispel and UnregisterForUpdate are never called once the effect
; has finished (on an ended effect they only log an error).

Float Property STALL_SECS = 2.5 AutoReadOnly
Float Property HOOK_RANGE = 2500.0 AutoReadOnly
Float Property CHAIN_MIN = 8.0 AutoReadOnly
Float Property CHAIN_START = 12.0 AutoReadOnly

Actor _target = None
ObjectReference _grinder = None
FL_GrinderRef _gscript = None
Float _pinchX = 0.0
Float _pinchY = 0.0
Float _pinchZ = 0.0
Float _curMax = 0.0
Float _startedAt = 0.0
Bool _active = false
Bool _consumed = false
Bool _ownsChain = false
; No chain went on (see HOW IT RUNS): the winch takes them once the rollers bite.
Bool _winchOnly = false
; The actor whose FL_GrindHookBusy mark this effect set, from the moment it is
; set until it is cleared, so OnEffectFinish can clear it even when the effect
; ends before the chain is on.
Actor _busyActor = None
Bool _finished = false
; Reel progress: the closest they have come, and when.
Float _bestDist = 999999.0
Float _bestAt = 0.0

Function EndEffect()
    If !_finished
        Dispel()
    EndIf
EndFunction

Event OnEffectStart(Actor akTarget, Actor akCaster)
    Actor pl = Game.GetPlayer()
    If akTarget == None || akTarget == pl || akTarget.IsDead() || akTarget.IsDisabled() || akTarget.IsDeleted() || !akTarget.Is3DLoaded()
        EndEffect()
        Return
    EndIf
    If !FL_GrinderSpells.ChainReady()
        Debug.Notification("The Grinder Hook needs Leash Framework, which did not load.")
        EndEffect()
        Return
    EndIf
    ; FleshCore never wounds a child (FL_Wound.WhyRefused).
    If FL_GrinderRef.IsChildLike(akTarget)
        EndEffect()
        Return
    EndIf
    ; Already on a hook, or already in the rollers.
    If StorageUtil.GetIntValue(akTarget, "FL_GrindHookBusy", 0) != 0 || StorageUtil.GetIntValue(akTarget, "FL_GrinderClaimed", 0) != 0
        EndEffect()
        Return
    EndIf
    ; Marked before the chain goes on, so the rollers' bystander check cannot take
    ; them in the gap before it holds.
    StorageUtil.SetIntValue(akTarget, "FL_GrindHookBusy", 1)
    _busyActor = akTarget

    ; The grinder must stand in the target's own cell, within HOOK_RANGE.
    Cell targetCell = akTarget.GetParentCell()
    ObjectReference g = StorageUtil.GetFormValue(None, "FL_GrinderActive") as ObjectReference
    If g != None
        If g.IsDisabled() || g.IsDeleted() || g.GetParentCell() != targetCell || akTarget.GetDistance(g) > HOOK_RANGE
            g = None
        EndIf
    EndIf
    If g == None && GrinderActivator != None
        g = Game.FindClosestReferenceOfTypeFromRef(GrinderActivator, akTarget, HOOK_RANGE)
        If g != None && g.GetParentCell() != targetCell
            g = None
        EndIf
    EndIf
    If g == None
        StorageUtil.UnsetIntValue(akTarget, "FL_GrindHookBusy")
        _busyActor = None
        Debug.Notification("No grinder within range. Cast Spawn Grinder first.")
        EndEffect()
        Return
    EndIf

    ; The anchor sits in the nip between the two rollers. A grinder without this
    ; script (another mod's copy of the activator) uses the same height.
    _gscript = g as FL_GrinderRef
    Float pinchUp = 70.0
    If _gscript != None
        pinchUp = _gscript.GetPinchZOffset()
    EndIf
    _pinchX = g.GetPositionX()
    _pinchY = g.GetPositionY()
    _pinchZ = g.GetPositionZ() + pinchUp
    Cell anchorCell = g.GetParentCell()
    If anchorCell == None
        anchorCell = targetCell
    EndIf

    ; A chain from another mod on them comes off first (the chained end only:
    ; chains they hold stay on). One actor can be the chained end of one chain.
    If FL_LeashBridge.IsHeld(akTarget)
        FL_LeashBridge.CutHeldEnd(akTarget)
    EndIf
    ; The effect may have ended during that wait: do not put the chain on at all.
    If _finished
        AbortBeforeReel(akTarget, false)
        Return
    EndIf

    Bool attached = FL_LeashBridge.HookChain(akTarget, anchorCell, _pinchX, _pinchY, _pinchZ, CHAIN_MIN, CHAIN_START)
    ; The effect ended while the chain was going on: take it back off (if it went on).
    If _finished
        AbortBeforeReel(akTarget, attached)
        Return
    EndIf

    _target = akTarget
    _grinder = g
    _curMax = CHAIN_START
    _startedAt = Utility.GetCurrentRealTime()
    _bestDist = 999999.0
    _bestAt = _startedAt
    _active = true
    _consumed = false
    _ownsChain = attached
    _winchOnly = !attached

    ; Only now that the chain holds (and OnEffectFinish owns its removal): spin
    ; the rollers up if they are still.
    If _gscript != None && !_gscript.IsOn()
        _gscript.RequestPower(true)
    EndIf
    If _finished || _target == None
        Return
    EndIf
    RegisterForSingleUpdate(0.06)
EndEvent

Event OnUpdate()
    If !_active || _consumed || _target == None || _grinder == None
        ReleaseChainOnly()
        Return
    EndIf
    If _target.IsDead() || _target.IsDisabled() || _target.IsDeleted() || !_target.Is3DLoaded() || _grinder.IsDisabled() || _grinder.IsDeleted() || _target.GetParentCell() != _grinder.GetParentCell()
        ReleaseChainOnly()
        Return
    EndIf

    If _winchOnly
        ; No chain on them: the winch takes them once the rollers bite, or lets go
        ; after 10 s of rollers that never came up to speed.
        Bool bites = true
        If _gscript != None
            bites = _gscript.IsLethalNow()
        EndIf
        Float waited = Utility.GetCurrentRealTime() - _startedAt
        If bites && waited >= 0.2
            _consumed = true
            _active = false
            WinchAndGrind()
        ElseIf waited >= 10.0
            ReleaseChainOnly()
        Else
            RegisterForSingleUpdate(0.06)
        EndIf
        Return
    EndIf

    Float dx = _target.GetPositionX() - _pinchX
    Float dy = _target.GetPositionY() - _pinchY
    Float dz = _target.GetPositionZ() - _pinchZ
    Float dist = Math.Sqrt(dx * dx + dy * dy + dz * dz)
    Float elapsed = Utility.GetCurrentRealTime() - _startedAt

    ; Contact: the grinder's roller box (at the spine) or within 75 of the nip.
    ; Bite: the rollers turn fast enough (always so on a grinder without the script).
    Bool touching = dist <= 75.0
    Bool biting = true
    If _gscript != None
        touching = touching || _gscript.IsInContactZone(_target)
        biting = _gscript.IsLethalNow()
    EndIf

    If touching && biting && elapsed >= 0.2
        _consumed = true
        _active = false
        GrindTarget()
        Return
    EndIf

    ; Reel progress. A pull that has stopped gaining ground, or has run out of
    ; time, is finished by the winch.
    Float now = Utility.GetCurrentRealTime()
    If dist < _bestDist - 12.0
        _bestDist = dist
        _bestAt = now
    EndIf
    Bool stalled = elapsed >= 1.0 && (now < _bestAt || (now - _bestAt) >= STALL_SECS)
    If stalled || elapsed >= 10.0
        If biting
            _consumed = true
            _active = false
            WinchAndGrind()
            Return
        ElseIf elapsed >= 10.0
            ; The rollers never came up to speed: let go.
            ReleaseChainOnly()
            Return
        EndIf
    EndIf

    ; A save loaded without Leash Framework in the middle of a reel: let go, and
    ; call nothing of it (CutChain below asks the same gate).
    If !FL_GrinderSpells.ChainReady()
        ReleaseChainOnly()
        Return
    EndIf
    _curMax = _curMax - 0.5
    If _curMax < CHAIN_MIN
        _curMax = CHAIN_MIN
    EndIf
    FL_LeashBridge.SetReach(_target, _curMax)
    RegisterForSingleUpdate(0.06)
EndEvent

; Every chain call after the start asks the gate again, so an effect that
; outlives Leash Framework (a save loaded without it) calls nothing of it.
Function CutChain(Actor akWho)
    If FL_GrinderSpells.ChainReady()
        FL_LeashBridge.CutHookChain(akWho)
    EndIf
EndFunction

Function CutEvery(Actor akWho)
    If FL_GrinderSpells.ChainReady()
        FL_LeashBridge.CutAll(akWho)
    EndIf
EndFunction

; The hook lets go without a grind: our chain comes off, nothing else.
Function ReleaseChainOnly()
    _active = false
    If !_finished
        UnregisterForUpdate()
    EndIf
    Actor v = _target
    Bool owned = _ownsChain
    _ownsChain = false
    _target = None
    If owned && v != None
        CutChain(v)
        StorageUtil.UnsetIntValue(v, "FL_GrindHookBusy")
        _busyActor = None
    EndIf
    EndEffect()
EndFunction

; The pull stalled or ran out of time while the rollers bite: the winch hauls them
; the rest of the way. The chain comes off first (with its settle), and only then
; the MoveTo onto the floor in front of the feed side (local +Y 64: just outside
; the solid box, which ends at 48, and inside the contact box), and the grind.
Function WinchAndGrind()
    If !_finished
        UnregisterForUpdate()
    EndIf
    Actor v = _target
    _target = None
    _ownsChain = false
    If v == None || _grinder == None
        GrindTarget(v)
        Return
    EndIf
    CutEvery(v)
    If !v.IsDead() && !v.IsDisabled() && !v.IsDeleted() && !_grinder.IsDisabled() && !_grinder.IsDeleted()
        Debug.Notification("The hook's winch drags " + v.GetDisplayName() + " into the rollers.")
        Float a = _grinder.GetAngleZ()
        v.MoveTo(_grinder, 64.0 * Math.Sin(a), 64.0 * Math.Cos(a), 0.0, false)
    EndIf
    GrindTarget(v)
EndFunction

; Undoes a hook that ends before the reel starts. abChainWasOn: the chain had gone on.
Function AbortBeforeReel(Actor akTarget, Bool abChainWasOn)
    If akTarget == None
        Return
    EndIf
    If abChainWasOn
        CutChain(akTarget)
    EndIf
    StorageUtil.UnsetIntValue(akTarget, "FL_GrindHookBusy")
    _busyActor = None
EndFunction

; akV: the target when the caller has already taken it (WinchAndGrind); else _target.
Function GrindTarget(Actor akV = None)
    If !_finished
        UnregisterForUpdate()
    EndIf
    Actor v = akV
    If v == None
        v = _target
    EndIf
    _target = None
    _ownsChain = false
    If v == None
        EndEffect()
        Return
    EndIf
    StorageUtil.SetIntValue(v, "FL_GrinderClaimed", 1)

    ; 1. Every chain comes off first, in the safe order (it returns at once when
    ;    the winch already took it off).
    CutEvery(v)

    If v.IsDisabled() || v.IsDeleted()
        StorageUtil.UnsetIntValue(v, "FL_GrindHookBusy")
        StorageUtil.UnsetIntValue(v, "FL_GrinderClaimed")
        _busyActor = None
        EndEffect()
        Return
    EndIf

    ; 2. FleshCore's grind and burst, and the death, on the same tick.
    FL_GrinderRef.GrindAndKill(v, "FL_Grinder")

    ; 3. Sound and blood once the body is already coming apart.
    FL_GrinderRef.PlayGrindCrunch(v, Crunch)
    FL_GrinderRef.GoreBurst(v, _grinder, XMarkerBase)

    StorageUtil.UnsetIntValue(v, "FL_GrindHookBusy")
    _busyActor = None
    EndEffect()
EndFunction

; The effect is already gone when this runs: no native call on it.
Event OnEffectFinish(Actor akTarget, Actor akCaster)
    _finished = true
    _active = false
    ; Ended before the chain went on: the busy mark was set but nothing owns it.
    If !_ownsChain && _busyActor != None
        StorageUtil.UnsetIntValue(_busyActor, "FL_GrindHookBusy")
        _busyActor = None
    EndIf
    Actor v = _target
    Bool owned = _ownsChain
    _ownsChain = false
    _target = None
    If owned && v != None
        CutChain(v)
        StorageUtil.UnsetIntValue(v, "FL_GrindHookBusy")
        _busyActor = None
    EndIf
EndEvent
