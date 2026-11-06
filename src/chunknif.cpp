#include "chunknif.h"
#include "blobs.h"
#include "redraw_bits.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <map>
#include <unordered_map>
#include <utility>

namespace chunknif {

static int   g_skinShader = 0;
static bool  g_debris = false;
static bool  g_haveTint = false;
static float g_tint[3] = {1.0f, 1.0f, 1.0f};
// A multiplier on their tint before it becomes a vertex colour. The lighting
// shader multiplies the diffuse by the vertex colour, and their measured tints
// are ordinary eight-bit skin values -- (221,221,221) pale, (143,114,101) tan,
// (73,73,100) the dark elf -- so a plain multiply against the standard body
// texture is what reproduces them. This exists because that is the ONE step of
// the chain not measured here: whether the skin-tint shader
// applies its own colour with a gain. It is a config number so testing can
// answer that without a rebuild, and 1.0 is the default.
static float g_tintGain = 1.0f;
// AND THE WAY OUT, WITHOUT A REBUILD.
//
// A rigid shape that declares a channel the engine dislikes does not draw
// wrong -- it never builds, and nothing spawns at all, silently. That is the
// failure this file has already been bitten by twice (the shader length, then
// SLSF1_Skinned), and it is the reason a new vertex channel gets an off
// switch that lives in the config rather than in the source. A gain of zero
// or less in the cfg's S line turns vertex tinting off and the pieces go back
// to the bytes they had before vertex tinting.
static bool  g_vcTint = true;
static BuildStat g_lastBuild;
// The fallback if the config does not say. NOT the Dismembering Framework
// atlas any more: a chunk's inner face and wall band are mapped by distance
// and tiled, and that atlas is 19.8% near-white, so tiling across it painted
// blank background onto the meat.
static std::string g_goreD = "Textures\\FleshCore\\flesh_muscle.dds";
static std::string g_goreN = "Textures\\FleshCore\\flesh_muscle_n.dds";

void SetSkinShader(int m) { g_skinShader = (m == 1) ? 1 : 0; }
BuildStat LastBuild() { return g_lastBuild; }
void SetTintGain(float g)
{
    g_vcTint   = (g > 0.0f);
    g_tintGain = (g > 0.05f && g < 8.0f) ? g : 1.0f;
}
void SetDebris(bool on) { g_debris = on; }
void SetSkinTint(const float rgb[3])
{
    g_haveTint = rgb != nullptr;
    if (rgb) { g_tint[0] = rgb[0]; g_tint[1] = rgb[1]; g_tint[2] = rgb[2]; }
    else     { g_tint[0] = g_tint[1] = g_tint[2] = 1.0f; }
}
// How many bind-space units one tile of the flesh texture covers. The gore
// textures are made tileable on purpose, so a coordinate past the edge
// wraps cleanly instead of clamping -- which is what lets a wall band be
// mapped by real distance rather than squeezed into [0,1].
static const float kGoreTile = 24.0f;
static float g_cell = 6.0f;
void SetCellSize(float c) { g_cell = (c > 0.5f && c < 64.0f) ? c : 6.0f; }
void SetGoreTextures(const std::string& d, const std::string& n) { g_goreD = d; g_goreN = n; }

static float HalfToFloat(std::uint16_t h)
{
    const int s = (h >> 15) & 1, e = (h >> 10) & 0x1F, m = h & 0x3FF;
    float v;
    if (e == 0)       v = std::ldexp(float(m), -24);
    else if (e == 31) v = m ? NAN : INFINITY;
    else              v = std::ldexp(float(m + 1024), e - 25);
    return s ? -v : v;
}

void PosOf(const std::uint8_t* rec, std::uint64_t desc, float out[3])
{
    if (((desc >> 8) & 0xF) == 2) {
        const std::uint16_t* h = reinterpret_cast<const std::uint16_t*>(rec);
        out[0] = HalfToFloat(h[0]); out[1] = HalfToFloat(h[1]); out[2] = HalfToFloat(h[2]);
    } else {
        std::memcpy(out, rec, 12);
    }
}

// float -> IEEE binary16. The values written through this are NOT confined to
// [0,1] -- a band that is tiled runs off the edge of the texture on purpose --
// so it must handle the whole range rather than clamping.
static inline std::uint16_t HalfOf(float f)
{
    std::uint32_t bits; std::memcpy(&bits, &f, 4);
    const std::uint32_t sign = (bits >> 16) & 0x8000u;
    const std::int32_t  exp  = std::int32_t((bits >> 23) & 0xFF) - 127 + 15;
    const std::uint32_t man  = bits & 0x7FFFFFu;
    if (exp <= 0)  return std::uint16_t(sign);
    if (exp >= 31) return std::uint16_t(sign | 0x7BFFu);
    return std::uint16_t(sign | (std::uint32_t(exp) << 10) | (man >> 13));
}

static inline std::uint32_t SkinOff(std::uint64_t d) { return std::uint32_t((d >> 28) & 0xF) * 4u; }
static inline std::uint32_t UVOff(std::uint64_t d)   { return std::uint32_t((d >> 8) & 0xF) * 4u; }

// ============================== WHERE A VERTEX COLOUR LIVES, MEASURED ========
//
// The vertex descriptor packs a byte offset per channel, one nibble each,
// each holding offset/4. Three of those nibbles were already established
// here by use: n0 = vertex size, n2 = UV, n7 = skinning data. The COLOUR
// nibble was not known, and no colours were written until it was
// measured. This is that measurement.
//
// Two shipping meshes, read off disk, both carrying vertex colours:
//
//  1. Bethesda's own `dwermsmcounterhalf01byoh.nif` shape 7 --
//     desc 0003B00007650408, nibbles (n0..n7) 8,0,4,0,5,6,7,0
//       n0=8 -> stride 32       dataSize 3318 == 87*32 + 89*6, exact
//       n2=4 -> UV      @16     first halves 0x3C00/0x0000 = 1.0/0.0
//       n4=5 -> normal  @20     modal bytes 127,127,255,127 = +Z
//       n5=6 -> tangent @24
//       n6=7 -> ????    @28     TWO distinct values in 87 vertices,
//                               255,255,255,255 and 128,124,113,255 --
//                               alpha pinned at 255 in both. That is a
//                               vertex COLOUR lane and nothing else: an
//                               ambient-occlusion darkening on part of the
//                               mesh. No other lane in the record behaves
//                               remotely like it.
//       n7=0 -> unskinned, and the shape's skin reference is -1.
//
//  2. A skinned armour mesh, shape 26 -- desc 0007B0008765040B, which is the
//     disambiguating case because it has colours AND skinning at once:
//       n0=B -> stride 44   n6=7 -> colour @28   n7=8 -> skin @32
//     and 32 + 12 (four half weights + four bone indices) = 44 closes the
//     record exactly. Colour and skinning are different nibbles, colour is
//     n6, skinning is n7 -- which is the same n7 this file has always used.
//
// So: COLOUR OFFSET IS NIBBLE 6, bits 24-27, holding offset/4. The flag bit
// was already proven: VF_COLORS is bit 49 (kMeatDesc's flags decode as
// Vertex|UV|Normal|Tangent|Skinned at bits 44+, and RigidDesc clears bit 50
// for SKINNED).
static inline std::uint32_t ColOff(std::uint64_t d) { return std::uint32_t((d >> 24) & 0xF) * 4u; }

// Give a descriptor a vertex-colour channel of four bytes at `at`, which for
// a rigid record is the old skinning offset -- i.e. the end of the record,
// exactly where the counter mesh above carries its own.
//
// BOTH DESCRIPTORS THIS PRODUCES HAVE A SHIPPING PRECEDENT. Checked by
// arithmetic:
//
//   meat  RigidDesc(kMeatDesc)      = 0001B00000650407  (stride 28)
//         WithColour(that, 28)      = 0003B00007650408
//                                   == the counter mesh above, to the nibble.
//
//   skin  this body's skin shells carry no normals at all (see the meat
//         format note below), so rigid they are stride 20 and coloured
//                                   = 0002300005000406  (stride 24, col @20)
//         which is that armour mesh's shape 33, 0006300065000409, with SKINNED
//         cleared and the skin block gone: the same channel set, the same
//         UV at 16 and the same colour at 20.
//
// Both layouts are a shipping one minus the skeleton.
static inline std::uint64_t WithColour(std::uint64_t d, std::uint32_t at)
{
    d &= ~(std::uint64_t(0xF) << 24);                       // n6: colour offset
    d |=  (std::uint64_t((at / 4u) & 0xFu) << 24);
    d &= ~std::uint64_t(0xF);                               // n0: vertex size
    d |=   std::uint64_t(((at + 4u) / 4u) & 0xFu);
    d |=  (std::uint64_t(1) << 49);                         // VF_COLORS
    return d;
}

// ==================================================== A PIECE HAS NO SKELETON
//
// WHY THIS EXISTS, IN BYTES.
//
// A forged piece is a rigid object. It falls, it bounces, it lies on the floor;
// nothing about it ever bends. Yet the skinned format gives every one of them a
// full skinning rig: a NiSkinInstance, a NiSkinData with a weight per vertex,
// and a NiSkinPartition that carries the vertex buffer AGAIN alongside a bone
// palette, a vertex map and sixteen bytes of bone weights per vertex. Counted
// against the meat format, one vertex costs
//
//     40 (record) + 2 (vertex map) + 16 (weights) + 4 (indices) + 6 (skin data)
//   = 68 bytes,
//
// of which 28 exist to describe a skeleton with exactly one bone in it, at
// weight one, for every vertex. Dropping the skinning and dropping the twelve
// bytes of per-vertex skin data out of the record itself takes that to 28 --
// two and a half times smaller, before the block count falls from six per
// shape to three.
//
// A piece that loses the race to open its own
// file never appears at all, and file size decides that race. It is
// also what makes TRUE DISMEMBERMENT possible: a severed torso is a hundred
// and thirty cells, and at the old cost it came to seven megabytes.
//
// THE ONE TRAP, AND IT IS RECORDED BECAUSE IT WAS ALREADY FALLEN INTO ONCE.
// An earlier unskinned attempt failed because the vertex
// DESCRIPTOR still declared SKINNED while the shape's skin reference said -1.
// The descriptor is not decoration: the engine sizes and walks the vertex
// buffer from it. So the strip rewrites the descriptor as well --
//
//   nibble 0 = vertexSize/4        -> the smaller record
//   nibble 7 = skinning offset/4   -> zero, there is none
//   bit  50  = SKINNED             -> clear
//
// -- and the skin block is the LAST field of both formats this body uses
// (32-byte skin: skin at 20; 40-byte meat: skin at 28), so the smaller record
// is the same bytes with the tail cut off and nothing moves.
//
// Verified against three shipping unskinned meshes (markerx, marker_current01,
// marker_guardmarker): skin ref -1, nibble 7 zero, no SKINNED bit, and
// dataSize == nV*vertexSize + nT*6 exact on all three.
static int g_rigid = 1;
void SetRigid(int on) { g_rigid = on ? 1 : 0; }
// NO DECALS on the pieces: NiAVObject flag bit 10 (1024, "No Decals"
// in NifSkope's flag editor; clib NiAVObject::Flag::kNoDecals) written into
// every shape's header, so the engine's blood splash near a piece on the
// floor does not project itself over a hundred thousand triangles of it.
static bool g_noDecals = false;
void SetNoDecals(bool on) { g_noDecals = on; }

// Can this shape's record lose its skin block without anything else moving?
static inline bool Strippable(std::uint64_t desc, std::uint32_t vsize)
{
    const std::uint32_t so = SkinOff(desc);
    // HALF POSITIONS CANNOT TAKE THE REBASE. A rigid shape has no bone to
    // carry it onto its own origin, so its positions are rewritten in place --
    // twelve bytes of float32 straight over the first twelve of the record.
    // On a half-position layout (UV nibble 2, position three halves at 0) that
    // is six bytes of position and six bytes of whatever comes after it,
    // silently corrupted. Nothing on this body uses that layout, which is
    // why it would never have been noticed.
    if (UVOff(desc) == 8) return false;
    return so >= 16 && so + 12 == vsize && ((desc >> 44) & 0x40u) != 0;
}

static inline std::uint64_t RigidDesc(std::uint64_t desc)
{
    const std::uint32_t so = SkinOff(desc);          // = the new vertex size
    std::uint64_t d = desc;
    d &= ~(std::uint64_t(0xF) << 28);                // nibble 7: no skinning data
    d &= ~std::uint64_t(0xF);                        // nibble 0: vertex size
    d |= std::uint64_t((so / 4u) & 0xFu);
    d &= ~(std::uint64_t(1) << 50);                  // flags bit 6 (0x40): SKINNED
    return d;
}

// ------------------------------------------------------- the meat format
//
// WHY MEAT NEEDS A DIFFERENT VERTEX FORMAT FROM SKIN.
//
// This body's skin records carry no normal at all -- measured, bytes 12-15 of
// every one of them are zero, and the description says so: stride 32, flags
// Vertex|UVs|Skinned. Skin can afford that because its shader is Skin Tint
// with SLSF1_Model_Space_Normals, and a model-space map hands the pixel
// shader an absolute direction per texel; the geometry is never asked which
// way it faces.
//
// Meat cannot afford it. Meat is UV-mapped by distance onto a tiled gore
// texture, so their model-space map lights a chunk by whatever square inch of
// their skin the tiled coordinate happens to land on. Faces pointing at the
// camera come out shaded as though they pointed away: flat, dark, and
// see-through-looking -- which is how the pieces looked in play.
//
// Dismembering Framework's own gore limb settles it. In ONE file it ships
// skin at stride 32 with Skin Tint and an msn, and meat at STRIDE 40 --
// desc 0005B0007065040A, Vertex|UVs|Normals|Tangents|Skinned -- with a
// Default shader and a TANGENT-space _n. Its stored normals agree with its
// own geometry to a mean dot of 0.997 and its weights sum to exactly 1.000.
// Both formats are measured out of that file.
//
//   0  float3 position     12 float  bitangent.x   16 half2 uv
//   20 ubyte3 normal +  ubyte bitangent.y
//   24 ubyte3 tangent + ubyte bitangent.z
//   28 half4  weights      36 ubyte4 bone indices
static const std::uint64_t kMeatDesc = 0x0005B0007065040AULL;
static const std::uint32_t kMeatVS   = 40;

// A colour channel in [0,1] to the byte a vertex colour holds. Their tints come
// out of the engine as exact multiples of 1/255, so this round-trips them.
static inline std::uint8_t Byte255(float v)
{
    float x = v * 255.0f;
    if (x < 0.0f)   x = 0.0f;
    if (x > 255.0f) x = 255.0f;
    return std::uint8_t(x + 0.5f);
}

static inline std::uint8_t SNorm(float v)
{
    float x = (v * 0.5f + 0.5f) * 255.0f;
    if (x < 0.0f) x = 0.0f;
    if (x > 255.0f) x = 255.0f;
    return std::uint8_t(x + 0.5f);
}

// Rewrite one shape's records into the meat format, keeping its skinning and
// its UVs and giving it the normals it never had. Position, UV, weights and
// bone indices come out of the record it already carries; the frame is built
// from the shape's own triangles and its own UVs, so it is right for the
// geometry as it stands AFTER any offsetting, not as it stood before.
static void ToMeat(Shape& s)
{
    if (!s.vsize || s.desc == kMeatDesc) return;
    const std::uint32_t nV = std::uint32_t(s.vdata.size() / s.vsize);
    const std::uint32_t nT = std::uint32_t(s.tris.size() / 3);
    if (!nV || !nT) return;
    const std::uint32_t uvo = UVOff(s.desc), sko = SkinOff(s.desc);
    const bool haveUV = uvo && uvo + 4 <= s.vsize;
    const bool haveSk = sko && sko + 12 <= s.vsize;

    std::vector<float> P(std::size_t(nV) * 3), UV(std::size_t(nV) * 2, 0.0f);
    for (std::uint32_t v = 0; v < nV; ++v) {
        const std::uint8_t* r = s.vdata.data() + std::size_t(v) * s.vsize;
        PosOf(r, s.desc, &P[std::size_t(v)*3]);
        if (haveUV) {
            std::uint16_t h[2]; std::memcpy(h, r + uvo, 4);
            UV[std::size_t(v)*2]   = HalfToFloat(h[0]);
            UV[std::size_t(v)*2+1] = HalfToFloat(h[1]);
        }
    }
    std::vector<float> N(std::size_t(nV) * 3, 0.0f), T(std::size_t(nV) * 3, 0.0f);
    for (std::uint32_t f = 0; f < nT; ++f) {
        const std::uint16_t a = s.tris[f*3], b = s.tris[f*3+1], c = s.tris[f*3+2];
        if (a >= nV || b >= nV || c >= nV) continue;
        const float* A = &P[std::size_t(a)*3];
        const float* B = &P[std::size_t(b)*3];
        const float* C = &P[std::size_t(c)*3];
        const float e1[3] = { B[0]-A[0], B[1]-A[1], B[2]-A[2] };
        const float e2[3] = { C[0]-A[0], C[1]-A[1], C[2]-A[2] };
        const float fn[3] = { e1[1]*e2[2]-e1[2]*e2[1], e1[2]*e2[0]-e1[0]*e2[2],
                              e1[0]*e2[1]-e1[1]*e2[0] };
        const float d1[2] = { UV[std::size_t(b)*2]-UV[std::size_t(a)*2],
                              UV[std::size_t(b)*2+1]-UV[std::size_t(a)*2+1] };
        const float d2[2] = { UV[std::size_t(c)*2]-UV[std::size_t(a)*2],
                              UV[std::size_t(c)*2+1]-UV[std::size_t(a)*2+1] };
        const float den = d1[0]*d2[1] - d2[0]*d1[1];
        const float rr = (std::fabs(den) > 1e-12f) ? 1.0f/den : 0.0f;
        const float tg[3] = { (e1[0]*d2[1] - e2[0]*d1[1]) * rr,
                              (e1[1]*d2[1] - e2[1]*d1[1]) * rr,
                              (e1[2]*d2[1] - e2[2]*d1[1]) * rr };
        for (std::uint16_t v : { a, b, c })
            for (int k = 0; k < 3; ++k) {
                N[std::size_t(v)*3 + k] += fn[k];
                T[std::size_t(v)*3 + k] += tg[k];
            }
    }
    std::vector<std::uint8_t> out(std::size_t(nV) * kMeatVS, 0);
    for (std::uint32_t v = 0; v < nV; ++v) {
        float* n = &N[std::size_t(v)*3];
        float L = std::sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
        if (L > 1e-12f) { n[0]/=L; n[1]/=L; n[2]/=L; } else { n[0]=0; n[1]=0; n[2]=1; }
        float* t = &T[std::size_t(v)*3];
        const float d = t[0]*n[0] + t[1]*n[1] + t[2]*n[2];
        t[0] -= n[0]*d; t[1] -= n[1]*d; t[2] -= n[2]*d;
        L = std::sqrt(t[0]*t[0] + t[1]*t[1] + t[2]*t[2]);
        if (L > 1e-9f) { t[0]/=L; t[1]/=L; t[2]/=L; }
        else {                                   // no usable UV: any perpendicular
            const float a[3] = { std::fabs(n[0]) > 0.9f ? 0.0f : 1.0f, 0.0f,
                                 std::fabs(n[0]) > 0.9f ? 1.0f : 0.0f };
            const float dd = a[0]*n[0] + a[1]*n[1] + a[2]*n[2];
            t[0] = a[0]-n[0]*dd; t[1] = a[1]-n[1]*dd; t[2] = a[2]-n[2]*dd;
            L = std::sqrt(t[0]*t[0] + t[1]*t[1] + t[2]*t[2]);
            if (L > 1e-9f) { t[0]/=L; t[1]/=L; t[2]/=L; }
        }
        const float bt[3] = { n[1]*t[2]-n[2]*t[1], n[2]*t[0]-n[0]*t[2], n[0]*t[1]-n[1]*t[0] };
        std::uint8_t* o = out.data() + std::size_t(v) * kMeatVS;
        std::memcpy(o, &P[std::size_t(v)*3], 12);
        std::memcpy(o + 12, &bt[0], 4);
        if (haveUV) {
            const std::uint16_t h[2] = { HalfOf(UV[std::size_t(v)*2]),
                                         HalfOf(UV[std::size_t(v)*2+1]) };
            std::memcpy(o + 16, h, 4);
        }
        o[20] = SNorm(n[0]); o[21] = SNorm(n[1]); o[22] = SNorm(n[2]); o[23] = SNorm(bt[1]);
        o[24] = SNorm(t[0]); o[25] = SNorm(t[1]); o[26] = SNorm(t[2]); o[27] = SNorm(bt[2]);
        if (haveSk) {
            const std::uint8_t* r = s.vdata.data() + std::size_t(v) * s.vsize;
            std::memcpy(o + 28, r + sko, 8);         // four half weights
            std::memcpy(o + 36, r + sko + 8, 4);     // four bone indices
        } else {
            const std::uint16_t one = HalfOf(1.0f);
            std::memcpy(o + 28, &one, 2);
        }
    }
    s.vdata.swap(out);
    s.desc = kMeatDesc;
    s.vsize = kMeatVS;
}

// BLOODY() IS NOT CALLED: the blood is the engine's own (see Build). What it does:
//
// The outer face of a shard is their skin, and skin that has just been torn off
// a body is not clean. A second sheet is laid over each skin patch: the same
// vertices pushed 0.18 units out along their own computed normals, wearing the
// splatter texture through an alpha blend -- two thirds blood, one third hole,
// so the skin reads through between the smears. ToMeat has already done the
// hard part by then: real per-vertex normals derived from the geometry, a
// tangent frame for the splatter's own normal map, and the source skinning
// carried across so the shell is re-skinned to the shard's one bone with
// everything else.
static const char* kBloodD = "Textures\\FleshCore\\blood_splat.dds";
static const char* kBloodN = "Textures\\FleshCore\\blood_splat_n.dds";
static void Bloody(std::vector<Shape>& shapes)
{
    std::vector<Shape> add;
    for (const Shape& src : shapes) {
        if (!src.skin || !src.vsize) continue;
        if (UVOff(src.desc) == 8) continue;          // half positions: leave it
        Shape sh = src;
        ToMeat(sh);
        if (sh.desc != kMeatDesc) continue;          // conversion refused
        const std::uint32_t nV = std::uint32_t(sh.vdata.size() / kMeatVS);
        for (std::uint32_t v = 0; v < nV; ++v) {
            std::uint8_t* r = sh.vdata.data() + std::size_t(v) * kMeatVS;
            float p[3]; std::memcpy(p, r, 12);
            for (int a = 0; a < 3; ++a)
                p[a] += (float(r[20 + a]) / 127.5f - 1.0f) * 0.18f;
            std::memcpy(r, p, 12);
        }
        sh.name = src.name + "x";
        sh.skin = false;                             // plain shader, tangent maps
        sh.solid = true;                             // never rinded
        sh.blood = true;
        sh.tex = { kBloodD, kBloodN };
        add.push_back(std::move(sh));
    }
    for (Shape& a : add) shapes.push_back(std::move(a));
}

// 3x3 symmetric eigen-decomposition by cyclic Jacobi. Thirty sweeps is far
// more than a 3x3 needs and costs nothing at these sizes.
static void Jacobi3(double a[3][3], double E[3][3])
{
    E[0][0] = E[1][1] = E[2][2] = 1;
    E[0][1] = E[0][2] = E[1][0] = E[1][2] = E[2][0] = E[2][1] = 0;
    for (int sweep = 0; sweep < 30; ++sweep) {
        int p = 0, q = 1;
        if (std::fabs(a[0][2]) > std::fabs(a[p][q])) { p = 0; q = 2; }
        if (std::fabs(a[1][2]) > std::fabs(a[p][q])) { p = 1; q = 2; }
        if (std::fabs(a[p][q]) < 1e-9) break;
        const double th = 0.5 * std::atan2(2 * a[p][q], a[q][q] - a[p][p]);
        const double c = std::cos(th), s = std::sin(th);
        double R[3][3] = {{1,0,0},{0,1,0},{0,0,1}};
        R[p][p] = c; R[q][q] = c; R[p][q] = s; R[q][p] = -s;
        double T[3][3];
        for (int r = 0; r < 3; ++r) for (int c2 = 0; c2 < 3; ++c2)
            T[r][c2] = R[0][r]*a[0][c2] + R[1][r]*a[1][c2] + R[2][r]*a[2][c2];
        for (int r = 0; r < 3; ++r) for (int c2 = 0; c2 < 3; ++c2)
            a[r][c2] = T[r][0]*R[0][c2] + T[r][1]*R[1][c2] + T[r][2]*R[2][c2];
        for (int r = 0; r < 3; ++r) {
            const double e0 = E[r][0]*R[0][0] + E[r][1]*R[1][0] + E[r][2]*R[2][0];
            const double e1 = E[r][0]*R[0][1] + E[r][1]*R[1][1] + E[r][2]*R[2][1];
            const double e2 = E[r][0]*R[0][2] + E[r][1]*R[1][2] + E[r][2]*R[2][2];
            E[r][0] = e0; E[r][1] = e1; E[r][2] = e2;
        }
    }
}

// ------------------------------------------------------------------ the writer
//
// Every value this file emits goes through here, little-endian, no padding.
//
// avxform() is one NiAVObject header: flags, translation, rotation, scale. Its
// two constants are MEASURED -- read straight out of a chunk this
// code had already written and the parser had already accepted: 56 bytes, with
// flags 0x0008000E, a zero translation, an identity rotation and unit scale.
struct W {
    std::vector<std::uint8_t> b;
    void raw(const void* p, std::size_t n) {
        const std::uint8_t* q = static_cast<const std::uint8_t*>(p);
        b.insert(b.end(), q, q + n);
    }
    void u8(std::uint8_t v)   { b.push_back(v); }
    void u16(std::uint16_t v) { raw(&v, 2); }
    void u32(std::uint32_t v) { raw(&v, 4); }
    void u64(std::uint64_t v) { raw(&v, 8); }
    void i32(std::int32_t v)  { raw(&v, 4); }
    void f32(float v)         { raw(&v, 4); }
    void ident9() { for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c) f32(r == c ? 1.0f : 0.0f); }
    void avxform(std::uint32_t extraFlags = 0) {
        u32(0x0008000Eu | extraFlags);
        f32(0); f32(0); f32(0);
        ident9();
        f32(1.0f);
    }
};

