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

// WHAT A SHAPE IS, AS THE RIND READS IT (Solidify, in chunknif.cpp).
//   skin                  their own skin, the body's or their face's. It takes
//                         the rind in every piece it is in.
//   layer 4, not skin     worn armour or clothing. Rinded in a piece that has
//                         none of their body's skin (their face does not
//                         count: it closes their head, not the volume under
//                         a cuirass or a helmet), and in a chunk that asks
//                         for it (Chunk::rindWorn).
//   layers 1-3, not solid an interior shell that is not a filled volume.
//                         Rinded only in a piece with none of their body's
//                         skin.
//   layer 0, not skin     their hair, eyes, brows or mouth. Written as it
//                         arrives and never rinded, in any piece.
struct Shape {
    std::string name;
    std::uint64_t desc = 0;
    std::uint32_t vsize = 0;
    bool skin = false;                    // body/skin rather than armour
    bool face = false;                    // skin that is their FACE: it closes their head and spares no worn shell the rind
    int  layer = 0;                       // 0 outer, 1 fat, 2 muscle, 3 bone
    bool solid = false;                   // already a filled volume, not a shell
    bool blood = false;                   // the splatter shell: alpha-blended
    std::vector<std::uint8_t> vdata;      // records, source skinning intact
    std::vector<std::uint16_t> tris;      // 3*n local indices
    std::vector<std::string> tex;
    // THE FACE AND ITS ACCESSORIES (cfg FT). All default off, so a shape
    // nobody fills in builds exactly as before.
    bool accessory = false;               // a non-face shape the face reader read (hair, brows, eyes, mouth, worn dynamic gear)
    int  feature = -2;                    // its material's GetFeature answer as the reader got it (-2 none)
    bool hasMatTint = false;              // matTint was read off its live material
    float matTint[3] = {1.0f, 1.0f, 1.0f};
    std::vector<std::string> liveTex;     // the face's texture list AS READ, before FaceTexForPiece (FT col 1); empty otherwise
};

struct Chunk {
    std::vector<Shape> shapes;
    // RIND THE WORN SHELLS AS WELL AS THEIR SKIN. Skin spares the clothing
    // over it because it closes the volume under that clothing. A piece that
    // is a whole side of them holds a bare hand and an armoured trunk at once,
    // and the hand's skin closes nothing under the cuirass.
    bool rindWorn = false;
};

// WHAT THE LAST BUILD ACTUALLY DID, so the log can answer "why is this piece
// the wrong colour".
//
// Under SetRigid(1), shapes on the type-5 skin-tint block (cfg S 1) or type-4
// FaceGen block (cfg FT col 1) keep their skeleton so the game draws them
// skinned like the live body and head, while meat, bone, hair, accessories,
// worn gear and S 0 shapes drop it inside the same NIF (`rigid` is true when
// every shape in the piece went rigid). On S 0 a vertex colour tints rigid
// skin shapes directly. All of it is decided here out of the source geometry.
struct BuildStat {
    bool rigid      = false;   // true iff every shape in the piece went rigid
    int  shapes     = 0;
    int  skinShapes = 0;       // shapes classified as their skin
    int  tinted     = 0;       // of those, how many actually carry their colour
    int  skinBlock  = 0;       // of those, how many are on the skin-tint block
    int  clipped    = 0;       // vertex-coloured ones cut off at white: their
                               // skin is lighter than a vertex colour can show
    int  faceGen    = 0;       // faces on the FaceGen (type-4) block (FT col 1)
    int  hairTint   = 0;       // accessories on the hair-tint (type-6) block (FT col 2)
    int  accSkin    = 0;       // feature-5 accessories on the skin-tint block (FT col 2 = 2)
    int  cutout     = 0;       // shapes given an alpha test (FT col 3)
    int  normals    = 0;       // accessories given normals and tangents (FT col 4)
    int  dedup      = 0;       // duplicate accessory shapes dropped (FT col 5)
    const char* why = nullptr; // why the last Build returned nothing (null when it built a piece)
};
BuildStat LastBuild();

