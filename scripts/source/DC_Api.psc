Scriptname DC_Api Hidden
{DecalCore's public interface. Leave a mark on anything.

 ---------------------------------------------------------------------------
 WHY THERE ARE TWO WAYS TO MARK SOMETHING, AND WHICH ONE YOU WANT
 ---------------------------------------------------------------------------
 A Skyrim decal is projected into the WORLD along a cast ray and stays where
 it was put. That is right for a floor, a wall, a table or a shard
 lying still, and wrong for anything that then walks away: paint a
 target with a projected decal and they step out of it, leaving the mark
 hanging in the air where they used to be.

 So:
   Splat*()  -- surfaces. Projected, permanent-ish, follows nothing.
   Paint()   -- PEOPLE. Painted into their skin's own overlay layers, so it
                moves with them, bends with them, and survives undressing.

 Marking an actor with Splat() is not forbidden and is occasionally what you
 want -- blood on the floor *under* someone -- but it marks the ground they are
 standing on, not them.

 ---------------------------------------------------------------------------
 COST
 ---------------------------------------------------------------------------
 Every global here resolves the service quest before it can do anything, which
 is two native calls. That is nothing for a splash of blood and it is real if
 you are marking twenty shards in a loop. Callers on a hot path should hold
 the result of Core() once and call its methods directly; the globals exist so
 that callers who are not on a hot path never have to think about it.

 ---------------------------------------------------------------------------
 REQUIREMENTS
 ---------------------------------------------------------------------------
 Surfaces need nothing but DecalCore itself. PEOPLE need RaceMenu/NiOverride
 (skee) for the overlay layers -- Ready() and PaintReady() answer separately,
 so a consumer can offer what it can and skip what it cannot rather than
 failing whole.}

; ---- kinds ---------------------------------------------------------------
Int Function BLOOD() global
    Return 0
EndFunction
Int Function ALT() global
    Return 1
EndFunction

; ---- sizes ---------------------------------------------------------------
Int Function SMALL() global
    Return 0
EndFunction
Int Function MEDIUM() global
    Return 1
EndFunction
Int Function LARGE() global
    Return 2
EndFunction

; ---- areas, for Paint ----------------------------------------------------
Int Function BODY() global
    Return 0
EndFunction
Int Function HANDS() global
    Return 1
EndFunction
Int Function FEET() global
    Return 2
EndFunction
Int Function FACE() global
    Return 3
EndFunction

