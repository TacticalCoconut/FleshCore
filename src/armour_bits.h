// armour_bits.h -- THE ARMOUR, AS ARITHMETIC. Pure: no engine call,
// compiled unchanged into the plugin. Mul() and Apply() have no callers in this release.
//
// Design note: areas covered by metallic or hard armour resist cutting and piercing
// but are weak to blunt damage. Soft armour,
// however, resists blunt and magic damage, but is weak against piercing
// and cutting.
//
// THREE QUESTIONS, ONE PLACE EACH:
//   * What is a worn item made of?            Classify() -- hard, soft, clothing, none
//   * Are they covered there?                 Probe()    -- the cells near the wound
//   * What does that do to the wound?         Mul() and Apply()
//
// AREAS, NOT SLOTS. A cuirass is not "the chest": it is the geometry it has.
// Every triangle of every worn shape is already in their lattice (lattice.h), so
// "is this spot protected" is asked of the cells AT the spot -- a cut-away
// cuirass protects what it covers and nothing else, a pauldron on an extra
// slot protects the shoulder, and a hole a wound has cut in a breastplate is a
// hole: a cell whose outer layer is gone covers nothing.
#pragma once
#include <cmath>
#include <cstdint>
#include <map>
#include <string>
#include <vector>
#include "facts.h"
#include "lattice.h"

