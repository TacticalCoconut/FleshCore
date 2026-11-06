Scriptname FL_ShredderSphere extends ObjectReference
{THE SHREDDER SPHERE -- the field itself, once it is standing.

 Design note: a persistent, localised sphere made of two
 shells, an outer radius and an inner radius. On contact with a
 voxelisable target, the outer shell pulls them in towards the centre of the
 inner one, and on contact with the inner shell, the target is
 aggressively voxelised. Five seconds after eliminating one target, the sphere
 disappears.

 WHAT THIS IS. An invisible scripted Activator -- MarkerX.nif, exactly as
 FL_Detonate_Mark and FL_Splatter_Mark already are -- placed by
 FL_ShredderSphereCast and left polling on its own. NOT a magic effect: an
 effect ends with its duration and takes its script with it, and this has to
 outlive the cast that made it.

 IT TAKES EVERYONE IN REACH, AND THE FIRST KILL ONLY STARTS THE CLOCK.
 The five seconds after the first kill do not mean it only ever takes
 one victim: the sphere is meant to pull and kill every playable-race
 character within range, not a single target.
 So every valid body inside the outer shell is
 hauled on every tick, every one that reaches the inner shell is taken apart,
 and the five seconds are a FUSE lit by the first kill -- not a stop. The field
 keeps working while it burns, and everything it can still reach in those five
 seconds goes with it.

 WHICH MEANS IT HAS TO SEE EVERYONE, and FindClosestActorFromRef answers with
 exactly one. powerofthree's Papyrus Extender is a dependency, and its
 FindAllReferencesOfFormType returns every reference of a form type inside a
 radius; 62 is kCharacter, which the scene framework's own source states in three separate
 places (the scene framework, the framework script, the framework script). That is the enumeration
 this needs, in one native call a tick.

 THE HAUL IS BETHESDA'S OWN, AND IT IS RE-APPLIED. An actor on their feet shrugs
 off an impulse; a ragdoll slides. DLC2CycloneEffectScript -- the Cyclone shout
 -- puts its targets down with Target.PushActorAway(Target, Force) for that
 reason. They get up again in a few seconds, though, and a knockdown applied
 ONCE would leave the rest of the haul pushing a standing body that ignores it,
 for as long as the field lived. So it is re-applied on a timer.

 THE KILL IS THE ONE FLESHCORE ALREADY HAS. Detonate is cast on them from
 themselves -- the self-delivery idiom the retired quest uses for DecapitateSelf and
 FL_Grind uses for its Tick -- so the wound, the pieces, the marks and the
 death all run down roads that are already proven, and the spell needs
 nothing of its own in the DLL or the W table.}

Spell Property Detonate = None Auto
{FL_Detonate_Spell. Set on the record.}

Float Property OuterRadius = 512.0 Auto
{Where the pull begins, in game units. 512 is about seven metres.}

Float Property InnerRadius = 128.0 Auto
{Where they are taken apart. 128 is about two metres.}

Float Property Pull = 40.0 Auto
{Impulse magnitude per tick toward the middle. DELIBERATELY SMALL. Impulses
 add momentum, they do not set speed, so this is applied four times a second
 and compounds; the largest figure anywhere in Bethesda's own scripts is 50
 (MaceTrap), and 900 -- which this shipped as before it was measured -- threw a
 ragdoll clean across the inner shell between two polls, so the arrival was
 never sampled and the field sat inert with nothing left to catch.}

Float Property Knock = 5.0 Auto
{The knockdown that makes the haul possible. Source and target are the same
 actor, which is Cyclone's own shape, so there is no direction to be thrown in
 -- they go down where they stand. Not zero: Cyclone guards on force > 0, and
 a push of no force in no direction is nothing at all.}

Float Property ReKnock = 1.0 Auto
{Seconds between knockdowns. ONE timer for the whole field, not one per body:
 when it comes round, everybody being hauled goes down together.

 A SECOND, NOT TWO AND A HALF (in testing, dragged targets kept trying to
 get up while being dragged). A body recovers from a knockdown far faster than
 the two and a half seconds this used to wait, and every second it is upright
 is a second the impulses do nothing at all, because a standing actor ignores
 them. Short enough to keep them down, still one shared timer rather than the
 every-tick storm that made a crowd un-haulable.}

Int Property MaxBodies = 16 Auto
{How many references the field will act on in one tick. A ceiling on the work,
 not on the spell -- a brawl with more bodies than this in one shell is not
 what the Papyrus VM should be asked to move four times a second.}

Static Property XMarker = None Auto
{Skyrim.esm 0x3B. The apex the two range rings are fired from. Set on the record.}

Float Property Lift = 24.0 Auto
{Base height of the ring apex. Each ring raises it further -- see Draw.}

