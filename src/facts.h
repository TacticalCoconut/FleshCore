// facts.h -- what is TRUE about Skyrim Special Edition 1.6.1170.
//
// This file contains no design. It is a record of measurements: struct
// offsets, global addresses and format constants that belong to the GAME, not
// to this mod. Every one carries the source it came from.
// They are stated here so the engine code below can be read as
// logic rather than as a pile of magic numbers.
//
// TWO CLASSES OF FACT, ESTABLISHED TWO DIFFERENT WAYS
//
// A) FUNCTION AND GLOBAL RVAs -- resolved offline out of the Address Library's
//    1.6.1170 database (428,461 entries) read as
//    CommonLibSSE-NG's src/REL/IDDB.cpp reads it, then CROSS-CHECKED against
//    SKSE64 v2.2.6, whose RelocAddrs target this same runtime. Both
//    sources agree to the byte, and every address reverse-maps to exactly
//    one address-library id -- i.e. it is a real symbol start, not an interior
//    offset that happens to look plausible.
//
//    The Steam SkyrimSE.exe is SteamStub-packed, so its .text is
//    encrypted at rest and none of this can be confirmed by static
//    disassembly. That is why two independent naming sources
//    were required.
//
// B) STRUCT OFFSETS -- read out of the CommonLibSSE-NG headers, SE "flat"
//    layout, never the VR variants. Where a layout could be derived two ways
//    it was, and the two derivations are shown agreeing inline. An offset
//    with no arithmetic check next to it is one the header states outright.
#pragma once
#include <cstdint>
#include <cstddef>