namespace armour {

enum Cls : std::uint8_t { kNone = 0, kCloth = 1, kSoft = 2, kHard = 3, kClsCount = 4 };
enum Fam : std::uint8_t { kFamNone = 0, kSlash = 1, kPierce = 2, kBlunt = 3, kMagic = 4, kFamCount = 5 };

inline const char* ClsName(int c)
{
    switch (c) { case kCloth: return "clothing"; case kSoft: return "soft"; case kHard: return "hard"; default: return "none"; }
}
// The store's spelling (the HQ's keys and the AM rows): hard soft cloth.
inline const char* ClsKey(int c)
{
    switch (c) { case kCloth: return "cloth"; case kSoft: return "soft"; case kHard: return "hard"; default: return "none"; }
}
inline const char* FamName(int f)
{
    switch (f) { case kSlash: return "slash"; case kPierce: return "pierce"; case kBlunt: return "blunt"; case kMagic: return "magic"; default: return "none"; }
}
inline bool ClsFromKey(const std::string& s, std::uint8_t& out)
{
    if (s == "hard") { out = kHard; return true; }
    if (s == "soft") { out = kSoft; return true; }
    if (s == "cloth" || s == "clothing") { out = kCloth; return true; }
    if (s == "none") { out = kNone; return true; }
    return false;
}

// THE BLOW'S FAMILY, from the words the engine already uses for it (ReadBlow,
// MagicTyped). A staff's hit is its spell. A werewolf's is its claws. An
// untyped blow -- a health drop nothing accounts for -- is no family, and no
// armour answers it.
inline std::uint8_t FamOf(const std::string& type, const std::string& weapon)
{
    if (weapon == "staff") return kMagic;
    if (type == "slash" || type == "werewolf") return kSlash;
    if (type == "pierce") return kPierce;
    if (type == "blunt" || type == "unarmed") return kBlunt;
    if (type == "fire" || type == "frost" || type == "shock" || type == "shout" || type == "drain") return kMagic;
    return kFamNone;
}

// THE GRID: what each class does to each family, a multiplier on the wound
// (and, for a blow, on the damage the thresholds read). 1 is bare skin.
struct Grid {
    bool  on = true;
    float reach = 8.0f;                 // units from the wound that count as "there"
    float mul[kClsCount][kFamCount];
    Grid()
    {
        for (int c = 0; c < kClsCount; ++c) for (int f = 0; f < kFamCount; ++f) mul[c][f] = 1.0f;
        // The rule, as shipped. Hard: resists the edge and the point,
        // weak to the hammer, indifferent to magic (a default, not a decision).
        mul[kHard][kSlash] = 0.5f; mul[kHard][kPierce] = 0.5f; mul[kHard][kBlunt] = 1.5f; mul[kHard][kMagic] = 1.0f;
        // Soft: resists the hammer and the spell, weak to the edge and the point.
        mul[kSoft][kSlash] = 1.5f; mul[kSoft][kPierce] = 1.5f; mul[kSoft][kBlunt] = 0.5f; mul[kSoft][kMagic] = 0.5f;
        // Clothing is not armour: bare skin, until the page says otherwise.
    }
};
inline float ClampMul(float m) { if (!(m >= 0.0f)) return 1.0f; return m > 4.0f ? 4.0f : m; }
inline float ClampReach(float r) { if (!(r >= 1.0f)) return 1.0f; return r > 40.0f ? 40.0f : r; }
inline float Mul(const Grid& g, int cls, int fam)
{
    if (!g.on || cls <= kNone || cls >= kClsCount || fam <= kFamNone || fam >= kFamCount) return 1.0f;
    return ClampMul(g.mul[cls][fam]);
}
// Below this a wound is not made at all: the armour turned it.
inline constexpr float kStops = 0.01f;

// ---- WHAT A WORN ITEM IS MADE OF ---------------------------------------------
//
// THE LIGHT-ARMOUR MATERIALS THAT ARE HARD. Every name below was read out of the
// vanilla masters (Skyrim.esm, Update.esm, Dawnguard.esm, Dragonborn.esm);
// WHICH of them is hard is a design choice --
// metal, glass, and the shell materials (chitin, stalhrim, bonemold, scales,
// dragon scale). Heavy armour is hard whatever it is made of; a light piece is
// soft unless it carries one of these. Leather, hide, fur, studded, the Imperial
// light set, the guild leathers, the Morag Tong, the hunter's and the vampire's
// are soft by that rule. The config's AM rows override any of it.
inline bool IsHardMaterial(const std::string& k)
{
    static const char* kHardKw[] = {
        "armormaterialelven", "armormaterialelvengilded", "armormaterialglass",
        "armormaterialscaled", "armormaterialdragonscale", "armormaterialdragonplate",
        "armormaterialiron", "armormaterialironbanded", "armormaterialsteel",
        "armormaterialsteelplate", "armormaterialdwarven", "armormaterialorcish",
        "armormaterialebony", "armormaterialdaedric", "armormaterialimperialheavy",
        "armormaterialblades", "armormaterialfalmer",
        "dlc1armormaterialfalmerhardened",
        "dlc2armormaterialchitinlight", "dlc2armormaterialchitinheavy",
        "dlc2armormaterialstalhrimlight", "dlc2armormaterialstalhrimheavy",
        "dlc2armormaterialbonemoldlight", "dlc2armormaterialbonemoldheavy",
        "dlc2armormaterialnordiclight", "dlc2armormaterialnordicheavy",
        "ccbgs_armormaterialorcishlight",
        nullptr };
    for (int i = 0; kHardKw[i]; ++i) if (k == kHardKw[i]) return true;
    return false;
}
inline bool IsJewellery(const std::string& k)
{
    return k == "armorjewelry" || k == "clothingring" || k == "clothingnecklace" ||
           k == "clothingcirclet" || k == "jewelryexpensive" || k == "vendoritemjewelry";
}
// The slots that carry nothing that protects: hair, long hair, amulet, ring, ears.
inline constexpr std::uint32_t kNonArmourSlots =
    fact::kSlot_Hair | fact::kSlot_LongHair | fact::kSlot_Amulet | fact::kSlot_Ring | fact::kSlot_Ears;

struct ItemFacts {
    std::uint32_t type = 0;             // fact::kArmorType_*
    std::uint32_t slots = 0;            // the BOD2 slot mask
    std::vector<std::string> kw;        // keyword editor ids, lowercase
    bool ours = false;                  // a record of FleshCore.esp's own (the interior, the head)
};
// `overrides`: lowercase keyword -> class, from the config's AM rows. The
// first keyword of the item's that names one decides, before any rule here.
inline std::uint8_t Classify(const ItemFacts& it, const std::map<std::string, std::uint8_t>& overrides, std::string& why)
{
    if (it.ours) { why = "FleshCore's own"; return kNone; }
    for (const std::string& k : it.kw) {
        auto o = overrides.find(k);
        if (o != overrides.end()) { why = "the config's AM row for " + k; return o->second; }
    }
    for (const std::string& k : it.kw) if (IsJewellery(k)) { why = "jewellery (" + k + ")"; return kNone; }
    if ((it.slots & ~kNonArmourSlots) == 0u) { why = "hair or jewellery slots only"; return kNone; }
    if (it.type == fact::kArmorType_Heavy) { why = "heavy armour"; return kHard; }
    // A RACE SKIN IS NOT CLOTHING. Skyrim.esm's SkinNaked (0x000D64) is armour
    // type Clothing on slots 30/32/33/37 with no keyword at all (as
    // is every Skin* record in the master), and it is the item
    // behind every shape of their own body mesh -- so a non-skin shape in it (a
    // body replacer's extra) would read as clothing over their belly. Wearable
    // clothing carries its keywords (ArmorClothing, Clothing*, the vendor's);
    // a keywordless Clothing item is a skin or an addon, and covers nothing.
    if (it.type == fact::kArmorType_Clothing && it.kw.empty()) { why = "Clothing with no keyword -- a race skin, not clothing"; return kNone; }
    if (it.type == fact::kArmorType_Clothing) { why = "clothing"; return kCloth; }
    if (it.type == fact::kArmorType_Light) {
        for (const std::string& k : it.kw) if (IsHardMaterial(k)) { why = "light armour of " + k; return kHard; }
        why = "light armour";
        return kSoft;
    }
    why = "armour type " + std::to_string(it.type) + " is none of the three";
    return kNone;
}

// ---- ARE THEY COVERED THERE ----------------------------------------------------
//
// The hardest class of any worn shape in a cell within `reach` of p (bind
// space) whose outer layer is still there. A cell is "there" by its centroid.
// Ties go to the nearer cell. `armourOf` is the class of each lattice shape
// (kNone for their skin, their fill, and anything not worn as armour).
// `outer` counts the cells within reach whose outer layer is there at all --
// theirs or worn. Zero means p is not at their surface (a wound anchored at the
// middle of the body), and the question has to be asked where the wound will open.
struct Hit {
    std::uint8_t  cls = kNone;
    std::uint32_t shape = 0;
    float         dist = 0.0f;
    int           cellsLooked = 0;
    int           outer = 0;
    bool          breached = false;
    int           breachedCells = 0;
    int           exposedSkin = 0;
    int           exposedFlesh = 0;
    int           exposedBone = 0;
};
inline Hit Probe(const std::map<flesh::Key, flesh::Cell>& cells, float cell,
                 const std::vector<std::uint8_t>& armourOf, const float p[3], float reach)
{
    Hit h;
    if (!(cell > 0.0f) || !(reach > 0.0f)) return h;
    // A cell more than floor(reach/cell)+1 keys away cannot have its centroid
    // within reach: its box is at least that many cells minus one from p's.
    const int n = int(std::floor(reach / cell)) + 1;
    const std::int32_t bx = std::int32_t(std::floor(p[0] / cell));
    const std::int32_t by = std::int32_t(std::floor(p[1] / cell));
    const std::int32_t bz = std::int32_t(std::floor(p[2] / cell));
    const float r2 = reach * reach;
    float best = 1e30f;
    float bestBreach = 1e30f;
    float bestBare = 1e30f;
    for (int dx = -n; dx <= n; ++dx) for (int dy = -n; dy <= n; ++dy) for (int dz = -n; dz <= n; ++dz) {
        auto it = cells.find(flesh::Key{ bx + dx, by + dy, bz + dz });
        if (it == cells.end()) continue;
        ++h.cellsLooked;
        const flesh::Cell& c = it->second;
        const float vx = c.c[0] - p[0], vy = c.c[1] - p[1], vz = c.c[2] - p[2];
        const float d2 = vx * vx + vy * vy + vz * vz;
        if (d2 > r2) continue;
        if (c.gone & flesh::kArmourBit) {
            ++h.breachedCells;
            if (d2 < bestBreach) bestBreach = d2;
        }
        const std::uint32_t rem = c.layers & ~c.gone;
        if (!(rem & (flesh::kArmourBit | 1u | 4u | 8u))) continue;
        ++h.outer;

        // Check whether this cell still has intact worn armour (layer 4 / 0x10u).
        bool cellArmoured = false;
        if (rem & flesh::kArmourBit) {
            for (std::uint32_t s : c.shapes) {
                if (s >= armourOf.size()) continue;
                const std::uint8_t a = armourOf[s];
                if (a == kNone) continue;
                cellArmoured = true;
                if (a > h.cls || (a == h.cls && d2 < best)) { h.cls = a; h.shape = s; best = d2; }
            }
        }
        if (!cellArmoured) {
            if (d2 < bestBare) bestBare = d2;
            if (rem & 1u)      ++h.exposedSkin;
            else if (rem & 4u) ++h.exposedFlesh;
            else if (rem & 8u) ++h.exposedBone;
        }
    }
    // If armour was explicitly peeled off at the impact site (or the nearest
    // surface cell at the impact site is unarmoured and closer than any fringe
    // armour cell), the strike lands on the exposed tissue in the breach rather
    // than being deflected by intact armour beside it.
    if (bestBreach < 1e29f && bestBreach <= best + cell * cell * 0.65f) {
        h.cls = kNone;
        h.shape = 0;
        h.breached = true;
        best = bestBreach;
    } else if (bestBare < 1e29f && bestBare + cell * cell * 0.25f < best) {
        h.cls = kNone;
        h.shape = 0;
        best = bestBare;
    }
    h.dist = (best < 1e29f) ? std::sqrt(best) : 0.0f;
    return h;
}

// THE NEAREST PLACE THEIR OUTER/EXPOSED LAYER IS STILL THERE, from p: the centroid
// of the nearest cell that still has remaining armour, skin, flesh, or bone.
inline bool NearestOuter(const std::map<flesh::Key, flesh::Cell>& cells, const float p[3], float out[3])
{
    bool found = false; float best = 0.0f;
    for (const auto& kv : cells) {
        const flesh::Cell& c = kv.second;
        if (!((c.layers & ~c.gone) & (flesh::kArmourBit | 1u | 4u | 8u))) continue;
        const float vx = c.c[0] - p[0], vy = c.c[1] - p[1], vz = c.c[2] - p[2];
        const float d2 = vx * vx + vy * vy + vz * vz;
        if (!found || d2 < best) { found = true; best = d2; out[0] = c.c[0]; out[1] = c.c[1]; out[2] = c.c[2]; }
    }
    return found;
}

// ---- WHAT IT DOES TO THE WOUND -----------------------------------------------
//
// A blow's wound the way the per-actor scalar already scales one (WoundActor):
// its size, how many pieces it may make, and -- at half or less, or double or
// more -- one layer shallower or deeper. A drain's bite is a count of cells,
// so that count is what moves. The size is capped at forty, the `per` cap.
inline void Apply(float f, bool drainBite, float& size, int& budget, int& depth, int& maxCells)
{
    if (drainBite) {
        const long m = std::lround(double(maxCells) * double(f));
        maxCells = m < 0 ? 0 : int(m);
        return;
    }
    const float origSize = size;
    size *= f;
    if (f >= kStops && origSize >= 6.5f && size < 6.5f) size = 6.5f;
    if (size > 40.0f) size = 40.0f;
    if (budget > 0) { const long b = std::lround(double(budget) * double(f)); budget = b < 1 ? 1 : int(b); }
    if (depth >= 1 && depth <= 3) {
        if (f >= 2.0f) depth = depth + 1 > 3 ? 3 : depth + 1;
        else if (f <= 0.5f) depth = depth - 1 < 1 ? 1 : depth - 1;
    }
}

}  // namespace armour
