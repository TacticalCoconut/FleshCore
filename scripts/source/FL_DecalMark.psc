Scriptname FL_DecalMark extends ObjectReference
{THE SURFACE HALF, AND NOTHING ELSE.

 This rides on an invisible activator that the spell's explosion drops where
 the shot landed -- the same chain Throw Voice has used since 2011:
 ThrowVoiceExplosion (0x07430E) places VoiceCastMarker (0x06B51D), MarkerX.nif,
 carrying a script.

 IT NO LONGER PAINTS ANYBODY. It used to find the nearest actor within eighty
 units and paint them, and "nearest" is not "hit": in play that marked
 bystanders, and marked nobody when the target who was hit happened to be
 standing further from the mark than someone else. The actor is FL_Decal's job
 now, because the magic effect is handed the target by name.

 AND THE DECAL IS LAID BY PlayImpactEffect, NOT BY THE EXPLOSION.
 The explosion carried the Impact Data Set at first, on the strength of 58
 vanilla explosions doing the same. In two tests running, surfaces took no
 mark at all -- while the OVERLAY textures, written by the same generator into
 the same format, rendered on skin perfectly well. That rules out the artwork
 and the file format and leaves the mechanism. So this uses the call FleshCore
 already lays its ground blood with, which is known to work.

 SIX DIRECTIONS, NEAREST SURFACE FIRST -- AND THAT ORDER IS THE FIX.

 This used to try DOWN first at the full 96-unit reach, then the horizontals.
 Down at 96 units finds the FLOOR from almost anywhere in a room. So a shot
 that hit a wall placed its marker on the wall, cast down, found the floor a
 metre below, and put the mark there. Walls never got marked; floors and
 furniture did, because for those the first ray was already the right one.
 That is the behaviour seen in testing, and it was an ordering bug,
 not a missing feature.

 So there are two passes. The SHORT pass reaches 20 units in all six
 directions: at that range only the surface the marker is actually sitting on
 can answer, whichever way it faces. The LONG pass is the old behaviour, kept
 as a fallback for a marker that ended up in open air.

 It stops at the first ray that reports a hit, so a mark in an open corner
 does not become six marks.}

Int Property Kind = 0 Auto
Float Property Reach = 96.0 Auto
{The fallback reach, for a marker that stopped in open air.}

