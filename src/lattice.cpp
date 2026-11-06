#include "lattice.h"
#include <cmath>
#include <cstring>
#include <deque>
#include <functional>
#include <algorithm>
#include <array>
#include <unordered_map>
#include <unordered_set>
#include <map>
#include <set>
#include <vector>
#include <chrono>

namespace flesh {

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
    // UV nibble 2 is the marker for the half-precision position layout the
    // engine uses on some meshes; every mesh measured so far is full floats,
    // but the branch costs nothing and a wrong guess here would silently
    // scatter every cell.
    if (((desc >> 8) & 0xF) == 2) {
        const std::uint16_t* h = reinterpret_cast<const std::uint16_t*>(rec);
        out[0] = HalfToFloat(h[0]); out[1] = HalfToFloat(h[1]); out[2] = HalfToFloat(h[2]);
    } else {
        std::memcpy(out, rec, 12);
    }
}

std::uint32_t CapWound(const std::uint16_t* orig, std::uint32_t origTris,
                       std::vector<std::uint16_t>& keep, std::uint32_t maxTris)
{
    if (!orig || !origTris || maxTris == 0) return 0;
    auto key = [](std::uint16_t a, std::uint16_t b) {
        return (a < b) ? ((std::uint32_t(a) << 16) | b) : ((std::uint32_t(b) << 16) | a);
    };

    // how many triangles shared each edge BEFORE the cut
    std::map<std::uint32_t, int> before;
    for (std::uint32_t t = 0; t < origTris; ++t)
        for (int k = 0; k < 3; ++k) {
            const std::uint16_t a = orig[t*3 + k], b = orig[t*3 + (k+1)%3];
            if (a != b) ++before[key(a, b)];
        }

    // and after, keeping the direction the surviving triangle used it in
    std::map<std::uint32_t, int> after;
    std::map<std::uint32_t, std::pair<std::uint16_t, std::uint16_t>> dir;
    const std::uint32_t nk = std::uint32_t(keep.size() / 3);
    for (std::uint32_t t = 0; t < nk; ++t)
        for (int k = 0; k < 3; ++k) {
            const std::uint16_t a = keep[t*3 + k], b = keep[t*3 + (k+1)%3];
            if (a == b) continue;
            const std::uint32_t e = key(a, b);
            ++after[e];
            dir[e] = std::make_pair(a, b);
        }

    // an edge the cut opened: shared before, exposed now
    std::vector<std::pair<std::uint16_t, std::uint16_t>> rim;
    for (const auto& [e, n] : after) {
        if (n != 1) continue;
        auto b2 = before.find(e);
        if (b2 == before.end() || b2->second < 2) continue;   // an original border
        rim.push_back(dir[e]);
    }
    if (rim.size() < 3) return 0;

    // group the rim into loops, so two separate holes are never sewn together
    std::map<std::uint16_t, std::uint16_t> parent;
    std::function<std::uint16_t(std::uint16_t)> find =
        [&](std::uint16_t x) {
            while (true) {
                auto it = parent.find(x);
                if (it == parent.end()) { parent[x] = x; return x; }
                if (it->second == x) return x;
                x = it->second;
            }
        };
    for (const auto& [a, b] : rim) {
        const std::uint16_t ra = find(a), rb = find(b);
        if (ra != rb) parent[rb] = ra;
    }
    std::map<std::uint16_t, std::uint16_t> hub;      // loop root -> its fan hub
    for (const auto& [a, b] : rim) hub.emplace(find(a), a);

    std::uint32_t added = 0;
    for (const auto& [a, b] : rim) {
        if (added + 2 > maxTris) break;
        const std::uint16_t h = hub[find(a)];
        if (h == a || h == b) continue;              // degenerate at the hub
        // The removed triangle used this edge the other way round, so b->a->h
        // faces the way the surface used to. Both windings are emitted anyway:
        // a cut face that can only be seen from one side is how this went wrong
        // in the first place.
        keep.push_back(b); keep.push_back(a); keep.push_back(h);
        keep.push_back(a); keep.push_back(b); keep.push_back(h);
        added += 2;
    }
    return added;
}

// Bind space: a body is ~130 units tall and reaches under 100 from the root.
// See the guard in Build for why this is set seventy-five times too big.
static const float kSaneReach = 10000.0f;

void Lattice::Build(const std::vector<ShapeData>& shapes,
                    const std::vector<std::vector<TriRef>>& tris,
                    float cellSize, float clearGain, float jointGain)
{
    cells.clear();
    boneSeed.clear();
    bridge.clear();
    severed.clear();
    shapeLayer.clear();
    triCell.assign(tris.size(), std::vector<std::uint16_t>());
    cellCount = 0;
    triCellProven = false;
    // Sized to the harvest and filled as each triangle finds its cell; a
    // triangle that never does keeps kNoCell.
    for (std::size_t si = 0; si < tris.size(); ++si) triCell[si].assign(tris[si].size(), kNoCell);
    for (const ShapeData& S : shapes) shapeLayer.push_back(S.layer);
    cell = cellSize > 0.25f ? cellSize : 6.0f;
    bool first = true;
    std::size_t insane = 0;      // triangles at impossible positions -- see the guard below

    // KEYED BY THE INTERNED POINTER, NOT BY THE TEXT. This is indexed once per
    // TRIANGLE, and a std::string key meant constructing a quarter of a million
    // strings and walking a red-black tree with them, per actor, to add three
    // doubles. The names come from the plugin's own intern table, so the
    // pointer identifies the bone exactly as well and costs nothing.
    std::unordered_map<const char*, std::array<double, 4>> seedAcc;
    const bool fcprof = getenv("FC_PROF") != nullptr;
    auto pstamp = std::chrono::steady_clock::now();
    auto psay = [&](const char* what) {
        if (!fcprof) return;
        const auto now = std::chrono::steady_clock::now();
        std::fprintf(stderr, "    [prof] %-22s %6.1f ms\n", what,
            std::chrono::duration_cast<std::chrono::microseconds>(now - pstamp).count()/1000.0);
        pstamp = now;
    };

    // ---- THEIR SKIN, INDEXED BY CELL -------------------------------------
    //
    // Built before anything else because the fill shapes are interleaved with
    // the skin ones in harvest order, and a lump cannot be measured against a
    // surface that has not been read yet.
    //
    // Only shapes they ARE, not shapes they are wearing: a flared robe sits a
    // hand's width off their thigh, and letting it stand in for skin would give
    // every lump behind it enormous clearance and mark none of them.
    struct SkinPt { float p[3]; std::uint8_t part; };
    std::map<Key, std::vector<SkinPt>> skinAt;
    std::size_t nSkinPts = 0;
    if (clearGain > 0.0f) {
        for (std::size_t si = 0; si < shapes.size(); ++si) {
            const ShapeData& S = shapes[si];
            if (!S.skin || S.lumpTris || !S.verts || !S.vsize) continue;
            for (std::uint32_t v = 0; v < S.nVerts; ++v) {
                float q[3];
                PosOf(S.verts + std::size_t(v) * S.vsize, S.desc, q);
                SkinPt sp;
                sp.p[0] = q[0]; sp.p[1] = q[1]; sp.p[2] = q[2];
                sp.part = std::uint8_t(v < S.vertBone.size() && S.vertBone[v]
                                       ? PartOfBone(S.vertBone[v]) : Part::Unknown);
                Key k{ std::int32_t(std::floor(q[0] / cellSize)),
                       std::int32_t(std::floor(q[1] / cellSize)),
                       std::int32_t(std::floor(q[2] / cellSize)) };
                skinAt[k].push_back(sp);
                ++nSkinPts;
            }
        }
    }
    // Their nearest skin vertex to a point, and how many named PARTS the skin
    // around it belongs to. Two parts within reach means a joint, and a joint
    // is where the skin creases inward under animation -- so the bind-pose
    // clearance measured here overstates the room a lump really has, and the
    // caller asks for a harder threshold there.
    auto measure = [&](const float c[3], float& clear, bool& joint) {
        clear = 1e30f; joint = false;
        const std::int32_t bx = std::int32_t(std::floor(c[0] / cellSize));
        const std::int32_t by = std::int32_t(std::floor(c[1] / cellSize));
        const std::int32_t bz = std::int32_t(std::floor(c[2] / cellSize));
        std::uint32_t seen = 0;
        for (std::int32_t dx = -1; dx <= 1; ++dx)
        for (std::int32_t dy = -1; dy <= 1; ++dy)
        for (std::int32_t dz = -1; dz <= 1; ++dz) {
            auto it = skinAt.find(Key{ bx+dx, by+dy, bz+dz });
            if (it == skinAt.end()) continue;
            for (const SkinPt& sp : it->second) {
                const float ex = sp.p[0]-c[0], ey = sp.p[1]-c[1], ez = sp.p[2]-c[2];
                const float d2 = ex*ex + ey*ey + ez*ez;
                if (d2 < clear) clear = d2;
                if (sp.part) seen |= 1u << sp.part;
            }
        }
        clear = (clear >= 1e29f) ? 1e30f : std::sqrt(clear);
        // more than one named part in the neighbourhood
        joint = (seen & (seen - 1)) != 0;
    };
    std::size_t nShallow = 0, nMeasured = 0;

    for (std::size_t si = 0; si < shapes.size() && si < tris.size(); ++si) {
        const ShapeData& S = shapes[si];
        if (!S.verts || !S.vsize) continue;

        // WHERE EACH TRIANGLE BELONGS. For a surface, its own centroid. For a
        // field of lumps, the centroid of the WHOLE LUMP -- so a lump is taken
        // or left as one thing however far it spills over a cell line.
        std::vector<float> lumpC;
        std::vector<std::uint8_t> lumpShallow;
        if (S.lumpTris) {
            const std::size_t nL = tris[si].size() / S.lumpTris;
            lumpC.assign(nL * 3, 0.0f);
            std::vector<double> acc(nL * 3, 0.0);
            std::vector<std::uint32_t> cnt(nL, 0);
            for (std::size_t ti = 0; ti < tris[si].size(); ++ti) {
                const std::size_t li = ti / S.lumpTris;
                if (li >= nL) break;
                const TriRef& t = tris[si][ti];
                for (int k = 0; k < 3; ++k) {
                    if (t.v[k] >= S.nVerts) continue;
                    float q[3];
                    PosOf(S.verts + std::size_t(t.v[k]) * S.vsize, S.desc, q);
                    acc[li*3] += q[0]; acc[li*3+1] += q[1]; acc[li*3+2] += q[2];
                    ++cnt[li];
                }
            }
            for (std::size_t li = 0; li < nL; ++li)
                if (cnt[li])
                    for (int k = 0; k < 3; ++k)
                        lumpC[li*3+k] = float(acc[li*3+k] / cnt[li]);

            // ---- WHICH OF THESE LUMPS CAN REACH THEIR SKIN -----------------
            //
            // A lump only ever surfaces if it sits closer to the skin than it
            // can reach, so that is the whole test: clearance against its own
            // corner radius.
            //
            // THE RADIUS IS MEASURED ONCE PER SHAPE, from the first lump, not
            // once per lump. Every lump in a fill shape is the same box built
            // by the same generator, and the comment forty lines down explains
            // what re-reading vertex records per triangle costs on a body
            // where the fill is three quarters of the geometry.
            if (clearGain > 0.0f && nL) {
                float rad = 0.0f;
                for (std::size_t ti = 0; ti < S.lumpTris && ti < tris[si].size(); ++ti) {
                    const TriRef& t = tris[si][ti];
                    for (int k = 0; k < 3; ++k) {
                        if (t.v[k] >= S.nVerts) continue;
                        float q[3];
                        PosOf(S.verts + std::size_t(t.v[k]) * S.vsize, S.desc, q);
                        const float ex = q[0]-lumpC[0], ey = q[1]-lumpC[1], ez = q[2]-lumpC[2];
                        const float d = ex*ex + ey*ey + ez*ez;
                        if (d > rad) rad = d;
                    }
                }
                rad = std::sqrt(rad);
                lumpShallow.assign(nL, 0);
                for (std::size_t li = 0; li < nL; ++li) {
                    float clear; bool joint;
                    measure(&lumpC[li*3], clear, joint);
                    if (clear >= 1e29f) continue;      // no skin near it at all
                    const float gain = joint ? (jointGain > 0.0f ? jointGain : clearGain)
                                             : clearGain;
                    ++nMeasured;
                    if (clear < rad * gain) { lumpShallow[li] = 1; ++nShallow; }
                }
            }
        }

        Cell* memoCell = nullptr; Key memoKey{}; std::size_t memoShape = 0;
        bool memoOK = false;
        for (std::size_t ti = 0; ti < tris[si].size(); ++ti) {
            const TriRef& t = tris[si][ti];
            float c[3];
            // A LUMP'S TRIANGLES DO NOT NEED THEIR OWN CENTROIDS. Every one of
            // them is placed by the lump's centre, computed once above, so
            // reading three vertex records per triangle and averaging them was
            // work whose only result was overwritten on the next line. On this
            // body the fill is 185,220 of 249,964 triangles, so that was half
            // a million wasted vertex reads per actor -- and voxelising is the
            // stall a wound is felt as.
            if (S.lumpTris) {
                const std::size_t li = ti / S.lumpTris;
                if (li * 3 + 2 >= lumpC.size()) continue;
                c[0] = lumpC[li*3]; c[1] = lumpC[li*3+1]; c[2] = lumpC[li*3+2];
                if (t.v[0] >= S.nVerts || t.v[1] >= S.nVerts || t.v[2] >= S.nVerts) continue;
            } else {
                float p[3][3];
                bool ok = true;
                for (int k = 0; k < 3; ++k) {
                    if (t.v[k] >= S.nVerts) { ok = false; break; }
                    PosOf(S.verts + std::size_t(t.v[k]) * S.vsize, S.desc, p[k]);
                }
                if (!ok) continue;
                c[0] = (p[0][0] + p[1][0] + p[2][0]) / 3.0f;
                c[1] = (p[0][1] + p[1][1] + p[2][1]) / 3.0f;
                c[2] = (p[0][2] + p[1][2] + p[2][2]) / 3.0f;
            }
            // ---- AND A TRIANGLE HAS TO BE SOMEWHERE --------------
            //
            // FIELD: a target voxelised into FORTY-ONE sections --
            // one of 1020 cells and forty of ONE cell each -- and the bridging
            // that ran afterwards reported gaps of 22, 31, 676, 6,364 and
            // 63,970,268 units. Sixty-four million units is not a place on a
            // body; it is a garbage position, and it built a cell, and a cell
            // is a section. Dismemberment and the orphan sweep are both gated
            // on their arriving in ONE section, so forty stray cells turned the
            // whole engine off for them.
            //
            // Those cells existed before the weld was keyed on position. What changed is that the
            // weld used to key vertices on a HASH with no position comparison,
            // and a hash that collides for a third of a body-sized grid
            // silently welded garbage into whatever real vertex it landed on --
            // so the strays were dragged into the main mass and nobody saw
            // them. The position key stops hiding them.
            //
            // The bound is deliberately enormous. Positions here are bind
            // space, where they stand about 130 units tall and their widest
            // reach is under 100 from the root. Ten thousand is seventy-five
            // times their height, so nothing real is anywhere near it, and both
            // NaN and infinity fail the comparison whichever way it is written.
            if (!(std::fabs(c[0]) < kSaneReach && std::fabs(c[1]) < kSaneReach
                                              && std::fabs(c[2]) < kSaneReach)) {
                ++insane;
                continue;
            }
            if (first) {
                lo[0] = hi[0] = c[0]; lo[1] = hi[1] = c[1]; lo[2] = hi[2] = c[2];
                first = false;
            } else {
                for (int k = 0; k < 3; ++k) {
                    if (c[k] < lo[k]) lo[k] = c[k];
                    if (c[k] > hi[k]) hi[k] = c[k];
                }
            }
            Key k{ std::int32_t(std::floor(c[0] / cell)),
                   std::int32_t(std::floor(c[1] / cell)),
                   std::int32_t(std::floor(c[2] / cell)) };
            // ONE-ENTRY MEMO. Triangles arrive shape by shape and a lump's
            // hundred and eight all land in the same cell, so the cell this
            // triangle wants is nearly always the cell the last one wanted:
            // remembering it turns a quarter of a million map lookups and set
            // insertions into a couple of thousand.
            if (!(memoOK && k == memoKey && memoShape == si)) {
                auto found = cells.find(k);
                if (found == cells.end()) {
                    found = cells.emplace(k, Cell()).first;
                    found->second.key = k;
                    // Numbered as created; the table below carries the number.
                    found->second.ord = std::uint16_t(cellCount < 0x7FFFu ? cellCount : 0x7FFFu);
                    ++cellCount;
                }
                memoCell = &found->second;
                memoCell->shapes.insert(std::uint32_t(si));
                memoKey = k; memoShape = si; memoOK = true;
            }
            Cell& C = *memoCell;
            std::uint16_t partBits = t.part;
            if (!lumpShallow.empty()) {
                const std::size_t li = ti / S.lumpTris;
                if (li < lumpShallow.size() && lumpShallow[li])
                    partBits |= TriRef::kShallow;
            }
            C.tris.push_back(TriRef{ std::uint32_t(si), partBits, { t.v[0], t.v[1], t.v[2] } });
            if (ti < triCell[si].size())
                triCell[si][ti] = std::uint16_t(C.ord | ((partBits & TriRef::kShallow) ? kTriShallow : 0));
            C.layers |= 1u << S.layer;
            // AND WHETHER ANY OF IT IS THEIR SKIN, which is not the same question
            // as `mine` below: a cell can be theirs because it holds fill and
            // still hold no skin at all. The head's by-layer death rule counts
            // this rather than layer bit 0 -- see Cell::isSkin.
            // ...AND ONLY SKIN THAT COUNTS: see ShapeData::skinCounts.
            // `mine` below is untouched by it -- their face is theirs.
            if (S.skin && S.skinCounts) C.isSkin = true;
            // Their skin, or anything under it. A layer-0 shape that is not skin,
            // or a layer-4 shape (worn armour), is something they are WEARING,
            // and a cell holding only that is a cell of wardrobe rather than a
            // cell of the target.
            if (S.skin || (S.layer > 0 && S.layer < kLayerArmour)) C.mine = true;

            // the bone that owns this triangle, and the bone seed it feeds
            const char* bn = nullptr;
            for (int q = 0; q < 3 && !bn; ++q)
                if (t.v[q] < S.vertBone.size()) bn = S.vertBone[t.v[q]];
            if (bn) {
                std::array<double, 4>& a = seedAcc[bn];
                a[0] += c[0]; a[1] += c[1]; a[2] += c[2]; a[3] += 1.0;
            }
        }
    }

    // KEPT AND COUNTED, SO THE LOG SHOWS WHEN THE GUARD FIRES. This
    // file has no logger of its own by design, so the count is handed to the
    // caller, which prints it. If it is ever non-zero, some shape is giving
    // the lattice positions that are not on a body, and THAT is the bug -- the
    // guard only stops it turning dismemberment off for them.
    insaneTris = insane;
    psay("bin triangles");
    // per-cell centroid and owning bone
    for (auto& [k, C] : cells) {
        double s[3] = {0, 0, 0};
        std::map<const char*, int> tally;
        for (const TriRef& t : C.tris) {
            const ShapeData& S = shapes[t.shape];
            // A cell's own middle is an average of what is in it, and a lump's
            // triangles all sit at the lump's centre for that purpose -- which
            // is where this cell put them in the first place. Reading their
            // vertices a second time changes the answer by less than the cell
            // is wide and costs another three quarters of a million reads.
            if (S.lumpTris) {
                s[0] += C.key.x * cell + cell * 0.5;
                s[1] += C.key.y * cell + cell * 0.5;
                s[2] += C.key.z * cell + cell * 0.5;
            } else {
                float p[3][3];
                for (int q = 0; q < 3; ++q)
                    PosOf(S.verts + std::size_t(t.v[q]) * S.vsize, S.desc, p[q]);
                for (int d = 0; d < 3; ++d) s[d] += (p[0][d] + p[1][d] + p[2][d]) / 3.0;
            }
            for (int q = 0; q < 3; ++q)
                if (t.v[q] < S.vertBone.size() && S.vertBone[t.v[q]])
                    ++tally[S.vertBone[t.v[q]]];
        }
        const double n = double(C.tris.size() ? C.tris.size() : 1);
        C.c[0] = float(s[0] / n); C.c[1] = float(s[1] / n); C.c[2] = float(s[2] / n);
        int best = 0;
        for (auto& [bn, v] : tally) if (v > best) { best = v; C.bone = bn; }
        // Cached here and nowhere else: this is the one place the owning bone
        // is decided, so it is the one place the part can be decided with it.
        C.part = static_cast<std::uint8_t>(PartOfBone(C.bone));
    }

    psay("cell centroids");
    for (auto& [bn, a] : seedAcc)
        if (a[3] > 0)
            boneSeed[bn] = { float(a[0] / a[3]), float(a[1] / a[3]), float(a[2] / a[3]) };

    psay("bone seeds");
    BuildAdjacency(shapes);
    psay("adjacency");
    // Before any remembered damage goes back, and on the adjacency the sweep
    // walks (the bridges BridgeSections adds later join strays that had no
    // neighbour at all, so they are not in these counts, and need not be).
    ComputeTearBirth();
    psay("tear birth");
    BuildRuns();
    psay("runs");
    ProveTriCell();
    psay("triangle table");
    // Counted here, reported by the caller: this file has no logger of its
    // own and every other diagnostic in it is handed out the same way.
    skinPts       = nSkinPts;
    measuredLumps = nMeasured;
    shallowLumps  = nShallow;
}

