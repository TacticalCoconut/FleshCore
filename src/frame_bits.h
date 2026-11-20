// frame_bits.h -- FleshCore: the pure pieces of the frame pass: a shape's
// stored frame as a rigid transform (validated, composed, inverted), that
// transform applied to a buffer of vertex records in every layout the body
// path admits, and the placement measure that decides whether it is applied.
// Header-only, no engine types, so a test can compile it verbatim beside the
// DLL.
#pragma once
#include <cstdint>
#include <cstddef>
#include <cmath>
#include <cstring>
#include <vector>
#include "facts.h"

namespace frame {

// A TRANSFORM AS THE ENGINE STORES ONE: rotate (row major), translate, one
// uniform scale, in that order and nothing between them (facts.h,
// kSizeof_NiTransform). A point goes through it as scale * (rotate * p) +
// translate; a direction goes through the rotation alone.
struct Xf {
    float r[9] = { 1, 0, 0,  0, 1, 0,  0, 0, 1 };
    float t[3] = { 0, 0, 0 };
    float s    = 1.0f;
};

inline void FromBytes(const std::uint8_t* p, Xf& x)
{
    std::memcpy(x.r, p, 36);
    std::memcpy(x.t, p + 36, 12);
    std::memcpy(&x.s, p + 48, 4);
}

// ---- WHAT MAY BE CALLED A FRAME --------------------------------------------
//
// The bytes come out of live engine memory, through an offset that for one of
// the two sources is recalled rather than measured, so they are taken for a
// transform only when they could not be anything else: every entry a number,
// the three rows of the rotation unit length and at right angles to each
// other, the handedness kept (a mirror is not a way to store a mesh, and
// would turn every triangle inside out), the translate within a few dozen
// body heights and the scale within two orders of magnitude of one. Pointer
// bytes, a freed block or a run of zeroes read as floats fail the first or
// the second of those.
//
// `reach` is how far the translate may go. A frame's is small: the largest
// on a shipping mesh measured is 280 units. A WORLD transform is a place in
// a cell and can be anywhere, so the one caller that reads one says so.
constexpr float  kMaxTranslate = 4096.0f;
constexpr float  kMinScale     = 0.01f;
constexpr float  kMaxScale     = 100.0f;
constexpr double kOrthoTol     = 2e-3;

inline bool Valid(const Xf& x, const char** why = nullptr, float reach = kMaxTranslate)
{
    const char* w = nullptr;
    for (int k = 0; k < 9 && !w; ++k) if (!std::isfinite(x.r[k])) w = "not-a-number";
    for (int k = 0; k < 3 && !w; ++k) if (!std::isfinite(x.t[k])) w = "not-a-number";
    if (!w && !std::isfinite(x.s)) w = "not-a-number";
    if (!w && !(x.s >= kMinScale && x.s <= kMaxScale)) w = "scale-out-of-range";
    for (int k = 0; k < 3 && !w; ++k)
        if (!(std::fabs(x.t[k]) <= reach)) w = "translate-out-of-reach";
    for (int i = 0; i < 3 && !w; ++i)
        for (int j = i; j < 3 && !w; ++j) {
            double d = 0.0;
            for (int k = 0; k < 3; ++k) d += double(x.r[i * 3 + k]) * double(x.r[j * 3 + k]);
            if (!(std::fabs(d - (i == j ? 1.0 : 0.0)) <= kOrthoTol)) w = "not-orthonormal";
        }
    if (!w) {
        const double det =
            double(x.r[0]) * (double(x.r[4]) * x.r[8] - double(x.r[5]) * x.r[7]) -
            double(x.r[1]) * (double(x.r[3]) * x.r[8] - double(x.r[5]) * x.r[6]) +
            double(x.r[2]) * (double(x.r[3]) * x.r[7] - double(x.r[4]) * x.r[6]);
        if (!(det > 0.0)) w = "mirrors";
    }
    if (why) *why = w ? w : "";
    return w == nullptr;
}

// DOES IT TURN ANYTHING. All nine entries, not the diagonal alone: a half
// turn about an axis leaves one diagonal entry at one, and a quarter turn
// leaves one there too.
inline bool RotIdentity(const Xf& x, float tol = 1e-3f)
{
    for (int k = 0; k < 9; ++k)
        if (!(std::fabs(x.r[k] - ((k == 0 || k == 4 || k == 8) ? 1.0f : 0.0f)) < tol)) return false;
    return true;
}
inline bool IsIdentity(const Xf& x, float tolT = 0.01f, float tolR = 1e-3f, float tolS = 1e-3f)
{
    for (int k = 0; k < 3; ++k) if (!(std::fabs(x.t[k]) < tolT)) return false;
    if (!(std::fabs(x.s - 1.0f) < tolS)) return false;
    return RotIdentity(x, tolR);
}

// How far it turns, in degrees, and about which axis (zero when it does not).
inline double AngleDeg(const Xf& x)
{
    double c = (double(x.r[0]) + double(x.r[4]) + double(x.r[8]) - 1.0) * 0.5;
    if (!(c <= 1.0)) c = 1.0;
    if (!(c >= -1.0)) c = -1.0;
    return std::acos(c) * (180.0 / 3.14159265358979323846);
}
inline void Axis(const Xf& x, float out[3])
{
    double a[3] = { double(x.r[7]) - x.r[5], double(x.r[2]) - x.r[6], double(x.r[3]) - x.r[1] };
    double len = std::sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    if (!(len > 1e-4)) {
        // No turn at all, or a half turn: the antisymmetric part vanishes for
        // both, and for a half turn the axis is read off the symmetric part.
        a[0] = a[1] = a[2] = 0.0;
        if (AngleDeg(x) > 90.0) {
            const double xx = (double(x.r[0]) + 1.0) * 0.5, yy = (double(x.r[4]) + 1.0) * 0.5,
                         zz = (double(x.r[8]) + 1.0) * 0.5;
            if (xx >= yy && xx >= zz && xx > 0.0) {
                a[0] = std::sqrt(xx);
                a[1] = (double(x.r[1]) + x.r[3]) / (4.0 * a[0]);
                a[2] = (double(x.r[2]) + x.r[6]) / (4.0 * a[0]);
            } else if (yy >= zz && yy > 0.0) {
                a[1] = std::sqrt(yy);
                a[0] = (double(x.r[1]) + x.r[3]) / (4.0 * a[1]);
                a[2] = (double(x.r[5]) + x.r[7]) / (4.0 * a[1]);
            } else if (zz > 0.0) {
                a[2] = std::sqrt(zz);
                a[0] = (double(x.r[2]) + x.r[6]) / (4.0 * a[2]);
                a[1] = (double(x.r[5]) + x.r[7]) / (4.0 * a[2]);
            }
        }
        len = std::sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    }
    for (int k = 0; k < 3; ++k) out[k] = (len > 1e-9) ? float(a[k] / len) : 0.0f;
}

// a AFTER b: the point goes through b first.
inline Xf Compose(const Xf& a, const Xf& b)
{
    Xf o;
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j) {
            double d = 0.0;
            for (int k = 0; k < 3; ++k) d += double(a.r[i * 3 + k]) * double(b.r[k * 3 + j]);
            o.r[i * 3 + j] = float(d);
        }
    for (int i = 0; i < 3; ++i) {
        double d = 0.0;
        for (int k = 0; k < 3; ++k) d += double(a.r[i * 3 + k]) * double(b.t[k]);
        o.t[i] = float(double(a.s) * d + double(a.t[i]));
    }
    o.s = a.s * b.s;
    return o;
}