FormList Property Chunks = None Auto
{FleshCore's FL_ChunkList -- the twenty shard activators. Set on the record.}

Float Property LiveRadius = 72.0 Auto
{How close a LIVING actor has to be before the marker will paint them itself.

 Tighter than BodyRadius on purpose. At 72 units -- about a metre -- a shot
 that detonated this close to them did, for all practical purposes, land on them,
 and the old bystander bug needs a generous radius to come back.}

Float Property BodyRadius = 90.0 Auto
{How far from the mark to look for a CORPSE. Deliberately tight: "nearest" is
 not "hit", and a generous radius here is what once painted
 bystanders.}

Int Property Draws = 14 Auto
{How many times to ask for a random nearby object. Papyrus has no "find all
 references", so covering a laid table means asking repeatedly and taking
 whatever comes back.

 How many distinct objects fourteen draws reach is counted separately.
 Successful shader calls cannot say it: the
 trace would count calls, and DC_Api.Coat returns true for any
 non-None reference, so the count would be the same whether fourteen
 draws found fourteen objects or found one cup fourteen times. Mark walks
 the FormIDs and reports the distinct count.

 Repeats no longer cost a redundant shader call -- a FormID already seen is
 not re-coated -- but they still cost a ray, deliberately: see the branch.}

Float Property ThingRadius = 110.0 Auto
{How far to look for a shard or a mundane object. Wider than BodyRadius is
 safe, because marking the wrong cup is not a bug anyone can see.}

Int Property Volleys = 4 Auto
{How many times the whole sweep is repeated. ONE, and five is what was
 breaking the wall marks.

 THE ENGINE HAS A DECAL POOL AND REPEATED SWEEPS EMPTY IT. skyrimprefs.ini's
 [Decals] uMaxDecals sets the pool. Mark() fires Blast twice per
 volley and Blast casts six rays, so five volleys is SIXTY axis casts per
 marker, plus up to Draws clutter rays. Measured, five volleys can lay several
 times as many marks as the engine pool holds, and the worst burst
 overflows the pool inside a single wound.


 Every one of those marks was LAID. PlayImpactEffect's own return value says
 so and SplatDir passes it straight through: none of the casts
 returned zero.
 They were laid and then flushed out of the pool by the next
 volley, seconds later.

 WALLS LOST FIRST, AND THAT IS WHY TESTING NOTICED THE WALLS. Only about 1.4
 of the eight horizontal rays land at Reach 96, while the two vertical ones
 land almost every time and re-stack on the same floor spot; so the floor
 keeps re-winning the pool it is itself emptying, and the rare wall mark is
 evicted before anybody walks round to look at it.

 This only ever runs for NON-NPC targets. A person is marked through RaceMenu
 overlays from FL_Decal and never comes through here.

 Raise it only alongside uMaxDecals: the two are one budget.}

Float Property NearReach = 20.0 Auto
{The opening pass. Short enough that only the surface the marker is ON can
 answer, which is what stops a wall hit being claimed by the floor below it.}

Bool _done = false

Event OnInit()
    Mark("OnInit")
EndEvent

Event OnLoad()
    Mark("OnLoad")
EndEvent

Function Mark(String how)
    If _done
        Return
    EndIf
    _done = true

    Int size = DC_Api.LARGE()
    ; EVERY DIRECTION, EVERY TIME, REPEATED. The old sweep stopped at the first
    ; ray that landed, which is right for one tidy mark and useless for finding
    ; out whether marks appear at all. Now every direction is fired on every
    ; volley, so a corner gets its floor AND both walls.
    Int landed = 0
    Int i = 0
    While i < Volleys
        landed += Blast(size, NearReach)
        landed += Blast(size, Reach)
        i += 1
    EndWhile
    String hit = "" + landed + " mark(s) from " + Volleys + " volley(s)"
    If landed == 0
        hit = "MISSED every direction at both ranges, " + Volleys + " times"
    EndIf

    ; ---- CORPSES -----------------------------------------------------------
    ;
    ; A dead actor takes no magic effect. Skyrim will not apply one to a corpse,
    ; so FL_Decal -- which is the exact path, handed the struck target by the engine, for the
    ; living -- never runs for the dead, and a corpse could be shot all day for
    ; nothing. The OVERLAY half has no such problem: NiOverride writes a shader
    ; override onto their 3D, and a corpse still has 3D.
    ;
    ; ONLY THE DEAD ARE PAINTED FROM HERE, and that is what keeps the old
    ; bystander bug from coming back. The living are handled by the magic
    ; effect, which is told who was struck; this branch never touches them, so
    ; "nearest" can never be mistaken for "hit" on anyone still standing.
    String who = "none"
    Actor near = Game.FindClosestActorFromRef(Self, BodyRadius)
    ; THE DISTANCE IS CHECKED AGAIN, NOT ONLY ASKED FOR. The living
    ; branch below re-measures with GetDistance against LiveRadius; the corpse
    ; branch trusted the search radius alone. A marker whose record sets a
    ; BodyRadius of one unit -- FL_Detonate_Mark, placed around a body the DLL
    ; is in the middle of taking apart -- must never paint that body, because
    ; an overlay write queues a rebuild of their 3D. Every other marker's
    ; BodyRadius is the same number it searched with, so nothing changes for
    ; them.
    If near != None && Self.GetDistance(near) <= BodyRadius && near.IsDead() && DC_Api.PaintReady()
        Int b = DC_Api.Paint(near, Kind, DC_Api.BODY(), 1.0)
        DC_Api.Paint(near, Kind, DC_Api.HANDS(), 1.0)
        DC_Api.Paint(near, Kind, DC_Api.FEET(), 1.0)
        DC_Api.Paint(near, Kind, DC_Api.FACE(), 1.0)
        ; AND COAT THEM TOO. The overlay only reaches bare skin; a corpse in
        ; armour shows none of it. The shader goes over whatever is actually
        ; being rendered, armour included.
        DC_Api.Coat(near, Kind)
        who = "corpse " + near + " body layer " + b
    ElseIf near != None && DC_Api.PaintReady()
        ; ---- AND THE LIVING, WHEN THE SPELL NEVER REACHED THEM -------------
        ;
        ; Field report: some NPCs are never marked at all. The Papyrus log says why,
        ; and says it without
        ; ambiguity: casts that land beside such a living
        ; actor produce no [DecalCore] hit line within two
        ; seconds, however many land and however close together, which is what
        ; casting repeatedly at someone who never gets marked looks like.
        ;
        ; FL_Decal never ran, so the magic effect never reached them: the
        ; projectile went past and detonated on the geometry behind. Those
        ; targets are bound and in furniture, and an actor in that state does not
        ; present the collision an aimed projectile needs.
        ;
        ; So the marker steps in -- but only where it is nearly certain, and
        ; only when the effect demonstrably did not:
        ;
        ;   * within LiveRadius, tighter than the corpse radius;
        ;   * and NOT already painted in the last second and a half, so a shot
        ;     that DID reach them is not painted twice and does not advance their
        ;     accumulation by two layers at once.
        ;
        ; The log says that guard will rarely fire: in it,
        ; casts that painted an actor did NOT also report one nearby
        ; here. The two paths are disjoint in practice. The guard is there
        ; because "in practice" is not "always".
        Float gap = Self.GetDistance(near)
        If gap <= LiveRadius && !DC_Api.RecentlyPainted(near, 1.5)
            Int lb = DC_Api.Paint(near, Kind, DC_Api.BODY(), 1.0)
            DC_Api.Paint(near, Kind, DC_Api.HANDS(), 1.0)
            DC_Api.Paint(near, Kind, DC_Api.FEET(), 1.0)
            DC_Api.Paint(near, Kind, DC_Api.FACE(), 1.0)
            DC_Api.Coat(near, Kind)
            who = "living " + near + " at " + gap \
                + "u -- the spell never reached them, painted layer " + lb
        Else
            who = "living " + near + " at " + gap + "u -- left to FL_Decal"
        EndIf
    ElseIf near != None
        who = "" + near + " nearby but skee is not running -- nothing to paint"
    EndIf

    ; ---- SHARDS ------------------------------------------------------------
    ; FleshCore's own gib pieces. They are activators from a known list, so
    ; unlike the rest of the world they can simply be looked up.
    String shard = "none"
    If Chunks != None
        ObjectReference ch = Game.FindClosestReferenceOfAnyTypeInListFromRef(Chunks, Self, ThingRadius)
        If ch != None
            ; Both mechanisms, because they fail in different places: the ray
            ; puts a proper projected decal on the floor beside the shard when
            ; it lands, and the shader marks the shard itself whether or not
            ; the ray found anything.
            Int sn = 0
            Int sj = 0
            While sj < Volleys
                If DC_Api.SplatToward(Self, ch, Kind, DC_Api.MEDIUM(), 4.0, 12.0)
                    sn += 1
                EndIf
                sj += 1
            EndWhile
            DC_Api.Coat(ch, Kind)
            shard = "" + ch + " coated, " + sn + " ray mark(s)"
        EndIf
    EndIf

    ; ---- CUPS, JUGS, PLATES, POTIONS ---------------------------------------
    ; SAMPLE THE WHOLE TABLE, NOT JUST THE NEAREST THING ON IT.
    ;
    ; Field report: the plate took the mark fully, the ewer partially, and the
    ; candles, cups, potion flask and book took nothing. That is not a list
    ; problem for most of them -- it is that this branch asked for the CLOSEST
    ; clutter reference, once, and coated that. One object per cast.
    ;
    ; FindRandom returns a different member of the set each time it is asked,
    ; so asking Draws times and coating whatever comes back covers a laid table
    ; instead of one plate on it. Repeats are harmless: coating an object twice
    ; is the same shader applied twice.
    ;
    ; ---- AND THE COUNT IS OF OBJECTS NOW, NOT OF SHADER CALLS --------------
    ;
    ; The old line -- "N of 14 draw(s) coated" -- cannot answer the coverage
    ; question testing raised (books and silver goblets better, not universal).
    ; DC_Api.Coat rejects only a None reference, a missing core and a
    ; missing shader record; past those three it Plays and returns true. So N
    ; counted SUCCESSFUL SHADER CALLS, and "14 of 14" was equally consistent
    ; with fourteen objects and with one cup coated fourteen times. Those are
    ; opposite answers and the log could not tell them apart.
    ;
    ; Worse, one test run shows the figure is strictly BIMODAL: 27 casts
    ; wrote "0 of 14 draw(s) coated" and 11 wrote "14 of 14", and nothing in
    ; between, ever. So a cast either finds clutter inside ThingRadius or finds
    ; none at all -- it is not a gradient across object types, and all of
    ; the coverage question lives inside those eleven identical lines.
    ;
    ; So the FormIDs are kept and walked. Papyrus has no set; a small Int array
    ; and a linear scan is the idiom, and at Draws entries of integer compare it
    ; is not worth measuring beside one native call. The array is built with
    ; Utility.CreateIntArray and not `new Int[14]` because `new` demands a
    ; literal, and a literal would stop matching Draws the first time that
    ; property is retuned on the record -- an overrun, not a smaller sample.
    ; distinct can never pass the number of draws that found anything, which is
    ; at most Draws, which is the length.
    ;
    ; ONLY THE COAT IS SKIPPED ON A REPEAT. THE RAY STILL FIRES.
    ; Coat resolves one fixed record -- either Coat shader, no choice in it --
    ; and plays it for an unlimited duration, so a second call on the same
    ; reference is the identical call and buys nothing; Draws' own note called
    ; those "one redundant shader call each". The ray is not the same: DC_Core's
    ; SetFor picks its atlas with Utility.RandomInt and the engine picks the
    ; quadrant and the size, so a second SplatToward at the same cup is a
    ; DIFFERENT mark. Dropping it would thin what is on the table, and this
    ; measurement has to be taken against the table already being looked
    ; at, or it measures something else.
    Int[] seen = Utility.CreateIntArray(Draws)
    Int distinct = 0
    Int found = 0
    Int coated = 0
    Int dj = 0
    While dj < Draws
        ObjectReference r = DC_Api.RandomClutter(Self, ThingRadius)
        If r != None
            found += 1
            Int id = r.GetFormID()
            Bool fresh = true
            Int scan = 0
            While scan < distinct
                If seen[scan] == id
                    fresh = false
                EndIf
                scan += 1
            EndWhile
            If fresh
                seen[distinct] = id
                distinct += 1
                If DC_Api.Coat(r, Kind)
                    coated += 1
                EndIf
            EndIf
            DC_Api.SplatToward(Self, r, Kind, DC_Api.SMALL(), 6.0, 14.0)
        EndIf
        dj += 1
    EndWhile

    ; THREE NUMBERS, BECAUSE THEY ARE THREE DIFFERENT FACTS. `found` of Draws is
    ; whether there was anything in radius at all -- the old bimodal 0 of 14 versus
    ; 14 of 14. `distinct` is how many different things those draws were, which is
    ; the coverage figure and the one that has never been written down. `coated`
    ; is how many of those the shader actually took, so a live core that has
    ; lost its Coat record reads as distinct > 0 with coated 0 instead of as an
    ; empty room.
    String thing = "" + coated + " coated, " + distinct + " distinct, from " \
                 + found + " of " + Draws + " draw(s)"
    ObjectReference obj = DC_Api.NearestClutter(Self, ThingRadius)
    If obj != None
        Int on = 0
        Int oj = 0
        While oj < Volleys
            If DC_Api.SplatToward(Self, obj, Kind, DC_Api.SMALL(), 6.0, 14.0)
                on += 1
            EndIf
            oj += 1
        EndWhile
        DC_Api.Coat(obj, Kind)
        thing = thing + "; nearest " + obj + ", " + on + " ray mark(s)"
    EndIf

    Debug.Trace("[DecalCore] surface mark(" + how + ") kind " + Kind + ": " + hit \
                + " | body: " + who + " | shard: " + shard + " | object: " + thing)

    DisableNoWait()
    Delete()
EndFunction

Int Function Blast(Int size, Float castDist)
    {Every one of the six axis casts, and a count of how many landed.

     Unlike Sweep this does NOT stop at the first hit. That is the difference
     between "put a mark somewhere" and "mark every surface this reaches",
     and this does the second.}
    Int n = 0
    If DC_Api.SplatDir(Self, Kind, size, 1.0, 0.0, 0.0, castDist, false)
        n += 1
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, -1.0, 0.0, 0.0, castDist, false)
        n += 1
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, 1.0, 0.0, castDist, false)
        n += 1
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, -1.0, 0.0, castDist, false)
        n += 1
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, 0.0, -1.0, castDist, false)
        n += 1
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, 0.0, 1.0, castDist, false)
        n += 1
    EndIf
    Return n
