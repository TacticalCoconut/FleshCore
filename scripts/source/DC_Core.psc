Scriptname DC_Core extends Quest
{DecalCore -- the record holder.

 Everything the service needs from the plugin lives here as a property, so
 DC_Api can reach it without knowing a single FormID beyond this quest's own.
 Consumers should not talk to this script directly; DC_Api is the interface and
 this is the cupboard behind it.}

; ---- the impact sets, one per kind per size -------------------------------
;
; SIZE IS A RECORD, NOT A NUMBER. PlayImpactEffect takes no size argument: the
; decal's dimensions live in the Impact's own Decal block. So the only way a
; caller can ask for a bigger mark is to be handed a different Impact, which is
; why there are three of each rather than one and a multiplier.
ImpactDataSet Property BloodS = None Auto
ImpactDataSet Property BloodM = None Auto
ImpactDataSet Property BloodL = None Auto
ImpactDataSet Property CumS = None Auto
ImpactDataSet Property CumM = None Auto
ImpactDataSet Property CumL = None Auto

; ---- the same, but FOUR OF EACH, in a list --------------------------------
;
; VARIETY IS NOT ONE TEXTURE. The engine already draws one quadrant of a 2x2
; atlas at random, so a single atlas is four marks; four atlases is sixteen.
; Which atlas a cast uses is decided here, by picking a member of the list at
; random, because an Impact record carries exactly one texture set.
;
; The single properties above are variant 0 and stay where they are -- their
; FormIDs are in existing saves and the layout is frozen. These lists hold all
; four, variant 0 included, so SetFor only has to read one place.
FormList Property SetsBloodS = None Auto
FormList Property SetsBloodM = None Auto
FormList Property SetsBloodL = None Auto
FormList Property SetsCumS = None Auto
FormList Property SetsCumM = None Auto
FormList Property SetsCumL = None Auto

; ---- the overlay textures -------------------------------------------------
;
; These are BODY-UV textures, not the little splat above. An overlay is painted
; into their skin's own UV space, so the art has to be laid out the way their body
; is unwrapped; a decal texture pasted here would appear as one square patch on
; whatever part of them that corner of the UV map happens to be.
;
; SIX OF EACH, ONE PER LAYER, AND THAT IS WHAT MAKES IT ACCUMULATE. RaceMenu
; gives six body overlay layers and DC_Api paints the first empty one, so the
; layers stack on their own -- but only if each carries DIFFERENT art. Six
; copies of one texture would put the same drips in the same places and the
; second hit would be invisible. Variant 0 is the sparsest; they get heavier.
; No properties: the path is built from the kind and the layer, so adding a
; seventh is a file and nothing else.
; ---- the mundane world ----------------------------------------------------
;
; Every Skyrim.esm base object whose model lives under Clutter\ -- cups, jugs,
; plates, bottles, potions, baskets, barrels, sacks. Two thousand and
; thirty-four of them.
;
; IT IS A LIST BECAUSE PAPYRUS GIVES NO CHOICE. Game.FindClosestReferenceOf*
; matches against base objects handed to it up front; there is no "find any
; reference near here", and SKSE adds no FindAll* either. So the
; only way to ask "what mundane thing is nearest this mark" is to have named
; every mundane thing in advance.
; ---- who is wearing a mark -------------------------------------------------
;
; Papyrus cannot enumerate actors, so the reset after a save load needs a record
; of who to reset. DC_Api.Paint adds to this; DC_Load walks it and reverts it.
FormList Property Marked = None Auto

FormList Property Clutter = None Auto

; ---- coating anything that is not a wall -----------------------------------
;
; A projected decal needs a ray to land on geometry, and a ray cast from a cup
; starts inside the cup. An EFFECT SHADER does not care: EffectShader.Play takes
; ANY ObjectReference and wraps its geometry in a texture for as long as you
; ask -- corpses, dropped items, FleshCore's own shards.
;
; Bethesda's own BerserkerFXS is this exact thing: a membrane shader with no
; particles whose fill texture is a blood decal atlas. These are cloned from it.
EffectShader Property CoatBlood = None Auto
EffectShader Property CoatAlt = None Auto

; ---- and the same thing in BODY UV, for shards ----------------------------
;
; Three per kind, ascending in density, whose fill textures are the OVERLAY art
; rather than the decal atlases. A shard keeps their body's texture coordinates,
; so body-UV art lands on it exactly where it sat on them; the flat-quad atlases
; in the two Coat shaders would be meaningless wrapped round a fragment of thigh.
FormList Property SkinCoatBlood = None Auto
FormList Property SkinCoatAlt = None Auto

Int Property SkinVariants = 6 Auto Hidden

; ---- the mark the pieces of the current wound should carry -----------------
;
; Hidden and set at runtime, so it costs no record and no plugin rebuild.
;
; It exists because a shard cannot be told directly. FL_Watch knows the victim
; and therefore the mark, but the moment it knows it -- inside PlaceAtMe's own
; loop -- the piece has no 3D to put a shader on, and a cross-script call into
; a just-created object stalls the placement loop until that object's OnInit is
; dispatched (FL_Watch says so, at length, about CameFromPool). So the mark is
; left here and each piece collects it in OnLoad, where its 3D is real.
Int Property PendingMark = -1 Auto Hidden

; ---- who was painted last, and when ----------------------------------------
;
; So the marker can tell whether the magic effect already dealt with an actor.
; Hidden and set at runtime: no record, no plugin rebuild.
Form Property LastPainted = None Auto Hidden
Float Property LastPaintAt = 0.0 Auto Hidden

Int Property Version = 2 Auto Hidden

ImpactDataSet Function SetFor(Int kind, Int size)
    {One record for a kind and size, chosen at random from that list.

     Falls back to the single frozen property if the list is empty or missing,
     so a half-installed update degrades to one atlas per size rather than to
     no decal at all.}
    FormList l = None
    ImpactDataSet one = None
    If kind == 0
        If size <= 0
            l = SetsBloodS
            one = BloodS
        ElseIf size == 1
            l = SetsBloodM
            one = BloodM
        Else
            l = SetsBloodL
            one = BloodL
        EndIf
    ElseIf kind == 1
        If size <= 0
            l = SetsCumS
            one = CumS
        ElseIf size == 1
            l = SetsCumM
            one = CumM
        Else
            l = SetsCumL
            one = CumL
        EndIf
    EndIf
    If l != None && l.GetSize() > 0
        Form f = l.GetAt(Utility.RandomInt(0, l.GetSize() - 1))
        ImpactDataSet picked = f as ImpactDataSet
        If picked != None
            Return picked
        EndIf
    EndIf
    Return one
EndFunction

String Function SkinFor(Int kind, Int layer)
    {The overlay texture for a kind and a LAYER, or "" if the kind is unknown.

     The layer picks the art, which is the whole accumulation mechanism: hit
     them once and they wear the sparsest of the six; hit them six times and they
     are wearing all of them at once. Out-of-range layers wrap rather than
     failing, so a RaceMenu configured with more layers than there is art for
     reuses art instead of painting nothing.}
    Int v = layer
    If v < 0
        v = 0
    EndIf
    v = v % SkinVariants
    If kind == 0
        Return "DecalCore\\blood_skin" + v + ".dds"
    ElseIf kind == 1
        Return "DecalCore\\alt_skin" + v + ".dds"
    EndIf
    Return ""
EndFunction