// The way back: p = (1 / s) * transpose(R) * (q - t). Only for a transform
// Valid() has passed -- the transpose is the inverse of an orthonormal
// rotation and of nothing else, and the scale is known not to be zero.
inline Xf Inverse(const Xf& a)
{
    Xf o;
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j) o.r[i * 3 + j] = a.r[j * 3 + i];
    o.s = 1.0f / a.s;
    for (int i = 0; i < 3; ++i) {
        double d = 0.0;
        for (int k = 0; k < 3; ++k) d += double(o.r[i * 3 + k]) * double(a.t[k]);
        o.t[i] = float(-double(o.s) * d);
    }
    return o;
}

inline void Apply(const Xf& x, const float p[3], float out[3])
{
    const double a = double(x.r[0]) * p[0] + double(x.r[1]) * p[1] + double(x.r[2]) * p[2];
    const double b = double(x.r[3]) * p[0] + double(x.r[4]) * p[1] + double(x.r[5]) * p[2];
    const double c = double(x.r[6]) * p[0] + double(x.r[7]) * p[1] + double(x.r[8]) * p[2];
    out[0] = float(double(x.s) * a + double(x.t[0]));
    out[1] = float(double(x.s) * b + double(x.t[1]));
    out[2] = float(double(x.s) * c + double(x.t[2]));
}
inline void Turn(const Xf& x, const double v[3], double out[3])
{
    const double a = double(x.r[0]) * v[0] + double(x.r[1]) * v[1] + double(x.r[2]) * v[2];
    const double b = double(x.r[3]) * v[0] + double(x.r[4]) * v[1] + double(x.r[5]) * v[2];
    const double c = double(x.r[6]) * v[0] + double(x.r[7]) * v[1] + double(x.r[8]) * v[2];
    out[0] = a; out[1] = b; out[2] = c;
}