Bool Property ShowRings = true Auto
{Draw the two range rings on arming. Field report: there was no visual
 indicator of the ranges.}

Float Property Tick = 0.25 Auto
{Seconds between polls.}

Float Property AfterKill = 5.0 Auto
{Five seconds: how long the field stands after eliminating one.}

Float Property MaxLife = 120.0 Auto
{A field nobody ever walks into still has to stop, persistent or not:
 a poller that outlives the fight, and then a
 save, is a cost with nobody left to pay it.}

Float born
Float killedAt
Float knockedAt
Bool  eaten
Bool  running
Bool  drawn

Event OnInit()
    born = Now()
    eaten = false
    running = true
    drawn = false
    ; THE RED X IS THE MODEL, AND IT IS MEANT TO BE SEEN BY NOBODY.
    ;
    ; Field report: the red X marker showed up at the centre. MarkerX.nif
    ; is what FL_Detonate_Mark and FL_Splatter_Mark use, and they get away with
    ; it because they live for a frame or two; this field stands for up to two
    ; minutes, so its marker is on screen the whole time. The engine hides the
    ; vanilla editor markers by their base record, not by the mesh, so a custom
    ; Activator wearing the same mesh draws it. Scaled to a hundredth it is
    ; smaller than a pixel at any distance the spell is used from, and scale
    ; changes nothing about position, distance or the rays fired from it.
    SetScale(0.01)
    RegisterForSingleUpdate(Tick)
EndEvent

Event OnUnload()
    ; A field the player has walked out of the cell on is spent. Without this
    ; it keeps its update registration forever on an unloaded reference, where
    ; it can find nobody and can never expire either.
    If running && Since(born) > 5.0
        Vanish()
    EndIf
EndEvent

Event OnUpdate()
    If !running
        Return
    EndIf
    ; ---- 1. THE TWO DEADLINES, BOTH REACHABLE --------------------------
    ; The MaxLife test is NOT behind the eaten branch. It was, and an eaten
    ; field whose five seconds could not elapse (see Since) had no second way
    ; out at all.
    If eaten && Since(killedAt) >= AfterKill
        Vanish()
        Return
    EndIf
    If Since(born) >= MaxLife
        Vanish()
        Return
    EndIf
    ; The rings, once, on the first poll -- by then the reference has its 3D and
    ; the cast script's MoveTo has landed. Same reasoning as FL_ShredderRune.Draw.
    If !drawn
        drawn = true
        If ShowRings
            Draw()
        EndIf
    EndIf
    ; NOTE there is no early return for `eaten`. The five seconds are a fuse,
    ; not a stop: the field goes on hauling and killing while it burns.
    ; ---- 2. EVERY BODY IN THE SHELL, THIS TICK -------------------------
    ObjectReference[] refs = PO3_SKSEFunctions.FindAllReferencesOfFormType(Self, 62, OuterRadius)
    If refs
        ; One knockdown for the whole field when the timer comes round, so a
        ; crowd goes down together instead of each body keeping its own clock.
        Bool knockNow = knockedAt == 0.0 || Since(knockedAt) >= ReKnock
        Bool knocked = false
        Int n = refs.Length
        If n > MaxBodies
            n = MaxBodies
        EndIf
        Int i = 0
        While i < n
            Actor a = refs[i] as Actor
            If Valid(a)
                Float d = Self.GetDistance(a)
                If d <= InnerRadius
                    Eat(a)
                Else
                    Haul(a, d, knockNow)
                    knocked = knocked || knockNow
                EndIf
            EndIf
            i += 1
        EndWhile
        If knocked
            knockedAt = Now()
        EndIf
    EndIf
    RegisterForSingleUpdate(Tick)
EndEvent

Bool Function Valid(Actor a)
    {Alive, and one the engine will actually cut. FL_Wound's own gate, so this
     and every other FleshCore cast cannot disagree about who qualifies.
     CoreActive is a file test, so it is asked only when there is a body to ask
     it about -- not four times a second for the life of the field.}
    If !a || a.IsDead() || a.IsDisabled()
        Return false
    EndIf
    Return FL_Wound.CoreActive() && FL_Wound.Targetable(a)
EndFunction

Function Eat(Actor a)
    {They reached the middle.}
    If !Detonate
        ; Logged: a field that consumed its one kill against a
        ; record with no spell on it would vanish looking like it had worked.
        Debug.Trace("[FleshCore] shredder sphere: Detonate not set on the record -- " + a + " reached the middle and nothing was cast")
        Return
    EndIf
    Detonate.Cast(a, a)
    Debug.Trace("[FleshCore] shredder sphere: " + a + " reached the middle")
    ; THE FUSE IS LIT ONCE, BY THE FIRST. A later kill must not push the
    ; deadline out again, or a field in a crowd would never close.
    If !eaten
        eaten = true
        killedAt = Now()
    EndIf
