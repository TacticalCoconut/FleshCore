Scriptname FL_DetonateBurst extends ActiveMagicEffect
{THE BURST AROUND THEM -- the half of a Detonate that is not the wound.

 This script rides on the Detonate effect BESIDE FL_Wound, not instead of it.
 FL_Wound is what every wound carries -- it clears their protection and the
 DLL's wound rides on the same effect -- and it is left exactly as it is. The
 pieces of them are coated by a different road again: FL_Chunk gives every
 piece a blood coat as it comes away. So what is left for this script is the
 ROOM: the floor and the walls for metres around the place they were standing.

 HOW THE ROOM IS MARKED -- ONE OBJECT, ONE POSITION, FORTY-NINE RAYS.

 A surface mark is one native call: PlayImpactEffect casts a ray from a
 reference in a direction and the engine projects a decal where it lands.
 That is all DC_Api.SplatDir is and it is all this needs. So ONE XMarker is
 placed at them, lifted once to Height, and every mark in the room is a ray
 FANNED OUT from that single point at the floor around them. Then it is
 disabled and deleted.

 WHY THE ORIGIN DOES NOT WALK. A ray aimed DOWN AND OUT from one high point
 lands where a ray straight down from a point on the floor would have, so
 the origin never has to move round the ring, only the aim. Whether MoveTo is
 latent is undocumented (ObjectReference.psc says nothing); one MoveTo is left.

 THE SPACING. Rings 28, 55 and 83 units out, with neighbours 21, 28 and 32
 units apart -- a third of a large decal's width (60-96), so the marks pile
 rather than tile. Wider spacing left the floor visibly sparse in testing.
 The wall rays (Axis, Flat) keep their reach. The table and the arithmetic
 are on Burst below.

 THE ATLAS IS PICKED PER RING. SetFor picks a random member of the
 (kind, size) list on every call (see DC_Core.SetFor), so asking once per
 RING keeps the variety across the floor and costs five calls, not forty-nine.
 The engine draws a random quadrant of whichever it picks for each ray.

 THE WHOLE BURST GOES OUT IN ONE FRAME. iMaxDecalsPerFrame
 (SkyrimPrefs.ini) sets how many decals a frame may take; the burst is issued in
 the frame it starts in and nothing here yields to spread it out.

 WHY THE ORIGIN IS AN XMARKER AND NOT THEM. PlayImpactEffect casts from the
 reference it is called on, so called on THEM every ray would start inside their
 own collision -- the reason DC_Api.SplatToward exists.
 An XMarker (Skyrim.esm 0x3B, the engine's own invisible static) has none to
 start inside. It is placed persistent and deleted in the documented order,
 so its persistence costs nothing.

 WHAT IS NOT DONE. Nothing here paints them. What is left of them on the floor
 gets the shard coat -- an effect shader in their body's own UV, which attaches
 to 3D without rebuilding it -- and nothing else. Their pieces are the DLL's and
 FL_Watch's to coat, and they are.}

Static Property XMarker = None Auto
{Skyrim.esm 0x3B. The one reference the whole burst is fired from. Set on the
 record.}

Int Property Kind = 0 Auto
{WHAT THE BURST IS MADE OF, in DecalCore's numbering: 0 blood, or a kind
 another mod registered (DC_Api.RegisterKind). Set on the record; a kind that
 is not registered bursts in blood.}

Float Property Height = 48.0 Auto
{How high above their feet the origin sits, and the apex of the whole fan.
 The record's 48 is the value the fan is drawn for: every ray's aim and length
 is computed from it below. Well inside the rays' reach, so the floor is always
 met, and high enough that the four horizontal rays meet walls and furniture at
 knee height rather than skimming the floor.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    If !akTarget
        Return
    EndIf
    ; THE SAME GATE FL_WOUND KEEPS. A target the engine will not wound is
    ; not detonated, and a room sprayed around a target who did not come apart
    ; is not the spell either. Both checks are FL_Wound's own globals, so the
    ; two scripts on this effect cannot disagree about who qualifies.
    If !FL_Wound.CoreActive() || !FL_Wound.Targetable(akTarget)
        Return
    EndIf
    If XMarker == None
        Debug.Trace("[FleshCore] burst: XMarker not set on the record -- no burst")
        Return
    EndIf
    ; THE SERVICE IS HELD, NOT ASKED FOR AGAIN AND AGAIN. DC_Api's own header:
    ; "Callers on a hot path should hold the result of Core() once and call its
    ; methods directly" (DC_Api.psc). Two native calls a resolve, and
    ; this is the hottest path the mod has.
    DC_Core c = DC_Api.Core()
    If c == None
        Debug.Trace("[FleshCore] burst: DecalCore did not answer -- no burst")
        Return
    EndIf
    Int k = DC_Api.BLOOD()
    If c.HasKind(Kind)
        k = Kind
    EndIf
    ; WHAT IS LEFT OF THEM WEARS IT. CoatSkin is the shard coat -- an effect
    ; shader in their body's UV, played on the reference, no overlay and no 3D
    ; rebuild -- at the heaviest of DecalCore's six bands. Their pieces get the
    ; same coat from FL_Chunk as they come away.
    DC_Api.CoatSkin(akTarget, k, 5)
    ObjectReference org = akTarget.PlaceAtMe(XMarker, 1, true, false)
    If !org
        Debug.Trace("[FleshCore] burst: could not place the origin -- no burst")
        Return
    EndIf
    ; ---- THE ONE MOVE, AND WHY THERE IS STILL ONE -------------------------
    ;
    ; PlaceAtMe's own header is "Create x copies of the passed in form ... and
    ; place them at OUR LOCATION" (ObjectReference.psc). Their location
    ; is their ORIGIN, which for a standing actor is the floor between their feet
    ; -- DC_Api says so about the same fact ("a reference's
    ; ORIGIN is usually at its feet, so a splat from the origin of a standing
    ; target marks the floor", DC_Api.psc). The fan needs its apex ABOVE
    ; that floor, because every ray's aim is (out, out, -Height) and a Height of
    ; nothing is a fan of rays lying flat in the ground. So the marker is lifted
    ; exactly once, and it is the only call in the burst that moves anything.
    Float h = Height
    If h < 1.0
        ; The record sets 48. A record that ever set zero would collapse the
        ; whole fan into the floor plane, so it is floored rather than obeyed.
        h = 48.0
    EndIf
    org.MoveTo(akTarget, 0.0, 0.0, h, false)
    ; A RAY NEEDS A 3D TO START FROM. There is no MoveTo between the placement
    ; and the rays, so the one thing that could make all forty-nine miss at
    ; once -- a marker with no 3D yet -- is waited for, one beat at most.
    If !org.Is3DLoaded()
        Utility.Wait(0.05)
    EndIf
    Int landed = 0
    Int rays = 0
    Int nring = 0
    ; ---- THE RING TABLE ----------------------------------------------------
    ;
    ; radius 28 x 8, 55 x 12, 83 x 16 -- about 28 apart, alternate rings
    ; turned half a step so the outer marks sit between the inner ones rather
    ; than on the same spokes. Neighbour spacing on a ring is
    ; 2 * r * sin(180/n):
    ;
    ;     28  x  8  ->  2 * 28  * sin 22.5   =  21.4 units
    ;     55  x 12  ->  2 * 55  * sin 15     =  28.5 units
    ;     83  x 16  ->  2 * 83  * sin 11.25  =  32.4 units
    ;
    ; all of them a third of one large decal's 60-96 units, and the 28
    ; between rings likewise, so the marks pile rather than tile.
    Int got = Axis(c, org, h, k)
    If got >= 0
        landed += got
        rays += 5
    EndIf
    got = Burst(c, org, 28.0, 8, 0.0, h, k)
    If got >= 0
        landed += got
        rays += 8
        nring += 1
    EndIf
    got = Burst(c, org, 55.0, 12, 15.0, h, k)
    If got >= 0
        landed += got
        rays += 12
        nring += 1
    EndIf
    got = Burst(c, org, 83.0, 16, 11.25, h, k)
    If got >= 0
        landed += got
        rays += 16
        nring += 1
    EndIf
    ; AND THE ROOM: every ring ray above aims DOWN, so nothing but the four
    ; axis rays could reach a wall. Eight flat rays, 200 units, from their
    ; height, for the walls and whatever stands between the target and the walls.
    got = Flat(c, org, 8, 22.5, k)
    If got >= 0
        landed += got
        rays += 8
    EndIf
    If nring == 0 && rays == 0
        Debug.Trace("[FleshCore] burst (kind " + k + "): DecalCore had no atlas -- nothing fired")
    EndIf
    ; DISABLE WITHOUT WAITING, THEN DELETE -- the order FL_DecalMark ends its
    ; own sweep in (FL_DecalMark.psc). The vanilla header's own words
    ; are all that is claimed for it: DisableNoWait "Disables this object -
    ; fading out if requested. Does NOT wait for the fade or disable to finish"
    ; (ObjectReference.psc), against plain Disable's "Disables this
    ; object - fading out if requested", which says nothing about
    ; waiting either way.
    org.DisableNoWait()
    org.Delete()
    Debug.Trace("[FleshCore] burst (kind " + k + "): " + landed + " mark(s) from " + rays \
                + " ray(s) in " + nring + " ring(s) around " + akTarget)
EndEvent

Int Function Axis(DC_Core c, ObjectReference org, Float afHeight, Int aiKind)
    {The floor directly under them and the four horizontal rays, from the one
     origin. Returns how many of the five laid a mark, or -1 if there was no
     atlas to fire at all -- which is not the same as five misses, and the
     trace has to be able to tell them apart.

     THE DOWN RAY IS THE HEIGHT AND NOT 96. It has exactly afHeight of floor
     to cross; the 16 is the same overshoot every ray in this script carries,
     so a floor slightly below their feet is still met.

     THE FOUR HORIZONTAL RAYS ARE KEPT AT 96 -- FL_DecalMark's Reach default
     (FL_DecalMark.psc). They are the only rays in the burst that can reach a
     WALL or the side of a table; every other ray is aimed at the floor by
     construction. Fired from Height above their feet, they meet furniture at
     knee height.

     THERE IS NO UP RAY. From 48 units up, 96 units of reach ends at 144 --
     about two metres, and lower than the ceiling of very nearly every room in
     the game -- so it would meet nothing, and where it did it would mark a
     ceiling nobody is looking at.}
    ImpactDataSet s = c.SetFor(aiKind, DC_Api.LARGE())
    If s == None
        Return -1
    EndIf
    Int n = 0
    If org.PlayImpactEffect(s, "", 0.0, 0.0, -1.0, afHeight + 16.0, false, false)
        n += 1
    EndIf
    If org.PlayImpactEffect(s, "", 1.0, 0.0, 0.0, 96.0, false, false)
        n += 1
    EndIf
    If org.PlayImpactEffect(s, "", -1.0, 0.0, 0.0, 96.0, false, false)
        n += 1
    EndIf
    If org.PlayImpactEffect(s, "", 0.0, 1.0, 0.0, 96.0, false, false)
        n += 1
    EndIf
    If org.PlayImpactEffect(s, "", 0.0, -1.0, 0.0, 96.0, false, false)
        n += 1
    EndIf
    Return n
EndFunction

Int Function Burst(DC_Core c, ObjectReference org, Float afRadius, Int aiRays, \
                   Float afTurn, Float afHeight, Int aiKind)
    {One ring of the fan: aiRays cast DOWN AND OUT from the held origin at the
     circle of radius afRadius on the floor around them, starting afTurn degrees
     round. Returns how many laid a mark, or -1 if there was no atlas.

     THE ARGUMENT SHAPE IS SplatDir's, REPRODUCED RATHER THAN CALLED.
     DC_Api.SplatDir ends in

         Return at.PlayImpactEffect(s, "", dx, dy, dz, dist, applyNodeRotation, false)

     (DC_Api.psc) -- node "" so the cast starts at the reference's own
     origin rather than a bone, WORLD-SPACE direction (applyNodeRotation
     false: "FALSE means dx/dy/dz are world-space, which is what every caller
     here wants", DC_Api.psc), and the native's own answer passed
     straight through, which is what makes the count mean anything
     (DC_Api.psc). The only thing not reproduced is the part that
     costs: SplatDir resolves the service quest and re-picks an atlas on EVERY
     call, and both of those are done once per RING here instead.

     ---- THE AIM, IN FULL -------------------------------------------------

     The origin sits afHeight above the floor they are standing on. The point
     this ray is for is on that floor, afRadius out, at angle ang. So the
     vector from the origin to that point is

         ( r*cos(ang), r*sin(ang), -afHeight )

     whose length is len = sqrt(r*r + afHeight*afHeight). PlayImpactEffect
     takes a DIRECTION and a LENGTH separately, so the vector is divided by
     len -- every caller in DC_Api normalises (see SplatToward)
     and this keeps the same convention -- and the length passed is len plus a
     16-unit overshoot, the same margin SplatToward uses so a ray that arrives
     a little short of an uneven floor still lands.

     With the record's Height of 48 that is, exactly:

         r=28   len = sqrt(784+2304)   = 55.57   dist = 71.57   dz = -0.864
         r=55   len = sqrt(3025+2304)  = 73.00   dist = 89.00   dz = -0.658
         r=83   len = sqrt(6889+2304)  = 95.88   dist = 111.88  dz = -0.501

     A ray that meets a wall or a chair on its way out lands there instead,
     which is wanted: the fan sprays what is in the room as well as the floor.

     Math.Cos and Math.Sin take DEGREES (Math.psc), which is why ang is
     in degrees and no conversion appears here.}
    ImpactDataSet s = c.SetFor(aiKind, DC_Api.LARGE())
    If s == None
        Return -1
    EndIf
    If aiRays < 1
        Return 0
    EndIf
    Float len = Math.sqrt(afRadius * afRadius + afHeight * afHeight)
    If len < 1.0
        Return 0
    EndIf
    ; Constant for the whole ring: only the horizontal part of the aim turns.
    Float dz = -afHeight / len
    Float dist = len + 16.0
    Float step = 360.0 / aiRays
    Int n = 0
    Int i = 0
    While i < aiRays
        Float ang = afTurn + step * i
        If org.PlayImpactEffect(s, "", (afRadius * Math.Cos(ang)) / len, \
                                (afRadius * Math.Sin(ang)) / len, \
                                dz, dist, false, false)
            n += 1
        EndIf
        i += 1
    EndWhile
    Return n
EndFunction

Int Function Flat(DC_Core c, ObjectReference org, Int aiRays, Float afTurn, Int aiKind)
    {One flat ring: aiRays cast level, out from the held origin at their height,
     200 units, for the walls. Returns how many laid a mark, or -1 for no atlas.}
    ImpactDataSet s = c.SetFor(aiKind, DC_Api.LARGE())
    If s == None
        Return -1
    EndIf
    If aiRays < 1
        Return 0
    EndIf
    Float step = 360.0 / aiRays
    Int n = 0
    Int i = 0
    While i < aiRays
        Float ang = afTurn + step * i
        If org.PlayImpactEffect(s, "", Math.Cos(ang), Math.Sin(ang), 0.0, 200.0, false, false)
            n += 1
        EndIf
        i += 1
    EndWhile
    Return n
EndFunction
