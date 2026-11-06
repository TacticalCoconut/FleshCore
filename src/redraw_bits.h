// redraw_bits.h -- FleshCore: the pure pieces of the redraw:
// the open grid (the clearance dilation), the skin-notch bridge, the lump weld and
// the table gather (one partition's survivors). Header-only, no engine
// types, so a test can compile them
// verbatim beside the DLL.
#pragma once
#include <cstdint>
#include <cstddef>
#include <climits>
#include <cmath>
#include <cstring>
#include <map>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <algorithm>
#include "lattice.h"

// THE OPEN GRID: the cells within two cells of a cut, as bytes in a
// box around them. Fit() reads the bounds off the cells; Mark125() stores the
// 125 positions around a key, two cells each way; Has() reads one. Bounded by the box
// plus two on every side, so a mark or a read for a key outside it -- there
// are none, since every key comes from the same cells -- is simply refused.
struct OpenGrid {
    int x0 = 0, y0 = 0, z0 = 0, nx = 0, ny = 0, nz = 0;
    std::vector<std::uint8_t> on;
    void FitBounds(int ax, int bx, int ay, int by, int az, int bz) {
        if (ax > bx) { nx = ny = nz = 0; on.clear(); return; }
        x0 = ax - 2; y0 = ay - 2; z0 = az - 2;
        nx = bx - ax + 5; ny = by - ay + 5; nz = bz - az + 5;
        on.assign(std::size_t(nx) * ny * nz, 0);
    }
    void Fit(const std::map<flesh::Key, flesh::Cell>& cells) {
        if (cells.empty()) { nx = ny = nz = 0; on.clear(); return; }
        int ax = INT_MAX, ay = INT_MAX, az = INT_MAX, bx = INT_MIN, by = INT_MIN, bz = INT_MIN;
        for (const auto& kv : cells) {
            const flesh::Key& k = kv.first;
            ax = std::min(ax, k.x); ay = std::min(ay, k.y); az = std::min(az, k.z);
            bx = std::max(bx, k.x); by = std::max(by, k.y); bz = std::max(bz, k.z);
        }
        FitBounds(ax, bx, ay, by, az, bz);
    }
    bool Inside(int x, int y, int z) const {
        return x >= x0 && x < x0 + nx && y >= y0 && y < y0 + ny && z >= z0 && z < z0 + nz;
    }
    std::size_t At(int x, int y, int z) const {
        return (std::size_t(z - z0) * ny + std::size_t(y - y0)) * nx + std::size_t(x - x0);
    }
    void Mark27(const flesh::Key& k) {
        for (int a = -1; a <= 1; ++a)
        for (int b = -1; b <= 1; ++b)
        for (int c = -1; c <= 1; ++c)
            if (Inside(k.x + a, k.y + b, k.z + c)) on[At(k.x + a, k.y + b, k.z + c)] = 1;
    }
    void Mark125(const flesh::Key& k) {
        Mark125Bits(k, 1u);
    }
    void Mark125Bits(const flesh::Key& k, std::uint8_t mask) {
        if (on.empty()) return;
        const int rx = k.x - x0, ry = k.y - y0, rz = k.z - z0;
        if (rx >= 2 && rx + 2 < nx && ry >= 2 && ry + 2 < ny && rz >= 2 && rz + 2 < nz) {
            const std::size_t strideY = std::size_t(nx);
            const std::size_t strideZ = std::size_t(nx) * std::size_t(ny);
            for (int c = -2; c <= 2; ++c) {
                std::uint8_t* zBase = on.data() + std::size_t(rz + c) * strideZ + std::size_t(rx - 2);
                for (int b = -2; b <= 2; ++b) {
                    std::uint8_t* row = zBase + std::size_t(ry + b) * strideY;
                    row[0] |= mask; row[1] |= mask; row[2] |= mask; row[3] |= mask; row[4] |= mask;
                }
            }
            return;
        }
        for (int a = -2; a <= 2; ++a)
        for (int b = -2; b <= 2; ++b)
        for (int c = -2; c <= 2; ++c)
            if (Inside(k.x + a, k.y + b, k.z + c)) on[At(k.x + a, k.y + b, k.z + c)] |= mask;
    }
    bool Has(const flesh::Key& k) const { return Inside(k.x, k.y, k.z) && (on[At(k.x, k.y, k.z)] & 1u) != 0; }
    std::uint8_t GetBits(const flesh::Key& k) const { return Inside(k.x, k.y, k.z) ? on[At(k.x, k.y, k.z)] : 0u; }
};