// THE FACE AND ITS ACCESSORIES (cfg row FT). Every argument 0 is the bytes
// every piece had before the row existed.
//   maps     1: a face whose live texture list passes FaceGenTexOK is written
//              skinned on the FaceGen (type-4) block with its detail (3) and
//              tint (6) maps, regardless of SetRigid or SetTintGain.
//   hair     1: feature-6 accessories with normals go on the hair-tint block in
//              their live colour; 2: also feature-5 accessories (non-MSN) on
//              the skin-tint block in their own colour. An accessory's record
//              has no normals until `normals` 1 gives it them, so hair needs
//              normals; LoadConfig (CheckFaceLook) turns hair off without it.
//   cutout   1: feature-6 accessories get an alpha test, 0x12EC threshold 128.
//   normals  1: accessories with no normals are rebuilt with normals and
//              tangents (the meat format).
//   dedup    1: an accessory shape identical to an earlier one is dropped.
void SetFaceLook(int maps, int hair, int cutout, int normals, int dedup);

// A FACE'S LIVE TEXTURE LIST FIT FOR THE FACEGEN BLOCK: slots 0, 1, 2, 3, 6
// and 7 all filled; slot 3 not a subsurface, specular or normal map (_sk, _s,
// _msn) and not a copy of slot 0, 1 or 2; slot 6 a FaceTint map (the path
// holds "facetint"). Pure, shared by the reader's log line and the forge.
bool FaceGenTexOK(const std::vector<std::string>& t);

// Shader path for skin shapes: 0 = the ordinary lighting shader with model
// space normals, their colour arriving as a vertex colour on rigid skin;
// 1 = the skin-tint (type-5) block, written skinned with their colour in the
// block itself whenever their tint and _sk/_s maps are present.
void SetSkinShader(int mode);

// THEIR SKIN COLOUR, for the pieces that come off them.
//
// A forged shard's shader is a fixed template, so without this every piece
// would wear the template's tint -- white -- whatever their skin. This hands
// the engine's measured value (material + 0xA0 on their
// live skin shader) to the forge, which writes it into the vertex colour lane
// or, on the skin path, into the block.
//
// Passing null says "no tint was readable from this body". That is not the
// same as white: without a tint the skin path is NOT used at all, because a
// skin-tint shader with no tint written is a skin shader with white skin, and
// the piece comes out bleached. No tint, no skin block.
void SetSkinTint(const float rgb[3]);

// HOW HARD THEIR COLOUR IS APPLIED, as a multiplier on the vertex colour their
// tint becomes on the ordinary lighting shader. That colour is already the
// multiplier that matches the skin shader's blend (SkinVertexColour in
// chunknif.cpp), so 1.0 is the default and the expected answer. It stays a
// config number so a piece can be nudged without a rebuild; it cannot take a
// channel past white.
//
// A gain of zero or less TURNS THE VERTEX COLOUR LANE OFF ENTIRELY on the
// ordinary lighting path (S 0) -- those rigid shapes go back to the exact bytes
// they had before tinting. Skin-tint (S 1) and FaceGen (FT col 1) shapes are
// written skinned and need no vertex-colour lane. A new vertex
// channel the engine refuses does not draw badly: the shape silently fails to
// build and nothing spawns at all. This file has been bitten by that twice
// already, so the off switch belongs somewhere that does not need a rebuild to
// reach.
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

// PER-SHAPE SKELETON STRIPPING, unless turned off.
//
// 1 (the default) writes every non-skin/non-face shape -- meat, bone, Solidify
// sheets and bands, hair, accessories, worn gear, and S 0 skin shapes -- as an
// unskinned BSTriShape (3 blocks) with its geometry inline and its positions
// rebased onto the chunk's origin, while keeping only type-5 skin-tint (S 1)
// and type-4 FaceGen (FT col 1) shapes (and any un-strippable layout) skinned
// (6 blocks, weighted 1.0 to bone 0 at -C) inside the same NIF. 0 writes every
// shape skinned, as a one-line retreat.
void SetRigid(int on);

// NO DECALS: every shape's NiAVObject flags carry bit 10, so the
// engine's decal projection skips the piece. Off restores the 0x0008000E header
// without bit 10.
void SetNoDecals(bool on);

// THE UNIQUENESS NUDGE (cfg S column 4; off by default). On: every type-5
// skin-tint block of a Build -- their skin's and a feature-5 accessory's
// (FT hair 2) -- gets uvOffset.x = (n % 1024 + 1) * 2^-24, n stepping once
// per Build, so pieces' materials differ in one field a tint-blind key may
// cover. The type-6 hair-tint block is not nudged. Off: output byte-identical
// to a build without this switch.
void SetUniqueSkin(bool on);

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
