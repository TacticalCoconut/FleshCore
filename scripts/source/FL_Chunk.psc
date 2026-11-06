Scriptname FL_Chunk extends ObjectReference
{One separated shard of flesh, and its own undertaker.

 THE IMPULSE IS THROWN HERE, NOT WHERE THE SHARD IS PLACED. PlaceAtMe hands
 back a reference whose 3D has not loaded yet, and an impulse applied in that
 same frame lands on a havok body that does not exist -- the shard then only
 ever falls, because gravity is the one force that reached it. OnLoad fires
 when the 3D is real, so the throw lands.

 A SHARD LANDS AND BLEEDS, SILENTLY. From the throw until it settles, a short
 poll watches its height; the tick it stops falling it plays a SILENT impact
 straight down, so the floor gets a blood pool where the shard came to rest.
 The squelch belongs to the blow, not to the landing, and is played there.

 AND IT NO LONGER SQUASHES. The landing used to pulse SetScale for a jiggle.
 SetScale on a havok reference makes the engine REBUILD ITS 3D -- proven, from
 the engine's own load events, which reported GOT its 3D / lost its 3D / GOT
 its 3D for every shard of every wound that used it. That second load competes
 with every other shard still streaming in, and a shard that loses it is
 invisible forever. A jiggle is not worth a shard.

 Self-cleaning: the shard settles, cannot be picked up, and then removes
 itself. Persistent references are how a save grows without anyone noticing;
 these are placed persistent so the engine cannot reclaim them mid-flight,
 which makes the undertaker mandatory rather than polite.}

Float Property Lifetime = 45.0 Auto
{Seconds on the ground before it goes.}

Float Property SectionLifetime = 300.0 Auto
{Seconds a SEVERED SECTION stays. A shard is debris and forty-five seconds is
 generous for it; a severed arm is the aftermath of what just happened, and it
 should still be lying there when the fight is over and you walk back to look.}

Int Property MaxPieces = 35 Auto
{THE LIVE-PIECE CAP. How many pieces may lie about at once, every
 target's together, shards and severed sections alike. A new piece's OnInit adds
 itself to a shared, ORDERED ring and tells the OLDEST to go when the ring is
 over this -- the bleed ring's shape (BeginBleed), for the bleed ring's reason.
 0 = no cap; every piece still joins the ring all the
 same, so a cap set later can clear it. Overridden through StorageUtil
 "FC_maxpieces": by the cfg's LP row on every load
 (FL_Watch.LearnPanelFromConfig) and by the HQ's "Pieces kept
 on the ground" slider over it once moved, live (FL_Watch.LearnPieceCap, which
 also clears the floor down to a lowered cap within seconds: TrimPieceRing, 32
 a batch). The lifetimes above are the cfg's alone, overridden the same way
 (FC_shardlife, FC_sectionlife). The ring lives in the co-save: a loaded piece
 keeps its place (OnInit runs once per object, never again on a load), and a
 piece that is gone reads back as None and drains in ClearPastCap. A load
 clears nothing unless the HQ's cap is below what the save has down; FL_Watch
 then trims to it.}

Float Property Force = 90.0 Auto
{Impulse as the shard comes away. SET BY THE PLUGIN RECORD at 90, so editing
 this default changes nothing -- see ForceScale, which is what to turn.}

Float Property ForceScale = 0.2 Auto
{THE SHARDS WERE BEING SHOT OUT, AND THE MASS CAP IS WHY.

 ApplyHavokImpulse applies an IMPULSE, and the velocity a body leaves with is
 that impulse divided by its MASS. Nothing about the throw changed; the mass
 underneath it did.

 Debris mass was capped at 4.0, because shipped shards were coming out at
 13 to 50 units -- heavier than the ragdoll bones they were landing on -- and
 that weight was throwing the corpse across the room. The cap fixed the kick.
 It also made every shard about five times lighter while the impulse stayed at
 90, so every shard left about five times faster:

     before   f 90 / mass ~20  ->  v ~ 4.5
     after    f 90 / mass   4  ->  v ~ 22.5

 The number that restores the throw the mass cap broke is 90 * 4/20 = 18, so
 the scale is 0.2. It is a separate property because Force itself is written
 into every pool record by the plugin, and the ESP is append-only:
 changing a baked value means rebuilding the plugin, and a script default the
 plugin does not set costs nothing and is reachable from here.

 A severed SECTION is not affected. Its mass was never capped -- it is a limb
 and weighs like one -- and SectionForce has always been its own small number.}

Float Property SectionForce = 45.0 Auto
{Impulse for a severed section. Deliberately small: a torso that cartwheels
 across the room reads as a bouncing prop, while one that drops roughly where
 it was cut reads as what it is. Gravity does the rest.}

