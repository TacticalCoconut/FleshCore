Scriptname FL_GrinderRef extends ObjectReference
{The grinder: two stacked spiked rollers in an iron frame, on FL_Grinder (the
 activator Spawn Grinder places). Power Off, RampUp, Running and RampDown, each
 played as the mesh's own animation of that name. The one on the Grinder Hook
 belongs to FL_GrindHook, which owns their chain.}

Static Property XMarkerBase Auto
Sound Property Crunch Auto

Int Property GRINDER_OFF = 0 AutoReadOnly
Int Property GRINDER_RAMPUP = 1 AutoReadOnly
Int Property GRINDER_RUNNING = 2 AutoReadOnly
Int Property GRINDER_RAMPDOWN = 3 AutoReadOnly

; The ramps last as long as the mesh's RampUp and RampDown animations (3.2 s each:
; two whole turns from rest to full speed, 75 turns a minute, and back).
Float Property RAMP_UP_SECS = 3.2 AutoReadOnly
Float Property RAMP_DOWN_SECS = 3.2 AutoReadOnly
Float Property BITE_AFTER_START = 0.6 AutoReadOnly
Float Property BITE_UNTIL_STOP = 2.0 AutoReadOnly
Float Property CONTACT_POLL = 0.1 AutoReadOnly
; Blend into Running / RampDown, so the switch does not snap the drums to a new angle.
Float Property RUN_EASE_IN = 0.1 AutoReadOnly
Float Property STOP_EASE_IN = 0.15 AutoReadOnly
; The rollers are stacked in the grinder's local Y = 0 plane: the lower drum's
; centre is 44 above the base, the upper one's 96, the teeth reach 31 out (local y
; -31..31, z 13..127). The feed side is local +Y. The solid collision box is
; x -78..78, y -48..48, z 0..44; the frame above it can be walked through.
; The contact box, in grinder-local units, is measured at the body's spine. In
; front of the feed side (+Y) it reaches ZONE_HALF_Y, so a body pulled against
; the rollers counts; behind the machine only ZONE_BACK_Y.
Float Property ZONE_HALF_X = 76.0 AutoReadOnly
Float Property ZONE_HALF_Y = 66.0 AutoReadOnly
Float Property ZONE_BACK_Y = 50.0 AutoReadOnly
Float Property ZONE_MIN_Z = -10.0 AutoReadOnly
Float Property ZONE_MAX_Z = 140.0 AutoReadOnly
; The hook's anchor height above the base: the nip between the two rollers.
Float Property PINCH_Z = 70.0 AutoReadOnly
Float Property SCAN_RADIUS = 220.0 AutoReadOnly

Int _power = 0
Float _phaseAt = 0.0
Int _pending = -1

Event OnInit()
    _power = GRINDER_OFF
    _pending = -1
EndEvent

; ---- asked by FL_GrindHook ------------------------------------------------

Int Function GetPower()
    Return _power
EndFunction

Bool Function IsOn()
    Return _power == GRINDER_RAMPUP || _power == GRINDER_RUNNING
EndFunction

Float Function GetPinchZOffset()
    Return PINCH_Z
EndFunction

; True while the rollers turn fast enough to take a body.
Bool Function IsLethalNow()
    Float t = Utility.GetCurrentRealTime() - _phaseAt
    If t < 0.0
        t = 999.0
    EndIf
    If _power == GRINDER_RUNNING
        Return true
    ElseIf _power == GRINDER_RAMPUP
        Return t >= BITE_AFTER_START
    ElseIf _power == GRINDER_RAMPDOWN
        Return t < BITE_UNTIL_STOP
    EndIf
    Return false
EndFunction

; Queued: the switch happens on the next update, so it is safe from a menu
; (updates do not run while one is open) and from any other thread.
Bool Function RequestPower(Bool abOn)
    If abOn
        _pending = 1
    Else
        _pending = 0
    EndIf
    RegisterForSingleUpdate(0.05)
    Return abOn
EndFunction

Bool Function TogglePower()
    Bool wantOn = (_power == GRINDER_OFF || _power == GRINDER_RAMPDOWN)
    If _pending == 1
        wantOn = false
    ElseIf _pending == 0
        wantOn = true
    EndIf
    Return RequestPower(wantOn)
EndFunction