// THE TABLE IS CHECKED AGAINST THE CELLS BEFORE ANYTHING TRUSTS IT. Per cell:
// the number of table entries naming it must equal the number of TriRefs in
// it, shallow bit for shallow bit; per shape: the number of entries that name
// any cell must equal the shape's TriRefs across all cells. A table that fails
// either count is emptied, and the redraw walks the cells as before.
void Lattice::ProveTriCell()
{
    triCellProven = false;
    if (cellCount == 0 || cellCount > 0x7FFFu) { triCell.clear(); return; }
    std::vector<std::uint32_t> named(cellCount, 0), shallowNamed(cellCount, 0);
    std::vector<std::uint32_t> perShapeTable(triCell.size(), 0);
    for (std::size_t si = 0; si < triCell.size(); ++si)
        for (std::uint16_t e : triCell[si]) {
            if (e == kNoCell) continue;
            const std::uint16_t o = std::uint16_t(e & 0x7FFF);
            if (o >= cellCount) { triCell.clear(); return; }
            ++named[o];
            if (e & kTriShallow) ++shallowNamed[o];
            ++perShapeTable[si];
        }
    std::vector<std::uint32_t> perShapeCells(triCell.size(), 0);
    for (const auto& kv : cells) {
        const Cell& C = kv.second;
        if (C.ord >= cellCount) { triCell.clear(); return; }
        std::uint32_t sh = 0;
        for (const TriRef& t : C.tris) {
            if (t.Shallow()) ++sh;
            if (t.shape < perShapeCells.size()) ++perShapeCells[t.shape];
        }
        if (named[C.ord] != C.tris.size() || shallowNamed[C.ord] != sh) { triCell.clear(); return; }
    }
    for (std::size_t si = 0; si < triCell.size(); ++si)
        if (perShapeTable[si] != perShapeCells[si]) { triCell.clear(); return; }
    triCellProven = true;
}

// ---- THE TEAR RULE'S BIRTH COUNTS ----------------------------------
//
// Per part: the mean of its cell centroids and their principal axis -- the
// covariance's largest eigenvector by power iteration, seeded with the bbox
// diagonal so it starts near the answer, thirty rounds, which on a limb whose
// length is five times its width converges in a handful. The axis is only ever
// used to slice the part across itself, so its sign does not matter and its
// exactness barely does. Per LIMB part: how many of its cells touch (through
// Neighbours, which is what the sweep walks) a cell of the part it hangs from.
// Everything is alive when this runs -- it is the end of Build, before any
// remembered damage goes back -- so these are what they were born with.
void Lattice::ComputeTearBirth()
{
    const std::size_t N = std::size_t(Part::Count);
    for (std::size_t p = 0; p < N; ++p) {
        partAxis[p][0] = partAxis[p][1] = partAxis[p][2] = 0.0f;
        partOrigin[p][0] = partOrigin[p][1] = partOrigin[p][2] = 0.0f;
        partCellsBirth[p] = 0; jointBirth[p] = 0;
    }
    double sum[std::size_t(Part::Count)][3] = {};
    double plo[std::size_t(Part::Count)][3], phi[std::size_t(Part::Count)][3];
    for (std::size_t p = 0; p < N; ++p)
        for (int i = 0; i < 3; ++i) { plo[p][i] = 1e30; phi[p][i] = -1e30; }
    for (const auto& [k, C] : cells) {
        const std::size_t p = C.part;
        if (p == 0 || p >= N) continue;
        ++partCellsBirth[p];
        for (int i = 0; i < 3; ++i) {
            sum[p][i] += C.c[i];
            if (C.c[i] < plo[p][i]) plo[p][i] = C.c[i];
            if (C.c[i] > phi[p][i]) phi[p][i] = C.c[i];
        }
    }
    for (std::size_t p = 1; p < N; ++p) {
        const std::uint32_t n = partCellsBirth[p];
        if (!n) continue;
        double o[3] = { sum[p][0] / n, sum[p][1] / n, sum[p][2] / n };
        for (int i = 0; i < 3; ++i) partOrigin[p][i] = float(o[i]);
        // the covariance, over this part's cells only
        double cov[3][3] = {};
        for (const auto& [k, C] : cells) {
            if (C.part != p) continue;
            const double d[3] = { C.c[0] - o[0], C.c[1] - o[1], C.c[2] - o[2] };
            for (int i = 0; i < 3; ++i) for (int j = 0; j < 3; ++j) cov[i][j] += d[i] * d[j];
        }
        double v[3] = { phi[p][0] - plo[p][0], phi[p][1] - plo[p][1], phi[p][2] - plo[p][2] };
        double len = std::sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
        if (!(len > 1e-6)) { v[0] = 0; v[1] = 0; v[2] = 1; len = 1; }
        for (int i = 0; i < 3; ++i) v[i] /= len;
        for (int round = 0; round < 30; ++round) {
            double w[3] = {
                cov[0][0]*v[0] + cov[0][1]*v[1] + cov[0][2]*v[2],
                cov[1][0]*v[0] + cov[1][1]*v[1] + cov[1][2]*v[2],
                cov[2][0]*v[0] + cov[2][1]*v[1] + cov[2][2]*v[2] };
            const double wl = std::sqrt(w[0]*w[0] + w[1]*w[1] + w[2]*w[2]);
            if (!(wl > 1e-9)) break;          // a single cell, or all on a point
            for (int i = 0; i < 3; ++i) v[i] = w[i] / wl;
        }
        for (int i = 0; i < 3; ++i) partAxis[p][i] = float(v[i]);
    }
    // the joints, on the same neighbourhood the sweep walks
    for (const auto& [k, C] : cells) {
        const Part p = Part(C.part);
        if (!PartIsLimb(p)) continue;
        const Part par = PartParent(p);
        bool touches = false;
        for (const Key& n : Neighbours(k)) {
            auto jt = cells.find(n);
            if (jt != cells.end() && Part(jt->second.part) == par) { touches = true; break; }
        }
        if (touches) ++jointBirth[std::size_t(p)];
    }
}

