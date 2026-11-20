// blobs.h -- SHIPPING BYTES.
//
// Four blocks copied verbatim out of a working, loose body-part mesh
// (Dismembering Framework's Female_Forearm_L.nif), because the
// safest way to be certain a physics body or a shader block is well formed is
// to use one the game already loads:
//
//   kTplRigidBody   250B  bhkRigidBody. mass is a float at +180, the inertia
//                         tensor a 3x4 matrix at +116 (identity here). Every
//                         other field -- damping, friction, restitution, the
//                         motion/quality/layer bytes -- is left exactly as it
//                         ships, because those are the numbers that make a
//                         dropped limb behave like a dropped limb.
//                         Fingerprinted before use: maxAngularVelocity reads
//                         31.57 at +216, which is the value the format
//                         documents there, so the whole layout is anchored.
//                         CHANGED FROM DF'S FOREARM: the two layer
//                         bytes below (+4 HavokFilter.layer and its stale copy
//                         at +36) are 32, DEADBIP, in DF's forearm, and with that
//                         every forged piece
//                         collides with living and ragdolled actors, and pieces
//                         shoot out of NPCs in play. Both are
//                         19, L_DEBRIS_SMALL, here -- the layer Skyrim's own COLL
//                         records (55 of them, read out of Skyrim.esm) reserve
//                         for physics debris spawned on top of actors: it
//                         collides with static geometry and the ground and with
//                         nothing that walks. Severed sections take these bytes
//                         as they stand; shards overwrite +4 in chunknif.cpp.
//   kTplHullHead     32B  the material / radius / unknown6 head of a
//                         bhkConvexVerticesShape, up to the vertex count.
//   kTplShaderSkin  112B  BSLightingShaderProperty, TYPE 5 (skin tint),
//                         model-space normals set. 112 bytes, not 100.
//   kTplShaderDefault 100B BSLightingShaderProperty, TYPE 0. 100 bytes.
//
// THE TWO SHADER BLOCKS ARE BOTH HERE FOR A REASON. Their lengths differ
// because type 5 carries a skin-tint tail that type 0 does not. Writing a
// type-0 header into a 112-byte block leaves twelve bytes the reader never
// consumes, and the file will not load at all -- silently, with nothing
// spawned and nothing logged. So the type stamped in the block and the block
// actually used must always be the same one.
#pragma once
static const unsigned char kTplRigidBody[250] = {2,0,0,0,19,0,0,0,250,0,0,0,1,10,0,0,0,0,0,0,0,0,0,0,0,0,0,128,1,0,0,0,46,0,46,0,19,0,0,0,42,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,160,65,205,204,204,61,205,204,76,61,0,0,128,63,0,0,128,63,0,0,0,63,0,0,0,0,205,204,204,62,205,204,208,66,92,143,252,65,205,204,76,61,3,1,2,4,0,0,3,0,32,0,0,0,108,0,117,0,101,0,0,0,0,0,0,0,0,0};
static const unsigned char kTplHullHead[32] = {219,173,81,177,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,0,0,0,0,0,0,0,0,0,0,0,128};
static const unsigned char kTplShaderSkin[112] = {5,0,0,0,255,255,255,255,0,0,0,0,255,255,255,255,3,19,96,130,33,128,0,2,0,0,0,0,0,0,0,0,0,0,128,63,0,0,128,63,32,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,3,0,0,0,0,0,128,63,0,0,0,0,0,0,240,65,0,0,128,63,0,0,128,63,0,0,128,63,0,0,64,64,205,204,204,62,0,0,0,64,0,0,128,63,0,0,128,63,0,0,128,63};
static const unsigned char kTplShaderDefault[100] = {0,0,0,0,255,255,255,255,0,0,0,0,255,255,255,255,3,3,64,130,1,128,0,0,0,0,0,0,0,0,0,0,0,0,128,63,0,0,128,63,13,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,3,0,0,0,0,0,128,63,0,0,0,0,0,0,160,66,0,0,128,63,0,0,128,63,0,0,128,63,0,0,128,63,154,153,153,62,0,0,0,64};
// TWO MORE SHIPPING BLOCKS, for the face and its hair (cfg FT), each read out
// of a working NIF in the load order and copied byte for byte:
//
//   kTplShaderFaceGen 100B BSLightingShaderProperty, TYPE 4 (FaceGen), the head
//                         block of CFTO's 0000AA06 'MaleHeadNord' FaceGen file:
//                         flags1 0x82401703 (Skinned, Model_Space_Normals),
//                         flags2 0x02008021 (Vertex_Colors, Soft_Lighting). No
//                         tail: a type-4 block is 100 bytes. A rigid piece
//                         clears Skinned and keeps Vertex_Colors only beside a
//                         colour lane (chunknif.cpp).
//   kTplShaderHair  112B  BSLightingShaderProperty, TYPE 6 (hair tint), the
//                         block of KS Hairdos' Isis.nif: flags1 0x82440303,
//                         flags2 0x00008081, no Vertex_Colors, no
//                         Vertex_Alpha. The hair colour is the last twelve
//                         bytes (+100), as in every hair, brow and beard block
//                         measured.
static const unsigned char kTplShaderFaceGen[100] = {4,0,0,0,255,255,255,255,0,0,0,0,255,255,255,255,3,23,64,130,33,128,0,2,0,0,0,0,0,0,0,0,0,0,128,63,0,0,128,63,16,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,3,0,0,0,0,0,128,63,0,0,0,0,0,0,4,66,162,161,33,63,203,194,66,63,0,0,128,63,244,40,44,64,205,204,204,62,0,0,32,65};
static const unsigned char kTplShaderHair[112] = {6,0,0,0,255,255,255,255,0,0,0,0,255,255,255,255,3,3,68,130,129,128,0,0,0,0,0,0,0,0,0,0,0,0,128,63,0,0,128,63,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,128,63,3,0,0,0,0,0,128,63,0,0,0,0,0,0,32,65,0,0,128,63,0,0,128,63,0,0,128,63,154,153,25,63,154,153,153,62,0,0,0,64,137,136,8,62,137,136,8,62,137,136,8,62};
