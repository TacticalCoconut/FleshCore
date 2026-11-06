Scriptname FL_ShredderRune extends ObjectReference
{THE SHREDDER RUNE -- the trap, once it is armed.

 Design note: the spell places a Conjured Trap Rune on the ground, which, when
 stepped on by a voxelisable target, Detonates them.

 The same shape as FL_ShredderSphere and for the same reason: an invisible
 scripted Activator (MarkerX.nif) that outlives the cast, because a magic
 effect cannot wait on the floor for somebody to walk over it.

 WHY IT POLLS RATHER THAN WAITING FOR OnTriggerEnter. A trigger volume is a
 property of a PLACED record authored in the Creation Kit; an Activator spawned
 at runtime with PlaceAtMe has none, so OnTriggerEnter never fires for it. One
 FindClosestActorFromRef a quarter-second is what is actually available.

 IT IS VISIBLE BECAUSE DECALCORE MAKES IT VISIBLE, AND THE RING IS DRAWN LATE
 ON PURPOSE. MarkerX.nif draws nothing, and an invisible trap is not a trap you
 can place deliberately. So on arming it lays a ring of DecalCore marks on the
 floor, by the road the burst script's burst uses. Two things about that road are
 easy to get wrong and were got wrong first time:

   -- A RAY NEEDS A 3D TO START FROM, and PlaceAtMe attaches 3D
      asynchronously (FL_Chunk says so twice, the burst script waits on
      Is3DLoaded for exactly this). Drawing from OnInit fires every ray before
      the reference exists to fire them, and all eight miss.
   -- AND IT NEEDS TO BE DRAWN WHERE THE RUNE ENDED UP. OnInit runs where
      PlaceAtMe put it -- at the caster's feet -- while the cast script's MoveTo
      happens afterwards. A ring drawn in OnInit marks the caster, not the trap.

 So the ring is drawn on the FIRST POLL instead, by which time the reference has
 its 3D and has been moved. If DecalCore does not answer, the rune still arms
 and still fires; it is simply unmarked, and says so.}

Spell Property Detonate = None Auto
{FL_Detonate_Spell. Set on the record.}

Static Property XMarker = None Auto
{Skyrim.esm 0x3B. The ring is fired from one of these, lifted off the floor --
 see Draw. Set on the record, as FL_Detonate_Mark sets its own.}

Float Property TriggerRadius = 96.0 Auto
{How close a body has to come. 96 is about a metre and a third -- a stride.}

Float Property Tick = 0.25 Auto
{Seconds between polls.}

Float Property MaxLife = 300.0 Auto
{A rune nobody ever steps on still has to stop polling eventually.}

