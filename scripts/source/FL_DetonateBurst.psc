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
    StorageUtil.SetFloatValue(akTarget, "FL_LastDetonateBurst", Utility.GetCurrentRealTime())
    Float scale = (pct as Float) / 100.0
    Int coatBand = (5.0 * scale + 0.999) as Int
    If coatBand < 1
        coatBand = 1
    ElseIf coatBand > 5
        coatBand = 5
    EndIf
    ; WHAT IS LEFT OF THEM WEARS IT. CoatSkin is the shard coat -- an effect
    ; shader in their body's UV, played on the reference, no overlay and no 3D
    ; rebuild -- scaled by the splatter slider.
    DC_Api.CoatSkin(akTarget, k, coatBand)
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
    Int nHoriz = (4.0 * scale + 0.999) as Int
    Int nR1 = (8.0 * scale + 0.999) as Int
    Int nR2 = (12.0 * scale + 0.999) as Int
    Int nR3 = (16.0 * scale + 0.999) as Int
    Int nFlat = (8.0 * scale + 0.999) as Int
    If nHoriz > 4
        nHoriz = 4
    EndIf
    ; Each ring's own count goes into the closing trace (-1: no atlas), so a
    ; test log shows which part of the fan found a surface.
    Int got = Axis(c, org, h, k, nHoriz)
    String per = "axis " + got
    If got >= 0
        landed += got
        rays += 1 + nHoriz
    EndIf
    got = Burst(c, org, 28.0, nR1, 0.0, h, k)
    per += ", rings " + got
    If got >= 0
        landed += got
        rays += nR1
        nring += 1
    EndIf
    got = Burst(c, org, 55.0, nR2, 15.0, h, k)
    per += "/" + got
    If got >= 0
        landed += got
        rays += nR2
        nring += 1
    EndIf
    got = Burst(c, org, 83.0, nR3, 11.25, h, k)
    per += "/" + got
    If got >= 0
        landed += got
        rays += nR3
        nring += 1
    EndIf
    ; AND THE ROOM: every ring ray above aims DOWN, so nothing but the four
    ; axis rays could reach a wall. Flat rays, 200 units, from their
    ; height, for the walls and whatever stands between the target and the walls.
    got = Flat(c, org, nFlat, 22.5, k)
    per += ", flat " + got
    If got >= 0
        landed += got
        rays += nFlat
    EndIf
    If nring == 0 && rays == 0
        Debug.Trace("[FleshCore] burst (kind " + k + "): DecalCore had no atlas -- nothing fired")
    EndIf
    ; How far above their origin the fan's apex really was (the record asks 48).
    Float apex = org.GetPositionZ() - akTarget.GetPositionZ()
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
                + " ray(s) in " + nring + " ring(s) around " + akTarget \
                + " (" + per + "; apex " + apex + " above them)")
EndEvent

Int Function Axis(DC_Core c, ObjectReference org, Float afHeight, Int aiKind, Int aiHorizMax = 4)
    {The floor directly under them and up to aiHorizMax horizontal rays, from the one
     origin.}
    ImpactDataSet s0 = c.SetFor(aiKind, Utility.RandomInt(1, 2))
    If s0 == None
        Return -1
    EndIf
    Int n = 0
    Float cAng = Utility.RandomFloat(0.0, 360.0)
    Float cTilt = Utility.RandomFloat(0.14, 0.28)
    ; 60 units past the floor assumed under the origin: a body whose origin
    ; sits above the floor (lying, ragdolled, on a slope) still marks it.
    If org.PlayImpactEffect(s0, "", cTilt * Math.Cos(cAng), cTilt * Math.Sin(cAng), -0.97, afHeight + 60.0, false, false)
        n += 1
    EndIf
    Int hLim = aiHorizMax
    If hLim < 0
        hLim = 0
    ElseIf hLim > 4
        hLim = 4
    EndIf
    Int hIdx = 0
    While hIdx < hLim
        ImpactDataSet sh = c.SetFor(aiKind, Utility.RandomInt(0, 2))
        If sh != None
            Float hAng = (90.0 * hIdx) + Utility.RandomFloat(-28.0, 28.0)
            Float hDz = Utility.RandomFloat(-0.22, 0.16)
            If org.PlayImpactEffect(sh, "", Math.Cos(hAng), Math.Sin(hAng), hDz, Utility.RandomFloat(84.0, 128.0), false, false)
                n += 1
            EndIf
        EndIf
        hIdx += 1
    EndWhile
    Return n
EndFunction

Int Function Burst(DC_Core c, ObjectReference org, Float afRadius, Int aiRays, \
                   Float afTurn, Float afHeight, Int aiKind)
    {One ring of the fan: aiRays cast DOWN AND OUT from the held origin at the
     circle of radius afRadius on the floor around them, starting afTurn degrees
     round. Returns how many laid a mark, or -1 if there was no atlas.}
    If c.SetFor(aiKind, DC_Api.LARGE()) == None
        Return -1
    EndIf
    If aiRays < 1
        Return 0
    EndIf
    Float step = 360.0 / aiRays
    Int n = 0
    Int i = 0
    While i < aiRays
        Int sz = Utility.RandomInt(0, 2)
        If afRadius < 40.0 && sz == 0 && Utility.RandomInt(0, 2) > 0
            sz = Utility.RandomInt(1, 2)
        EndIf
        ImpactDataSet s = c.SetFor(aiKind, sz)
        If s != None
            Float ang = afTurn + step * i + Utility.RandomFloat(-step * 0.44, step * 0.44)
            Float rJit = afRadius * Utility.RandomFloat(0.60, 1.42)
            Float lenJ = Math.sqrt(rJit * rJit + afHeight * afHeight)
            If lenJ >= 1.0
                ; Reach: 60 units past the aimed floor point, as Axis.
                If org.PlayImpactEffect(s, "", (rJit * Math.Cos(ang)) / lenJ, \
                                        (rJit * Math.Sin(ang)) / lenJ, \
                                        -afHeight / lenJ, lenJ + 60.0, false, false)
                    n += 1
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    Return n
EndFunction

Int Function Flat(DC_Core c, ObjectReference org, Int aiRays, Float afTurn, Int aiKind)
    {One flat ring: aiRays cast level, out from the held origin at their height,
     200 units, for the walls. Returns how many laid a mark, or -1 for no atlas.}
    If c.SetFor(aiKind, DC_Api.LARGE()) == None
        Return -1
    EndIf
    If aiRays < 1
        Return 0
    EndIf
    Float step = 360.0 / aiRays
    Int n = 0
    Int i = 0
    While i < aiRays
        ImpactDataSet s = c.SetFor(aiKind, Utility.RandomInt(0, 2))
        If s != None
            Float ang = afTurn + step * i + Utility.RandomFloat(-step * 0.42, step * 0.42)
            Float fDz = Utility.RandomFloat(-0.18, 0.16)
            If org.PlayImpactEffect(s, "", Math.Cos(ang), Math.Sin(ang), fDz, Utility.RandomFloat(165.0, 235.0), false, false)
                n += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    Return n
EndFunction