Bool Property LandingSplatter = true Auto
{Whether a shard leaves a blood decal where it settles. BACK ON, now that the
 square is understood and fixed in the record rather than worked around here.

 The impact this plays was orientation 2 -- Projectile Reflection -- which on a
 cast fired straight DOWN projects almost edge-on and is clipped by its own
 projection box into a square frame with a bright rim. Its twin, the loud
 wound-time splat, was changed to orientation 1 first, for exactly that
 reason; this one was missed, and this one is the one that actually draws. It
 is orientation 1 now, which is what vanilla's own downward blood
 uses, and the mark it leaves is Bethesda's blood decal on the floor.}

ImpactDataSet Property Squish = None Auto
{FL_ShardImpactSetQuiet: the blood decal alone, answered for every floor
 material, with NO sound -- the squelch is played once at the blow by FL_Watch.
 Filled by the plugin record; when absent the shard still lands, just clean.}

; A PIECE of THE BODY, NOT A PIECE OFF THEM.
;
; TRUE DISMEMBERMENT hands this script whole limbs and body halves, and they
; are not debris: they last minutes rather than seconds and they are barely
; thrown at all. FL_Watch sets this between PlaceAtMe and the frame the 3D
; arrives -- which is a frame or more, because PlaceAtMe attaches 3D
; asynchronously, so it always wins the race to OnLoad.
Bool section = false
Int kick = 0                ; the wound's kick, given with ItIsAPieceOfTheBody
; ---- TOLD BY THE ENGINE, THROUGH THE ROLL ----------------------------
;
; A piece the ENGINE placed (FleshCore.cfg.txt `E`) exists before FL_Watch has
; read the wound at all, so nobody can call ItIsAPieceOfTheBody on it in time. The
; engine tells it instead, through the one thing it controls at creation: the
; reference's Y angle. It is placed rolled by
;
;     0.1234 rad + code * 0.00001 rad     (7.0703 deg + code * 0.00057296 deg)
;     code = 1 + 2*section + 4*kick + 256*mark
;
; -- seven degrees and a fraction, on debris about to be thrown, and a roll
; no standing actor ever has, so a piece FL_Watch placed (which inherits the
; target's own angles) is never mistaken for one. Decoded in OnInit from this
; reference's own angle: a native on itself, waiting on nobody.
Bool engineMade = false     ; the roll decoded: this piece was placed by the engine
Int  rollMark = -1          ; the wound's forced mark from the roll (0 theirs, 1 blood, 2 alt)
Float Property RollBase = 7.0702992 Auto
{0.1234 rad in degrees -- the roll an engine-placed piece is born with, before
 its code is added. Must match flesh.cpp PlaceOne.}
Float Property RollStep = 0.00057295780 Auto
{0.00001 rad in degrees -- one unit of the code. Must match flesh.cpp PlaceOne.}
Float Property PitchSeal = 4.4518821 Auto
{0.0777 rad in degrees -- the X angle every engine-placed piece is also born
 with, required alongside the roll so a piece placed by FL_Watch, which wears
 its target's own angles, cannot decode as engine-placed by chance. Must match
 flesh.cpp PlaceOne.}

Bool thrown = false
Int settlePolls = 0
Float lastZ = 0.0
Float born = 0.0
Bool evicted = false        ; told to go by a newer piece: the ring was over its cap

; ---- THE PROBES ---------------------------------------------------------
;
; WHAT THE OLD LOG COULD NOT SAY. In one test, eighty-four pieces were placed, the
; engine's own load event fired for nine of them, and the other seventy-five
; were never given 3D at all -- not slowly, never. The old log could not tell
; "it took too long" from "it was never going to happen", because the only
; question it ever asked was Is3DLoaded() twenty seconds later.
;
; So the wait is now measured: a tenth-of-a-second poll for
; the first few seconds, which records the exact tick 3D arrived, or proves
; that it did not arrive in a window nothing could reasonably need.
Int    probePolls = 0
Float  probeStart = 0.0
Bool   probeDone  = false
Int    poolSlot = -1
Bool   toldEngine = false

Bool Property ProveShader = false Auto
{Also play Bethesda's own BerserkerFXS on every piece, as a control.

 OFF. It is a diagnostic: with it on, every
 single piece plays a THIRD membrane shader on top of the blood coat and their
 mark, which is both an extra cost and a confound on any judgement
 of how the coats themselves look.

 WHAT IT ANSWERS: whether a membrane shader can attach to a forged piece
 at all. The coats alone cannot say, because a coat that fails to show
 looks the same whether the record or the piece is at fault, and only a
 vanilla shader on the same piece tells the two apart.


 To ask it: set this true, build, cast once, and read the PROOF line below
 against the CoatSkin line beside it. If the piece is visibly bloody under
 Bethesda's own shader and not under FleshCore's, the fault is in FleshCore's records; if it
 is clean under both, a forged piece cannot take a membrane and the blood has
 to be baked into the mesh by the DLL instead.}

Int Property BloodLevel = 5 Auto
{How bloody a piece is as it comes away, on DecalCore's 0-5 accumulation scale.

 FIVE, the top of it. A shard is not a target who has been splashed once; it is
 the inside of somebody, a second old. The scale exists so the coats can be
 subtle on skin, and nothing about that argues for subtlety here.

 The plugin does not set this, so editing the default is enough to change it.}

; ---- BLEEDING WHERE IT CAME TO REST -------------------------------------
;
; A piece of somebody, a second old, lying on a floor. It should leave a pool,
; and the pool should grow for a moment and then stop -- blood runs out.
;
; TWO LIMITS, both because the engine's decal pool is finite and shared with
; every other mark in the game. A dismemberment can put eight pieces down at
; once; eight pieces each dripping five marks is forty from one blow, and the
; pool holds every arrow scar and every other mod's blood too.
Bool Property BleedAtRest = true Auto
{Whether a piece bleeds where it settles.}

Float Property BleedMinSize = 10.0 Auto
{The smallest piece worth a pool, as the LONGEST side of its bounding box in
 game units -- measured off the loaded 3D with SKSE's GetWidth/GetLength/
 GetHeight, not taken from a cell count, because the cell count is
 not carried across the file bridge and the bounding box is the thing actually
 lying on the floor. A chip of fingertip does not pool.}

Int Property BleedMaxConcurrent = 6 Auto
{How many pieces may bleed at once. When a new one starts and that would make
 it MaxConcurrent + 1, the OLDEST stops -- it has been lying there longest and
 has most nearly finished anyway.}

Int Property BleedDrips = 5 Auto
{How many marks a piece lays before it runs dry.}

Float Property BleedInterval = 0.8 Auto
{Seconds between them. Five at 0.8 is four seconds of pooling.}

Int bleedLeft = 0

Bool Property ForceDynamic = false Auto
{Call SetMotionType(Motion_Dynamic) when the piece loads. OFF, and the reason
 is measured.

 THIS CALL WAS COSTING A WHOLE SECOND BUILD OF THE 3D. The engine's own load
 events show it: twenty of forty-five shards went GOT its 3D -> lost it
 -> GOT it again, and the loss landed about 0.13s after the first arrival --
 which is when Papyrus gets round to dispatching OnLoad. Touching a
 havok reference's motion type destroys and rebuilds its 3D, the same way
 FL_Chunk's header records SetScale doing, and the shard cannot be thrown until
 the rebuild finishes. It was most of the spawn delay.

 And it was never needed. The forged collision is DF's own limb body, and its
 motionSystem byte is 3 -- BOX_INERTIA -- which is already a dynamic motion
 type. The piece falls and takes an impulse the moment its 3D exists; nothing
 has to ask it to.

 Set true if a shard ever loads and refuses to move.}

Bool Property ProbeVerbose = false Auto
{THE PROBES COST WHAT THEY MEASURE, so they are off unless asked for.

 The dossier is a dozen native calls and a fourteen-term string concatenation,
 and it used to run inside OnInit -- which is inside PlaceAtMe, which is on the
 critical path between the blow landing and the shard appearing. The watcher's
 census was worse: up to thirty-two Is3DLoaded() calls for every piece placed.
 They found the fault they were built for; leaving them switched on afterwards
 would mean shipping a permanent tax on the exact latency they were used to
 measure. Set true to bring them all back.}

Int Property ProbeTicks = 40 Auto
{How many polls to spend watching for 3D before recording that it did not come
 quickly. Forty at a quarter-second is ten seconds -- an eternity for a mesh
 that in the good case attaches in the same second it is placed.}

Float Property ProbeInterval = 0.05 Auto
{Seconds between 3D polls for the first second of a piece's life.

 This was a quarter of a second when it was only ever a measurement. Now it
 matters: the poll is one of the two things that can throw a piece, and
 the test log says which one wins is not consistent -- OnLoad usually fires
 around 0.35s, but it took 0.76s longer than the poll had already seen the 3D
 on one piece in ten. Whichever notices first now does the work, so the slow
 case costs nothing.}

Float Property SlowInterval = 0.5 Auto
{Seconds between polls after the first second. A piece that has no 3D after a
 second is not about to get one in a hurry, and polling it twenty times a
 second for ten more is how a diagnostic becomes a performance problem.}

Int Property FastPolls = 20 Auto
{How many polls to spend at the fast interval before dropping to the slow one.}

Function CameFromPool(Int slot)
    {Which pool record this piece was placed on. The engine needs it to answer
     what that record points at NOW, which is the question behind "the mesh was
     taken away before the game got to it".}
    poolSlot = slot
EndFunction

Function Dossier(String when)
    {Everything knowable about this piece from up here, in one line.

     Written at placement and again at every point it could have gone wrong, so
     the two can be compared. A piece that is enabled, in a cell, near the
     player and still has no 3D is a different bug from one that was disabled,
     deleted, or left in an unloaded cell -- and those four were indistinguishable
     in every log before this one.}
    If !ProbeVerbose
        Return
    EndIf
    Actor pl = Game.GetPlayer()
    Float d = -1.0
    If pl
        d = pl.GetDistance(self)
    EndIf
    Cell c = GetParentCell()
    String cn = "<none>"
    If c
        cn = c as String
    EndIf
    Debug.Trace("[FleshCore] PROBE " + when + " " + self         + " pool=" + poolSlot         + " base=" + GetBaseObject()         + " 3D=" + Is3DLoaded()         + " disabled=" + IsDisabled()         + " deleted=" + IsDeleted()         + " section=" + section         + " thrown=" + thrown         + " cell=" + cn         + " pos=(" + GetPositionX() + "," + GetPositionY() + "," + GetPositionZ() + ")"         + " distToPlayer=" + d         + " age=" + (Utility.GetCurrentRealTime() - born))
EndFunction

Function AskTheEngine()
    {Hand this piece's id and pool record to the DLL, which can see the things
     Papyrus cannot: whether the reference is still in the form map at all,
     whether it has loaded data, whether that data has 3D hung off it, and what
     the pool record it was placed on currently points at.

     Appended, not overwritten -- several pieces give up in the same second and
     each of them has a different story. The engine empties this file when it
     reads it, at the start of the next wound.}
    If toldEngine
        Return
    EndIf
    toldEngine = true
    String line = GetFormID() + "," + poolSlot + ";"
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.ask.txt", line, true, false)
EndFunction

Function ItIsAPieceOfTheBody(Int aiKick = 0)
    {Told by FL_Watch that this is a severed section rather than a shard.

     A function and not a property, because the two things it changes are read
     at two different moments -- the throw in OnLoad, the lifetime in OnUpdate
     -- and both of them are after this object already exists.

     AND HOW HARD TO THROW ITSELF. The wound's kick rides on the same
     call rather than in a shared slot, because this call already exists and
     is already paid for on every section: a slot read a quarter of a second
     later, when this piece's 3D arrives, is a slot another wound may have
     overwritten by then. Shards do not take a kick at all -- a section is
     a limb, and a limb leaving at eight times its usual pace is
     what "forcefully" means; a gobbet at eight times its pace is a shard
     through the camera.}
    section = true
    kick = aiKick
EndFunction

Float Function Life()
    {How long this piece has. Read fresh every tick, so a section told what it
     is a moment after OnInit is not held to the shard clock OnInit started.
     The cfg's LP row, read through StorageUtil, outranks the properties.}
    If section
        Float sl = StorageUtil.GetFloatValue(None, "FC_sectionlife", SectionLifetime)
        If sl > 0.0
            Return sl
        EndIf
    EndIf
    Return StorageUtil.GetFloatValue(None, "FC_shardlife", Lifetime)
EndFunction

Event OnInit()
    BlockActivation(true)
    born = Utility.GetCurrentRealTime()
    probeStart = born
    ; into the piece ring; joining over the cap evicts the oldest.
    JoinPieceRing()
    ; ---- WAS THIS PIECE MADE BY THE ENGINE? ----------------------------
    ; One native, on this reference, before anything else. GetAngleY on a
    ; reference with no 3D yet reads the angle it was placed with.
    Float roll = GetAngleY()
    If roll > RollBase - RollStep && roll < RollBase + RollStep * 1024.0
        Float pitch = GetAngleX()
        Int code = Math.Floor((roll - RollBase) / RollStep + 0.5)
        Float back = RollBase + code * RollStep
        If code >= 1 && code <= 1023 && Math.abs(roll - back) < RollStep * 0.25 \
                && Math.abs(pitch - PitchSeal) < 0.002
            engineMade = true
            section = (code / 2) % 2 == 1
            kick = (code / 4) % 64
            rollMark = (code / 256) % 4
            ; LOGGED, ONCE PER PIECE: this line is the probe's proof that an
            ; engine-placed reference runs this script and reads its roll.
            Debug.Trace("[FleshCore] piece " + self + " was placed by the engine: section=" \
                        + section + " kick=" + kick + " mark=" + rollMark \
                        + " (roll " + roll + ", pitch " + pitch + ")")
        Else
            Debug.Trace("[FleshCore] piece " + self + " has a roll in the engine's band but" \
                        + " does not decode (roll " + roll + ", pitch " + pitch + ", code " + code + ")")
        EndIf
    ElseIf roll != 0.0
        ; A script-placed piece wears its target's angles, and an actor's roll
        ; is zero. A non-zero roll outside the band is therefore either an
        ; engine-placed piece whose angle was already changed by the time
        ; this ran -- which is what the probe needs to know -- or a target
        ; who was rolled, which is worth a line too.
        Debug.Trace("[FleshCore] piece " + self + " born with roll " + roll \
                    + " outside the engine's band (pitch " + GetAngleX() + ")")
    EndIf
    ; THE FAST WATCH. Not the lifetime clock -- that is set when the fast watch
    ; ends. Six seconds at a tenth of a second is the window in which a mesh
    ; either attaches or is never going to, and every tick of it is recorded so
    ; the answer is a measurement.
    probePolls = 0
    RegisterForSingleUpdate(ProbeInterval)
    If ProbeVerbose
        Debug.Trace("[FleshCore] piece " + self + " created")
        Dossier("placed")
    EndIf
EndEvent

Function Launch()
    {THE FRAME THE PIECE BECOMES REAL -- reached from either direction.

     This used to live in OnLoad and nowhere else, and OnLoad is an event the
     engine queues and the Papyrus VM dispatches when it gets to it. Measured:
     usually about 0.35s after placement, but on one piece in ten it arrived
     three quarters of a second AFTER this script's own poll had already seen
     the 3D sitting there. Three quarters of a second of a shard hanging in the
     air, waiting for a message about something that had already happened.

     So the poll calls this too, and whichever notices first does the work.
     Guarded by `thrown`, which was already the guard OnLoad used against
     firing twice when a piece loses and regains its 3D.}
    If thrown
        Return
    EndIf
    thrown = true
    ; ACTIVATION: blocked as always, unless a caller
    ; has asked for it through FL_Api.EnableShardActivation -- the word is
    ; the number of callers that did. A piece launched before anyone asked
    ; stays blocked for its lifetime.
    BlockActivation(StorageUtil.GetIntValue(None, "FC_shardact", 0) == 0)
    If ForceDynamic
        SetMotionType(Motion_Dynamic, false)
    EndIf
    Float f = Force * ForceScale
    If section
        ; The section's mass was never capped, so its force needs no rescaling.
        f = SectionForce
    EndIf
    ; ---- THE WOUND'S KICK -----------------------------------------
    ;
    ; A multiplier the wound's own W row asked for, handed through the flags
    ; word to FL_Watch and given to this piece with ItIsAPieceOfTheBody, before
    ; its 3D exists. 0 and 1 are the throw above, untouched; Detonate's 8 is
    ; what turns fifteen sections lying where they were cut into fifteen
    ; sections leaving in every direction at once. Sections only -- see
    ; ItIsAPieceOfTheBody for why a shard never takes it.
    If section && kick > 1
        f = f * kick
    EndIf
    If section
        ; Topple severed limb/leg sections immediately off vertical equilibrium
        ; so they collapse horizontally onto the ground instead of standing upright.
        SetAngle(Utility.RandomFloat(65.0, 85.0), \
                 Utility.RandomFloat(-35.0, 35.0), \
                 GetAngleZ())
        Float sx = Utility.RandomFloat(0.65, 1.0)
        If Utility.RandomInt(0, 1) == 0
            sx = -sx
        EndIf
        Float sy = Utility.RandomFloat(0.65, 1.0)
        If Utility.RandomInt(0, 1) == 0
            sy = -sy
        EndIf
        ApplyHavokImpulse(sx, sy, -0.35, f)
    Else
        ApplyHavokImpulse(Utility.RandomFloat(-1.0, 1.0), \
                          Utility.RandomFloat(-1.0, 1.0), \
                          Utility.RandomFloat(0.10, 0.80), f)
    EndIf
    ; MEASURED, THEN SILENCED. This line proved that a piece is thrown 0.13 to
    ; 0.25s after its own placement -- fast -- while the wound as a whole took
    ; seconds, which is what sent the search to the placement loop where the
    ; fault actually was. It has no question left to answer.
    ;
    ; It is not free. With bEnableLogging=1 every trace
    ; is a synchronous write, and this one is a six-term concatenation plus a
    ; native GetPositionZ, per piece, in the exact window the pieces are
    ; competing for VM time with the loop still placing their siblings.
    If ProbeVerbose
        Debug.Trace("[FleshCore] " + self + " has 3D and was thrown at " \
                    + GetPositionZ() + "z, force " + f + ", section " + section \
                    + ", " + (Utility.GetCurrentRealTime() - born) + "s after placement")
    EndIf
    ; A PIECE OF SOMEONE MARKED IS ALSO MARKED, AND THIS IS THE PLACE.
    ;
    ; An effect shader needs 3D to attach to, exactly as the impulse above
    ; does. It was first put in OnLoad, which is nearly right and wrong in two
    ; ways this function already documents:
    ;
    ;   * OnLoad is not the earliest moment the 3D exists. This function is
    ;     reached from OnLoad OR from the poll, "whichever notices first", and
    ;     the note above records the poll beating OnLoad by three quarters of a
    ;     second on one piece in ten. Here it lands as soon as the 3D is real.
    ;   * SetMotionType above REBUILDS the 3D -- this file's own OnLoad comment
    ;     says two of them back to back are "two rebuilds of it". A shader
    ;     applied before that call would be applied to geometry about to be
    ;     thrown away. ForceDynamic happens to default false and the plugin
    ;     never sets it, so nothing is rebuilt today -- by luck, which is why
    ;     the shader still waits until after it.
    ;
    ; And `thrown` guards it, so it happens exactly once however it was reached.
    ; BLOOD FIRST, AND UNCONDITIONALLY.
    ;
    ; This used to coat a piece ONLY when the target it came off had been
    ; painted, which is a rule about DecalCore's bookkeeping and not about
    ; flesh. In a test screenshot of two severed arms the cut
    ; faces are raw meat and the SKIN is clean, because they had never been hit
    ; with a marking spell. A limb that has just been torn off a body is bloody
    ; whether or not anybody painted the target first.
    ;
    ; So every piece takes a heavy blood coat as it comes away, and their own
    ; mark goes on top of it when they had one -- two membrane passes, which
    ; composite, so a target covered in one fluid ends up with a piece wearing
    ; both. That is also what a piece of them should look like.
    DC_Api.CoatSkin(Self, DC_Api.BLOOD(), BloodLevel)
    Int mark = DC_Api.PendingMark()
    ; an engine-placed piece of a wound that FORCES alt (the alt burst's
    ; W row says mark 2) carries that in its roll and does not depend on
    ; FL_Watch having reached SetPendingMark before this piece's 3D arrived --
    ; the exact packing FL_Watch uses for a forced mark, kind * 10 + level 5.
    If engineMade && rollMark == 2
        mark = DC_Api.ALT() * 10 + 5
    EndIf
    If mark >= 0 && mark / 10 != DC_Api.BLOOD()
        DC_Api.CoatSkin(Self, mark / 10, mark % 10)
    EndIf
    ; ---- THE CONTROL -----------------------------------------------
    ;
    ; DecalCore's side of an unpainted shard checks out against
    ; the shipped files: the
    ; effect shader records carry FillFullAlphaRatio 1 and flags 264, they
    ; alpha-blend, they point at textures that exist on disk and are 83% ink
    ; across the whole square, the pending mark is valid on every wound,
    ; and CoatSkin runs on every piece. There is nothing
    ; left on that side to be wrong.
    ;
    ; So the question is not "is FleshCore's record right" but "can a membrane
    ; shader attach to one of these forged meshes AT ALL" -- and that is
    ; answerable in one cast with a vanilla shader.
    ;
    ; BerserkerFXS, 0x000FD7D9, is Bethesda's own: a membrane with no particles
    ; whose fill texture is Blood\DecalsBloodSplatter01.dds, the record every
    ; one of FleshCore's was cloned from. If a shard turns visibly bloody under it,
    ; the mechanism works and the fault is in FleshCore's records after all. If a shard
    ; stays clean under Bethesda's own blood shader, then a FleshCore piece
    ; cannot take a membrane and the coats have to be baked into the forged
    ; mesh instead, which the DLL can do.
    ;
    ; Off by default; turn it on only to run that comparison.
    If ProveShader
        EffectShader proof = Game.GetFormEx(0x000FD7D9) as EffectShader
        If proof
            proof.Play(Self, -1.0)
            Debug.Trace("[FleshCore] PROOF: played vanilla BerserkerFXS on " + Self \
                        + " (3D=" + Is3DLoaded() + ")")
        Else
            Debug.Trace("[FleshCore] PROOF: could not resolve BerserkerFXS 0x000FD7D9")
        EndIf
    EndIf

    ; From here the update chain is the LANDING WATCH, at a tenth of a second;
    ; the lifetime clock keeps its own time through `born`.
    settlePolls = 0
    lastZ = GetPositionZ()
    Nap(0.1)
EndFunction

Event OnLoad()
    If ProbeVerbose
        Debug.Trace("[FleshCore] PROBE onload " + self + " -- 3D ARRIVED after " \
                    + (Utility.GetCurrentRealTime() - born) + "s")
        Dossier("onload")
    EndIf
    ; NOTHING ELSE HERE. This used to call BlockActivation and SetMotionType
    ; and then call Launch(), which calls both again -- two motion-type changes
    ; back to back on a reference whose 3D had just arrived, which is two
    ; rebuilds of it. Launch does the work; this only says when.
    Launch()
EndEvent

Event OnUnload()
    If ProbeVerbose
        Debug.Trace("[FleshCore] " + self + " unloaded (thrown=" + thrown + ", section=" + section + ")")
        Dossier("onunload")
    EndIf
EndEvent

Event OnActivate(ObjectReference akActionRef)
    {A consumer's actor touched this piece. The condition is the
     consumer's: the handler of FL_ShardActivated tests werewolf form, the
     ring, the faction, whatever it likes, and calls FL_Api.ConsumeShard if it
     wants the piece. strArg: shardId|victimId|part|layers|cells|section.}
    If !akActionRef
        Return
    EndIf
    String prov = StorageUtil.GetStringValue(self, "FC_prov", "")
    If prov == ""
        Return
    EndIf
    String[] f = StringUtil.Split(prov, "|")
    String rest = ""
    If f.Length >= 2
        String[] g = StringUtil.Split(f[1], ":")
        Int i = 0
        While i < g.Length
            rest += "|" + g[i]
            i += 1
        EndWhile
        rest = f[0] + rest
    Else
        rest = prov
    EndIf
    akActionRef.SendModEvent("FL_ShardActivated", GetFormID() + "|" + rest, 0.0)
EndEvent

Function Consume()
    {The undertaker, run early for a piece somebody consumed (FL_Api.ConsumeShard).}
    LeavePieceRing()
    Disable(true)
    Delete()
    DeleteWhenAble()
EndFunction

Event OnUpdate()
    Float age = Utility.GetCurrentRealTime() - born
    ; age < 0: born in an earlier launch of the game. GetCurrentRealTime counts
    ; from the executable's start, and a saved section (300 s) can outlive a
    ; launch -- such a piece has had its time.
    If evicted || age >= Life() || age < 0.0
        If ProbeVerbose
            Debug.Trace("[FleshCore] " + self + " lifetime up -- deleting (evicted=" + evicted + ", age " + age + ")")
            Dossier("at-deletion")
        EndIf
        LeavePieceRing()
        Disable(true)
        Delete()
        DeleteWhenAble()
        Return
    EndIf
    ; ---- BLEEDING, WHILE IT HAS BLOOD LEFT -------------------------------
    ;
    ; Multiplexed onto the same single update slot everything else here uses:
    ; Papyrus gives a script exactly one RegisterForSingleUpdate, so a separate
    ; bleed timer is not available and a second script on the same reference
    ; would be a second thing to keep in step. The lifetime check above still
    ; runs first on every tick, so a piece that would bleed past its own
    ; deletion time is deleted on schedule rather than kept alive by pooling.
    If settlePolls == -1 && bleedLeft > 0
        bleedLeft -= 1
        If Squish
            PlayImpactEffect(Squish, "", 0.0, 0.0, -1.0, 96.0, false, false)
        EndIf
        If bleedLeft > 0
            Nap(BleedInterval)
        Else
            LeaveBleedRing()
            Nap(Life() - age)
        EndIf
        Return
    EndIf
    ; ---- THE FAST WATCH FOR 3D ------------------------------------------
    ;
    ; Runs before anything else and only until it has an answer. OnLoad is the
    ; event that says 3D arrived, but an event that never fires cannot tell you
    ; WHEN it stopped being possible; this polls the same fact directly, so the
    ; log carries either "3D at poll 7" or "still nothing after six seconds",
    ; and those are different bugs.
    ; ---- THE RACE FOR 3D --------------------------------------------------
    ;
    ; Not a measurement any more. This poll is one of the two things that can
    ; throw a piece, and it exists because the other one -- OnLoad -- is an
    ; event dispatched at the VM's convenience and is sometimes most of a
    ; second late. Whichever sees the 3D first launches the piece.
    If !probeDone
        probePolls += 1
        If Is3DLoaded()
            probeDone = true
            If ProbeVerbose
                Debug.Trace("[FleshCore] PROBE 3d-arrived " + self + " at poll " \
                            + probePolls + " (" + (Utility.GetCurrentRealTime() - probeStart) \
                            + "s after placement)")
                Dossier("3d-arrived")
            EndIf
            ; THE POLL THROWS IT. If OnLoad has already been and gone this is a
            ; no-op; if it has not, this is three quarters of a second the
            ; shard does not spend hanging in the air.
            Launch()
            Return
        ElseIf probePolls >= ProbeTicks
            probeDone = true
            Debug.Trace("[FleshCore] " + self + " -- no 3D after " \
                        + probePolls + " poll(s), " \
                        + (Utility.GetCurrentRealTime() - probeStart) + "s")
            If ProbeVerbose
                Dossier("3d-never")
            EndIf
            ; Hand it to the engine, which can see what Papyrus cannot.
            AskTheEngine()
        Else
            ; Fast while it matters, slow once it clearly does not.
            If probePolls < FastPolls
                Nap(ProbeInterval)
            Else
                Nap(SlowInterval)
            EndIf
            Return
        EndIf
        ; The watch is over and this piece never got its 3D. Hand the clock
        ; back to the long lifetime wait.
        If !thrown
            Float rest = Life() - (Utility.GetCurrentRealTime() - born)
            If rest < 0.1
                rest = 0.1
            EndIf
            Nap(rest)
            Return
        EndIf
    EndIf
    If thrown && settlePolls >= 0
        settlePolls += 1
        Float zNow = GetPositionZ()
        Bool still = (zNow - lastZ) < 0.35 && (lastZ - zNow) < 0.35
        lastZ = zNow
        ; Landed: two consecutive quiet ticks after at least three of flight,
        ; or sixty ticks of never settling (wedged somewhere) -- either way
        ; the wet arrival plays once and the watch ends.
        If (still && settlePolls > 3) || settlePolls > 60
            settlePolls = -1
            Land()
            ; Land() may have started a bleed, in which case the next tick is
            ; the next drip rather than the deletion. Asking bleedLeft keeps
            ; the decision in one place.
            If bleedLeft > 0
                Nap(BleedInterval)
            Else
                Nap(Life() - (Utility.GetCurrentRealTime() - born))
            EndIf
        Else
            Nap(0.1)
        EndIf
        Return
    EndIf
    ; NOT THROWN, SO NOT LOADED YET -- or loaded somewhere nobody is looking.
    ; Keep checking, but keep checking against the time this piece actually has
    ; left rather than forever at a fixed rate: a severed section lives for five
    ; minutes, and half-second polling across that is six hundred updates for a
    ; thing that is doing nothing.
    Float left = Life() - age
    If left > 2.0
        left = 2.0
    ElseIf left < 0.1
        left = 0.1
    EndIf
    Nap(left)
EndEvent

Function Land()
    {The arrival: plays Squish, the silent blood decal, when LandingSplatter is on, then starts the bleed.}
    ; ---- THE SQUARE WAS AN ORIENTATION, AND IT IS FIXED IN THE RECORD ----
    ;
    ; This was switched off at first because every shard was leaving a hard square
    ; crop with a bright rim. That was right as a stopgap and wrong as a
    ; diagnosis of the artwork: the texture and the model here are Bethesda's
    ; own, copied verbatim. What was FleshCore's was the ORIENTATION -- 2, Projectile
    ; Reflection -- on an effect cast straight down, which projects the decal
    ; almost edge-on to the floor and lets its own projection box cut it into a
    ; rectangle.
    ;
    ; The loud wound-time splat had exactly this fault and was changed to
    ; orientation 1 first. Its twin was missed, and its twin is the one
    ; that draws: the loud one fires once a wound and has been off since, while
    ; this fires once per shard as it settles. So every square seen in play
    ; came from the record that never got the orientation fix.
    ;
    ; Fixed there, so what lands here now is the vanilla blood decal.
    If Squish && LandingSplatter
        PlayImpactEffect(Squish, "", 0.0, 0.0, -1.0, 64.0, false, false)
    EndIf
    BeginBleed()
    If ProbeVerbose
        Debug.Trace("[FleshCore] " + self + " landed at " + GetPositionZ() + "z after " \
                    + settlePolls + " poll(s)")
    EndIf
EndFunction

; ---- THE BLEED RING -------------------------------------------------------
;
; A shared, ordered list of every piece currently bleeding, held in
; StorageUtil under a single global key rather than on a quest. Nothing here
; needs a record, nothing needs the ESP rebuilt, and the list survives exactly
; as long as the session does -- which is the right lifetime: a piece from
; before a load no longer exists to be told to stop.
;
; ORDERED, because "the oldest stops" is the rule. StorageUtil's form list
; keeps insertion order, so index 0 is always the piece that has been bleeding
; longest, and it is the one with least blood left to lose anyway.

String Function BleedRing() global
    Return "FleshCore.bleeders"
EndFunction

Float Function LongestSide()
    {The longest side of the loaded bounding box, or 0 when there is no 3D to
     measure. Not a volume: a shard is a slab as often as a cube, and the
     question being asked is "is this big enough to see a pool under", which
     the longest side answers and a volume flatters.}
    If !Is3DLoaded()
        Return 0.0
    EndIf
    Float w = GetWidth()
    Float l = GetLength()
    Float h = GetHeight()
    Float m = w
    If l > m
        m = l
    EndIf
    If h > m
        m = h
    EndIf
    Return m
EndFunction

Function BeginBleed()
    {Start pooling, if this piece is big enough and there is room in the ring.}
    If !BleedAtRest || BleedDrips < 1 || bleedLeft > 0
        Return
    EndIf
    Float side = LongestSide()
    ; UNMEASURABLE MEANS BLEED, NOT MEANS SKIP.
    ;
    ; This shipped at first as a plain "smaller than the minimum, so no pool" and
    ; in play NOTHING bled. A forged chunk is a runtime NIF hung on a pool
    ; Activator whose OBND was baked from seed.nif, so GetWidth/GetLength/
    ; GetHeight have every reason to report something that is not this piece --
    ; zero being the most likely. A size test that cannot read a size must not
    ; be the thing that decides, so a piece that measures nothing bleeds, and
    ; the trace says what it measured. That is also what is wanted for
    ; Grind Down, whose scraps are deliberately below any sane minimum.
    If side > 0.0 && side < BleedMinSize
        If ProbeVerbose
            Debug.Trace("[FleshCore] " + self + " too small to bleed (" + side \
                        + " < " + BleedMinSize + ")")
        EndIf
        Return
    EndIf
    If side <= 0.0
        Debug.Trace("[FleshCore] " + self + " has no readable bounds (w/l/h gave " \
                    + GetWidth() + "/" + GetLength() + "/" + GetHeight() \
                    + ") -- bleeding anyway")
    EndIf
    ; MAKE ROOM FIRST, so the ring never holds more than the cap even for the
    ; instant between adding and trimming.
    While StorageUtil.FormListCount(None, BleedRing()) >= BleedMaxConcurrent
        ; ONE native (Shift) instead of Get(0) then RemoveAt(0) -- two
        ; pieces born in the same frame could both read the same head, and the
        ; second RemoveAt(0) would drop its neighbour unstopped. Only a drip is
        ; at stake here, but the piece ring (JoinPieceRing) had to change for
        ; the same reason, and one shape is easier to keep right than two.
        Form oldest = StorageUtil.FormListShift(None, BleedRing())
        FL_Chunk och = oldest as FL_Chunk
        If och
            och.StopBleed()
        EndIf
        ; A null or already-deleted entry is simply dropped by the Shift
        ; above; the loop condition re-tests the count, so a ring full of dead
        ; references empties rather than spinning.
    EndWhile
    StorageUtil.FormListAdd(None, BleedRing(), self, false)
    bleedLeft = BleedDrips
EndFunction

Function StopBleed()
    {Called on the oldest bleeder when a newer one needs its slot. The piece
     stays exactly where it is and keeps everything already on the floor; it
     simply stops adding to it.}
    If bleedLeft <= 0
        Return
    EndIf
    bleedLeft = 0
    Float age = Utility.GetCurrentRealTime() - born
    Float rest = Life() - age
    If rest < 0.1
        rest = 0.1
    EndIf
    Nap(rest)
EndFunction

Function LeaveBleedRing()
    {Ran dry of its own accord. Give the slot back so the next piece can have
     it rather than waiting to be evicted.}
    StorageUtil.FormListRemove(None, BleedRing(), self, true)
EndFunction

; ---- THE PIECE RING ------------------------------------------------
;
; Every live piece, oldest first, in one StorageUtil form list -- the bleed
; ring's shape, for the bleed ring's reason: no record, no ESP change. The
; co-save keeps the list: a loaded piece keeps its place (OnInit runs once per
; object, never again on a load), a piece that is gone reads back as None and
; drains in ClearPastCap's Shift loop. A load clears nothing unless the HQ's
; cap is below what the save has down; FL_Watch then trims to it.
; A piece joins at birth and leaves when its own undertaker runs. When joining
; puts the ring over the cap -- or when the HQ lowers the cap
; (TrimPieceRing) -- the OLDEST are told to go: oldest first because
; they are nearest their own deletion anyway, and because what is wanted
; is a floor that stops filling up, not a newest cut that vanishes.
String Function PieceRing() global
    Return "FleshCore.pieces"
EndFunction

Int Function MaxLive()
    Return StorageUtil.GetIntValue(None, "FC_maxpieces", MaxPieces)
EndFunction

Function JoinPieceRing()
    ; EVERY PIECE JOINS, CAPPED OR NOT. At first a piece born
    ; while the cap was 0 never joined, and once the HQ's slider came back up
    ; the ring could never clear it: it lay there its whole Life() while the
    ; DLL counted it against the cap. The ring is only a list; the cap decides
    ; what is cleared.
    StorageUtil.FormListAdd(None, PieceRing(), self, false)
    ; MAKE ROOM AFTER, not before: the newest piece is the one that just came
    ; off them and must be seen; the oldest has had its forty-five seconds.
    ClearPastCap(MaxLive(), 64)
EndFunction

Bool Function TrimPieceRing() global
    {THE HQ'S CAP, NOW. Clears the oldest toward FC_maxpieces without
     waiting for a piece to be born, at most 32 a call: it runs on FL_Watch's
     beat, and a big drop must not hold that beat up. Returns true while the
     ring is still over the cap, and FL_Watch calls again every four beats
     until it is not, so lowering the slider empties the floor to the new
     number within a few seconds. An unset or 0 cap clears nothing.}
    Int cap = StorageUtil.GetIntValue(None, "FC_maxpieces", 0)
    ClearPastCap(cap, 32)
    Return cap > 0 && StorageUtil.FormListCount(None, PieceRing()) > cap
EndFunction

Function ClearPastCap(Int cap, Int maxClears) global
    {The oldest are shifted off the ring and told to go until it holds `cap` or
     fewer; `maxClears` bounds one call. A cap of 0 or less clears nothing.}
    If cap <= 0
        Return
    EndIf
    Int guard = 0
    While StorageUtil.FormListCount(None, PieceRing()) > cap && guard < maxClears
        guard += 1
        ; ONE native, not Get(0) then RemoveAt(0). Several pieces born in the
        ; same frame run this loop at once, each on its own stack, and between
        ; two natives another joiner can take index 0 -- the second RemoveAt(0)
        ; would then drop the NEXT piece without evicting it, a cap slot lost
        ; for that piece's whole Life(). Shift reads and removes the head under
        ; PapyrusUtil's one lock (StorageUtil.FormListShift, in since 3.1), so
        ; two joiners can never hold the same `oldest`; a None head is dropped
        ; the same way, so a loaded ring still drains.
        Form oldest = StorageUtil.FormListShift(None, PieceRing())
        ; NO EXCEPTION FOR THE JOINER. At first a piece
        ; that reached the head of its own loop was shifted off the ring and NOT
        ; told to go, so it lay outside the ring for its whole Life(). It only
        ; gets there when at least `cap` newer pieces joined at once (a spell's
        ; burst at a small cap), and then it is the oldest: it goes like any
        ; other, oldest first.
        If oldest
            FL_Chunk och = oldest as FL_Chunk
            If och
                och.Evict()
            Else
                ; No longer a FleshCore piece (script gone) but still a reference:
                ; the plain undertaker, no fade.
                ObjectReference oref = oldest as ObjectReference
                If oref
                    oref.Disable(false)
                    oref.Delete()
                EndIf
            EndIf
        EndIf
        ; A None or already-deleted entry is simply dropped by the Shift above;
        ; the loop re-tests the count, so a ring of dead references drains
        ; rather than spins, and `guard` bounds it either way.
    EndWhile
EndFunction

Function LeavePieceRing()
    StorageUtil.FormListRemove(None, PieceRing(), self, true)
EndFunction

Function Evict()
    {A newer piece needs the room: the ring is over its cap. Not deleted from
     here -- that would be a latent Disable inside the newer piece's OnInit,
     which is inside PlaceAtMe on the game's thread -- but marked and woken:
     this piece's next OnUpdate is its undertaker's, on its own clock. Every
     other re-arm of the update slot goes through Nap(), so a tick that was
     running when this landed cannot overwrite the 0.05 s wake-up with its own
     longer wait (Papyrus keeps ONE single-update registration per script; the
     last writer wins).}
    If evicted
        Return
    EndIf
    evicted = true
    RegisterForSingleUpdate(0.05)
EndFunction

Function Nap(Float s)
    {Every re-arm of the single update slot. An eviction that landed while this
     tick was running must not be overwritten by the tick's own longer wait.}
    If evicted
        s = 0.05
    EndIf
    RegisterForSingleUpdate(s)
EndFunction