// ---- THE RECORD, FIELD BY FIELD ---------------------------------------------
//
// Read exactly as the other readers of a record read it. The position is
// what flesh::PosOf decodes: three floats at 0, or three halves at 0 when the
// UV sits at offset 8. The packed normal and tangent are where the vertex
// descriptor puts them (facts.h, NormalOffset and TangentOffset): three
// signed bytes each, then one byte of the bitangent, whose x is the float
// after a full-float position.
inline float HalfToFloat(std::uint16_t h)
{
    const int s = (h >> 15) & 1, e = (h >> 10) & 0x1F, m = h & 0x3FF;
    float v;
    if (e == 0)       v = std::ldexp(float(m), -24);
    else if (e == 31) v = m ? NAN : INFINITY;
    else              v = std::ldexp(float(m + 1024), e - 25);
    return s ? -v : v;
}
// Round to nearest, ties to even; past the largest half it stops there
// rather than becoming an infinity, which is not a place a vertex can be.
inline std::uint16_t FloatToHalf(float f)
{
    std::uint32_t x; std::memcpy(&x, &f, 4);
    const std::uint32_t sign = (x >> 16) & 0x8000u;
    const std::uint32_t mag  = x & 0x7FFFFFFFu;
    if (mag > 0x7F800000u)  return std::uint16_t(sign | 0x7E00u);      // not a number
    if (mag >= 0x47800000u) return std::uint16_t(sign | 0x7BFFu);      // 65536 and beyond
    if (mag < 0x33000000u)  return std::uint16_t(sign);                // under half the smallest half
    const int e = int(mag >> 23) - 127;
    const std::uint32_t m = (mag & 0x7FFFFFu) | 0x800000u;
    const int shift = (e < -14) ? 13 + (-14 - e) : 13;
    std::uint32_t h = m >> shift;
    const std::uint32_t rem = m & ((1u << shift) - 1u), halfway = 1u << (shift - 1);
    if (rem > halfway || (rem == halfway && (h & 1u))) ++h;
    if (e >= -14) h += std::uint32_t(e + 14) << 10;
    if (h > 0x7BFFu) h = 0x7BFFu;
    return std::uint16_t(sign | h);
}

inline double UnpackS(std::uint8_t b) { return double(b) * (2.0 / 255.0) - 1.0; }
inline std::uint8_t PackS(double v)
{
    double x = (v * 0.5 + 0.5) * 255.0;
    if (!(x > 0.0)) x = 0.0;
    if (x > 255.0)  x = 255.0;
    return std::uint8_t(x + 0.5);
}