Bool Function IsInContactZone(Actor akActor)
    If akActor == None || !akActor.Is3DLoaded()
        Return false
    EndIf
    Float[] np = new Float[3]
    Float px = 0.0
    Float py = 0.0
    Float pz = 0.0
    If NetImmerse.GetNodeWorldPosition(akActor, "NPC Spine [Spn0]", np, false)
        px = np[0]
        py = np[1]
        pz = np[2]
    Else
        px = akActor.GetPositionX()
        py = akActor.GetPositionY()
        pz = akActor.GetPositionZ() + 40.0
    EndIf
    Float dz = pz - GetPositionZ()
    If dz < ZONE_MIN_Z || dz > ZONE_MAX_Z
        Return false
    EndIf
    Float dx = px - GetPositionX()
    Float dy = py - GetPositionY()
    Float ang = GetAngleZ()
    Float c = Math.Cos(ang)
    Float s = Math.Sin(ang)
    ; Skyrim turns a reference clockwise about Z: its local +Y faces world
    ; (sin a, cos a) and its local +X faces (cos a, -sin a). These two lines undo
    ; that turn, so the box stays on the rollers at any angle.
    Float lx = dx * c - dy * s
    Float ly = dx * s + dy * c
    Return Math.Abs(lx) <= ZONE_HALF_X && ly <= ZONE_HALF_Y && ly >= -ZONE_BACK_Y
EndFunction

; ---- events -------------------------------------------------------------

Event OnActivate(ObjectReference akActionRef)
    Actor pl = Game.GetPlayer()
    If akActionRef == None || akActionRef != pl
        Return
    EndIf
    If TogglePower()
        Debug.Notification("The grinder clanks and starts to turn.")
    Else
        Debug.Notification("The grinder winds down.")
    EndIf
EndEvent

Event OnLoad()
    ApplyPowerPose()
    If _power != GRINDER_OFF || _pending != -1
        RegisterForSingleUpdate(0.1)
    EndIf
EndEvent

Event OnUnload()
    UnregisterForUpdate()
EndEvent

Event OnUpdate()
    Float now = Utility.GetCurrentRealTime()
    If _phaseAt > now
        ; a time from an earlier game session
        _phaseAt = 0.0
    EndIf
    If _pending == 1
        _pending = -1
        If _power == GRINDER_OFF || _power == GRINDER_RAMPDOWN
            StartRampUp(now)
        EndIf
    ElseIf _pending == 0
        _pending = -1
        If _power == GRINDER_RAMPUP || _power == GRINDER_RUNNING
            StartRampDown(now)
        EndIf
    EndIf
    Float t = now - _phaseAt
    If _power == GRINDER_RAMPUP && t >= RAMP_UP_SECS + 0.25
        ; RampUp ends in 60 s at full speed, so this switch can be late
        _power = GRINDER_RUNNING
        _phaseAt = now
        If Is3DLoaded()
            PlayGamebryoAnimation("Running", true, RUN_EASE_IN)
        EndIf
    ElseIf _power == GRINDER_RAMPDOWN && t >= RAMP_DOWN_SECS
        ; RampDown already rests at the Off pose
        _power = GRINDER_OFF
        _phaseAt = now
    EndIf
    If _power == GRINDER_OFF || !Is3DLoaded()
        Return
    EndIf
    Bool scanning = StorageUtil.GetIntValue(None, "FL_GrinderGrindAnyone", 0) != 0
    If scanning && IsLethalNow()
        ScanContact()
    EndIf
    Float nextIn = 2.0
    If scanning
        nextIn = CONTACT_POLL
    ElseIf _power == GRINDER_RAMPUP
        nextIn = (RAMP_UP_SECS + 0.25) - (Utility.GetCurrentRealTime() - _phaseAt)
    ElseIf _power == GRINDER_RAMPDOWN
        nextIn = RAMP_DOWN_SECS - (Utility.GetCurrentRealTime() - _phaseAt)
    EndIf
    If nextIn < 0.05
        nextIn = 0.05
    EndIf
    RegisterForSingleUpdate(nextIn)
EndEvent

; ---- power --------------------------------------------------------------

Function StartRampUp(Float afNow)
    _power = GRINDER_RAMPUP
    _phaseAt = afNow
    If Is3DLoaded()
        PlayGamebryoAnimation("RampUp", true, 0.0)
        PlaySwitchClank()
    EndIf
    Debug.Trace("[FleshCore] grinder " + Self + ": spinning up")
EndFunction

Function StartRampDown(Float afNow)
    _power = GRINDER_RAMPDOWN
    _phaseAt = afNow
    If Is3DLoaded()
        PlayGamebryoAnimation("RampDown", true, STOP_EASE_IN)
        PlaySwitchClank()
    EndIf
    Debug.Trace("[FleshCore] grinder " + Self + ": winding down")
EndFunction

Function PlaySwitchClank()
    Sound clank = Game.GetFormFromFile(0x055780, "Skyrim.esm") as Sound   ; TRPPressurePlateStone
    If clank != None
        clank.Play(Self)
    EndIf