// ONE PARTITION'S SURVIVORS FROM THE TABLE: for each triangle, its cell's
// `gone` word and clearance verdict decide it, and the survivors are copied
// straight from the original list. The one gather both paths use.
static inline std::uint32_t GatherPart(const std::uint16_t* tab, std::uint32_t real, const std::uint16_t* orig, int L,
                      const std::uint32_t* goneOf, const std::uint8_t* coveredOf, std::size_t cellCount,
                      std::vector<std::uint16_t>& out, std::size_t& hid, bool underArmourSkin = false)
{
    for (std::uint32_t t = 0; t < real; ++t) {
        const std::uint16_t o = tab[t];
        if (o == flesh::Lattice::kNoCell) continue;
        const std::uint16_t c = std::uint16_t(o & 0x7FFF);
        if (c >= cellCount) continue;
        if (underArmourSkin) {
            // Hidden body skin under a cuirass: only draw in cells where worn
            // armour (0x10) has been peeled off and skin (0x01) is still intact.
            if (!(goneOf[c] & flesh::kArmourBit)) continue;
            if (goneOf[c] & 1u) continue;
        } else {
            if (goneOf[c] & (1u << L)) continue;
            // THE CLEARANCE RULE: hold back all interior fill lumps outside the
            // 2-cell neighbourhood of actual cuts so unwounded body parts (head,
            // hands, feet) never show internal skull/muscle lumps.
            if (L >= 1 && L < 4 && coveredOf[c]) { ++hid; continue; }
        }
        out.push_back(orig[t * 3]); out.push_back(orig[t * 3 + 1]); out.push_back(orig[t * 3 + 2]);
    }
    return std::uint32_t(out.size() / 3);
}