struct Layout {
    bool halfPos = false;             // three halves at 0, not three floats
    bool hasN = false, hasT = false;  // a packed normal; a packed tangent with the bitangent beside it
    std::uint32_t nrm = 0, tan = 0;   // their byte offsets
};
inline bool LayoutOf(std::uint64_t desc, std::uint32_t vsize, Layout& L, const char** why = nullptr)
{
    L = Layout();
    const char* w = nullptr;
    L.halfPos = fact::UVOffset(desc) == 8;
    const std::uint32_t posEnd = L.halfPos ? 8u : 16u;
    if (vsize < (L.halfPos ? 6u : 12u)) w = "record-shorter-than-a-position";
    L.hasN = (desc & fact::kVF_NORMAL) != 0;
    L.hasT = (desc & fact::kVF_TANGENT) != 0;
    L.nrm = fact::NormalOffset(desc);
    L.tan = fact::TangentOffset(desc);
    if (!w && L.hasN && (L.nrm < posEnd || L.nrm + 4u > vsize)) w = "normal-outside-the-record";
    if (!w && L.hasT && (L.tan < posEnd || L.tan + 4u > vsize)) w = "tangent-outside-the-record";
    if (!w && L.hasT && !L.hasN) w = "tangent-without-a-normal";
    if (!w && L.hasT && !L.halfPos && vsize < 16u) w = "no-room-for-the-bitangent";
    if (why) *why = w ? w : "";
    return w == nullptr;
}

// CAN THESE RECORDS TAKE THIS TRANSFORM. A move or a scale needs only the
// position. A turn needs every direction in the record turned with it, and
// on the half-position layout the bitangent's x has no measured home -- no
// mesh measured carries that layout at all -- so a turn is refused there
// rather than applied to two thirds of a vector.
inline bool CanTransform(std::uint64_t desc, std::uint32_t vsize, const Xf& x, const char** why = nullptr)
{
    Layout L;
    if (!LayoutOf(desc, vsize, L, why)) return false;
    if (!RotIdentity(x) && L.halfPos && L.hasT) {
        if (why) *why = "half-position-record-with-tangents";
        return false;
    }
    if (why) *why = "";
    return true;
}

inline void TurnPacked(const Xf& x, double v[3])
{
    double o[3]; Turn(x, v, o);
    const double len = std::sqrt(o[0] * o[0] + o[1] * o[1] + o[2] * o[2]);
    // A real direction comes back unit length; a slot that never held one
    // (all bytes at the midpoint, or zero) is turned and left as it is.
    const double k = (len > 0.5 && len < 1.5) ? 1.0 / len : 1.0;
    v[0] = o[0] * k; v[1] = o[1] * k; v[2] = o[2] * k;
}