EndFunction

Function ApplyPowerPose()
    If !Is3DLoaded()
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Float t = now - _phaseAt
    If t < 0.0
        t = 999.0
    EndIf
    If _power == GRINDER_RAMPUP && t < 0.5
        PlayGamebryoAnimation("RampUp", true, 0.0)
        _phaseAt = now
    ElseIf _power == GRINDER_RAMPUP || _power == GRINDER_RUNNING
        _power = GRINDER_RUNNING
        _phaseAt = now
        PlayGamebryoAnimation("Running", true, 0.0)
    Else
        _power = GRINDER_OFF
        PlayGamebryoAnimation("Off", true, 0.0)
    EndIf
EndFunction

; ---- bystanders (only with the MCM's "Rollers grind bystanders" on) -------

Function ScanContact()
    Actor pl = Game.GetPlayer()
    Actor[] near = MiscUtil.ScanCellNPCs(Self, SCAN_RADIUS, None, true)
    Int i = 0
    While i < near.Length
        Actor a = near[i]
        If a != None && a != pl && CanGrindBystander(a) && IsInContactZone(a)
            GrindContact(a)
        EndIf
        i += 1
    EndWhile
EndFunction

; Someone who walks into the rollers by accident: not the player's followers,
; not anyone the game protects, never a child (FleshCore's own rule), and not
; someone on another mod's chain (cutting it is that mod's business). These only
; spare passers-by: the Grinder Hook, which the player aims, takes anyone but a
; child.
Bool Function CanGrindBystander(Actor a)
    If a.IsDead() || a.IsDisabled() || a.IsPlayerTeammate() || IsChildLike(a)
        Return false
    EndIf
    If StorageUtil.GetIntValue(a, "FL_GrindHookBusy", 0) != 0 || StorageUtil.GetIntValue(a, "FL_GrinderClaimed", 0) != 0
        Return false
    EndIf
    ActorBase ab = a.GetLeveledActorBase()
    If a.IsEssential() || (ab != None && (ab.IsEssential() || ab.IsProtected()))
        Return false
    EndIf
    If FL_GrinderSpells.ChainReady()
        If FL_LeashBridge.IsHeld(a)
            Return false
        EndIf
    EndIf
    Return true
EndFunction

Function GrindContact(Actor akVictim)
    StorageUtil.SetIntValue(akVictim, "FL_GrinderClaimed", 1)
    If FL_GrinderSpells.ChainReady()
        FL_LeashBridge.CutAll(akVictim)
    EndIf
    GrindAndKill(akVictim, "FL_Grinder")
    PlayGrindCrunch(akVictim, Crunch)
    GoreBurst(akVictim, Self, XMarkerBase)
    Debug.Trace("[FleshCore] grinder " + Self + ": " + akVictim + " touched the rollers")
EndFunction

; ---- shared with FL_GrindHook ---------------------------------------------

; FleshCore never wounds a child: the same four tests as FL_Wound.WhyRefused
; (IsChild, the race's child flag, "Child" in the race's editor id, a child voice).
Bool Function IsChildLike(Actor a) Global
    If a == None
        Return false
    EndIf
    If a.IsChild()
        Return true
    EndIf
    Race r = a.GetRace()
    If r != None
        If r.IsChildRace() || StringUtil.Find(PO3_SKSEFunctions.GetFormEditorID(r), "Child") >= 0
            Return true
        EndIf
    EndIf
    ActorBase ab = a.GetLeveledActorBase()
    If ab == None
        ab = a.GetActorBase()
    EndIf
    If ab != None
        VoiceType voice = ab.GetVoiceType()
        If voice != None
            Int vid = voice.GetFormID()
            Return vid == 0x00013AE8 || vid == 0x00013AE9
        EndIf
    EndIf
    Return false
EndFunction

; FleshCore's grind and its burst on one tick, with no deferred kill: the grind
; wound and the detonation are queued to the engine now. Not the Grind Down
; spell, which holds its target alive until its rows finish. Kick 0 is
; FleshCore's own throw force. Wound reports are whatever FleshCore's watcher
; sends for any wound; nothing here adds or holds back a report.
Function GrindBodyFast(Actor akVictim, String asCaller) Global
    If akVictim == None
        Return
    EndIf
    FL_Wound.ClearProtection(akVictim)
    If FL_Api.IsInstalled() && FL_Wound.CoreActive() && FL_Wound.Targetable(akVictim)
        FL_Api.SystemWoundEx(asCaller, akVictim, FL_Api.Columns("grind", 14.0, 3, "-", "centre", false, 1, 48, 18, 0, false, 4, 1))
        FL_Api.SystemDetonate(asCaller, akVictim, 1, 0)
    EndIf
EndFunction

; The kill past a defeat framework: Acheron turns a death into defeat, so its
; own switch is held off for this one call (as FL_Grind does).
Function KillPastAcheron(Actor akVictim) Global
    If akVictim == None || akVictim.IsDead()
        Return
    EndIf
    Bool hasAcheron = Game.IsPluginInstalled("Acheron.esm")
    If hasAcheron
        Acheron.DisableProcessing(true)
    EndIf
    akVictim.Kill()
    If hasAcheron
        Acheron.DisableProcessing(false)
    EndIf
EndFunction

; The burst and the death on one tick. The crime faction is held off for the
; grind (FL_Grind found that grinding placed a bounty without this) and given
; back if they live through it. A survivor (FleshCore's no-kill list, or an actor
; the engine will not let die) loses the FL_GrinderClaimed mark, so the rollers
; can take them later.
Function GrindAndKill(Actor akVictim, String asCaller) Global
    If akVictim == None
        Return
    EndIf
    Faction crimeWas = akVictim.GetCrimeFaction()
    If crimeWas != None
        akVictim.SetCrimeFaction(None)
    EndIf
    GrindBodyFast(akVictim, asCaller)
    KillPastAcheron(akVictim)
    If !akVictim.IsDead()
        If crimeWas != None
            akVictim.SetCrimeFaction(crimeWas)
        EndIf
        StorageUtil.UnsetIntValue(akVictim, "FL_GrinderClaimed")
        Debug.Trace("[FleshCore] grinder: " + akVictim + " lived through the rollers (no-kill or essential)")
    EndIf
EndFunction

Function PlayGrindCrunch(Actor akVictim, Sound akCrunch) Global
    If akVictim != None && akCrunch != None
        akCrunch.Play(akVictim)
    EndIf
EndFunction

; The player's Blood Splatter switch and slider (HQ and MCM) govern this blood
; too, read the way FleshCore's own burst reads them: off, or 0, lays none; below
; 100 the coat, the splat under the grinder and the number of rays shrink with it.
Function GoreBurst(Actor akVictim, ObjectReference akGrinder, Static akMarkerBase) Global
    If akVictim == None
        Return
    EndIf
    Int pct = 0
    If FL_Native.GetBloodSplatter()
        pct = FL_Native.GetBloodSplatterPct()
    EndIf
    If pct <= 0
        Return
    EndIf
    If pct > 100
        pct = 100
    EndIf
    Float scale = (pct as Float) / 100.0
    Int coatBand = (5.0 * scale + 0.999) as Int
    If coatBand < 1
        coatBand = 1
    ElseIf coatBand > 5
        coatBand = 5
    EndIf
    Int rays = (12.0 * scale + 0.999) as Int
    If rays < 1
        rays = 1
    ElseIf rays > 12
        rays = 12
    EndIf
    Int bloodKind = DC_Api.BLOOD()
    DC_Api.CoatSkin(akVictim, bloodKind, coatBand)
    If akGrinder != None
        Int splatSize = DC_Api.LARGE()
        If pct < 34
            splatSize = DC_Api.SMALL()
        ElseIf pct < 67
            splatSize = DC_Api.MEDIUM()
        EndIf
        DC_Api.Splat(akGrinder, bloodKind, splatSize)
    EndIf
    DC_Core core = DC_Api.Core()
    If core == None || akMarkerBase == None
        Return
    EndIf
    ObjectReference org = akVictim.PlaceAtMe(akMarkerBase, 1, true, false)
    If org == None
        Return
    EndIf
    org.MoveTo(akVictim, 0.0, 0.0, 48.0, false)
    If !org.Is3DLoaded()
        Utility.Wait(0.05)
    EndIf
    Float step = 360.0 / (rays as Float)
    Int i = 0
    While i < rays
        ImpactDataSet ids = core.SetFor(bloodKind, Utility.RandomInt(0, 2))
        If ids != None
            Float ang = step * (i as Float) + Utility.RandomFloat(-10.0, 10.0)
            Float rOut = Utility.RandomFloat(28.0, 80.0)
            Float lenJ = Math.Sqrt(rOut * rOut + 48.0 * 48.0)
            org.PlayImpactEffect(ids, "", (rOut * Math.Cos(ang)) / lenJ, (rOut * Math.Sin(ang)) / lenJ, -48.0 / lenJ, lenJ + 20.0, false, false)
        EndIf
        i += 1
    EndWhile
    org.DisableNoWait()
    org.Delete()
EndFunction