// CUT SKIN EDGES WITHOUT THE STAIRCASE.
// A cut along cell lines leaves 90-degree notches in the skin, so a triangle of a
// cut cell is drawn again when it fills a corner: it shares at least TWO edges with
// surviving triangles on the same side of the cut (never bridging across a cut).
static inline std::uint32_t BridgeSkinNotches(
    const std::uint16_t* orig, std::uint32_t real,
    std::vector<std::uint16_t>& keep, std::uint32_t cap)
{
    if (keep.size() < 6 || !orig || !real) return 0;
    std::uint32_t maxV = 0;
    for (std::uint16_t v : keep) {
        if (std::uint32_t(v) >= maxV) maxV = std::uint32_t(v) + 1u;
    }
    if (!maxV || maxV > 65536u) return 0;
    std::vector<std::uint8_t> aliveV(maxV, 0);
    for (std::uint16_t v : keep) aliveV[v] = 1;

    auto edgeKey = [](std::uint16_t a, std::uint16_t b) -> std::uint32_t {
        return a < b ? ( (std::uint32_t(a) << 16) | std::uint32_t(b) )
                     : ( (std::uint32_t(b) << 16) | std::uint32_t(a) );
    };
    const std::size_t origKeepSize = keep.size();
    std::size_t hashCap = 64u;
    while (hashCap < origKeepSize * 2u) hashCap <<= 1;
    const std::size_t hashMask = hashCap - 1u;
    std::vector<std::uint32_t> aliveTable(hashCap, 0xFFFFFFFFu);
    auto insertEdge = [&](std::uint32_t ek) {
        if (ek == 0xFFFFFFFFu) return;
        std::size_t slot = (std::size_t(ek * 2654435761u)) & hashMask;
        while (aliveTable[slot] != 0xFFFFFFFFu && aliveTable[slot] != ek)
            slot = (slot + 1u) & hashMask;
        aliveTable[slot] = ek;
    };
    auto hasEdge = [&](std::uint32_t ek) -> bool {
        if (ek == 0xFFFFFFFFu) return false;
        std::size_t slot = (std::size_t(ek * 2654435761u)) & hashMask;
        while (aliveTable[slot] != 0xFFFFFFFFu) {
            if (aliveTable[slot] == ek) return true;
            slot = (slot + 1u) & hashMask;
        }
        return false;
    };
    for (std::size_t i = 0; i + 2 < origKeepSize; i += 3) {
        const std::uint16_t a = keep[i], b = keep[i + 1], c = keep[i + 2];
        insertEdge(edgeKey(a, b));
        insertEdge(edgeKey(b, c));
        insertEdge(edgeKey(c, a));
    }

    std::size_t ki = 0;
    std::uint32_t added = 0;
    for (std::uint32_t t = 0; t < real; ++t) {
        if (keep.size() / 3 >= cap) break;
        const std::uint16_t v0 = orig[t * 3];
        const std::uint16_t v1 = orig[t * 3 + 1];
        const std::uint16_t v2 = orig[t * 3 + 2];
        if (ki + 2 < origKeepSize && keep[ki] == v0 && keep[ki + 1] == v1 && keep[ki + 2] == v2) {
            ki += 3;
            continue;
        }
        if (v0 < maxV && v1 < maxV && v2 < maxV &&
            aliveV[v0] && aliveV[v1] && aliveV[v2]) {
            const int sharedEdges = int(hasEdge(edgeKey(v0, v1)))
                                  + int(hasEdge(edgeKey(v1, v2)))
                                  + int(hasEdge(edgeKey(v2, v0)));
            if (sharedEdges >= 2) {
                keep.push_back(v0);
                keep.push_back(v1);
                keep.push_back(v2);
                ++added;
            }
        }
    }
    return added;
}