std::size_t Lattice::Tear(std::vector<Key>& sel, float frac, void (*say)(const char*, ...)) const
{
    if (!(frac > 0.0f) || sel.empty()) return 0;
    if (frac > 1.0f) frac = 1.0f;
    const float keepAtMost = 1.0f - frac;   // live cells at or under this share of birth tear
    auto pack = [](const Key& k) {
        return (std::uint64_t(std::uint32_t(k.x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(k.y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(k.z) & 0x1FFFFFu) << 42);
    };
    std::unordered_set<std::uint64_t> going;
    going.reserve(sel.size() * 4);
    for (const Key& k : sel) going.insert(pack(k));
    // "still there once this wound has gone through": alive on any layer and
    // not in the selection
    auto stays = [&](const Key& k, const Cell& C) { return C.Alive(kAllLayers) && !going.count(pack(k)); };
    // which parts the wound touches at all, and which of those are limbs
    std::uint32_t touchedAny = 0, touched = 0;
    for (const Key& k : sel) {
        auto it = cells.find(k);
        if (it == cells.end()) continue;
        touchedAny |= 1u << it->second.part;
        if (PartIsLimb(Part(it->second.part))) touched |= 1u << it->second.part;
    }
    // The joint is asked of every limb part the wound touches and of every
    // limb part that hangs from a part it touches -- a bite at the elbow takes
    // cells of the upper arm and of the forearm, and it is the forearm's joint
    // count that says whether the forearm still hangs there; a bite in the
    // armpit may take nothing but chest and still leave the upper arm joined
    // by a third of what joined it.
    std::uint32_t ask = touched;
    for (int q = 1; q < int(Part::Count); ++q) {
        const Part par = PartParent(Part(q));
        if (par != Part::Unknown && (touchedAny & (1u << unsigned(par)))) ask |= 1u << q;
    }
    if (!touched && !ask) return 0;
    std::size_t added = 0;
    auto take = [&](const std::vector<Key>& ks) {
        for (const Key& k : ks) { if (going.insert(pack(k)).second) { sel.push_back(k); ++added; } }
    };

    // ---- THE LAYER: the rest of any slice the wound has mostly taken ---------
    for (int q = 1; q < int(Part::Count); ++q) {
        const Part P = Part(q);
        if (!(touched & (1u << q)) || !partCellsBirth[q]) continue;
        const float* a = partAxis[q];
        const float* o = partOrigin[q];
        // slice -> [born, staying], and the staying cells by slice
        std::map<int, std::array<std::uint32_t, 3>> slice;   // born, staying, going now
        std::map<int, std::vector<Key>> staying;
        for (const auto& [k, C] : cells) {
            if (C.part != q) continue;
            const float t = (C.c[0] - o[0]) * a[0] + (C.c[1] - o[1]) * a[1] + (C.c[2] - o[2]) * a[2];
            const int b = int(std::floor(t / cell));
            auto& s = slice[b];
            ++s[0];
            if (going.count(pack(k))) ++s[2];
            else if (C.Alive(kAllLayers)) { ++s[1]; staying[b].push_back(k); }
        }
        std::uint32_t slices = 0, born = 0, stay = 0, torn = 0;
        for (auto& [b, s] : slice) {
            if (!s[2] || !s[1]) continue;                          // untouched, or already through
            if (float(s[1]) > keepAtMost * float(s[0])) continue;  // most of the slice still stands
            take(staying[b]);
            ++slices; born += s[0]; stay += s[1]; torn += s[1];
        }
        if (slices && say)
            say("  tear: the wound leaves %u of %u cell(s) standing across %u slice(s) of the %s"
                " -- at most %.0f%% may -- so the %u tear too",
                unsigned(stay), unsigned(born), unsigned(slices), PartName(P),
                double(keepAtMost) * 100.0, unsigned(torn));
    }

    // ---- THE JOINT: the rest of any joint the wound has mostly taken --------
    for (int q = 1; q < int(Part::Count); ++q) {
        const Part P = Part(q);
        if (!(ask & (1u << q)) || !jointBirth[q]) continue;
        const Part par = PartParent(P);
        std::vector<Key> hold;
        for (const auto& [k, C] : cells) {
            if (C.part != q || !stays(k, C)) continue;
            for (const Key& n : Neighbours(k)) {
                auto jt = cells.find(n);
                if (jt == cells.end() || Part(jt->second.part) != par) continue;
                if (!stays(n, jt->second)) continue;
                hold.push_back(k);
                break;
            }
        }
        if (hold.empty()) continue;                                   // already off them
        if (float(hold.size()) > keepAtMost * float(jointBirth[q])) continue;
        take(hold);
        if (say)
            say("  tear: the %s would hang from the %s by %u of the %u cell(s) that joined them"
                " -- at most %.0f%% may -- so those %u tear too and it comes away",
                PartName(P), PartName(par), unsigned(hold.size()), unsigned(jointBirth[q]),
                double(keepAtMost) * 100.0, unsigned(hold.size()));
    }
    return added;
}

std::size_t Lattice::TearTrunkAtPlane(std::vector<Key>& sel, float frac, void (*say)(const char*, ...)) const
{
    // Only the plane this wound's SelectPlane() recorded WITH a reach: a
    // spell's slab already strips the whole body, and no plane is no cut.
    if (!haveLastPlane || !(lastPlaneReach > 0.0f)) return 0;
    if (!(frac > 0.0f) || sel.empty()) return 0;
    if (frac > 1.0f) frac = 1.0f;
    // HALF WHAT THE TEAR LETS A LIMB KEEP. Half a shoulder does not hold an arm;
    // half a torso holds them together, and at the limb's own fraction a sword
    // through a shallow chest, front to back, halved them on 44 blows of 88.
    // A quarter at TE 0.5 keeps every tested case: a greatsword
    // leaves the far side a strip.
    const float keepAtMost = (1.0f - frac) * 0.5f;
    const float px = lastPlaneP[0], py = lastPlaneP[1], pz = lastPlaneP[2];
    const float nx = lastPlaneN[0], ny = lastPlaneN[1], nz = lastPlaneN[2];
    const float band = lastPlaneHalf + 1e-3f;
    auto pack = [](const Key& k) {
        return (std::uint64_t(std::uint32_t(k.x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(k.y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(k.z) & 0x1FFFFFu) << 42);
    };
    std::unordered_set<std::uint64_t> going;
    going.reserve(sel.size() * 2);
    for (const Key& k : sel) going.insert(pack(k));
    // The trunk's band at the plane, against birth: every chest and abdomen
    // cell as close to the plane as the slab went, dead ones included, so a
    // second blow along the same line counts what the first one took -- and
    // only within the plane's own part scope, the one SelectPlane() took and
    // SeverPlane() cuts by, so a row scoped to their chest never tears their
    // belly. THEIR OWN CELLS VOTE (Cell::mine), the way the loss rules count:
    // a robe a fire burned off is no part of how far a blade got through them.
    // A worn cell standing in the band still tears with the rest.
    const std::uint32_t parts = lastPlaneParts;
    std::uint32_t born = 0, taking = 0, left = 0, over = 0, under = 0;
    float far2 = 0.0f;
    std::vector<Key> staying;
    for (const auto& [k, C] : cells) {
        if (C.part != std::uint8_t(Part::Chest) && C.part != std::uint8_t(Part::Abdomen)) continue;
        if (parts && !(parts & (1u << C.part))) continue;
        const float vx = C.c[0] - px, vy = C.c[1] - py, vz = C.c[2] - pz;
        const float d = vx * nx + vy * ny + vz * nz;
        const bool taken = going.count(pack(k)) != 0;
        if (!(std::fabs(d) <= band)) {
            if (C.mine && !taken && C.Alive(kAllLayers)) { if (d > 0.0f) ++over; else ++under; }
            continue;
        }
        far2 = std::max(far2, vx * vx + vy * vy + vz * vz - d * d);
        if (C.mine) ++born;
        if (taken) { if (C.mine) ++taking; }
        else if (C.Alive(kAllLayers)) { staying.push_back(k); if (C.mine) ++left; }
    }
    if (!taking) return 0;                                             // the plane missed the trunk
    if (float(left) > keepAtMost * float(born)) return 0;              // a gash: its reach still bounds it
    // THE TRUNK HAS TO GO ON PAST THE PLANE, BOTH WAYS. The band alone says how
    // much of the slice was taken, and a slice can be a handful of cells: a
    // plane at crotch height has four cells of belly between the thighs, a
    // sword takes them, and it is not through anything -- going by the band
    // alone cut both legs off. What a cut can part is the
    // trunk on one side from the trunk on the other, so a tenth of what still
    // stands has to be on the lesser side.
    const std::uint32_t lesser = std::min(over, under);
    if (!lesser || lesser * 10u < over + under) return 0;
    for (const Key& k : staying) sel.push_back(k);
    // AS FAR AS THE TRUNK GOES, AND AN ARM'S THICKNESS PAST IT. An arm lying
    // against the far side is joined to the chest above and below the plane,
    // so it has to be cut too or it holds the two halves together; nothing
    // further off can do that, and clearing the reach instead took a leg
    // lengthwise on a plane that only passed it.
    constexpr float kArmThick = 16.0f;
    lastPlaneReach = std::max(lastPlaneReach, std::sqrt(far2) + kArmThick);
    if (say)
        say("  tear: the cut plane takes %u of their %u trunk cell(s) in its band and leaves %u -- at most %.0f%%"
            " may -- so it went THROUGH: the %u cell(s) left in the band tear too, and the cut now reaches %.0f units",
            unsigned(taking), unsigned(born), unsigned(left), double(keepAtMost) * 100.0,
            unsigned(staying.size()), double(lastPlaneReach));
    return staying.size();
}

void Lattice::BuildRuns()
{
    resortedCells = 0;
    for (auto& kv : cells) {
        Cell& C = kv.second;
        C.runs.clear();
        // Build pushes shape by shape, so this is expected to be already in
        // order. It is checked: a cell whose triangles
        // arrived out of order is sorted (stably -- the order within a shape
        // is kept) and counted, so the log can say it happened.
        bool ordered = true;
        for (std::size_t i = 1; i < C.tris.size(); ++i)
            if (C.tris[i].shape < C.tris[i - 1].shape) { ordered = false; break; }
        if (!ordered) {
            std::stable_sort(C.tris.begin(), C.tris.end(),
                             [](const TriRef& a, const TriRef& b) { return a.shape < b.shape; });
            ++resortedCells;
        }
        std::size_t i = 0;
        while (i < C.tris.size()) {
            const std::uint32_t sh = C.tris[i].shape;
            std::size_t j = i + 1;
            while (j < C.tris.size() && C.tris[j].shape == sh) ++j;
            C.runs.push_back(Cell::Run{ sh, std::uint32_t(i), std::uint32_t(j) });
            i = j;
        }
    }
}

// Weld by position, then let shared vertices define what is connected.
//
// A body mesh is cut open along its UV seams -- down the flanks here -- and
// the vertices either side of a seam sit at the same point but carry
// unrelated indices. Treating them as distinct would make the torso two
// surfaces that never touch, and a wound would come off as a half-shell.
void Lattice::BuildAdjacency(const std::vector<ShapeData>& shapes)
{
    adj.clear();

    std::unordered_map<std::int64_t, std::uint32_t> weld;      // quantised position -> id
    std::unordered_map<std::uint32_t, std::vector<Key>> owners; // welded id -> cells
    std::uint32_t next = 0;

    auto idOf = [&](const float p[3]) {
        // 1/16 unit lattice: finer than any seam gap, coarser than float noise
        const std::int64_t qx = std::int64_t(std::llround(p[0] * 16.0));
        const std::int64_t qy = std::int64_t(std::llround(p[1] * 16.0));
        const std::int64_t qz = std::int64_t(std::llround(p[2] * 16.0));
        // ---- AND THE KEY IS THE POSITION, NOT A HASH OF IT ------
        //
        // This used to be `(qx * 73856093) ^ (qy * 19349663) ^ (qz * 83492791)`
        // -- the Teschner spatial hash -- looked up in a map with NO position
        // comparison on a hit. That is a hash used as an identity, and it
        // welds any two points that collide. Measured over the integer grid a
        // body occupies: K(x,y,z) == K(-x,-y,z) for 53,377 of 160,801 pairs,
        // a THIRD of them, because negating two of the three products leaves
        // the exclusive-or unchanged for a large family of values. On a shape
        // symmetric about their vertical axis -- a torc, a circlet, a hood rim,
        // a belt -- that welded points up to eighty-two units apart into one
        // vertex: 16.5% of the points on a test sphere centred on that axis.
        // (Organic, y-asymmetric flesh measured 0%, which is why nothing ever
        // showed.)
        //
        // The pack is exact and is the one this file already uses in
        // Sections(): twenty-one bits an axis at 1/16 unit is +/-65,536 units,
        // some five hundred times a body's height, so there is no collision left
        // to reason about.
        const std::int64_t key = std::int64_t(
              (std::uint64_t(std::uint32_t(std::int32_t(qx)) & 0x1FFFFFu))
            | (std::uint64_t(std::uint32_t(std::int32_t(qy)) & 0x1FFFFFu) << 21)
            | (std::uint64_t(std::uint32_t(std::int32_t(qz)) & 0x1FFFFFu) << 42));
        auto it = weld.find(key);
        if (it != weld.end()) return it->second;
        weld[key] = next;
        return next++;
    };

    // THE WELD IS FOR SEAMS, AND ONLY A SURFACE HAS SEAMS.
    //
    // This pass existed to join the two halves of a body that is cut open
    // along its UV seams: same point in space, unrelated indices. A field of
    // lumps has no seams -- each lump is its own closed volume, and two lumps
    // in neighbouring cells overlap in space without ever sharing a vertex, so
    // running the weld over them linked nothing and cost everything. Measured
    // on this body: 185,220 of 249,964 triangles are fill, and this function
    // was three quarters of the time an actor spends being voxelised -- which is the
    // stall a wound is felt as. Their cells are joined by the grid pass below
    // instead, which is what actually connected them all along.
    // ---- AND ONLY THEIR OWN SURFACE HAS THE SEAMS THIS IS FOR --------
    //
    // A triangle is BINNED by its centroid (Lattice::Build) and WELDED by each
    // of its three vertices, and nothing here bounds how far a vertex is from
    // the cell the triangle landed in. That is harmless on skin, whose
    // triangles are a fraction of a cell. It is not harmless on a HAIR CARD: a
    // card is a long thin strip, and one card triangle two cells long welds
    // cells two rows apart -- while a Form::LayerZ slab is one row thick, by
    // its own definition. So when hair was first admitted into the lattice,
    // Cleave Skull stopped taking the top of a wig-wearing target's head off:
    // the row went entire and their skull above the cut was still joined to their
    // skull below it, through a weld the cut could not reach. Seen in testing
    // and reproduced in a test: a wig of one-cell cards
    // separates, a wig of two-cell cards does not.
    //
    // HANDING THE CARDS OVER BONELESS DOES NOT HELP, which is what rules out
    // the obvious fix. The weld is geometry, not bone: a cell holding both
    // skull and hair triangles is Part::Head on the skull's vote and carries
    // the hair's distant vertices into the weld regardless. Measured in the
    // same test.
    //
    // The pass exists to join the two halves of THEIR BODY where a UV seam
    // splits it. Their wardrobe -- a hat, a sleeve, a legging, a wig -- is also
    // joined to them by the grid pass below, which has no shape condition, but
    // taking it out of this pass fragments them: see the vertex bound below.
    //
    // NOT a distance bound on the link, which was the first thing tried and
    // was wrong twice over: at one cell it makes this whole
    // pass a strict subset of the grid pass below -- dead code that still pays
    // the hash -- and at any larger reach it leaves the hair bridge in place.
    std::vector<std::uint32_t> ids;
    for (auto& [k, C] : cells) {
        ids.clear();
        for (const TriRef& t : C.tris) {
            const ShapeData& S = shapes[t.shape];
            if (S.lumpTris) continue;
            for (int q = 0; q < 3; ++q) {
                float p[3];
                PosOf(S.verts + std::size_t(t.v[q]) * S.vsize, S.desc, p);
                // ---- AND THE VERTEX HAS TO BE IN THIS CELL -------
                //
                // The bound is on the VERTEX, not on the shape and not on the
                // link. Taking their whole wardrobe out of this pass was tried first:
                // in testing a Bisect forged a piece
                // of "15 cell(s), 1 of them, 14 worn" with T=2 -- two triangles
                // stretched across fifteen cells, a flat rectangle
                // on screen -- and section counts rose from a maximum
                // of five to nine. A robe weighted across their waist WAS
                // carrying real connectivity, and taking it out of the weld
                // fragmented them.
                //
                // So keep every shape and refuse only the thing that actually
                // caused the head bug: a vertex FAR FROM THE CELL ITS TRIANGLE
                // LANDED IN. A triangle is binned by its centroid, so a small
                // triangle's corners are in that cell or the next one, and a
                // hair card's are two or three cells away. Refusing those
                // leaves every genuine seam -- same point in space, small
                // triangles, adjacent cells -- exactly where it was.
                const Key vk{ std::int32_t(std::floor(p[0] / cell)),
                              std::int32_t(std::floor(p[1] / cell)),
                              std::int32_t(std::floor(p[2] / cell)) };
                const std::int32_t ddx = vk.x - k.x, ddy = vk.y - k.y, ddz = vk.z - k.z;
                const std::int32_t adx = ddx < 0 ? -ddx : ddx, ady = ddy < 0 ? -ddy : ddy,
                                   adz = ddz < 0 ? -ddz : ddz;
                std::int32_t cheb = adx; if (ady > cheb) cheb = ady; if (adz > cheb) cheb = adz;
                if (cheb > 1) continue;
                ids.push_back(idOf(p));
            }
        }
        std::sort(ids.begin(), ids.end());
        ids.erase(std::unique(ids.begin(), ids.end()), ids.end());
        for (std::uint32_t id : ids) owners[id].push_back(k);
    }
    static const int N[27][3] = {
        {-1,-1,-1},{-1,-1,0},{-1,-1,1},{-1,0,-1},{-1,0,0},{-1,0,1},{-1,1,-1},{-1,1,0},{-1,1,1},
        { 0,-1,-1},{ 0,-1,0},{ 0,-1,1},{ 0,0,-1},{ 0,0,0},{ 0,0,1},{ 0,1,-1},{ 0,1,0},{ 0,1,1},
        { 1,-1,-1},{ 1,-1,0},{ 1,-1,1},{ 1,0,-1},{ 1,0,0},{ 1,0,1},{ 1,1,-1},{ 1,1,0},{ 1,1,1},
    };
    // Propagate named anatomy parts into adjacent Part::Unknown (robe/cloak) cells
    // so wardrobe cells cannot act as an untyped bridge between non-touching parts
    // (such as bridging LCalf directly to Abdomen or RThigh across a severed thigh).
    for (int pass = 0; pass < 2; ++pass) {
        std::vector<std::pair<Key, std::uint8_t>> assign;
        for (const auto& [k, C] : cells) {
            if (C.part != std::uint8_t(Part::Unknown)) continue;
            int counts[int(Part::Count)] = {};
            int bestP = 0, bestN = 0;
            for (const auto& d : N) {
                const Key nk{ k.x + d[0], k.y + d[1], k.z + d[2] };
                if (nk == k) continue;
                auto it = cells.find(nk);
                if (it == cells.end() || it->second.part == std::uint8_t(Part::Unknown)) continue;
                const int p = int(it->second.part);
                if (p > 0 && p < int(Part::Count) && ++counts[p] > bestN) {
                    bestN = counts[p]; bestP = p;
                }
            }
            if (bestP > 0) assign.emplace_back(k, std::uint8_t(bestP));
        }
        for (const auto& [k, p] : assign) cells[k].part = p;
    }
    auto canLinkCells = [&](const Key& ka, const Key& kb) -> bool {
        auto ia = cells.find(ka);
        auto ib = cells.find(kb);
        if (ia == cells.end() || ib == cells.end()) return false;
        const std::uint8_t pa = ia->second.part, pb = ib->second.part;
        if (pa != std::uint8_t(Part::Unknown) && pb != std::uint8_t(Part::Unknown) && pa != pb) {
            if (!PartsTouch(Part(pa), Part(pb))) return false;
        }
        return true;
    };
    for (auto& [id, ks] : owners)
        for (std::size_t a = 0; a < ks.size(); ++a)
            for (std::size_t b = a + 1; b < ks.size(); ++b) {
                if (!canLinkCells(ks[a], ks[b])) continue;
                adj[ks[a]].insert(ks[b]);
                adj[ks[b]].insert(ks[a]);
            }

    // (b) cells that touch on the grid are neighbours, provided their anatomical parts touch.
    for (auto& [k, C] : cells)
        for (const auto& d : N) {
            const Key n{ k.x + d[0], k.y + d[1], k.z + d[2] };
            if (n == k) continue;
            if (!canLinkCells(k, n)) continue;
            adj[k].insert(n); adj[n].insert(k);
        }
}

const std::set<Key>& Lattice::Neighbours(const Key& k) const
{
    static const std::set<Key> kEmpty;
    auto it = adj.find(k);
    return it == adj.end() ? kEmpty : it->second;

}

std::size_t Lattice::LiveCells() const
{
    std::size_t n = 0;
    for (const auto& [k, C] : cells) if (!C.Empty()) ++n;
    return n;
}

std::size_t Lattice::LiveTris() const
{
    std::size_t n = 0;
    for (const auto& [k, C] : cells)
        for (const TriRef& t : C.tris) {
            const int L = t.shape < shapeLayer.size() ? shapeLayer[t.shape] : 0;
            if (!(C.gone & (1u << L))) ++n;
        }
    return n;
}

std::vector<Key> Lattice::Within(const float p[3], float r, std::uint32_t mask) const
{
    std::vector<Key> out;
    const float r2 = r * r;
    for (const auto& [k, C] : cells) {
        if (!C.Alive(mask)) continue;
        const float dx = C.c[0] - p[0], dy = C.c[1] - p[1], dz = C.c[2] - p[2];
        if (dx*dx + dy*dy + dz*dz <= r2) out.push_back(k);
    }
    return out;
}

std::vector<Key> Lattice::All(std::uint32_t mask) const
{
    std::vector<Key> out;
    for (const auto& [k, C] : cells) if (C.Alive(mask)) out.push_back(k);
    return out;
}


bool Lattice::NearestLive(const float p[3], std::uint32_t mask, float out[3],
                          float* dist, int* liveCount, std::uint32_t parts) const
{
    const Cell* best = nullptr;
    float bestD = 1e30f;
    int live = 0;
    for (const auto& [k, C] : cells) {
        if (!C.Alive(mask, parts)) continue;
        ++live;
        const float dx = C.c[0]-p[0], dy = C.c[1]-p[1], dz = C.c[2]-p[2];
        const float d = dx*dx + dy*dy + dz*dz;
        if (d < bestD) { bestD = d; best = &C; }
    }
    if (liveCount) *liveCount = live;
    if (!best) return false;
    out[0] = best->c[0]; out[1] = best->c[1]; out[2] = best->c[2];
    if (dist) *dist = std::sqrt(bestD);
    return true;
}

std::vector<Key> Lattice::Flood(const float p[3], float r, int maxCells,
                                std::uint32_t mask, std::uint32_t parts) const
{
    // seed: the live cell whose centroid is nearest the wound point
    const Key* seed = nullptr;
    const float* seedC = nullptr;
    float bestD = 1e30f;
    for (const auto& [k, C] : cells) {
        if (!C.Alive(mask, parts)) continue;
        const float dx = C.c[0]-p[0], dy = C.c[1]-p[1], dz = C.c[2]-p[2];
        const float d = dx*dx + dy*dy + dz*dz;
        if (d < bestD) { bestD = d; seed = &C.key; seedC = C.c; }
    }
    if (!seed) return {};
    if (maxCells < 1) maxCells = 1;
    const float r2 = r * r;
    const float* ctr = (bestD <= r2 * 0.25f || !seedC) ? p : seedC;

    std::set<Key> seen;
    std::vector<Key> out;
    std::deque<Key> q;
    q.push_back(*seed);
    seen.insert(*seed);
    while (!q.empty() && int(out.size()) < maxCells) {
        const Key k = q.front(); q.pop_front();
        auto it = cells.find(k);
        if (it == cells.end() || !it->second.Alive(mask, parts)) continue;
        const float dx = it->second.c[0]-ctr[0], dy = it->second.c[1]-ctr[1], dz = it->second.c[2]-ctr[2];
        if (dx*dx + dy*dy + dz*dz > r2) continue;
        out.push_back(k);
        for (const Key& n : Neighbours(k)) {
            if (seen.count(n)) continue;
            auto jt = cells.find(n);
            if (jt == cells.end() || !jt->second.Alive(mask, parts)) continue;
            seen.insert(n);
            q.push_back(n);
        }
    }
    return out;
}

std::vector<std::vector<Key>> Lattice::Islands(const std::vector<Key>& sel, int maxCells) const
{
    std::set<Key> pool(sel.begin(), sel.end());
    std::vector<std::vector<Key>> out;
    if (maxCells < 1) maxCells = 1;

    // Breadth-first over the lattice's own neighbourhood WITHIN the selection
    // -- 26 grid neighbours plus welded vertices plus bridges.
    // Taking
    // cells in BFS order and cutting at maxCells is what makes an oversized
    // island fragment into compact lumps rather than into arbitrary slices:
    // every fragment is still a connected run that grew outward from a seed.

    while (!pool.empty()) {
        std::vector<Key> island;
        std::deque<Key> q;
        Key seed = *pool.begin();
        pool.erase(pool.begin());
        q.push_back(seed);
        while (!q.empty() && int(island.size()) < maxCells) {
            Key k = q.front(); q.pop_front();
            island.push_back(k);
            for (const Key& n : Neighbours(k)) {
                auto it = pool.find(n);
                if (it != pool.end()) { pool.erase(it); q.push_back(n); }
            }
        }
        // anything the cut left queued goes back for the next island, so the
        // remainder of a big lump stays connected instead of being orphaned
        for (const Key& k : q) pool.insert(k);
        if (!island.empty()) out.push_back(std::move(island));
    }
    return out;
}

// See the header for why this is by SIZE where Fuse is by count.
std::vector<std::vector<Key>> Lattice::AbsorbSmall(const std::vector<std::vector<Key>>& isl,
                                                   std::size_t minCells) const
{
    if (minCells < 2 || isl.size() < 2) return isl;
    std::vector<std::vector<Key>> cur = isl;
    const std::size_t n = cur.size();
    auto packKey = [](const Key& k) -> std::uint64_t {
        return (std::uint64_t(std::uint32_t(k.x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(k.y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(k.z) & 0x1FFFFFu) << 42);
    };
    std::size_t totalCells = 0;
    for (const auto& v : cur) totalCells += v.size();
    std::unordered_map<std::uint64_t, std::size_t> owner;
    owner.reserve(totalCells * 2 + 16);
    for (std::size_t i = 0; i < n; ++i)
        for (const Key& k : cur[i]) owner[packKey(k)] = i;
    std::vector<std::set<std::size_t>> touch(n);
    for (std::size_t i = 0; i < n; ++i)
        for (const Key& k : cur[i])
            for (const Key& nb : Neighbours(k)) {
                auto it = owner.find(packKey(nb));
                if (it != owner.end() && it->second != i) {
                    touch[i].insert(it->second);
                    touch[it->second].insert(i);
                }
            }
    for (;;) {
        // The smallest island that is under the minimum AND has somewhere to
        // go. Smallest first so the specks disappear before anything larger is
        // touched.
        std::size_t pick = n, best = 0;
        for (std::size_t i = 0; i < n; ++i) {
            if (cur[i].empty() || cur[i].size() >= minCells || touch[i].empty()) continue;
            if (pick == n || cur[i].size() < best) { pick = i; best = cur[i].size(); }
        }
        if (pick == n) break;                       // nothing left to absorb
        // Into its SMALLEST touching neighbour, so a wound comes apart into
        // several even pieces rather than one boulder and a crowd of specks.
        std::size_t into = *touch[pick].begin();
        for (std::size_t j : touch[pick])
            if (cur[j].size() < cur[into].size()) into = j;
        cur[into].insert(cur[into].end(), cur[pick].begin(), cur[pick].end());
        cur[pick].clear();
        touch[into].erase(pick);
        for (std::size_t nb : touch[pick]) {
            touch[nb].erase(pick);
            if (nb != into) {
                touch[nb].insert(into);
                touch[into].insert(nb);
            }
        }
        touch[pick].clear();
    }
    std::vector<std::vector<Key>> out;
    out.reserve(n);
    for (auto& v : cur)
        if (!v.empty()) out.push_back(std::move(v));
    return out;
}

std::vector<std::vector<Key>> Lattice::Fuse(const std::vector<std::vector<Key>>& isl,
                                            int perPiece) const
{
    // WHY THIS EXISTS. Islands() cuts a wound into compact runs and each run
    // becomes an object, so a big bite came apart into a dozen small things
    // that fell separately. Anything whose cells TOUCH is one piece of the body, so
    // touching islands are fused -- up to `perPiece` of them -- and the rule
    // when there is a choice is to take the biggest group available rather
    // than the most groups: larger pieces, fewer of them.
    if (perPiece < 2 || isl.size() < 2) return isl;
    const std::size_t n = isl.size();

    // Which islands touch which, over the same neighbourhood the lattice uses
    // everywhere else -- 26 grid neighbours, plus welded vertices
    // (of every shape but the fill lumps),
    // plus any anatomy bridges. NOT named `adj`: that would shadow the member of the
    // same name in this class.
    auto packKey = [](const Key& k) -> std::uint64_t {
        return (std::uint64_t(std::uint32_t(k.x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(k.y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(k.z) & 0x1FFFFFu) << 42);
    };
    std::size_t totalCells = 0;
    for (const auto& v : isl) totalCells += v.size();
    std::vector<std::set<std::size_t>> touch(n);
    std::unordered_map<std::uint64_t, std::size_t> owner;
    owner.reserve(totalCells * 2 + 16);
    for (std::size_t i = 0; i < n; ++i)
        for (const Key& k : isl[i]) owner[packKey(k)] = i;
    for (std::size_t i = 0; i < n; ++i)
        for (const Key& k : isl[i])
            for (const Key& nb : Neighbours(k)) {
                auto it = owner.find(packKey(nb));
                if (it != owner.end() && it->second != i) {
                    touch[i].insert(it->second);
                    touch[it->second].insert(i);
                }
            }

    std::vector<char> taken(n, 0);
    std::vector<std::vector<Key>> out;
    // FULLEST FIRST, which is what "larger over more" means: a pass that
    // only accepts groups of the full size runs before the pass that accepts
    // smaller ones, so an island that could complete a triple is never spent
    // making a pair.
    for (int want = perPiece; want >= 1; --want) {
        for (std::size_t i = 0; i < n; ++i) {
            if (taken[i]) continue;
            // grow outward from i through untaken neighbours
            std::vector<std::size_t> grp{ i };
            std::deque<std::size_t> q(touch[i].begin(), touch[i].end());
            std::set<std::size_t> seen{ i };
            while (!q.empty() && int(grp.size()) < want) {
                const std::size_t j = q.front(); q.pop_front();
                if (taken[j] || !seen.insert(j).second) continue;
                grp.push_back(j);
                for (std::size_t m : touch[j]) if (!taken[m]) q.push_back(m);
            }
            if (int(grp.size()) != want) continue;      // not this pass's size
            std::vector<Key> merged;
            for (std::size_t j : grp) {
                taken[j] = 1;
                merged.insert(merged.end(), isl[j].begin(), isl[j].end());
            }
            out.push_back(std::move(merged));
        }
    }
    return out;
}

// THE ONE TABLE. Order must match the Form enum exactly, and the static_assert
// below is what makes "must" mean something: adding a form without a name here
// is now a compile error rather than a crash at startup three hours later.
static constexpr const char* const kFormNames[] = {
    "bite", "slabx", "slaby", "slabz",
    "borex", "borey", "borez",
    "scatter", "all", "layerz", "halve", "grind",
    "diagf", "diags", "neck", "midhead", "crown", "restore",
    "layerx", "layery", "detonate",
};

// AND THE CHECK IS PER NAME, NOT A COUNT.
//
// A static_assert that compares only the COUNT of the names
// against the count of the enum passes with the names in a
// different ORDER from the enum: "neck", "restore", "midhead", "crown" against
// Neck, MidHead, Crown, Restore. Eighteen names, eighteen values, assertion
// satisfied, and every spell from MidHead on wired to the wrong form --
// Crown running a Restore, Restore a head-locked band that selects nothing.
//
// So every name is pinned to its own enum value by
// a constexpr compare, so inserting a form without inserting its name in the
// same place fails the BUILD, naming the form.
constexpr bool CEq(const char* a, const char* b)
{
    return (*a == *b) && (*a == '\0' || CEq(a + 1, b + 1));
}
#define FC_PIN(F, S) static_assert(CEq(kFormNames[int(Lattice::Form::F)], S), \
    "kFormNames[" #F "] is not \"" S "\" -- the names and the enum have drifted")
FC_PIN(Bite,       "bite");
FC_PIN(SlabX,      "slabx");   FC_PIN(SlabY,  "slaby");   FC_PIN(SlabZ, "slabz");
FC_PIN(BoreX,      "borex");   FC_PIN(BoreY,  "borey");   FC_PIN(BoreZ, "borez");
FC_PIN(Scatter,    "scatter"); FC_PIN(Everything, "all"); FC_PIN(LayerZ, "layerz");
FC_PIN(Halve,      "halve");   FC_PIN(Grind,  "grind");
FC_PIN(DiagF,      "diagf");   FC_PIN(DiagS,  "diags");
FC_PIN(Neck,       "neck");    FC_PIN(MidHead, "midhead");
FC_PIN(Crown,      "crown");   FC_PIN(Restore, "restore");
FC_PIN(LayerX,     "layerx");  FC_PIN(LayerY, "layery");
FC_PIN(Detonate,   "detonate");
#undef FC_PIN
static_assert(sizeof(kFormNames) / sizeof(*kFormNames)
                  == static_cast<std::size_t>(Lattice::Form::Count),
              "every Lattice::Form needs a name in kFormNames, in enum order");

static constexpr const char* const kAnchorNames[] = {
    "aim", "centre", "front", "back", "top", "bottom", "left", "right",
};
static_assert(sizeof(kAnchorNames)/sizeof(*kAnchorNames) == std::size_t(Anchor::Count),
              "every Anchor needs a name, in enum order");
#define FC_APIN(A, S) static_assert(CEq(kAnchorNames[int(Anchor::A)], S), \
    "kAnchorNames[" #A "] is not \"" S "\" -- the names and the enum have drifted")
FC_APIN(Aim, "aim");     FC_APIN(Centre, "centre");
FC_APIN(Front, "front"); FC_APIN(Back,   "back");
FC_APIN(Top, "top");     FC_APIN(Bottom, "bottom");
FC_APIN(Left, "left");   FC_APIN(Right,  "right");
#undef FC_APIN

const char* AnchorName(Anchor a)
{
    const int i = int(a);
    if (i < 0 || i >= int(Anchor::Count)) return "?";
    return kAnchorNames[i];
}

bool AnchorFromName(const std::string& s, Anchor& out)
{
    for (int i = 0; i < int(Anchor::Count); ++i)
        if (_stricmp(s.c_str(), kAnchorNames[i]) == 0) { out = Anchor(i); return true; }
    return false;
}

// THE ANCHOR, OVER THEIR OWN LIVE CELLS.
//
// The extremes are taken from the CENTROIDS of live cells rather than from a
// bounding box of geometry, for the same reason Halve asks the lattice about
// their abdomen: a centroid is a place there is flesh, and a bounding box corner
// is a place there might be nothing. "The front of their head" is therefore the
// front of what is LEFT of their head -- cut their face off and Unmask's next cast
// moves back with it, which is the intended behaviour.
bool Lattice::PartAnchor(std::uint32_t parts, Anchor a, std::uint32_t mask,
                         float out[3]) const
{
    if (a == Anchor::Aim) return false;
    // ---- OVER ONE PIECE of THE BODY, NOT OVER EVERYTHING WEARING THAT BONE -----
    //
    // The mean of every cell tagged with a part is only the middle of that
    // part when the part is in one place. It is not, as testing showed:
    // a target in a chef's hat, with a second clump of
    // Head-tagged geometry far down their body, gave a head anchor at z 65 --
    // below their navel, in the empty air between the two clumps. CleaveSkull
    // (layerz) then took the row through the nearest live head cell to that
    // point, which is the bottom of their head, and cut their NECK, four casts
    // running. Field report: Cleave Skull was hitting the neck.
    //
    // So a filtered anchor is measured over the biggest connected piece of
    // that part, and biggest is counted in THEIR OWN cells: a hat is Head cells
    // too, and the mean of a hat is not the middle of a head. Unfiltered
    // anchors (parts == 0, the whole body) are untouched -- they are one
    // connected thing and the pass would only cost time.
    // PACKED, and `filtered` rather than "the set is empty": a piece with no
    // cells at all would otherwise read as "no filter" and measure the
    // anchor over the hat as well.
    auto packK = [](const Key& k) {
        return (std::uint64_t(std::uint32_t(k.x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(k.y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(k.z) & 0x1FFFFFu) << 42);
    };
    std::unordered_set<std::uint64_t> only;
    bool filtered = false;
    if (parts) {
        // UNCONDITIONAL ONCE THERE IS A FILTER AT ALL. The pass to find out
        // how many pieces there are IS the pass, so branching on ps.size() > 1
        // saves nothing and leaves a second code path that is never exercised
        // when the part happens to arrive whole. One piece filters to itself.
        const std::vector<Section> ps = Sections(*this, mask, parts);
        if (!ps.empty()) {
            std::size_t best = 0, bestMine = 0;
            for (std::size_t i = 0; i < ps.size(); ++i) {
                std::size_t mineHere = 0;
                for (int q = 1; q < int(Part::Count); ++q)
                    if (parts & (1u << unsigned(q))) mineHere += ps[i].minePer[std::size_t(q)];
                if (i == 0 || mineHere > bestMine) { bestMine = mineHere; best = i; }
            }
            only.reserve(ps[best].cells.size() * 2);
            for (const Key& k : ps[best].cells) only.insert(packK(k));
            filtered = true;
        }
    }
    double s[3] = {0,0,0};
    float lo[3] = { 1e30f, 1e30f, 1e30f }, hi[3] = { -1e30f, -1e30f, -1e30f };
    std::size_t n = 0;
    for (const auto& [k, C] : cells) {
        if (!C.Alive(mask, parts)) continue;
        if (filtered && !only.count(packK(k))) continue;
        for (int q = 0; q < 3; ++q) {
            s[q] += double(C.c[q]);
            if (C.c[q] < lo[q]) lo[q] = C.c[q];
            if (C.c[q] > hi[q]) hi[q] = C.c[q];
        }
        ++n;
    }
    if (!n) return false;
    for (int q = 0; q < 3; ++q) out[q] = float(s[q] / double(n));
    switch (a) {
    case Anchor::Centre: break;
    case Anchor::Front:  out[1] = hi[1]; break;
    case Anchor::Back:   out[1] = lo[1]; break;
    case Anchor::Top:    out[2] = hi[2]; break;
    case Anchor::Bottom: out[2] = lo[2]; break;
    case Anchor::Left:   out[0] = hi[0]; break;
    case Anchor::Right:  out[0] = lo[0]; break;
    default: break;
    }
    return true;
}

const char* Lattice::FormName(Form f)
{
    const int i = int(f);
    if (i < 0 || i >= int(Form::Count)) return "?";
    return kFormNames[i];
}

// BOTH DIRECTIONS OFF THE SAME TABLE, so they cannot disagree. This used to be
// eleven hand-written string compares beside a hand-written array of ten
// names, which is how the two came apart.
bool Lattice::FormFromName(const std::string& s, Form& out)
{
    for (int i = 0; i < int(Form::Count); ++i)
        if (_stricmp(s.c_str(), kFormNames[i]) == 0) { out = Form(i); return true; }
    if (_stricmp(s.c_str(), "detonatealt") == 0) { out = Form::Detonate; return true; }
    return false;
}

// THE FIXED NORMAL OF A SLAB FORM, in one place. Select() used to carry this
// switch in its slab branch and flesh.cpp had nowhere to ask; a blow that
// wants to know which way a form cuts now asks here, and the two cannot
// disagree. The numbers are the ones Select() has always used, bit for bit.
bool Lattice::SlabNormal(Form f, float out[3])
{
    static const float kR2 = 0.70710678118654752f;   // 1/sqrt(2)
    out[0] = out[1] = out[2] = 0.0f;
    switch (f) {
    case Form::SlabX: out[0] = 1.0f; return true;
    case Form::SlabY: out[1] = 1.0f; return true;
    case Form::SlabZ: out[2] = 1.0f; return true;
    // Their left-to-right against them up: the cut you see as a diagonal when you
    // are standing in front of them.
    case Form::DiagF: out[0] = kR2; out[2] = kR2; return true;
    // Their front-to-back against them up: the cut you see as a diagonal when you
    // are standing at their side.
    case Form::DiagS: out[1] = kR2; out[2] = kR2; return true;
    default: return false;
    }
}

// A PLANE WITH ITS OWN NORMAL AND A REACH.
//
// FIELD: a Gorefest greatsword blow was a slab -- 15 units either
// side of a horizontal plane through the seed, across the whole body -- and
// one such blow, seeded at their pelvis, took twelve named parts: both legs,
// both hands, and everything else the plane passed through on its way out of
// them. A sword does not cut like that. The blow has a direction and an
// extent: the plane is the blade's, and the cut goes as far in that plane as
// the swing carried, which is `reach` about `p`.
//
// With reach 0 this IS Select()'s slab -- the same signed-distance test, the
// same `bd + cell` fallback band when the plane falls between rows, the same
// nearest-the-plane sort -- so the five shipped slab forms delegate here and
// nothing of theirs moves. The one new thing on that path is the Key
// tie-break in the sort, which makes a budgeted slab deterministic instead of
// leaving the choice to std::sort.
std::vector<Key> Lattice::SelectPlane(const float p[3], const float nIn[3], float a, float reach,
                                      int maxTotal, std::uint32_t mask, std::uint32_t parts) const
{
    if (maxTotal < 1) maxTotal = 1;
    float nrm[3] = { nIn[0], nIn[1], nIn[2] };
    const float L2 = nrm[0]*nrm[0] + nrm[1]*nrm[1] + nrm[2]*nrm[2];
    if (!(L2 > 1e-8f) || !std::isfinite(L2)) {
        // No direction at all -- zero, NaN or infinite -- is a horizontal cut:
        // SlabZ, the form every blow shipped with at first. The header
        // promises exactly this, so a caller that wants "no direction, no
        // cut" tests its normal before it gets here.
        nrm[0] = 0.0f; nrm[1] = 0.0f; nrm[2] = 1.0f;
    } else if (std::fabs(L2 - 1.0f) > 1e-5f) {
        // A normal that is already unit is used AS GIVEN, so the slab forms'
        // arithmetic is Select()'s to the last bit; only a caller's raw
        // direction is normalised here.
        const float L = std::sqrt(L2);
        nrm[0] /= L; nrm[1] /= L; nrm[2] /= L;
    }
    // Remembered for SeverPlane(): WHERE the plane is, WHICH parts it was
    // scoped to, and HOW FAR it reached. Only this function ever records a
    // reach; Select()'s top and every other plane setter write 0, so a reach
    // cannot outlive the one blow that carried it.
    lastPlaneP[0] = p[0]; lastPlaneP[1] = p[1]; lastPlaneP[2] = p[2];
    lastPlaneN[0] = nrm[0]; lastPlaneN[1] = nrm[1]; lastPlaneN[2] = nrm[2];
    lastPlaneParts = parts;
    lastPlaneReach = (reach > 0.0f) ? reach : 0.0f;
    lastPlaneHalf = a;                                 // the fallback below widens it
    haveLastPlane = true;
    const float r2 = lastPlaneReach * lastPlaneReach;
    // Signed distance to the plane, and the squared distance from the impact
    // measured IN the plane -- the thing a swing's extent bounds.
    auto planeDist = [&](const Cell& C, float& lateral2) -> float {
        const float vx = C.c[0] - p[0], vy = C.c[1] - p[1], vz = C.c[2] - p[2];
        const float d = vx*nrm[0] + vy*nrm[1] + vz*nrm[2];
        lateral2 = (vx*vx + vy*vy + vz*vz) - d*d;
        return d;
    };
    // Nearest the plane first, so a budget thins the cut rather than
    // shortening it -- the reasoning Halve gives for sorting a band by height.
    std::vector<std::pair<float, Key>> hit;
    for (const auto& [k, C] : cells) {
        if (!C.Alive(mask, parts)) continue;
        float lat2; const float d = planeDist(C, lat2);
        if (!(std::fabs(d) <= a)) continue;            // the slab test, as Select() wrote it
        if (r2 > 0.0f && lat2 > r2) continue;          // beyond the reach of the swing
        hit.push_back(std::make_pair(std::fabs(d), k));
    }
    if (hit.empty()) {
        // The plane fell between cell rows: take the band nearest it, within
        // reach, rather than nothing -- a blow that silently does nothing is
        // the worst outcome available here.
        float bd = 1e30f;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts)) continue;
            float lat2; const float d = std::fabs(planeDist(C, lat2));
            if (r2 > 0.0f && lat2 > r2) continue;
            if (d < bd) bd = d;
        }
        if (bd < 1e29f) {
            const float band = bd + cell;
            lastPlaneHalf = band;
            for (const auto& [k, C] : cells) {
                if (!C.Alive(mask, parts)) continue;
                float lat2; const float d = std::fabs(planeDist(C, lat2));
                if (r2 > 0.0f && lat2 > r2) continue;
                if (d <= band) hit.push_back(std::make_pair(d, k));
            }
        }
    }
    std::sort(hit.begin(), hit.end(),
              [](const std::pair<float, Key>& x, const std::pair<float, Key>& y) {
                  if (x.first != y.first) return x.first < y.first;
                  return x.second < y.second;      // ties resolve the same way every run
              });
    std::vector<Key> out;
    for (const auto& [d, k] : hit) {
        if (int(out.size()) >= maxTotal) break;
        out.push_back(k);
    }
    return out;
}

std::vector<Key> Lattice::Select(Form f, const float p[3], float a, int count,
                                 int maxTotal, std::uint32_t mask,
                                 std::uint32_t parts) const
{
    if (maxTotal < 1) maxTotal = 1;
    haveLastPlane = false;
    lastPlaneReach = 0.0f;   // a reach belongs to ONE plane; Layer/Halve/Neck/MidHead/Crown set none

    switch (f) {
    case Form::Bite:
        return Flood(p, a, maxTotal, mask, parts);

    case Form::Everything: {
        // NEAREST FIRST, like every other form here.
        //
        // This used to be All() truncated to the budget -- and All() returns
        // cells in std::map order, which is sorted by (x, y, z). So a wound
        // that could not take the whole body took the cells with the SMALLEST
        // X: their left side, every single time, whatever it was aimed at. On
        // the shipping numbers "Unmake" reaches 168 of about 336 cells, so it
        // was reliably eating exactly one half of them and never the half you
        // were looking at.
        std::vector<std::pair<float, Key>> hit;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts)) continue;
            const float dx = C.c[0]-p[0], dy = C.c[1]-p[1], dz = C.c[2]-p[2];
            hit.push_back(std::make_pair(dx*dx + dy*dy + dz*dz, k));
        }
        std::sort(hit.begin(), hit.end(),
                  [](const std::pair<float, Key>& x, const std::pair<float, Key>& y) {
                      if (x.first != y.first) return x.first < y.first;
                      return x.second < y.second;      // ties resolve the same way every run
                  });
        std::vector<Key> out;
        for (const auto& [d, k] : hit) {
            if (int(out.size()) >= maxTotal) break;
            out.push_back(k);
        }
        return out;
    }

    case Form::Scatter: {
        // Buckshot: several separate bites, spread as far apart as the live
        // flesh allows. Each seed is the live cell FURTHEST from everything
        // already chosen, so the wounds land across the whole body instead of
        // clustering wherever the first one happened to fall.
        std::vector<Key> out;
        std::set<Key> have;
        std::vector<const Cell*> seeds;
        const int n = count > 0 ? count : 4;
        for (int i = 0; i < n && int(out.size()) < maxTotal; ++i) {
            const Cell* best = nullptr;
            // Must start below every possible score. The first seed scores by
            // NEGATIVE squared distance to the wound point, which is almost
            // always well below -1, so a -1 floor rejected every candidate and
            // the whole spell did nothing.
            float bestD = -1e30f;
            for (const auto& [k, C] : cells) {
                if (!C.Alive(mask, parts) || have.count(k)) continue;
                float d;
                if (seeds.empty()) {
                    // first seed: nearest the wound point, so a cast still
                    // starts where it was aimed
                    const float dx = C.c[0]-p[0], dy = C.c[1]-p[1], dz = C.c[2]-p[2];
                    d = -(dx*dx + dy*dy + dz*dz);
                } else {
                    d = 1e30f;
                    for (const Cell* s : seeds) {
                        const float dx = C.c[0]-s->c[0], dy = C.c[1]-s->c[1], dz = C.c[2]-s->c[2];
                        const float q = dx*dx + dy*dy + dz*dz;
                        if (q < d) d = q;
                    }
                }
                if (d > bestD) { bestD = d; best = &C; }
            }
            if (!best) break;
            seeds.push_back(best);
            const int left = maxTotal - int(out.size());
            for (const Key& k : Flood(best->c, a, left, mask, parts))
                if (have.insert(k).second) out.push_back(k);
        }
        return out;
    }

    case Form::LayerX:
    case Form::LayerY:
    case Form::LayerZ: {
        // THE ROW THE CUT WAS AIMED AT, decided by the nearest LIVE cell
        // rather than by arithmetic on the seed. The seed is a point in bind
        // space and the rows are a grid; a seed that lands in the gap between
        // two rows of flesh -- inside the pelvis, between their legs, in the
        // hollow of an armpit -- would otherwise name a row with nothing in
        // it, and the spell would be a silent no-op. Asking which living cell
        // is nearest cannot do that: whatever it names, there is flesh there.
        // NOT NAMED `near`. That is a legacy Windows macro (near/far), and
        // this file is compiled for Windows.
        const Cell* aimed = nullptr;
        float bd = 1e30f;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts)) continue;
            const float dx = C.c[0]-p[0], dy = C.c[1]-p[1], dz = C.c[2]-p[2];
            const float d = dx*dx + dy*dy + dz*dz;
            if (d < bd) { bd = d; aimed = &C; }
        }
        if (!aimed) return {};
        // WHICH AXIS THE ROW RUNS ACROSS. LayerZ is the horizontal slice this
        // was written for; LayerX and LayerY are the same construction turned
        // through ninety degrees, which is what lets a head three cells wide
        // be cut one cell thick from the front or the side.
        const int ax = (f == Form::LayerX) ? 0 : (f == Form::LayerY) ? 1 : 2;
        lastPlaneP[0] = aimed->c[0]; lastPlaneP[1] = aimed->c[1]; lastPlaneP[2] = aimed->c[2];
        lastPlaneN[0] = (ax == 0) ? 1.0f : 0.0f;
        lastPlaneN[1] = (ax == 1) ? 1.0f : 0.0f;
        lastPlaneN[2] = (ax == 2) ? 1.0f : 0.0f;
        lastPlaneParts = parts;
        lastPlaneReach = 0.0f;                 // a row goes all the way across them
        haveLastPlane = true;
        auto keyOf = [ax](const Key& k) {
            return ax == 0 ? k.x : ax == 1 ? k.y : k.z;
        };
        const std::int32_t row = keyOf(aimed->key);
        // Nearest first, so a layer with more cells in it than the budget can
        // carry loses its far edges rather than an arbitrary half. Distance is
        // measured in the plane of the row, over the two axes that are NOT the
        // row's own axis.
        std::vector<std::pair<float, Key>> hit;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts) || keyOf(k) != row) continue;
            float d2 = 0.0f;
            for (int q = 0; q < 3; ++q)
                if (q != ax) { const float dq = C.c[q] - p[q]; d2 += dq * dq; }
            hit.push_back(std::make_pair(d2, k));
        }
        std::sort(hit.begin(), hit.end(),
                  [](const std::pair<float, Key>& x, const std::pair<float, Key>& y) {
                      return x.first < y.first;
                  });
        std::vector<Key> out;
        for (const auto& [d, k] : hit) {
            if (int(out.size()) >= maxTotal) break;
            out.push_back(k);
        }
        return out;
    }

    case Form::Grind: {
        // ---- THE LOWEST ROW THEY STILL HAVE ---------------------------------
        //
        // No seed, no aim, no distance test. Halve already established that a
        // form may take its height from their own body rather than from where
        // the spell landed; this takes the bottom of them instead of their navel.
        // One application is a slice off their soles. The Grind Down spell casts
        // it again every third of a second, and because each one removes the
        // row the last one exposed, the cut walks up them -- feet, ankles,
        // calves, knees -- without anything having to track where it got to.
        // The lattice IS the progress marker.
        //
        // Rows, not distances: `k.z` is the integer lattice row, so "the
        // lowest row" is exact and one cell thick by construction, the same
        // property LayerZ exists to guarantee.
        bool any = false;
        std::int32_t zmin = 0;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts)) continue;
            if (!any || k.z < zmin) { zmin = k.z; any = true; }
        }
        if (!any) return {};
        // HOW MANY ROWS AT ONCE. `count` is the cfg row's own column and means
        // the same thing it means for scatter -- how many of this wound to do
        // -- so a grind that should bite deeper per application says so there
        // rather than needing the script's timer shortened. Rows are contiguous
        // by construction: taking zmin..zmin+count-1 cannot skip flesh.
        const std::int32_t rows = (count > 1) ? std::int32_t(count) : 1;
        const std::int32_t zmax = zmin + rows - 1;

        // Their feet are not one blob: at ankle height the row is two separate
        // islands, and taking only part of it would grind one foot and leave
        // the other. The whole row goes, every time.
        std::vector<Key> row;
        double cx = 0.0, cy = 0.0;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts) || k.z < zmin || k.z > zmax) continue;
            row.push_back(k);
            cx += double(C.c[0]); cy += double(C.c[1]);
        }
        if (row.empty()) return {};
        if (int(row.size()) <= maxTotal) return row;

        // OVER BUDGET, WHICH ON A WIDE ROW -- THEIR HIPS, THEIR SHOULDERS -- IS
        // NORMAL. Keep the middle rather than an arbitrary corner: sorting by
        // distance from the row's own centre thins the slice symmetrically,
        // the same reasoning Halve uses for sorting a band by height.
        cx /= double(row.size()); cy /= double(row.size());
        std::vector<std::pair<float, Key>> byMid;
        byMid.reserve(row.size());
        for (const Key& k : row) {
            auto it = cells.find(k);
            if (it == cells.end()) continue;
            const float dx = it->second.c[0] - float(cx);
            const float dy = it->second.c[1] - float(cy);
            byMid.push_back(std::make_pair(dx*dx + dy*dy, k));
        }
        std::sort(byMid.begin(), byMid.end(),
                  [](const std::pair<float, Key>& l, const std::pair<float, Key>& r) {
                      return l.first < r.first;
                  });
        std::vector<Key> out;
        out.reserve(std::size_t(maxTotal));
        for (std::size_t i = 0; i < byMid.size() && int(out.size()) < maxTotal; ++i)
            out.push_back(byMid[i].second);
        return out;
    }

    case Form::Halve: {
        // ---- NAVEL HEIGHT, OUT OF THEIR ANATOMY -----------------------------
        //
        // The middle of the belly. Taken from the cells the lattice already
        // knows are abdomen rather than from a bone name, because a bone name
        // is a thing a body replacer can rename and the part mapping is
        // already keyed on the bracket tag that cannot move.
        double sz = 0.0; int na = 0;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts)) continue;
            if (PartOfBone(C.bone) != Part::Abdomen) continue;
            sz += double(C.c[2]); ++na;
        }
        float zc = 0.0f;
        if (na > 0) {
            zc = float(sz / double(na));
        } else {
            // They have no abdomen left to ask. Halve whatever IS left, through
            // its middle, rather than refusing: the spell was cast.
            float lo = 1e30f, hi = -1e30f;
            for (const auto& [k, C] : cells) {
                if (!C.Alive(mask, parts)) continue;
                if (C.c[2] < lo) lo = C.c[2];
                if (C.c[2] > hi) hi = C.c[2];
            }
            if (lo > hi) return {};
            zc = 0.5f * (lo + hi);
        }
        lastPlaneP[0] = p[0]; lastPlaneP[1] = p[1]; lastPlaneP[2] = zc;
        lastPlaneN[0] = 0.0f; lastPlaneN[1] = 0.0f; lastPlaneN[2] = 1.0f;
        lastPlaneParts = parts;
        lastPlaneReach = 0.0f;                 // a bisection is the whole body
        haveLastPlane = true;
        // ---- THE BAND, SORTED BY HEIGHT AND NOT BY AIM --------------------
        //
        // This is the difference between a cut and a bite. Every other form
        // sorts by distance from where the spell landed, so a budget that
        // cannot take everything keeps the near side -- which for a bisection
        // would keep half the cut and leave them in one piece. Sorting by
        // VERTICAL distance from the plane means a short budget thins the
        // band and still goes all the way through.
        std::vector<std::pair<float, Key>> hit;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask, parts)) continue;
            const float dz = C.c[2] - zc;
            const float ad = dz < 0.0f ? -dz : dz;
            if (ad <= a) hit.push_back(std::make_pair(ad, k));
        }
        if (hit.empty()) {
            // The band fell between two rows of flesh. Take the nearest row
            // entire rather than nothing: a spell that silently does nothing
            // is the worst outcome available here.
            const Cell* aimed = nullptr; float bd = 1e30f;
            for (const auto& [k, C] : cells) {
                if (!C.Alive(mask, parts)) continue;
                const float dz = C.c[2] - zc, ad = dz < 0.0f ? -dz : dz;
                if (ad < bd) { bd = ad; aimed = &C; }
            }
            if (!aimed) return {};
            const std::int32_t row = aimed->key.z;
            for (const auto& [k, C] : cells)
                if (C.Alive(mask, parts) && k.z == row)
                    hit.push_back(std::make_pair(0.0f, k));
        }
        std::sort(hit.begin(), hit.end(),
                  [](const std::pair<float, Key>& x, const std::pair<float, Key>& y) {
                      return x.first < y.first;
                  });
        std::vector<Key> out;
        for (const auto& [d, k] : hit) {
            if (int(out.size()) >= maxTotal) break;
            out.push_back(k);
        }
        return out;
    }

    case Form::Detonate: {
        // EVERY SEAM, BOTH SIDES. See the enum for what a seam is and why
        // both sides go. Neighbours() is the exact adjacency Sections()
        // walks, so what this removes is what would otherwise
        // carry the flood fill from one part into the next.
        std::vector<Key> out;
        std::set<Key> seen;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask)) continue;
            if (C.part == static_cast<std::uint8_t>(Part::Unknown)) continue;
            bool seam = false;
            for (const Key& n : Neighbours(k)) {
                auto it = cells.find(n);
                if (it == cells.end()) continue;
                const Cell& N = it->second;
                if (!N.Alive(mask)) continue;
                if (N.part == static_cast<std::uint8_t>(Part::Unknown)) continue;
                if (N.part != C.part) { seam = true; break; }
            }
            if (seam && seen.insert(k).second) out.push_back(k);
        }
        // AND THE HEAD, IN HALF: BisectSkull's own cut -- one row through the
        // centre of their live head cells, head cells only -- so the head that
        // the neck seam just freed leaves as two pieces. Whatever head is in
        // the lattice: a test head or their own.
        float hc[3];
        const std::uint32_t headOnly = 1u << static_cast<unsigned>(Part::Head);
        if (PartAnchor(headOnly, Anchor::Centre, mask, hc)) {
            const int room = int(cells.size()) + 1;
            std::vector<Key> half = Select(Form::LayerX, hc, a, count, room, mask, headOnly);
            for (const Key& k : half)
                if (seen.insert(k).second) out.push_back(k);
        }
        // AND THE TORSO, DOWN THE MIDDLE. Design note: Detonate effects
        // also bisect the torso vertically, separating left from
        // right. The head's own cut, taken through the centre of their chest
        // and abdomen and those two parts only: LayerX is the plane of
        // constant x, and x is their left-right axis (Anchor::Left is hi[0]),
        // so the trunk the seams just freed leaves as a left and a right --
        // and, since the chest/abdomen seam is already in `out`, as four.
        // Anchored on both parts together so the one column chosen is the
        // same column through both; anchored on each alone, a target bent at
        // the waist could get two different columns and a step in the cut.
        const std::uint32_t trunkOnly = (1u << static_cast<unsigned>(Part::Chest))
                                      | (1u << static_cast<unsigned>(Part::Abdomen));
        float tc[3];
        if (PartAnchor(trunkOnly, Anchor::Centre, mask, tc)) {
            const int room = int(cells.size()) + 1;
            std::vector<Key> half = Select(Form::LayerX, tc, a, count, room, mask, trunkOnly);
            for (const Key& k : half)
                if (seen.insert(k).second) out.push_back(k);
        }
        haveLastPlane = false;
        lastPlaneReach = 0.0f;
        return out;
    }

    case Form::Neck: {
        // The join, out of their own anatomy: the lowest live cell that belongs
        // to their HEAD. Asked of the cached part rather than of a bone name,
        // for the same reason Halve asks the lattice about their abdomen -- a
        // body replacer can rename a bone and cannot move the part mapping.
        //
        // THEIR OWN ANATOMY MEANS THEIR OWN FLESH. This loop said "their
        // HEAD" and tested only Part::Head, which a HAT also is: head-boned
        // wardrobe carries Part::Head exactly as their skull does. FIELD:
        // one target took five Decapitates and survived all
        // five, their head never separating -- "129 Head cell(s) ... but only 66
        // of them are THEIRS", the other 63 being a hat that arrives as a head
        // piece of its own. (That tally counts only their SKIN, and it counts
        // cells born with a layer-0 shape; `mine` is skin OR fill, so 66 is a
        // FLOOR on what is theirs, not the same measurement.
        // Note too that with
        // FA on, their own eyes, brows and mouth are layer-0 wardrobe and sit in
        // the other 63 alongside the hat -- the unhatted target in the same log
        // shows a dozen such cells.) The lowest Head cell was the hat's hem, so
        // the join was found below their neck and the band cut their chest, where
        // there is nothing to take off. Every target without a hat severed on
        // the first cast.
        //
        // So the join is the lowest cell of their own FLESH -- `mine`, which a
        // layer-0 non-skin shape never sets.
        //
        // AND THERE IS NO FALLBACK TO THE UNFILTERED SCAN.
        // A fallback for a head that is ALL wardrobe would
        // re-arm the very bug on their SECOND cast: once the head has
        // come off, the rebuilt lattice has no `mine` Head cell left, but their
        // hood is still there and is still Part::Head -- the reader keeps it on
        // purpose ("they are theirs to wear, not loose flesh"). The fallback
        // would then find the hood's hem and cut their chest again, and the log
        // line would say it cut at their own flesh.
        // Nor can the case it was for arise. What guarantees a `mine` Head cell is
        // not their head fill, which they may not be wearing yet -- the log
        // has "the skull count is 0" on a target who severed correctly anyway --
        // nor their face, which HF 3 force-skins but the frame decision can
        // still withdraw: it is THEIR BODY'S OWN NECK SKIN -- real skin, so `mine`
        // by lattice.cpp's `S.skin || S.layer > 0`, and Part::Head by the Neck
        // and Neck1 tags. They have that whatever they are wearing and whatever HF
        // is set to. The only target with no `mine` Head cell is one whose head
        // has already come off, and for them the right answer is the one below.
        float zc = 1e30f; bool any = false;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask)) continue;          // NOT filtered: see below
            if (C.part != static_cast<std::uint8_t>(Part::Head)) continue;
            if (!C.mine) continue;                 // a hat is not their neck
            if (C.c[2] < zc) { zc = C.c[2]; any = true; }
        }
        if (!any) return {};                       // no head of theirs left to take off
        lastJoinZ = zc;                            // read back for the log
        lastPlaneP[0] = p[0]; lastPlaneP[1] = p[1]; lastPlaneP[2] = zc;
        lastPlaneN[0] = 0.0f; lastPlaneN[1] = 0.0f; lastPlaneN[2] = 1.0f;
        lastPlaneParts = 0;
        lastPlaneReach = 0.0f;                 // the collar goes all the way round
        haveLastPlane = true;

        // THE BAND IS NOT PART-FILTERED. The height comes from their head; the
        // cut goes through whatever is at that height, which is the point.
        std::vector<std::pair<float, Key>> hit;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask)) continue;
            const float dz = C.c[2] - zc;
            const float ad = dz < 0.0f ? -dz : dz;
            if (ad <= a) hit.push_back(std::make_pair(ad, k));
        }
        if (hit.empty()) {
            // The band fell between two rows. Take the row nearest the join
            // entire, exactly as Halve does, rather than doing nothing.
            const Cell* aimed = nullptr; float bd = 1e30f;
            for (const auto& [k, C] : cells) {
                if (!C.Alive(mask)) continue;
                const float dz = C.c[2] - zc, ad = dz < 0.0f ? -dz : dz;
                if (ad < bd) { bd = ad; aimed = &C; }
            }
            if (!aimed) return {};
            const std::int32_t row = aimed->key.z;
            for (const auto& [k, C] : cells)
                if (C.Alive(mask) && k.z == row)
                    hit.push_back(std::make_pair(0.0f, k));
        }
        // Sorted by distance from the JOIN, not from the aim, so a short
        // budget thins the collar and still goes all the way round.
        std::sort(hit.begin(), hit.end(),
                  [](const std::pair<float, Key>& x, const std::pair<float, Key>& y) {
                      return x.first < y.first;
                  });
        std::vector<Key> out;
        for (const auto& [d, k] : hit) {
            if (int(out.size()) >= maxTotal) break;
            out.push_back(k);
        }
        return out;
    }

    case Form::MidHead:
    case Form::Crown: {
        // The height, out of their head and nothing else.
        //
        // KNOWN HOLE, DELIBERATELY NOT PLUGGED. This scan has the
        // same fault Form::Neck had above: a head-boned hat is Part::Head, so
        // it is measured as part of their head -- it raises `ztop`, which pushes
        // Crown's "halfway to the top of their head" above their skull, and drags
        // MidHead's mean up with it. Measured in a test on a
        // hatted fixture: MidHead cut 3 units low, CROWN 6 units high -- a
        // whole cell, above their skull entirely.
        //
        // Neck's fix does not transfer.
        // Neck can demand `mine` because
        // their body's own neck skin is always there to answer. These two cannot:
        // when their face is not in the lattice at all -- HF 0, or a frame
        // decision that withdrew it -- and they are not yet wearing the head
        // fill, the only `mine` Head cells left ARE that neck skin, so the
        // height collapses onto their throat. Crown carries no `nosever`, so
        // that would be a full-depth severing ring through their neck on a spell
        // whose whole job is to take the cap off their skull. Cutting their hat is
        // wrong; cutting their throat is worse.
        //
        // Wanted: a height measured over the cells ABOVE the join
        // Form::Neck already computes, refusing when there are
        // none.
        // Form::Halve (Part::Abdomen, a belt or a sash)
        // and Detonate's head bisect through PartAnchor share the same shape.
        double sz = 0.0; int nh = 0; float ztop = -1e30f;
        const std::uint8_t HEAD = static_cast<std::uint8_t>(Part::Head);
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask) || C.part != HEAD) continue;
            sz += double(C.c[2]); ++nh;
            if (C.c[2] > ztop) ztop = C.c[2];
        }
        if (!nh) return {};                     // no head left to measure
        float zc = float(sz / double(nh));
        // Crown: halfway from the middle of their head to the top of it.
        if (f == Form::Crown) zc = zc + 0.5f * (ztop - zc);
        lastPlaneP[0] = p[0]; lastPlaneP[1] = p[1]; lastPlaneP[2] = zc;
        lastPlaneN[0] = 0.0f; lastPlaneN[1] = 0.0f; lastPlaneN[2] = 1.0f;
        lastPlaneParts = 1u << static_cast<unsigned>(Part::Head);
        lastPlaneReach = 0.0f;                 // the whole head, not a swing's worth of it
        haveLastPlane = true;

        // HEAD-ONLY, unlike Neck. A band at eye height that was not filtered
        // would take both shoulders with it on a target who is bent forward.
        std::vector<std::pair<float, Key>> hit;
        for (const auto& [k, C] : cells) {
            if (!C.Alive(mask) || C.part != HEAD) continue;
            const float dz = C.c[2] - zc;
            const float ad = dz < 0.0f ? -dz : dz;
            if (ad <= a) hit.push_back(std::make_pair(ad, k));
        }
        if (hit.empty()) {
            // Between two rows: take the head row nearest the height whole,
            // as Halve and Neck both do, rather than doing nothing.
            const Cell* aimed = nullptr; float bd = 1e30f;
            for (const auto& [k, C] : cells) {
                if (!C.Alive(mask) || C.part != HEAD) continue;
                const float dz = C.c[2] - zc, ad = dz < 0.0f ? -dz : dz;
                if (ad < bd) { bd = ad; aimed = &C; }
            }
            if (!aimed) return {};
            const std::int32_t row = aimed->key.z;
            for (const auto& [k, C] : cells)
                if (C.Alive(mask) && C.part == HEAD && k.z == row)
                    hit.push_back(std::make_pair(0.0f, k));
        }
        std::sort(hit.begin(), hit.end(),
                  [](const std::pair<float, Key>& x, const std::pair<float, Key>& y) {
                      return x.first < y.first;
                  });
        std::vector<Key> out;
        for (const auto& [d, k] : hit) {
            if (int(out.size()) >= maxTotal) break;
            out.push_back(k);
        }
        return out;
    }

    // Dispatched long before this in flesh.cpp; here so the switch is total.
    case Form::Restore: return {};

    default: break;
    }

    // Slab and bore: a purely geometric volume, taken whole.
    //
    // ONE PLANE TEST FOR ALL FIVE SLABS, and it lives in SelectPlane.
    // The three axis-aligned slabs used to compare a single coordinate; the
    // two diagonals cannot, so all five go through the same signed distance
    // to a unit normal. SlabX with normal (1,0,0) is exactly the old
    // `fabs(C.c[0] - p[0]) <= a` -- the same arithmetic, not an equivalent
    // one -- so nothing that worked before can move. A slab form is
    // SelectPlane with the form's fixed normal and NO reach: across the whole body, as every slab was before blows had a reach; a blow that knows how far it
    // swung calls SelectPlane itself. The bores keep their own axis, because
    // a bore is a line and a line is not a plane.
    {
        float nrm[3];
        if (SlabNormal(f, nrm))
            return SelectPlane(p, nrm, a, 0.0f, maxTotal, mask, parts);
    }
    const int axis = (f == Form::BoreX) ? 0 : (f == Form::BoreY) ? 1 : 2;
    const float a2 = a * a;

    // Nearest first, so that when the volume holds more cells than the budget
    // allows, what survives is the part of the cut closest to where it was
    // aimed rather than whichever cells the map happened to store first.
    std::vector<std::pair<float, Key>> hit;
    for (const auto& [k, C] : cells) {
        if (!C.Alive(mask, parts)) continue;
        float d2 = 0;
        for (int q = 0; q < 3; ++q)
            if (q != axis) { const float d = C.c[q] - p[q]; d2 += d * d; }
        if (!(d2 <= a2)) continue;
        hit.push_back(std::make_pair(d2, k));
    }
    std::sort(hit.begin(), hit.end(),
              [](const std::pair<float, Key>& x, const std::pair<float, Key>& y) {
                  return x.first < y.first;
              });
    std::vector<Key> out;
    for (const auto& [d, k] : hit) {
        if (int(out.size()) >= maxTotal) break;
        out.push_back(k);
    }
    return out;
}