namespace fact {

// ============================================================== (A) ADDRESSES

// ScriptEventSourceHolder::GetSingleton()
//   addrlib AE id 14298            -> 0x001D5230
//   skse64 v2.2.6 GameEvents.cpp    RelocAddr(0x001D5230)
constexpr std::uint32_t kGetEventSourceHolder = 0x001D5230;

// BSTEventSource<T>::AddEventSink(Sink*)
//   skse64 v2.2.6 GameEvents.h     DEFINE_MEMBER_FN(..., 0x005DC8C0)
//   addrlib reverse-lookup            0x005DC8C0 -> exactly one id (35182)
//   The engine emits an identical copy per template instantiation (skse64
//   says so in its own comment), so one generic copy services any dispatcher.
constexpr std::uint32_t kAddEventSink = 0x005DC8C0;

// TESForm::GetAllForms() -- BSTHashMap<FormID, TESForm*>**
//   clib RE/T/TESForm.h GetAllForms(): RELOCATION_ID(514351, 400507)
//   addrlib AE id 400507           -> 0x020FBB88
//   The static AT this RVA IS the map pointer. It is dereferenced ONCE.
//   (Dereferencing twice lands in the map's zero padding and silently reads
//   nothing.)
constexpr std::uint32_t kAllFormsGlobal = 0x020FBB88;

// ID3D11Device** -- a global pointer straight at the live device.
//   clib src/RE/R/Renderer.cpp Renderer::GetDevice():
//     REL::Relocation<ID3D11Device**>{ RELOCATION_ID(524729, 411348) }
//   addrlib AE id 411348           -> 0x03286A10
//   Corroborated by its neighbour: id 411347 (RendererData**) -> 0x03286A08,
//   exactly eight bytes earlier, i.e. consecutive pointers in one table.
constexpr std::uint32_t kD3D11DeviceGlobal = 0x03286A10;

// ========================================================== (B) OBJECT MODEL

// TESForm (clib RE/T/TESForm.h; sizeof 0x20)
constexpr std::uintptr_t kForm_formID   = 0x14;
constexpr std::uintptr_t kForm_formType = 0x1A;
constexpr std::uint8_t   kFormType_ACTI = 24;   // FormType::Activator
constexpr std::uint8_t   kFormType_QUST = 77;   // FormType::Quest
// FormType::ActorCharacter -- an ACHR, i.e. a placed actor. From the same
// clib FormTypes.h enum whose Activator (24) and Quest (77) are the two
// values already proven by every lookup this plugin has ever made.
constexpr std::uint8_t   kFormType_ACHR = 62;

// TESObjectREFR (sizeof 0x98 SE) -> LOADED_REF_DATA -> NiAVObject
constexpr std::uintptr_t kREFR_loadedData = 0x68;
constexpr std::uintptr_t kLoaded_data3D   = 0x68;

// BSTEventSource<T> (sizeof 0x58); BSTArray<T> (sizeof 0x18).
//   BSTArray derives Allocator then BSTArrayBase, so in declaration order
//   _data 0x00, _capacity 0x08, _size 0x10 -- identical to skse64's tArray
//   (entries 00 / capacity 08 / count 10). Both sources give this layout.
constexpr std::uintptr_t kSourceStride    = 0x58;
constexpr std::uintptr_t kArray_data      = 0x00;
constexpr std::uintptr_t kArray_capacity  = 0x08;
constexpr std::uintptr_t kArray_size      = 0x10;

// ScriptEventSourceHolder's BSTEventSource bases.
//
//   The holder derives from one BSTEventSource per event type and from
//   nothing else, so base N sits at N * 0x58 and the first at zero. The clib
//   header's inheritance list, read in order, gives N:
//
//     ... 17 TESHitEvent ... 21 TESMagicEffectApplyEvent ...
//     ... 24 TESObjectLoadedEvent ...
//
//   ARITHMETIC CHECK, and it is a real one because two of these three were
//   already proven in play before the third was added:
//     17 * 0x58 == 0x5D8   -- Hit, proven in use
//     21 * 0x58 == 0x738   -- MagicEffectApply, proven in use
//     24 * 0x58 == 0x840   -- ObjectLoaded, added third
//   The two standing offsets reproduce exactly from the same list and the
//   same stride, so the list is the right list and 0x840 follows from it.
constexpr std::uintptr_t kHolder_MagicEffectApply = 0x738;
constexpr std::uintptr_t kHolder_Hit              = 0x5D8;
constexpr std::uintptr_t kHolder_ObjectLoaded     = 0x840;
// TESEquipEvent: index 13 of the same clib list (ScriptEventSourceHolder.h
// "public BSTEventSource<TESEquipEvent>, // 0478"), 13 * 0x58 == 0x478, the same
// arithmetic the three proven offsets above reproduce from. skse64 names no
// TESEquipEvent at all (its EventDispatcherList marks the slot `unk478`), so this
// rests on the clib list alone -- accepted because the registration itself
// cannot fault (every 0x58-aligned slot inside the holder is a real source) and
// the handler validates the actor it is handed before believing it.
constexpr std::uintptr_t kHolder_Equip            = 0x478;

// TESObjectLoadedEvent (clib RE/T/TESObjectLoadedEvent.h, sizeof 0x8):
//   FormID formID 0x00, bool loaded 0x04, then two bytes of padding.
// It carries an ID, not a pointer: the reference has to be looked up.
constexpr std::uintptr_t kObjLoaded_formID = 0x00;
constexpr std::uintptr_t kObjLoaded_loaded = 0x04;

// TESEquipEvent (clib RE/T/TESEquipEvent.h, sizeof 0x18):
//   NiPointer<TESObjectREFR> actor 0x00, FormID baseObject 0x08,
//   FormID originalRefr 0x0C, uint16 uniqueID 0x10, bool equipped 0x12.
// Only the actor pointer is used, and only after it reads as a placed actor.
constexpr std::uintptr_t kEquip_actor      = 0x00;
constexpr std::uintptr_t kEquip_baseObject = 0x08;
constexpr std::uintptr_t kEquip_equipped   = 0x12;

// TESMagicEffectApplyEvent (sizeof 0x18)
constexpr std::uintptr_t kMagApply_target = 0x00;
constexpr std::uintptr_t kMagApply_caster = 0x08;
constexpr std::uintptr_t kMagApply_effect = 0x10;   // FormID

// TESHitEvent (clib RE/T/TESHitEvent.h, sizeof 0x28):
//   NiPointer<TESObjectREFR> target 0x00, cause 0x08, FormID source 0x10,
//   FormID projectile 0x14, Flag flags 0x18.
constexpr std::uintptr_t kHit_target     = 0x00;
constexpr std::uintptr_t kHit_cause      = 0x08;
constexpr std::uintptr_t kHit_source     = 0x10;
constexpr std::uintptr_t kHit_projectile = 0x14;
constexpr std::uintptr_t kHit_flags      = 0x18;
constexpr std::uint32_t  kHitFlag_PowerAttack  = 1u << 0;
constexpr std::uint32_t  kHitFlag_SneakAttack  = 1u << 1;
constexpr std::uint32_t  kHitFlag_BashAttack   = 1u << 2;
constexpr std::uint32_t  kHitFlag_HitBlocked   = 1u << 3;

// NiObjectNET (sizeof 0x30) and NiAVObject.
//
//   READ FROM THE HEADER, not derived:
//   guessing the member order and
//   back-solving until the arithmetic lands on `flags` at 0xF4 proves nothing,
//   because a different member order reaches 0xF4 too. The
//   real list, read out of clib RE/N/NiAVObject.h:
//
//     parent 0x30, parentIndex 0x38, unk03C 0x3C, collisionObject 0x40,
//     local 0x48, world 0x7C, previousWorld 0xB0, worldBound 0xE4,
//     flags 0xF4, userData 0xF8
//
//   and NiTransform (sizeof 0x34, static_assert) is { rotate 0x00, translate
//   0x24, scale 0x30 }. So world.translate is 0x7C + 0x24 = 0xA0. Reading
//   0x64 instead lands in local.rotate: rotation matrix elements read
//   as a position put every wound somewhere arbitrary, and
//   the log reports bones hundreds of units away.
constexpr std::uintptr_t kNET_name          = 0x10;   // BSFixedString -> char*
constexpr std::uintptr_t kAV_parent         = 0x30;
constexpr std::uintptr_t kAV_local          = 0x48;
constexpr std::uintptr_t kAV_world          = 0x7C;
constexpr std::uintptr_t kAV_worldRotate    = 0x7C;   // NiMatrix3, row major
constexpr std::uintptr_t kAV_worldTranslate = 0xA0;   // 0x7C + 0x24
constexpr std::uintptr_t kAV_worldScale     = 0xAC;   // 0x7C + 0x30
constexpr std::uintptr_t kAV_worldBound     = 0xE4;   // NiBound{center 0, radius 0x0C}
constexpr std::uintptr_t kAV_boundRadius    = 0xF0;
constexpr std::uintptr_t kAV_flags          = 0xF4;
constexpr std::uint32_t  kAV_flagHidden     = 1u << 0;   // NiAVObject::Flag
// NO DECALS. NiAVObject::Flag::kNoDecals = 1 << 10 in clib
// (include/RE/N/NiAVObject.h); NifSkope's NiAVObject flag editor names bit
// 1024 "No Decals" (src/spells/flags.cpp, niavFlags); the GECK wiki lists it
// under NIF NiAVObject Flags. A geometry carrying it is skipped by the engine's
// decal projection -- the flag fur-shell mods set so the blood decal is not
// applied to every one of their shells, where it costs a great deal of frame rate,
// and FleshCore's fill is twenty-seven to forty-five
// skinned shells stacked under every impact. Written into the live flags word
// at kAV_flags, exactly where the NIF's own value lands.
constexpr std::uint32_t  kAV_flagNoDecals   = 1u << 10;  // NiAVObject::Flag

// NiNode: NiTObjectArray<NiPointer<NiAVObject>> children at 0x110.
//   NiTArray has a vtable: vtbl 00, _data 08, _capacity 10, _freeIdx 12,
//   _size 14, _growthSize 16 (sizeof 0x18). Iterate _freeIdx and skip nulls.
constexpr std::uintptr_t kNode_children  = 0x110;
constexpr std::uintptr_t kNiTArr_data    = 0x08;
constexpr std::uintptr_t kNiTArr_freeIdx = 0x12;

// BSGeometry (SE, sizeof 0x158)
constexpr std::uintptr_t kGeom_shaderProperty = 0x128;
constexpr std::uintptr_t kGeom_skinInstance   = 0x130;
constexpr std::uintptr_t kGeom_rendererData   = 0x138;
constexpr std::uintptr_t kGeom_vertexDesc     = 0x148;

// BSDynamicTriShape (clib RE/B/BSDynamicTriShape.h, sizeof 0x180 SE): a
// BSTriShape (0x160) followed by DYNAMIC_TRISHAPE_RUNTIME_DATA at 0x160 --
//
// 0x158 is
// BSGeometry -- clib RE/B/BSGeometry.h STATIC_ASSERT_SIZE(BSGeometry,
// 0x158, 0x198), the three-argument (ClassName, FlatSize, VRSize) form of the
// macro in clib REL/Common.h -- and BSTriShape is 0x160, clib
// RE/B/BSTriShape.h STATIC_ASSERT_SIZE(BSTriShape, 0x160, 0x1A0). The eight
// bytes BSTriShape adds beyond BSGeometry hold triangleCount and vertexCount,
// which are named below.
// { void* dynamicData 00, BSSpinLock lock 08, u32 dataSize 10, u32 frameCount
// 14, ... }. So dynamicData is at 0x160 and dataSize at 0x170.
//
// THE HEADER DOES NOT SAY WHAT AN ELEMENT IS -- it types dynamicData as a bare
// void* -- so the stride was MEASURED in play:
// dataSize divided by the vertex count the shape's own skin partition reports.
// Every dynamic shape on a loaded actor answered the same, exactly:
//
//   eyes shape                  176 v, dataSize   2816 -> 16.00 B/vertex
//   head shape                 3832 v, dataSize  61312 -> 16.00 B/vertex
//   brows shape                 371 v, dataSize   5936 -> 16.00 B/vertex
//   physics wig               10781 v, dataSize 172496 -> 16.00 B/vertex
//
// Sixteen bytes a vertex, on the nose, across four shapes and three orders of
// magnitude of vertex count: NiPoint4 positions. That is the fact the head
// work needs.
constexpr std::uintptr_t kDynTri_dynamicData = 0x160;
constexpr std::uintptr_t kDynTri_dataSize    = 0x170;

// ---- WHAT ELSE IS IN THOSE TWO STRUCTS (for the head probes) -----
//
// BSTriShape's own runtime data sits at 0x158 -- clib RE/B/BSTriShape.h
//   RUNTIME_DATA_ACCESSOR_EX(TRISHAPE_RUNTIME_DATA, GetTrishapeRuntimeData,
//                            0x158, 0x198)
// where the macro's parameters are (StructType, FuncName, SEOffset, VROffset)
// (clib REL/RuntimeDataAccessors.h), so the SECOND number is VR and not
// AE. Its members, clib RE/B/BSTriShape.h:
//     u16 triangleCount 00, u16 vertexCount 02, u32 pad15C 04
// giving 0x158 and 0x15A. ARITHMETIC CHECK against the two offsets above it:
// BSGeometry ends at 0x158 (clib RE/B/BSGeometry.h), BSTriShape ends at
// 0x160 (clib RE/B/BSTriShape.h), and 0x158 + 8 == 0x160 == where
// dynamicData already is, measured. The struct closes exactly.
//
// A SKINNED SHAPE DECLARES A VERTEX COUNT AND NO TRIANGLES: femalehead.nif's
// BSDynamicTriShape reads nvert 3832, ntri 0, dataSize 0 off the disk, and the
// 3,832 the runtime reports for the head shape is the same number
// (see the table above). So vertexCount is the true N for a private
// buffer and triangleCount is the cheap "is any geometry inline here" test.
constexpr std::uintptr_t kTri_triangleCount = 0x158;   // u16
constexpr std::uintptr_t kTri_vertexCount   = 0x15A;   // u16

// The rest of DYNAMIC_TRISHAPE_RUNTIME_DATA, from the same declaration the two
// measured offsets above came out of (clib RE/B/BSDynamicTriShape.h,
// base 0x160): dynamicData 00, BSSpinLock lock 08, u32 dataSize 10,
// u32 frameCount 14, u32 unk178 18, u32 unk17C 1C.
//
// BSSpinLock is { volatile u32 _owningThread 0, volatile u32 _lockCount 4 },
// sizeof 8 -- clib RE/B/BSAtomic.h -- and CommonLib reimplements the
// whole protocol in SOURCE (clib src/RE/B/BSAtomic.cpp): acquire is
// InterlockedCompareExchange(&_lockCount, 1, 0) spun until it returns zero,
// then _owningThread = GetCurrentThreadId(); it is RECURSIVE on the owning
// thread; release clears the owner and CASes the count 1 -> 0.
//
// WHICH ENGINE FUNCTION WRITES dynamicData, ON WHICH THREAD, AND WHETHER IT
// TAKES THIS LOCK, IS UNKNOWN. Nothing in CommonLibSSE-NG's headers or sources
// mentions dynamicData, lock, dataSize or frameCount at all (grep of
// include/ and src/), so the probe LOGS these four words and does not write
// them unless the config says to.
constexpr std::uintptr_t kDynTri_lock       = 0x168;   // BSSpinLock::_owningThread
constexpr std::uintptr_t kDynTri_lockCount  = 0x16C;   // BSSpinLock::_lockCount
constexpr std::uintptr_t kDynTri_frameCount = 0x174;   // u32
constexpr std::uintptr_t kDynTri_unk178     = 0x178;   // u32, then u32 at 0x17C
constexpr std::size_t    kSizeof_BSDynamicTriShape = 0x180;   // clib, SE == AE

// VF_VERTEX -- "this vertex record carries a position of its own".
//   clib RE/V/VertexDesc.h   VA_POSITION = 0, VF_VERTEX = 1 << VA_POSITION
//   clib RE/V/VertexDesc.h   HasFlag(f) = ((desc >> 44) & f) != 0
// so the flag word begins at bit 44 and VF_VERTEX is bit 44 exactly. CHECKED
// against the two descriptors this mod has already measured: the body's
// 0x0004300050000408 gives (desc >> 44) == 0x043 = VERTEX|UV|SKINNED, whose
// GetSize() (clib) is 16 + 4 + 12 == 32 == VertexStride() below; the
// head's 0x0044200010000044 gives 0x442 = UV|SKINNED|FULLPREC with VF_VERTEX
// CLEAR, whose GetSize() is 4 + 12 == 16 == its stride. That is why a head
// partition record holds no position and why the head's positions have to come
// out of dynamicData instead.
constexpr std::uint64_t kVF_VERTEX = 1ull << 44;

// GetFeature is BSShaderMaterial virtual slot 06 -- clib RE/B/BSShaderMaterial.h
// annotates the whole table: dtor 00, Create 01, CopyMembers 02,
// DoIsCopy 03, ComputeCRC32 04, GetDefault 05, GetFeature 06, GetType 07 --
// i.e. the QWORD at vtable + 8*6. Feature values, clib: kDefault 0,
// kFaceGen 4, kFaceGenRGBTint 5, kHairTint 6, kEye 16.
//
// SLOT 02 IS CopyMembers, NOT GetRTTI. A BSShaderMaterial is not an NiObject
// and IsA() must never be pointed at one.
//
// WHY IT MATTERS HERE: kMat_skinTint (0xA0) above was measured on FEATURE-5
// materials. On a feature-4 (FaceGen) material the same twelve bytes are the
// two dwords of NiPointer<NiSourceTexture> tintTexture and the low dword of
// detailTexture (clib RE/B/BSLightingShaderMaterialFacegen.h), which is
// a pointer read as a colour.
constexpr std::size_t   kMat_GetFeature       = 6;
constexpr std::uint32_t kMatFeature_FaceGen     = 4;
constexpr std::uint32_t kMatFeature_FaceGenTint = 5;

// The three NiSourceTexture pointers a feature-4 material carries where a
// feature-5 material carries its NiColor -- clib
// RE/B/BSLightingShaderMaterialFacegen.h (tintTexture A0, detailTexture
// A8, subsurfaceTexture B0), sizeof 0xB8. An NiSourceTexture is an
// NiObjectNET, so its path reads through kNET_name.
constexpr std::uintptr_t kMatFG_tintTexture       = 0xA0;
constexpr std::uintptr_t kMatFG_detailTexture     = 0xA8;
constexpr std::uintptr_t kMatFG_subsurfaceTexture = 0xB0;

// NiObjectNET's extra-data array, clib RE/N/NiObjectNET.h:
//   NiExtraData** extra 0x20, u16 extraDataSize 0x28, u16 maxSize 0x2A.
// NiExtraData itself is an NiObject with a BSFixedString name at 0x10
// (clib RE/N/NiExtraData.h, sizeof 0x18) -- so kNET_name reads an
// entry's name as well.
//
// WALK IT, NEVER LOOK IT UP BY NAME. NiObjectNET::GetExtraData binary-searches
// on the INTERNED STRING'S POINTER VALUE, not on the characters
// (clib src/RE/N/NiObjectNET.cpp), so a hand-built BSFixedString can
// never match. The probe matches on the vtable instead.
constexpr std::uintptr_t kNET_extra         = 0x20;
constexpr std::uintptr_t kNET_extraDataSize = 0x28;   // u16

// BSFaceGenBaseMorphExtraData, clib RE/B/BSFaceGenBaseMorphExtraData.h:
//   NiPoint3* vertexData 0x18 ("allocated using modelVertexCount, not
//   vertexCount"), u32 modelVertexCount 0x20, u32 vertexCount 0x24; sizeof
//   0x28. Twelve bytes a vertex, count = modelVertexCount.
// WHAT STATE OF THE HEAD IT HOLDS IS UNKNOWN -- the header does not say, and
// nothing here can. Probe #5 only reports whether it exists.
constexpr std::uintptr_t kBaseMorph_vertexData       = 0x18;
constexpr std::uintptr_t kBaseMorph_modelVertexCount = 0x20;
constexpr std::uintptr_t kBaseMorph_vertexCount      = 0x24;

// NiTransform is { rotate 0x00, translate 0x24, scale 0x30 } -- the same
// static_assert-checked layout the world transform above was derived from --
// so the LOCAL translate is kAV_local + 0x24 == 0x48 + 0x24 == 0x6C. Read
// only to answer "is a per-actor head identity-transformed" (helmets are not).
constexpr std::uintptr_t kAV_localTranslate = 0x6C;

// BSGraphics::TriShape (sizeof 0x30) -- the renderer's own buffers.
constexpr std::uintptr_t kRD_vertexBuffer  = 0x00;   // ID3D11Buffer*
constexpr std::uintptr_t kRD_indexBuffer   = 0x08;   // ID3D11Buffer*
constexpr std::uintptr_t kRD_vertexDesc    = 0x10;
constexpr std::uintptr_t kRD_refCount      = 0x18;
constexpr std::uintptr_t kRD_rawVertexData = 0x20;
constexpr std::uintptr_t kRD_rawIndexData  = 0x28;

// NiSkinInstance (SE, sizeof 0x88)
constexpr std::uintptr_t kSkinI_skinData      = 0x10;
constexpr std::uintptr_t kSkinI_skinPartition = 0x18;
constexpr std::uintptr_t kSkinI_bones         = 0x28;   // NiAVObject**
constexpr std::uintptr_t kSkinI_numMatrices   = 0x3C;

// NiSkinPartition (sizeof 0x28) and its Partition (sizeof 0x50).
constexpr std::uintptr_t kSkinP_numPartitions = 0x10;
constexpr std::uintptr_t kSkinP_partitions    = 0x18;
constexpr std::uintptr_t kSkinP_vertexCount   = 0x20;
constexpr std::uintptr_t kPart_vertexDesc     = 0x00;
constexpr std::uintptr_t kPart_bones          = 0x08;   // u16* palette
constexpr std::uintptr_t kPart_weights        = 0x10;
constexpr std::uintptr_t kPart_vertexMap      = 0x18;
constexpr std::uintptr_t kPart_bonePalette    = 0x20;
constexpr std::uintptr_t kPart_triList        = 0x28;
constexpr std::uintptr_t kPart_vertices       = 0x38;   // u16
constexpr std::uintptr_t kPart_triangles      = 0x3A;   // u16
constexpr std::uintptr_t kPart_numBones       = 0x3C;   // u16
constexpr std::uintptr_t kPart_bonesPerVertex = 0x40;   // u16
constexpr std::uintptr_t kPart_buffData       = 0x48;
constexpr std::uintptr_t kPartStride          = 0x50;

// NiRefObject (sizeof 0x10): vtable 0x00, volatile u32 _refCount 0x08.
// Clones made with malloc get a saturated refcount so the engine's own
// allocator is never asked to free memory it did not hand out.
constexpr std::uintptr_t kNiRef_refCount = 0x08;
constexpr std::size_t kSizeof_NiSkinPartition   = 0x28;
constexpr std::size_t kSizeof_BSGraphicsTriShape = 0x30;

// SimpleArray<T> IS NOT A BARE POINTER. clib RE/M/MemoryManager.h:
//
//     size() { return _data ? *static_cast<const size_t*>(get_head()) : 0; }
//     get_head() { return reinterpret_cast<size_t*>(_data) - 1; }
//
// The element count lives in the eight bytes IMMEDIATELY BEFORE the data, and
// resize() allocates sizeof(T)*n + sizeof(size_t) and hands back the pointer
// one size_t in. (The branch that offsets by a whole element instead is only
// taken when alignof(T) > alignof(size_t); Partition is all pointers, so
// alignof is 8 and this is the size_t branch.)
//
// A partition array handed to the engine as a plain malloc block therefore
// reports the CRT's own heap bookkeeping as its element count. Everything that
// iterates partitions properly -- the engine, and every other plugin that
// walks actor geometry -- then runs off the end of the array. That was the
// crash: two access violations inside another plugin's geometry copy, on
// shapes FleshCore had cloned.
constexpr std::size_t kSimpleArrayHead = sizeof(std::size_t);

// NiObject vtable slot 2 is GetRTTI (clib annotates "// 02" on every
// override); NiRTTI is { const char* name 0x00; NiRTTI* base 0x08; }.
constexpr std::size_t   kVS_GetRTTI = 2;
constexpr std::uintptr_t kRTTI_name = 0x00;
constexpr std::uintptr_t kRTTI_base = 0x08;

// ID3D11Device vtable: IUnknown owns 0/1/2, CreateBuffer is the first
// virtual thereafter (clib REX/W32/D3D11.h) -> slot 3.
constexpr std::size_t   kVS_CreateBuffer         = 3;
// GetCreationFlags: the thirty-ninth virtual of the interface --
// clib REX/W32/D3D11.h, thirty-five virtuals after CreateBuffer
// (one per line, counted), and mingw-w64's d3d11.h ID3D11DeviceVtbl, where
// GetCreationFlags is the 39th entry after QueryInterface (GetFeatureLevel,
// GetCreationFlags, GetDeviceRemovedReason, GetImmediateContext in that
// order in both) -> slot 38. It answers the flags the device was created
// with; D3D11_CREATE_DEVICE_SINGLETHREADED is 0x1 in both headers, and a
// device created WITH it may not be called from more than one thread -- the
// redraw worker asks before it creates a buffer off the game's thread.
constexpr std::size_t   kVS_GetCreationFlags     = 38;
constexpr std::uint32_t kD3D11_CREATE_DEVICE_SINGLETHREADED = 0x1;
constexpr std::uint32_t kD3D11_USAGE_DEFAULT     = 0;
constexpr std::uint32_t kD3D11_BIND_INDEX_BUFFER  = 0x2;
// D3D11_BIND_VERTEX_BUFFER, from the same D3D11_BIND_FLAG enum as the index
// flag above (clib REX/W32/D3D11.h) -- the two are 0x1 and 0x2.
constexpr std::uint32_t kD3D11_BIND_VERTEX_BUFFER = 0x1;

// ============================================================ (B) FORM TABLE
// BSTScatterTable<...HeapAllocator> (clib RE/B/BSTHashMap.h, the padded
// "18/10" parent): capacity 0x0C, sentinel 0x18, entries 0x28. An entry for
// BSTTuple<const FormID, TESForm*> is key u32 @0, value @8, next @0x10,
// stride 0x18. next == nullptr means the slot is empty; next == sentinel
// ends the chain. The hash is CRC32 (poly 0xEDB88320, init 0, no final xor)
// over the four key bytes -- clib RE/C/CRC.h GenerateCRC32, via BSCRC32.
constexpr std::uintptr_t kMap_capacity    = 0x0C;
constexpr std::uintptr_t kMap_sentinel    = 0x18;
constexpr std::uintptr_t kMap_entries     = 0x28;
constexpr std::uintptr_t kMapEntry_key    = 0x00;
constexpr std::uintptr_t kMapEntry_value  = 0x08;
constexpr std::uintptr_t kMapEntry_next   = 0x10;
constexpr std::uintptr_t kMapEntryStride  = 0x18;

// BSStringPool::Entry -- 0x18 of header in front of the characters:
//   _left 0x00, _flags 0x08 (kRefCountMask 0x7FFF), _crc 0x0A, _length 0x10.
// A hand-built entry with a saturated refcount is safe to hand to anything
// that reads a BSFixedString, because nothing will ever try to free it.
constexpr std::uintptr_t kStrEntry_flags  = 0x08;
constexpr std::uintptr_t kStrEntry_length = 0x10;
constexpr std::uintptr_t kStrEntry_data   = 0x18;
constexpr std::uint16_t  kStrRefSaturated = 0x7FFF;

// TESObjectACTI: TESBoundAnimObject 0x00, TESFullName 0x30,
// TESModelTextureSwap 0x40, and TESModel keeps its model BSFixedString at
// +0x08 -- so the model path char* is at ACTI + 0x48.
constexpr std::uintptr_t kACTI_modelStr = 0x48;

// BSShaderProperty::material 0x78 -> BSLightingShaderMaterialBase::textureSet
// 0x78 -> BSShaderTextureSet, whose paths start at 0x10. sizeof 0x58 =
// 0x10 + 9*8, and every texture set parsed off disk reports exactly 9 slots.
constexpr std::uintptr_t kShadProp_material = 0x78;
constexpr std::uintptr_t kMat_textureSet    = 0x78;
constexpr std::uintptr_t kTexSet_paths      = 0x10;
constexpr int            kTexSet_count      = 9;

// THEIR SKIN COLOUR: three floats at material + 0xA0, in RGB order.
//
// NOT TAKEN FROM A HEADER. There is no clib offset quoted here because this
// one was MEASURED, in the running game, by dumping a window of every live
// skin shader property and its material and reporting every run of three
// floats that could be a colour. Across ten different targets, one offset and
// only one behaved the way a skin tone has to:
//
//   * IDENTICAL across a body's own skin shapes -- the 3BA body, the hands and
//     the feet of one target always agreed;
//   * DIFFERENT between targets -- (221,221,221), (155,139,132), (206,205,204),
//     (143,114,101), (148,143,88), and the dark blue-violet (73,73,100) of
//     a purple target;
//   * every channel an EXACT multiple of 1/255. Nothing else in either window
//     was quantised to eight bits, and a skin tone is stored in the NPC record
//     as three bytes, so that quantisation is a signature rather than a
//     coincidence.
//
// The neighbouring offsets in the dump are the same run seen through a sliding
// three-float window: 0x98 shows (0,0,R), 0x9C shows (0,R,G), 0xA0 shows
// (R,G,B), 0xA4 shows (G,B,0). So the colour begins at 0xA0 and 0x9C and 0xAC
// are not part of it.
constexpr std::uintptr_t kMat_skinTint      = 0xA0;

// ============================================================ (B) VERTEX FORM
// BSGraphics::VertexDesc packs the layout in nibbles: n0 * 4 is the vertex
// stride, n2 * 4 the UV offset, n7 * 4 the skinning offset. Confirmed against
// the test body, which byte-fitted with ZERO residue at stride 32 and
// desc 0x0004300050000408 -- (0x8 & 0xF) * 4 == 32. Position is three floats
// at offset 0 unless the UV nibble says otherwise.
constexpr std::uint32_t kVertexSizeShift = 4;
inline std::uint32_t VertexStride(std::uint64_t d) { return std::uint32_t(d & 0xF) * kVertexSizeShift; }
inline std::uint32_t UVOffset(std::uint64_t d)     { return std::uint32_t((d >> 8) & 0xF) * 4u; }
inline std::uint32_t SkinOffset(std::uint64_t d)   { return std::uint32_t((d >> 28) & 0xF) * 4u; }

// BSLightingShaderProperty, as it sits in a NIF block: type u32 @0, name @4,
// numExtra @8, controller @12, flags1 @16, flags2 @20, uvOffset, uvScale,
// textureSet ref @40. THE TYPE AND THE BLOCK LENGTH MUST AGREE -- type 0 is
// 100 bytes and type 5 is 112, and a type-0 header inside a 112-byte block
// leaves twelve undeclared bytes that make the file unloadable.
constexpr std::size_t kShaderBlockOff_type    = 0;
constexpr std::size_t kShaderBlockOff_flags1  = 16;
constexpr std::size_t kShaderBlockOff_texSet  = 40;
// flags1 bit 12 is Model Space Normals. Measured across every shipping mesh
// checked: of 26 BSLightingShaderProperty blocks, all 13 whose slot-1
// texture is a _msn map have bit 12 set and no other block does.
constexpr std::uint32_t kShaderFlag1_ModelSpaceNormals = 1u << 12;

// Havok: 69.9904 game units to one havok unit, measured off the shipping
// collision blocks.
constexpr float kHavokScale = 69.9904f;


// ======================================================= (A) PLACEMENT
//
// THE ENGINE FUNCTION PAPYRUS'S OWN PlaceAtMe RUNS. skse64 names it and calls
// it itself (PapyrusSpawnerTask.cpp) from a latent delay functor on the
// game's thread with a real registry and the calling stack's id:
//   skse64 v2.2.6 GameReferences.h, GameReferences.cpp
//     RelocAddr<_PlaceAtMe_Native> PlaceAtMe_Native(0x00A2E330);
//     TESObjectREFR* (VMClassRegistry* registry, UInt32 stackId,
//                     TESObjectREFR* target, TESForm* form, SInt32 count,
//                     bool bForcePersist, bool bInitiallyDisabled)
//   addrlib reverse-lookup 0x00A2E330 -> exactly one id (56203)
// ONE naming source (CommonLibSSE-NG does not name it). What the engine
// does with `registry` and `stackId` is unknown: the exe is packed. This is why
// the call sits behind the cfg's `E` row (1 or 2; the shipped config sets 2), proven by a probe first.
constexpr std::uint32_t kPlaceAtMeNative = 0x00A2E330;

// MOVE A REFERENCE TO A POSITION. TWO independent naming sources:
//   skse64 v2.2.6 GameReferences.h, GameReferences.cpp
//     RelocAddr<_MoveRefrToPosition> MoveRefrToPosition(0x00A447F0);
//     void (TESObjectREFR* source, UInt32* pTargetHandle, void* parentCell,
//           void* worldSpace, NiPoint3* position, NiPoint3* rotation)
//   clib src/RE/T/TESObjectREFR.cpp TESObjectREFR::MoveTo_Impl
//     RELOCATION_ID(56227, 56626): (this, const ObjectRefHandle&,
//     TESObjectCELL*, TESWorldSpace*, const NiPoint3&, const NiPoint3&)
//   addrlib id 56626 -> 0x00A447F0, and 0x00A447F0 -> exactly one id (56626).
// Both agree on every argument. skse64's spawner calls it right after
// PlaceAtMe_Native with the spawned ref's own parentCell and worldspace.
constexpr std::uint32_t kMoveRefrToPosition = 0x00A447F0;

// TESObjectREFR::GetWorldspace() -- what skse64's spawner hands to the move
// above (CALL_MEMBER_FN(spawned, GetWorldspace)()).
//   skse64 v2.2.6 GameReferences.h DEFINE_MEMBER_FN(GetWorldspace,
//     TESWorldSpace*, 0x002ED870)
//   addrlib reverse-lookup 0x002ED870 -> exactly one id (19816)
// clib implements the same thing in source (TESObjectREFR.cpp: the
// parent cell's worldSpace when the cell is exterior, else null), which is
// what the probe log checks it against: null inside, non-null outside.
constexpr std::uint32_t kRefrGetWorldspace = 0x002ED870;

// SkyrimVM* -- the singleton pointer, and the class registry inside it.
//   skse64 v2.2.6 PapyrusVM.cpp RelocPtr<SkyrimVM*>(0x020FBA70)
//   clib src/RE/S/SkyrimVM.cpp RELOCATION_ID(514315, 400475) -> 0x020FBA70
//   registry at +0x200: skse64 PapyrusVM.h
//     STATIC_ASSERT(offsetof(SkyrimVM, m_classRegistry) == 0x200)
//   clib include/RE/S/SkyrimVM.h  BSTSmartPointer<IVirtualMachine> impl; // 0200
constexpr std::uint32_t  kSkyrimVMGlobal        = 0x020FBA70;
constexpr std::uintptr_t kSkyrimVM_classRegistry = 0x200;

// THE INVALID REFERENCE HANDLE, read from the engine's own global exactly as
// skse64 does (GameReferences.cpp), and passed to the move as
// "no target reference" -- the spawner's `nullHandle`.
//   skse64 v2.2.6 GameReferences.cpp RelocPtr<UInt32> g_invalidRefHandle(0x020F699C)
//   addrlib reverse-lookup 0x020F699C -> exactly one id (400312)
constexpr std::uint32_t kInvalidRefHandleGlobal = 0x020F699C;

// TESObjectREFR: the placed object's own angle and position (two sources)
//   skse64 GameReferences.h  NiPoint3 rot 48, NiPoint3 pos 54,
//                                    TESObjectCELL* parentCell 60
//   clib RE/T/TESObjectREFR.h OBJ_REFR data 40 { objectReference 00,
//                                    angle 08, location 14 }, parentCell 60
constexpr std::uintptr_t kREFR_angle      = 0x48;
constexpr std::uintptr_t kREFR_pos        = 0x54;
constexpr std::uintptr_t kREFR_parentCell = 0x60;
// sizeof(TESObjectREFR), SE: clib RE/T/TESObjectREFR.h static_assert 0x98;
// skse64 GameReferences.h lays out the same members to 0x98.
constexpr std::size_t    kREFR_size       = 0x98;

// BSModelDB::Demand -- load a model into the engine's model database now.
//   clib include/RE/B/BSModelDB.h, src/RE/B/BSModelDB.cpp
//     RELOCATION_ID(74040, 75782): BSResource::ErrorCode (const char* path,
//     NiPointer<NiNode>& out, const DBTraits::ArgsType& args)
//     ArgsType (sizeof 0xC): u32 LODmult 0, u32 texLoadLevel 3, bool true,
//     bool false, bool true, bool postProcess true  (BSModelDB.h)
//   addrlib id 75782 -> 0x00E03EE0, unique. ONE naming source (clib only;
//   skse64 has no loader). Whether it is synchronous and what it does to the
//   cache's refcounts is unknown; it is a PROBE (`E` prime flag), off.
constexpr std::uint32_t kBSModelDBDemand = 0x00E03EE0;

// =========================================== (A) THE HEAD MATERIALS
//
// THREE VTABLE ADDRESSES, USED ONLY AS IDENTITIES -- never called through,
// never written. Each is a class's vtable start, so the QWORD at an object's
// offset 0 equals base + one of these exactly when the object is of that
// class. They are resolved the same way as every address in section (A):
//
//   clib RE/Offsets_VTABLE.h  VTABLE_BSLightingShaderMaterialFacegen
//                                  REL::VariantID(304560, 254749, 0x18fe820)
//   clib RE/Offsets_VTABLE.h  VTABLE_BSLightingShaderMaterialFacegenTint
//                                  REL::VariantID(304561, 254751, 0x18fe898)
//   clib RE/Offsets_VTABLE.h  VTABLE_BSFaceGenBaseMorphExtraData
//                                  REL::VariantID(252391, 200326, 0x1678260)
//
// VariantID is (SE id, AE id, VR offset) -- clib REL/ID.h -- so the
// MIDDLE number is this runtime's, and the third is a VR byte offset, not an
// id. Resolved against the Address Library's 1.6.1170 database (428,461 entries):
//
//   AE id 254749 -> 0x01AB7188      AE id 254751 -> 0x01AB7200
//   AE id 200326 -> 0x01846338
//
// and each REVERSE-maps to exactly one id, so all three are real symbol starts
// rather than interior offsets that happen to look plausible. CONTROL, run in
// the same pass through the same table: id 411348 -> 0x03286A10 and id 400507
// -> 0x020FBB88, byte-identical to kD3D11DeviceGlobal and kAllFormsGlobal
// above, both of which are proven in play. ONE naming source (CommonLibSSE-NG
// only; skse64 names no vtables), which is why nothing here is called and the
// material's own GetFeature is the deciding test -- these are corroboration
// for the log, not a substitute for asking the object.
constexpr std::uint32_t kVT_MaterialFacegen     = 0x01AB7188;
constexpr std::uint32_t kVT_MaterialFacegenTint = 0x01AB7200;
constexpr std::uint32_t kVT_FaceGenBaseMorph    = 0x01846338;

// The face node's NiRTTI name, for IsA(). The DLL's IsA walks the NiRTTI chain
// by name (see GetRtti/IsA), and BSFaceGenNiNode derives NiNode, so the walk
// finds "NiNode" too -- the class name is what separates the face node from
// every other node under their root.
//   clib RE/B/BSFaceGenNiNode.h  class BSFaceGenNiNode : public NiNode
//   clib RE/B/BSFaceGenNiNode.h  sizeof 0x168 (SE == AE)
// Its own members are not used here; only its identity and its kAV_flags bit.
constexpr const char* kRTTI_BSFaceGenNiNode = "BSFaceGenNiNode";


// ============================================================ THE PLAYER CAMERA
//
// For the death camera. Every number below was read
// from CommonLibSSE-NG's headers and cross-checked against skse64 v2.2.6's
// GameCamera.h, and the one global was resolved out of the Address Library's
// 1.6.1170 database. What no source states -- the meaning of the
// zoom numbers, what the engine does to them each frame, which state a dying
// player's camera is in -- is said in flesh.cpp beside the write, and the
// write logs what it finds.
//
// PlayerCamera** -- the singleton pointer, dereferenced once.
//   clib src/RE/P/PlayerCamera.cpp   RELOCATION_ID(514642, 400802)
//   addrlib AE id 400802                -> 0x030FD7F8   (Address Library)
//   skse64 v2.2.6 GameCamera.h      RelocPtr<PlayerCamera*> g_playerCamera(0x030FD7F8)
constexpr std::uint32_t  kPlayerCameraGlobal = 0x030FD7F8;
// TESCamera (clib RE/T/TESCamera.h, sizeof 0x38):
//   BSTSmartPointer<TESCameraState> currentState;  // 28   (a bare T*: clib BSTSmartPointer.h, one member _ptr)
constexpr std::uintptr_t kTESCamera_currentState = 0x28;
// PlayerCamera (clib RE/P/PlayerCamera.h, sizeof 0x168 flat): TESCamera at 000,
// BSTSingletonSDM at 038, pad039, pad03A, ActorHandle cameraTarget at 03C, then
// RUNTIME_DATA at 040 whose cameraStates[kTotal] sits at +0x78 = 0xB8.
//   skse64 GameCamera.h  STATIC_ASSERT(offsetof(PlayerCamera, cameraStates) == 0xB8)  -- agrees
constexpr std::uintptr_t kPlayerCamera_cameraStates = 0xB8;
constexpr std::size_t    kPlayerCamera_size         = 0x168;
// CameraStates::CameraState (clib PlayerCamera.h; skse64 GameCamera.h names the same
// order): FirstPerson 0, AutoVanity 1, VATS 2, Free 3, IronSights 4, Furniture 5, PCTransition 6,
// Tween 7, Animated 8, ThirdPerson 9, Mount 10, Bleedout 11, Dragon 12, Total 13.
constexpr std::uint32_t  kCameraState_ThirdPerson = 9;
constexpr std::uint32_t  kCameraState_Bleedout    = 11;
constexpr std::uint32_t  kCameraState_Total       = 13;
// TESCameraState (clib RE/T/TESCameraState.h, sizeof 0x20):
//   TESCamera* camera;  // 10        CameraState id;  // 18
constexpr std::uintptr_t kCameraState_camera = 0x10;
constexpr std::uintptr_t kCameraState_id     = 0x18;
// ThirdPersonState (clib RE/T/ThirdPersonState.h; skse64 GameCamera.h STATIC_ASSERT(sizeof == 0xE8)):
//   float targetZoomOffset;   // 74
//   float currentZoomOffset;  // 78
//   float savedZoomOffset;    // 84
//   float pitchZoomOffset;    // 88 - [0, 100]     <- the only range the header states
constexpr std::uintptr_t kThirdPerson_targetZoomOffset  = 0x74;
constexpr std::uintptr_t kThirdPerson_currentZoomOffset = 0x78;
constexpr std::uintptr_t kThirdPerson_savedZoomOffset   = 0x84;
constexpr std::size_t    kThirdPerson_size              = 0xE8;
// BleedoutCameraState : ThirdPersonState (clib RE/B/BleedoutCameraState.h):
//   NiMatrix3 rotationMtx;  // 0E8      float zoom;  // 10C      float pitch;  // 110
//   float yaw;              // 114      float randHeading;  // 118
//   skse64 GameCamera.h: "unk10C - init'd to 200", "unk110 - init'd to 0.523599 (PI/6)"
//   -- so the header's `zoom` is constructed at 200, a distance-sized number, not a fraction.
constexpr std::uintptr_t kBleedout_zoom  = 0x10C;
constexpr std::uintptr_t kBleedout_pitch = 0x110;
constexpr std::size_t    kBleedout_size  = 0x11C;   // through randHeading; enough for every read here


// ================================================= (B) THE BLOW
//
// Everything the trigger table needs to know about a hit that the event
// itself does not carry: how hard it was, where it landed, what swung, and
// how much life the target has. Read from CommonLibSSE-NG
// (include/RE) and skse64 v2.2.6 (the 1.6.1170 release).
//
// THE AE SHIFT. From runtime 1.6.629 TESObjectREFR grew by eight bytes at its
// end, and every Actor member after it moved by eight. The two sources
// say so two different ways, and agree:
//   clib RE/A/Actor.h   AsActorValueOwner(): RelocateMemberIfNewer(
//                               RUNTIME_SSE_1_6_629, this, 0xB0, 0xB8)
//   clib RE/A/Actor.h   GetActorRuntimeData(): (..., 0xE0, 0xE8), and
//                               currentProcess sits at +0x10 in that block
//                               (Actor.h "/* 0F0 */" against the block's
//                               own "/* 0E0 */" origin) -> 0xE8 + 0x10 = 0xF8
//   skse64 GameReferences.h STATIC_ASSERT(sizeof(TESObjectREFR) == 0xA0)
//   skse64 GameReferences.h STATIC_ASSERT(offsetof(Actor, actorValueOwner) == 0xB8)
//   skse64 GameReferences.h STATIC_ASSERT(offsetof(Actor, addedSpells) == 0x190)
//                               -- its member comments still read the SE numbers
//                               (actorValueOwner "0B0", processManager "0F0",
//                               addedSpells "188"), and the asserts are +8 on
//                               every one, so processManager is 0xF0 + 8 = 0xF8.
// kREFR_pos (0x54) and kREFR_loadedData (0x68) sit BEFORE the growth and are
// untouched, which use in play has confirmed.
constexpr std::uintptr_t kActor_avOwner        = 0xB8;   // ActorValueOwner base (a vtable pointer)
constexpr std::uintptr_t kActor_currentProcess = 0xF8;   // AIProcess*
constexpr std::size_t    kActor_readSpan       = 0x100;  // enough to cover both reads

// AIProcess -> MiddleHighProcessData -> HitData.
//   clib RE/A/AIProcess.h   middleLow 000, middleHigh 008, high 010
//   skse64 GameFormComponents.h MiddleProcess* middleProcess; // 08
//   clib RE/M/MiddleHighProcessData.h  HitData* lastHitData; // 190
//   skse64 GameFormComponents.h (MiddleProcess): "UInt64 unk190; // 190",
//     STATIC_ASSERT(offsetof(MiddleProcess, effectList) == 0x1A0) and
//     sizeof == 0x338 -- the SAME skeleton (clib: activeEffects 1A0, sizeof
//     0x338), with the slot at 0x190 present but unnamed. So the offset has
//     two sources and the MEANING one, which is why the HitData read
//     below is cross-checked against the event before it is used:
//     hd.weapon must be the event's source, hd's own power/sneak/bash flags
//     must be the event's, and hitPosition must be within reach of them.
constexpr std::uintptr_t kAIProcess_middleHigh = 0x08;
constexpr std::uintptr_t kMHPD_lastHitData     = 0x190;
constexpr std::size_t    kMHPD_readSpan        = 0x198;

// HitData (clib RE/H/HitData.h, static_assert sizeof 0x90; skse64 names no
// HitData at all, so this is clib alone, guarded as said above):
//   NiPoint3 hitPosition 00, NiPoint3 hitDirection 0C, ActorHandle aggressor
//   18, target 1C, ObjectRefHandle sourceRef 20, attackData 28,
//   TESObjectWEAP* weapon 30, criticalEffect 38, attackDataSpell 40,
//   VATSCommand 48, float totalDamage 50, physicalDamage 54,
//   targetedLimbDamage 58, percentBlocked 5C, ..., Flag flags 80 (u32).
//   Flag: kSneakAttack 1<<11, kBash 1<<14, kPowerAttack 1<<16 (HitData.h)
constexpr std::uintptr_t kHD_hitPosition    = 0x00;
constexpr std::uintptr_t kHD_hitDirection   = 0x0C;
constexpr std::uintptr_t kHD_weapon         = 0x30;
constexpr std::uintptr_t kHD_totalDamage    = 0x50;
constexpr std::uintptr_t kHD_physicalDamage = 0x54;
constexpr std::uintptr_t kHD_flags          = 0x80;
constexpr std::size_t    kHD_size           = 0x90;
constexpr std::uint32_t  kHDFlag_SneakAttack = 1u << 11;
constexpr std::uint32_t  kHDFlag_Bash        = 1u << 14;
constexpr std::uint32_t  kHDFlag_PowerAttack = 1u << 16;

// ActorValueOwner's vtable (sizeof 8: it IS a vtable pointer). Slot order:
//   clib RE/A/ActorValueOwner.h   ~00, GetActorValue 01,
//     GetPermanentActorValue 02, GetBaseActorValue 03, SetBaseActorValue 04,
//     ModActorValue 05, RestoreActorValue 06, SetActorValue 07
//   skse64 GameFormComponents.h  ~, GetCurrent, GetMaximum, GetBase,
//     SetBase, ModBase, ModCurrent, SetCurrent  -- the same eight, in order,
//     and skse64's name for slot 2 says what it returns.
// Both are (this, ActorValue) -> float; on x64 Windows that is RCX, EDX,
// XMM0. Called ONLY on a form whose type reads 62 (ACHR), on the engine's
// own thread inside its own hit event, exactly as skse64's Papyrus natives do
// (PapyrusActorValueInfo.cpp, Hooks_Scaleform.cpp).
constexpr std::size_t   kVS_AVO_GetActorValue          = 1;
constexpr std::size_t   kVS_AVO_GetPermanentActorValue = 2;
// Health is actor value 24:
//   clib RE/A/ActorValues.h          kHealth = 24
//   CK wiki, ActorValueInfo Script (SKSE's GetActorValueInfoByID table):
//                                       "24 Health / 25 Magicka / 26 Stamina"
constexpr std::uint32_t kAV_Health = 24;

// TESObjectWEAP, the two things a blow's type is read from:
//   clib RE/T/TESObjectWEAP.h   ... BGSBlockBashData 128,
//                                     BGSKeywordForm 140, TESDescription 158
//   skse64 GameObjects.h    blockBash 128, keyword 140, description 158
//   BGSKeywordForm: clib RE/B/BGSKeywordForm.h keywords 08, numKeywords 10
//                   skse64 GameFormComponents.h keywords 08, numKeywords 10
//   -> keywords at 0x148, numKeywords at 0x150.
//   Data (DNAM) at 0x168 on both (clib "weaponData // 168 - DNAM";
//   skse64 "GameData gameData; // 168"), and animationType is the byte
//   at +0x35 on both (clib "animationType // 35"; skse64
//   "UInt8 type; // 35") -> 0x19D.
//   WEAPON_TYPE (clib; skse64 the same ten in the same
//   order): HandToHandMelee 0, OneHandSword 1, OneHandDagger 2, OneHandAxe 3,
//   OneHandMace 4, TwoHandSword 5, TwoHandAxe 6, Bow 7, Staff 8, Crossbow 9.
//   A warhammer and a battleaxe are BOTH TwoHandAxe here; the keyword tells
//   them apart, which is why the keywords are read at all.
constexpr std::uintptr_t kWEAP_keywords      = 0x148;   // BGSKeyword**
constexpr std::uintptr_t kWEAP_numKeywords   = 0x150;   // u32
constexpr std::uintptr_t kWEAP_animationType = 0x19D;   // u8
constexpr std::size_t    kWEAP_readSpan      = 0x1A0;
constexpr std::uint8_t   kWT_HandToHand = 0, kWT_Sword = 1, kWT_Dagger = 2, kWT_Axe = 3,
                         kWT_Mace = 4, kWT_Greatsword = 5, kWT_TwoHandAxe = 6, kWT_Bow = 7,
                         kWT_Staff = 8, kWT_Crossbow = 9;
// BGSKeyword keeps its editor id at runtime, as a BSFixedString (a char*):
//   clib RE/B/BGSKeyword.h     BSFixedString formEditorID; // 20, sizeof 0x28
//   skse64 GameForms.h        BSFixedString keyword; // 20
constexpr std::uintptr_t kKYWD_editorID = 0x20;
constexpr std::size_t    kKYWD_size     = 0x28;
// Form types, beside the three already proven above:
//   clib RE/F/FormTypes.h  Spell 0x16, Armor 0x1A, Weapon 0x29
//   skse64 GameForms.h             STATIC_ASSERT(kFormType_Weapon == 0x29),
//   and its enum runs ...Activator(24), TalkingActivator, Armor -> 26 in the
//   same order as clib's.
constexpr std::uint8_t kFormType_SPEL = 22;
constexpr std::uint8_t kFormType_ARMO = 26;
constexpr std::uint8_t kFormType_WEAP = 41;
// A placed object that is not an actor: clib FormTypes.h "3D REFR"; skse64
// GameForms.h kFormType_Reference, the entry before Character (62, proven).
constexpr std::uint8_t kFormType_REFR = 61;

// ================================================= (B) TYPED MAGIC
//
// EffectSetting (MGEF), for typing a hostile effect that lands on them:
//   clib RE/E/EffectSetting.h   TESForm 000, TESFullName 020,
//                                     BGSMenuDisplayObject 030, BGSKeywordForm 040
//   skse64 GameForms.h      fullName 20, menuDisplayObject 30, keywordForm 40
//   -> keywords at 0x48, numKeywords at 0x50 (BGSKeywordForm as above).
//   clib  EffectSettingData data; // 068 -- and inside it
//              flags 00 (kHostile = 1 << 0), resistVariable 14, archetype 58
//   skse64 Properties properties; // 68 -- flags 00 (kEffectType_Hostile
//              0x1), resistance 14, archetype 58
//   -> flags 0x68, resistVariable 0x7C, archetype 0xC0; sizeof 0x198 (clib).
//   Archetype (clib RE/E/EffectArchetypes.h; skse64 the same list):
//   WerewolfFeed 26, Werewolf 36.
//   Resist actor values: clib RE/A/ActorValues.h kResistFire 41,
//   kResistShock 42, kResistFrost 43; CK wiki ActorValueInfo table
//   "41 FireResist / 42 ElectricResist / 43 FrostResist".
constexpr std::uint8_t   kFormType_MGEF      = 18;   // clib FormTypes.h "12 MGEF"; skse64 kFormType_EffectSetting
constexpr std::uintptr_t kMGEF_keywords      = 0x48;
constexpr std::uintptr_t kMGEF_numKeywords   = 0x50;
constexpr std::uintptr_t kMGEF_flags         = 0x68;
constexpr std::uintptr_t kMGEF_resistVariable = 0x7C;
constexpr std::uintptr_t kMGEF_archetype     = 0xC0;
constexpr std::size_t    kMGEF_readSpan      = 0x198;
constexpr std::uint32_t  kMGEFFlag_Hostile   = 1u << 0;
constexpr std::uint32_t  kArchetype_WerewolfFeed = 26;
constexpr std::uint32_t  kArchetype_Werewolf     = 36;
constexpr std::uint32_t  kAV_ResistFire  = 41;
constexpr std::uint32_t  kAV_ResistShock = 42;
constexpr std::uint32_t  kAV_ResistFrost = 43;
// The three actor values the abilities plugin's effects modify:
//   clib ActorValues.h kSpeedMult 30, kBlockPowerModifier 138,
//   kAttackDamageMult 154; CK wiki "30 SpeedMult / 138 BlockPowerMod /
//   154 AttackDamageMult". Stated here for the record; the plugin carries them.
constexpr std::uint32_t  kAV_SpeedMult          = 30;
constexpr std::uint32_t  kAV_BlockPowerModifier = 138;
constexpr std::uint32_t  kAV_AttackDamageMult   = 154;

// ================================================ (A) WHO THEY ARE
//
// The HQ's Combat page decides who a blow may cut -- the player, a follower,
// an essential or protected NPC, anyone else -- and those are four facts
// about an Actor, read and never written.
//
// THE PLAYER is the reference 0x00000014: the CK wiki ("Player - the
// PlayerRef, form ID 00000014") and UESP's FormID page agree, and skse64
// resolves `player` through the same id (GameReferences.cpp: g_thePlayer,
// FormID 0x14 in every console command).
constexpr std::uint32_t  kPlayerFormID = 0x00000014;
// THE RUNTIME FLAG WORDS on Actor, both in the block that moved by eight at
// 1.6.629 (see kActor_avOwner above for the two-source proof of the
// shift; skse64's own asserts are the post-629 numbers while its comments
// are the old ones):
//   boolBits  clib RE/A/Actor.h   "boolBits  /* 0E0 */" in the 0xE0-origin
//             runtime block (RelocateMemberIfNewer(..., 0xE0, 0xE8))
//             skse64 GameReferences.h "UInt32 flags1; // 0E0", and its
//             STATIC_ASSERT(offsetof(Actor, unk0D8) == 0xE0) puts flags1 at
//             0xE8 on this runtime.                               -> 0xE8
//     kPlayerTeammate = 1 << 26: clib Actor.h; skse64
//             kFlags_IsPlayerTeammate = 0x4000000. Actor::IsPlayerTeammate
//             (clib src/RE/A/Actor.cpp) reads exactly this bit.
//   boolFlags clib Actor.h "boolFlags /* 1FC */" in the same block;
//             skse64 "UInt32 flags2; // 1FC"                  -> 0x204
//     kEssential = 1 << 18, kProtected = 1 << 19: clib Actor.h, read
//             by Actor::IsEssential / IsProtected (Actor.cpp). skse64
//             names no bit of flags2 but kFlags_CanDoFavor (0x80), so the
//             runtime bits have ONE naming source; the base record's own
//             flags below are the second read, and both are consulted.
constexpr std::uintptr_t kActor_boolBits   = 0xE8;
constexpr std::uintptr_t kActor_boolFlags  = 0x204;
constexpr std::size_t    kActor_flagsSpan  = 0x208;
constexpr std::uint32_t  kActorBit_PlayerTeammate = 1u << 26;
constexpr std::uint32_t  kActorFlag_Essential     = 1u << 18;
constexpr std::uint32_t  kActorFlag_Protected     = 1u << 19;
// THE BASE RECORD (TESNPC) and its ACBS flags:
//   TESObjectREFR::data.objectReference -- the base form -- at 0x40:
//     clib RE/T/TESObjectREFR.h "OBJ_REFR data; // 40", "TESBoundObject*
//     objectReference; // 00"; skse64 GameReferences.h "TESForm* baseForm; // 40"
//   TESNPC : TESActorBase (clib RE/T/TESNPC.h "// 000"), and TESActorBase
//     carries TESActorBaseData at 0x30 (clib TESActorBase.h; skse64
//     GameObjects.h "TESActorBaseData actorData; // 030"), whose
//     ACTOR_BASE_DATA sits at +0x08 with the flag word first (clib
//     TESActorBaseData.h "ACTOR_BASE_DATA actorData; // 08",
//     "actorBaseFlags // 00"; skse64 GameFormComponents.h "UInt32 flags; // 08")
//                                                                 -> 0x38
//     kEssential = 1 << 1, kProtected = 1 << 11: clib TESActorBaseData.h
//     (TESActorBaseData::IsEssential / IsProtected); the CK
//     wiki's NPC_ record, ACBS flags: "0x00000002 Essential", "0x00000800
//     Protected".
constexpr std::uintptr_t kREFR_baseForm     = 0x40;
constexpr std::uintptr_t kNPC_acbsFlags     = 0x38;
constexpr std::size_t    kNPC_flagsSpan     = 0x40;
constexpr std::uint32_t  kACBS_Essential    = 1u << 1;
constexpr std::uint32_t  kACBS_Protected    = 1u << 11;
// THE LEVEL, eight past the flag word: clib TESActorBaseData.h
// ACTOR_BASE_DATA "std::uint16_t level; // 08"; skse64 GameFormComponents.h
// TESActorBaseData "UInt16 level; // 10 ... (CK Multiplier * 1000 if PCLevelMult
// is true)" -> 0x40. PCLevelMult: clib "kPCLevelMult = 1 << 7", skse64
// "kFlag_PCLevelMult = 0x80". That the player's own base record carries the live
// level is unverified (SkyrimSE.exe's code is encrypted on disk): the DLL range-checks
// it and logs it, and one look at the character sheet settles it.
constexpr std::uintptr_t kNPC_acbsLevel     = 0x40;
constexpr std::size_t    kNPC_levelSpan     = 0x42;
constexpr std::uint32_t  kACBS_PCLevelMult  = 1u << 7;
constexpr std::uint8_t   kFormType_NPC      = 43;   // clib FormTypes.h "2B NPC_"; skse64 GameForms.h kFormType_NPC, two after Weapon (0x29, asserted)

// ---- WHAT RACE THEY ARE (the race gate) --------------------------------
//
// Proven in play. The gate that reads them (flesh.cpp, RaceGateRefuses)
// defaults to log mode (RG 1) and enforces refusals when RG is set to 2.
//
// THE ACTOR'S RACE, a TESRace*, in the runtime block that moved by eight at
// 1.6.629:
//   skse64 GameReferences.h  "TESRace* race; // 1F0" -- the SE number, like
//                            every member comment in that struct
//   the AE shift              +8 on every Actor member after TESObjectREFR
//                            (the two-source proof beside kActor_avOwner).
//                            skse64's asserts bracket this member: addedSpells,
//                            commented 188, is asserted at 0x190, and the
//                            struct, whose last comment ends at 2B0, is
//                            asserted at 0x2B8                      -> 0x1F8
//   skse64's own Actor natives read actor->race->data.raceFlags through this
//   layout (PapyrusActor.cpp).
constexpr std::uintptr_t kActor_race     = 0x1F8;
constexpr std::size_t    kActor_raceSpan = 0x200;
// THE FORM TYPE OF A RACE, the byte at kForm_formType:
//   skse64 GameForms.h  the FormType enum: kFormType_Race is its fifteenth
//                       entry, the one after kFormType_Eyes          -> 14
//   skse64 GameForms.h  its form-id table: "0F 0E 0E RACE TESRace", whose
//                       last column is the SE id                    -> 0x0E
//   The same enum gives EffectSetting 18, Spell 22 and Activator 24, the
//   values already proven above.
constexpr std::uint8_t   kFormType_Race  = 14;
// TESRace's FLAG WORD -- the RACE record's DATA flags, held at runtime:
//   skse64 GameForms.h  TESRace "Data data; // 0E8". ARITHMETIC CHECK: the
//                       "TESModel models[2]; // 098" before it are two
//                       0x28-byte TESModels (GameFormComponents.h: vtable,
//                       name 08, 10, 18, a UInt32 at 20), ending at 0xE8.
//   skse64 GameForms.h  TESRace::Data "UInt32 raceFlags; // 20". ARITHMETIC
//                       CHECK: seven two-byte skill bonuses (00-0D), two pad
//                       bytes (0E), height[2] at 10 and weight[2] at 18 put
//                       it at +0x20                                 -> 0x108
//   The master file carries the same word at the same place: Skyrim.esm's
//   RACE records hold it at byte 0x20 of DATA -- NordRace 0x50A08943,
//   NordRaceChild 0x50208946, NordRaceVampire 0x54A08942.
//   The bits: skse64 GameForms.h kRace_Playable = 0x00000001 and
//   kRace_Child = 0x00000004, which those three records bear out (playable;
//   child; neither).
constexpr std::uintptr_t kRace_flags        = 0x108;
constexpr std::uint32_t  kRaceFlag_Playable = 0x00000001;
constexpr std::uint32_t  kRaceFlag_Child    = 0x00000004;
// TESRace KEEPS ITS EDITOR ID at runtime, as a BSFixedString (one char*):
//   skse64 GameForms.h  TESRace "StringCache::Ref editorId; // 2E0".
//                       ARITHMETIC CHECK: from data at 0E8 (0xAC bytes, so
//                       the next member aligns to 198) the member comments
//                       add up, size by size, to 2E0.
//   skse64's Race natives build their by-name race table from it
//   (PapyrusRace.cpp), and its menu data hands it out (ScaleformExtendedData.cpp).
// ONE naming source.
constexpr std::uintptr_t kRace_editorID = 0x2E0;
constexpr std::size_t    kRace_readSpan = 0x2E8;

// ---- WHAT THEY ARE WEARING, AND WHAT IT IS MADE OF (the armour) --------
//
// THE ACTOR'S BIPED. One pointer-sized slot in the runtime block that moved by
// eight at 1.6.629 (see kActor_avOwner for the shift's two-source proof):
//   clib RE/A/Actor.h   "BSTSmartPointer<BipedAnim> biped; /* 260 */" in the
//                           0xE0-origin block, RelocateMemberIfNewer(...,
//                           0xE0, 0xE8)                               -> 0x268
//   skse64 GameReferences.h "UInt64 unk260; // 260" -- SE numbering, the
//                           asserts are +8 on this runtime -> 0x268
//   BSTSmartPointer is ONE raw pointer: clib BSTSmartPointer.h
//   static_assert(sizeof(BSTSmartPointer<void*>) == 0x8).
// skse64 names the slot but not its meaning, so the MEANING has one naming
// source -- clib -- and a second, indirect one: both declare a biped getter
// at TESObjectREFR vtable 0x7E (clib TESObjectREFR.h GetBiped1 "// 7E",
// skse64 GameReferences.h GetBiped(UInt32), the slot after Unk_7D), whose
// return in both is a pointer to the same one-pointer holder. Like the HitData
// slot, every read below is CROSS-CHECKED before it is used: an item must
// resolve as an ARMO record, its 3D must be a node of THEIR scene graph, and a
// worn shape must reach it by its own parent chain.
constexpr std::uintptr_t kActor_biped      = 0x268;
constexpr std::size_t    kActor_bipedSpan  = 0x270;
// BipedAnim / skse64's Biped (0x2778 bytes both):
//   clib RE/B/BipedAnim.h  root 0008, objects[kTotal] 0010; sizeof 0x2778
//        RE/B/BipedObjects.h  kTotal = 42
//   skse64 GameFormComponents.h "NiNode * root; // 08", "Data unk10[42]; // 10",
//        offsetof(Biped, unk10) == 0x10, sizeof == 0x2778
// BIPOBJECT / Biped::Data (0x78 both):
//   clib BipedAnim.h "TESForm* item; // 00", "NiPointer<NiAVObject> partClone; // 20",
//        sizeof 0x78
//   skse64 GameFormComponents.h "TESForm* armor; // 00 - Can be ARMO or ARMA",
//        "NiAVObject* object; // 20", unk28[(0x78 - 0x28) >> 3] -> 0x78
constexpr std::uintptr_t kBiped_root      = 0x08;
constexpr std::uintptr_t kBiped_objects   = 0x10;
constexpr std::size_t    kBiped_count     = 42;
constexpr std::size_t    kBiped_size      = 0x2778;
constexpr std::size_t    kBipObj_stride   = 0x78;
constexpr std::uintptr_t kBipObj_item     = 0x00;
constexpr std::uintptr_t kBipObj_partClone= 0x20;
// TESObjectARMO (0x228 both: clib TESObjectARMO.h, skse64 GameObjects.h):
//   TESFullName at 030       clib TESObjectARMO.h;  skse64 GameObjects.h
//     its BSFixedString at +08: clib TESFullName.h; skse64 GameFormComponents.h
//                                                               -> name char* at 0x38
//   BGSBipedObjectForm at 1B0 clib;              skse64
//     its BOD2 at +08 (clib BGSBipedObjectForm.h; skse64 GameFormComponents.h),
//     slot mask +0, armour type +4 (clib; skse64)
//                                                               -> 0x1B8, 0x1BC
//   BGSKeywordForm at 1D8    clib;               skse64
//     keywords +08, numKeywords +10 (as kWEAP_keywords above)  -> 0x1E0, 0x1E8
constexpr std::uintptr_t kARMO_name        = 0x38;
constexpr std::uintptr_t kARMO_slotMask    = 0x1B8;
constexpr std::uintptr_t kARMO_armorType   = 0x1BC;
constexpr std::uintptr_t kARMO_keywords    = 0x1E0;
constexpr std::uintptr_t kARMO_numKeywords = 0x1E8;
constexpr std::size_t    kARMO_size        = 0x228;
// The armour type: clib BGSBipedObjectForm.h ArmorType { kLightArmor,
// kHeavyArmor, kClothing }; skse64 GameFormComponents.h { kWeight_Light = 0,
// kWeight_Heavy, kWeight_None }.
constexpr std::uint32_t  kArmorType_Light    = 0;
constexpr std::uint32_t  kArmorType_Heavy    = 1;
constexpr std::uint32_t  kArmorType_Clothing = 2;
// Slot-mask bits (slot N is bit N-30): clib BGSBipedObjectForm.h and
// skse64 GameFormComponents.h agree bit for bit -- Hair 1<<1, Amulet
// 1<<5, Ring 1<<6, LongHair 1<<11, Ears 1<<13.
constexpr std::uint32_t  kSlot_Hair     = 1u << 1;
constexpr std::uint32_t  kSlot_Amulet   = 1u << 5;
constexpr std::uint32_t  kSlot_Ring     = 1u << 6;
constexpr std::uint32_t  kSlot_LongHair = 1u << 11;
constexpr std::uint32_t  kSlot_Ears     = 1u << 13;
// BSDismemberSkinInstance (0xA0 both): numPartitions at 0x88, the partition
// array at 0x90, four bytes an entry --
//   clib RE/B/BSDismemberSkinInstance.h (numPartitions 00, partitions 08 of
//        the runtime block at RelocateMember(this, 0x88, ...)) and the
//        entry's "std::uint16_t slot; // 2"
//   skse64 NiGeometry.h numPartitions 88, partitionFlags 90 (UInt32 each)
// The slot's MEANING (the body-part number, 30..61 for a biped slot) is clib's
// alone; it is used only when a shape's parent chain names no biped item, and
// only for a value in 30..61.
constexpr std::uintptr_t kDSI_numPartitions = 0x88;
constexpr std::uintptr_t kDSI_partitions    = 0x90;
constexpr std::size_t    kDSI_span          = 0xA0;
constexpr std::uintptr_t kDSIPart_slot      = 0x02;

}  // namespace fact
