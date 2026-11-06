// WHAT ONE BLOW OF EACH WEAPON TAKES OFF A REAL BODY.
//
// Builds a lattice from the shipped fill store with the real Lattice::Build,
// then runs Separate's geometry steps -- selection, the tear rule, islands,
// fuse, absorb, the piece budget, the sever plane, the section sweep -- from
// seeds on their surface all over the body. No engine, no game: this measures
// the SHAPE of a wound, which is what "explosive" means here, and it
// is the only bench for it short of play.
//
// What it does not model: peel stages (every selected cell loses every layer,
// so a bite below Gorefest reads as an UPPER bound), armour factors, and the
// skin shapes a live body adds around the fill.
//
// POSITIVE CONTROL: the old Gorefest blade must reproduce the tested
// many-part blows (12 named parts from one swing in a test log).
// NULL CONTROL: the lattice must arrive as one section, so every part lost is
// a part this blow took.
//
// THE LIMITS BELOW ARE COPIED BY HAND from kWeaponCuts and WoundActor in
// flesh.cpp, and the slider's curves from PresetScales, PresetBladeReach and
// HQBuild. Change them there, change them here, and read the table again.
//
// A blow "explodes" here when it takes three or more named parts. The test
// fails if the controls fail, or if any weapon does that on more than 20 % of
// blows at any slider. The greatsword and the battleaxe are exempt and printed:
// a long cleave through them is what those two are for.
//
// build (from test/):
//        x86_64-w64-mingw32-g++ -std=c++17 -O2 -include array -I ../src blast_test.cpp ../src/lattice.cpp
//            -static -static-libgcc -static-libstdc++ -o blast_test.exe
// usage: blast_test <FleshCore.fill.bin>
#include "lattice.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>
using namespace flesh;
typedef std::uint32_t u32;

struct Store {
    std::vector<std::string> bones;
    std::vector<ShapeData> shapes;
    std::vector<std::vector<TriRef>> tris;
    std::vector<std::vector<std::uint8_t>> recs;
    std::vector<std::vector<const char*>> vbone;
};
static bool LoadFill(const char* path, Store& F)
{
    FILE* f = std::fopen(path, "rb");
    if (!f) return false;
    auto r32 = [&](u32* v) { return std::fread(v, 4, 1, f) == 1; };
    auto rs = [&](std::string* o) { u32 n = 0; if (!r32(&n) || n > (1u << 20)) return false;
        o->assign(n, '\0'); return n == 0 || std::fread(&(*o)[0], 1, n, f) == n; };
    u32 nB = 0; if (!r32(&nB)) return false;
    F.bones.resize(nB);
    for (u32 i = 0; i < nB; ++i) if (!rs(&F.bones[i])) return false;
    u32 nS = 0; if (!r32(&nS)) return false;
    F.shapes.resize(nS); F.tris.resize(nS); F.recs.resize(nS); F.vbone.resize(nS);
    for (u32 si = 0; si < nS; ++si) {
        ShapeData& S = F.shapes[si];
        if (!rs(&S.name)) return false;
        u32 skin = 0, layer = 0, nV = 0, vsize = 0; std::uint64_t desc = 0;
        if (std::fread(&desc, 8, 1, f) != 1 || !r32(&vsize) || !r32(&skin) || !r32(&layer) || !r32(&nV)) return false;
        S.desc = desc; S.vsize = vsize; S.skin = skin != 0; S.layer = int(layer); S.nVerts = nV;
        u32 nRec = 0; if (!r32(&nRec)) return false;
        F.recs[si].resize(nRec);
        if (nRec && std::fread(F.recs[si].data(), 1, nRec, f) != nRec) return false;
        u32 nT = 0; if (!r32(&nT)) return false;
        F.tris[si].resize(nT);
        for (u32 t = 0; t < nT; ++t) {
            std::uint16_t v[3]; if (std::fread(v, 2, 3, f) != 3) return false;
            F.tris[si][t].shape = si; F.tris[si][t].part = 0;
            F.tris[si][t].v[0] = v[0]; F.tris[si][t].v[1] = v[1]; F.tris[si][t].v[2] = v[2];
        }
        u32 nTex = 0; if (!r32(&nTex)) return false;
        for (u32 t = 0; t < nTex; ++t) { std::string s; if (!rs(&s)) return false; S.tex.push_back(s); }
        F.vbone[si].assign(nV, nullptr);
        for (u32 v = 0; v < nV; ++v) {
            std::int32_t b = 0; if (std::fread(&b, 4, 1, f) != 1) return false;
            F.vbone[si][v] = (b >= 0 && std::size_t(b) < F.bones.size()) ? F.bones[std::size_t(b)].c_str() : nullptr;
        }
    }
    std::fclose(f);
    for (u32 si = 0; si < nS; ++si) {
        ShapeData& S = F.shapes[si];
        S.verts = F.recs[si].data(); S.vertBone = F.vbone[si];
        S.lumpTris = (F.tris[si].size() % 48u) == 0 ? 48u : 0u;     // what every shape of this store measures
    }
    return true;
}

