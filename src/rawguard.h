#pragma once
// ============================================================ RAWGUARD
//
// Pure checks on a shape's vertex records. NOTHING IN HERE READS ENGINE MEMORY
// ON ITS OWN: every pointer handed in is memory the caller has already proven
// readable for the count it passes. flesh.cpp uses it at the harvest
// (Voxelise), before a wound is cut (CheckLiveRaw) and in the forge's copy
// (AssembleChunk). Because it reads only what it is handed, an offline test
// can run the very same code against the shipped body meshes and against
// pieces saved from a game session.
//
// WHY IT EXISTS. A shape's vertex records are a pointer into the engine's
// skin partition, taken when the body was built. A body-morph update (a slider
// change, another mod's morph) can swap in a fresh copy of the partition and free
// the old one while the skin instance, the root and the shape count all stay
// the same. The freed block is then reused, and records read through the old
// pointer belong to a copy of the same mesh that starts some records earlier or
// later: every triangle lands that many vertices off, and the piece comes out
// as long, sharp triangles spanning the body. The print below tells "the same
// mesh in the same order" from that; the edge test is the last line of defence
// in the forge's copy.
#include "lattice.h"
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace rawguard {

// How many records a print and a sample set read: evenly spaced through the
// buffer, the first and the last included.
constexpr unsigned kSamples = 32;

inline std::uint32_t SampleAt(unsigned i, std::uint32_t n)
{
    return n > 1u ? std::uint32_t((std::uint64_t(i) * (n - 1u)) / (kSamples - 1u)) : 0u;
}

// THE BYTES A PRINT READS FROM ONE RECORD: its UV (descriptor bit 45 is
// VF_UV, the UV nibble gives the offset, two half floats), or its position
// when the record carries no UV.
inline void PrintField(std::uint64_t desc, std::uint32_t vs, std::uint32_t& off, std::uint32_t& len)
{
    const std::uint32_t uvo = std::uint32_t((desc >> 8) & 0xFu) * 4u;
    if (((desc >> 45) & 1u) && uvo + 4u <= vs) { off = uvo; len = 4u; }
    else { off = 0u; len = vs < 12u ? vs : 12u; }
}

// WHICH MESH, IN WHICH ORDER. FNV-1a over the record count and the UV bytes of
// kSamples records. A body morph moves positions and never UVs, so the print
// survives a morph; records read from the wrong place -- another mesh, or the
// same mesh some records earlier or later -- give a different print.
inline std::uint32_t Print(const std::uint8_t* raw, std::uint32_t n, std::uint32_t vs, std::uint64_t desc)
{
    std::uint32_t h = 2166136261u;
    for (int k = 0; k < 4; ++k) { h ^= (n >> (8 * k)) & 0xFFu; h *= 16777619u; }
    if (!raw || !n || !vs) return h;
    std::uint32_t off = 0, len = 0;
    PrintField(desc, vs, off, len);
    for (unsigned i = 0; i < kSamples; ++i) {
        const std::uint8_t* r = raw + std::size_t(SampleAt(i, n)) * vs + off;
        for (std::uint32_t b = 0; b < len; ++b) { h ^= r[b]; h *= 16777619u; }
    }
    return h;
}

// The positions of the same kSamples records, kept beside the print so a
// re-read can tell how far the body moved since it was built.
struct Samples { float p[kSamples][3]; };

inline void Take(const std::uint8_t* raw, std::uint32_t n, std::uint32_t vs, std::uint64_t desc, Samples& out)
{
    for (unsigned i = 0; i < kSamples; ++i) {
        if (raw && n && vs) flesh::PosOf(raw + std::size_t(SampleAt(i, n)) * vs, desc, out.p[i]);
        else out.p[i][0] = out.p[i][1] = out.p[i][2] = 0.0f;
    }
}

// HOW FAR THE SAMPLED VERTICES MOVED between two takes: the largest distance.
// A sample that is bitwise the same has not moved (a NaN that stayed the same
// NaN is not movement); a distance that is not a finite number is returned as
// HUGE_VALF, which no limit passes.
inline float Moved(const Samples& a, const Samples& b)
{
    float worst = 0.0f;
    for (unsigned i = 0; i < kSamples; ++i) {
        if (std::memcmp(a.p[i], b.p[i], sizeof(a.p[i])) == 0) continue;
        const float dx = a.p[i][0] - b.p[i][0], dy = a.p[i][1] - b.p[i][1], dz = a.p[i][2] - b.p[i][2];
        const float d = std::sqrt(dx * dx + dy * dy + dz * dz);
        if (!(d <= 1.0e30f)) return HUGE_VALF;
        if (d > worst) worst = d;
    }
    return worst;
}

// THE LONGEST TRIANGLE EDGE of idx[0 .. 3 * nTris) over n records. An index
// at or past n is skipped (the caller proved n records readable, no more), and
// so is an edge that is not a finite length under 100,000 units.
inline float MaxEdge(const std::uint8_t* raw, std::uint32_t n, std::uint32_t vs, std::uint64_t desc,
                     const std::uint16_t* idx, std::size_t nTris)
{
    if (!raw || !idx || !vs) return 0.0f;
    float best2 = 0.0f;
    for (std::size_t t = 0; t < nTris; ++t) {
        const std::uint16_t* T = idx + t * 3;
        if (T[0] >= n || T[1] >= n || T[2] >= n) continue;
        float p[3][3];
        for (int k = 0; k < 3; ++k) flesh::PosOf(raw + std::size_t(T[k]) * vs, desc, p[k]);
        for (int k = 0; k < 3; ++k) {
            const float* a = p[k]; const float* b = p[(k + 1) % 3];
            const float dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
            const float d2 = dx * dx + dy * dy + dz * dz;
            if (d2 > best2 && d2 < 1.0e10f) best2 = d2;
        }
    }
    return std::sqrt(best2);
}

// THE EDGE NO TRIANGLE OF A SHAPE CAN HAVE, given the longest edge its own mesh
// had when it was built: twice that, plus two units of allowance for a morph
// that stretched it since. Real body triangles here are about three units at
// most; the scrambled ones measured 12 to 88.
inline float EdgeLimit(float maxEdge) { return 2.0f * maxEdge + 2.0f; }

// HOW MANY TRIANGLES OF A COPIED SHAPE have an edge past `limit`: its own
// records (vdata, n of them) and its own local indices. `longest` (optional)
// receives its longest edge.
inline std::uint32_t LongTris(const std::uint8_t* vdata, std::uint32_t n, std::uint32_t vs, std::uint64_t desc,
                              const std::uint16_t* idx, std::size_t nTris, float limit, float* longest = nullptr)
{
    std::uint32_t bad = 0;
    float best2 = 0.0f;
    const float lim2 = limit * limit;
    if (vdata && idx && vs)
        for (std::size_t t = 0; t < nTris; ++t) {
            const std::uint16_t* T = idx + t * 3;
            if (T[0] >= n || T[1] >= n || T[2] >= n) { ++bad; continue; }
            float p[3][3];
            for (int k = 0; k < 3; ++k) flesh::PosOf(vdata + std::size_t(T[k]) * vs, desc, p[k]);
            float m2 = 0.0f;
            for (int k = 0; k < 3; ++k) {
                const float* a = p[k]; const float* b = p[(k + 1) % 3];
                const float dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
                const float d2 = dx * dx + dy * dy + dz * dz;
                if (!(d2 <= 1.0e30f)) { m2 = HUGE_VALF; break; }
                if (d2 > m2) m2 = d2;
            }
            if (m2 > lim2) ++bad;
            if (m2 > best2) best2 = m2;
        }
    if (longest) *longest = std::sqrt(best2);
    return bad;
}

// SCRAMBLED: one in a hundred of its triangles or more are past the limit, and
// that is at least two of them -- or at least half of a shape of one or two
// triangles. One long triangle in a real shape is left alone (a sliver a morph
// stretched); records read from the wrong place make most triangles long (30%
// to 78% of a whole body or hand at a shift of a single record, measured).
inline bool Scrambled(std::uint32_t longTris, std::size_t nTris)
{
    if (!longTris || std::uint64_t(longTris) * 100u < std::uint64_t(nTris)) return false;
    return longTris >= 2u || 2u * std::uint64_t(longTris) >= std::uint64_t(nTris);
}

// THE VERDICT ON A SHAPE'S RECORDS before a wound is cut from them.
//   held        the pointer the body was built from
//   live        the pointer the engine holds now (null: the chain could not be read)
//   liveOk      `live` is readable for the shape's whole record count
//   layoutSame  the live partition still has the vertex count and descriptor it had
//   prints      Print() at the build and now; moved: Moved() between the two takes
// Same: nothing changed. Repoint: a fresh copy of the same mesh in the same
// order that has not moved past moveLimit -- cut from the new pointer. Stale:
// anything else -- re-read the body before cutting it.
enum class Live { Same, Repoint, Stale };
inline Live Judge(const void* held, const void* live, bool liveOk, bool layoutSame,
                  std::uint32_t heldPrint, std::uint32_t livePrint, float moved, float moveLimit)
{
    if (!live || !liveOk || !layoutSame) return Live::Stale;
    if (livePrint != heldPrint) return Live::Stale;
    if (!(moved <= moveLimit)) return Live::Stale;
    return live == held ? Live::Same : Live::Repoint;
}

// A SHAPE THAT CARRIES A DRAWN CUT is re-pointed only while the plugin's copy
// of its partition is the one installed. Its records can only have moved when
// the partition the cut was written into was swapped out, and then the cut is
// no longer drawn while the shape's bookkeeping still says it is: re-read the
// body instead, which re-cuts it. `written`: a cut was written into the shape;
// `copyInstalled`: the plugin's copy is the partition under the instance now.
inline Live KeepCut(Live v, bool written, bool copyInstalled)
{
    return (v == Live::Repoint && written && !copyInstalled) ? Live::Stale : v;
}

}  // namespace rawguard
