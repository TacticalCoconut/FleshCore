// chunknif.h -- write one separated chunk out as a physics-enabled NIF.
//
// A chunk is a handful of cells' worth of triangles, lifted straight out of
// the actor's live vertex buffers. It arrives here still carrying the original
// records byte for byte -- the same positions, UVs and normals the game was
// drawing a frame ago -- so what lands on the ground is literally the geometry
// that was on the body, wearing the body's own textures.
//
// Three things happen here and nowhere else:
//   1. THE PIECE IS MADE SOLID. A chunk cut out of a body is a patch of a
//      SHELL -- a surface with no thickness at all -- and a surface in this
//      engine is drawn from one side only: turn it round and it is not merely
//      unlit, it is not there. Capping its boundary loops with a lid does not
//      fix that, because a lid is another surface with no thickness. So the
//      patch is given a real inside: its own copy pushed inward along the
//      surface, wound the other way, and a wall band stitched between the two
//      around every open edge. What lands on the floor is a closed volume with
//      skin on the outside and meat on the inside and around the cut, and it
//      reads as solid from every angle because it IS solid.
//   2. IT IS RE-ROOTED. Its positions are rebased onto the chunk's own centroid
//      (skinned: one bone at weight 1 carries minus that centroid), which puts the
//      geometry around the object's origin where its collision lives.
//   3. IT IS GIVEN MASS AND A HULL. The hull is a box oriented along the
//      chunk's own principal axes; the mass comes from the mesh's signed
//      volume at the density of a shipping limb prop.
//
// PURE. No engine calls, no Windows. This file compiles unchanged into the
// SKSE plugin or a native test build.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace chunknif {

struct Shape {
    std::string name;
    std::uint64_t desc = 0;
    std::uint32_t vsize = 0;
    bool skin = false;                    // body/skin rather than armour
    int  layer = 0;                       // 0 outer, 1 fat, 2 muscle, 3 bone
    bool solid = false;                   // already a filled volume, not a shell
    bool blood = false;                   // the splatter shell: alpha-blended
    std::vector<std::uint8_t> vdata;      // records, source skinning intact
    std::vector<std::uint16_t> tris;      // 3*n local indices
    std::vector<std::string> tex;
};

struct Chunk {
    std::vector<Shape> shapes;
};

// WHAT THE LAST BUILD ACTUALLY DID, so the log can answer "why is this piece
// the wrong colour".
//
// The tint reaches a shape only if the whole FILE went rigid and that shape is
// skin, and both of those are decided in here out of the source geometry. From
// outside all that is visible is a beige shard, and an untinted
// piece and a piece with no skin in it both look beige.
struct BuildStat {
    bool rigid      = false;   // the file kept its skeleton, or lost it
    int  shapes     = 0;
    int  skinShapes = 0;       // shapes classified as their skin
    int  tinted     = 0;       // of those, how many actually carry their colour
};
BuildStat LastBuild();

// Shader path for skin shapes: 0 = ordinary lighting shader with model space
// normals (a chunk on the ground has no actor tint for the skin path to
// sample and comes out bleached), 1 = the shipping skin-tint block.
void SetSkinShader(int mode);

// THEIR SKIN COLOUR, for the pieces that come off them.
//
// A forged shard's shader is a fixed template, so without this every piece
// would wear the template's tint -- white -- whatever their skin. This hands
// the engine's measured value (material + 0xA0 on their
// live skin shader) to the forge, and the skin path writes it into the block.
//
// Passing null says "no tint was readable from this body". That is not the
// same as white: without a tint the skin path is NOT used at all, because a
// skin-tint shader with nothing to sample is the bleached-chunk bug
// SetSkinShader's comment above describes. No tint, no skin block.
void SetSkinTint(const float rgb[3]);

// HOW HARD THEIR COLOUR IS APPLIED, as a multiplier on the tint before it is
// written into the vertices. The lighting shader multiplies the diffuse by the
// vertex colour, and their tints are eight-bit skin values against the standard
// body texture, so 1.0 -- a plain multiply -- is the default and the expected
// answer. It is a knob only because whether the ENGINE's own skin path adds a
// gain of its own is the one link in this chain that could not be measured
// here, and a wrong guess would be a rebuild rather than a config line.
//
// A gain of zero or less TURNS VERTEX TINTING OFF ENTIRELY -- the pieces go
// back to the exact bytes they had before tinting. A new vertex channel the engine
// refuses does not draw badly: the shape silently fails to build and nothing
// spawns at all. This file has been bitten by that twice already, so the off
// switch belongs somewhere that does not need a rebuild to reach.
void SetTintGain(float gain);

// IS THIS PIECE DEBRIS, OR IS IT A LIMB?
//
// Debris is put on layer 19, L_DEBRIS_SMALL, with Havok's DEBRIS quality:
// off the dead-biped layer the corpse is on, and with continuous collision
// detection disabled. A shard spawns inside the body it was cut from, so its
// collision shape begins fully penetrating the ragdoll's; asked to resolve
// that between two dead bipeds with CCD on, several times in one frame, Havok
// shoves them apart hard enough to throw the corpse across the room.
//
// A severed limb keeps the template's L_DEBRIS_SMALL and MOVING: it IS a body
// part, and it arrives alone rather than in a handful.
void SetDebris(bool on);

// A FORGED PIECE HAS NO SKELETON, unless this is turned off.
//
// 1 (the default) writes each shape as an ordinary unskinned BSTriShape with
// its geometry inline and its positions rebased onto the chunk's own origin:
// no skin instance, no skin data, no skin partition, and twelve fewer bytes in
// every vertex record. Two and a half times smaller, which decides
// whether a piece wins the race to open its own file. 0 restores the skinned
// form, as a one-line retreat if play
// disagrees with the parser.
void SetRigid(int on);

// NO DECALS: every shape's NiAVObject flags carry bit 10, so the
// engine's decal projection skips the piece. Off restores the 0x0008000E header
// without bit 10.
void SetNoDecals(bool on);

// The lattice cell a chunk was cut out of. A piece is never made thicker than
// half of one, because it has no business being thicker than the volume it
// came from.
void SetCellSize(float cell);

// The wound texture painted on every closed boundary.
void SetGoreTextures(const std::string& diffuse, const std::string& normal);

// Build the file. Empty return means refused: degenerate, implausibly large,
// or too many shapes to be one object.
std::vector<std::uint8_t> Build(const Chunk& c, float* massOut);

// Shared with the engine side so both agree on where a vertex is.
void PosOf(const std::uint8_t* rec, std::uint64_t desc, float out[3]);

}  // namespace chunknif