// LUMPS THAT TOUCH ARE DRAWN AS ONE.
// Surviving muscle (`FleshMuscle*`) and bone lumps next to each other
// (`FleshBone*`) are drawn as one strand or plate, not a string of beads:
//   1. the surviving lumps, by triangle connectivity over `keep`;
//   2. each lump's surviving neighbours within inter-voxel reach;
//   3. the facing hemisphere vertices stretched across the gap, the waist
//      between them inflated so it does not pinch, and the normal crease
//      along the axis projected out so the pair shades as one.
// Changes only what is drawn.
static inline bool WeldConnectedLumps(
    const std::uint8_t* rawVerts, std::uint32_t nVerts, std::uint32_t vsize, std::uint64_t desc,
    const std::vector<std::uint16_t>& keep, float cellPitch,
    std::vector<std::uint8_t>& outVerts)
{
    if (!rawVerts || !nVerts || vsize < 12 || keep.size() < 6) return false;
    outVerts.assign(rawVerts, rawVerts + std::size_t(nVerts) * vsize);

    // 1. Mark active vertices and group into connected lump components.
    std::vector<std::int32_t> parent(nVerts, -1);
    for (std::uint16_t v : keep) {
        if (v < nVerts) parent[v] = std::int32_t(v);
    }
    auto findRoot = [&](std::int32_t x) {
        std::int32_t r = x;
        while (parent[r] != r) r = parent[r];
        while (x != r) { std::int32_t p = parent[x]; parent[x] = r; x = p; }
        return r;
    };
    const std::size_t nTris = keep.size() / 3;
    for (std::size_t t = 0; t < nTris; ++t) {
        const std::uint16_t a = keep[t * 3], b = keep[t * 3 + 1], c = keep[t * 3 + 2];
        if (a >= nVerts || b >= nVerts || c >= nVerts) continue;
        const std::int32_t ra = findRoot(a), rb = findRoot(b), rc = findRoot(c);
        if (ra != rb) parent[rb] = ra;
        const std::int32_t r2 = findRoot(ra);
        if (r2 != rc) parent[rc] = r2;
    }

    std::vector<std::int32_t> rootToComp(nVerts, -1);
    struct LumpComp {
        std::vector<std::uint16_t> verts;
        float c[3] = {0.0f, 0.0f, 0.0f};
        float rad = 0.0f;
        std::uint8_t bone0 = 0xFF;
    };
    std::vector<LumpComp> lumps;
    lumps.reserve(256);
    for (std::uint32_t v = 0; v < nVerts; ++v) {
        if (parent[v] < 0) continue;
        const std::int32_t r = findRoot(std::int32_t(v));
        std::int32_t cid = rootToComp[r];
        if (cid < 0) {
            cid = std::int32_t(lumps.size());
            rootToComp[r] = cid;
            lumps.emplace_back();
        }
        lumps[cid].verts.push_back( std::uint16_t(v) );
    }
    if (lumps.size() < 2) return false;

    // 2. Compute centroid and radius for each lump component.
    for (LumpComp& L : lumps) {
        if (L.verts.empty() || L.verts.size() > 256) { L.rad = 0.0f; continue; }
        double sx = 0.0, sy = 0.0, sz = 0.0;
        for (std::uint16_t v : L.verts) {
            float p[3];
            flesh::PosOf(rawVerts + std::size_t(v) * vsize, desc, p);
            sx += p[0]; sy += p[1]; sz += p[2];
        }
        const double inv = 1.0 / double(L.verts.size());
        L.c[0] = float(sx * inv);
        L.c[1] = float(sy * inv);
        L.c[2] = float(sz * inv);
        float maxR2 = 0.0f;
        for (std::uint16_t v : L.verts) {
            float p[3];
            flesh::PosOf(rawVerts + std::size_t(v) * vsize, desc, p);
            const float dx = p[0] - L.c[0], dy = p[1] - L.c[1], dz = p[2] - L.c[2];
            const float d2 = dx * dx + dy * dy + dz * dz;
            if (d2 > maxR2) maxR2 = d2;
        }
        L.rad = std::sqrt(maxR2);
        if (vsize >= 40) {
            L.bone0 = rawVerts[std::size_t(L.verts[0]) * vsize + 36];
        }
    }

    // 3. Spatial hash grid over lump centroids to find connected neighbour lumps.
    const float gridCell = (cellPitch > 1.5f) ? cellPitch : 3.5f;
    auto packKey = [](std::int32_t x, std::int32_t y, std::int32_t z) -> std::uint64_t {
        return (std::uint64_t(std::uint32_t(x) & 0x1FFFFFu))
             | (std::uint64_t(std::uint32_t(y) & 0x1FFFFFu) << 21)
             | (std::uint64_t(std::uint32_t(z) & 0x1FFFFFu) << 42);
    };
    std::unordered_map<std::uint64_t, std::vector<std::size_t>> grid;
    grid.reserve(lumps.size() * 2);
    for (std::size_t i = 0; i < lumps.size(); ++i) {
        if (lumps[i].rad <= 0.01f) continue;
        const std::int32_t gx = std::int32_t(std::floor(lumps[i].c[0] / gridCell));
        const std::int32_t gy = std::int32_t(std::floor(lumps[i].c[1] / gridCell));
        const std::int32_t gz = std::int32_t(std::floor(lumps[i].c[2] / gridCell));
        grid[packKey(gx, gy, gz)].push_back(i);
    }

    auto encodeSNorm = [](float f) -> std::uint8_t {
        if (f < -1.0f) f = -1.0f;
        if (f >  1.0f) f =  1.0f;
        return std::uint8_t(std::lround(f * 127.5f + 127.5f));
    };

    struct NbrInfo {
        float u[3];
        float dist;
        float rB;
    };
    std::vector<NbrInfo> nbrs;
    nbrs.reserve(24);
    bool anyWelded = false;

    // 4. For each lump, bridge its vertices and normals toward connected neighbours.
    for (std::size_t i = 0; i < lumps.size(); ++i) {
        const LumpComp& A = lumps[i];
        if (A.rad <= 0.01f) continue;
        nbrs.clear();

        const std::int32_t gx = std::int32_t(std::floor(A.c[0] / gridCell));
        const std::int32_t gy = std::int32_t(std::floor(A.c[1] / gridCell));
        const std::int32_t gz = std::int32_t(std::floor(A.c[2] / gridCell));

        for (std::int32_t dx = -1; dx <= 1; ++dx)
        for (std::int32_t dy = -1; dy <= 1; ++dy)
        for (std::int32_t dz = -1; dz <= 1; ++dz) {
            auto it = grid.find(packKey(gx + dx, gy + dy, gz + dz));
            if (it == grid.end()) continue;
            for (std::size_t j : it->second) {
                if (j == i) continue;
                const LumpComp& B = lumps[j];
                if (B.rad <= 0.01f) continue;
                const float vx = B.c[0] - A.c[0], vy = B.c[1] - A.c[1], vz = B.c[2] - A.c[2];
                const float d2 = vx * vx + vy * vy + vz * vz;
                const float sumR = A.rad + B.rad;
                const bool sameBone = (A.bone0 == B.bone0);
                const float maxReach = sameBone
                    ? std::max(2.35f * sumR, 1.55f * gridCell)
                    : (1.55f * sumR);
                if (d2 <= 0.001f || d2 > maxReach * maxReach) continue;
                const float dist = std::sqrt(d2);
                nbrs.push_back(NbrInfo{ { vx / dist, vy / dist, vz / dist }, dist, B.rad });
            }
        }
        if (nbrs.empty()) continue;

        // Sort closest neighbours first and cap at 12 so dense clusters stay balanced.
        std::sort(nbrs.begin(), nbrs.end(), [](const NbrInfo& a, const NbrInfo& b) {
            return a.dist < b.dist;
        });
        if (nbrs.size() > 12) nbrs.resize(12);
        anyWelded = true;

        const bool hasNormals = (vsize >= 28 && (desc & (1ULL << 51)) == 0);
        for (std::uint16_t v : A.verts) {
            const std::uint8_t* srcRec = rawVerts + std::size_t(v) * vsize;
            std::uint8_t*       dstRec = outVerts.data() + std::size_t(v) * vsize;

            float p[3];
            flesh::PosOf(srcRec, desc, p);
            const float rel[3] = { p[0] - A.c[0], p[1] - A.c[1], p[2] - A.c[2] };
            const float relLen = std::sqrt(rel[0]*rel[0] + rel[1]*rel[1] + rel[2]*rel[2]);
            if (relLen <= 1e-5f) continue;
            const float dHat[3] = { rel[0] / relLen, rel[1] / relLen, rel[2] / relLen };

            float shift[3] = { 0.0f, 0.0f, 0.0f };
            float wSum = 0.0f;

            float nrm[3] = { dHat[0], dHat[1], dHat[2] };
            if (hasNormals) {
                nrm[0] = (float(srcRec[20]) / 127.5f) - 1.0f;
                nrm[1] = (float(srcRec[21]) / 127.5f) - 1.0f;
                nrm[2] = (float(srcRec[22]) / 127.5f) - 1.0f;
            }

            for (const NbrInfo& nb : nbrs) {
                const float alpha = dHat[0]*nb.u[0] + dHat[1]*nb.u[1] + dHat[2]*nb.u[2];
                if (alpha <= 0.12f) continue;
                float t = (alpha - 0.12f) / 0.72f;
                if (t > 1.0f) t = 1.0f;
                const float w = t * t * (3.0f - 2.0f * t);

                // Axial reach across the inter-lump gap to fuse with neighbour B.
                const float sPar = rel[0]*nb.u[0] + rel[1]*nb.u[1] + rel[2]*nb.u[2];
                const float targetPar = 0.57f * nb.dist;
                const float addPar = (targetPar > sPar) ? (targetPar - sPar) * w : 0.0f;

                // Cylindrical waist inflation perpendicular to nb.u so the sphere
                // does not pinch between A and B.
                const float perp[3] = {
                    rel[0] - sPar * nb.u[0],
                    rel[1] - sPar * nb.u[1],
                    rel[2] - sPar * nb.u[2]
                };
                const float perpLen = std::sqrt(perp[0]*perp[0] + perp[1]*perp[1] + perp[2]*perp[2]);
                const float collarR = 0.88f * (0.65f * A.rad + 0.35f * nb.rB);
                float addPerp = 0.0f;
                if (perpLen > 1e-4f && collarR > perpLen) {
                    addPerp = 0.72f * w * (collarR - perpLen) / perpLen;
                }

                shift[0] += addPar * nb.u[0] + addPerp * perp[0];
                shift[1] += addPar * nb.u[1] + addPerp * perp[1];
                shift[2] += addPar * nb.u[2] + addPerp * perp[2];
                wSum += w;

                // Flatten out the spherical normal component pointing into the
                // neighbour so connected balls shade as a continuous cylinder/sheet.
                const float nDotU = nrm[0]*nb.u[0] + nrm[1]*nb.u[1] + nrm[2]*nb.u[2];
                if (nDotU > 0.0f) {
                    const float damp = 0.86f * w;
                    nrm[0] -= damp * nDotU * nb.u[0];
                    nrm[1] -= damp * nDotU * nb.u[1];
                    nrm[2] -= damp * nDotU * nb.u[2];
                }
            }

            if (wSum > 0.0f) {
                const float normScale = (wSum > 1.35f) ? (1.35f / wSum) : 1.0f;
                const float newP[3] = {
                    p[0] + shift[0] * normScale,
                    p[1] + shift[1] * normScale,
                    p[2] + shift[2] * normScale
                };
                if ((desc & (1ULL << 51)) == 0) {
                    std::memcpy(dstRec, newP, 12);
                }
                if (hasNormals) {
                    const float nLen = std::sqrt(nrm[0]*nrm[0] + nrm[1]*nrm[1] + nrm[2]*nrm[2]);
                    if (nLen > 1e-4f) {
                        nrm[0] /= nLen; nrm[1] /= nLen; nrm[2] /= nLen;
                        dstRec[20] = encodeSNorm(nrm[0]);
                        dstRec[21] = encodeSNorm(nrm[1]);
                        dstRec[22] = encodeSNorm(nrm[2]);
                        // Keep tangent orthogonal to the blended normal.
                        float tng[3] = {
                            (float(srcRec[24]) / 127.5f) - 1.0f,
                            (float(srcRec[25]) / 127.5f) - 1.0f,
                            (float(srcRec[26]) / 127.5f) - 1.0f
                        };
                        const float tDotN = tng[0]*nrm[0] + tng[1]*nrm[1] + tng[2]*nrm[2];
                        tng[0] -= tDotN * nrm[0];
                        tng[1] -= tDotN * nrm[1];
                        tng[2] -= tDotN * nrm[2];
                        const float tLen = std::sqrt(tng[0]*tng[0] + tng[1]*tng[1] + tng[2]*tng[2]);
                        if (tLen > 1e-4f) {
                            dstRec[24] = encodeSNorm(tng[0] / tLen);
                            dstRec[25] = encodeSNorm(tng[1] / tLen);
                            dstRec[26] = encodeSNorm(tng[2] / tLen);
                        }
                    }
                }
            }
        }
    }
    return anyWelded;
}