EndFunction

String Function Sweep(Int size, Float castDist, String tag)
    {Six axis casts at one range. Returns which one landed, or "" for none.

     THE PARAMETER IS NOT CALLED `reach`. Papyrus is case-insensitive, so a
     parameter named `reach` collides with the `Reach` PROPERTY on this script,
     and Caprica resolves the collision in the property's favour -- it says so,
     as W1004 "shadows script property, using property". Both passes would have
     silently cast at 96 units, the near pass would have been the far pass, and
     walls would still have lost to the floor. The build would have been clean
     and the fix would have done nothing.

     The horizontals come BEFORE down. At the short range it makes little
     difference -- only one surface is within reach -- but at the long fallback
     range it means a marker floating near a wall still prefers the wall to the
     floor it happens to be above.}
    If DC_Api.SplatDir(Self, Kind, size, 1.0, 0.0, 0.0, castDist, false)
        Return tag + " +x"
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, -1.0, 0.0, 0.0, castDist, false)
        Return tag + " -x"
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, 1.0, 0.0, castDist, false)
        Return tag + " +y"
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, -1.0, 0.0, castDist, false)
        Return tag + " -y"
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, 0.0, -1.0, castDist, false)
        Return tag + " down"
    EndIf
    If DC_Api.SplatDir(Self, Kind, size, 0.0, 0.0, 1.0, castDist, false)
        Return tag + " up"
    EndIf
    Return ""
EndFunction
