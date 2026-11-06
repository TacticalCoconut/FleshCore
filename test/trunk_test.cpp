// THE TRUNK ACROSS A CLEAVE on a stick figure built by hand:
// a wide chest over an abdomen, a head, an
// arm hanging against each side of the chest, a leg under each hip. Links are
// the 26-neighbour grid where the two parts touch (PartsTouch), which is what
// BuildAdjacency's grid pass makes -- so an upper arm lying against the chest
// is joined to it all the way down, and a forearm is never joined to the belly.
//
// The cleave is SelectPlane() with a reach, landed on their right upper arm,
// horizontal through the chest at row 14 -- the tested case,
// where the plane took the chest out to its reach and the upper
// body stayed on them, joined to the hips by the far side.
//
// What is proved:
//   1  the tested case, as it was: the reach-bounded cut leaves the far side
//      standing and the body stays ONE section after SeverPlane();
//   2  through: a cut taking 80% of the trunk's band tears the other 20%,
//      grows the reach to the band plus an arm's thickness, and after
//      SeverPlane() the head and the legs are in different sections -- the left
//      arm, past the old reach and joined to the chest above and below the
//      plane, included;
//   3  a gash changes nothing: no cell appended, the reach kept, still one
//      section -- at 32% of the band, and at 70%: at TE 0.5 a quarter of it may
//      stand, half what a limb keeps;
//   4  only a plane with a reach: a spell's slab (reach 0) and no plane at all
//      (a bite) are left alone, and so is a plane that took no trunk cell;
//   5  cumulative against birth: a gash from the left and then one from the
//      right that would each be a gash alone go through together;
//   6  the plane's part scope bounds the band: a chest-only plane never
//      appends a cell of their belly;
//   7  TE 0 is off; what is appended is alive, trunk, in the band, and new;
//   8  the trunk has to stand on both sides: a dagger between the thighs, where
//      a few cells of belly make a small band all taken, leaves the legs on,
//      and so does a plane through the chest's top row;
//   9  only what stands near the trunk is cut: a limb crossing the plane far
//      off stays in one piece;
//  10  their own cells vote: a robe a fire burned away is no part of how far
//      the blade got;
//  11  Rejoin gives an un-cut body its links back: one section again;
//  12  TakeScraps takes trunk scraps under the floor, never the largest, however
//      much chest a scrap holds, and no scrap without trunk in it.
#include "lattice.h"
#include <cstdio>
#include <cmath>
#include <set>
#include <vector>
using flesh::Key; using flesh::Part; using flesh::Lattice;