// ------------------------------------------------------------------- solidify
//
// WHY A CAP WAS NEVER GOING TO BE ENOUGH.
//
// A chunk is a patch of the body's SHELL: a surface, zero units thick. Skyrim
// draws a surface from one side only, so a dropped piece was visible from
// outside and simply absent from behind -- you looked straight through where
// it was. The old fix fanned a lid across each open boundary, but a lid is
// another zero-thickness surface, so it inherited the same problem and
// only moved it.
//
// The cure is thickness. Each patch gets:
//   * its OUTER surface, untouched, still wearing their skin and their UVs;
//   * an INNER surface -- the same vertices pushed back along the local
//     surface normal and wound the other way, so it faces into the piece;
//   * a WALL BAND stitched between the two around every open edge, which is
//     the cut face of the piece and is textured as meat.
// Together those close a volume. A closed volume shows a front face to a
// viewer standing anywhere, which is what "visible from any angle" means when
// backface culling is on -- no double-sided trickery, no lids, no planes.
//
// Anything nested INSIDE that volume is then unreachable by any camera, so the
// deeper layer shells a wound carried along are dropped rather than written:
// they cost a third of the file each and cannot be seen through solid flesh.
static const float kSolidMax = 3.0f, kSolidMin = 0.6f, kSolidFrac = 0.35f;
// THE SKIN SLAB ON A PIECE THAT ALREADY HAS MEAT BEHIND IT IS NOT A 0.8 RIND.
//
// A deeper offset drives the skin through the
// lumps it is draped over, and that does not matter in the
// slightest, because both are opaque meat and the intersection is inside the
// solid. What DOES matter was measured off the game's own output: the fill only
// begins 0.80 under their skin and sits on a 2.0 grid, so a wound cell at the
// surface holds skin and almost nothing else, and a 0.8 rind over twenty units
// of patch is a 25:1 slab -- a sheet of paper landing on the
// floor. So the slab gets the same budget a piece cut out of a hollow body
// gets: as deep as the per-vertex safe march allows, capped by the
// piece's own size and by half a lattice cell.
#ifndef FC_SOLID_KEEP
#define FC_SOLID_KEEP 0.50f
#endif
// How far a triangle may swing from the way it started before a step is
// refused: 0.5 is sixty degrees. This is the whole anti-inversion mechanism --
// there is no thickness constant to tune against curvature any more.
static const float kSolidKeep = FC_SOLID_KEEP;
// HOW MANY SHAPES A CHUNK MAY CARRY. Build() refuses a chunk over this (the
// note there says why 128), and Solidify() stops rinding shells short of it
// rather than tripping it.
static const std::size_t kShapeCeiling = 128;