// ---- one wound, Separate's order ---------------------------------------------
struct Spec {
    const char* name; Lattice::Form form; float size; float reach; int maxCells; int budget;
    bool blunt;      // allowTear is false for a blunt blow
};
struct Result { int sel = 0, taken = 0, detached = 0, sections = 0, lost = 0, pieces = 0; };
static std::map<int, int> g_born;
static bool IsSlab(Lattice::Form f) { return f == Lattice::Form::SlabX || f == Lattice::Form::SlabY || f == Lattice::Form::SlabZ; }
static bool IsBore(Lattice::Form f) { return f == Lattice::Form::BoreX || f == Lattice::Form::BoreY || f == Lattice::Form::BoreZ; }

template <class Adj>
static Result Blow(Lattice& L, const float p[3], const Spec& s, const Adj& adj0, int fuse, int minCells, int dropCells)
{
    Result R;
    const std::uint32_t mask = kAllLayers;
    const bool plane = IsSlab(s.form) || IsBore(s.form);
    const int cap = plane ? int(L.cells.size()) + 1 : s.budget * s.maxCells;
    std::vector<Key> sel;
    auto selectAt = [&](const float* at) {
        if (IsSlab(s.form) && s.reach > 0.0f) {
            float n[3]; Lattice::SlabNormal(s.form, n);
            return L.SelectPlane(at, n, s.size, s.reach, cap, mask, 0);
        }
        return L.Select(s.form, at, s.size, 1, cap, mask, 0);
    };
    sel = selectAt(p);
    if (sel.empty()) {
        float q[3], d = 0; int live = 0;
        if (L.NearestLive(p, mask, q, &d, &live, 0)) sel = selectAt(q);
    }
    R.sel = int(sel.size());
    if (sel.empty()) return R;
    if (!s.blunt) L.Tear(sel, 0.5f, nullptr);
    auto islands = L.Islands(sel, s.maxCells);
    islands = L.Fuse(islands, fuse);
    if (minCells >= 2) {
        const std::size_t want = std::min(std::size_t(minCells), std::size_t(std::max(1, (s.maxCells * 9) / 10)));
        islands = L.AbsorbSmall(islands, want);
    }
    std::vector<Key> taken; int made = 0;
    for (const auto& isl : islands) {
        if (made >= s.budget) break;
        const int floorC = std::min(dropCells, std::max(1, s.maxCells / 2));
        if (floorC > 0 && int(isl.size()) < floorC) { taken.insert(taken.end(), isl.begin(), isl.end()); continue; }
        taken.insert(taken.end(), isl.begin(), isl.end()); ++made;
    }
    if (plane) taken = sel;                       // isFullSever: `taken = sel`, budget or no budget
    L.MarkGone(taken, mask);
    if (plane) L.SeverPlane();
    R.taken = int(taken.size()); R.pieces = made;
    auto secs = Sections(L, kAllLayers);
    if (!secs.empty()) {
        std::size_t big = 0;
        for (std::size_t i = 1; i < secs.size(); ++i) if (secs[i].cells.size() > secs[big].cells.size()) big = i;
        std::map<int, int> attached;
        for (const Key& k : secs[big].cells) ++attached[int(L.cells.at(k).part)];
        for (std::size_t i = 0; i < secs.size(); ++i) if (i != big) { R.detached += int(secs[i].cells.size()); ++R.sections; }
        for (const auto& [pt, born] : g_born) {
            if (pt == int(Part::Unknown)) continue;
            const int N = PartIsLimb(Part(pt)) ? 4 : 2;      // D row: lossLimb 4, lossTrunk 2, lossHead 2
            if (attached[pt] * N < born) ++R.lost;
        }
    }
    for (auto& kv : L.cells) kv.second.gone = 0;
    if (plane) L.adj = adj0;
    return R;
}