// THE WHOLE TRANSFORM, ON EVERY RECORD OF A BUFFER THIS DLL OWNS. Position
// through scale, rotation and translate; normal, tangent and bitangent
// through the rotation, each brought back to unit length before it is
// packed. Every other byte of the record -- UV, colour, weights, bone
// indices -- is left exactly as it was. An identity transform writes
// nothing, and a transform that does not turn leaves the packed directions
// byte for byte. Returns false, having written nothing, when CanTransform
// refuses.
inline bool TransformRecords(std::uint8_t* recs, std::size_t n, std::uint32_t vsize,
                             std::uint64_t desc, const Xf& x)
{
    if (!recs || !n || !vsize) return false;
    if (!CanTransform(desc, vsize, x)) return false;
    if (IsIdentity(x)) return true;
    Layout L; LayoutOf(desc, vsize, L);
    const bool turn = !RotIdentity(x);
    for (std::size_t v = 0; v < n; ++v) {
        std::uint8_t* rec = recs + v * vsize;
        float p[3], q[3];
        if (L.halfPos) {
            std::uint16_t h[3]; std::memcpy(h, rec, 6);
            p[0] = HalfToFloat(h[0]); p[1] = HalfToFloat(h[1]); p[2] = HalfToFloat(h[2]);
            Apply(x, p, q);
            h[0] = FloatToHalf(q[0]); h[1] = FloatToHalf(q[1]); h[2] = FloatToHalf(q[2]);
            std::memcpy(rec, h, 6);
        } else {
            std::memcpy(p, rec, 12);
            Apply(x, p, q);
            std::memcpy(rec, q, 12);
        }
        if (!turn) continue;
        if (L.hasN) {
            double nv[3] = { UnpackS(rec[L.nrm]), UnpackS(rec[L.nrm + 1]), UnpackS(rec[L.nrm + 2]) };
            TurnPacked(x, nv);
            rec[L.nrm] = PackS(nv[0]); rec[L.nrm + 1] = PackS(nv[1]); rec[L.nrm + 2] = PackS(nv[2]);
        }
        if (L.hasT) {
            double tv[3] = { UnpackS(rec[L.tan]), UnpackS(rec[L.tan + 1]), UnpackS(rec[L.tan + 2]) };
            TurnPacked(x, tv);
            rec[L.tan] = PackS(tv[0]); rec[L.tan + 1] = PackS(tv[1]); rec[L.tan + 2] = PackS(tv[2]);
            // The bitangent rides in three places: x after the position, y
            // after the normal, z after the tangent. (hasT with a half
            // position was refused above, so offset 12 is the float.)
            float bx; std::memcpy(&bx, rec + 12, 4);
            double bv[3] = { double(bx), UnpackS(rec[L.nrm + 3]), UnpackS(rec[L.tan + 3]) };
            if (std::isfinite(bx)) {
                TurnPacked(x, bv);
                bx = float(bv[0]);
                std::memcpy(rec + 12, &bx, 4);
                rec[L.nrm + 3] = PackS(bv[1]);
                rec[L.tan + 3] = PackS(bv[2]);
            }
        }
    }
    return true;
}

// ---- IS IT WHERE ITS OWN BONES ARE -----------------------------------------
//
// A read of a transform is a claim; this is the check. Every vertex of a
// shape names the bone it rides, and the body's own flesh says where that
// bone's flesh is in bind space. So for each bone the shape and the body
// share, the centre of the shape's vertices on it is compared with the
// centre of the body's, as read and through the candidate frame, and the
// distances are averaged by vertex count. A garment is not flesh -- a
// pauldron sits on one side of an arm -- so a shape that is in place still
// measures a few units; a shape stored in another frame measures the size of
// the offset, or, turned half a circle, the width of the body.
//
// MEASURED on shipping meshes against the two fill stores. Shapes stored in
// body space read 1.0 to 10.3, and up to 15.8 for a small plate that sits at
// one end of the bone it rides (a knee guard weighted to the thigh). Shapes
// stored in another frame read from 3.6 (a helmet stored five units low, or
// turned half a circle about the vertical through the head it sits on) to
// 196 as stored, and mostly 1.7 to 10.9 through their own node transform.
// So how far a shape reads does not by itself tell the two apart. The GAIN
// tells many of them apart, not all: a cuirass stored 10.8 units off read
// 12.6 as stored and 5.2 through its frame, a gain of 7.5, and a small
// offset or a turn about a shape's own middle gains little or nothing. For
// those the two reads of the frame are the evidence (Decide).
struct BonePlace {
    double c[3] = { 0, 0, 0 };     // centre of the shape's own vertices on this bone, as read
    double n    = 0;               // how many of them
    float  ref[3] = { 0, 0, 0 };   // where the body has that bone's flesh
};
struct Placement {
    bool   have = false;           // enough of the shape rides bones the body can place
    double raw = 0, xf = 0;        // mean distance to its bones, as read and through the frame
    double lift[3] = { 0, 0, 0 };  // mean of (body - shape) as read: the move that would seat it
    unsigned bones = 0;            // bones that voted
    double cover = 0;              // share of its bone-carrying vertices that sit on such a bone
};
constexpr double kMinVotes = 8.0;    // vertices
constexpr double kMinCover = 0.05;
// ONE READ OF A FRAME IS HELD TO THE MEASURE ALONE. As read, within kNear of
// its bones: in place, and not moved. Past that, the frame is taken only if
// it lands the shape within kReach of its bones AND at least kMargin nearer
// to them than it was as read -- so a plate that reads 15 where it belongs
// is not moved by a transform that does not seat it.
//
// TWO READS THAT AGREE ARE TAKEN AT THEIR WORD. A mesh stored in another
// frame usually carries that frame twice: in its node's transform, and
// inverted in its skin data. Where both were read, each undoes the other, and
// the frame moves the shape at all (it turns or scales it, or shifts it
// kMinMove or more), it is applied wherever it lands the shape within kReach
// -- the centroid measure cannot see a helmet turned back to front on the
// head it sits on, nor one stored a cell low -- except that a shape which
// reads in place must land in place too. A leftover node transform on a mesh
// that is in place usually has no inverse in its skin data and stays under
// the rule above. Not always: a boot carries a 1.7-unit node transform with
// its exact inverse in the skin data and is in place as read, which is why
// an agreeing pair that moves the shape less than kMinMove is never taken.
constexpr double kNear    = 12.0;
constexpr double kReach   = 30.0;
constexpr double kMargin  = 8.0;
constexpr double kMinMove = 2.0;