static void Block(Lattice& L, Part p, int x0, int x1, int y0, int y1, int z0, int z1)
{
    for (int x = x0; x < x1; ++x) for (int y = y0; y < y1; ++y) for (int z = z0; z < z1; ++z) {
        Key k{ x, y, z };
        if (L.cells.count(k)) continue;
        flesh::Cell C; C.key = k;
        C.c[0] = (x + 0.5f) * L.cell; C.c[1] = (y + 0.5f) * L.cell; C.c[2] = (z + 0.5f) * L.cell;
        C.layers = flesh::kAllLayers; C.gone = 0; C.mine = true; C.isSkin = true;
        C.part = std::uint8_t(p);
        L.cells.emplace(k, std::move(C));
    }
}
static void Grid(Lattice& L)
{
    L.adj.clear();
    for (auto& [k, C] : L.cells)
        for (int dx = -1; dx <= 1; ++dx) for (int dy = -1; dy <= 1; ++dy) for (int dz = -1; dz <= 1; ++dz) {
            if (!dx && !dy && !dz) continue;
            Key n{ k.x + dx, k.y + dy, k.z + dz };
            auto it = L.cells.find(n);
            if (it == L.cells.end()) continue;
            if (!flesh::PartsTouch(Part(C.part), Part(it->second.part))) continue;
            L.adj[k].insert(n);
        }
}
// Cell 4. Chest x 0..10, y 0..4, z 10..18; abdomen under it z 4..10; head
// x 4..6, y 1..3, z 18..21. Right arm off the +x face (x 10..12, y 1..3):
// upper arm z 12..18, forearm 6..12, hand 4..6; left arm the same off the -x
// face (x -2..0). Thighs x 1..3 and 7..9, y 1..3, z -2..4; calves under them.
static Lattice Figure()
{
    Lattice L; L.cell = 4.0f;
    Block(L, Part::Chest,     0, 10, 0, 4, 10, 18);
    Block(L, Part::Abdomen,   0, 10, 0, 4,  4, 10);
    Block(L, Part::Head,      4,  6, 1, 3, 18, 21);
    Block(L, Part::RUpperArm, 10, 12, 1, 3, 12, 18);
    Block(L, Part::RForearm,  10, 12, 1, 3,  6, 12);
    Block(L, Part::RHand,     10, 12, 1, 3,  4,  6);
    Block(L, Part::LUpperArm, -2,  0, 1, 3, 12, 18);
    Block(L, Part::LForearm,  -2,  0, 1, 3,  6, 12);
    Block(L, Part::LHand,     -2,  0, 1, 3,  4,  6);
    Block(L, Part::LThigh,    1, 3, 1, 3, -2, 4);
    Block(L, Part::LCalf,     1, 3, 1, 3, -8, -2);
    Block(L, Part::RThigh,    7, 9, 1, 3, -2, 4);
    Block(L, Part::RCalf,     7, 9, 1, 3, -8, -2);
    Grid(L);
    L.ComputeTearBirth();
    return L;
}
static int Fail(const char* what) { std::printf("FAIL: %s\n", what); return 1; }