static void Solidify(std::vector<Shape>& shapes)
{
    if (shapes.empty()) return;

    // WHAT A FILLED BODY CHANGES HERE.
    //
    // Everything below exists to fake thickness for a piece cut out of a
    // hollow bag. A body that has been filled hands over closed boxes instead:
    // a chunk of them arrives as a solid, with meat and bone already inside it
    // and every face already wound the right way. Those shapes are left
    // untouched -- offsetting a box would drive its own six faces through each
    // other -- and the deeper layers are KEPT rather than dropped, because
    // here they ARE the volume rather than a shell hiding inside one.
    //
    // Their skin is still a surface, and it still ends in a rim at the cut. It
    // gets a thin rind so there is no gap to see between the skin and the meat
    // behind it -- thin on purpose, because a deep offset would drive it
    // straight through the boxes it is draped over.
    bool anySolid = false, anySkin = false;
    for (const Shape& s : shapes) {
        if (s.solid) anySolid = true;
        if (s.skin)  anySkin = true;
    }

    if (!anySolid) {
        int outer = 99;
        for (const Shape& s : shapes) if (s.layer < outer) outer = s.layer;
        std::vector<Shape> keep;
        for (Shape& s : shapes)
            if (s.layer == outer || s.layer == 0 || s.layer == 4)
                keep.push_back(std::move(s));
        if (keep.empty()) return;
        shapes.swap(keep);
    }

    // WHICH SHELLS GET THE RIND.
    //
    // With skin in the piece: the skin, and only the skin. Clothing over skin
    // is left alone, as it always was -- the skin under it is what closes the
    // volume. Without skin: EVERY shell. It used to be the single
    // largest shell alone.
    //
    // FIELD: a Whiterun Guard's thigh section arrived as six
    // shapes -- two merged lump solids and FOUR one-sided armour shells -- and
    // only the largest shell was extruded, so three of them were see-through
    // from inside and the section read as hollow: looking into the cut showed
    // no meat, only the far side of the armour. The skin is not in the piece
    // at all -- the slot-32 cuirass replaced the body and the interior's
    // hidden skin copy is skipped by the harvest -- so nothing else was ever
    // going to close it. A section made of ONE shell, a hand, got its rind
    // and looked right, which is why only some sections looked hollow.
    // Rinding every shell is what the targets' skin rind already does for them.
    //
    // THE CEILING. Build() refuses a chunk over kShapeCeiling shapes. A rinded
    // shell adds its inner sheet and its wall band -- and a band is a FRESH
    // SHAPE every 65,000 vertices (16,250 open edges), so a ragged shell can
    // add three or more. Nothing is booked ahead, then: the skinless shells
    // are taken largest first, each one's sheet and band(s) are built and
    // COUNTED, and the first shell that would put the piece over the ceiling
    // stops the rind -- it and the smaller shells after it stay one-sided
    // rather than sinking the piece, which is the very case the ceiling
    // exists to save (Build() returns nothing, and nothing spawns). A guard's
    // section is four to six shells, a dozen or so shapes after rinding; this
    // bites only on an outfit of fifty-odd shells. With skin present every
    // skin shell is rinded in index order, uncounted.
    std::vector<std::size_t> order;
    if (anySkin) {
        for (std::size_t i = 0; i < shapes.size(); ++i) order.push_back(i);
    } else {
        for (std::size_t i = 0; i < shapes.size(); ++i) {
            const Shape& s = shapes[i];
            if (s.solid || !s.vsize) continue;
            if (s.vdata.size() / s.vsize < 3 || s.tris.size() < 3) continue;
            if (UVOff(s.desc) == 8) continue;         // half positions: the loop below cannot author it either
            order.push_back(i);
        }
        std::sort(order.begin(), order.end(), [&](std::size_t x, std::size_t y) {
            if (shapes[x].tris.size() != shapes[y].tris.size()) return shapes[x].tris.size() > shapes[y].tris.size();
            return x < y;                             // ties resolve the same way every run
        });
    }

    std::vector<Shape> add;
    for (std::size_t oi = 0; oi < order.size(); ++oi) {
        const std::size_t si = order[oi];
        const Shape& src = shapes[si];
        if (src.solid) continue;              // a box needs nothing done to it
        if (!src.skin && anySkin) continue;   // skin carries the rind when there is skin; every shell in `order` when there is none
        if (!src.vsize) continue;
        const std::uint32_t nV = std::uint32_t(src.vdata.size() / src.vsize);
        const std::uint32_t nT = std::uint32_t(src.tris.size() / 3);
        if (nV < 3 || !nT) continue;
        if (UVOff(src.desc) == 8) continue;      // half positions: cannot author

        std::vector<float> pos(std::size_t(nV) * 3);
        float lo[3] = { 1e30f, 1e30f, 1e30f }, hi[3] = { -1e30f, -1e30f, -1e30f };
        for (std::uint32_t v = 0; v < nV; ++v) {
            PosOf(src.vdata.data() + std::size_t(v) * src.vsize, src.desc, &pos[std::size_t(v)*3]);
            for (int a = 0; a < 3; ++a) {
                const float c = pos[std::size_t(v)*3 + a];
                if (c < lo[a]) lo[a] = c;
                if (c > hi[a]) hi[a] = c;
            }
        }
        float span = 0;
        for (int a = 0; a < 3; ++a) if (hi[a] - lo[a] > span) span = hi[a] - lo[a];
        float t = kSolidFrac * span;
        if (t > kSolidMax) t = kSolidMax;
        if (t < kSolidMin) t = kSolidMin;

        // WELD BY POSITION FIRST, AND KEEP EVERYTHING BELOW WELDED.
        //
        // A body mesh carries duplicate vertices wherever its UV unwrap has a
        // seam: the same point in space with two indices, two normals and two
        // independent futures. Two things went wrong because of that, and both
        // were measured.
        //
        // The boundary of the cut was found by INDEX, so every seam counted as
        // an open edge and the band walled it -- fins standing inside the
        // solid, tens of thousands of triangles of them.
        //
        // Worse, the offset march moved each copy on its own normal, so the
        // inner sheet tore open along every seam while the outer stayed whole:
        // the piece's surface normals then failed to sum to zero by 8% of its
        // own area, in 180 of 610 pieces, and no wall could close it because
        // the hole was not at the boundary at all.
        //
        // So a welded point is one point from here on: one normal, one step,
        // one decision, applied to every copy of it.
        std::vector<std::uint32_t> wid(nV);
        std::uint32_t nW = 0;
        {
            std::unordered_map<std::uint64_t, std::uint32_t> seen;
            seen.reserve(std::size_t(nV) * 2);
            for (std::uint32_t v = 0; v < nV; ++v) {
                const float* P = &pos[std::size_t(v)*3];
                const std::uint64_t k =
                      (std::uint64_t(std::uint32_t(std::lround(P[0]*512.0f))) & 0x1FFFFFull)
                    | ((std::uint64_t(std::uint32_t(std::lround(P[1]*512.0f))) & 0x1FFFFFull) << 21)
                    | ((std::uint64_t(std::uint32_t(std::lround(P[2]*512.0f))) & 0x1FFFFFull) << 42);
                auto it = seen.find(k);
                if (it == seen.end()) { wid[v] = nW++; seen.emplace(k, wid[v]); }
                else wid[v] = it->second;
            }
        }

        // Area-weighted vertex normals, off the piece's own triangles. The
        // vertex records carry no normal to borrow -- measured: bytes 12-15 of
        // this body's format are always zero -- so the geometry is the only
        // source there is for which way is "in".
        std::vector<float> nrm(std::size_t(nV) * 3, 0.0f);
        for (std::uint32_t f = 0; f < nT; ++f) {
            const std::uint16_t a = src.tris[f*3], b = src.tris[f*3+1], c = src.tris[f*3+2];
            if (a >= nV || b >= nV || c >= nV) continue;
            const float* A = &pos[std::size_t(a)*3];
            const float* B = &pos[std::size_t(b)*3];
            const float* C = &pos[std::size_t(c)*3];
            const float u[3] = { B[0]-A[0], B[1]-A[1], B[2]-A[2] };
            const float w[3] = { C[0]-A[0], C[1]-A[1], C[2]-A[2] };
            const float n[3] = { u[1]*w[2]-u[2]*w[1], u[2]*w[0]-u[0]*w[2], u[0]*w[1]-u[1]*w[0] };
            for (std::uint16_t v : { a, b, c })
                for (int k = 0; k < 3; ++k) nrm[std::size_t(v)*3 + k] += n[k];
        }
        {   // every copy of a point gets the same normal, or they part company
            std::vector<float> acc(std::size_t(nW) * 3, 0.0f);
            for (std::uint32_t v = 0; v < nV; ++v)
                for (int k = 0; k < 3; ++k)
                    acc[std::size_t(wid[v])*3 + k] += nrm[std::size_t(v)*3 + k];
            for (std::uint32_t g = 0; g < nW; ++g) {
                float* n = &acc[std::size_t(g)*3];
                const float L = std::sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
                if (L > 1e-12f) { n[0] /= L; n[1] /= L; n[2] /= L; }
                else { n[0] = n[1] = n[2] = 0.0f; }
            }
            for (std::uint32_t v = 0; v < nV; ++v)
                std::memcpy(&nrm[std::size_t(v)*3], &acc[std::size_t(wid[v])*3], 12);
        }

        // HOW FAR A VERTEX MAY BE PUSHED, decided per vertex rather than once
        // for the piece.
        //
        // Inversion is governed by the LOCAL size of the mesh, not by how big
        // the piece is: this body carries 36,680 triangles over about 120
        // units, so its edges run around a unit, and pushing a vertex two
        // units back turns most of the surface inside out -- measured at 75%
        // of triangles flipped on the first build of this. Bounding each
        // vertex by a fraction of its own shortest edge makes the offset
        // adapt: dense, curved regions move a little, flat open ones move the
        // full thickness, and a fold where opposing faces cancel the normal
        // does not move at all.
        std::vector<float> lim(nV, 1e30f);
        std::vector<std::vector<std::uint16_t>> nb(nV);
        for (std::uint32_t f = 0; f < nT; ++f)
            for (int k = 0; k < 3; ++k) {
                const std::uint16_t a = src.tris[f*3 + k], b = src.tris[f*3 + (k+1)%3];
                if (a >= nV || b >= nV || a == b) continue;
                const float* A = &pos[std::size_t(a)*3];
                const float* B = &pos[std::size_t(b)*3];
                const float d = std::sqrt((A[0]-B[0])*(A[0]-B[0]) + (A[1]-B[1])*(A[1]-B[1])
                                        + (A[2]-B[2])*(A[2]-B[2]));
                if (d < lim[a]) lim[a] = d;
                if (d < lim[b]) lim[b] = d;
                nb[a].push_back(b); nb[b].push_back(a);
            }

        // SMOOTH BOTH THE DIRECTION AND THE DISTANCE.
        //
        // A chunk is a bucket of triangles out of a fine mesh, so its normal
        // field is noisy and its edge lengths vary house to house. Offsetting
        // straight off that noise either inverts the surface or, once the
        // inversion is bounded away, leaves a piece too thin to read as flesh.
        // Averaging both fields over the one-ring a few times buys real
        // thickness at the same inversion budget: the sheet moves back as a
        // sheet instead of as several thousand independent decisions.
        for (int pass = 0; pass < 4; ++pass) {
            std::vector<float> sn(std::size_t(nV) * 3), sl(nV);
            for (std::uint32_t v = 0; v < nV; ++v) {
                float a[3] = { nrm[std::size_t(v)*3], nrm[std::size_t(v)*3+1], nrm[std::size_t(v)*3+2] };
                float d = lim[v]; int c = 1;
                for (std::uint16_t u : nb[v]) {
                    a[0] += nrm[std::size_t(u)*3]; a[1] += nrm[std::size_t(u)*3+1]; a[2] += nrm[std::size_t(u)*3+2];
                    d += lim[u]; ++c;
                }
                const float L = std::sqrt(a[0]*a[0] + a[1]*a[1] + a[2]*a[2]);
                if (L > 1e-9f) { a[0] /= L; a[1] /= L; a[2] /= L; }
                else { a[0] = a[1] = a[2] = 0.0f; }
                sn[std::size_t(v)*3] = a[0]; sn[std::size_t(v)*3+1] = a[1]; sn[std::size_t(v)*3+2] = a[2];
                sl[v] = d / float(c);
            }
            nrm.swap(sn); lim.swap(sl);
        }

        Shape in;
        in.name = src.name + "s";            // "s" for solid
        in.desc = src.desc; in.vsize = src.vsize;
        in.skin = false;                     // meat is its own material
        in.layer = src.layer;
        in.tex = { g_goreD, g_goreN };
        in.vdata = src.vdata;                // every record copied whole:
        // AS DEEP AS THE GEOMETRY ALLOWS, ONE SAFE STEP AT A TIME.
        //
        // A fixed offset cannot work at either end. Big enough to read as a
        // chunk of a body, it turns the surface inside out -- 75% of triangles
        // flipped, measured. Small enough never to flip, it leaves a piece
        // 0.8 units thick across twenty, which is a closed solid and still
        // reads as a sheet of paper, because that is what a 25:1 slab is.
        //
        // So the sheet is walked inward in small steps, and a vertex takes a
        // step only if every triangle it belongs to survives it: still facing
        // the way it started, still with area. Flat, open regions travel the
        // whole budget; a tight fold stops where it must, on its own, without
        // anything having to be assumed about how tight folds get. The budget
        // is half a lattice cell, because a piece has no business being
        // thicker than the volume it was cut out of.
        std::vector<std::vector<std::uint32_t>> inc(nV);
        std::vector<float> fn0(std::size_t(nT) * 3, 0.0f);
        for (std::uint32_t f = 0; f < nT; ++f) {
            const std::uint16_t a = src.tris[f*3], b = src.tris[f*3+1], c = src.tris[f*3+2];
            if (a >= nV || b >= nV || c >= nV) continue;
            inc[a].push_back(f); inc[b].push_back(f); inc[c].push_back(f);
            const float* A = &pos[std::size_t(a)*3];
            const float* B = &pos[std::size_t(b)*3];
            const float* C = &pos[std::size_t(c)*3];
            const float u[3] = { B[0]-A[0], B[1]-A[1], B[2]-A[2] };
            const float w[3] = { C[0]-A[0], C[1]-A[1], C[2]-A[2] };
            float n[3] = { u[1]*w[2]-u[2]*w[1], u[2]*w[0]-u[0]*w[2], u[0]*w[1]-u[1]*w[0] };
            const float L = std::sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
            if (L > 1e-12f) { n[0] /= L; n[1] /= L; n[2] /= L; }
            fn0[std::size_t(f)*3] = n[0]; fn0[std::size_t(f)*3+1] = n[1]; fn0[std::size_t(f)*3+2] = n[2];
        }

        float budget = 0.5f * g_cell;
        if (budget > t) budget = t;
        std::vector<float> cur(pos);
        const int steps = 24;
        const float dstep = budget / float(steps);
        auto safe = [&](std::uint32_t v, const float q[3]) {
            for (std::uint32_t f : inc[v]) {
                const std::uint16_t idx[3] = { src.tris[f*3], src.tris[f*3+1], src.tris[f*3+2] };
                const float* P[3];
                for (int k = 0; k < 3; ++k)
                    P[k] = (idx[k] == v) ? q : &cur[std::size_t(idx[k])*3];
                const float u[3] = { P[1][0]-P[0][0], P[1][1]-P[0][1], P[1][2]-P[0][2] };
                const float w[3] = { P[2][0]-P[0][0], P[2][1]-P[0][1], P[2][2]-P[0][2] };
                const float n[3] = { u[1]*w[2]-u[2]*w[1], u[2]*w[0]-u[0]*w[2], u[0]*w[1]-u[1]*w[0] };
                const float L = std::sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
                if (L < 1e-9f) return false;
                const float* m = &fn0[std::size_t(f)*3];
                if ((n[0]*m[0] + n[1]*m[1] + n[2]*m[2]) / L < kSolidKeep) return false;
            }
            return true;
        };
        // A vertex that has been refused twice running is wedged: its
        // neighbours would have to move first, and in a fold they never do.
        // Retesting it on every remaining step is most of the cost of this
        // loop and buys nothing.
        std::vector<std::vector<std::uint32_t>> members(nW);
        for (std::uint32_t v = 0; v < nV; ++v) members[wid[v]].push_back(v);
        std::vector<std::uint8_t> stuck(nW, 0);
        for (int st = 0; st < steps; ++st)
            for (std::uint32_t g = 0; g < nW; ++g) {
                if (stuck[g] >= 2 || members[g].empty()) continue;
                const std::uint32_t v0 = members[g][0];
                const float* n = &nrm[std::size_t(v0)*3];
                if (n[0] == 0.0f && n[1] == 0.0f && n[2] == 0.0f) { stuck[g] = 2; continue; }
                const float* p = &cur[std::size_t(v0)*3];
                const float q[3] = { p[0] - n[0]*dstep, p[1] - n[1]*dstep, p[2] - n[2]*dstep };
                bool ok = true;
                for (std::uint32_t v : members[g]) if (!safe(v, q)) { ok = false; break; }
                if (!ok) { ++stuck[g]; continue; }
                stuck[g] = 0;
                for (std::uint32_t v : members[g]) {
                    cur[std::size_t(v)*3] = q[0];
                    cur[std::size_t(v)*3+1] = q[1];
                    cur[std::size_t(v)*3+2] = q[2];
                }
            }
        for (std::uint32_t v = 0; v < nV; ++v)   // only the position moves
            std::memcpy(in.vdata.data() + std::size_t(v) * src.vsize, &cur[std::size_t(v)*3], 12);
        in.tris.reserve(src.tris.size());
        for (std::uint32_t f = 0; f < nT; ++f) {   // wound to face inward
            in.tris.push_back(src.tris[f*3+2]);
            in.tris.push_back(src.tris[f*3+1]);
            in.tris.push_back(src.tris[f*3]);
        }

        // THE WALL BAND, AND WHY IT GETS ITS OWN VERTICES.
        //
        // An edge used by exactly one triangle is where the cut went through,
        // and that is where the two surfaces have to be joined or the piece is
        // a hollow bag again.
        //
        // The first build stitched the band out of the vertices either side of
        // it, which closed the geometry and produced garbage: an outer vertex
        // and its inner twin are the SAME record, so they carry the SAME UV,
        // so every band quad had exactly ZERO area in texture space. Measured
        // on the game's own output: 100% of band triangles, UV area 0.000e+00.
        // A quad with no UV extent does not sample a texture, it smears one
        // pixel across itself -- which is the ring of red and white stripes
        // that showed up on the small pieces.
        //
        // So the band is its own shape with its own vertices and a UV built
        // from real distance: across the wall, how tall the wall actually is;
        // along it, how long the edge actually is. Same units-per-tile as
        // everything else, so a band reads as flesh at the same scale whatever
        // size the piece is. Its own shape also means its own u16 index space,
        // so a piece with thousands of open edges cannot run out of room and
        // silently leave the hole it was supposed to close.
        struct Edge { int cnt = 0; std::uint16_t a = 0, b = 0, opp = 0; };
        std::unordered_map<std::uint64_t, Edge> edge;
        edge.reserve(std::size_t(nT) * 6);
        for (std::uint32_t f = 0; f < nT; ++f)
            for (int k = 0; k < 3; ++k) {
                const std::uint16_t ia = src.tris[f*3 + k], ib = src.tris[f*3 + (k+1)%3];
                const std::uint16_t ic = src.tris[f*3 + (k+2)%3];
                if (ia >= nV || ib >= nV || ic >= nV) continue;
                std::uint32_t wa = wid[ia], wb = wid[ib];
                if (wa == wb) continue;
                if (wa > wb) std::swap(wa, wb);
                Edge& e = edge[(std::uint64_t(wa) << 32) | wb];
                ++e.cnt; e.a = ia; e.b = ib; e.opp = ic;
            }
        // The inner sheet is MEAT: gore diffuse, Default shader, and now the
        // normals that shader has always needed. This shell's sheet and
        // band(s) gather in `mine` and are counted against the ceiling before
        // any of them joins `add`.
        std::vector<Shape> mine;
        ToMeat(in);
        if (!in.tris.empty()) mine.push_back(std::move(in));

        const std::uint32_t uvo = UVOff(src.desc);
        int bandNo = 0;
        Shape bd;
        auto freshBand = [&]() {
            char nm[16]; std::snprintf(nm, sizeof(nm), "%sb%d", src.name.c_str(), bandNo++);
            bd = Shape();
            bd.name = nm; bd.desc = src.desc; bd.vsize = src.vsize;
            bd.skin = false; bd.layer = src.layer;
            bd.tex = { g_goreD, g_goreN };
        };
        freshBand();
        auto put = [&](std::uint16_t srcV, const float p[3], float u, float v) {
            const std::uint8_t* rec = src.vdata.data() + std::size_t(srcV) * src.vsize;
            const std::size_t at = bd.vdata.size();
            bd.vdata.insert(bd.vdata.end(), rec, rec + src.vsize);
            std::memcpy(bd.vdata.data() + at, p, 12);
            if (uvo + 4 <= src.vsize) {
                const std::uint16_t uv[2] = { HalfOf(u), HalfOf(v) };
                std::memcpy(bd.vdata.data() + at + uvo, uv, 4);
            }
            return std::uint16_t(at / src.vsize);
        };
        for (const auto& [key, ed] : edge) {
            // AN ODD NUMBER OF TRIANGLES, NOT EXACTLY ONE. A body patch welded
            // by position is not always a clean two-manifold -- separate parts
            // of their surface touch, and an edge can come out used three times.
            // Those edges are boundaries just as surely as the ones used once,
            // and skipping them left a hole: measured, 180 of 610 pieces still
            // leaking after the seams were dealt with.
            if (!(ed.cnt & 1)) continue;
            const std::uint16_t a = ed.a, b = ed.b;
            if (a >= nV || b >= nV) continue;
            if (bd.vdata.size() / src.vsize > 65000) {
                if (!bd.tris.empty()) { ToMeat(bd); mine.push_back(std::move(bd)); }
                freshBand();
            }
            const float* oA = &pos[std::size_t(a)*3];
            const float* oB = &pos[std::size_t(b)*3];
            const float* iA = &cur[std::size_t(a)*3];
            const float* iB = &cur[std::size_t(b)*3];
            const float L = std::sqrt((oA[0]-oB[0])*(oA[0]-oB[0]) + (oA[1]-oB[1])*(oA[1]-oB[1])
                                    + (oA[2]-oB[2])*(oA[2]-oB[2])) / kGoreTile;
            const float hA = std::sqrt((oA[0]-iA[0])*(oA[0]-iA[0]) + (oA[1]-iA[1])*(oA[1]-iA[1])
                                     + (oA[2]-iA[2])*(oA[2]-iA[2])) / kGoreTile;
            const float hB = std::sqrt((oB[0]-iB[0])*(oB[0]-iB[0]) + (oB[1]-iB[1])*(oB[1]-iB[1])
                                     + (oB[2]-iB[2])*(oB[2]-iB[2])) / kGoreTile;
            // A deterministic per-edge shift so a hundred quads do not all show
            // the same corner of the texture. Derived from the edge itself, so
            // the same cut always looks the same.
            const float su = float((a * 7u + b * 13u) % 64u) / 64.0f;
            const float sv = float((a * 11u + b * 5u) % 64u) / 64.0f;
            // WOUND ONCE, AND WOUND BY TOPOLOGY.
            //
            // It used to be emitted twice, both windings, so it would show
            // whichever side you looked from. Two coincident opposite faces
            // enclose nothing and have no consistent orientation, and the
            // piece stops being a solid: measured on the game's own output,
            // the skin, its twin and their band together came to 429-1793
            // unpaired edges. Once the meat carries real normals there is
            // nothing to hide from, so the wall is one surface.
            //
            // Which way it faces follows from the mesh. The one triangle
            // that owns this boundary edge traverses it a->b; the outer sheet
            // keeps that winding and the inner sheet is its reverse, so a wall
            // that runs a->b along the outside and back b->a along the inside
            // continues both without contradicting either. Deciding it
            // geometrically instead -- turning each quad away from the corner
            // opposite it -- left 180 of 610 pieces leaking, because
            // neighbouring quads disagreed wherever the surface curved.
            const std::uint16_t q[4] = {
                put(a, oA, su,     sv),
                put(b, oB, su + L, sv),
                put(b, iB, su + L, sv + hB),
                put(a, iA, su,     sv + hA),
            };
            bd.tris.push_back(q[0]); bd.tris.push_back(q[2]); bd.tris.push_back(q[1]);
            bd.tris.push_back(q[0]); bd.tris.push_back(q[3]); bd.tris.push_back(q[2]);
        }
        if (!bd.tris.empty()) { ToMeat(bd); mine.push_back(std::move(bd)); }
        // COUNTED. If this shell's sheet and band(s) would put
        // the piece over the ceiling, it and every smaller shell after it stay
        // one-sided; Build() would otherwise refuse the whole piece.
        if (!anySkin && shapes.size() + add.size() + mine.size() > kShapeCeiling) break;
        for (Shape& s : mine) add.push_back(std::move(s));
    }
    for (Shape& s : add) shapes.push_back(std::move(s));
}

