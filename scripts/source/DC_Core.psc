Scriptname DC_Core extends Quest
{DecalCore -- the record holder.

 Everything the service needs from the plugin lives here as a property, so
 DC_Api can reach it without knowing a single FormID beyond this quest's own.
 Consumers should not talk to this script directly; DC_Api is the interface and
 this is the cupboard behind it.}

; ---- the impact sets, one per size ----------------------------------------
;
; SIZE IS A RECORD, NOT A NUMBER. PlayImpactEffect takes no size argument: the
; decal's dimensions live in the Impact's own Decal block. So the only way a
; caller can ask for a bigger mark is to be handed a different Impact, which is
; why there are three rather than one and a multiplier.
;
; These are blood, kind 0, the one kind built in. Any other kind is registered
; at runtime by the mod that owns its records -- see RegisterKind below.
ImpactDataSet Property BloodS = None Auto
ImpactDataSet Property BloodM = None Auto
ImpactDataSet Property BloodL = None Auto

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

; ---- and the same thing in BODY UV, for shards ----------------------------
;
; Three, ascending in density, whose fill textures are the OVERLAY art rather
; than the decal atlases. A shard keeps their body's texture coordinates, so
; body-UV art lands on it exactly where it sat on them; the flat-quad atlas in
; the Coat shader would be meaningless wrapped round a fragment of thigh.
FormList Property SkinCoatBlood = None Auto

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

; ---- the kinds an add-on registers -----------------------------------------
;
; Blood is kind 0 and lives in the properties above. Any other kind is handed in
; at runtime by the mod that owns its records, through DC_Api.RegisterKind, and
; kept here in plain script variables: no property and no record in this plugin,
; and it survives a save. A mod registers its kind again on every load, which
; also picks up anything it changed. Kinds 1 to 7; each brings the same set of
; records blood has -- three size lists of impact sets, a coat shader, a list of
; three body-UV coat shaders -- and the stem of its six overlay textures.
FormList[] kindSetsS
FormList[] kindSetsM
FormList[] kindSetsL
EffectShader[] kindCoat
FormList[] kindSkinCoat
String[] kindSkin
Int kindTop = 0

Bool Function RegisterKind(Int kind, FormList setsS, FormList setsM, FormList setsL, \
                           EffectShader coat, FormList skinCoat, String skinStem)
    {Kind `kind` (1-7) marks with these records. skinStem names its overlay art
     under textures\DecalCore\: layer variant v is skinStem + v + ".dds". False,
     and nothing kept, for a kind out of range or an empty stem.}
    If kind < 1 || kind > 7 || skinStem == ""
        Return false
    EndIf
    If !kindSkin
        kindSetsS = new FormList[8]
        kindSetsM = new FormList[8]
        kindSetsL = new FormList[8]
        kindCoat = new EffectShader[8]
        kindSkinCoat = new FormList[8]
        kindSkin = new String[8]
    EndIf
    kindSetsS[kind] = setsS
    kindSetsM[kind] = setsM
    kindSetsL[kind] = setsL
    kindCoat[kind] = coat
    kindSkinCoat[kind] = skinCoat
    kindSkin[kind] = skinStem
    If kind > kindTop
        kindTop = kind
    EndIf
    Return true
EndFunction

Bool Function HasKind(Int kind)
    {Blood, or a kind something registered.}
    If kind == 0
        Return true
    EndIf
    Return kind >= 1 && kind <= 7 && kindSkin && kindSkin[kind] != ""
EndFunction

Int Function TopKind()
    {The highest kind number that may be in use: 0 while blood is the only one.
     A loop over 0..TopKind() still asks HasKind of each.}
    Return kindTop
EndFunction

EffectShader Function CoatFor(Int kind)
    {The flat-atlas coat for a kind, or None.}
    If kind == 0
        Return CoatBlood
    ElseIf HasKind(kind)
        Return kindCoat[kind]
    EndIf
    Return None
EndFunction

FormList Function SkinCoatFor(Int kind)
    {The body-UV coat bands for a kind, lightest first, or None.}
    If kind == 0
        Return SkinCoatBlood
    ElseIf HasKind(kind)
        Return kindSkinCoat[kind]
    EndIf
    Return None
EndFunction

ImpactDataSet Function SetFor(Int kind, Int size)
    {One record for a kind and size, chosen at random from that list.

     For blood, falls back to the single frozen property if the list is empty or
     missing, so a half-installed update degrades to one atlas per size rather
     than to no decal at all. A registered kind has its lists only; an unknown
     kind has nothing and gets None.}
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
    ElseIf HasKind(kind)
        If size <= 0
            l = kindSetsS[kind]
        ElseIf size == 1
            l = kindSetsM[kind]
        Else
            l = kindSetsL[kind]
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
    ElseIf HasKind(kind)
        Return "DecalCore\\" + kindSkin[kind] + v + ".dds"
    EndIf
    Return ""
EndFunction

Bool _washArmed = false
Bool _playerWashedSent = false

Function EnsureWashLoop()
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
    If !_washArmed
        _washArmed = true
        RegisterForSingleUpdate(1.0)
    EndIf
EndFunction

Event OnInit()
    EnsureWashLoop()
EndEvent

Function OnFleshCoreReload(String eventName, String strArg, Float numArg, Form sender)
    _washArmed = true
    _playerWashedSent = false
    RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
    RegisterForSingleUpdate(1.0)
EndFunction

Function WashActorCheck(Actor a, Bool isPlayer)
    If !a || a.IsDisabled() || !a.Is3DLoaded()
        Return
    EndIf
    Bool deep = a.IsSwimming() || PO3_SKSEFunctions.IsActorUnderwater(a)
    Bool waist = false
    If !deep
        waist = PO3_SKSEFunctions.IsRefNodeInWater(a, "NPC Pelvis [Pelv]") || PO3_SKSEFunctions.IsRefNodeInWater(a, "NPC Spine [Spn0]")
    EndIf
    If deep || waist
        Float drop = 0.22
        If deep
            drop = 0.35
        EndIf
        If StorageUtil.IntListCount(a, DC_Api.SlotsKey()) > 0
            DC_Api.WashStep(a, drop)
            If isPlayer
                _playerWashedSent = true
            EndIf
        Else
            DC_Api.UncoatAll(a)
            If isPlayer && !_playerWashedSent
                _playerWashedSent = true
                a.SendModEvent("FL_Clean", "", 0.0)
            EndIf
        EndIf
    ElseIf isPlayer
        _playerWashedSent = false
    EndIf
EndFunction

Event OnUpdate()
    Actor p = Game.GetPlayer()
    If p
        WashActorCheck(p, true)
    EndIf
    Int i = StorageUtil.FormListCount(None, DC_Api.WornKey()) - 1
    While i >= 0
        Actor a = StorageUtil.FormListGet(None, DC_Api.WornKey(), i) as Actor
        If a && a != p
            If !p || a.GetDistance(p) <= 3500.0
                WashActorCheck(a, false)
            EndIf
        EndIf
        i -= 1
    EndWhile
    RegisterForSingleUpdate(1.0)
EndEvent