inline Placement Measure(const std::vector<BonePlace>& in, double bonedVerts, const Xf* x)
{
    Placement P;
    double w = 0.0;
    for (const BonePlace& b : in) {
        if (!(b.n > 0.0)) continue;
        const float c[3] = { float(b.c[0]), float(b.c[1]), float(b.c[2]) };
        float cx[3] = { c[0], c[1], c[2] };
        if (x) Apply(*x, c, cx);
        double dr = 0.0, dx = 0.0;
        for (int k = 0; k < 3; ++k) {
            const double a = double(c[k]) - double(b.ref[k]), e = double(cx[k]) - double(b.ref[k]);
            dr += a * a; dx += e * e;
            P.lift[k] += b.n * (double(b.ref[k]) - double(c[k]));
        }
        P.raw += b.n * std::sqrt(dr);
        P.xf  += b.n * std::sqrt(dx);
        w += b.n;
        ++P.bones;
    }
    if (w > 0.0) {
        P.raw /= w; P.xf /= w;
        for (int k = 0; k < 3; ++k) P.lift[k] /= w;
    }
    P.cover = (bonedVerts > 0.0) ? w / bonedVerts : 0.0;
    P.have = w >= kMinVotes && P.cover >= kMinCover && std::isfinite(P.raw) && std::isfinite(P.xf);
    return P;
}

enum Verdict {
    kAsRead = 0,        // no candidate frame: nothing to decide
    kApply,             // the frame seats it on its bones: use it
    kKeptInPlace,       // a candidate frame, but as read it is already on its bones
    kRefusedNoRef,      // a candidate frame, and nothing on the body to check it against
    kRefusedFar         // a candidate frame that does not seat it on its bones
};
// Does this frame move a shape by enough to matter: a turn, a scale, or a
// shift of kMinMove or more.
inline bool Moves(const Xf& x)
{
    if (!RotIdentity(x) || !(std::fabs(x.s - 1.0f) < 1e-3f)) return true;
    return double(x.t[0]) * x.t[0] + double(x.t[1]) * x.t[1] + double(x.t[2]) * x.t[2] >= kMinMove * kMinMove;
}
// `agreed`: the node transform and the skin data were both read as rigid,
// each undoes the other, and the frame Moves.
inline Verdict Decide(bool haveFrame, const Placement& P, bool agreed = false)
{
    if (!haveFrame) return kAsRead;
    if (!P.have) return kRefusedNoRef;
    if (agreed && P.xf <= kReach && (P.raw > kNear || P.xf <= kNear)) return kApply;
    if (P.raw <= kNear) return kKeptInPlace;
    if (P.xf <= kReach && P.raw - P.xf >= kMargin) return kApply;
    return kRefusedFar;
}

}  // namespace frame