static int Pct(std::vector<int> v, double q) { if (v.empty()) return 0; std::sort(v.begin(), v.end()); return v[std::size_t(q * double(v.size() - 1))]; }

int main(int argc, char** argv)
{
    if (argc < 2) { std::puts("usage: blast_test <fill.bin>"); return 2; }
    Store F;
    if (!LoadFill(argv[1], F)) { std::puts("could not read the store"); return 2; }
    int failed = 0;
    for (float cell : { 8.0f, 4.0f }) {
        Lattice L; L.Build(F.shapes, F.tris, cell, 1.0f, 1.6f);
        BridgeSections(L, kAllLayers, nullptr);
        auto whole = Sections(L, kAllLayers);
        if (whole.size() != 1u) { std::printf("FAIL: %u sections at birth\n", unsigned(whole.size())); ++failed; }
        g_born.clear();
        float lo[3] = {1e9f,1e9f,1e9f}, hi[3] = {-1e9f,-1e9f,-1e9f};
        std::map<int, std::array<float, 6>> ext;
        for (const auto& [k, C] : L.cells) {
            ++g_born[int(C.part)];
            auto it = ext.find(int(C.part));
            if (it == ext.end()) it = ext.emplace(int(C.part), std::array<float, 6>{1e9f,-1e9f,1e9f,-1e9f,1e9f,-1e9f}).first;
            for (int q = 0; q < 3; ++q) {
                lo[q] = std::min(lo[q], C.c[q]); hi[q] = std::max(hi[q], C.c[q]);
                it->second[q*2] = std::min(it->second[q*2], C.c[q]); it->second[q*2+1] = std::max(it->second[q*2+1], C.c[q]);
            }
        }
        std::printf("\n################ cell %.0f: %u cells, %u section(s) at birth, box %.0f x %.0f x %.0f\n",
                    double(cell), unsigned(L.cells.size()), unsigned(whole.size()),
                    double(hi[0]-lo[0]+cell), double(hi[1]-lo[1]+cell), double(hi[2]-lo[2]+cell));
        if (cell == 4.0f) for (const auto& [pt, n] : g_born) {
            const auto& e = ext[pt];
            std::printf("  %-16s %4d cells, extent x %.0f y %.0f z %.0f\n", PartName(Part(pt)), n,
                        double(e[1]-e[0]+cell), double(e[3]-e[2]+cell), double(e[5]-e[4]+cell));
        }
        // SURFACE SEEDS: a blow lands on the outside of them.
        std::vector<Key> seeds;
        for (const auto& kv : L.adj) if (kv.second.size() <= 18u) seeds.push_back(kv.first);
        std::sort(seeds.begin(), seeds.end());
        const std::size_t stride = std::max<std::size_t>(1, seeds.size() / 260);
        std::vector<Key> use; for (std::size_t i = 0; i < seeds.size(); i += stride) use.push_back(seeds[i]);
        const auto adj0 = L.adj;
        std::vector<Spec> specs;
        const float h = 0.75f * cell;
        using Fm = Lattice::Form;
        // The limits, as WoundActor applies them.
        auto bladeReach = [&](float units) { return std::max(units + 4.0f - cell, 0.5f * cell); };   // SeverPlane pads one cell
        auto limit = [&](float want, float most) { return std::min(want, std::max(most, 0.5f * cell)); };
        const struct { const char* n; float rm; } Blades[] = {
            {"dagger", 0.20f}, {"sword", 0.30f}, {"waraxe", 0.25f}, {"battleaxe", 0.50f}, {"greatsword", 1.00f} };
        const struct { const char* n; float most; bool bore; bool blunt; } Others[] = {
            {"bow", 3.0f, true, false}, {"crossbow", 4.0f, true, false},
            {"mace", 7.0f, false, true}, {"warhammer", 10.0f, false, true}, {"bash", 5.25f, false, true} };
        static char names[96][48]; int nn = 0;
        specs.push_back({"#controls and what this replaces", Fm::SlabZ, 0, 0, 0, 0, false});
        specs.push_back({"control: the old Gorefest blade", Fm::SlabZ, 15.0f, 0.0f, 34, 8, false});
        specs.push_back({"saved panel: every physical blow", Fm::SlabZ, h, 10.0f * cell, 24, 3, false});
        for (int lvl : { 30, 72, 100 }) {
            const float scale = lvl <= 50 ? 0.75f + 0.40f * float(lvl) / 50.0f : 1.15f + 0.55f * float(lvl - 50) / 50.0f;
            const float uSize = std::max(2.0f, std::min(30.0f, std::round(6.0f * scale)));
            const float uReach = std::max(12.0f, std::min(40.0f, std::round(12.0f + 28.0f * (scale - 0.75f) / 0.95f)));
            const int maxC = lvl >= 85 ? 34 : lvl >= 50 ? 24 : 18;
            const int budget = lvl >= 60 ? 3 : 2;              // 8 or 4, capped at 3 a blow; 2 below 60 %
            static char head[3][72];
            char* hd = head[lvl == 30 ? 0 : lvl == 72 ? 1 : 2];
            std::snprintf(hd, 72, "#slider %d %% (size %.0f, blade reach %.0f), strong hit x1.5", lvl, double(uSize), double(uReach));
            specs.push_back({hd, Fm::SlabZ, 0, 0, 0, 0, false});
            for (const auto& w : Blades) {
                std::snprintf(names[nn], 48, "%s", w.n);
                specs.push_back({names[nn++], Fm::SlabZ, h, bladeReach(uReach * w.rm), maxC, budget, false});
            }
            for (const auto& k : Others) {
                std::snprintf(names[nn], 48, "%s", k.n);
                specs.push_back({names[nn++], k.bore ? Fm::BoreY : Fm::Bite, limit(uSize * 1.5f, k.most), 0.0f, maxC, budget, k.blunt});
            }
        }
        std::printf("%u surface seeds of %u\n", unsigned(use.size()), unsigned(seeds.size()));
        std::printf("%-44s %-4s %6s %6s | taken p50 p95 max | detach p95 max | parts p50 p95 max | >=3 parts\n", "", "form", "r", "reach");
        for (const Spec& s : specs) {
            if (s.name[0] == '#') { std::printf("--- %s\n", s.name + 1); continue; }
            std::vector<int> t, d, l; int many = 0; unsigned jit = 12345u;
            for (const Key& k : use) {
                float at[3]; { const float* c = L.cells.at(k).c; for (int q = 0; q < 3; ++q) { jit = jit * 1103515245u + 12345u;
                    at[q] = c[q] + (float((jit >> 16) & 1023u) / 1023.0f - 0.5f) * 0.9f * cell; } }
                const Result R = Blow(L, at, s, adj0, 3, 34, 10);
                t.push_back(R.taken); d.push_back(R.detached); l.push_back(R.lost); if (R.lost >= 3) ++many;
            }
            const int pct = int(100.0 * many / double(std::max<std::size_t>(1, use.size())));
            std::printf("%-44s %-4s %6.1f %6.1f | %5d %4d %4d | %5d %4d | %3d %3d %3d | %3d%%\n", s.name,
                        IsSlab(s.form) ? "slab" : IsBore(s.form) ? "bore" : "bite", double(s.size), double(s.reach),
                        Pct(t, .5), Pct(t, .95), Pct(t, 1), Pct(d, .95), Pct(d, 1), Pct(l, .5), Pct(l, .95), Pct(l, 1), pct);
            const std::string nm = s.name;
            if (nm.rfind("control", 0) == 0) { if (pct < 60) { std::printf("FAIL: the control no longer explodes\n"); ++failed; } }
            else if (nm.find("saved panel") != std::string::npos || nm == "greatsword" || nm == "battleaxe") {}
            else if (pct > 20) { std::printf("FAIL: %s takes three parts on %d %% of blows\n", s.name, pct); ++failed; }
        }
    }
    std::printf("\n%s\n", failed ? "FAILED" : "PASSED");
    return failed ? 1 : 0;
}