; ==========================================================================
DC_Core Function Core() global
    {The service. Hold this if you are going to call more than a few times.

     0x8D5 is fixed, not a lookup that can drift: DecalCore's quest is
     appended to FleshCore's plugin like every other record, so that this
     literal is stable for the life of the mod. Records are only ever appended
     and none is ever inserted -- FleshCore's own law, kept here
     because this mod's ids end up in other
     people's saves by design.}
    ; Two casts, two statements: Papyrus will not chain `as` in one expression.
    ; FOLDED INTO FLESHCORE. DC_Quest was 0x800
    ; in DecalCore.esp and is 0x8D5 in FleshCore.esp -- appended, with every
    ; link remapped and every one of DC_Core's
    ; eighteen script properties pointing inside FleshCore. This is
    ; the only place in the three DC_ scripts that names a plugin by file;
    ; everything else reaches its records through the quest's properties.
    Quest q = Game.GetFormFromFile(0x000008D5, "FleshCore.esp") as Quest
    Return q as DC_Core
EndFunction

Bool Function Ready() global
    {Can this service mark surfaces at all?}
    DC_Core c = Core()
    Return c != None && c.BloodS != None
EndFunction

Bool Function IsFemale(Actor who) global
    {Which override map their marks are filed under -- and the ONE place that
     question is answered, because getting it wrong is silent.

     THIS IS WHY SOME TARGETS COULD NOT BE MARKED AT ALL. In testing some NPCs
     could not be marked, and the Papyrus log shows
     the pattern: hit after hit on the same actor reporting
     "painted b/h/f/fa=0/0/0/0", with layer 0 reading back as RaceMenu's
     default every single time. The write was not failing loudly; it was
     landing somewhere nothing reads.

     NiOverride files a node override under a GENDER and applies it only to an
     actor of that gender. GetActorBase() on a TEMPLATED or LEVELLED NPC does
     not return the base they are actually running as -- it returns the editor
     base they were built from, whose sex can be anything. Ask it for the sex of
     a levelled bandit and it can answer male for a target whose body is female; the mark is then
     filed in the male map and skee never applies it.

     GetLeveledActorBase is SKSE's answer to exactly this, and its own header
     says so: "returns the base the actor is using if the actor is leveled.
     This differs from GetActorBase which will return the editor base." It is
     asked first and GetActorBase is only the fallback for an actor that has
     no levelled base at all.}
    If who == None
        Return false
    EndIf
    ActorBase ab = who.GetLeveledActorBase()
    If ab == None
        ab = who.GetActorBase()
    EndIf
    If ab == None
        Return false
    EndIf
    Return ab.GetSex() == 1
EndFunction

Bool Function PaintReady() global
    {Can this service mark PEOPLE? Separate from Ready() on purpose: overlays
     need RaceMenu's skee plugin and surfaces do not, so a consumer with only
     half the requirements can still use the half it has.}
    Return SKSE.GetPluginVersion("skee") >= 1
EndFunction

; ==========================================================================
; SURFACES
; ==========================================================================
Bool Function Splat(ObjectReference at, Int kind, Int size) global
    {Straight down from `at`, which is what nearly every caller means: blood
     under a body, under a shard, under a puddle. Sixty-four units of reach is
     enough to find the floor from anything standing on it.

     World-space down, not node-space -- see SplatDir. A corpse's root node is
     not upright, and a cast rotated into its frame would go sideways.}
    Return SplatDir(at, kind, size, 0.0, 0.0, -1.0, 64.0, false)
EndFunction

Bool Function SplatDir(ObjectReference at, Int kind, Int size, \
                       Float dx, Float dy, Float dz, Float dist, \
                       Bool applyNodeRotation) global
    {A mark along an arbitrary cast -- spray up a wall, across a table.

     applyNodeRotation is PlayImpactEffect's seventh argument, and its real
     name: it rotates the cast direction into the node's own frame. FALSE means
     dx/dy/dz are world-space, which is what every caller here wants and what
     every vanilla caller passes. Pass true only to aim along a bone's own axis.

     There is NO always-hit option. The seventh argument is applyNodeRotation
     and nothing else; nothing places the decal when the ray finds nothing.
     That behaviour does not exist in ObjectReference.psc, and a caller passing
     true here is asking for node rotation, not for a guaranteed mark.
     A miss means no mark. Give the ray something to land on.}
    If at == None
        Return false
    EndIf
    DC_Core c = Core()
    If c == None
        Return false
    EndIf
    ImpactDataSet s = c.SetFor(kind, size)
    If s == None
        Return false
    EndIf
    ; THE NATIVE'S OWN ANSWER, PASSED STRAIGHT THROUGH. This used to return
    ; true whenever the data set resolved, which told a caller nothing about
    ; whether a mark was actually laid -- and a caller that wants to try
    ; another direction has no other way to find out.
    Return at.PlayImpactEffect(s, "", dx, dy, dz, dist, applyNodeRotation, false)
EndFunction

Bool Function SplatToward(ObjectReference from, ObjectReference target, \
                          Int kind, Int size, Float bias, Float overshoot) global
    {A mark on a NAMED OBJECT, by aiming the ray at it.

     THIS IS THE ONLY WAY TO PUT A DECAL ON A CUP. PlayImpactEffect casts from
     the reference it is called on, in a direction, and lays its decal on the
     first thing the ray meets. Called ON the cup it starts AT the cup's own
     origin -- which for anything standing on a table is the middle of its base,
     already inside its own collision -- and the ray either reports nothing or
     comes out the far side into the table. Either way the cup is not marked.

     Called on the MARKER and aimed AT the cup, the ray crosses the gap and
     meets the cup's near face, which is a surface, facing the shot, exactly
     like a wall. Same call, same engine, right end of the ray.

     `bias` lifts the aim point above the target's origin, because that origin
     sits at the bottom of the object and a ray aimed dead at it grazes the
     table first. `overshoot` lets the ray continue a little past the aim point
     so a near-miss still lands on the far side of the object rather than
     stopping in mid air.}
    If from == None || target == None
        Return false
    EndIf
    Float dx = target.GetPositionX() - from.GetPositionX()
    Float dy = target.GetPositionY() - from.GetPositionY()
    Float dz = (target.GetPositionZ() + bias) - from.GetPositionZ()
    Float len = Math.sqrt(dx * dx + dy * dy + dz * dz)
    If len < 1.0
        ; sitting on top of it: straight down is as good an aim as any
        Return SplatDir(from, kind, size, 0.0, 0.0, -1.0, 24.0, false)
    EndIf
    Return SplatDir(from, kind, size, dx / len, dy / len, dz / len, \
                    len + overshoot, false)
EndFunction

Int Function MarkOn(Actor who) global
    {What mark is this target wearing, packed as kind * 10 + heaviest variant,
     or -1 for none.

     Asked ONCE PER WOUND rather than once per shard. Reading six overlay node
     properties is six native calls, and FL_Watch's placement loop is the exact
     window between the blow landing and the first piece appearing -- the one
     FleshCore works to keep short. Thirty calls in it to
     answer the same question five times would be a poor trade.

     Kind is taken from the heaviest layer, so a target hit with both wears
     whichever fluid was applied deepest.}
    If who == None || !PaintReady()
        Return -1
    EndIf
    DC_Core c = Core()
    If c == None
        Return -1
    EndIf
    Int best = -1
    Int bestKind = -1
    Int n = LayerCount(BODY())
    Int i = 0
    While i < n
        String cur = NiOverride.GetNodePropertyString(who, false, NodeName(BODY(), i), 9, 0)
        Int v = 0
        While v < c.SkinVariants
            If cur == c.SkinFor(0, v)
                If v > best
                    best = v
                    bestKind = 0
                EndIf
            ElseIf cur == c.SkinFor(1, v)
                If v > best
                    best = v
                    bestKind = 1
                EndIf
            EndIf
            v += 1
        EndWhile
        i += 1
    EndWhile
    If best < 0
        Return -1
    EndIf
    Return bestKind * 10 + best
EndFunction

Function SetPendingMark(Int packed) global
    {Leave the mark for the pieces of the wound about to be placed.}
    DC_Core c = Core()
    If c != None
        c.PendingMark = packed
    EndIf
EndFunction

Int Function PendingMark() global
    {What the pieces of the current wound should be wearing, or -1.}
    DC_Core c = Core()
    If c == None
        Return -1
    EndIf
    Return c.PendingMark
EndFunction

Bool Function CoatSkin(ObjectReference what, Int kind, Int level) global
    {Coat a shard in BODY-UV art, at a density matching what they were wearing.

     Six overlay variants map onto three shaders: 0-1 light, 2-3 medium,
     4-5 heavy. The fill texture is baked into an effect shader record, so
     carrying all six would be twelve records to express a difference nobody
     can see on a piece the size of a hand.}
    If what == None
        Return false
    EndIf
    DC_Core c = Core()
    If c == None
        Return false
    EndIf
    FormList l = c.SkinCoatBlood
    If kind == 1
        l = c.SkinCoatAlt
    EndIf
    If l == None || l.GetSize() < 1
        Return false
    EndIf
    Int band = level / 2
    If band < 0
        band = 0
    EndIf
    If band > l.GetSize() - 1
        band = l.GetSize() - 1
    EndIf
    EffectShader sh = l.GetAt(band) as EffectShader
    If sh == None
        Debug.Trace("[DecalCore] CoatSkin: list for kind " + kind + " has no shader at band " \
                    + band + " of " + l.GetSize())
        Return false
    EndIf
    sh.Play(what, -1.0)
    ; SAY WHAT WAS PLAYED, ON WHAT. The old log, chasing unpainted shards,
    ; only ever recorded that a MARK existed.
    ; Whether the shader was found, which record it was, and which reference it
    ; was played on are three different facts and none of them were written
    ; down. Play() returns nothing, so this cannot report success -- it reports
    ; what was asked of the engine, which is what was missing.
    Debug.Trace("[DecalCore] CoatSkin: played " + sh + " (kind " + kind + " level " \
                + level + " -> band " + band + ") on " + what \
                + "; 3D=" + what.Is3DLoaded())
    Return true
EndFunction

Bool Function Coat(ObjectReference what, Int kind) global
    {Wrap a whole object in the mark texture, permanently.

     THIS IS THE ANSWER FOR HAVOK ENTITIES. Everything else in this script casts
     a ray and lets the engine's decal system put a quad where it lands, which
     needs a surface the ray can reach from outside. A cup, a bottle, a severed
     forearm rolling across a floor -- the ray has nowhere to start.

     EffectShader.Play(ref, -1.0) has no ray. It applies the texture over the
     object's own geometry in the object's own UV, for an unlimited duration,
     and it works on any reference with 3D. The atlases are around 95%
     transparent, so what lands is marks with the object showing between them
     rather than an object painted a flat colour.

     Duration is NEGATIVE, which the engine reads as forever. It is not written
     to the co-save, so a reload still clears it -- which is the behaviour
     this service wants, and nothing here may undo it.}
    If what == None
        Return false
    EndIf
    DC_Core c = Core()
    If c == None
        Return false
    EndIf
    EffectShader sh = c.CoatBlood
    If kind == 1
        sh = c.CoatAlt
    EndIf
    If sh == None
        Return false
    EndIf
    sh.Play(what, -1.0)
    Return true
EndFunction

Function Uncoat(ObjectReference what, Int kind) global
    {Take the coat back off. The other end of Coat and CoatSkin, which until
     now had none.

     NOTHING IN THIS SERVICE EVER STOPPED ONE. Both Coat and CoatSkin play
     their shader with a duration of -1.0, which the engine reads as forever
     (the note on Coat says so and calls it deliberate), and a shader plays
     until it is stopped or its reference unloads. That is right for a shard
     that exists for forty-five seconds and wrong for a target who is put back
     on their feet: in testing, restored targets were still covered in
     alt, and there was no call in this file that could have
     removed it.

     EVERY MEMBER OF THE LIST, NOT THE ONE THAT WAS PLAYED. CoatSkin picks a
     band out of the kind's SkinCoat list by the level it was handed
     (see CoatSkin) and writes down nowhere which one it chose. Rather
     than start a per-reference record for it, all three are stopped: Stop on
     a shader that is not playing on that reference is the engine being asked
     to do nothing, and three of those cost less than the bookkeeping would.

     THE TWO LISTS ARE THE ONES DC_Core HOLDS. the two SkinCoat lists are
     the body-UV coats for shards (DC_Core.psc) and the two Coat shaders
     are the flat atlas coats for everything else (DC_Core.psc); a
     reference may be wearing either, so both come off.}
    If what == None
        Return
    EndIf
    DC_Core c = Core()
    If c == None
        Return
    EndIf
    FormList l = c.SkinCoatBlood
    EffectShader sh = c.CoatBlood
    If kind == 1
        l = c.SkinCoatAlt
        sh = c.CoatAlt
    EndIf
    If l != None
        Int n = l.GetSize()
        Int i = 0
        While i < n
            EffectShader band = l.GetAt(i) as EffectShader
            If band != None
                band.Stop(what)
            EndIf
            i += 1
        EndWhile
    EndIf
    If sh != None
        sh.Stop(what)
    EndIf
EndFunction

ObjectReference Function RandomClutter(ObjectReference near, Float radius) global
    {A cup, jug, plate, book or candle near this mark -- ANY of them, not the
     closest one.

     THIS IS WHY ONLY ONE PROP EVER TOOK A MARK. NearestClutter returns exactly
     one reference, so a cast into a laid table coated the plate and left the
     ewer, the cups, the candles and the book untouched. The candles were never
     missing from the list -- CandleHornTable01 is a STAT with a
     Clutter\Candles\ model and has been in it all along. They were simply
     never asked for, because the caller only ever asked once.

     Papyrus has no "find all references": Game.FindAllReferences* does not
     exist in SKSE, and FindClosest always answers with the same
     object. FindRandom is the one call that can return a DIFFERENT member of
     the set each time it is asked, so a caller that wants the whole table asks
     repeatedly and coats whatever comes back.}
    DC_Core c = Core()
    If c == None || c.Clutter == None
        Return None
    EndIf
    Return Game.FindRandomReferenceOfAnyTypeInListFromRef(c.Clutter, near, radius)
EndFunction

ObjectReference Function NearestClutter(ObjectReference near, Float radius) global
    {The closest cup, jug, plate, bottle, basket or barrel, or None.

     Returns None rather than failing when the list is missing, so an install
     whose plugin lacks the list degrades to marking only surfaces.}
    DC_Core c = Core()
    If c == None || c.Clutter == None
        Return None
    EndIf
    Return Game.FindClosestReferenceOfAnyTypeInListFromRef(c.Clutter, near, radius)
EndFunction

Bool Function SplatNode(ObjectReference at, String node, Int kind, Int size, Float dist) global
    {From a named node rather than the reference's origin -- a hand, a weapon
     tip, the bone a limb came off. Straight down from there.

     Worth knowing: a reference's ORIGIN is usually at its feet, so a splat
     from the origin of a standing target marks the floor. If you want the mark
     where the wound is, name the node.

     The cast is world-space down from that node, not down along the bone.}
    If at == None
        Return false
    EndIf
    DC_Core c = Core()
    If c == None
        Return false
    EndIf
    ImpactDataSet s = c.SetFor(kind, size)
    If s == None
        Return false
    EndIf
    Return at.PlayImpactEffect(s, node, 0.0, 0.0, -1.0, dist, false, false)
EndFunction

; ==========================================================================
; PEOPLE
; ==========================================================================
String Function NodeName(Int area, Int layer) global
    {RaceMenu's own naming, as its own script spells it:
     "Body [Ovl0]", "Hands [Ovl0]", "Feet [Ovl0]", "Face [Ovl0]".}
    If area == 1
        Return "Hands [Ovl" + layer + "]"
    ElseIf area == 2
        Return "Feet [Ovl" + layer + "]"
    ElseIf area == 3
        Return "Face [Ovl" + layer + "]"
    EndIf
    Return "Body [Ovl" + layer + "]"
EndFunction

Int Function LayerCount(Int area) global
    {How many overlay layers the running game actually has. It is a RaceMenu INI
     setting, not a constant, so it is asked for -- writing to
     a layer that does not exist is a silent no-op and looks exactly like a
     texture that failed to load.}
    If area == 1
        Return NiOverride.GetNumHandOverlays()
    ElseIf area == 2
        Return NiOverride.GetNumFeetOverlays()
    ElseIf area == 3
        Return NiOverride.GetNumFaceOverlays()
    EndIf
    Return NiOverride.GetNumBodyOverlays()
EndFunction

Int Function Paint(Actor who, Int kind, Int area, Float alpha) global
    {Paint a mark into their skin. Returns the layer used, or -1.

     THE LAYER CHOOSES THE ART, and that is the accumulation. Each layer gets a
     different, progressively heavier texture, so one hit is a few drips and
     six hits is six different sets of drips at once. Painting the same texture
     into every layer would have made every hit after the first invisible.

     Layers are a scarce shared resource -- tattoo mods, dirt mods and this one
     all want them -- so this takes the first EMPTY one. When they are all
     spoken for it reuses one of DecalCore's own, which is only the same fluid landing on
     them twice. Overwriting somebody else's tattoo is the last resort and it
     says so in the log.}
    If who == None || !PaintReady()
        Return -1
    EndIf
    DC_Core c = Core()
    If c == None
        Return -1
    EndIf

    ; AN NPC HAS NO OVERLAY NODES UNTIL SOMETHING ASKS FOR THEM.
    ;
    ; RaceMenu ships skee64.ini with bPlayerOnly=1, so overlays are installed
    ; on the PLAYER and on nobody else -- and its own comment names the way
    ; round it: "you can add overlays to certain actors via script". Without
    ; this every write went into a database keyed on nodes they do not have.
    If !NiOverride.HasOverlays(who)
        NiOverride.AddOverlays(who)
        ; AND THEN MAKE THE ACTOR BUILD THEM.
        ;
        ; AddOverlays enters them in skee's list. It does not create the nodes:
        ; skee installs overlay geometry while an actor's 3D is being built, so
        ; a target who is standing there fully loaded when they are first added has
        ; a registration and no nodes, and every write into those nodes goes
        ; nowhere -- silently, forever, because nothing else in normal play
        ; ever rebuilds an NPC's 3D.
        ;
        ; QueueNiNodeUpdate is what asks for that rebuild. It costs a visible
        ; flicker, which is why it is inside this branch and fires ONCE per
        ; actor per session -- on a target who already has overlays it would
        ; throw away every mark they are wearing.
        who.QueueNiNodeUpdate()
    EndIf

    ; REMEMBER THEM, so a save load can strip them. Papyrus cannot enumerate
    ; actors, and with persist = false NiOverride keeps no record either, so
    ; without a list there is nobody to ask.
    ;
    ; THIS IS ONLY HALF THE BOOKKEEPING AND THE OTHER HALF IS DELIBERATELY
    ; SOMEWHERE ELSE. Remember() names who might need CLEANING and must survive
    ; a load to do it; Record(), called beside each Wear below, says what the
    ; save should put BACK and must roll back with the load. Two questions, two
    ; containers -- the note is above WornKey().
    Remember(c, who)

    ; AND NOTE THAT THEY WERE JUST DEALT WITH, so the marker can tell whether the
    ; magic effect got to them before it decides to step in.
    ;
    ; The clock is read ONCE and kept, because the walk below needs the same
    ; instant to age the write-lag slot against and a second call to
    ; GetCurrentRealTime would be a second native call to learn a number this
    ; function already holds.
    Float now = Utility.GetCurrentRealTime()
    c.LastPainted = who
    c.LastPaintAt = now

    Bool female = IsFemale(who)
    Int n = LayerCount(area)

    ; ---- WHAT PAINT PUT ON THIS AREA LAST, AND WHEN --------------------------
    ;
    ; Four native calls, once per Paint rather than once per layer, read before
    ; the walk because the walk needs them and because reading them inside it
    ; would ask the same question up to six times for one answer. What they are
    ; for and why they exist at all is the note above LagFile().
    Int myId = who.GetFormID()
    Int lagWho = JsonUtil.GetIntValue(LagFile(), "who" + area, 0)
    Int lagLayer = JsonUtil.GetIntValue(LagFile(), "layer" + area, -1)
    String lagTex = JsonUtil.GetStringValue(LagFile(), "tex" + area, "")
    Float lagAge = now - JsonUtil.GetFloatValue(LagFile(), "at" + area, 0.0)

    ; ---- WHICH LAYER IS FREE IS ASKED OF THE NODE, NOT OF THE DATABASE ----
    ;
    ; THIS IS WHY THE ACCUMULATION NEVER WORKED. Paint after paint, on every
    ; actor in the Papyrus logs, read:
    ;
    ;     painted b/h/f/fa=0/0/0/0
    ;
    ; Always layer 0. Never 1. The first hit and the twentieth wrote the same
    ; sparsest texture into the same layer, so nothing ever built up and a
    ; heavily-shot NPC wore the faintest art in the set -- which on a dark skin
    ; is very close to wearing nothing, and from the outside it looked like some NPCs
    ; were not being marked at all.
    ;
    ; The cause was itself a fix. Wear() was changed to persist = FALSE so
    ; marks would not survive a reload, and NiOverride's header says what that
    ; means:
    ;
    ; the change applies visually until the armour is re-equipped or the game
    ; is reloaded, the same as SetPropertyX.
    ;
    ; SetPropertyX sets the property ON THE NODE and records no override.
    ; So HasNodeOverride -- which asks the stored-override database -- answered
    ; false for a layer that was visibly wearing a DecalCore texture, every time, and
    ; the walk below stopped at the first layer on every cast.
    ;
    ; GetNodePropertyString reads the live node instead ("Handy if you need the
    ; current value if an override D.N.E yet", says the same header), which is
    ; precisely the case here. Note its second argument is firstPerson,
    ; NOT isFemale -- a different signature from the override calls above it,
    ; and false is right for an NPC.
    ;
    ; AND THE TEST IS "IS IT ALREADY A DECALCORE TEXTURE", NOT "IS IT EMPTY".
    ;
    ; What an untouched overlay layer reports is not documented and cannot be
    ; measured from here: RaceMenu builds those nodes by copying the body
    ; shape, so slot 0 may come back as "" or may come back as their skin
    ; texture. Testing for "" would work in the first world and fail silently
    ; in the second -- every layer would look occupied, the walk would fall
    ; through to the last-resort branch, and Paint would be back to painting one
    ; fixed layer for ever, which is the bug being fixed.
    ;
    ; "Not a DecalCore texture" is true in BOTH worlds. It is also the question that
    ; actually matters: the layer is usable unless this mark is already there.
    ; The cost is that another mod's overlay on a low layer gets taken before
    ; an empty high one -- acceptable here, because skee64.ini ships
    ; bPlayerOnly=1, so by default nothing else writes NPC overlays, and
    ; these actors had no overlay nodes at all until Paint asked for them.
    Int lowIdx = -1
    Int lowVar = 99
    Int i = 0
    String first = ""
    While i < n
        String node = NodeName(area, i)
        ; Key 9 is ShaderTexture and its index is the texture SLOT, 0 being
        ; diffuse, per NiOverride's own header.
        String cur = NiOverride.GetNodePropertyString(who, false, node, 9, 0)
        If i == 0
            first = cur
        EndIf
        ; `first` is taken BEFORE the slot is consulted, on purpose: the trace
        ; below reports what the NODE says layer 0 holds, and that has to stay
        ; the node's own answer even when the slot knows better.
        ;
        ; ---- AND WHAT THE NODE SAYS IS NOT ALWAYS WHAT IT HOLDS ------------
        ;
        ; This is the one place the write-lag slot is used, and it is used for
        ; two opposite purposes depending only on how old it is.
        ;
        ; YOUNG -- Paint picks a layer by reading the node back, and a
        ; write from the same frame has not landed yet -- so two hits close
        ; together can both claim the same layer and one paint is wasted. That
        ; is this exact read, and it is the read the WRITE DID NOT
        ; TAKE lines were complaining about from the other side. If Paint wrote
        ; this layer within the last LagWindow seconds then the node's answer is
        ; the pre-write one and the slot's is the true one, so it is used instead and
        ; the walk moves on to the next layer rather than claiming this one
        ; twice.
        ;
        ; OLD -- the write has had its chance and the node is authoritative. A
        ; disagreement now is the failure the old log could never show:
        ; not "which layer was chosen" but "the layer was chosen, written, and
        ; is still not wearing it". It costs nothing to ask -- `cur` was already
        ; read for the walk itself -- and it only speaks when it has bad news.
        ;
        ; Both branches are floored at zero age as well as ceilinged. A slot
        ; whose timestamp came off disk from a previous run of the game was
        ; stamped by a real-time clock that has since restarted, so it reads as
        ; being in the FUTURE; without the floor that would look fresher than
        ; fresh and be believed.
        If lagWho == myId && lagLayer == i
            If lagAge >= 0.0 && lagAge < LagWindow()
                cur = lagTex
            ElseIf lagAge >= LagWindow() && lagAge < LagStale() && cur != lagTex
                Debug.Trace("[DecalCore] WRITE DID NOT TAKE on " + who + " node '" \
                            + node + "' (female=" + female + "): asked for '" \
                            + lagTex + "' " + lagAge + "s ago, node still holds '" \
                            + cur + "'")
            EndIf
        EndIf
        Int v = VariantOf(c, cur)
        ; ---- "NOT DECALCORE'S" IS NOT THE SAME AS "FREE" -------------------------
        ;
        ; THIS ATE THE TATTOOS. VariantOf returns -1 for anything that is
        ; not one of this service's own textures -- and an empty layer and
        ; another mod's tattoo are both "not DecalCore's". So the walk claimed the
        ; first layer that was not already blood, which on a tattooed character
        ; is layer 0, and painted over the tattoo; the next cast took the next
        ; one. The docstring above promises "the first EMPTY one",
        ; and only an emptiness test keeps that promise.
        ;
        ; An empty layer holds a KNOWN string -- DefaultOverlay(), measured
        ; in the traces -- so emptiness is now
        ; asked directly: a negative from VariantOf is not enough. A layer that has
        ; never been written at all reads as "", and that counts too.
        ;
        ; A layer belonging to somebody else is skipped and left exactly as it
        ; is. It is not a promotion candidate either: lowVar below may only ever
        ; name a layer this service already owns, so a crowded character loses
        ; their oldest BLOOD rather than their tattoo.
        Bool isFree = (cur == "" || cur == DefaultOverlay())
        If isFree
            Debug.Trace("[DecalCore] area " + area + " layer " + i + " free (was '" \
                        + cur + "')")
            String freeArt = c.SkinFor(kind, i)
            NoteWrite(area, myId, i, freeArt, now)
            Record(who, area, i, freeArt, alpha)
            Return Wear(who, female, node, freeArt, alpha, i)
        EndIf
        If v < 0
            Debug.Trace("[DecalCore] area " + area + " layer " + i \
                        + " belongs to another mod ('" + cur + "') -- left alone")
            i += 1
        Else
        If v < lowVar
            lowVar = v
            lowIdx = i
        EndIf
        i += 1
        EndIf
    EndWhile
    Debug.Trace("[DecalCore] area " + area + ": all " + n + " layer(s) already ours," \
                + " sparsest is layer " + lowIdx + " at variant " + lowVar \
                + " (layer 0 holds '" + first + "')")

    ; ---- EVERY LAYER IS FULL, AND THE HIT STILL HAS TO SHOW ----------------
    ;
    ; This branch used to re-write the FIRST of its own layers with
    ; SkinFor(kind, mine) -- which is the texture that layer was already
    ; wearing. It returned a layer number, so the caller and the log both said
    ; the paint had worked, and NOTHING CHANGED ON SCREEN. The design is a
    ; mark that keeps building the more you strike; past the sixth strike it
    ; silently stopped, and reported success while doing it.
    ;
    ; So instead: find the layer wearing the SPARSEST of DecalCore's textures and
    ; promote it. The replacement is always at least two variants denser, so
    ; the hit is visible; the sparsest layer is chosen so total coverage can
    ; only go up. Repeated hits walk every layer up to the heaviest art there
    ; is, and only when all of them are already there does this give up --
    ; and then it says so, instead of pretending.
    If lowIdx >= 0
        Int top = c.SkinVariants - 1
        If lowVar >= top
            Debug.Trace("[DecalCore] area " + area + ": all " + n + " layer(s) already" \
                        + " wearing the heaviest art -- nothing left to add")
            Return -1
        EndIf
        Int nextV = lowVar + 2
        If nextV > top
            nextV = top
        EndIf
        String denserArt = c.SkinFor(kind, nextV)
        NoteWrite(area, myId, lowIdx, denserArt, now)
        Record(who, area, lowIdx, denserArt, alpha)
        Return Wear(who, female, NodeName(area, lowIdx), denserArt, alpha, lowIdx)
    EndIf
    If n > 0
        Debug.Trace("[DecalCore] area " + area + ": all " + n + " layer(s) belong to" \
                    + " something else -- taking the last one")
        String lastArt = c.SkinFor(kind, n - 1)
        NoteWrite(area, myId, n - 1, lastArt, now)
        Record(who, area, n - 1, lastArt, alpha)
        Return Wear(who, female, NodeName(area, n - 1), lastArt, alpha, n - 1)
    EndIf
    Debug.Trace("[DecalCore] area " + area + " reports ZERO overlay layers -- check" \
                + " skee64.ini [Overlays/...] iNumOverlays")
    Return -1
EndFunction

Int Function VariantOf(DC_Core c, String tex) global
    {Which of DecalCore's overlay variants is this layer wearing, or -1 for none.

     Asked against every variant of BOTH kinds, because a layer holding blood
     and a layer holding alt are equally DecalCore's and equally in the way. The
     number is what lets Paint promote the sparsest layer rather than rewrite
     an arbitrary one with what it already had.}
    If tex == ""
        Return -1
    EndIf
    Int v = 0
    While v < c.SkinVariants
        If tex == c.SkinFor(0, v) || tex == c.SkinFor(1, v)
            Return v
        EndIf
        v += 1
    EndWhile
    Return -1
EndFunction

Bool Function RecentlyPainted(Actor who, Float within) global
    {Did the magic effect already paint this target moments ago?

     The marker uses this before painting a LIVING actor, so a shot that DID
     reach them is not painted twice and does not advance their accumulation by
     two layers at once.}
    If who == None
        Return false
    EndIf
    DC_Core c = Core()
    If c == None || c.LastPainted != who as Form
        Return false
    EndIf
    Return (Utility.GetCurrentRealTime() - c.LastPaintAt) < within
EndFunction

Bool Function IsOurs(DC_Core c, String tex) global
    {Is this layer wearing one of DecalCore's textures? Kept as the plain question for
     consumers; Paint itself needs the variant number and asks VariantOf.}
    Return VariantOf(c, tex) >= 0
EndFunction

Int Function Wear(Actor who, Bool female, String node, String tex, Float alpha, Int layer) global
    {Put one texture on one layer. Split out so every route into it -- empty
     layer, one of DecalCore's, last resort -- writes exactly the same pair.}
    ; PERSIST IS FALSE, AND THAT IS DELIBERATE.
    ;
    ; The last argument decides whether NiOverride writes the override into the
    ; SKSE CO-SAVE. It was true, and so a mark outlived the save it was made
    ; in: reloading the starting save, without closing the
    ; game, left every marked target still marked. A decal is
    ; something that HAPPENED, not something they are; it has no business
    ; surviving the undoing of the thing that happened.
    ;
    ; False means it is applied to the 3D they are wearing now and written
    ; nowhere. It goes when they unload, and a reload cannot bring it back
    ; because there is nothing to bring back.
    NiOverride.AddNodeOverrideString(who, female, node, 9, 0, tex, false)
    ; Key 8 is ShaderAlpha and takes index -1, which is NiOverride's "no
    ; controller involved". An overlay left at its default alpha is invisible,
    ; so this is not optional.
    NiOverride.AddNodeOverrideFloat(who, female, node, 8, -1, alpha, false)
    ; ---- AND WHETHER IT TOOK IS ASKED LATER, NOT HERE --------------------
    ;
    ; A READ-BACK HERE WOULD BE right about the question
    ; and wrong about the moment. Re-reading the node the instant after writing
    ; it reports WRITE DID NOT TAKE on writes that do land: the node has not
    ; caught up yet. The
    ; measurement and the proof are set out above LagFile().
    ;
    ; THE CHECK IS KEPT, BECAUSE THE REASON FOR IT STANDS.
    ; Which layer was CHOSEN and whether the write LANDED
    ; are different facts, and only the second shows an actor who cannot be marked.
    ; On such an actor they disagree on
    ; every hit: layer 0 chosen, layer 0 still holding RaceMenu's default a
    ; second later, forever.

    ;
    ; IT IS DEFERRED. Paint files what was asked for in the write-lag slot for
    ; the area, and the next walk of that area on that actor compares the slot
    ; against the node -- once the write has had its chance, and inside a read
    ; Paint was making anyway. A working actor now costs ONE integer comparison
    ; and no native call at all, where this line cost a native call on every
    ; single write.
    ;
    ; THE SLOT IS FILLED BY PAINT AND NOT BY WEAR, because the slots are per
    ; AREA and Wear is not told the area -- it is handed a node name, and
    ; picking "Body" back out of "Body [Ovl3]" to recover something the caller
    ; already knew would be a parser where a parameter would do. The cost of
    ; that choice: a consumer that calls Wear directly rather
    ; than through Paint writes a texture that nothing later checks.
    ;
    ; AND WHAT THE DEFERRAL TRADES AWAY: a paint that is never followed by
    ; another paint of the same area on the same actor is never checked at all.
    ; The failure this exists to catch is repeated by its nature -- an actor who
    ; cannot be marked gets shot again, which is how they came to be noticed --
    ; so what is given up is the case that would have been announced once and
    ; then never reproduced, and what is bought is that the announcement means
    ; something when it comes.
    Return layer
EndFunction

; ==========================================================================
; WHAT PAINT JUST WROTE, BECAUSE THE NODE WILL NOT SAY SO YET
; ==========================================================================
;
; A READ-BACK IS RIGHT ABOUT THE QUESTION AND WRONG ABOUT THE MOMENT.
; Re-reading the texture the instant after writing it, as Wear once did, sees
; the old value in exactly two shapes:
;
;     asked 'DecalCore\alt_skin0.dds', node still holds
;         'textures\actors\character\overlays\default.dds'  -- nothing there yet
;     asked 'DecalCore\alt_skin4.dds', node still holds
;         'DecalCore\alt_skin2.dds'                         -- an EARLIER variant
;
; Neither is a failed write, and the proof is Paint's own
; layer walk. Paint chooses a layer by reading the node, so a write that never
; landed would leave its layer looking free and the very next hit would claim it
; again. Instead each actor's body layers rise strictly, one per hit.
;
; The writes land; a read taken in the same call does not see them.



;


;
; WHERE THE DELAY LIVES IS NOT DOCUMENTED.
; NiOverride's header says persist = false is "Equivalent to SetPropertyX"
; (nioverride.psc) and says nothing anywhere about when the property reaches
; the node; GetNodePropertyString is documented only as "Gets the property
; straight from the node". Whether the lag is
; a deferred task, a frame of render state or something else
; is unknown. What IS measured is the
; shape of it: a read in the same call misses the write, a read on the next hit
; -- seconds later -- sees it.
;
; SO THE FACT IS WRITTEN DOWN INSTEAD OF ASKED FOR. One slot per AREA records
; the actor, the layer, the texture and the instant of the last thing Paint had
; Wear put there. Paint reads it and uses it for two opposite purposes, chosen
; purely by its age:
;
;   younger than LagWindow()  the node cannot be trusted yet, so the slot is
;                             believed instead. This is the wasted-paint fix.
;   older than LagWindow()    the write has had every chance, so the node is
;   and younger than          the truth and the slot is what it ought to say.
;   LagStale()                A disagreement here is a genuine failure, and it
;                             is the only thing that now trips WRITE DID NOT
;                             TAKE.
;
; ONE SLOT PER AREA, AND NOT ONE SLOT. A single "last write" slot does not cover
; the case seen in testing, and the shipping caller is why: FL_Decal paints body,
; hands, feet and face back to back (see FL_Decal.psc). By the time a second
; hit walks the BODY layers, a one-deep memory would be holding FACE, and the
; body race -- the one seen in testing -- would be exactly as it was.
; Four slots match the shape of the caller.
;
; AND ONE SLOT PER AREA, NOT ONE PER ACTOR PER AREA. Each slot names the actor
; it belongs to and is ignored for anybody else, so what this does NOT cover is
; two different targets painted inside the same second on the same area, where the
; second target's write evicts the first target's slot and the first target's race
; is unguarded again. That case did not occur in testing or in the
; measured run, and a map keyed per actor would grow for the whole session
; to cover it.
;
; JsonUtil BECAUSE THIS IS A MAP AND PAPYRUS HAS NONE. It is the same
; PapyrusUtil this script already hard-depends on and already calls on this very
; path -- Remember() asks IntListHas on every single paint. Nothing here ever
; calls Save(): these are scratch, not a record, and the file that IS a record
; is deliberately somewhere else. PapyrusUtil will still flush this file when
; the player saves ("any modified file will be automatically saved",
; JsonUtil.psc) and that is harmless, because every reader is guarded at BOTH
; ends of the age: a slot that came off disk from a previous run of the game
; carries a real-time stamp from a clock that has since restarted at zero, so it
; reads as being in the future, and a negative age is believed by neither
; branch.
String Function LagFile() global
    {The scratch file the write-lag slots live in.

     NOT MarkFile(). That file's whole purpose is to survive a load and it is
     Save()d on purpose for that; these slots are the opposite of a record and
     have no business in it.}
    Return "DecalCore/writelag"
EndFunction

Float Function LagWindow() global
    {How long after a write the node may still be answering with the old value.

     THIS ONE IS AN ESTIMATE. The test log bounds it from both
     sides and no tighter than this: a read in the same call misses the write,
     a read on the next hit sees it. One second is chosen
     because it is far longer than any per-frame deferral can be and still well
     inside "two hits close together", which is the case being covered; and
     because FL_DecalMark already calls 1.5 s "moments ago" when it asks whether
     the magic effect beat it to an actor (see FL_DecalMark.psc), so this sits
     under that rather than disagreeing with it.

     Erring long is the safe direction. Believing the slot for too long can only
     send a hit to the NEXT layer, which is a layer number and no worse; erring
     short puts the wasted paint straight back.}
    Return 1.0
EndFunction

Float Function LagStale() global
    {How long a slot is still worth checking against the node.

     A mismatch a second after the write is the original bug: layer 0
     chosen, layer 0 still holding RaceMenu's default a second later, forever. A
     mismatch a minute after the write is something else having changed that
     layer since -- Strip puts every DecalCore layer back to DefaultOverlay() after
     a load, Wipe hands one back whenever a consumer asks, and a persist = false
     property lives on 3D the engine may rebuild without telling anybody.
     Blaming the write for those would be a false report,
     so the check gives up at eight seconds.}
    Return 8.0
EndFunction

Function NoteWrite(Int area, Int id, Int layer, String tex, Float when) global
    {File what Wear was just asked to put on a layer, for the next walk of this
     area to read.

     FORMIDS, NOT FORMS, for the reason this file already gives about the marked
     list: JsonUtil serialises a Form as plugin + id and has to resolve it back
     through the load order, and what is being filed here is frequently one of
     the FF-prefixed references the engine made at runtime.

     Four sets and no Save(). The comparison Paint makes is `slot actor == this
     actor AND slot layer == this layer`, so the actor and the layer are what
     identify the slot and the texture and the stamp are what it says.}
    JsonUtil.SetIntValue(LagFile(), "who" + area, id)
    JsonUtil.SetIntValue(LagFile(), "layer" + area, layer)
    JsonUtil.SetStringValue(LagFile(), "tex" + area, tex)
    JsonUtil.SetFloatValue(LagFile(), "at" + area, when)
EndFunction

Bool Function Fade(Actor who, Int area, Int layer, Float alpha) global
    {Change how strong an existing mark is. Fade it toward 0 over time and a
     wound dries; there is no need to remove and repaint it to do that.}
    If who == None || !PaintReady() || layer < 0
        Return false
    EndIf
    Bool female = IsFemale(who)
    NiOverride.AddNodeOverrideFloat(who, female, NodeName(area, layer), 8, -1, alpha, true)
    ; AND THE RECORD IS TOLD, or a load would put the mark back at the strength
    ; it was painted at rather than the strength it had faded to. Only if there
    ; is already a slot for this layer: fading something this service did not
    ; paint is a caller's business and not a mark to start recording.
    RecordAlpha(who, area, layer, alpha)
    Return true
EndFunction

Bool Function Wipe(Actor who, Int area, Int layer) global
    {Remove one mark and hand the layer back.

     Both overrides go: leaving the texture behind at alpha 0 would look clean
     and would still hold the layer against every other mod that wants one.}
    If who == None || !PaintReady() || layer < 0
        Return false
    EndIf
    Bool female = IsFemale(who)
    String node = NodeName(area, layer)
    NiOverride.RemoveNodeOverride(who, female, node, 9, 0)
    NiOverride.RemoveNodeOverride(who, female, node, 8, -1)
    ; AND THE SAVE-SCOPED RECORD LOSES THE SLOT WITH IT. A consumer that hands a
    ; layer back has said the mark is over; leaving the slot in the record would
    ; have the next load paint it on again, which is the same class of bug as
    ; the one this whole section exists to fix, only pointing the other way.
    Unrecord(who, area, layer)
    Return true
EndFunction

Int Function WipeArea(Actor who, Int area) global
    {Remove every DecalCore mark from an area. Returns how many were cleared.

     It only touches layers whose texture is one this service put there, which
     is why it reads before it removes: another mod's tattoo is not DecalCore's to
     wipe, and clearing the whole area was the easy way to make that mistake.}
    If who == None || !PaintReady()
        Return 0
    EndIf
    DC_Core c = Core()
    If c == None
        Return 0
    EndIf
    Bool female = IsFemale(who)
    Int n = LayerCount(area)
    Int cleared = 0
    Int i = 0
    While i < n
        String node = NodeName(area, i)
        ; THE LIVE NODE, NOT THE STORED OVERRIDE -- AND THIS FUNCTION HAS
        ; NEVER CLEARED ANYTHING BECAUSE OF IT.
        ;
        ; It read GetNodeOverrideString, which is documented as "the stored
        ; override, returns default (nil) values if the override D.N.E"
        ; (nioverride.psc). Wear writes with persist = false, which the
        ; same header calls "apply the change visually ... (Equivalent to
        ; SetPropertyX)" -- so there IS no stored override
        ; for anything this service painted. `cur` came back empty, IsOurs
        ; answers false on an empty string (see VariantOf),
        ; and WipeArea walked every layer, matched nothing and returned zero.
        ; WipeAll is four of those, so it cleared nothing either.
        ;
        ; GetNodePropertyString "gets the property straight from the node"
        ; (nioverride.psc) and is what Paint, Strip and
        ; RestoreOne all read for this reason. SAME PROPERTY:
        ; key 9 is ShaderTexture and index 0 is the diffuse slot in both calls
        ; -- the key table at the top of nioverride.psc is shared by the
        ; override and the property halves of that file. What changes with the
        ; call is the second argument, which is firstPerson here and isFemale
        ; there; false is right for a body, as Paint's own note says.
        ;
        ; LIMIT: THE READ IS RIGHT, THE REMOVAL MAY NOT BE. The two removals
        ; below are RemoveNodeOverride, which takes away a STORED override --
        ; and by the paragraph above there is no stored override to take. So
        ; this correctly identifies DecalCore's layers and may still not clear
        ; them from the 3D they are wearing. Strip does clear them, by
        ; WRITING the default texture and alpha 0 with persist = false, which
        ; is the same road Wear came in on; ClearMarks and the revive path use
        ; Strip for that reason and do not come through here. Whether
        ; RemoveNodeOverride also reaches the live node is not answerable from
        ; nioverride.psc, whose only word on it is "Removes one particular
        ; override from an actor, of a particular gender, nodeName, key, and
        ; index" -- so the answer is unknown, and this is
        ; left as the caller's one remaining surprise.

        String cur = NiOverride.GetNodePropertyString(who, false, node, 9, 0)
        If IsOurs(c, cur)
            NiOverride.RemoveNodeOverride(who, female, node, 9, 0)
            NiOverride.RemoveNodeOverride(who, female, node, 8, -1)
            ; Same reason as Wipe: the record has to lose what the actor lost.
            Unrecord(who, area, i)
            cleared += 1
        EndIf
        i += 1
    EndWhile
    Return cleared
EndFunction

Int Function WipeAll(Actor who) global
    {Every DecalCore mark, everywhere on them. Returns how many were cleared.}
    Return WipeArea(who, 0) + WipeArea(who, 1) + WipeArea(who, 2) + WipeArea(who, 3)
EndFunction

; ==========================================================================
; ONE-SHOT CLEANUP, FOR A SAVE THAT ALREADY HAS MARKS BAKED INTO IT
; ==========================================================================
Function PurgeAllNodeOverrides() global
    {A LAST RESORT, AND IT CLEARS MORE THAN DECALCORE'S OWN.

     DecalCore at first wrote its overlay overrides with persist = true,
     which put them in the SKSE co-save; now it does not. That fixes
     every mark made from now on and does nothing at all for the ones already
     written into a save that exists.

     NiOverride.RemoveAllNodeOverrides is the only global undo there is, and it
     removes EVERY node override on EVERY actor -- tattoos, warpaint, scars,
     anything any mod put there. It is never called automatically and nothing
     in this mod calls it. It is here so that an old save that still has marks on
     people has an answer, to be run once, deliberately, from the console:

         cgf "DC_Api.PurgeAllNodeOverrides"

     Skin overrides and overlay INSTALLATION are untouched; only node overrides
     go.}
    Debug.Trace("[DecalCore] PurgeAllNodeOverrides: clearing EVERY node override" \
                + " from every actor -- deliberate, global, and not undoable")
    NiOverride.RemoveAllNodeOverrides()
EndFunction


; ==========================================================================
; WHO MIGHT BE DIRTY -- THE STRIP LIST, WHICH MUST *NOT* ROLL BACK
; ==========================================================================
;
; WHY THE LIST IS NOT IN THE SAVE, AND WHY THE SAVE STILL DECIDES.
; Two jobs pull opposite ways here. The strip has to reach every actor who
; may still carry live marks; the restore has to put back what the save
; was made with. One container cannot do both.
;
; A FormList is in the save, so a load rolls it back to a moment
; before they were painted, and the one actor the strip exists to clean is the one
; actor the list no longer contains. That is why the strip list is a file. It
; does not make rolling back the wrong behaviour everywhere, because a load's
; job is not always to CLEAN: sometimes it has to put marks back.
; Field report:
;
;      decals and voxels were cleared on every load, whether or not they
;      were there when the save was made. Loading a save, marking and
;      damaging a target, then loading the same save again should show
;      them clean. Marking and damaging them, saving, and loading that new
;      save should show them still marked and damaged.


;
; THE RULE, THEN: AFTER A LOAD, WHAT THEY ARE WEARING MUST EQUAL WHAT THE SAVE WAS
; MADE WITH. Two cases fall out of that one sentence and they pull opposite ways:
;
;   A  load save 1, paint them, load save 1 again    ->  they must end CLEAN
;   B  load save 1, paint them, save 2, load save 2  ->  they must end PAINTED
;
; Neither container can do both, so there are two, and each is asked only the
; question it is actually good at:
;
;   THIS SECTION -- the strip list. WHO MIGHT HAVE LIVE MARKS ON THEIR 3D, a
;   superset that grows all session and must SURVIVE a load, because the marks
;   themselves survive it. NiOverride writes with persist = false, which its own
;   header defines as applying the change visually until the armour is re-equipped
;   or the game is reloaded, like SetPropertyX (nioverride.psc) --
;   and a same-session load does not necessarily rebuild 3D that is already
;   resident, so the marks stay on screen while every scrap of in-save
;   bookkeeping rolls back underneath them. A list that rolled back would name
;   nobody and clean nobody.

;
;   THE NEXT SECTION -- the restore record. WHAT THE SAVE SAYS EACH ACTOR IS
;   WEARING, which must roll back WITH the save, because rolling back is
;   what makes case A and case B differ.
;
; On load: strip everything live using this list, then re-apply from that
; record. Case A's record is empty or older, so they end clean; case B's record
; holds their marks, so they go back on.
;
; Script state does roll back with a load. FleshCore's watcher shows it:
; after a load it can announce a new engine session and restart its wound
; sequence at 1 while the session file stays untouched. Nothing restarted:
; its lastStamp had
; rolled back to a value from the save and disagreed with a file that had not
; changed.
;
; So THIS list lives in a file, through JsonUtil, whose own header says what
; happens on a load: "the loaded data will be discarded and revert back to
; whatever the contents of the current saved file are" (JsonUtil.psc). The
; DISK is not rolled back, so a Save() after each new name is what makes the
; entry survive the thing it exists to survive.
;
; FORMIDS, NOT FORMS. JsonUtil serialises a Form as plugin+id and has to
; resolve it back through the load order; Game.GetFormEx takes the raw
; thirty-two bits and answers for anything, including the FF-prefixed
; references the engine makes at runtime. The id is signed because Papyrus's
; Int is signed, which is the same reason FleshCore's wound files are.
String Function MarkFile() global
    Return "DecalCore/marked"
EndFunction

String Function MarkKey() global
    Return "actors"
EndFunction

Function Remember(DC_Core c, Actor who) global
    {Note that this target is wearing a DecalCore mark.}
    If who == None
        Return
    EndIf
    ; The ESP's own list is kept up to date as well. It is not what the strip
    ; reads -- see above -- but it costs one native call and it is the only
    ; record of this that a human reading the save can see.
    If c != None && c.Marked != None && !c.Marked.HasForm(who)
        c.Marked.AddForm(who)
    EndIf
    Int id = who.GetFormID()
    If JsonUtil.IntListHas(MarkFile(), MarkKey(), id)
        Return
    EndIf
    JsonUtil.IntListAdd(MarkFile(), MarkKey(), id, false)
    ; SAVED HERE AND NOWHERE ELSE. Once per newly-marked actor, not once per
    ; paint: the second and later hits on the same target find them already in
    ; the list and never touch the disk.
    JsonUtil.Save(MarkFile())
EndFunction

Int Function Strip(Actor a) global
    {Put every layer of every area back to the default. Returns how many were
     actually DecalCore's -- somebody else's overlay is left alone.

     BOTH HALVES OF WHAT WEAR WROTE ARE UNDONE. Wear sets key 9 index 0 (the
     texture) and key 8 index -1 (ShaderAlpha), and its own note says an overlay
     left at its default alpha is invisible -- so the alpha is not decoration,
     it is what makes the layer show at all. Putting the texture back without
     the alpha would leave a layer turned on and pointed at RaceMenu's blank,
     which is invisible only for as long as that blank stays blank.}
    If a == None || !PaintReady()
        Return 0
    EndIf
    DC_Core c = Core()
    If c == None
        Return 0
    EndIf
    Bool female = IsFemale(a)
    Int done = 0
    Int area = 0
    While area < 4
        Int layers = LayerCount(area)
        Int L = 0
        While L < layers
            String node = NodeName(area, L)
            ; Read the LIVE node, for the same reason Paint does: with
            ; persist = false there is no stored override to ask about.
            String cur = NiOverride.GetNodePropertyString(a, false, node, 9, 0)
            If VariantOf(c, cur) >= 0
                NiOverride.AddNodeOverrideString(a, female, node, 9, 0, DefaultOverlay(), false)
                NiOverride.AddNodeOverrideFloat(a, female, node, 8, -1, 0.0, false)
                done += 1
            EndIf
            L += 1
        EndWhile
        area += 1
    EndWhile
    Return done
EndFunction

Function ClearMarks(Actor a) global
    {Every DecalCore mark off this target, AND the save's record of them, so that
     nothing puts them back.

     TWO CONTAINERS, AND CLEARING ONE IS NOT CLEARING THEM. Strip() puts every
     DecalCore layer back to RaceMenu's default on the 3D they are wearing now.
     The record kept beside it -- their slot list, and their place on the worn list
     -- is a separate thing with a separate job: the note above WornKey has
     it, and RestoreAll is what acts on it. Strip alone leaves the record
     saying they wear six layers of alt, and the next load walks that record
     and paints all six back on.

     WHICH IS THE OTHER HALF OF THE RESTORE BUG. FL_Watch calls this on
     a target the engine has just put back together; a restore that survived
     the reload would be the same bug one save later.

     THE SLOTS ARE DROPPED THROUGH Unrecord AND NOT BY CLEARING THE LIST,
     because Unrecord is what also unsets the texture and the alpha the slot
     names, and what takes them off the worn list once they have no slots left
     -- and it is the worn list BeginRestore snapshots.
     Left on it they would be walked by every load for the rest of the save,
     finding nothing to do.

     BACKWARDS, because Unrecord removes the slot it is given and everything
     after it shifts down one; walking down means only entries already dealt
     with ever move.

     AND MigrateSlots FIRST, for RestoreOne's reason: a base-ten
     slot from an older save unpacks to a negative area under the base-hundred
     arithmetic, Unrecord would be handed a slot number that is in nobody's
     list, and the record RestoreOne migrates and reads would survive this
     untouched. It is idempotent and costs one list count.}
    If a == None
        Return
    EndIf
    ; Strip self-gates on PaintReady and on the service; the record below does
    ; not need either, and a save whose skee is missing still has a record.
    Strip(a)
    MigrateSlots(a)
    Int i = StorageUtil.IntListCount(a, SlotsKey()) - 1
    While i >= 0
        Int slot = StorageUtil.IntListGet(a, SlotsKey(), i)
        Unrecord(a, slot / 100 - 1, slot % 100)
        i -= 1
    EndWhile
EndFunction

String Function DefaultOverlay() global
    {What an untouched RaceMenu overlay layer holds.

     MEASURED. A trace printed what each layer
     was holding at the moment it was claimed, and the Papyrus log
     answered the same way every time, on every area of every
     actor: 'textures\actors\character\overlays\default.dds'. An empty
     string is what an empty layer looks like from the outside and is not what
     it holds.}
    Return "textures\\actors\\character\\overlays\\default.dds"
EndFunction

Int Function MarkedCount() global
    {How many remembered actors are still waiting to be stripped.}
    Return JsonUtil.IntListCount(MarkFile(), MarkKey())
EndFunction

Int Function StripAll() global
    {ONE PASS over the remembered actors. Strips everyone whose 3D is up right
     now and drops them from the list; leaves the rest for the next pass.
     Returns how many layers this pass wiped.

     WHY A PASS AND NOT A SWEEP. The load stamp is written on PostLoadGame, and
     PostLoadGame is not a promise that anyone's 3D has arrived. The test log
     shows it both ways: on one load targets were pre-warmed BEFORE
     PostLoadGame, and on a later load nobody had been touched by the time it
     fired. A single pass at a fixed moment would have cleared the list on the
     second of those and stripped nobody -- and reported success.

     So the caller runs this repeatedly for a few seconds and each actor leaves
     the list the moment they have actually been dealt with. An actor whose 3D
     never arrives in that window does not need dealing with: their marks were
     written with persist = false into 3D that is now gone, and the 3D they
     come back with is clean.

     THE LIST IS NOT SAVED HERE. JsonUtil writes to disk on Save() and on the
     player saving, and this runs up to fifty times after every load. The
     in-memory list is what the passes walk; ForgetMarks writes the pruned one
     out once, at the end.

     AND IT STILL STRIPS UNCONDITIONALLY, WHICH IS STILL RIGHT. Everything this
     touches is a live persist = false write on 3D from a timeline the load has
     undone, so all of it has to go regardless of what the save says. Putting
     back the part the save DOES say is RestoreAll's job, and it runs after this
     in the same pass -- never before it, or this would erase it again.}
    Int n = JsonUtil.IntListCount(MarkFile(), MarkKey())
    Int wiped = 0
    Int i = n - 1
    ; BACKWARDS, because entries are removed as they are dealt with and
    ; removing from under a forward index skips the next one.
    While i >= 0
        Int id = JsonUtil.IntListGet(MarkFile(), MarkKey(), i)
        Actor a = Game.GetFormEx(id) as Actor
        If a != None && a.Is3DLoaded()
            wiped += Strip(a)
            JsonUtil.IntListRemoveAt(MarkFile(), MarkKey(), i)
        EndIf
        i -= 1
    EndWhile
    Return wiped
EndFunction

Function ForgetMarks() global
    {The window is over. Whoever never got their 3D back is dropped; whoever HAS
     3D at this instant is KEPT, because they may still be wearing marks that the
     next load will have to strip.

     THIS USED TO BE ONE IntListClear, AND THAT WAS ONLY SAFE WHILE NOTHING
     COULD JOIN THE LIST AROUND THE WINDOW. Two things can.

     The actors RestoreAll put back join it HERE -- that is the third duty of
     this function and the note on RestoredKey() says why it cannot happen any
     earlier. What was painted onto them is a persist = false write into live 3D,
     indistinguishable from a fresh paint, so the next load has to be able to
     strip it; an actor restored and then cleared in the same breath is an actor
     case A could never clean again. Clearing the list would have traded
     that bug for its mirror image.

     And a consumer that paints anybody at all in the ten seconds after a load
     was always in this position: Paint remembered them, this function forgot them
     a moment later, and their marks then outlived every load for the rest of the
     session. That one is older than the restore and went unnoticed, because
     a silent bookkeeping loss shows nothing from the outside.

     So the test is the one the doc string describes:
     an entry goes only if its actor is gone or has no 3D. Their marks were
     written into 3D that no longer exists, and the 3D they come back with is
     clean, so there is nothing left to strip and nothing left to remember.

     WHAT THAT COSTS: an actor who is still standing there stays on
     the list after the window instead of being cleared off it, so the list now
     grows with the actors painted in this save rather than emptying on every
     load. That is the same bound as the save's own record, and the alternative
     is a target nothing can ever clean.}
    Int n = JsonUtil.IntListCount(MarkFile(), MarkKey())
    Int dropped = 0
    ; BACKWARDS, for the reason StripAll gives: entries are removed as they are
    ; judged and removing from under a forward index skips the next one.
    Int i = n - 1
    While i >= 0
        Int id = JsonUtil.IntListGet(MarkFile(), MarkKey(), i)
        Actor a = Game.GetFormEx(id) as Actor
        If a == None || !a.Is3DLoaded()
            JsonUtil.IntListRemoveAt(MarkFile(), MarkKey(), i)
            dropped += 1
        EndIf
        i -= 1
    EndWhile

    ; ---- AND THE RESTORE WINDOW CLOSES WITH THIS ONE ----------------------
    ;
    ; EVERYONE PUT BACK DURING THE WINDOW JOINS THE STRIP LIST NOW. They could
    ; not join it earlier without being stripped by the next pass; they have to
    ; join it at all because what was painted onto them is live persist = false
    ; work that the next load must be able to undo. This is the one moment both
    ; of those are true.
    Int back = JsonUtil.IntListCount(RestoreFile(), RestoredKey())
    Int r = 0
    While r < back
        JsonUtil.IntListAdd(MarkFile(), MarkKey(), \
                            JsonUtil.IntListGet(RestoreFile(), RestoredKey(), r), false)
        r += 1
    EndWhile
    JsonUtil.IntListClear(RestoreFile(), RestoredKey())
    ; The pending list empties too, but THE RECORD IS NOT TOUCHED. An actor whose
    ; 3D never arrived inside the ten seconds is still, as far as the save is
    ; concerned, wearing what they were wearing, and the next load that finds them
    ; loaded will put it back. Forgetting them here would silently turn "they were
    ; too far away to reach" into "the save no longer says so".
    Int stillPending = JsonUtil.IntListCount(RestoreFile(), RestoreKey())
    JsonUtil.IntListClear(RestoreFile(), RestoreKey())
    ; SAVED ONCE, HERE, AFTER BOTH EDITS. The strip list is the one thing in this
    ; function that has to survive the next load, and it has now been both pruned
    ; and added to; a Save() between the two would have written a list that was
    ; still half-finished.
    JsonUtil.Save(MarkFile())

    DC_Core c = Core()
    If c != None
        If c.Marked != None
            ; The ESP list is the human-readable mirror and nothing reads it, so
            ; it is rebuilt rather than diffed: Revert puts it back to what the
            ; plugin ships, which is nothing, without walking it removing
            ; entries while indexing, and the survivors go straight back on.
            c.Marked.Revert()
            Int k = JsonUtil.IntListCount(MarkFile(), MarkKey())
            Int j = 0
            While j < k
                Form f = Game.GetFormEx(JsonUtil.IntListGet(MarkFile(), MarkKey(), j))
                If f != None
                    c.Marked.AddForm(f)
                EndIf
                j += 1
            EndWhile
        EndIf
        c.LastPainted = None
    EndIf
    If dropped > 0 || stillPending > 0 || back > 0
        Debug.Trace("[DecalCore] window closed: " + back + " actor(s) put back and now" \
                    + " on the strip list, " + dropped \
                    + " never got their 3D back (nothing to strip), " \
                    + stillPending + " never came back to be restored" \
                    + " -- their record is kept for the next load")
    EndIf
EndFunction


; ==========================================================================
; WHAT THE SAVE SAYS THEY ARE WEARING -- THE RECORD, WHICH *MUST* ROLL BACK
; ==========================================================================
;
; THE CONTAINER QUESTION IS SETTLED BY ONE LINE OF SOMEBODY ELSE'S HEADER, AND
; BY THE LINE FIVE HUNDRED LINES BELOW IT THAT SAYS THE OPPOSITE.
;
; PapyrusUtil ships two storages and labels them itself:
;
;     "Storage functions - values in save game file."
;         -- StorageUtil.psc, the block heading over SetIntValue,
;            SetStringValue, SetFloatValue, IntListAdd, FormListAdd and the
;            rest of the Form-keyed family.
;
;     "Storage functions - separate file. These are shared in all save games.
;      Values are loaded and saved when savegame is loaded or saved."
;         -- StorageUtil.psc, the block heading over the File* family,
;            which it then records as "DEPRECATED v2.9: Replaced by
;            JsonUtil functions ... proxied to a shared json file".
;
; One header, two headings, and between them exactly the two behaviours this
; problem needs. The Form-keyed family belongs to the SAVE, so it rolls back
; with the save. The File* family -- which is JsonUtil, which is where the strip
; list above already lives -- is deliberately shared by every save and does not.
;
; SO: StorageUtil, Form-keyed, IS THE RESTORE RECORD. It is the only candidate
; among this mod's dependencies that both rolls back and can carry a payload.
;
; ONE THING THE HEADER DOES NOT SAY. It says "save
; game file"; it does not say WHICH file. PapyrusUtil is an SKSE plugin and an
; SKSE plugin cannot write into the .ess, so in practice this is the SKSE
; co-save -- an inference from what PapyrusUtil is, and nothing
; in this design rests on it. What the
; header does state, and all that is needed, is that these values belong to the
; save game and that the File* family deliberately does not.
;
; WHY NOT A FORMLIST ON THE QUEST. It is in the save and it would roll back
; correctly. What it
; cannot do is carry a PAYLOAD. Putting a mark back needs the area, the layer,
; the texture and the alpha, per actor; a FormList is a set of forms with
; nowhere to hang any of it, and Papyrus has no map. It would also be a new FLST
; record in a plugin whose append-only law exists precisely because its ids are
; already in existing saves.
;
; WHY NOT SCRIPT VARIABLES ON DC_Core. Same storage (the save), same rollback,
; and free of records because they would be Auto Hidden -- but the same missing
; map. Papyrus arrays are fixed-length with no dictionary, so a per-actor,
; per-area, per-layer record becomes parallel arrays with hand-rolled indexing
; and a hard cap of 128 entries. StorageUtil is the same storage with the keyed
; API already written and already loaded.
;
; AND IT IS NOT A NEW DEPENDENCY. StorageUtil and JsonUtil are the same
; PapyrusUtil plugin -- StorageUtil.psc implements its own File*
; functions by calling JsonUtil -- and this mod has hard-depended on it since
; the strip list moved into a file.
;
; FORMS HERE, FORMIDS THERE, AND THE CONTAINER IS THE REASON. JsonUtil is given
; FormIDs because it serialises a Form as plugin + id and has to resolve it back
; through the load order. StorageUtil lives in the save, so what it keeps is the
; engine's own handle, which is already right for the FF-prefixed references the
; engine makes at runtime. Each container gets the currency it is good at.
;
; THE SHAPE. One global list names the actors that have a record; each actor
; carries their own list of packed slots, and each slot a texture and an alpha:
;
;     FormList (None,  "DecalCore.worn")      -- the actors
;     IntList  (actor, "DecalCore.slots")     -- (area + 1) * 100 + layer
;     String   (actor, "DecalCore.t<slot>")   -- the texture
;     Float    (actor, "DecalCore.a<slot>")   -- the alpha
;
; THE SLOT IS ONE-BASED ON THE AREA SO THAT IT CAN NEVER BE ZERO. The doc block
; over Set*Value says "If zero, empty, or none are given, the key will be unset"
; (StorageUtil.psc). The doc block over the *ListAdd family
; says nothing either way about zero, and nothing else settles it.
; Body layer 0 is the commonest slot
; this mod writes -- it is the one every first hit takes -- and it is not a thing
; to hang on a difference that cannot be measured from here, so the packing
; simply never produces a zero. Areas are 0-3 and layers 0-99, so slot is
; 100-499 and both halves come back out by division.
;
; THE BASE IS A HUNDRED, NOT TEN. Ten is correct only for as long as
; a layer index cannot reach ten, as with skee64.ini's shipped six body layers and
; three of each of the others. Raising any area past ten layers
; puts layer 10 in reach, and (0 + 1) * 10 + 10 is 20, which is also
; (1 + 1) * 10 + 0 -- body layer 10 and HANDS layer 0 pack to the same int. The
; collision is silent both ways: the record overwrites, and the unpack hands
; RestoreOne the wrong area, so a mark restores onto the wrong body part or not
; at all. The base has to be wider than the widest layer count, so it is a
; hundred, which covers any iNumOverlays a person would set.
;
; AND THE OLD RECORDS ARE MOVED RATHER THAN ABANDONED. Slots written base-ten
; are 10-49; slots written base-hundred are 100-499. THE TWO RANGES DO NOT
; OVERLAP, so a slot below 100 is an old one and needs no version flag to say
; so -- MigrateSlots below reads the pair back out with the old arithmetic,
; repacks it with the new, and carries the texture and alpha across to the new
; key names. It runs at the top of RestoreOne, which is the one place a slot is
; ever read back, so every actor is converted the first time the save tries to
; put their marks back and never again.
;
; ALPHA IS READ BACK WITH missing = 0.0 FOR THE SAME RULE, from the other side:
; a recorded alpha of exactly zero unsets its own key, and zero is what it meant,
; so the default and the value agree and nothing has to know which happened.
;
; THE KEY NAMES ARE PREFIXED because the header asks for it:
; "all mods access the same storage ... It is recommended to prefix the variable
; with your mod name" (StorageUtil.psc).
String Function WornKey() global
    {The global list of actors this save says are wearing a DecalCore mark.}
    Return "DecalCore.worn"
EndFunction

String Function SlotsKey() global
    {Per actor: which (area, layer) pairs they have a record for.}
    Return "DecalCore.slots"
EndFunction

String Function TexKey(Int slot) global
    {Per actor, per slot: the texture that layer is recorded as wearing.}
    Return "DecalCore.t" + slot
EndFunction

String Function AlphaKey(Int slot) global
    {Per actor, per slot: the alpha it was recorded at.}
    Return "DecalCore.a" + slot
EndFunction

Int Function PackSlot(Int area, Int layer) global
    {(area, layer) as one never-zero int -- see the note above WornKey.

     THE BASE IS A HUNDRED AND NOT TEN. Ten collided the moment a layer index
     could reach ten, which more than ten overlays in an area makes it do; the note above
     WornKey works the collision through.}
    Return (area + 1) * 100 + layer
EndFunction

Int Function SlotBase() global
    {The first slot value the current packing can produce.

     Anything below this was packed by the old base-ten scheme and is an old
     record. The ranges do not overlap -- old is 10-49, new is 100-499 -- which
     is what lets MigrateSlots tell them apart without a version flag.}
    Return 100
EndFunction

Int Function MigrateSlots(Actor a) global
    {Repack this actor's base-ten slots as base-hundred. Returns how many moved.

     IN PLACE, BY INDEX. IntListSet writes one element without reordering the
     list (StorageUtil.psc), so the walk does not have to cope with the list
     shifting under it the way remove-and-add would.

     THE TEXTURE AND THE ALPHA MOVE WITH THE SLOT because the slot is part of
     their key names -- TexKey(20) and TexKey(100) are different keys, and a
     repack that left them behind would produce a slot that unpacks correctly
     and reads back an empty texture, which RestoreOne skips. So each pair is
     read at the old key, written at the new one, and the old one unset.

     THE ALPHA IS READ WITH missing = 0.0 for the reason the header gives: a
     recorded alpha of exactly zero unsets its own key, so the default and the
     value agree and nothing here has to know which happened.}
    If a == None
        Return 0
    EndIf
    Int n = StorageUtil.IntListCount(a, SlotsKey())
    Int moved = 0
    Int i = 0
    While i < n
        Int slot = StorageUtil.IntListGet(a, SlotsKey(), i)
        If slot > 0 && slot < SlotBase()
            Int area = slot / 10 - 1
            Int layer = slot % 10
            If area >= 0 && area < 4
                Int fresh = PackSlot(area, layer)
                String tex = StorageUtil.GetStringValue(a, TexKey(slot), "")
                Float alpha = StorageUtil.GetFloatValue(a, AlphaKey(slot), 0.0)
                If tex != ""
                    StorageUtil.SetStringValue(a, TexKey(fresh), tex)
                EndIf
                If alpha != 0.0
                    StorageUtil.SetFloatValue(a, AlphaKey(fresh), alpha)
                EndIf
                StorageUtil.UnsetStringValue(a, TexKey(slot))
                StorageUtil.UnsetFloatValue(a, AlphaKey(slot))
                StorageUtil.IntListSet(a, SlotsKey(), i, fresh)
                moved += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    If moved > 0
        Debug.Trace("[DecalCore] migrated " + moved + " base-10 slot(s) to base-100 on " + a)
    EndIf
    Return moved
EndFunction

Function Record(Actor who, Int area, Int layer, String tex, Float alpha) global
    {File what this actor is now wearing on this layer, in the save.

     CALLED FROM PAINT AND NOT FROM WEAR, for the reason Wear's own note already
     gives about the write-lag slot: the record is keyed per AREA and Wear is not
     told the area -- it is handed a node name, and picking "Body" back out of
     "Body [Ovl3]" to recover something the caller already knew would be a parser
     where a parameter would do. The cost is the same as there:
     a consumer that calls Wear directly rather than through Paint writes a
     texture that no later load will put back.

     FOUR NATIVE CALLS PER PAINT, and no more than that however many times the
     same target is hit: the two lists are told not to take duplicates, and the
     two values are a fixed key that is overwritten in place when a layer is
     promoted to denser art.}
    If who == None
        Return
    EndIf
    Int slot = PackSlot(area, layer)
    StorageUtil.FormListAdd(None, WornKey(), who, false)
    StorageUtil.IntListAdd(who, SlotsKey(), slot, false)
    StorageUtil.SetStringValue(who, TexKey(slot), tex)
    StorageUtil.SetFloatValue(who, AlphaKey(slot), alpha)
EndFunction

Function RecordAlpha(Actor who, Int area, Int layer, Float alpha) global
    {Update the recorded strength of a layer that already has a record.

     THE GUARD IS THE POINT. Fade() is public and takes any layer; fading a
     layer this service never painted is a consumer's own business, and starting
     a record for it would have the next load paint DecalCore's empty layer over somebody
     else's tattoo.}
    If who == None
        Return
    EndIf
    Int slot = PackSlot(area, layer)
    If !StorageUtil.IntListHas(who, SlotsKey(), slot)
        Return
    EndIf
    StorageUtil.SetFloatValue(who, AlphaKey(slot), alpha)
EndFunction

Function Unrecord(Actor who, Int area, Int layer) global
    {This layer is no longer wearing a DecalCore texture. Drop it from the record, and
     drop the actor themselves once they have no slots left, so the roster does not
     grow for the life of the save with targets who are clean.}
    If who == None
        Return
    EndIf
    Int slot = PackSlot(area, layer)
    ; IntListRemove returns how many instances went (StorageUtil.psc), so
    ; nothing removed means there was no record and there is nothing to unset.
    If StorageUtil.IntListRemove(who, SlotsKey(), slot, true) < 1
        Return
    EndIf
    StorageUtil.UnsetStringValue(who, TexKey(slot))
    StorageUtil.UnsetFloatValue(who, AlphaKey(slot))
    If StorageUtil.IntListCount(who, SlotsKey()) < 1
        StorageUtil.FormListRemove(None, WornKey(), who, true)
    EndIf
EndFunction

Int Function RecordedCount(Actor who) global
    {How many layers the save says this actor is wearing.}
    If who == None
        Return 0
    EndIf
    Return StorageUtil.IntListCount(who, SlotsKey())
EndFunction

Int Function WornCount() global
    {How many actors the save says are wearing something.}
    Return StorageUtil.FormListCount(None, WornKey())
EndFunction

; ==========================================================================
; PUTTING IT BACK, ACROSS THE SAME TEN SECONDS THE STRIP USES
; ==========================================================================
;
; THE WINDOW IS NOT A CONVENIENCE. StripAll's own note sets out why one pass at
; one moment is not enough -- the load stamp is written on PostLoadGame and
; PostLoadGame is not a promise that anyone's 3D has arrived; the test log shows
; it landing both before and after the pre-warm on different loads.
; Everything true of the strip is true of the restore for the same reason,
; so the restore rides the same fifty passes: whoever is up is dealt with and the
; rest are left for the next pass.
;
; THE PENDING LIST IS A WORKING COPY, AND IT IS IN JsonUtil ON PURPOSE -- WITH
; NO Save(). This is the one place in this file where JsonUtil's rollback
; behaviour is used as a FEATURE rather than worked around. Its header:
;
;     "When the player loads another save without saving themselves or the
;      Save() function having been manually called by a script, the loaded data
;      will be discarded and revert back to whatever the contents of the current
;      saved file are"  -- JsonUtil.psc
;
; A list that is never Save()d therefore empties itself on every load, which is
; what a per-window working list wants. BeginRestore clears it first in
; any case, so the one path that can leave stale content on disk -- the player
; saving the game inside the ten seconds, which flushes every modified file --
; is covered as well.
;
; WHY A SNAPSHOT AT ALL, RATHER THAN WALKING THE RECORD EACH PASS. Because an
; actor has to be able to LEAVE. The record must survive the window intact for
; the next load; the list of who still needs dealing with must empty as they are
; dealt with. They are the same shape as the strip list and the record above it,
; and for the same reason: one says what is true, the other says what is left
; to do.
;
; AND THE SNAPSHOT IS TAKEN AFTER THE LOAD, WHICH IS WHY IT READS THE RIGHT
; SAVE. BeginRestore is called from FL_Watch.CheckLoad, which fires on the first
; tick after the DLL's load stamp changes, and the stamp is written on
; PostLoadGame -- so the co-save deserialisation that rolls StorageUtil back has
; already happened by the time anything here reads it. That the engine restores
; SKSE plugin data before dispatching PostLoadGame is not documented in any
; header; what is measured is that everything else
; has already rolled back by then (FL_Watch's lastStamp, above).
String Function RestoreFile() global
    {The scratch file the pending-restore list lives in.

     NOT MarkFile(), for the mirror of the reason LagFile() is not MarkFile():
     that file's whole purpose is to survive a load and it is Save()d for it.
     This one's purpose is to be emptied by a load.}
    Return "DecalCore/restore"
EndFunction

String Function RestoreKey() global
    Return "pending"
EndFunction

String Function RestoredKey() global
    {Who has been put back during THIS window, held until the window closes.

     THE STRIP LIST CANNOT BE TOLD UNTIL THEN, AND THE REASON IS THE ORDER THE
     TWO HALVES RUN IN. A restored actor is wearing live persist = false marks
     and so belongs on the strip list for the NEXT load -- but StripAll runs
     first in every pass and strips whoever is on that list, so adding them
     during the window would have pass N+1 wipe what pass N had just put
     back, fifty times over. They wait here and ForgetMarks moves them across
     once the passes are finished.}
    Return "restored"
EndFunction

Int Function BeginRestore() global
    {A load happened. Snapshot who the save says is wearing something, and hand
     the fifty passes something to work through. Returns how many.

     FORMIDS GOING IN, because the working list is JsonUtil and JsonUtil is
     given FormIDs for the reason stated above the strip list. The record itself
     keeps Forms, and RestoreAll turns the id back into one with Game.GetFormEx
     exactly as StripAll does.}
    JsonUtil.IntListClear(RestoreFile(), RestoreKey())
    JsonUtil.IntListClear(RestoreFile(), RestoredKey())
    Int n = StorageUtil.FormListCount(None, WornKey())
    Int added = 0
    Int i = 0
    While i < n
        Form f = StorageUtil.FormListGet(None, WornKey(), i)
        If f != None
            ; THE REPACK HAPPENS HERE, AT THE EARLIEST POINT A LOAD REACHES the
            ; records -- before any pass has had a chance to read a slot with
            ; the new arithmetic. RestoreOne repeats the call because it is the
            ; function that actually reads a slot back and must not depend on
            ; having been reached through this one; the second call finds
            ; nothing below SlotBase() and returns zero.
            MigrateSlots(f as Actor)
            JsonUtil.IntListAdd(RestoreFile(), RestoreKey(), f.GetFormID(), false)
            added += 1
        EndIf
        i += 1
    EndWhile
    Debug.Trace("[DecalCore] load: the save says " + added + " actor(s) are wearing marks")
    Return added
EndFunction

Int Function PendingRestoreCount() global
    {How many recorded actors are still waiting for their 3D to come back.

     The window's closing test needs this as well as MarkedCount: on a save
     loaded in a later RUN of the game the strip list is empty on the opening pass,
     and a window that closed on that alone would shut before anybody's 3D had
     arrived and restore nothing.}
    Return JsonUtil.IntListCount(RestoreFile(), RestoreKey())
EndFunction

Int Function RestoreOne(Actor a) global
    {Put back everything the save says this actor is wearing. Returns how many
     layers had to be WRITTEN -- zero means every recorded layer already reads
     back as the record says, and they are done.

     IT WRITES ONLY WHAT DISAGREES, AND THAT IS WHAT MAKES THE WINDOW SELF-
     HEALING. The one hazard a restore has that a strip does not is
     QueueNiNodeUpdate: an actor who has never been painted in this run of the
     game has no overlay nodes, so RestoreAll has to ask for them and the rebuild
     that builds them can arrive after the write and throw it away. Re-checking
     the node on the next pass finds the texture missing and writes it again, and
     the pass after that finds it there and lets them go. Nothing has to know
     whether the rebuild happened.

     WHAT IT COSTS, BOUNDED. The write-lag note above LagFile() measures that a
     node does not answer with a write taken in the same call and does answer
     seconds later, and LagWindow() puts one second on it. Passes are a fifth of
     a second apart, so a layer is written about five times before the node
     agrees -- ten native calls per layer per load, once, and nothing at all for
     the rest of the window once they have left the list. That is the price of not
     needing to know when a rebuild finished, and it is worth paying.

     THE LAYER IS CHECKED AGAINST THE INSTALL. A record written when skee64.ini
     offered six body layers, read on an install configured for three, would name
     a node that does not exist -- and a write to a node that does not exist is a
     silent no-op that never reads back, which is the one input that could make
     the paragraph above run for all fifty passes instead of five.}
    If a == None || !PaintReady()
        Return 0
    EndIf
    Bool female = IsFemale(a)
    Int myId = a.GetFormID()
    Float now = Utility.GetCurrentRealTime()
    ; IDEMPOTENT, AND HERE BECAUSE THIS IS WHERE A SLOT IS READ BACK. Once
    ; BeginRestore has run there is nothing below SlotBase() left and this
    ; returns zero; it costs one list count on an actor who is already current.
    MigrateSlots(a)
    Int n = StorageUtil.IntListCount(a, SlotsKey())
    Int written = 0
    Int i = 0
    While i < n
        Int slot = StorageUtil.IntListGet(a, SlotsKey(), i)
        Int area = slot / 100 - 1
        Int layer = slot % 100
        String tex = StorageUtil.GetStringValue(a, TexKey(slot), "")
        If tex != "" && area >= 0 && area < 4 && layer < LayerCount(area)
            String node = NodeName(area, layer)
            ; THE LIVE NODE, for the reason Paint and Strip both read it: with
            ; persist = false there is no stored override to ask about.
            If NiOverride.GetNodePropertyString(a, false, node, 9, 0) != tex
                Float alpha = StorageUtil.GetFloatValue(a, AlphaKey(slot), 0.0)
                Wear(a, female, node, tex, alpha, layer)
                ; AND THE WRITE-LAG SLOT IS FILLED AS PAINT WOULD FILL IT, so a
                ; consumer painting this area in the next second reads what was
                ; just put here rather than the pre-write node, and does not
                ; claim a layer RestoreOne is in the middle of restoring. One slot per
                ; area is all there is, so with several layers of one area
                ; restored together only the last is guarded -- the same limit
                ; the slots have always had.
                NoteWrite(area, myId, layer, tex, now)
                written += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    Return written
EndFunction

Int Function RestoreAll() global
    {ONE PASS over the actors the save says are wearing something. Returns how
     many finished on this pass.

     IT MUST RUN AFTER StripAll IN THE SAME PASS, NEVER BEFORE IT. The strip is
     unconditional by design -- everything live belongs to a timeline the load
     undid -- so a restore that ran first would be wiped by the strip that
     followed and case B would fail. FL_Watch.StripPass
     is the caller and the order is written there too.

     AND EVERY ACTOR IT TOUCHES IS FILED FOR THE STRIP LIST. What it paints is a
     persist = false write onto live 3D, indistinguishable from a fresh paint, so
     the next load has to be able to strip it: an actor restored and not
     remembered is an actor case A could never clean again. They are filed under
     RestoredKey() rather than remembered outright, because remembering them now
     would put them under the strip that runs at the top of the very next pass --
     the note on RestoredKey has it in full.

     FILED WHEN THEY ARE TOUCHED, NOT WHEN THEY CONFIRM. The write has already
     happened by then; an actor the window runs out on mid-restore is wearing
     marks whether or not the node has admitted it yet.}
    If !PaintReady()
        Return 0
    EndIf
    Int n = JsonUtil.IntListCount(RestoreFile(), RestoreKey())
    Int done = 0
    ; BACKWARDS, for StripAll's reason: entries leave as they are dealt with.
    Int i = n - 1
    While i >= 0
        Int id = JsonUtil.IntListGet(RestoreFile(), RestoreKey(), i)
        Actor a = Game.GetFormEx(id) as Actor
        If a != None && a.Is3DLoaded()
            ; THEY MAY HAVE NO OVERLAY NODES AT ALL, and on the case this exists
            ; for -- a save made in an earlier run of the game -- they usually have
            ; none: AddOverlays is a per-session registration and skee installs
            ; the geometry on the next 3D build. Paint's own note explains it.
            ; The rebuild is asked for here for the same reason and the
            ; write that races it is covered by RestoreOne re-checking.
            If !NiOverride.HasOverlays(a)
                NiOverride.AddOverlays(a)
                a.QueueNiNodeUpdate()
            EndIf
            JsonUtil.IntListAdd(RestoreFile(), RestoredKey(), id, false)
            If RestoreOne(a) < 1
                JsonUtil.IntListRemoveAt(RestoreFile(), RestoreKey(), i)
                done += 1
            EndIf
        EndIf
        i -= 1
    EndWhile
    Return done
EndFunction