Int Property Kind = 0 Auto
{What the ring is made of, in DecalCore's numbering: 0 blood, 1 alt.}

Float Property Ring = 40.0 Auto
{Radius of the mark ring on the floor.}

Float Property Lift = 24.0 Auto
{How high above the floor the ring is fired FROM. A fan of rays whose apex sits
 ON the floor is a fan lying flat in it -- every ray lands at zero distance and
 the whole ring collapses into one blob at the origin. the burst script lifts its
 own apex 48 for the same reason; this ring is smaller, so this is smaller.}

Float born
Bool  running
Bool  drawn

Event OnInit()
    born = Now()
    running = true
    drawn = false
    ; See FL_ShredderSphere.OnInit: MarkerX.nif is a visible red X on a custom
    ; Activator, and this one stands for up to five minutes. The ring of marks
    ; is what shows where the rune is; the marker itself should show nothing.
    SetScale(0.01)
    RegisterForSingleUpdate(Tick)
EndEvent

Event OnUnload()
    If running && Since(born) > 5.0
        Vanish()
    EndIf
EndEvent

Event OnUpdate()
    If !running
        Return
    EndIf
    If Since(born) >= MaxLife
        Vanish()
        Return
    EndIf
    ; The engine gate is asked HERE and not in Valid: whether FleshCore is armed
    ; decides whether the detonation can do anything, never whether the trap is
    ; allowed to notice somebody standing on it.
    If !FL_Wound.CoreActive()
        RegisterForSingleUpdate(Tick)
        Return
    EndIf
    ; The ring, once, on the first poll: the 3D is attached by now and the cast
    ; script's MoveTo has landed.
    If !drawn
        drawn = true
        Draw()
    EndIf
    Actor a = Pick()
    If a
        If !Detonate
            Debug.Trace("[FleshCore] shredder rune: Detonate not set on the record -- " + a + " stepped on it and nothing was cast")
            RegisterForSingleUpdate(Tick)
            Return
        EndIf
        Detonate.Cast(a, a)
        Debug.Trace("[FleshCore] shredder rune: " + a + " stepped on it")
        Vanish()
        Return
    EndIf
    RegisterForSingleUpdate(Tick)
EndEvent

Actor Function Pick()
    {Whoever stepped on it.

     ANYONE, NOT JUST A BODY FLESHCORE CAN CUT (design note: the rune
     triggers when ANYONE walks into it). A rune that let a chicken,
     a summon or a follower walk over it untouched is a rune you cannot trust
     to be armed, and the old gate made that worse than it sounds: the
     gate was also what chose the victim, so a single non-target parked on top
     of it starved the rune for its whole life while a bandit stood in the
     middle of it. Now the trap fires for the first living thing that reaches
     it, and what the detonation does to that thing is the DLL's business --
     a body it cannot voxelise simply takes no wound.}
    Actor a = Game.FindClosestActorFromRef(Self, TriggerRadius)
    If Valid(a)
        Return a
    EndIf
    a = Game.FindRandomActorFromRef(Self, TriggerRadius)
    If Valid(a)
        Return a
    EndIf
    a = Game.FindRandomActorFromRef(Self, TriggerRadius)
    If Valid(a)
        Return a
    EndIf
    Return None
EndFunction

Bool Function Valid(Actor a)
    {Alive and here. Deliberately NOT FL_Wound.Targetable -- see Pick.}
    Return a && !a.IsDead() && !a.IsDisabled()
EndFunction

Function Draw()
    {Mark the floor so the rune can be seen and walked into on purpose.

     Eight rays out and DOWN from an apex Lift above the rune, onto the circle
     of radius Ring -- the burst script's Burst with one ring and a short reach.
     The apex is a throwaway XMarker because PlayImpactEffect casts from the
     reference it is called on, and a ray fired from the rune itself would start
     in the floor plane.

     The aim, in full, exactly as Burst computes it: the vector from the apex to
     a point Ring out on the floor is (Ring*cos, Ring*sin, -Lift), whose length
     is len = sqrt(Ring*Ring + Lift*Lift). PlayImpactEffect takes a DIRECTION
     and a LENGTH separately, so the whole vector -- Z INCLUDED -- is divided by
     len, and the length passed is len plus the same 16-unit overshoot every ray
     in the burst script carries so an uneven floor is still met.}
    If !XMarker
        Debug.Trace("[FleshCore] shredder rune: XMarker not set on the record -- armed unmarked")
        Return
    EndIf
    DC_Core c = DC_Api.Core()
    If c == None
        Debug.Trace("[FleshCore] shredder rune: DecalCore did not answer -- armed unmarked")
        Return
    EndIf
    Int k = DC_Api.BLOOD()
    If Kind == DC_Api.ALT()
        k = DC_Api.ALT()
    EndIf
    ImpactDataSet s = c.SetFor(k, DC_Api.MEDIUM())
    If s == None
        Debug.Trace("[FleshCore] shredder rune: DecalCore had no atlas -- armed unmarked")
        Return
    EndIf
    Float len = Math.sqrt(Ring * Ring + Lift * Lift)
    If len < 1.0
        Return
    EndIf
    ObjectReference org = PlaceAtMe(XMarker, 1, true, false)
    If !org
        Debug.Trace("[FleshCore] shredder rune: could not place the ring origin -- armed unmarked")
        Return
    EndIf
    org.MoveTo(Self, 0.0, 0.0, Lift, false)
    If !org.Is3DLoaded()
        Utility.Wait(0.05)
    EndIf
    Float dz = -Lift / len
    Float dist = len + 16.0
    Int n = 0
    Int i = 0
    While i < 8
        Float ang = 45.0 * i
        If org.PlayImpactEffect(s, "", (Ring * Math.Cos(ang)) / len, \
                                (Ring * Math.Sin(ang)) / len, dz, dist, false, false)
            n += 1
        EndIf
        i += 1
    EndWhile
    org.DisableNoWait()
    org.Delete()
    Debug.Trace("[FleshCore] shredder rune: armed, " + n + " of 8 mark(s) on the floor")
EndFunction

Float Function Now()
    Return Utility.GetCurrentRealTime()
EndFunction

Float Function Since(Float stamp)
    {See FL_ShredderSphere.Since -- GetCurrentRealTime restarts with the
     application and these stamps are co-saved, so a stamp in the future is
     read as expired rather than as a deadline that can never arrive.}
    Float now = Now()
    If now < stamp
        Return 999999.0
    EndIf
    Return now - stamp
EndFunction

Function Vanish()
    running = false
    UnregisterForUpdate()
    DisableNoWait()
    Delete()
EndFunction