// The blade: horizontal, through the centre of row 14 (z 58), landed in their
// right upper arm at (46, 10); half a row thick, so the band is row 14 alone.
static const float kN[3] = { 0.0f, 0.0f, 1.0f };
static const float kRight[3] = { 46.0f, 10.0f, 58.0f };
static const float kLeft[3]  = { -6.0f, 10.0f, 58.0f };
static std::vector<Key> Cleave(const Lattice& L, const float* at, float reach, std::uint32_t parts = 0)
{
    return L.SelectPlane(at, kN, 2.0f, reach, int(L.cells.size()) + 1, flesh::kAllLayers, parts);
}
static int TrunkInBand(const Lattice& L, const std::vector<Key>& sel)
{
    int n = 0;
    for (const Key& k : sel) {
        const auto& C = L.cells.at(k);
        if (k.z == 14 && (C.part == std::uint8_t(Part::Chest) || C.part == std::uint8_t(Part::Abdomen))) ++n;
    }
    return n;
}
// What the wound path does next: the selection goes, SeverPlane() cuts, and
// the sweep asks what is still one thing. True when their head and their legs
// are no longer in the same section.
static bool Apart(Lattice L, const std::vector<Key>& sel, std::size_t* sections = nullptr)
{
    for (const Key& k : sel) L.cells.at(k).gone = flesh::kAllLayers;
    L.SeverPlane();
    const std::vector<flesh::Section> S = flesh::Sections(L, flesh::kAllLayers);
    if (sections) *sections = S.size();
    const std::uint32_t head = 1u << int(Part::Head), legs = 1u << int(Part::LThigh);
    for (const flesh::Section& s : S)
        if ((s.parts & head) && (s.parts & legs)) return false;
    return true;
}
static bool Sane(const Lattice& L, const std::vector<Key>& before, const std::vector<Key>& after, std::uint32_t trunk)
{
    std::set<Key> was(before.begin(), before.end()), seen;
    for (std::size_t i = 0; i < after.size(); ++i) {
        if (!seen.insert(after[i]).second) return false;                   // a duplicate
        if (i < before.size() && !(after[i] == before[i])) return false;     // the prefix is the selection, in order
        const auto& C = L.cells.at(after[i]);
        if (i >= before.size()) {
            if (was.count(after[i])) return false;                         // already going
            if (!C.Alive(flesh::kAllLayers)) return false;                 // a dead cell
            if (!(trunk & (1u << C.part))) return false;                   // not trunk, or out of scope
            if (after[i].z != 14) return false;                            // not in the band
        }
    }
    return true;
}
int main()
{
    const std::uint32_t trunk = (1u << int(Part::Chest)) | (1u << int(Part::Abdomen));
    // 1  THE TESTED CASE, AS IT WAS. Reach 38 takes the chest's row 14 from
    //    x 2 out (32 of 40) and the right upper arm; x 0..1 and the left arm
    //    are past it, and SeverPlane() cuts only within reach + a cell.
    {
        Lattice L = Figure();
        const std::vector<Key> sel = Cleave(L, kRight, 38.0f);
        if (TrunkInBand(L, sel) != 32) { std::printf("trunk in band %d\n", TrunkInBand(L, sel)); return Fail("field: reach 38 should take 32 of the 40 chest cells in row 14"); }
        if (Apart(L, sel)) return Fail("field: without the rule the far side holds them together (this is the bug)");
    }
    // 2  THROUGH. Same blow: 8 of 40 stand (20%, at most 25% may), so the 8
    //    tear, and the reach grows to the far side of the band and an arm past it.
    {
        Lattice L = Figure();
        std::vector<Key> sel = Cleave(L, kRight, 38.0f);
        const std::vector<Key> before = sel;
        const std::size_t torn = L.TearTrunkAtPlane(sel, 0.5f, nullptr);
        if (torn != 8) { std::printf("torn %zu\n", torn); return Fail("through: the 8 chest cells left standing in the band should tear"); }
        if (!Sane(L, before, sel, trunk)) return Fail("through: appended cells are not sane");
        std::size_t n = 0;
        if (!Apart(L, sel, &n)) return Fail("through: their head and their legs should be in different sections");
        // the left arm's row 14 is cut on both faces -- a four-cell sliver --
        // and nothing else is in pieces: lower body, upper body, sliver
        if (n != 3) { std::printf("sections %zu\n", n); return Fail("through: lower body, upper body and the left arm's sliver"); }
        const float want = std::sqrt(44.0f * 44.0f + 8.0f * 8.0f) + 16.0f;   // the farthest band cell is (2, 2)
        if (std::fabs(L.lastPlaneReach - want) > 0.01f) { std::printf("reach %.3f want %.3f\n", double(L.lastPlaneReach), double(want)); return Fail("through: the reach should be the band plus an arm's thickness"); }
    }
    // 3  A GASH. Reach 20 takes 13 of the 40 (32%): 27 stand, over half.
    {
        Lattice L = Figure();
        std::vector<Key> sel = Cleave(L, kRight, 20.0f);
        if (TrunkInBand(L, sel) != 13) { std::printf("trunk in band %d\n", TrunkInBand(L, sel)); return Fail("gash: reach 20 should take 13"); }
        const std::vector<Key> before = sel;
        if (L.TearTrunkAtPlane(sel, 0.5f, nullptr) != 0 || sel != before) return Fail("gash: nothing may be appended");
        if (L.lastPlaneReach != 20.0f) return Fail("gash: the reach must stand");
        if (Apart(L, sel)) return Fail("gash: they stay one body");
        // ...and 28 of 40: a cut past the spine, 30% standing, is no more through
        Lattice M = Figure();
        std::vector<Key> deep = Cleave(M, kRight, 34.0f);
        if (TrunkInBand(M, deep) != 28) return Fail("deep gash: reach 34 should take 28");
        const std::vector<Key> d0 = deep;
        if (M.TearTrunkAtPlane(deep, 0.5f, nullptr) != 0 || deep != d0) return Fail("deep gash: a quarter may stand, not 30%");
    }
    // 4  ONLY A PLANE WITH A REACH, AND ONLY ONE THAT TOOK TRUNK.
    {
        Lattice L = Figure();
        std::vector<Key> sel = Cleave(L, kRight, 0.0f);                  // a spell's slab: the whole body
        const std::vector<Key> slab = sel;
        if (L.TearTrunkAtPlane(sel, 0.5f, nullptr) != 0 || sel != slab) return Fail("a reach-0 slab is left alone");
        // a bite right after a cleave does not inherit its plane: it takes
        // all of row 14, which against the cleave's band would be THROUGH
        Lattice M = Figure();
        Cleave(M, kRight, 34.0f);
        const float mid[3] = { 20.0f, 8.0f, 58.0f };
        std::vector<Key> bite = M.Select(Lattice::Form::Bite, mid, 30.0f, 1, 1000, flesh::kAllLayers, 0);
        const std::vector<Key> b0 = bite;
        if (TrunkInBand(M, bite) != 40) { std::printf("bite in band %d\n", TrunkInBand(M, bite)); return Fail("the bite should take all of row 14"); }
        if (M.TearTrunkAtPlane(bite, 0.5f, nullptr) != 0 || bite != b0) return Fail("no plane, no trunk rule");
        Lattice N = Figure();                                             // the right forearm alone, nowhere near the trunk
        const float hand[3] = { 46.0f, 10.0f, 30.0f };
        std::vector<Key> arm = N.SelectPlane(hand, kN, 2.0f, 6.0f, 1000, flesh::kAllLayers, 0);
        const std::vector<Key> a0 = arm;
        if (arm.empty() || TrunkInBand(N, arm) != 0) return Fail("the forearm cut should take forearm only");
        if (N.TearTrunkAtPlane(arm, 0.5f, nullptr) != 0 || arm != a0 || N.lastPlaneReach != 6.0f)
            return Fail("a plane that took no trunk cell is left alone");
    }
    // 5  CUMULATIVE AGAINST BIRTH. From the left, reach 20: 13 of 40, a gash.
    //    From the right, reach 24: 17 of 40, a gash alone. Together 30 gone,
    //    10 stand (25%): through, and only the 10 live ones are appended.
    {
        Lattice A = Figure();
        std::vector<Key> right = Cleave(A, kRight, 24.0f);
        if (TrunkInBand(A, right) != 17) { std::printf("trunk in band %d\n", TrunkInBand(A, right)); return Fail("cumulative: reach 24 should take 17"); }
        const std::vector<Key> r0 = right;
        if (A.TearTrunkAtPlane(right, 0.5f, nullptr) != 0 || right != r0) return Fail("cumulative: the right blow alone is a gash");
        Lattice L = Figure();
        const std::vector<Key> left = Cleave(L, kLeft, 20.0f);
        if (TrunkInBand(L, left) != 13) { std::printf("trunk in band %d\n", TrunkInBand(L, left)); return Fail("cumulative: the left blow should take 13"); }
        for (const Key& k : left) L.cells.at(k).gone = flesh::kAllLayers;  // the first blow, landed
        std::vector<Key> sel = Cleave(L, kRight, 24.0f);
        const std::vector<Key> before = sel;
        const std::size_t torn = L.TearTrunkAtPlane(sel, 0.5f, nullptr);
        if (torn != 10) { std::printf("torn %zu\n", torn); return Fail("cumulative: the 10 still standing should tear"); }
        if (!Sane(L, before, sel, trunk)) return Fail("cumulative: appended cells are not sane (a dead one?)");
        if (!Apart(L, sel)) return Fail("cumulative: the second blow should part them");
    }
    // 6  THE PLANE'S SCOPE. A chest-only plane tilted across the seam, so its
    //    band holds chest and belly and chest stands on both sides of it,
    //    judges the chest alone and never appends a cell of their belly.
    {
        Lattice L = Figure();
        const float tilt[3] = { 0.5f, 0.0f, 0.5f };
        const float seam[3] = { 24.0f, 8.0f, 44.0f };
        std::vector<Key> sel = L.SelectPlane(seam, tilt, 3.0f, 26.0f, 1000, flesh::kAllLayers, 1u << int(Part::Chest));
        for (const Key& k : sel) if (L.cells.at(k).part != std::uint8_t(Part::Chest)) return Fail("scope: SelectPlane took a cell out of scope");
        const std::vector<Key> before = sel;
        L.TearTrunkAtPlane(sel, 0.5f, nullptr);
        for (std::size_t i = before.size(); i < sel.size(); ++i)
            if (L.cells.at(sel[i]).part != std::uint8_t(Part::Chest)) return Fail("scope: appended a cell of their belly");
        if (sel.size() == before.size()) return Fail("scope: most of the chest's band was taken and the rest should tear");
    }
    // 7  OFF.
    {
        Lattice L = Figure();
        std::vector<Key> sel = Cleave(L, kRight, 38.0f);
        const std::vector<Key> before = sel;
        if (L.TearTrunkAtPlane(sel, 0.0f, nullptr) != 0 || sel != before) return Fail("TE 0 must tear nothing");
        if (L.lastPlaneReach != 38.0f) return Fail("TE 0 must keep the reach");
    }
    // 8  THE TRUNK ON BOTH SIDES. A little belly hangs between the thighs,
    //    rows 2 and 3. A dagger at row 3 takes its whole band: 100% of a slice,
    //    and through nothing -- the eight cells of row 2 are all that stand
    //    below it, against 560 above.
    {
        Lattice L = Figure();
        Block(L, Part::Abdomen, 3, 7, 1, 3, 2, 4);
        Grid(L);
        L.ComputeTearBirth();
        const float crotch[3] = { 20.0f, 8.0f, 14.0f };
        std::vector<Key> sel = L.SelectPlane(crotch, kN, 2.0f, 8.0f, 1000, flesh::kAllLayers, 0);
        if (TrunkInBand(L, sel) != 0 || sel.size() != 8) { std::printf("sel %zu\n", sel.size()); return Fail("crotch: the dagger should take the band's eight cells of belly and nothing else"); }
        const std::vector<Key> before = sel;
        if (L.TearTrunkAtPlane(sel, 0.5f, nullptr) != 0 || sel != before) return Fail("crotch: nothing may tear");
        if (L.lastPlaneReach != 8.0f) return Fail("crotch: the reach must stand");
        const std::uint32_t legs = (1u << int(Part::LThigh)) | (1u << int(Part::RThigh));
        for (const Key& k : sel) L.cells.at(k).gone = flesh::kAllLayers;
        L.SeverPlane();
        const std::vector<flesh::Section> S = flesh::Sections(L, flesh::kAllLayers);
        for (std::size_t i = 1; i < S.size(); ++i)
            if (S[i].parts & legs) return Fail("crotch: a dagger between the thighs must not take a leg off");
        // the chest's top row: everything of theirs that is trunk is below it
        Lattice M = Figure();
        const float top[3] = { 46.0f, 10.0f, 70.0f };
        std::vector<Key> high = M.SelectPlane(top, kN, 2.0f, 38.0f, 1000, flesh::kAllLayers, 0);
        const std::vector<Key> h0 = high;
        if (M.TearTrunkAtPlane(high, 0.5f, nullptr) != 0 || high != h0) return Fail("top row: no trunk above it, nothing to part");
    }
    // 9  ONLY NEAR THE TRUNK. A hand held out far to their left crosses the
    //    plane; the cut went through their chest, and it still stays whole.
    {
        Lattice L = Figure();
        Block(L, Part::LHand, -14, -12, 1, 3, 12, 17);
        Grid(L);
        L.ComputeTearBirth();
        std::vector<Key> sel = Cleave(L, kRight, 38.0f);
        if (L.TearTrunkAtPlane(sel, 0.5f, nullptr) != 8) return Fail("far hand: the cut should still go through");
        for (const Key& k : sel) L.cells.at(k).gone = flesh::kAllLayers;
        L.SeverPlane();
        const std::vector<flesh::Section> S = flesh::Sections(L, flesh::kAllLayers);
        int holding = 0;
        for (const flesh::Section& s : S) {
            bool far = false;
            for (const Key& k : s.cells) if (k.x <= -12) far = true;
            if (far) ++holding;
        }
        if (holding != 1) { std::printf("far hand in %d sections\n", holding); return Fail("far hand: a limb far past the trunk must not be cut"); }
    }
    // 10 THEIR OWN CELLS VOTE. Forty cells of robe behind the chest in row 14,
    //    burned away: reach 34 took 28 of their 40 own cells, 30% standing, and
    //    counting the dead robe as gone would call that 15% of 80, through.
    {
        Lattice L = Figure();
        Block(L, Part::Chest, 0, 10, 4, 8, 14, 15);
        for (auto& [k, C] : L.cells)
            if (k.y >= 4) { C.mine = false; C.isSkin = false; C.gone = flesh::kAllLayers; }
        Grid(L);
        L.ComputeTearBirth();
        std::vector<Key> sel = Cleave(L, kRight, 34.0f);
        const std::vector<Key> before = sel;
        if (L.TearTrunkAtPlane(sel, 0.5f, nullptr) != 0 || sel != before) return Fail("robe: a burned robe must not vote");
    }
    // 11 REJOIN. A through, then what a warm Restore does: every cell alive
    //    again -- and without Rejoin, still two bodies.
    {
        Lattice L = Figure();
        std::vector<Key> sel = Cleave(L, kRight, 38.0f);
        L.TearTrunkAtPlane(sel, 0.5f, nullptr);
        for (const Key& k : sel) L.cells.at(k).gone = flesh::kAllLayers;
        if (L.SeverPlane() == 0) return Fail("rejoin: the cut should sever links");
        if (L.severed.empty()) return Fail("rejoin: the links should be recorded");
        for (auto& [k, C] : L.cells) C.gone = 0;
        if (flesh::Sections(L, flesh::kAllLayers).size() < 2) return Fail("rejoin control: alive is not joined, this should still be apart");
        L.Rejoin();
        if (!L.severed.empty()) return Fail("rejoin: the record should be spent");
        if (flesh::Sections(L, flesh::kAllLayers).size() != 1) return Fail("rejoin: an un-cut body is one section");
        const Lattice M = Figure();
        if (M.adj != L.adj) return Fail("rejoin: the links should be exactly the ones the body was built with");
    }
    // 12 SCRAPS. Everything from the chest up is gone but for a two-cell chip
    //    of chest on its own. Sections() ranks the chip first, the way a sweep
    //    would keep it; it goes, and the hips and legs stay, with the forearms
    //    the cut already left apart, which are over the floor, and a two-cell
    //    hand off on its own, which holds no trunk. A section at the floor stays
    //    too.
    {
        Lattice L = Figure();
        Block(L, Part::LHand, -12, -10, 1, 2, 2, 3);
        Grid(L);
        for (auto& [k, C] : L.cells)
            if (k.z >= 10) C.gone = flesh::kAllLayers;
        const Key a{ 0, 0, 16 }, b{ 1, 0, 16 };
        L.cells.at(a).gone = 0; L.cells.at(b).gone = 0;                    // a two-cell chip of chest on its own
        const std::vector<flesh::Section> S = flesh::Sections(L, flesh::kAllLayers);
        if (S.size() != 5 || S[0].cells.size() != 2) { std::printf("sections %zu first %zu\n", S.size(), S.empty() ? 0 : S[0].cells.size()); return Fail("scraps: the chip should rank first, the way the sweep would keep it"); }
        Lattice K = L;
        std::map<Key, std::uint32_t> ledger;
        if (flesh::TakeScraps(K, 7, ledger) != 2) return Fail("scraps: the two-cell chip should go");
        if (ledger.size() != 2 || !ledger.count(a) || !ledger.count(b)) return Fail("scraps: the ledger should hold exactly the chip");
        const std::vector<flesh::Section> T = flesh::Sections(K, flesh::kAllLayers);
        if (T.size() != 4 || T[0].cells.size() < 100) return Fail("scraps: the body stays, the forearms over the floor, and the hand with no trunk in it");
        Lattice F = L;
        std::map<Key, std::uint32_t> none;
        if (flesh::TakeScraps(F, 2, none) != 0 || !none.empty()) return Fail("scraps: a section at the floor is not a scrap");
    }
    std::printf("trunk OK: field case, through, gash, reach-0/no-plane/no-trunk, cumulative, scope, off, both sides, near the trunk, own cells, rejoin, scraps\n");
    return 0;
}