EndFunction

Function Haul(Actor a, Float d, Bool abKnock)
    {Pull one body toward the middle. d is their distance, measured by the caller;
     abKnock is the field's shared decision for this tick, so a crowd is put
     down together and the timer is stamped once by the caller afterwards.}
    If d < 1.0
        Return
    EndIf
    If abKnock
        a.PushActorAway(a, Knock)
    EndIf
    ; A unit vector from them to the middle, times the magnitude. X/Y/Z are this
    ; reference's own world position -- the three Game.FindClosestActorFromRef
    ; reads off arCenter.
    a.ApplyHavokImpulse((X - a.X) / d, (Y - a.Y) / d, (Z - a.Z) / d, Pull)
EndFunction

Function Draw()
    {Two rings on the floor: where the pull begins and where it kills.

     Fired from a throwaway XMarker apex, exactly as FL_ShredderRune.Draw and
     the burst script's burst are. The apex has to be RAISED FURTHER FOR THE WIDER
     RING: a ray from 24 units up aimed at a point 512 units away is travelling
     almost flat and meets the first wall or chair in its path instead of the
     floor. Each ring therefore gets an apex about half its own radius, which
     keeps every ray steep enough to land where it is aimed.}
    If !XMarker
        Return
    EndIf
    DC_Core c = DC_Api.Core()
    If c == None
        Debug.Trace("[FleshCore] shredder sphere: DecalCore did not answer -- no range rings")
        Return
    EndIf
    ImpactDataSet s = c.SetFor(DC_Api.BLOOD(), DC_Api.MEDIUM())
    If s == None
        Debug.Trace("[FleshCore] shredder sphere: DecalCore had no atlas -- no range rings")
        Return
    EndIf
    ObjectReference org = PlaceAtMe(XMarker, 1, true, false)
    If !org
        Return
    EndIf
    Int inner = Ring(s, org, InnerRadius, Lift + InnerRadius * 0.5, 12)
    Int outer = Ring(s, org, OuterRadius, Lift + OuterRadius * 0.5, 16)
    org.DisableNoWait()
    org.Delete()
    Debug.Trace("[FleshCore] shredder sphere: range rings drawn, " + inner + " inner and " + outer + " outer mark(s)")
EndFunction

Int Function Ring(ImpactDataSet s, ObjectReference org, Float r, Float h, Int rays)
    {One ring of radius r, fired from an apex h above this reference. The whole
     aim vector -- Z included -- is divided by its own length, because
     PlayImpactEffect takes a direction and a distance separately; the 16 is the
     same overshoot every ray in the burst script carries.}
    Float len = Math.sqrt(r * r + h * h)
    If len < 1.0 || rays < 1
        Return 0
    EndIf
    org.MoveTo(Self, 0.0, 0.0, h, false)
    If !org.Is3DLoaded()
        Utility.Wait(0.05)
    EndIf
    Float dz = -h / len
    Float dist = len + 16.0
    Float step = 360.0 / rays
    Int n = 0
    Int i = 0
    While i < rays
        Float ang = step * i
        If org.PlayImpactEffect(s, "", (r * Math.Cos(ang)) / len, \
                                (r * Math.Sin(ang)) / len, dz, dist, false, false)
            n += 1
        EndIf
        i += 1
    EndWhile
    Return n
EndFunction

Float Function Now()
    Return Utility.GetCurrentRealTime()
EndFunction

Float Function Since(Float stamp)
    {Seconds since a stamp, IN A CLOCK THAT RESTARTS.

     GetCurrentRealTime counts from when the APPLICATION started, and these
     stamps are co-saved. Quit, reload, and `now` begins again near zero while
     the stamp still reads four thousand: every plain `now - stamp` goes hugely
     negative and no deadline in this script can ever be met again -- an
     invisible object polling four times a second for the rest of the session
     with no way out. A stamp in the future is therefore read as expired, which
     is the same rule FL_KO_Hold keeps (`now - shoveAt > 1.0 || now < shoveAt`).}
    Float now = Now()
    If now < stamp
        Return 999999.0
    EndIf
    Return now - stamp
EndFunction

Function Vanish()
    {Stop, and leave nothing behind. DisableNoWait then Delete, the order
     FL_DecalMark and the burst script both end on. Nothing holds an Actor across
     ticks any more -- the shell is re-enumerated every time -- so there is no
     reference left here to pin a body in the co-save.}
    running = false
    UnregisterForUpdate()
    DisableNoWait()
    Delete()
EndFunction
