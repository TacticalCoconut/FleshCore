// lattice.h -- THE VOXEL BODY.
//
// The premise of this mod, stated once: a playable-race body is not a mesh
// with fourteen named limbs that can be hidden. It is a FIELD OF CELLS. Every
// triangle of every shape the actor wears -- their skin, their armour, their
// jewellery -- belongs to exactly one cell of a regular lattice in the body's
// own bind space, and a cell is the smallest thing that can leave.
//
// Everything else follows from that:
//   * A wound is a REGION OF SPACE, not a region of the skeleton. A blow to
//     the shoulder takes the cells near the shoulder, and whatever geometry
//     happens to pass through them comes away together, in one piece, still
//     wearing its own textures.
//   * The lattice is fine (a few units per cell) because it is only a map.
//     What becomes a physical object is an ISLAND: a set of cells that are
//     connected to each other. A clean sever takes an arm off as one island;
//     a heavy blow opens a crater of two or three.
//   * Islands are capped, so a large island fragments instead of becoming one
//     absurd object, and the fragments are still connected runs of cells
//     rather than arbitrary slices.
//   * A body remembers what it has already lost, so damage accumulates.
//
// This header is PURE. It knows nothing about Skyrim, has no engine calls in
// it, and is compiled unchanged into both the SKSE plugin and the unit tests
// in test/.
#pragma once
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace flesh {

// One shape of the actor's assembled body, as the engine handed it over.
struct ShapeData {
    std::string name;                    // the node name, for logs
    std::uint64_t desc = 0;              // BSVertexDesc, verbatim
    std::uint32_t vsize = 0;             // bytes per vertex record
    const std::uint8_t* verts = nullptr; // raw records; NOT owned
    std::uint32_t nVerts = 0;
    bool skin = false;                   // body/skin rather than armour
    // WHETHER THAT SKIN COUNTS AS A CELL'S isSkin. Their own face is
    // skin for every purpose the lattice has -- cells, `mine`, clearance --
    // except the head's by-layer death tally while it cannot yet be cut:
    // a face the engine still draws whole must not be what kills them. The
    // reader clears this at HF 1 and sets it at HF 2. Nothing else clears it.
    bool skinCounts = true;
    int layer = 0;                       // 0 outer, 1 fat, 2 muscle -- DEPTH
    std::vector<std::string> tex;        // texture slots, in order
    std::vector<const char*> vertBone;   // heaviest bone per vertex, or null
    // TRIANGLES PER LUMP, for a shape that is a field of closed volumes rather
    // than a surface. Zero for ordinary geometry.
    //
    // The lattice sorts a triangle into a cell by the floor of its centroid,
    // which is right for a surface and wrong for a solid: a lump big enough to
    // leave no gap against its neighbours is necessarily big enough to cross a
    // cell line, and then a wound takes half of it and leaves the rest open --
    // 341 of 574 test chunks, the first time this was tried. Grouping the
    // triangles and sorting the GROUP by its own centroid removes the problem
    // at its root instead of shrinking the lumps to fit, which is what forced
    // them to be square.
    std::uint32_t lumpTris = 0;
};

// Every layer a body can carry: skin (0), fat (1), muscle (2), bone (3), and worn armour (4).
inline constexpr int           kLayerArmour = 4;
inline constexpr std::uint32_t kArmourBit   = 0x10u;
inline constexpr std::uint32_t kAllLayers   = 0x1Fu;

// ARMOUR, SKIN, FAT AND MUSCLE, AND NOT BONE.
//
// DepthMask cannot express this and must not be taught to: depth 3 reaching
// the bone is a FIX -- see the note below -- and changing it back to
// 0b111 would restore the band of white lumps left hanging in a deep cut.
// A wound that wants all their meat and none of their skeleton names this instead.
inline constexpr std::uint32_t kFleshLayers = 0x17u;

// How deep a wound goes, as a mask over layers. Depth 1 takes only the outer
// surface (armour/skin) and leaves the fat showing; depth 2 takes the fat too
// and leaves muscle; depth 3 takes EVERYTHING, bone included.
//
// DEPTH 3 REACHES THE BONE. A mask that topped out at 0b111 would spare
// layer 3, which is bone, and a deep cut would leave a band of white lumps
// hanging in the gap where the flesh around them had gone. Those lumps are
// the bone of the cells the wound took, and they have no business surviving it.
//
// It costs nothing that was worth keeping. A crater's floor is the next cell
// IN, which still has its own bone -- so a deep wound still opens onto bone,
// it simply does not leave the bone of the cells it removed floating in mid
// air. And a chunk of arm on the floor has bone in it, which is what a
// chunk of arm has in it.
inline std::uint32_t DepthMask(int depth) {
    if (depth < 1) depth = 1;
    if (depth >= 3) return kAllLayers;
    return ((1u << depth) - 1u) | kArmourBit;
}

// A triangle, addressed globally: which shape, and three vertex indices into
// that shape's record array.
struct TriRef {
    std::uint32_t shape = 0;
    // WHICH RENDER PARTITION DREW IT -- in the low fifteen bits.
    //
    // Bit 15 is THE SHALLOW FLAG: this triangle belongs to a fill lump that
    // sits closer to their skin than its own reach, so it is one of the lumps
    // that surfaces when they bend. A partition index is bounded by 64 and a
    // skin instance may hold at most 64 of them, so the top bits of this field
    // have never been anything but zero.
    //
    // It lives here rather than in a byte of its own because a body carries
    // about two million TriRefs: a byte would be padded to four and cost eight
    // megabytes an actor, and five bodies are loaded at once. This
    // costs nothing. `part` is read in exactly one place (Redraw's `live` key),
    // so Idx() is the only accessor that matters.
    std::uint16_t part = 0;
    std::uint16_t v[3] = {0, 0, 0};

    static constexpr std::uint16_t kShallow = 0x8000;
    std::uint16_t Idx()     const { return std::uint16_t(part & 0x7FFF); }
    bool          Shallow() const { return (part & kShallow) != 0; }
};

struct Key {
    std::int32_t x = 0, y = 0, z = 0;
    bool operator<(const Key& o) const {
        if (x != o.x) return x < o.x;
        if (y != o.y) return y < o.y;
        return z < o.z;
    }
    bool operator==(const Key& o) const { return x == o.x && y == o.y && z == o.z; }
};

struct Cell {
    Key key;
    std::vector<TriRef> tris;
    float c[3] = {0, 0, 0};        // bind-space centroid
    const char* bone = nullptr;    // the bone that owns most of it
    // WHAT IS LEFT HERE, PER LAYER. A cell is not simply present or absent:
    // the skin over a piece of hip can be gone while the fat and the muscle
    // under it are still there, which is what a shallow cut IS. `layers` is
    // what this cell ever had, `gone` is what has been taken.
    std::uint32_t layers = 0;
    std::uint32_t gone = 0;
    // WHAT THE LAST REDRAW SAW HERE: the `gone` word and the
    // clearance verdict (0 open, 1 covered) it drew this cell with. A cell
    // whose two answers have not moved since cannot have changed what any
    // shape through it draws, so Redraw rebuilds only the shapes that pass
    // through a cell that HAS moved -- the difference between walking every
    // triangle they have on every blow and walking the ones near the wound.
    // The sentinels mean "never drawn": a fresh lattice is all dirty.
    std::uint32_t drawnGone = 0xFFFFFFFFu;
    std::uint8_t  drawnCovered = 2;
    // IS ANY OF *THEM* IN THIS CELL, as opposed to only things they are wearing?
    //
    // The lattice takes every triangle of every shape an actor carries, so a
    // cell can hold nothing but hat, or nothing but collar, or nothing but the
    // hem of a robe. Those cells are real and they must be swept when they
    // come loose -- a hat left hanging where a head was
    // looks broken -- but they are not evidence that a TARGET
    // has come apart, and a target who dies because their hat fell off is worse
    // than one that keeps it. True when any triangle here belongs to their skin
    // or to their fill; false when the cell is pure wardrobe.
    bool mine = false;
    // IS ANY OF WHAT IS HERE THEIR SKIN?
    //
    // `mine` is "any of them, skin or fill". This is narrower and it exists for
    // one reason: the head's death-by-layer rule counts a Head cell's SKIN by
    // testing layer bit 0, and Build sets that bit for every layer-0 shape --
    // theirs, FL_Head's wardrobe face, a hat, and (when they are read) their brows,
    // their eyes and their hair. Hair is weighted to NPC Neck and NPC Head, reaches
    // down the back, and maps to Part::Head by the Neck tag, so a back wound
    // that took nothing but hair would count against the head's skin threshold.
    //
    // Set from ShapeData::skin, which is the same substring test that decides
    // everything else about what is theirs.
    bool isSkin = false;
    std::set<std::uint32_t> shapes;   // which shapes pass through here
    // WHERE EACH SHAPE'S TRIANGLES SIT IN `tris`. Build fills `tris`
    // shape by shape, so a cell's triangles are already grouped by shape in
    // ascending order; this is that grouping written down -- one entry per
    // shape, [begin, end) into `tris` -- so a redraw that rebuilds six of
    // sixty-odd shapes walks the six shapes' triangles and steps over the
    // rest, instead of visiting every one of their two million TriRefs to ask
    // each which shape it belongs to. Built by BuildRuns at the end of Build,
    // which also proves the grouping (and sorts the one cell that broke it).
    struct Run { std::uint32_t shape, begin, end; };
    std::vector<Run> runs;
    // THIS CELL'S NUMBER: the order Build created it in, so a flat
    // array can stand in for the map when a redraw asks every cell the same
    // two questions. See Lattice::triCell.
    std::uint16_t ord = 0;
    // WHICH NAMED PART THIS CELL BELONGS TO, cached at Build time.
    //
    // A plain byte holding a flesh::Part, for two reasons: Part is declared
    // further down this header, and PartOfBone() parses a bone NAME -- a
    // string compare per cell per test is not something a selection loop over
    // several thousand cells can pay, and this is asked once per selection
    // per cell.
    std::uint8_t part = 0;            // flesh::Part, 0 = Unknown

    bool Alive(std::uint32_t mask) const { return (layers & ~gone & mask) != 0; }
    // AND, OPTIONALLY, ONLY CERTAIN PARTS of THE BODY.
    //
    // `parts` is a bitmask over flesh::Part and ZERO MEANS EVERY PART, which
    // is the default. A wound that sets it cannot
    // reach a cell outside those parts at all -- not to select it, not to
    // spread into it, not to re-seed onto it when the aim misses. That total
    // exclusion is what makes a head spell a HEAD spell rather than a body
    // spell that happens to be pointed at a head.
    bool Alive(std::uint32_t mask, std::uint32_t parts) const {
        return (parts == 0u || (parts & (1u << part))) && Alive(mask);
    }
    // ANYTHING AT ALL LEFT HERE. This used to exclude bit 3, because bit 3 was
    // the lining and the lining could never be removed -- counting it would
    // have made every cell look alive forever. Bit 3 is bone, a deep wound
    // takes it, and a cell that has lost its bone as well as its meat is
    // empty in every sense that matters: nothing is drawn there, and nothing
    // there holds anything on to anything.
    bool Empty() const { return (layers & ~gone & kAllLayers) == 0; }
};

// Position of one vertex record, honouring half-float positions.
void PosOf(const std::uint8_t* rec, std::uint64_t desc, float out[3]);

// CLOSE THE WOUND ON THE ACTOR.
//
// Surfaces put BEHIND a see-through wound cannot stand in for this.
// Removing triangles from a closed shell
// leaves a hole, and a hole viewed from outside shows either backfaces --
// which the rasterizer discards -- or the room beyond. No number of inner
// shells changes that, because an inward-facing shell is invisible from
// outside by construction. The only thing that makes a wound read as flesh is
// a surface AT the wound, facing OUT. Chunks have one
// (chunknif's Solidify); this is the actor's.
//
// It is built from the shape's OWN vertices because that is all an index
// buffer can address -- no new geometry, no new allocation, just triangles
// the mesh could always have drawn and never did. An edge that two triangles
// shared before the cut and only one shares after is an edge the cut opened;
// those edges form loops; each loop is fanned to one of its own vertices and
// emitted BOTH ways, so no winding convention has to be guessed.
//
// `orig` is the shape's full original triangle list, `keep` the survivors
// (appended to in place). Returns the number of triangles added.
std::uint32_t CapWound(const std::uint16_t* orig, std::uint32_t origTris,
                       std::vector<std::uint16_t>& keep, std::uint32_t maxTris);

// ============================================================ THE CUT VOLUME
//
// WHY A WOUND NEEDS A SURFACE OF ITS OWN.
//
// A body in Skyrim is a THIN SHELL. Every vertex it owns lies on its skin, so
// every surface that can be built out of its own vertices lies on its skin
// too. So a fat shell, a muscle shell, an inward-facing lining or a fanned
// cut face each puts a surface somewhere OTHER than in the
// opened volume, because the opened volume contains no vertices to build one
// from. A hole in a shell shows backfaces, which are culled, or the room
// beyond. Nothing placed behind it changes that.
//
// The lattice, though, knows the volume. It knows which cells held flesh and
// which of them a wound has taken, and the boundary between those two sets is
// the wound surface -- a real surface, at the real depth of the cut, with a
// real outward direction. THIS is the geometry the wound opens up, and it can
// be stated exactly:
//
//   a face is exposed when flesh on one side of it meets, on the other side,
//   a cell that HELD flesh and no longer does.
//
// The "and no longer does" is what keeps the outer skin out of it. Where a
// solid cell faces open air there is no neighbouring cell at all, and no wall
// is emitted -- their skin is already drawn there. Walls appear only where
// something was removed, which is where the player is looking in.
//
// A cavity built this way is CLOSED: the far wall of the crater is the face
// of the cell behind it, wound the other way. There is nothing left to see
// through, so no backstop shell is needed for the wound to read as flesh.
//
// Such quads cannot be drawn from the wounded shape's vertices --
// so they would go into vertex slots reserved
// in the mesh, in a shape that already carries a gore texture. Nothing builds them now (see below).
struct CutQuad {
    float p[4][3];          // corners in bind space, wound to face the void
    std::uint16_t tmpl;     // a REAL vertex of the cut shape, near this face
};

// WHY A TEMPLATE VERTEX AND NOT A DESCRIBED ONE.
//
// The body's vertex record was measured, byte by byte, against the shipping
// body mesh: position is three floats at 0, bytes 12-15 are always
// zero, the UV is a half pair at 16, and the skin block is four half weights
// at 20 followed by four palette indices at 28. There is NO NORMAL in it --
// all shading comes from the model-space normal map, indexed by UV. So a
// vertex invented from nothing would have to invent a UV as well, and a UV
// invented from nothing samples an arbitrary direction out of that normal map
// and lights the wound in an arbitrary direction.
//
// A vertex of the cut shape from the SAME PART OF THEIR BODY has all of it
// already: a UV that lands on flesh in the diffuse and on a sane direction in
// the normal map, and skin weights that ride the right bones with the right
// blend across a joint. So a cut vertex is that vertex copied whole, with its
// POSITION -- and only its position -- replaced. One field is written, and it
// is the one field there is no doubt about.
// ExposedFaces() was declared here and is gone: it had no callers, and it was
// written for a hollow body that no longer exists. CutQuad stays because the
// dormant blood canvas in flesh.cpp still names it.


class Lattice;

// ======================================================== TRUE DISMEMBERMENT
//
// A NAMED PART OF THE BODY, AND WHAT IT IS ALLOWED TO HANG OFF.
//
// The point of this mod is that a body is a field of cells, not a set of named
// limbs -- but the moment the question becomes "is this arm still ON them", the
// names come back, because they are the only thing that can answer it.
//
// The naive answer is to take what is still alive and run connected components
// over the lattice adjacency. That does not work, and the reason is worth
// writing down: a cell exists wherever geometry is, and cells are joined when
// they are grid neighbours. In bind pose the upper arm hangs a couple of units
// off the ribs, which is less than one cell -- so the armpit air gap is
// invisible, the arm is "connected" to the chest through nothing at all, and a
// clean cut through the shoulder reads as no cut at all. Every gap where two
// parts of a body pass close has the same problem: the inner thighs, the hand
// against the hip, the heel against the calf.
//
// So the adjacency is gated by anatomy. Two cells are joined only if they
// belong to the same named part, or to two parts that are jointed to
// each other. The armpit shortcut dies with it: the upper arm may still reach
// the chest, because a shoulder IS a joint -- but the forearm cannot reach the
// pelvis, and once the flesh AT the shoulder is gone there is no chain of
// legal hops left between the arm and the rest of the body.
//
// THE UNKNOWN PART IS NOT A WILDCARD. A cell whose heaviest bone is not one of the
// named bones -- a skirt bone, a chain, a piece of jewellery with its own rig -- is
// given Part::Unknown, and Unknown cells are left OUT of the component pass
// entirely, then attached afterwards to whichever section reached them first.
// The alternative, letting Unknown join to everything, means a long robe is a
// bridge between the two legs and a target in a robe can never lose one.
enum class Part : std::uint8_t {
    Unknown = 0,
    Head, Chest, Abdomen,
    LUpperArm, LForearm, LHand,
    RUpperArm, RForearm, RHand,
    LThigh, LCalf, LFoot,
    RThigh, RCalf, RFoot,
    Count
};

const char* PartName(Part p);
// THE SAME PART AS ONE WORD: "lthigh", "chest", "rfoot" -- the
// spelling FL_Api.PartBit lists and every event payload carries, where a
// column is split on '|' and ',' and a name with a space in it is a name a
// consumer has to quote. PartName's spellings ("left thigh") stay the log's
// and the config file's; either is accepted wherever a part is named.
const char* PartKey(Part p);

// WHERE A WOUND LANDS WHEN IT DOES NOT LAND WHERE YOU AIMED.
//
// Field report on the head set: aimed head spells landed wherever the cast hit,
// so the same spell cut a different place every cast.
// Head spells take their place from anatomy, as Halve does: a
// cut taken from the crosshair is a different wound every cast, and a cut
// taken from their own anatomy is a thing you can point at and name.
//
// Halve and Neck each answered this by computing one number inside their own
// form. That does not generalise -- there is nothing anatomical about `bite`
// or `layerx` -- so the anchor is a property of the WOUND instead, and any
// form can have one. It is resolved over the live cells of whatever parts the
// wound is locked to, so "the front of their head" is their head's own front.
//
// Aim is the default.
enum class Anchor : std::uint8_t {
    Aim = 0,        // where the shot landed -- the default
    Centre,         // the middle of the locked part's live cells
    Front, Back,    // +y / -y face of it, at the centre in the other two axes
    Top, Bottom,    // +z / -z
    Left, Right,    // +x / -x
    Count
};
const char* AnchorName(Anchor a);
bool AnchorFromName(const std::string& s, Anchor& out);

// WHICH PART A BONE BELONGS TO, BY ITS BRACKET TAG.
//
// Skyrim's rig names every bone `NPC L Forearm [LLar]`, and the tag inside the
// brackets is the stable half: body replacers rename the readable part, add
// twist bones and physics bones, and translate the words, but the tag is what
// animations address and it does not move. Matching on the tag also means
// `NPC Pelvis` cannot answer for `NPC Pelvis [Pelv]`, which is the exact
// mistake that once gave the skeleton two spines.
//
// Anything unrecognised is Unknown, and Unknown never holds a limb on.
Part PartOfBone(const char* boneName);

// Are these two parts jointed to each other? True for a part and itself.
// Unknown touches nothing -- see the note above.
bool PartsTouch(Part a, Part b);

// ---- HOW FAR APART TWO PARTS ARE, IN JOINTS -------------------------------
//
// PartsTouch answers one joint. This answers any number, by walking the same
// table: thigh to hip is 1, thigh to chest is 2, a whole arm (upper arm to
// hand) is 2, and a right hand to a right foot is 7 because the only way
// across is through them. Unknown is jointed to nothing, so anything involving
// it is -1.
int PartDistance(Part a, Part b);

// The widest joint-distance between any two named parts in a mask -- the
// SPAN of a piece. 0 when the mask holds one part or none, -1 never.
int PartSpan(std::uint32_t parts);

// ---- THE TEAR RULE ---------------------------------------------
//
// FIELD: on a target in Dragonsreach, a greatsword bite at their right
// shoulder took twenty-seven cells -- every cell of the joint the camera could
// see -- and the arm stayed on them, drawn and animating, held by the flesh at
// the front of the armpit that the camera could not see. The note on Part
// above says why the lattice was right by its own rules: the upper arm may
// touch the chest because a shoulder is a joint, and "once the flesh AT the
// shoulder is gone" the arm comes off. HALF the flesh at the shoulder was
// gone, and half a joint does not hold an arm.
//
// So a limb TEARS. Two counts, each against what they were born with, each
// asked only of the limb parts a wound touches:
//   the LAYER -- the cells of the hit limb part in the same one-cell slice
//   across the part's own long axis as the cells the wound takes. A bite
//   that took at least `frac` of a slice takes the rest of it: a chunk wider
//   than the arm cannot leave the arm.
//   the JOINT -- the cells of a limb part that touch a live cell of the part
//   it hangs from (upper arm off the chest, forearm off the upper arm, thigh
//   off the abdomen ...). A wound that has taken at least `frac` of them
//   takes the rest: the limb was hanging by a fraction of its joint.
// Cumulative, because the counts are against birth: the second bite at a
// shoulder tears what the first left. Limb parts only -- the head has the
// neck form, and the torso does not tear under this rule; a blade's plane
// through the torso is Lattice::TearTrunkAtPlane's. The head sweep,
// the sections and the pieces then do what they always did with cells that
// are gone.
Part PartParent(Part p);     // the part it hangs from; Unknown for head, torso, unknown
bool PartIsLimb(Part p);     // the twelve arm and leg parts


// ONE CONNECTED SECTION OF WHAT IS LEFT of THE BODY.
struct Section {
    std::vector<Key> cells;        // every cell of it, Unknown ones included
    std::uint32_t parts = 0;       // bitmask over Part of the named parts in it
    Part dominant = Part::Unknown; // the part with the most cells
    std::size_t named = 0;         // cells with a known part, which is what counts
    std::size_t flesh = 0;         // cells that hold any of THEM -- see Cell::mine
    // HOW MUCH OF EACH NAMED PART IS IN HERE, COUNTING ONLY THEM.
    //
    // The bitmask above says which parts are present; this says how much,
    // which is what tells a leg from three stray cells that happen to carry a
    // thigh bone. It counts CELLS OF THEIRS -- see Cell::mine -- and the
    // wardrobe is left out on purpose, in both directions:
    //
    //   A hat is skinned to the head bone, so its cells are Head cells. Their
    //   real head is in the lattice only as far as HF reads their face (Voxelise skips every
    //   BSDynamicTriShape), so if the wardrobe counted, Head could be mostly the hat,
    //   and knocking a hat off would read as them losing their
    //   head. They would die of losing a hat.
    //
    //   Shackles are skinned to the foot bones, so their cells are Foot cells.
    //   If the wardrobe counted, a target whose feet were gone would still
    //   "have" both feet as long as the irons were on them -- as testing
    //   showed: shackles hanging on feet that were not there, and
    //   no death for the legs they had lost.
    //
    // One rule removes both. Their own flesh is the only thing that can be a
    // limb, and the only thing whose absence can kill them.
    std::size_t minePer[std::size_t(Part::Count)] = {};
    // AND HOW MUCH OF IT IS HERE AT ALL, wardrobe included.
    //
    // Needed because of the one case the rule above gets wrong. Skyrim does
    // not draw a boot OVER their foot -- it swaps the foot mesh out and draws
    // the boot INSTEAD. So a target in boots has no foot flesh anywhere in the
    // lattice: their feet come back "0 of them, 19 worn", their birth set holds no
    // feet at all, and they cannot be killed by losing something they
    // never had. In testing, cutting their feet off did nothing and they
    // only died once the cut reached their knees, where the boot ends and their
    // calf begins.
    //
    // Which of the two counts a part is judged by is decided ONCE, at birth,
    // by whether they have any flesh there -- see Body::wornPart. A foot with
    // flesh is judged by their flesh, so irons hanging off a stump cannot keep
    // it alive; a foot that is nothing but boot is judged by the boot, because
    // there the boot IS the foot.
    std::size_t cellsPer[std::size_t(Part::Count)] = {};
    float c[3] = {0, 0, 0};        // bind-space centre
};

// Which parts this section holds `floorCells` or more of THEIR OWN cells in.
inline std::uint32_t PartsOver(const Section& S, std::size_t floorCells) {
    std::uint32_t m = 0;
    for (std::size_t p = 1; p < std::size_t(Part::Count); ++p)
        if (S.minePer[p] >= floorCells) m |= 1u << p;
    return m;
}

// SPLIT WHAT IS STILL ALIVE INTO ANATOMICALLY CORRECT SECTIONS.
//
// `mask` is the set of layers that count as a cell being alive at all. EVERY
// caller in the sweep passes kAllLayers, bone included, and that is correct:
// DepthMask(3) has returned kAllLayers since the lining became bone, so a deep
// wound DOES take the bone of the cells it removes, and a cell whose only
// surviving layer is bone is still a cell that is there.
//
// Sections come back with the one holding the chest first, then largest first. An intact body must come back as exactly
// ONE of them; if it does not, this map is wrong and the caller is expected to
// say so and refuse to act on it rather than dismember somebody on a bug.
// `parts`, when non-zero, is a bitmask over Part that restricts the pass to
// those parts alone -- the connectivity of ONE piece of their anatomy, judged
// without the rest of their body being allowed to hold it together. It exists
// for the head: their head is a hollow shell of face skin over nothing (a target
// with no head fill has a skull count of zero), its lower rim reaches down the
// neck to their chest, and so two fragments of skull on opposite sides of a cut
// are still ONE section of the whole body -- joined the long way round, under
// their jaw. Asking the question over Head cells alone is what tells a piece of
// their head that is still on them from one that is hanging in the air beside it.
//
// NEVER SET THE Unknown BIT IN `parts`. The rider pass below claims unnamed
// cells TRANSITIVELY -- each one it claims is pushed back onto the queue and
// claims its own neighbours -- and with a filter on, the named parts in the
// mask are the only claimants there are, so nothing bounds the chain. One
// named cell will tow every unnamed cell connected to it. Measured, with a
// head-only filter: a five-cell chip of skull took a forty-three-cell cloak
// off them, down to their ankles. Unfiltered this cannot happen, because every
// other named part of them is in the index and competing for those cells.
std::vector<Section> Sections(const Lattice& L, std::uint32_t mask, std::uint32_t parts = 0);
// WHAT A REBUILD'S CARRIED WOUNDS LEFT STANDING ON ITS OWN: every section
// under `floorCells` that holds trunk, except the largest, loses every layer and
// goes into `ledger` so the next rebuild takes it too; returns how many cells
// went. Trunk, because a chip of it is what does harm: the loss rule reads it as
// their trunk cut in half, and Sections() ranks a chest cell over everything, so
// it would outrank the body it came off. A hand a `nosever` wound holds on them
// is neither, and stays. Size alone says which stays of the rest.
std::size_t TakeScraps(Lattice& L, std::size_t floorCells, std::map<Key, std::uint32_t>& ledger);

// ---- AND THE RULE THAT USES IT --------------------------------------------
//
// A severed section is whatever stayed connected after a cut, which for a
// bisection is an entire side of the body: one rigid object holding an arm and a
// leg joined through the pelvis, standing where it lands. In testing it
// looked like a mannequin: a whole half body is furniture, not
// gore.
//
// So a section wider than `maxSpan` joints is split into pieces that are not.
// At a span of 2 a whole arm (2) and a whole leg (2) survive intact, thigh
// plus hip plus abdomen (2) survives, and a hand-to-foot section (7) comes
// apart into the arm, the leg and what is left of the trunk.
//
// Returns S alone when it already fits, or when maxSpan < 1 (off). Sub-
// sections come back largest first, with every tally rebuilt from the lattice
// so a caller cannot tell them from sections Sections() made itself. Cells
// with no named part behind them -- a sleeve, a chain -- ride with the group
// their nearest named neighbour went to.
std::vector<Section> SplitBySpan(const Lattice& L, const Section& S, int maxSpan);

// WHICH NAMED PARTS THIS SECTION HOLDS AND NO OTHER SECTION DOES.
//
// This is the test: a dismemberment is when a
// NAMED PART of the body is separated from another named part. Not when some
// flesh comes loose -- a wound always leaves scraps, and a single cell of skin
// off a fingertip is a scrap however disconnected it is. The difference
// between a scrap and a limb is not size, it is completeness: the scrap's part
// is still on them (the rest of that hand is right there), and the limb's is
// not.
//
// Measured: at a five-unit lattice, two of eight hundred and sixty-eight cuts
// produced a one-cell section of skin at a fingertip, from wounds too shallow
// to reach muscle. A size floor would have hidden those behind a number; this
// rejects them because the hand they came off is still attached, which is the
// actual reason they are not dismemberments.
std::uint32_t SoleParts(const std::vector<Section>& secs, std::size_t i);

// MAKE THEM ONE BODY, BY CONSTRUCTION.
//
// A target does not arrive as one connected thing, and the reason is mundane:
// their head is a different mesh. The body ends at the neck, the head begins
// above it, and between the two there is a gap wide enough that no cell of one
// is a lattice neighbour of any cell of the other. Nothing is wrong with
// either mesh; they simply do not touch. The log said it on every single
// actor -- "they are in 2 separate section(s) already ... [1] 28 cell(s), mostly
// head" -- and everything downstream inherited it: the baseline for
// dismemberment was two instead of one, so nearly any blow that detached
// anything at all read as taking them apart.
//
// Bridging is the right fix, because the head IS attached; the lattice just
// cannot see how. Each stray section is linked to the main mass at the closest
// pair of cells between them (and every pair nearly as close, so one unlucky
// cell cannot behead them). The link goes into the adjacency graph, so it is
// removed exactly the way any other connection is: cut the neck, and the cells
// holding the bridge go with it, and the head comes off properly.
//
// Called on the WHOLE body, before any remembered damage is put back -- a
// bridge is a fact about their anatomy, not about their injuries. Returns how many
// were added.
std::size_t BridgeSections(Lattice& L, std::uint32_t mask,
                           void (*say)(const char*, ...) = nullptr);


class Lattice {
public:
    float cell = 6.0f;
    std::map<Key, Cell> cells;
    // WHAT THE CLEARANCE PASS FOUND, for the caller to log. Zero when the
    // pass is off, which is what clearGain 0 means.
    std::size_t skinPts = 0;        // skin vertices indexed
    std::size_t measuredLumps = 0;  // fill lumps that had any skin near them
    std::size_t shallowLumps = 0;   // of those, the ones that can surface
    std::size_t resortedCells = 0;  // cells BuildRuns had to sort (expected 0)
    // THE TRIANGLE-TO-CELL TABLE: for each shape, one entry per
    // triangle IN HARVEST ORDER (the order `tris[si]` was handed to Build,
    // which is partition by partition, each in its index-buffer order): the
    // cell's `ord`, with bit 15 set for a shallow lump, or kNoCell for a
    // triangle Build put in no cell (an impossible position, an index past
    // the buffer). A redraw can then rebuild a partition by walking ITS OWN
    // triangles in order -- sequential reads, the survivors copied straight
    // from the engine's original index list -- instead of walking every
    // cell of them to find them. Empty when the body has too many cells for
    // sixteen bits, and then the redraw walks the cells as it always did.
    static constexpr std::uint16_t kNoCell = 0xFFFF;
    static constexpr std::uint16_t kTriShallow = 0x8000;
    std::vector<std::vector<std::uint16_t>> triCell;
    std::uint32_t cellCount = 0;
    // Build's own proof of the table: false when the histogram of the table
    // disagrees with the cells (then the table is emptied and said so).
    bool triCellProven = false;
    // Group every cell's `tris` by shape into Cell::runs. Called at
    // the end of Build; safe to call again on any lattice whose `tris` changed.
    void BuildRuns();
    void ProveTriCell();

    // WHAT THE TEAR RULE MEASURES AGAINST, written at the end of
    // Build when every cell is alive: per part, its long axis (the principal
    // axis of its cell centroids) and their mean, and for a limb part the
    // number of its cells that touch a cell of the part it hangs from. Zero
    // for a part they do not have.
    float partAxis[std::size_t(Part::Count)][3] = {};
    float partOrigin[std::size_t(Part::Count)][3] = {};
    std::uint32_t partCellsBirth[std::size_t(Part::Count)] = {};
    std::uint32_t jointBirth[std::size_t(Part::Count)] = {};
    void ComputeTearBirth();
    // Append to `sel` the cells the tear rule takes with it -- the rest of
    // any slice, then the rest of any joint, that the selection leaves under
    // 1 - frac of its birth count -- and return how many. `sel` is read as
    // "about to go"; nothing here changes a cell. `say` is the log, or null.
    std::size_t Tear(std::vector<Key>& sel, float frac,
                     void (*say)(const char*, ...) = nullptr) const;
    // THE TRUNK ACROSS A CLEAVE. The rule above leaves the torso
    // alone, and a reach-bounded cleave (SelectPlane with a reach)
    // stops where its reach ends. FIELD: a
    // greatsword landed on their right upper arm, the plane took the chest's
    // band out to its 36 units and severed 131 cross-plane links -- and the
    // upper body stayed on them, joined to the hips by the far side the blade
    // never reached, drawn floating over the gap. So, for the plane the LAST
    // SelectPlane() recorded with a reach: if this selection leaves standing at
    // most half of what `frac` lets a limb keep -- a quarter at 0.5 -- of their
    // own trunk cells (chest and abdomen, within the plane's part scope) in
    // that plane's own band, against what they were born with, AND live trunk
    // of theirs stands on both sides of the band -- at least a
    // tenth of it on the lesser side, so a plane through the last rows of their
    // belly or between their thighs has nothing to part -- the cut went
    // THROUGH. The rest of the band is appended to `sel` and the recorded reach
    // grows to the whole band plus an arm's thickness, so SeverPlane() cuts what
    // held the two sides together (the far side, an arm or a garment lying
    // against it) and no limb further off. Otherwise the cut is the gash it was
    // and nothing changes. Returns how many cells it appended; a spell's
    // whole-body plane (no reach) or no recorded plane returns 0.
    std::size_t TearTrunkAtPlane(std::vector<Key>& sel, float frac,
                                 void (*say)(const char*, ...) = nullptr) const;

    // WHERE Form::Neck DECIDED THEIR HEAD JOINS THEM. The form works out
    // the join height itself and the wound log only ever printed the ANCHOR,
    // which for Decapitate is the centre of their whole body and has nothing to
    // do with it -- so five failed decapitations in testing left no line
    // saying where the cut actually went. Written by Form::Neck, read by the
    // wound log, meaningless until one has run.
    // Triangles Build refused because their centroid was not a place on a
    // body (see the guard there). The caller prints it; a non-zero value is
    // always a bug somewhere upstream, never a normal condition.
    std::size_t insaneTris = 0;
    mutable float lastJoinZ = 0.0f;
    mutable float lastPlaneP[3] = {0.0f, 0.0f, 0.0f};
    mutable float lastPlaneN[3] = {0.0f, 0.0f, 0.0f};
    mutable std::uint32_t lastPlaneParts = 0;
    mutable bool haveLastPlane = false;
    // HOW FAR FROM THE IMPACT THE LAST PLANE REACHED, in the plane.
    // 0 is a spell's slab: the whole body. SeverPlane()
    // strips cross-plane links only within it (plus a cell of slack), so a
    // cut that stops at their ribs cannot detach a leg. Written non-zero by
    // SelectPlane() alone; Select()'s top and every other plane setter write
    // 0, so a reach belongs to the ONE blow that carried it and a stale one
    // can never bound the next spell's Decapitate, Halve or Layer.
    mutable float lastPlaneReach = 0.0f;
    // HOW DEEP THE LAST REACH-BOUNDED SLAB WAS: the half-thickness
    // SelectPlane() actually took -- `a`, or the fallback band when the plane
    // fell between rows. TearTrunkAtPlane() judges the trunk's band by it, so
    // the band it measures is the band the cut took.
    mutable float lastPlaneHalf = 0.0f;
    // EVERY LINK SeverPlane() TOOK OUT, so an un-cut body gets them
    // back. Clearing `gone` makes a cell alive; it does not join it to anything,
    // and a warm Restore keeps this lattice: a target who outlived a cut (a
    // limb the preset lets them lose, NoKill) came back whole in one lattice and
    // in two sections, and the next scratch swept the smaller off them. Build
    // starts it empty, because Build's links are all there.
    struct SeveredLink { Key a, b; bool isBridge; };
    std::vector<SeveredLink> severed;
    void Rejoin();
    // A bind-space proxy for each bone: the mean position of the vertices it
    // owns. This is what lets a wound named by a BONE become a wound named by
    // a POINT, without ever needing the skeleton's bind transforms.
    std::map<std::string, std::vector<float>> boneSeed;
    float lo[3] = {0, 0, 0}, hi[3] = {0, 0, 0};

    // WHAT COUNTS AS TOUCHING. Not "near in space" -- an arm hangs a finger's
    // width from the hip, and any adjacency built out of distance alone lets a
    // wound in the forearm tear a piece out of the pelvis it never touched.
    // Two cells are neighbours here only if:
    //   (a) they share a vertex of any shape but the fill lumps -- welded
    //       by position, so that a UV seam does not read as a
    //       tear. A VERTEX MORE THAN ONE CELL FROM ITS TRIANGLE'S CELL IS NOT
    //       WELDED: a hair card is
    //       long enough that welding it joined cells two rows apart -- which
    //       stopped a one-row head slab from separating anything in testing; or
    //   (b) they are lattice neighbours, full stop. This clause used to add
    //       "AND belong to DIFFERENT shapes", on the reasoning that same-shape
    //       neighbours were already welded together -- true of a surface and
    //       false of a fill, so two cells of lumps were left joined by nothing
    //       at all. BuildAdjacency dropped the shape test.
    // Built once, when the body is voxelised.
    std::map<Key, std::set<Key>> adj;

    // BRIDGES: LINKS THAT THE ANATOMY GATE MAY NOT REFUSE.
    //
    // BridgeSections joins a stray piece of the body -- a hat, a collar, a lone
    // cell -- to their main mass at the closest pair of cells it can find. That
    // link went into `adj` and nowhere else, and Sections() walks `adj`
    // through PartsTouch(): it will not step from a hat (Head) to an upper arm
    // because a hat is not jointed to an arm. So the bridge was BUILT and then
    // IGNORED, and the log said both things one line apart --
    //
    //     bridged 28 cell(s) of head onto their main mass ... 95 link(s)
    //     NOTE: they are in 2 separate section(s) already
    //
    // -- and a body stuck at two sections has the orphan sweep switched off
    // entirely, which is how shackles end up hanging where a leg used to be.
    //
    // A bridge states that these two
    // cells were attached on the whole body, made once, before any damage. So
    // it is recorded separately and Sections walks it unconditionally. It
    // still dies the ordinary way: cut away the cells at either end and the
    // link goes with them.
    std::map<Key, std::set<Key>> bridge;
    bool Bridged(const Key& a, const Key& b) const {
        auto it = bridge.find(a);
        return it != bridge.end() && it->second.count(b) != 0;
    }

    // Build the lattice from the actor's shapes and their triangles.
    // clearGain / jointGain: a fill lump is marked SHALLOW when its distance
    // to their nearest skin vertex is under its own corner radius times this.
    // 0 turns the measurement off entirely and nothing is ever marked, which
    // is the old behaviour. jointGain applies in cells that touch a
    // cell of a different named part -- the joints, where the skin creases
    // inward under animation and the bind-pose clearance overstates the room a
    // lump actually has.
    void Build(const std::vector<ShapeData>& shapes,
               const std::vector<std::vector<TriRef>>& tris,
               float cellSize, float clearGain = 0.0f, float jointGain = 0.0f);

    std::size_t LiveCells() const;
    std::size_t LiveTris() const;
    // which layer each shape belongs to, indexed by shape
    std::vector<int> shapeLayer;

    // Live cells whose centroid lies within r of point p. Raw distance: use
    // this only where the wound really is a sphere in space.
    std::vector<Key> Within(const float p[3], float r, std::uint32_t mask) const;

    // A WOUND. Grows outward from the live cell nearest p, over cells that
    // touch each other, and stops at radius r or at maxCells.
    //
    // This is distance THROUGH THE FLESH, not through the air, and the
    // difference matters: a forearm hangs a few units from the hip,
    // so a plain sphere around the forearm also swallows a piece of the
    // pelvis, and a wound to the arm takes a bite out of the body it never
    // touched. Growing over contact cannot do that -- there are no cells in
    // the gap between the arm and the hip, so the growth stops at the arm.
    std::vector<Key> Flood(const float p[3], float r, int maxCells,
                           std::uint32_t mask, std::uint32_t parts = 0) const;

    // THE SHAPE OF A WOUND.
    //
    // Two families:
    // something that EATS and something that PASSES
    // THROUGH.
    //
    //   Bite and Scatter GROW. They start at a point in the flesh and spread
    //   over cells that touch, so they can never cross the gap between a
    //   forearm and the hip it hangs beside. This is what a chunk taken out
    //   of a body looks like.
    //
    //   Slab and Bore CUT. They are a plane and a line laid through the body,
    //   and every cell they intersect is taken whether or not it is attached
    //   to the rest -- because a blade swung at waist height goes through the
    //   waist AND through whatever arm is in front of it, and a spear that
    //   goes in the front comes out the back. Connectivity is then applied
    //   afterwards, by Islands(), so the entry wound and the exit wound
    //   become two objects rather than one impossible one.
    //
    //   Everything takes what is left.
    enum class Form {
        Bite,        // grows from the seed, radius a
        SlabX, SlabY, SlabZ,   // plane through the seed, half-thickness a
        BoreX, BoreY, BoreZ,   // line through the seed, radius a
        Scatter,     // `count` separate bites of radius a, spread over the body
        Everything,
        // ONE LATTICE LAYER, AND EXACTLY ONE.
        //
        // A horizontal cut one voxel thick, which a slab cannot promise. A
        // slab takes every cell whose CENTROID is within a of the plane, so
        // its thickness depends on where the plane happens to fall between the
        // rows: half a cell either side catches one row when the plane lands
        // on a row of centres and two when it lands between them, and shaving
        // the half down to be safe catches NOTHING in the second case. There
        // is no radius that means "one voxel".
        //
        // So this does not measure a distance at all. It finds the row the cut
        // was aimed at and takes that row -- every live cell whose lattice z
        // matches, attached or not, because a blade at that height goes
        // through everything at that height. One cell thick everywhere, by
        // construction, wherever the aim lands.
        LayerZ,
        // CUT IN HALF AT THE NAVEL, and the height is ANATOMICAL rather than
        // aimed. Every other form here takes its position from where the spell
        // landed; this one takes it from their own body, so the cut is at the
        // same place on every target however they were hit.
        //
        // The height is the mean z of their live ABDOMEN cells -- the middle of
        // the belly, which is navel height -- falling back to the mid-height
        // of whatever is still alive when they have no abdomen left to ask.
        //
        // Two things make it a BISECTION rather than a wide slab:
        //   * the band is taken WHOLE across them, never truncated by distance
        //     from the aim, because a cut that stops halfway leaves them in one
        //     piece; when the budget cannot hold the whole band the cells are
        //     dropped by VERTICAL distance instead, thinning the cut rather
        //     than shortening it.
        //   * it is at least one full lattice row thick, and by default rather
        //     more, because Neighbours() joins cells through welded surface
        //     vertices (any shape but the fill lumps) and anatomy bridges
    //     as well as the grid -- a one-row
        //     gap that the grid would separate can still be bridged by those.
        Halve,
        // COUNT, AND IT MATTERS.
        //
        // A name table shorter than the enum crashes the game at startup: with
        // the names in an array of ten entries and Halve at index ten, every log
        // line naming that wound reads one past the
        // end of the array and hands printf a garbage pointer to print as
        // %s. Sometimes the bytes past the array happen to be readable and
        // it works; when they are not, the crash log's registers hold
        // the exact format string with rax = 0x100000000.
        //
        // There is ONE table, in lattice.cpp, and the count exists so a
        // static_assert can refuse to compile if a form is ever added without
        // a name.
        // GROUND DOWN FROM THE FEET, one row at a time.
        //
        // Like Halve, the aim is not consulted at all: this takes the LOWEST
        // row of lattice they still have. On its own that is a slice off their
        // soles; applied over and over -- which is what the Grind Down spell's
        // script does -- it walks up their body until there is nothing left,
        // which is the whole effect. Sorting is by lattice z, not by distance
        // from a seed, because there is no seed.
        Grind,
        // THE TWO DIAGONALS, AND WHY THEY ARE FORMS RATHER THAN AN ANGLE.
        //
        // There are six cut directions: horizontal, vertical and
        // diagonal, each as seen from the front of the target and from its
        // side. Four of those already existed and the naming hides it, so it
        // is written out here once:
        //
        //   their axes, measured off the head mesh -- +X their left-to-right
        //   (bbox symmetric about 0), +Y forward (the face juts to +9.6
        //   against -6.4 behind), +Z up.
        //
        //   horizontal, either viewpoint     SlabZ   normal (0,0,1)
        //   vertical, seen from the FRONT    SlabX   normal (1,0,0)
        //   vertical, seen from the SIDE     SlabY   normal (0,1,0)
        //   diagonal, seen from the FRONT    DiagF   normal (1,0,1)/sqrt2
        //   diagonal, seen from the SIDE     DiagS   normal (0,1,1)/sqrt2
        //
        // A slab is a plane, and a plane is a normal -- so a diagonal is not a
        // new KIND of cut, only a normal that is not a basis vector. The three
        // existing slabs are folded into the same normal-based test below, so
        // there is one implementation of "plane through the seed" rather than
        // two that can disagree.
        //
        // The sense is fixed per form: DiagF descends from their left shoulder
        // toward their right hip as you look at them. The mirror of each is a
        // third and fourth form, not a parameter -- the config row has nowhere
        // to put an angle, and inventing a column for one cut would be a worse
        // trade than a named form that says what it does.
        DiagF, DiagS,
        // THE NECK, AND WHY A DECAPITATION IS NOT A HEAD SPELL.
        //
        // Every other head wound is locked to Head cells. This one must NOT
        // be: the cut goes through the NECK, and the neck's cells belong to
        // whichever bone owns them -- some Head, some Chest. Locking it to the
        // head would cut just above the join and leave the head sitting on a
        // stump.
        //
        // The height is anatomical, like Halve's: the lowest live Head cell
        // THAT IS THEIRS. Head-boned wardrobe -- a hat, a hood, a horn
        // -- carries Part::Head exactly as their skull does, and a hood that
        // hangs to their shoulders put the join below their neck and cut their chest
        // instead: a target survived five Decapitates in testing
        // because of it. `Cell::mine` is what separates their flesh
        // from what they are wearing, and their body's own neck skin is always
        // there to answer, whatever they wear and whatever HF is set to.
        // Everything alive within `a` of that height goes, whatever part it
        // belongs to, and the band is taken whole rather than truncated by
        // distance from the aim -- a decapitation that stops halfway is a
        // wound to the throat.
        //
        // What makes the head come OFF rather than merely vanish is that
        // nothing here forges it: taking the band disconnects everything above
        // it, Sections() then finds the head as its own island, and the
        // existing severance path drops it as an object. So this form removes
        // a collar of flesh and the dismemberment code does the rest.
        //
        // With no live Head cell OF THEIRS left -- already decapitated, or
        // wearing head-boned geometry over a head that is gone -- it selects
        // nothing rather than inventing a height, and the caller says so.
        // There is deliberately no fallback to an unfiltered scan: that would
        // find the hood again on the very next cast.
        Neck,
        // TWO HORIZONTAL CUTS WHOSE HEIGHT COMES FROM THEIR HEAD, not from the
        // aim -- the head's own Halve, and the same argument. An aimed slab
        // lands wherever the crosshair was, so the same spell is a different
        // wound every cast; a cut taken from their anatomy is the SAME cut on
        // every target however they were hit, which is what makes it a thing you
        // can point at and say "that one".
        //
        //   MidHead  the mean height of their live Head cells -- through the
        //            middle of the skull, about eye level on a human head.
        //   Crown    halfway from that middle to the top of their head, so it
        //            takes the cap of the skull off rather than the face.
        //
        // Both are HEAD-ONLY by construction: the height is measured over Head
        // cells and the band is filtered to Head cells, so neither can reach a
        // shoulder standing at the same height. That is the opposite choice
        // from Neck directly above, and for the opposite reason.
        //
        // AND UNLIKE NECK, THE HEIGHT IS NOT FILTERED TO THEIR OWN FLESH. A hat
        // is measured as part of their head here and moves both cuts -- 3 units
        // low on MidHead and 6 high on Crown, measured. Neck's fix does not
        // transfer and shipping it here would be worse; see the long note at
        // the top of this case in lattice.cpp for why, and for what it wants
        // instead.
        MidHead, Crown,
        // NOT A WOUND AT ALL, and it never reaches Select.
        //
        // Restore is dispatched in flesh.cpp before any selection happens: it
        // un-cuts every loaded body and asks the watcher to revive whoever
        // died of one. It lives in this enum only so that a config row can
        // NAME it -- the W row's form column is how a spell says what it is,
        // and a spell with no row is not a spell this engine answers at all.
        // Select returns nothing for it, defensively.
        Restore,
        // ONE LATTICE ROW, IN THE OTHER TWO AXES.
        //
        // LayerZ has said for some time why a slab cannot promise a cut one
        // voxel thick: it takes every cell whose CENTROID is within `a` of the
        // plane, so its thickness depends on where the plane falls between the
        // rows -- one row when it lands on a row of centres, two when it lands
        // between them, and nothing at all if `a` is shaved to be safe.
        //
        // That mattered little on a body two dozen cells across. It is the
        // whole problem on a HEAD, which is three cells wide at the shipping
        // cell size: the thinnest slab that reliably catches anything takes a
        // third of their skull. These are the same construction as LayerZ in the
        // other two axes -- find the row the cut was aimed at, take that row --
        // so a head can be cut one cell thick from any direction.
        //
        // ONE CELL IS STILL THE FLOOR. No form can cut finer than the lattice,
        // and at cell 4.0 a head is about three cells across. Past this, the
        // only thing that buys a finer head cut is a finer lattice.
        LayerX, LayerY,
        // EVERY JOINT AT ONCE, AND THE HEAD IN HALF.
        //
        // Design note: this form splits every named part of the
        // body from its neighbours (hand from forearm, forearm from upper arm, chest
        // from hips, at every joint) -- and, when the head is
        // in the lattice, splits it in half too.
        //
        // The seam between two named parts is exactly the set of cells that
        // are NEIGHBOURS in the graph Sections() walks -- weld or grid,
        // touching by the joint table or bridged -- and belong to different
        // parts. Both sides of every seam are taken, so after the cut no
        // cross-part link is left for the flood fill to cross and every part
        // falls out as its own section. The head is then cut one row thick
        // through its own centre, the same row BisectSkull takes, so it
        // leaves as two halves rather than one.
        //
        // Not aimed and not budgeted: `p`, `a`, `count` and `maxTotal` are
        // ignored, because a seam left standing is a limb left attached.
        Detonate,
        Count,
    };
    static bool FormFromName(const std::string& s, Form& out);
    // The name of a form, bounds-checked. Never indexes blindly: an unknown
    // form logs as "?" rather than dereferencing whatever follows the table.
    static const char* FormName(Form f);
    // The fixed normal of one of the five slab forms (SlabX/Y/Z, DiagF/S),
    // exactly as Select() has always used it -- one source of truth, so a
    // blow in flesh.cpp that wants to know which way a form cuts asks here
    // and cannot disagree with the lattice. False for any other form, and
    // `out` is zeroed.
    static bool SlabNormal(Form f, float out[3]);
    // A PLANE WITH ITS OWN NORMAL AND A REACH. `n` is a
    // normal IN BIND SPACE (normalised here when it is not unit), `a` the
    // half-thickness exactly as a slab's `a`, `reach` the in-plane radius
    // about `p` that the cut extends to -- 0 is across the whole body, which is
    // every spell's slab. Select()'s five slabs are this with the
    // form's fixed normal and reach 0. Records the plane, its parts and its
    // reach for SeverPlane(), as the slabs always recorded the plane.
    // A zero or non-finite `n` is taken as (0,0,1) -- a horizontal cut,
    // SlabZ, the default for a blow -- and a plane IS recorded for
    // SeverPlane(). A caller that wants "no direction, no cut" must test its
    // normal first.
    std::vector<Key> SelectPlane(const float p[3], const float n[3], float a, float reach,
                                 int maxTotal, std::uint32_t mask,
                                 std::uint32_t parts = 0) const;

    std::vector<Key> Select(Form f, const float p[3], float a, int count,
                            int maxTotal, std::uint32_t mask,
                            std::uint32_t parts = 0) const;
    // Every live cell (the whole remaining body).
    std::vector<Key> All(std::uint32_t mask) const;
    // Resolve an anchor over the live cells of `parts` (0 = the whole body).
    // False when they have no living cell in those parts to anchor on, which is
    // a spell that should say so rather than land somewhere arbitrary.
    bool PartAnchor(std::uint32_t parts, Anchor a, std::uint32_t mask,
                    float out[3]) const;
    // Live cells whose owning bone is in the given set.


    // Split a selection into connected islands, each at most maxCells big.
    // Adjacency is the lattice's own (Neighbours) inside the selection, so two lumps that
    // do not touch never end up in the same object.
    std::vector<std::vector<Key>> Islands(const std::vector<Key>& sel, int maxCells) const;
    // Fuse islands that touch into single pieces of at most `perPiece` of
    // them, taking the fullest groups first: fewer, bigger things on the
    // floor rather than a scatter of small ones.
    std::vector<std::vector<Key>> Fuse(const std::vector<std::vector<Key>>& isl,
                                       int perPiece) const;
    // A SLIVER IS NOT WORTH AN OBJECT. Absorb every island smaller than
    // `minCells` into a neighbour it TOUCHES, smallest into smallest, until
    // none is left that can be absorbed.
    //
    // Fuse merges by COUNT of islands -- three of them, whatever their size --
    // so three single cells came out as a three-cell speck and stayed one
    // object. This merges by SIZE, which is the thing that actually costs:
    // every piece, however small, is a pool record, a PlaceAtMe, a
    // SetPosition, a file and a 3D load, and a test log had 18 of 65 chunks
    // at three cells or fewer. One of them was twelve vertices.
    //
    // Only TOUCHING islands are merged. Two lumps that do not touch would
    // become one rigid object with a collision hull bridging the gap between
    // them, which is a floating pair rather than a piece of a person. An
    // island that stays under the minimum with nothing to join keeps its own
    // piece: nothing is ever dropped here.
    std::vector<std::vector<Key>> AbsorbSmall(const std::vector<std::vector<Key>>& isl,
                                              std::size_t minCells) const;

    struct PeelReport {
        std::uint32_t armourPeeled = 0;
        std::uint32_t skinPeeled   = 0;
        std::uint32_t fleshPeeled  = 0;
        std::uint32_t bonePeeled   = 0;
        std::uint32_t skinExposed  = 0;
        std::uint32_t fleshExposed = 0;
        std::uint32_t boneExposed  = 0;
    };

    void MarkGone(const std::vector<Key>& sel, std::uint32_t mask);
    std::size_t SeverPlane();
    std::uint32_t PeelStageMask(const std::vector<Key>& sel, std::uint32_t mask, int maxStages = 1) const;
    void PeelGone(const std::vector<Key>& sel, std::uint32_t mask, int maxStages = 1,
                  PeelReport* rep = nullptr);
    void BuildAdjacency(const std::vector<ShapeData>& shapes);
    const std::set<Key>& Neighbours(const Key& k) const;
    bool Seed(const std::string& bone, float out[3]) const;
    // The nearest cell that still has removable flesh in it, and how far away
    // it is. A wound whose seed lands outside every live cell is a cast that
    // silently does nothing, so the seed is always checked against this.
    bool NearestLive(const float p[3], std::uint32_t mask, float out[3],
                     float* dist, int* liveCount, std::uint32_t parts = 0) const;
};

}  // namespace flesh