void Lattice::MarkGone(const std::vector<Key>& sel, std::uint32_t mask)
{
    for (const Key& k : sel) {
        auto it = cells.find(k);
        if (it != cells.end()) it->second.gone |= (mask & it->second.layers);
    }
}

std::size_t Lattice::SeverPlane()
{
    if (!haveLastPlane) return 0;
    haveLastPlane = false;
    const float px = lastPlaneP[0], py = lastPlaneP[1], pz = lastPlaneP[2];
    const float nx = lastPlaneN[0], ny = lastPlaneN[1], nz = lastPlaneN[2];
    const std::uint32_t parts = lastPlaneParts;
    // HOW FAR THE CUT WENT, IN THE PLANE. 0 is a spell's
    // slab: the whole body, as ever. Otherwise only the cells within the
    // reach -- plus one cell of slack, so the rim of the selection still parts
    // from the row just beyond it -- take part in the stripping below, and a
    // link that crosses the plane out past the swing is left standing.
    //
    // FIELD: "cut plane severed 389 cross-plane link(s)" on a
    // pelvis-height greatsword slab detached both legs from a disc of pelvis
    // the blade had reached and the rest of them it had not. The reach is read
    // once and cleared with the flag, so it cannot outlive this one cut.
    const float reach = lastPlaneReach;
    lastPlaneReach = 0.0f;
    const float rr = (reach > 0.0f) ? reach + cell : 0.0f;
    const float r2 = rr * rr;

    auto packKey = [](const Key& k) -> std::uint64_t {
        return (std::uint64_t(std::uint32_t(k.x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(k.y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(k.z) & 0x1FFFFFu) << 42);
    };
    auto sideOf = [&](const Cell& C) -> float {
        return (C.c[0] - px) * nx + (C.c[1] - py) * ny + (C.c[2] - pz) * nz;
    };
    auto inScope = [&](const Cell& C) -> bool {
        if (parts == 0) return true;
        return C.part != 0 && ((parts & (1u << C.part)) != 0);
    };
    auto inReach = [&](const Cell& C) -> bool {
        if (r2 <= 0.0f) return true;                     // a spell's slab: the whole body, as ever
        const float vx = C.c[0] - px, vy = C.c[1] - py, vz = C.c[2] - pz;
        const float d = vx*nx + vy*ny + vz*nz;
        return (vx*vx + vy*vy + vz*vz) - d*d <= r2;      // squared distance IN the plane
    };

    // A link is cut only when BOTH its ends are in sideMap and on opposite
    // sides, so limiting the map to the reach limits the cut.
    std::unordered_map<std::uint64_t, float> sideMap;
    sideMap.reserve(cells.size() * 2 + 16);
    for (const auto& [k, C] : cells) {
        if (inScope(C) && inReach(C)) sideMap.emplace(packKey(k), sideOf(C));
    }

    std::size_t cut = 0;
    auto stripMap = [&](std::map<Key, std::set<Key>>& m, bool isBridge) {
        for (auto& [u, nbrs] : m) {
            auto cu = sideMap.find(packKey(u));
            if (cu == sideMap.end()) continue;
            const float du = cu->second;
            for (auto it = nbrs.begin(); it != nbrs.end(); ) {
                auto cv = sideMap.find(packKey(*it));
                if (cv != sideMap.end()) {
                    const float dv = cv->second;
                    if ((du < 0.0f && dv > 0.0f) || (du > 0.0f && dv < 0.0f) ||
                        (du == 0.0f && dv != 0.0f) || (du != 0.0f && dv == 0.0f)) {
                        severed.push_back(SeveredLink{ u, *it, isBridge });
                        it = nbrs.erase(it);
                        ++cut;
                        continue;
                    }
                }
                ++it;
            }
        }
    };
    stripMap(adj, false);
    stripMap(bridge, true);
    return cut / 2;
}

void Lattice::Rejoin()
{
    for (const SeveredLink& s : severed) (s.isBridge ? bridge : adj)[s.a].insert(s.b);
    severed.clear();
}

std::uint32_t Lattice::PeelStageMask(const std::vector<Key>& sel, std::uint32_t mask, int maxStages) const
{
    if (maxStages <= 0 || maxStages >= 4) return mask;
    static const std::uint32_t kStageBits[4] = { kArmourBit, 0x03u, 0x04u, 0x08u };
    int intact[4] = { 0, 0, 0, 0 };
    int peeled[4] = { 0, 0, 0, 0 };
    for (const Key& k : sel) {
        auto it = cells.find(k);
        if (it == cells.end()) continue;
        const Cell& C = it->second;
        const std::uint32_t rem = (C.layers & ~C.gone) & mask;
        for (int s = 0; s < 4; ++s) {
            if (rem & kStageBits[s]) ++intact[s];
            if (C.gone & kStageBits[s]) ++peeled[s];
        }
    }
    int s0 = -1;
    for (int s = 0; s < 4; ++s) {
        if (!intact[s]) continue;
        bool nextWaiting = false;
        for (int d = s + 1; d < 4; ++d) if (intact[d] > 0) { nextWaiting = true; break; }
        if (nextWaiting && peeled[s] > 0 && (peeled[s] >= 2 || peeled[s] * 4 >= intact[s])) {
            continue;
        }
        s0 = s;
        break;
    }
    if (s0 < 0) {
        for (int s = 0; s < 4; ++s) if (intact[s] > 0) { s0 = s; break; }
    }
    if (s0 < 0) return 0u;
    std::uint32_t outMask = 0u;
    for (int s = 0; s < s0; ++s) outMask |= (kStageBits[s] & mask);
    int left = maxStages;
    for (int s = s0; s < 4 && left > 0; ++s) {
        if (intact[s] > 0) {
            outMask |= (kStageBits[s] & mask);
            --left;
        }
    }
    return outMask;
}

void Lattice::PeelGone(const std::vector<Key>& sel, std::uint32_t mask, int maxStages, PeelReport* rep)
{
    if (rep) *rep = PeelReport{};
    if (sel.empty() || !mask) return;
    if (maxStages < 1) maxStages = 1;
    const std::uint32_t stageMask = PeelStageMask(sel, mask, maxStages);
    if (!stageMask) return;

    std::vector<std::pair<Key, std::uint32_t>> crumbs;
    crumbs.reserve(sel.size());
    for (const Key& k : sel) {
        auto it = cells.find(k);
        if (it == cells.end()) continue;
        Cell& C = it->second;
        const std::uint32_t rem = (C.layers & ~C.gone) & stageMask;
        if (rep && rem) {
            if (rem & kArmourBit) ++rep->armourPeeled;
            if (rem & 0x03u)      ++rep->skinPeeled;
            if (rem & 0x04u)      ++rep->fleshPeeled;
            if (rem & 0x08u)      ++rep->bonePeeled;
        }
        const std::uint32_t carried = (C.gone & (kArmourBit | 0x03u | 0x04u)) | stageMask;
        C.gone |= stageMask;
        if (rem) crumbs.push_back(std::make_pair(k, carried));
    }
    for (const auto& [k, crumb] : crumbs) {
        for (int dx = -1; dx <= 1; ++dx)
            for (int dy = -1; dy <= 1; ++dy)
                for (int dz = -1; dz <= 1; ++dz) {
                    if (!dx && !dy && !dz) continue;
                    auto nit = cells.find(Key{ k.x + dx, k.y + dy, k.z + dz });
                    if (nit == cells.end()) continue;
                    Cell& N = nit->second;
                    const std::uint32_t safeCrumb = crumb & ~N.layers;
                    if (safeCrumb) N.gone |= safeCrumb;
                }
    }
    if (rep) {
        for (const Key& k : sel) {
            auto it = cells.find(k);
            if (it == cells.end()) continue;
            const std::uint32_t after = it->second.layers & ~it->second.gone;
            if (after & 0x01u)      ++rep->skinExposed;
            else if (after & 0x04u) ++rep->fleshExposed;
            else if (after & 0x08u) ++rep->boneExposed;
        }
    }
}

bool Lattice::Seed(const std::string& bone, float out[3]) const
{
    auto it = boneSeed.find(bone);
    if (it == boneSeed.end() || it->second.size() != 3) return false;
    out[0] = it->second[0]; out[1] = it->second[1]; out[2] = it->second[2];
    return true;
}


// THE CUT VOLUME'S OWN FACE BUILDER IS GONE.
//
// ExposedFaces() lived here and had no callers. It was written for a HOLLOW
// body, to build a wall out of the lattice wherever a wound opened onto
// nothing; a solid body has meat behind every face already, and nothing has
// called it in a long time.
// CutQuad itself stays -- the (dormant) blood canvas still names it.

// ======================================================== TRUE DISMEMBERMENT

const char* PartName(Part p)
{
    switch (p) {
        case Part::Head:      return "head";
        case Part::Chest:     return "upper torso";
        case Part::Abdomen:   return "abdomen";
        case Part::LUpperArm: return "left upper arm";
        case Part::LForearm:  return "left forearm";
        case Part::LHand:     return "left hand";
        case Part::RUpperArm: return "right upper arm";
        case Part::RForearm:  return "right forearm";
        case Part::RHand:     return "right hand";
        case Part::LThigh:    return "left thigh";
        case Part::LCalf:     return "left lower leg";
        case Part::LFoot:     return "left foot";
        case Part::RThigh:    return "right thigh";
        case Part::RCalf:     return "right lower leg";
        case Part::RFoot:     return "right foot";
        default:              return "unnamed";
    }
}

const char* PartKey(Part p)
{
    switch (p) {
        case Part::Head:      return "head";
        case Part::Chest:     return "chest";
        case Part::Abdomen:   return "abdomen";
        case Part::LUpperArm: return "lupperarm";
        case Part::LForearm:  return "lforearm";
        case Part::LHand:     return "lhand";
        case Part::RUpperArm: return "rupperarm";
        case Part::RForearm:  return "rforearm";
        case Part::RHand:     return "rhand";
        case Part::LThigh:    return "lthigh";
        case Part::LCalf:     return "lcalf";
        case Part::LFoot:     return "lfoot";
        case Part::RThigh:    return "rthigh";
        case Part::RCalf:     return "rcalf";
        case Part::RFoot:     return "rfoot";
        default:              return "unnamed";
    }
}

// THE TAG INSIDE THE BRACKETS, and the LAST pair of brackets at that: an
// armour bone can arrive as `CollarBone (formid)[1]/CollarBone`,
// and taking the first bracket would read `1` as a bone tag.
static bool TagOf(const char* n, char out[8])
{
    if (!n) return false;
    const char* a = nullptr;
    for (const char* p = n; *p; ++p) if (*p == '[') a = p;
    if (!a) return false;
    ++a;
    int i = 0;
    while (a[i] && a[i] != ']' && i < 7) { out[i] = a[i]; ++i; }
    if (a[i] != ']') return false;
    out[i] = 0;
    // `NPC L Foot [Lft ]` really is spelled with a trailing space inside the
    // brackets. Every other tag is not, so the space is trimmed rather than
    // carried into the comparison.
    while (i > 0 && out[i - 1] == ' ') out[--i] = 0;
    return i > 0;
}

static bool EqI(const char* a, const char* b)
{
    for (;; ++a, ++b) {
        const char ca = (*a >= 'A' && *a <= 'Z') ? char(*a + 32) : *a;
        const char cb = (*b >= 'A' && *b <= 'Z') ? char(*b + 32) : *b;
        if (ca != cb) return false;
        if (!ca) return true;
    }
}

static bool Has(const char* hay, const char* needle)
{
    if (!hay || !needle) return false;
    for (const char* h = hay; *h; ++h) {
        const char* a = h; const char* b = needle;
        for (;; ++a, ++b) {
            if (!*b) return true;
            const char ca = (*a >= 'A' && *a <= 'Z') ? char(*a + 32) : *a;
            const char cb = (*b >= 'A' && *b <= 'Z') ? char(*b + 32) : *b;
            if (ca != cb) break;
        }
    }
    return false;
}

struct TagPart { const char* tag; Part p; };
// Every tag the rig actually produces, read off the shipping body: the 62
// bones it carries, plus the head and neck the head mesh brings and the
// twist bones XPMSSE adds. A tag not in here falls through to the readable
// name, and a name that resolves to nothing is Unknown -- which holds nothing
// on to anything.
static const TagPart kTags[] = {
    { "Head", Part::Head },  { "Neck",  Part::Head },  { "Neck1", Part::Head },
    { "Spn2", Part::Chest }, { "Spn1",  Part::Chest },
    { "LClv", Part::Chest }, { "RClv",  Part::Chest },
    { "Spn0", Part::Abdomen }, { "Pelv", Part::Abdomen },

    { "LUar", Part::LUpperArm }, { "LUt1", Part::LUpperArm }, { "LUt2", Part::LUpperArm },
    { "RUar", Part::RUpperArm }, { "RUt1", Part::RUpperArm }, { "RUt2", Part::RUpperArm },
    { "LLar", Part::LForearm },  { "LLt1", Part::LForearm },  { "LLt2", Part::LForearm },
    { "RLar", Part::RForearm },  { "RLt1", Part::RForearm },  { "RLt2", Part::RForearm },
    { "LHnd", Part::LHand },     { "RHnd", Part::RHand },

    { "LThg", Part::LThigh },    { "RThg", Part::RThigh },
    { "LClf", Part::LCalf },     { "RClf", Part::RCalf },
    { "Lft",  Part::LFoot },     { "Rft",  Part::RFoot },
    { "LToe", Part::LFoot },     { "RToe", Part::RFoot },
};

// The readable name, for the bones that carry no tag at all -- the 3BA breast
// and belly rig, the BBP thigh bones, and whatever a body replacer invents.
// Ordered so the longer word is tested before the word inside it: `Forearm`
// before `arm`, `Spine1` before `Spine`.
static Part BySubstring(const char* n)
{
    int side = 0;                                   // -1 left, +1 right
    if (Has(n, "left") || Has(n, " l ") || (n[0] == 'L' && n[1] == ' ')) side = -1;
    if (Has(n, "right") || Has(n, " r ") || (n[0] == 'R' && n[1] == ' ')) side = +1;
    auto L = [&](Part l, Part r) { return side < 0 ? l : (side > 0 ? r : Part::Unknown); };

    if (Has(n, "forearm") || Has(n, "lowerarm")) return L(Part::LForearm, Part::RForearm);
    if (Has(n, "upperarm") || Has(n, "upper arm")) return L(Part::LUpperArm, Part::RUpperArm);
    if (Has(n, "finger") || Has(n, "thumb") || Has(n, "hand"))
        return L(Part::LHand, Part::RHand);
    if (Has(n, "clavicle") || Has(n, "shoulder") || Has(n, "scapula")) return Part::Chest;
    if (Has(n, "breast") || Has(n, "bust") || Has(n, "nipple") || Has(n, "pectoral"))
        return Part::Chest;
    if (Has(n, "spine2") || Has(n, "spine1") || Has(n, "chest") || Has(n, "ribcage"))
        return Part::Chest;
    if (Has(n, "thigh")) return L(Part::LThigh, Part::RThigh);
    if (Has(n, "calf") || Has(n, "shin") || Has(n, "knee"))
        return L(Part::LCalf, Part::RCalf);
    if (Has(n, "toe") || Has(n, "foot") || Has(n, "ankle") || Has(n, "heel"))
        return L(Part::LFoot, Part::RFoot);
    if (Has(n, "pelvis") || Has(n, "belly") || Has(n, "butt") || Has(n, "genital") ||
        Has(n, "vagina") || Has(n, "anus") || Has(n, "labia") || Has(n, "clit") ||
        Has(n, "penis") || Has(n, "scrotum") || Has(n, "groin") || Has(n, "spine") ||
        Has(n, "skirt") || Has(n, "tasset") || Has(n, "loin") || Has(n, "pelv") ||
        Has(n, "hip") || Has(n, "belt") || Has(n, "sash"))
        return Part::Abdomen;
    if (Has(n, "neck") || Has(n, "head") || Has(n, "jaw") || Has(n, "tongue") ||
        Has(n, "teeth") || Has(n, "skull") || Has(n, "face") || Has(n, "eye"))
        return Part::Head;
    return Part::Unknown;
}

Part PartOfBone(const char* boneName)
{
    if (!boneName || !*boneName) return Part::Unknown;
    char tag[8];
    if (TagOf(boneName, tag)) {
        for (const TagPart& t : kTags) if (EqI(t.tag, tag)) return t.p;
        // Fingers are LF00..LF42 and there are thirty of them; a prefix rule
        // is the simpler way to say that than thirty table rows. The
        // foot's `Lft` cannot reach here -- it matched the table above -- and
        // its lowercase f would not match this anyway.
        if ((tag[0] == 'L' || tag[0] == 'R') && tag[1] == 'F' &&
            tag[2] >= '0' && tag[2] <= '9')
            return tag[0] == 'L' ? Part::LHand : Part::RHand;
    }
    return BySubstring(boneName);
}

// THE ANATOMY. Fourteen joints over fifteen named parts, which is a tree: cut
// any one of them and the body falls into exactly two pieces. That is the
// whole claim this feature rests on.
static const Part kJoints[][2] = {
    { Part::Head,      Part::Chest },
    { Part::Chest,     Part::Abdomen },
    { Part::Chest,     Part::LUpperArm }, { Part::LUpperArm, Part::LForearm },
    { Part::LForearm,  Part::LHand },
    { Part::Chest,     Part::RUpperArm }, { Part::RUpperArm, Part::RForearm },
    { Part::RForearm,  Part::RHand },
    { Part::Abdomen,   Part::LThigh },    { Part::LThigh,    Part::LCalf },
    { Part::LCalf,     Part::LFoot },
    { Part::Abdomen,   Part::RThigh },    { Part::RThigh,    Part::RCalf },
    { Part::RCalf,     Part::RFoot },
};

bool PartsTouch(Part a, Part b)
{
    if (a == Part::Unknown || b == Part::Unknown) return false;
    if (a == b) return true;
    for (const auto& j : kJoints)
        if ((j[0] == a && j[1] == b) || (j[0] == b && j[1] == a)) return true;
    return false;
}

// The joint table is a tree with the torso at its root, written parent
// first: the part a limb part hangs from is the left column of the row that
// names it on the right. The head hangs from the chest too, but the neck has
// its own form and the tear rule leaves it alone, so it answers Unknown here.
Part PartParent(Part p)
{
    if (!PartIsLimb(p)) return Part::Unknown;
    for (const auto& j : kJoints)
        if (j[1] == p) return j[0];
    return Part::Unknown;
}

bool PartIsLimb(Part p)
{
    switch (p) {
        case Part::LUpperArm: case Part::LForearm: case Part::LHand:
        case Part::RUpperArm: case Part::RForearm: case Part::RHand:
        case Part::LThigh:    case Part::LCalf:    case Part::LFoot:
        case Part::RThigh:    case Part::RCalf:    case Part::RFoot:
            return true;
        default:
            return false;
    }
}

// ---- JOINT DISTANCE, BREADTH-FIRST OVER THE SAME TABLE --------------------
//
// Fifteen parts and fourteen joints: the graph is a tree, the walk is a dozen
// steps, and there is nothing here worth caching.
int PartDistance(Part a, Part b)
{
    if (a == Part::Unknown || b == Part::Unknown) return -1;
    if (a == b) return 0;
    int dist[std::size_t(Part::Count)];
    for (std::size_t i = 0; i < std::size_t(Part::Count); ++i) dist[i] = -1;
    dist[std::size_t(a)] = 0;
    std::deque<Part> q; q.push_back(a);
    while (!q.empty()) {
        const Part u = q.front(); q.pop_front();
        if (u == b) return dist[std::size_t(u)];
        for (const auto& j : kJoints) {
            Part v = Part::Unknown;
            if (j[0] == u) v = j[1];
            else if (j[1] == u) v = j[0];
            else continue;
            if (dist[std::size_t(v)] >= 0) continue;
            dist[std::size_t(v)] = dist[std::size_t(u)] + 1;
            q.push_back(v);
        }
    }
    return -1;                     // disconnected: cannot happen on this table
}

int PartSpan(std::uint32_t parts)
{
    std::vector<Part> ps;
    for (int i = 1; i < int(Part::Count); ++i)
        if (parts & (1u << i)) ps.push_back(Part(i));
    int worst = 0;
    for (std::size_t i = 0; i < ps.size(); ++i)
        for (std::size_t j = i + 1; j < ps.size(); ++j) {
            const int d = PartDistance(ps[i], ps[j]);
            if (d > worst) worst = d;
        }
    return worst;
}

// ---- GROUPING PARTS SO NO GROUP IS WIDER THAN maxSpan ---------------------
//
// Seeded from the EXTREMITY -- the part whose distances to the rest sum to the
// most -- because growing inward from a hand collects the arm, while growing
// outward from the middle collects half of everything and stops. Ties go to
// the lower enum value so the same body always comes apart the same way.
//
// Then the nearest part that keeps the whole group within maxSpan is added,
// repeatedly, until nothing else fits. That is a clique-growing rule and not a
// chain-growing one: every pair in the group is checked, so a group can never
// end up two joints wide at one end and four at the other.
static std::vector<std::vector<Part>> GroupPartsBySpan(std::uint32_t parts, int maxSpan)
{
    std::vector<Part> left;
    for (int i = 1; i < int(Part::Count); ++i)
        if (parts & (1u << i)) left.push_back(Part(i));
    // How many joints a part has. An extremity has one; the chest has four.
    auto degree = [](Part p) {
        int d = 0;
        for (const auto& j : kJoints) if (j[0] == p || j[1] == p) ++d;
        return d;
    };
    std::vector<std::vector<Part>> out;
    while (!left.empty()) {
        // SEED FROM AN EXTREMITY, AND BREAK TIES TOWARDS THE LEAF.
        //
        // Sum-of-distances alone is not enough, and a test caught it: on
        // an arm-and-leg section that still carries a chest and a hip, the
        // chest ties with the foot at ten, and seeding from the chest grows
        // chest+abdomen+thigh and leaves the calf and foot behind as a stump.
        // The foot has one joint and the chest has four, so preferring the
        // part with FEWER joints seeds from the toe and collects the whole leg.
        // Lowest enum last, so the same body always comes apart the same way.
        std::size_t seed = 0; int bestSum = -1; int bestDeg = 99;
        for (std::size_t i = 0; i < left.size(); ++i) {
            int sum = 0;
            for (std::size_t j = 0; j < left.size(); ++j) {
                const int d = PartDistance(left[i], left[j]);
                if (d > 0) sum += d;
            }
            const int deg = degree(left[i]);
            if (sum > bestSum || (sum == bestSum && deg < bestDeg)) {
                bestSum = sum; bestDeg = deg; seed = i;
            }
        }
        std::vector<Part> grp{ left[seed] };
        left.erase(left.begin() + long(seed));
        for (;;) {
            long pick = -1; int pickNear = 0;
            for (std::size_t i = 0; i < left.size(); ++i) {
                int far = 0, near = 1 << 20;
                bool ok = true;
                for (const Part g : grp) {
                    const int d = PartDistance(left[i], g);
                    if (d < 0) { ok = false; break; }
                    if (d > far)  far  = d;
                    if (d < near) near = d;
                }
                if (!ok || far > maxSpan) continue;
                if (pick < 0 || near < pickNear) { pick = long(i); pickNear = near; }
            }
            if (pick < 0) break;
            grp.push_back(left[std::size_t(pick)]);
            left.erase(left.begin() + pick);
        }
        out.push_back(std::move(grp));
    }
    return out;
}

std::vector<Section> SplitBySpan(const Lattice& L, const Section& S, int maxSpan)
{
    std::vector<Section> out;
    if (maxSpan < 1 || PartSpan(S.parts) <= maxSpan) { out.push_back(S); return out; }

    const std::vector<std::vector<Part>> groups = GroupPartsBySpan(S.parts, maxSpan);
    if (groups.size() < 2) { out.push_back(S); return out; }

    // part -> which group it joined
    int owner[std::size_t(Part::Count)];
    for (std::size_t i = 0; i < std::size_t(Part::Count); ++i) owner[i] = -1;
    for (std::size_t g = 0; g < groups.size(); ++g)
        for (const Part p : groups[g]) owner[std::size_t(p)] = int(g);

    std::vector<std::vector<Key>> bucket(groups.size());
    std::vector<Key> orphan;
    for (const Key& k : S.cells) {
        auto c = L.cells.find(k);
        if (c == L.cells.end()) continue;
        const Part p = PartOfBone(c->second.bone);
        const int g = (p == Part::Unknown) ? -1 : owner[std::size_t(p)];
        if (g < 0) orphan.push_back(k); else bucket[std::size_t(g)].push_back(k);
    }
    // UNNAMED CELLS GO WITH THEIR NEAREST NAMED NEIGHBOUR'S GROUP, not with
    // the biggest one. A sleeve belongs to the arm inside it; dropped into the
    // largest bucket it would be left hanging in the air beside the arm.
    for (const Key& k : orphan) {
        auto c = L.cells.find(k);
        if (c == L.cells.end()) continue;
        double best = 1e30; std::size_t bestG = 0;
        for (std::size_t g = 0; g < bucket.size(); ++g)
            for (const Key& n : bucket[g]) {
                auto cn = L.cells.find(n);
                if (cn == L.cells.end()) continue;
                const double dx = c->second.c[0] - cn->second.c[0];
                const double dy = c->second.c[1] - cn->second.c[1];
                const double dz = c->second.c[2] - cn->second.c[2];
                const double d2 = dx*dx + dy*dy + dz*dz;
                if (d2 < best) { best = d2; bestG = g; }
            }
        if (best < 1e29) bucket[bestG].push_back(k);
    }

    // ---- rebuild each sub-section's tallies exactly as Sections() does -----
    for (std::size_t g = 0; g < bucket.size(); ++g) {
        if (bucket[g].empty()) continue;
        Section T;
        T.cells = bucket[g];
        double sum[3] = { 0, 0, 0 };
        for (const Key& k : T.cells) {
            auto c = L.cells.find(k);
            if (c == L.cells.end()) continue;
            sum[0] += c->second.c[0]; sum[1] += c->second.c[1]; sum[2] += c->second.c[2];
            const Part p = PartOfBone(c->second.bone);
            if (p != Part::Unknown) {
                T.parts |= 1u << unsigned(p);
                ++T.cellsPer[std::size_t(p)];
                ++T.named;
                if (c->second.mine) ++T.minePer[std::size_t(p)];
            }
            if (c->second.mine) ++T.flesh;
        }
        const double d = double(T.cells.empty() ? 1 : T.cells.size());
        T.c[0] = float(sum[0] / d); T.c[1] = float(sum[1] / d); T.c[2] = float(sum[2] / d);
        std::size_t best = 0;
        for (std::size_t p = 1; p < std::size_t(Part::Count); ++p)
            if (T.cellsPer[p] > best) { best = T.cellsPer[p]; T.dominant = Part(p); }
        out.push_back(std::move(T));
    }
    std::sort(out.begin(), out.end(), [](const Section& a, const Section& b) {
        return a.cells.size() > b.cells.size();
    });
    if (out.empty()) out.push_back(S);
    return out;
}

std::size_t BridgeSections(Lattice& L, std::uint32_t mask, void (*say)(const char*, ...))
{
    std::vector<Section> secs = Sections(L, mask);
    if (secs.size() < 2) return 0;
    std::size_t added = 0;

    // The largest section is the trunk; everything else is linked to it. Not
    // to its nearest neighbour section -- linking every stray to the trunk is
    // both sufficient (they all end up in one component) and simpler to reason
    // about than a minimum spanning tree over body parts.
    const Section& trunk = secs[0];
    for (std::size_t i = 1; i < secs.size(); ++i) {
        const Section& S = secs[i];
        double best = 1e30;
        for (const Key& a : S.cells) {
            auto ca = L.cells.find(a);
            if (ca == L.cells.end() || Part(ca->second.part) == Part::Unknown) continue;
            for (const Key& b : trunk.cells) {
                auto cb = L.cells.find(b);
                if (cb == L.cells.end() || Part(cb->second.part) == Part::Unknown) continue;
                const double dx = ca->second.c[0] - cb->second.c[0];
                const double dy = ca->second.c[1] - cb->second.c[1];
                const double dz = ca->second.c[2] - cb->second.c[2];
                const double d2 = dx*dx + dy*dy + dz*dz;
                if (d2 < best) best = d2;
            }
        }
        if (!(best < 1e29)) continue;
        // EVERY PAIR NEARLY AS CLOSE AS THE CLOSEST, not just the closest one.
        // A single link would mean one cell of damage anywhere near it takes
        // their head off; a small cluster of links across the actual join means
        // it takes a cut through the join, which is the point.
        const double reach = std::sqrt(best) + L.cell;
        const double reach2 = reach * reach;
        std::size_t here = 0;
        for (const Key& a : S.cells) {
            auto ca = L.cells.find(a);
            if (ca == L.cells.end() || Part(ca->second.part) == Part::Unknown) continue;
            for (const Key& b : trunk.cells) {
                auto cb = L.cells.find(b);
                if (cb == L.cells.end() || Part(cb->second.part) == Part::Unknown) continue;
                const double dx = ca->second.c[0] - cb->second.c[0];
                const double dy = ca->second.c[1] - cb->second.c[1];
                const double dz = ca->second.c[2] - cb->second.c[2];
                if (dx*dx + dy*dy + dz*dz > reach2) continue;
                L.adj[a].insert(b);
                L.adj[b].insert(a);
                L.bridge[a].insert(b);
                L.bridge[b].insert(a);
                ++here;
            }
        }
        added += here;
        if (say)
            say("  bridged %u cell(s) of %s onto their main mass across a %.1f unit"
                " gap -- %u link(s)", unsigned(S.cells.size()),
                PartName(S.dominant), std::sqrt(best), unsigned(here));
    }
    return added;
}

std::uint32_t SoleParts(const std::vector<Section>& secs, std::size_t i)
{
    if (i >= secs.size()) return 0;
    std::uint32_t elsewhere = 0;
    for (std::size_t j = 0; j < secs.size(); ++j)
        if (j != i) elsewhere |= secs[j].parts;
    return secs[i].parts & ~elsewhere;
}

std::size_t TakeScraps(Lattice& L, std::size_t floorCells, std::map<Key, std::uint32_t>& ledger)
{
    const std::vector<Section> secs = Sections(L, kAllLayers);
    std::size_t biggest = 0;
    for (std::size_t i = 1; i < secs.size(); ++i)
        if (secs[i].cells.size() > secs[biggest].cells.size()) biggest = i;
    std::size_t took = 0;
    for (std::size_t i = 0; i < secs.size(); ++i) {
        if (i == biggest || secs[i].cells.size() >= floorCells) continue;
        if (!secs[i].cellsPer[std::size_t(Part::Chest)] && !secs[i].cellsPer[std::size_t(Part::Abdomen)]) continue;
        for (const Key& k : secs[i].cells) {
            auto it = L.cells.find(k);
            if (it == L.cells.end()) continue;
            ledger[k] |= it->second.layers;
            it->second.gone |= it->second.layers;
            ++took;
        }
    }
    return took;
}

std::vector<Section> Sections(const Lattice& L, std::uint32_t mask, std::uint32_t parts)
{
    // INDEXED ONCE, WALKED WITH INTEGERS.
    //
    // With std::map lookups per neighbour this costs 0.98 ms on a
    // three-hundred-cell body -- and it runs on the thread that has
    // to draw the next frame, where a stutter at the
    // moment of impact is the failure to avoid. Three hundred cells times twenty-six neighbours times
    // two red-black trees is where it goes. The cells are numbered once into a
    // vector, a hash maps a packed key to that number, and everything after is
    // array indexing.
    //
    // The pack is exact: a lattice coordinate is a floor of (position / cell)
    // and a body is a hundred and twenty units tall, so twenty-one bits per
    // axis is four orders of magnitude of headroom and there is no collision to
    // reason about.
    auto pack = [](const Key& k) {
        return (std::uint64_t(std::uint32_t(k.x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(k.y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(k.z) & 0x1FFFFFu) << 42);
    };

    std::vector<Key>  ks;
    std::vector<Part> ps;
    std::vector<const Cell*> cs;
    std::unordered_map<std::uint64_t, int> at;
    ks.reserve(L.cells.size()); ps.reserve(L.cells.size()); cs.reserve(L.cells.size());
    at.reserve(L.cells.size() * 2);
    for (const auto& [k, C] : L.cells) {
        // `parts` 0 means the whole body, which is every caller but the head
        // sweep. Cell::Alive(mask, parts) tests C.part, and C.part is set from
        // PartOfBone(C.bone) at build time -- the same classification `ps`
        // below takes -- so the filter and the walk agree by construction.
        if (!C.Alive(mask, parts)) continue;
        at.emplace(pack(k), int(ks.size()));
        ks.push_back(k);
        cs.push_back(&C);
        // Cell::part, NOT PartOfBone(C.bone). They are the same value by
        // construction -- Lattice::Build decides the owning bone and caches
        // the part from it in the same loop, two lines apart, and neither is
        // ever written again -- and the cached byte is why it was cached: a
        // string parse per cell per pass is not something this function may
        // pay, least of all now that a wound runs it twice (the head sweep).
        ps.push_back(Part(C.part));
    }
    const int n = int(ks.size());
    std::vector<int> comp(n, -1);
    std::vector<Section> out;

    // ---- components over the NAMED cells, hopping only across real joints
    std::vector<int> q;
    for (int seed = 0; seed < n; ++seed) {
        if (ps[seed] == Part::Unknown || comp[seed] >= 0) continue;
        const int id = int(out.size());
        out.push_back(Section());
        comp[seed] = id;
        q.clear(); q.push_back(seed);
        for (std::size_t head = 0; head < q.size(); ++head) {
            const int u = q[head];
            const Part pu = ps[u];
            out[id].cells.push_back(ks[u]);
            out[id].parts |= 1u << unsigned(pu);
            ++out[id].cellsPer[std::size_t(pu)];
            ++out[id].named;
            if (cs[u]->mine) {
                ++out[id].flesh;
                ++out[id].minePer[std::size_t(pu)];
            }
            for (const Key& v : L.Neighbours(ks[u])) {
                auto f = at.find(pack(v));
                if (f == at.end()) continue;
                const int w = f->second;
                if (comp[w] >= 0 || ps[w] == Part::Unknown) continue;
                // A bridge is walked whatever the anatomy says -- it was put
                // there because these two cells ARE attached on their whole
                // body, which is a stronger fact than any joint table.
                if (!PartsTouch(pu, ps[w]) && !L.Bridged(ks[u], ks[w])) continue;
                comp[w] = id;
                q.push_back(w);
            }
        }
    }

    // ---- the unnamed cells ride with whoever reaches them first
    //
    // A sleeve, a legging, a chain: geometry with no named bone behind it.
    // It cannot hold a limb on -- that is why it was kept out of the pass
    // above -- but when a limb goes, the cloth over that limb has to go with
    // it, or a sleeve is left hanging in the air where the arm was.
    {
        q.clear();
        for (int i = 0; i < n; ++i) if (comp[i] >= 0) q.push_back(i);
        for (std::size_t head = 0; head < q.size(); ++head) {
            const int u = q[head];
            const int id = comp[u];
            for (const Key& v : L.Neighbours(ks[u])) {
                auto f = at.find(pack(v));
                if (f == at.end()) continue;
                const int w = f->second;
                if (comp[w] >= 0 || ps[w] != Part::Unknown) continue;
                comp[w] = id;
                out[id].cells.push_back(ks[w]);
                if (cs[w]->mine) ++out[id].flesh;
                q.push_back(w);
            }
        }
    }

    // Cells no section claimed are unnamed geometry that no flesh of theirs ever
    // reaches -- a hat, a floating trinket. When a wound has already occurred
    // (any cell has gone != 0), any unnamed component that borders a destroyed
    // cell was severed from its owner by a cut and becomes a loose section so
    // the orphan sweep removes it instead of leaving stretched floating cloth.
    bool anyGone = false;
    for (const auto& [k, C] : L.cells) {
        if (C.gone != 0) { anyGone = true; break; }
    }
    if (anyGone && !out.empty()) {
        for (int seed = 0; seed < n; ++seed) {
            if (comp[seed] >= 0) continue;
            q.clear(); q.push_back(seed);
            comp[seed] = -2;
            bool touchesGone = false;
            for (std::size_t head = 0; head < q.size(); ++head) {
                const int u = q[head];
                for (const Key& v : L.Neighbours(ks[u])) {
                    auto cv = L.cells.find(v);
                    if (cv != L.cells.end() && cv->second.gone != 0) touchesGone = true;
                    auto f = at.find(pack(v));
                    if (f == at.end()) continue;
                    const int w = f->second;
                    if (comp[w] != -1) continue;
                    comp[w] = -2;
                    q.push_back(w);
                }
            }
            if (touchesGone) {
                const int id = int(out.size());
                out.push_back(Section());
                for (const int u : q) {
                    comp[u] = id;
                    out[id].cells.push_back(ks[u]);
                }
            }
        }
    }

    // ---- what each section is, and its middle
    for (Section& S : out) {
        std::size_t tally[std::size_t(Part::Count)] = {};
        double sum[3] = { 0, 0, 0 };
        for (const Key& k : S.cells) {
            auto f = at.find(pack(k));
            if (f == at.end()) continue;
            const int idx = f->second;
            sum[0] += cs[idx]->c[0]; sum[1] += cs[idx]->c[1]; sum[2] += cs[idx]->c[2];
            if (ps[idx] != Part::Unknown) ++tally[std::size_t(ps[idx])];
        }
        const double d = double(S.cells.empty() ? 1 : S.cells.size());
        S.c[0] = float(sum[0] / d); S.c[1] = float(sum[1] / d); S.c[2] = float(sum[2] / d);
        std::size_t best = 0;
        for (std::size_t p = 1; p < std::size_t(Part::Count); ++p)
            if (tally[p] > best) { best = tally[p]; S.dominant = Part(p); }
    }
    // ---- WHICH SECTION IS STILL *THEM* ---------------------------------
    //
    // Section [0] is the mass that stays on the actor; everything after it is
    // forged and dropped. That used to be decided purely by cell count, and
    // Halve broke it in testing: cut at the navel they come apart into legs
    // (146 cells) and torso (130), the legs win on size, and the TORSO is
    // taken away as a piece.
    //
    // Their head is a BSDynamicTriShape, which Voxelise skips (HF reads only
    // their face in, as skin) -- so the head is drawn on the ACTOR
    // no matter which section the actor keeps. Keep the legs and you get a
    // head floating over a pair of legs with no torso between them, as seen in
    // testing after a decapitation.
    //
    // So the chest outranks size. Their head sits on their chest; whichever
    // section holds the chest is the one that still looks like a person, and
    // it is the one they keep. This is the
    // invariant that was always implied by leaving the head out of the
    // lattice, and it went unnoticed only because no wound before this one
    // could take their whole chest off in a single piece.
    //
    // With no chest left anywhere -- Unmake, or a body already reduced to
    // limbs -- it falls back to size.
    auto holdsChest = [](const Section& s) {
        return s.cellsPer[std::size_t(Part::Chest)] > 0;
    };
    std::sort(out.begin(), out.end(), [&holdsChest](const Section& a, const Section& b) {
        const bool ca = holdsChest(a), cb = holdsChest(b);
        if (ca != cb) return ca;              // their head rides on their chest
        if (a.cells.size() != b.cells.size()) return a.cells.size() > b.cells.size();
        return a.c[2] > b.c[2];               // stable, and top-down reads better
    });
    return out;
}

}  // namespace flesh