std::vector<std::uint8_t> Build(const Chunk& c, float* massOut)
{
    std::vector<Shape> shapes = c.shapes;
    Solidify(shapes);
    // Bloody() is withdrawn: the blood is VANILLA -- the engine's
    // own spray and decals, which the landing impact now provides -- not a
    // painted shell. The machinery stays above; nothing calls it.
    const std::size_t nShapes = shapes.size();
    // A chunk carries THREE shapes per source patch -- the skin, the
    // inner sheet and the wall band -- and a
    // heavily dressed actor can put several layer-0 sources in one piece. A
    // ceiling of 24 would refuse whole chunks at
    // eight sources, so this one sits far above that, and the refusal is not
    // silent.
    if (!nShapes) return {};
    // A SEVERED LIMB IS NOT A SHARD. A shard is a handful of cells and a
    // dozen shapes; a severed body half is a hundred and thirty cells whose
    // fill will not fit in one sixteen-bit index list and arrives already
    // split across several shapes, each of which Solidify may then triple.
    // Measured on the real body, the worst cut seen is a sagittal bisection at
    // twenty-odd shapes -- so the ceiling is where an absurd chunk is still
    // refused and a real one never is.
    if (nShapes > kShapeCeiling) return {};
    for (const Shape& s : shapes)
        if (!s.vsize || s.vdata.size() % s.vsize) return {};

    // ---- centroid and bounds, in the body's bind space -------------------
    double sx = 0, sy = 0, sz = 0; std::uint64_t nPts = 0;
    float xa=1e30f, xb=-1e30f, ya=1e30f, yb=-1e30f, za=1e30f, zb=-1e30f;
    for (const Shape& s : shapes) {
        const std::size_t nV = s.vdata.size() / s.vsize;
        for (std::size_t i = 0; i < nV; ++i) {
            float p[3];
            PosOf(s.vdata.data() + i * s.vsize, s.desc, p);
            sx += p[0]; sy += p[1]; sz += p[2]; ++nPts;
            if (p[0]<xa) xa=p[0];
            if (p[0]>xb) xb=p[0];
            if (p[1]<ya) ya=p[1];
            if (p[1]>yb) yb=p[1];
            if (p[2]<za) za=p[2];
            if (p[2]>zb) zb=p[2];
        }
    }
    if (!nPts) return {};
    const float C[3] = { float(sx/nPts), float(sy/nPts), float(sz/nPts) };
    const float hx = xb-xa, hy = yb-ya, hz = zb-za;
    // A chunk thinner than a twentieth of a unit in any axis is a sliver with
    // no volume to give physics, and one over five hundred units across is not
    // a chunk of anybody. Both are refused rather than shipped.
    if (!(hx > 0.05f && hy > 0.05f && hz > 0.05f)) return {};
    if (hx > 500 || hy > 500 || hz > 500) return {};
    const float rad = 0.5f * std::sqrt(hx*hx + hy*hy + hz*hz);

    // ---- principal axes, for a hull that is not mostly air ---------------
    double cov[3][3] = {}, E[3][3];
    for (const Shape& s : shapes) {
        const std::size_t nV = s.vdata.size() / s.vsize;
        for (std::size_t i = 0; i < nV; ++i) {
            float p[3];
            PosOf(s.vdata.data() + i * s.vsize, s.desc, p);
            const double d[3] = { p[0]-C[0], p[1]-C[1], p[2]-C[2] };
            for (int a = 0; a < 3; ++a) for (int b = 0; b < 3; ++b) cov[a][b] += d[a]*d[b];
        }
    }
    Jacobi3(cov, E);
    float lo[3] = {1e30f,1e30f,1e30f}, hi[3] = {-1e30f,-1e30f,-1e30f};
    for (const Shape& s : shapes) {
        const std::size_t nV = s.vdata.size() / s.vsize;
        for (std::size_t i = 0; i < nV; ++i) {
            float p[3];
            PosOf(s.vdata.data() + i * s.vsize, s.desc, p);
            const float d[3] = { p[0]-C[0], p[1]-C[1], p[2]-C[2] };
            for (int a = 0; a < 3; ++a) {
                const float t = float(d[0]*E[0][a] + d[1]*E[1][a] + d[2]*E[2][a]);
                if (t < lo[a]) lo[a] = t;
                if (t > hi[a]) hi[a] = t;
            }
        }
    }
    constexpr float kHavok = 69.9904f;

    // ---- mass from the chunk's own volume --------------------------------
    // Divergence theorem over the triangles. Exact for a closed mesh, and the
    // shell was just closed, so it is close here too; the oriented box volume
    // is the sanity bound, and when the mesh volume falls outside it the box
    // half-volume is used instead.
    double svol = 0;
    for (const Shape& s : shapes) {
        // The splatter shell is an OPEN sheet floating off the skin: its
        // signed-volume contribution is not volume, it is error. Blood
        // weighs nothing here.
        if (s.blood) continue;
        const std::size_t nT = s.tris.size() / 3;
        for (std::size_t t = 0; t < nT; ++t) {
            // v0/v1/v2, not a/b/c: `c` here shadowed the Chunk& parameter
            // this whole function is about.
            float v0[3], v1[3], v2[3];
            PosOf(s.vdata.data() + std::size_t(s.tris[t*3  ]) * s.vsize, s.desc, v0);
            PosOf(s.vdata.data() + std::size_t(s.tris[t*3+1]) * s.vsize, s.desc, v1);
            PosOf(s.vdata.data() + std::size_t(s.tris[t*3+2]) * s.vsize, s.desc, v2);
            const double ax=v0[0]-C[0], ay=v0[1]-C[1], az=v0[2]-C[2];
            const double bx=v1[0]-C[0], by=v1[1]-C[1], bz=v1[2]-C[2];
            const double cx=v2[0]-C[0], cy=v2[1]-C[1], cz=v2[2]-C[2];
            svol += (ax*(by*cz - bz*cy) - ay*(bx*cz - bz*cx) + az*(bx*cy - by*cx)) / 6.0;
        }
    }
    const double h3 = double(kHavok)*kHavok*kHavok;
    const double meshVol = std::fabs(svol) / h3;
    const double boxVol = double(hi[0]-lo[0]) * (hi[1]-lo[1]) * (hi[2]-lo[2]) / h3;
    double useVol = meshVol;
    if (!(useVol > 0.05 * boxVol) || !(useVol < 1.5 * boxVol)) useVol = boxVol * 0.5;
    // Density anchor: the shipping limb prop weighs 20 at 0.0047763 havok^3.
    float mass = float(20.0 * (useVol / 0.0047763));
    if (mass < 1.0f) mass = 1.0f;
    if (mass > 300.0f) mass = 300.0f;
    // A SHARD IS A HANDFUL OF FLESH AND MUST WEIGH LIKE ONE.
    //
    // The shipped meshes were coming out at thirteen to fifty units of mass --
    // heavier than the ragdoll's individual bones -- because the scale is taken
    // from DF's whole limb, where twenty is right. A fifty-unit lump appearing
    // inside a corpse does not get nudged out of it; it throws the corpse.
    // Severed limbs keep the real number, because a limb IS that heavy and
    // arrives alone. Debris is capped, and the cap is a physical claim rather
    // than a tuning knob: a piece you could hold in one hand.
    if (g_debris && mass > 4.0f) mass = 4.0f;
    if (massOut) *massOut = mass;
    const float rscale = (rad / 10.016f) * (rad / 10.016f);   // template bound radius

    // ---- tables ----------------------------------------------------------
    std::vector<std::string> strs = { "FleshChunk", "BSX", "Root" };
    for (const Shape& s : shapes) strs.push_back(s.name);

    static const char* kTypes[] = {
        "BSFadeNode", "BSXFlags", "bhkConvexVerticesShape", "bhkRigidBody",
        "bhkCollisionObject", "NiNode", "BSTriShape", "BSDismemberSkinInstance",
        "NiSkinData", "NiSkinPartition", "BSLightingShaderProperty",
        "BSShaderTextureSet", "NiAlphaProperty",
    };
    enum { tFade, tBSX, tHull, tRigid, tColl, tNode, tTri, tDSI, tSkinD, tSkinP, tShader, tTexSet, tAlpha };

    bool anyBlood = false;
    for (const Shape& sh : shapes) if (sh.blood) anyBlood = true;
    // RIGID ONLY IF EVERY SHAPE CAN BE. The block layout is one number, so a
    // file cannot be half skinned; a shape whose record does not end in its
    // skin block would have to keep it, and then all of them do.
    bool rigid = g_rigid != 0;
    for (const Shape& sh : shapes)
        if (!Strippable(sh.desc, sh.vsize)) {
            rigid = false;
            if (getenv("FC_WHY"))
                std::fprintf(stderr, "  [rigid off] shape '%s' desc=0x%016llX vsize=%u skinOff=%u\n",
                             sh.name.c_str(), (unsigned long long)sh.desc, sh.vsize, SkinOff(sh.desc));
        }
    g_lastBuild = BuildStat{};
    g_lastBuild.rigid  = rigid;
    g_lastBuild.shapes = int(nShapes);
    const int perShape = rigid ? 3 : 6;
    const int alphaBlk = 6 + int(nShapes) * perShape;   // one, shared by every shell
    const int nBlocks = alphaBlk + (anyBlood ? 1 : 0);
    std::vector<std::uint16_t> tidx(nBlocks);
    tidx[0]=tFade; tidx[1]=tBSX; tidx[2]=tHull; tidx[3]=tRigid; tidx[4]=tColl; tidx[5]=tNode;
    for (std::size_t s = 0; s < nShapes; ++s) {
        const int b = 6 + int(s) * perShape;
        tidx[b] = tTri;
        if (rigid) { tidx[b+1]=tShader; tidx[b+2]=tTexSet; }
        else { tidx[b+1]=tDSI; tidx[b+2]=tSkinD; tidx[b+3]=tSkinP; tidx[b+4]=tShader; tidx[b+5]=tTexSet; }
    }
    if (anyBlood) tidx[alphaBlk] = tAlpha;
    std::vector<std::vector<std::uint8_t>> blocks(nBlocks);
    if (anyBlood) {
        // Measured off a shipping stump mesh, block 25:
        // name -1, extra 0, controller -1, flags 0x12EC (blend + test), thr 40.
        W w; w.i32(-1); w.u32(0); w.i32(-1); w.u16(0x12EC); w.u8(40);
        blocks[alphaBlk] = std::move(w.b);
    }

    {   // BSFadeNode root
        W w;
        w.i32(0); w.u32(1); w.i32(1); w.i32(-1);
        w.avxform();
        w.i32(4);
        w.u32(1 + std::uint32_t(nShapes));
        w.i32(5);
        for (std::size_t s = 0; s < nShapes; ++s) w.i32(6 + int(s) * perShape);
        w.u32(0);
        blocks[0] = std::move(w.b);
    }
    {   // BSXFlags 198 = Havok|Ragdoll|Dynamic|Articulated, as the prop ships
        W w; w.i32(1); w.u32(198); blocks[1] = std::move(w.b);
    }
    {   // bhkConvexVerticesShape: template head, then the oriented box.
        // Plane convention, measured off the template:
        // n . x + d = 0, with n pointing OUT of the solid.
        W w;
        w.raw(kTplHullHead, sizeof(kTplHullHead));
        w.u32(8);
        for (int i = 0; i < 8; ++i) {
            const float t0 = (i&1) ? hi[0] : lo[0];
            const float t1 = (i&2) ? hi[1] : lo[1];
            const float t2 = (i&4) ? hi[2] : lo[2];
            w.f32(float(t0*E[0][0] + t1*E[0][1] + t2*E[0][2]) / kHavok);
            w.f32(float(t0*E[1][0] + t1*E[1][1] + t2*E[1][2]) / kHavok);
            w.f32(float(t0*E[2][0] + t1*E[2][1] + t2*E[2][2]) / kHavok);
            w.f32(0);
        }
        w.u32(6);
        for (int a = 0; a < 3; ++a)
            for (int sgn = 0; sgn < 2; ++sgn) {
                const float s2 = sgn ? 1.0f : -1.0f;
                w.f32(s2*float(E[0][a])); w.f32(s2*float(E[1][a])); w.f32(s2*float(E[2][a]));
                w.f32((sgn ? -hi[a] : lo[a]) / kHavok);
            }
        blocks[2] = std::move(w.b);
    }
    {   // bhkRigidBody: shipping bytes, mass and inertia scaled to this chunk
        std::vector<std::uint8_t> rb(kTplRigidBody, kTplRigidBody + sizeof(kTplRigidBody));
        // ---- WHY A SHARD MUST NOT BE A CORPSE, PHYSICALLY -----------------
        //
        // The template is DF's limb body and it is set up to BE a limb: its
        // collision layer is 32, DEADBIP -- the same layer the ragdoll it just
        // came off is on -- and its Havok quality type is 4, MOVING, which is
        // continuous collision detection.
        //
        // Both are wrong for a shard, and together they are why a body kicks
        // across the room when its pieces appear. A shard is spawned AT the
        // bone it was cut from, which means its collision shape starts fully
        // inside the corpse's. Havok is then asked to resolve a deep
        // penetration between two dead bipeds with CCD switched on, several
        // times over in the same frame, and it does so the only way it can:
        // by shoving them apart hard. The corpse, being lighter, is the one thrown.
        //
        // BOTH get L_DEBRIS_SMALL. The first fix gave shards
        // layer 4, CLUTTER, and left severed sections on DEADBIP. Testing
        // showed pieces were still being shot out of NPCs, and the
        // reason is in Skyrim's own collision table: CLUTTER collides with
        // L_CHARCONTROLLER and DEADBIP collides with everything a corpse does,
        // so both were still biped fights. Read out of the 55 COLL records in
        // Skyrim.esm, the layer that collides with static geometry and the
        // ground and with nothing that walks is 19, L_DEBRIS_SMALL -- what
        // Bethesda uses for physics debris spawned on top of actors. Sections
        // take it from the template (blobs.h); shards take it here. Debris gets:
        //
        //   layer 19, L_DEBRIS_SMALL -- collides with the world, not with the
        //   target it just came off.
        //
        //   quality 3, DEBRIS -- Havok's own name for exactly this: small,
        //   cheap, allowed to tolerate penetration rather than be violently
        //   corrected out of it. Turning CCD off is the half that stops the
        //   kick; the layer is the half that stops it being a biped fight.
        //
        // Offsets are anchored: the filter's layer byte is at +4
        // of a bhkRigidBody, and the motion quartet at +224 is fixed by
        // maxAngularVelocity reading 31.57 at +216, which is the value the
        // format documents there and the same anchor blobs.h fingerprints.
        if (g_debris) {
            rb[4]   = 19;   // HavokFilter.layer  : L_DEBRIS_SMALL
            rb[227] = 3;    // qualityType        : DEBRIS
        }
        std::memcpy(rb.data() + 180, &mass, 4);
        for (int k : { 0, 5, 10 }) {
            float v; std::memcpy(&v, rb.data() + 116 + 4*k, 4);
            v *= (mass / 20.0f) * rscale;
            std::memcpy(rb.data() + 116 + 4*k, &v, 4);
        }
        blocks[3] = std::move(rb);
    }
    {   W w; w.i32(0); w.u16(0x81); w.i32(3); blocks[4] = std::move(w.b); }
    {   // NiNode "Root": the chunk's one and only bone
        W w; w.i32(2); w.u32(0); w.i32(-1); w.avxform(); w.i32(-1); w.u32(0); w.u32(0);
        blocks[5] = std::move(w.b);
    }

    for (std::size_t s = 0; s < nShapes; ++s) {
        const Shape& sh = shapes[s];
        const int b = 6 + int(s) * perShape;
        const std::uint32_t nV = std::uint32_t(sh.vdata.size() / sh.vsize);
        const std::uint32_t nT = std::uint32_t(sh.tris.size() / 3);
        if (!nV || !nT || nV > 0xFFFF || nT > 0xFFFF) return {};
        const std::uint32_t so = SkinOff(sh.desc);
        if (so + 12 > sh.vsize) return {};

        // THE RECORDS, in whichever of the two shapes this file takes.
        //
        //   rigid: the record loses its skin block and its POSITION is rebased
        //          onto the chunk's centroid, because there is no bone left to
        //          carry it there.
        //   skinned: the record is kept whole, re-skinned to bone 0 at weight
        //          one, and the positions are untouched -- the single bone's
        //          own translation is what moves the piece onto its origin.
        // ---- THEIR COLOUR, BY THE ONE ROUTE THAT SURVIVES BEING RIGID ------
        //
        // The skin-tint shader cannot be used on a piece with no skeleton --
        // repeated tests, written out at the shader block below. So
        // their colour arrives as a VERTEX COLOUR on the ordinary lighting
        // shader, which multiplies the diffuse by it and does not care in the
        // slightest whether the geometry is skinned.
        //
        // It is added only where all four of these hold:
        //   * the file is rigid -- the colour then goes at the very end of the
        //     record, where the skin block used to be, and NOTHING MOVES. On
        //     the skinned fallback the colour would have to be spliced in
        //     ahead of the skin block, and no shipping mesh was measured for
        //     that layout, so it is not attempted.
        //   * their tint was actually read off their live shader.
        //   * this shape is their SKIN. Meat and bone are not skin-toned: the
        //     cut face is gore texture and stays as it is.
        //   * the skin-tint block is not in use (cfg S 1), which has its own
        //     tint field and must not be tinted twice.
        // and the new offset still fits a nibble, which is offset/4 <= 15.
        const bool haveSkinTex  = sh.tex.size() > 7 && !sh.tex[2].empty() && !sh.tex[7].empty();
        const bool useSkinBlock = sh.skin && haveSkinTex && g_skinShader == 1;
        const bool tintShape    = g_vcTint && rigid && g_haveTint && sh.skin
                                  && !useSkinBlock && (so + 4u) <= 60u;
        if (sh.skin)   ++g_lastBuild.skinShapes;
        if (tintShape) ++g_lastBuild.tinted;

        const std::uint32_t copyN = rigid ? so : sh.vsize;
        const std::uint32_t vsz  = copyN + (tintShape ? 4u : 0u);
        std::uint64_t desc = rigid ? RigidDesc(sh.desc) : sh.desc;
        if (tintShape) desc = WithColour(desc, copyN);
        const std::uint8_t col[4] = {
            Byte255(g_tint[0] * g_tintGain), Byte255(g_tint[1] * g_tintGain),
            Byte255(g_tint[2] * g_tintGain), 0xFF
        };
        std::vector<std::uint8_t> vd(std::size_t(nV) * vsz);
        for (std::uint32_t i = 0; i < nV; ++i) {
            const std::uint8_t* src = sh.vdata.data() + std::size_t(i) * sh.vsize;
            std::uint8_t* dst = vd.data() + std::size_t(i) * vsz;
            std::memcpy(dst, src, copyN);
            if (tintShape) std::memcpy(dst + copyN, col, 4);
            if (rigid) {
                float p[3];
                PosOf(src, sh.desc, p);
                p[0] -= C[0]; p[1] -= C[1]; p[2] -= C[2];
                std::memcpy(dst, p, 12);
            } else {
                std::uint8_t* r = dst + so;
                r[0] = 0x00; r[1] = 0x3C;       // half 1.0
                std::memset(r + 2, 0, 6);       // remaining weights zero
                std::memset(r + 8, 0, 4);       // all four bone indices zero
            }
        }

        float pxa=1e30f,pxb=-1e30f,pya=1e30f,pyb=-1e30f,pza=1e30f,pzb=-1e30f;
        for (std::uint32_t i = 0; i < nV; ++i) {
            float p[3];
            PosOf(vd.data() + std::size_t(i) * vsz, desc, p);
            if (p[0]<pxa) pxa=p[0];
            if (p[0]>pxb) pxb=p[0];
            if (p[1]<pya) pya=p[1];
            if (p[1]>pyb) pyb=p[1];
            if (p[2]<pza) pza=p[2];
            if (p[2]>pzb) pzb=p[2];
        }
        const float bc[3] = { (pxa+pxb)*0.5f, (pya+pyb)*0.5f, (pza+pzb)*0.5f };
        const float br = 0.5f * std::sqrt((pxb-pxa)*(pxb-pxa) + (pyb-pya)*(pyb-pya) + (pzb-pza)*(pzb-pza));
        const int shaderBlk = rigid ? (b + 1) : (b + 4);

        {   W w;
            w.i32(3 + int(s));
            w.u32(0); w.i32(-1);
            w.avxform(g_noDecals ? 0x400u : 0u);
            w.i32(-1);
            w.f32(bc[0]); w.f32(bc[1]); w.f32(bc[2]); w.f32(br);
            w.i32(rigid ? -1 : (b + 1)); w.i32(shaderBlk); w.i32(sh.blood ? alphaBlk : -1);
            w.u64(desc);
            if (rigid) {
                // numTriangles, numVertices, dataSize, then the geometry, then
                // particleDataSize. dataSize == nV*vertexSize + nT*6 -- measured
                // exact on three shipping unskinned meshes.
                w.u16(std::uint16_t(nT)); w.u16(std::uint16_t(nV));
                w.u32(std::uint32_t(vd.size()) + nT * 6u);
                w.raw(vd.data(), vd.size());
                w.raw(sh.tris.data(), sh.tris.size() * 2);
                w.u32(0);
            } else {
                w.u16(0); w.u16(0);      // skinned shapes carry no inline data
                w.u32(0); w.u32(0);
            }
            blocks[b] = std::move(w.b);
        }
        if (!rigid) {
        {   W w;
            w.i32(b + 2); w.i32(b + 3); w.i32(0);
            w.u32(1); w.i32(5);
            w.u32(1); w.u16(257); w.u16(32);
            blocks[b + 1] = std::move(w.b);
        }
        {   // NiSkinData: identity at the root, and the one bone carrying
            // minus the chunk centroid -- this is what re-origins the piece.
            W w;
            w.ident9(); w.f32(0); w.f32(0); w.f32(0); w.f32(1);
            w.u32(1); w.u8(1);
            w.ident9(); w.f32(-C[0]); w.f32(-C[1]); w.f32(-C[2]); w.f32(1);
            w.f32(bc[0]-C[0]); w.f32(bc[1]-C[1]); w.f32(bc[2]-C[2]); w.f32(br);
            w.u16(std::uint16_t(nV));
            for (std::uint32_t i = 0; i < nV; ++i) { w.u16(std::uint16_t(i)); w.f32(1.0f); }
            blocks[b + 2] = std::move(w.b);
        }
        {   W w;
            w.u32(1);
            w.u32(std::uint32_t(vd.size()));
            w.u32(vsz);
            w.u64(desc);
            w.raw(vd.data(), vd.size());
            w.u16(std::uint16_t(nV)); w.u16(std::uint16_t(nT));
            w.u16(1); w.u16(0); w.u16(4);
            w.u16(0);
            w.u8(1);
            for (std::uint32_t i = 0; i < nV; ++i) w.u16(std::uint16_t(i));
            w.u8(1);
            for (std::uint32_t i = 0; i < nV; ++i) { w.f32(1); w.f32(0); w.f32(0); w.f32(0); }
            w.u8(1);
            w.raw(sh.tris.data(), sh.tris.size() * 2);
            w.u8(1);
            for (std::uint32_t i = 0; i < nV * 4; ++i) w.u8(0);
            w.u16(0);
            w.u64(desc);
            w.raw(sh.tris.data(), sh.tris.size() * 2);
            blocks[b + 3] = std::move(w.b);
        }
        }
        {   // Shader. The block used and the type stamped in it must match.
            // THE SKIN BLOCK IS USED ONLY WHEN THE CONFIG ASKS (cfg S 1),
            // AND IT CARRIES THEIR COLOUR WHEN ONE WAS READ.
            //
            // The 112-byte type-5 block ends in three floats -- their skin tint
            // -- and the 100-byte type-0 block does not have them at all. That
            // is why the default block leaves every piece white whatever their
            // skin, and why the skin
            // path with no tint read uses the template's own (1,1,1) and comes
            // out as bleached meat. Both are the same missing number.
            //
            // The block needs that number: with their
            // tint in hand the skin path is right and the piece matches them;
            // without it the skin path is guaranteed wrong and the ordinary
            // lighting shader is the right one. The config switch (S 1)
            // turns the block on for anyone who wants to test it.
            // THE SKIN BLOCK IS ONLY USED IF ITS TEXTURES ARE THERE.
            //
            // Type 5 with FaceGen_RGB_Tint and Soft_Lighting -- which is what
            // their own body mesh uses, read off the disk, and therefore what a
            // piece of them must use to look like them -- samples FOUR textures:
            // diffuse, model-space normal, the subsurface map at slot 2 and the
            // specular at slot 7. Handed an empty slot 2 it does not degrade
            // gracefully; it renders a flat pale blue wash, the normal map
            // showing through where the skin should be. That is the cyan, twice.
            //
            // ReadTextures rebuilds the missing pair from the diffuse and
            // checks the files open. When even that fails, this shape does not
            // get the skin block at all -- the ordinary lighting shader needs
            // only slots 0 and 1 and has always rendered these shapes correctly.
            // So the worst case is a piece that is their shape but not their colour,
            // and cyan is no longer reachable.
            // THE SKIN-TINT SHADER CANNOT BE USED ON A PIECE THAT HAS NO
            // SKELETON; repeated tests show it.
            //
            // Their body's skin shape is TYPE 5 with flags1 82601303 -- and bit 1
            // of that is SLSF1_Skinned. A forged piece is RIGID: it has no skin
            // instance, no bone palette and no partition, and writing that bit
            // onto it is what originally stopped every piece from ever
            // appearing. So it must be cleared, and 82601301 is a skin shader
            // told its geometry is not skinned -- a permutation that reads
            // inputs nothing has bound, and renders a flat pale blue wash.
            //
            // That is the cyan, and no better data cures it: the donor's flags,
            // the default's flags, the vertex
            // colour bit cleared, the subsurface map moved to the slot a NIF
            // means by it, or a texture set matching their body mesh
            // EXACTLY -- slots 0, 1, 2, 7 and nothing else -- all render it blue.
            // The cause is the shader type on
            // unskinned geometry.
            //
            // So the skin block is off unless the config asks for it. The
            // ordinary lighting shader has rendered these shapes correctly in
            // every build that used it, and an untinted piece of them is a great
            // deal better than a blue one. Their colour has to arrive by a route
            // that survives being rigid -- vertex colours on the default
            // shader -- which needs the colour-offset nibble of the vertex
            // descriptor measured off a mesh that actually has them.
            const unsigned char* tpl = useSkinBlock ? kTplShaderSkin : kTplShaderDefault;
            const std::size_t len   = useSkinBlock ? sizeof(kTplShaderSkin) : sizeof(kTplShaderDefault);
            std::vector<std::uint8_t> sp(tpl, tpl + len);
            // A RIGID SHAPE MUST NOT DECLARE ITSELF SKINNED.
            //
            // This is what originally stopped every forged piece from
            // ever appearing. Both shader templates are shipping bytes lifted
            // out of Dismembering Framework's limb prop, which is a SKINNED
            // mesh -- so both carry SLSF1_Skinned, bit 1 of flags1, and every
            // skinned shape on this body carries it too (0x82601303,
            // 0x82401303, 0x82400303: all of them). Writing that shader onto a
            // BSTriShape whose skin reference is -1 tells the engine to set up
            // skinned rendering for geometry that has no skin instance, no
            // bone palette and no partition, and the shape simply never
            // builds. Silently: the reference exists, the file is on disk and
            // reopens, the watcher places it, and it never gets 3D. A test log
            // showed that forty times in a row.
            //
            // blobs.h warned about this class of mistake in its own header --
            // "the file will not load at all -- silently, with nothing spawned
            // and nothing logged" -- about the shader LENGTH. It is just as
            // true of the shader's flags.
            // ONE FLAG WAS WRONG, AND THE FIRST FIX THREW OUT TWO MORE WITH IT.
            //
            // kTplShaderSkin comes from Dismembering Framework's limb prop and
            // carries that mesh's flags. Exactly one of them is wrong for a
            // forged piece:
            //
            //   flags2 bit 5, SLSF2_Vertex_Colors. It tells the shader every
            //   vertex carries a colour. NEITHER vertex format a skin-block shape uses has a
            //   colour channel -- their skin is Vertex|UVs|Skinned and the meat
            //   is Vertex|UVs|Normals|Tangents|Skinned, checked in the
            //   descriptor -- so the shader read a
            //   per-vertex colour out of a buffer that has none and got flat,
            //   uniform cyan.
            //
            // The first fix took the DEFAULT block's flags
            // wholesale, which cured the cyan and also threw away the two
            // bits that are not wrong at all:
            //
            //   flags1 bit 21, SLSF1_FaceGen_RGB_Tint -- the flag that makes
            //   the shader APPLY the tint colour. Without it the three floats
            //   are still sitting in the block being ignored, as testing showed:
            //   pale shards off a purple target, no cyan
            //   and no colour either.
            //
            //   flags2 bit 25, SLSF2_Soft_Lighting -- subsurface softening,
            //   which is what skin wants and degrades harmlessly without it.
            //
            // The bit list is anchored: bit 12 of flags1 is
            // Model_Space_Normals, which this file has relied on by name since
            // the meat format was worked out, and the same list gives bit 21.
            //
            // So the skin block now keeps its OWN flags and clears one bit.
            if (useSkinBlock) {
                std::uint32_t f2 = 0;
                std::memcpy(&f2, sp.data() + 20, 4);
                f2 &= ~0x20u;                    // SLSF2_Vertex_Colors
                std::memcpy(sp.data() + 20, &f2, 4);
            }
            if (rigid) {
                std::uint32_t f1 = 0;
                std::memcpy(&f1, sp.data() + 16, 4);
                f1 &= ~2u;                       // SLSF1_Skinned
                std::memcpy(sp.data() + 16, &f1, 4);
            }
            // THE FLAG AND THE CHANNEL ARE SET IN THE SAME BREATH.
            //
            // SLSF2_Vertex_Colors on a buffer with no colour lane is what
            // turned every shard cyan at first, and the reverse -- a colour
            // lane no shader reads -- is four wasted bytes a vertex. So the
            // one condition, `tintShape`, drives both, so a shape never
            // carries one without the other.
            if (tintShape || (desc & (std::uint64_t(1) << 49)) != 0) {
                std::uint32_t f2 = 0;
                std::memcpy(&f2, sp.data() + 20, 4);
                f2 |= 0x20u;                     // SLSF2_Vertex_Colors
                std::memcpy(sp.data() + 20, &f2, 4);
            }
            if (sh.skin && !useSkinBlock) {
                // Model space normals: bit 12 of flags1. The body's normal map
                // is a _msn, and that bit is the only thing the skin path was
                // giving it that the ordinary lighting shader does not.
                std::uint32_t f1 = 0;
                std::memcpy(&f1, sp.data() + 16, 4);
                f1 |= 1u << 12;
                std::memcpy(sp.data() + 16, &f1, 4);
            }
            // THEIR COLOUR, WRITTEN INTO THE PIECE.
            //
            // Offsets 100, 104 and 108 of the 112-byte skin block: the three
            // floats the type-0 block does not have. Measured off the shipping
            // template, where all three are 1.0 -- white skin, which is what
            // every piece this mod has ever forged has worn.
            if (useSkinBlock && g_haveTint && sp.size() >= 112) {
                std::memcpy(sp.data() + 100, &g_tint[0], 4);
                std::memcpy(sp.data() + 104, &g_tint[1], 4);
                std::memcpy(sp.data() + 108, &g_tint[2], 4);
            }
            const std::int32_t ts = shaderBlk + 1;
            std::memcpy(sp.data() + 40, &ts, 4);
            blocks[shaderBlk] = std::move(sp);
        }
        {   W w;
            w.u32(9);
            for (int t = 0; t < 9; ++t) {
                const std::string& p = (std::size_t(t) < sh.tex.size()) ? sh.tex[t] : std::string();
                w.u32(std::uint32_t(p.size()));
                w.raw(p.data(), p.size());
            }
            blocks[shaderBlk + 1] = std::move(w.b);
        }
    }

    // ---- header ----------------------------------------------------------
    W f;
    static const char kMagic[] = "Gamebryo File Format, Version 20.2.0.7\n";
    f.raw(kMagic, sizeof(kMagic) - 1);
    f.u32(0x14020007);
    f.u8(1);
    f.u32(12);
    f.u32(std::uint32_t(nBlocks));
    f.u32(100);
    f.u8(1); f.u8(0);          // author, process and export strings: each one
    f.u8(1); f.u8(0);          // counted byte that IS the terminating NUL,
    f.u8(1); f.u8(0);          // which is how the shipping files write them
    f.u16(std::uint16_t(sizeof(kTypes)/sizeof(*kTypes)));
    for (const char* t : kTypes) {
        const std::uint32_t n = std::uint32_t(std::strlen(t));
        f.u32(n); f.raw(t, n);
    }
    for (int i = 0; i < nBlocks; ++i) f.u16(tidx[i]);
    for (int i = 0; i < nBlocks; ++i) f.u32(std::uint32_t(blocks[i].size()));
    std::uint32_t maxLen = 0;
    for (const std::string& s : strs) if (s.size() > maxLen) maxLen = std::uint32_t(s.size());
    f.u32(std::uint32_t(strs.size())); f.u32(maxLen);
    for (const std::string& s : strs) { f.u32(std::uint32_t(s.size())); f.raw(s.data(), s.size()); }
    f.u32(0);
    for (int i = 0; i < nBlocks; ++i) f.raw(blocks[i].data(), blocks[i].size());
    f.u32(1); f.i32(0);
    return std::move(f.b);
}

}  // namespace chunknif
