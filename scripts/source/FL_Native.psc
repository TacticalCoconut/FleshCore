Scriptname FL_Native Native Hidden
{In-memory SKSE native bridge exposed by FleshCore.dll.
 Every actor lookup takes the actor's raw 32-bit FormID (from GetFormID()),
 preserving bit 31 for dynamic 0xFF...... actors.
 Part indices aiPartIdx are 1..15 (matching FL_Api.PartBit).}

Bool Function IsReady() Global Native
Int Function GetPresetId() Global Native
Int Function GetPresetBase() Global Native
Bool Function GetBloodSplatter() Global Native
String Function GetVersionString() Global Native

String Function PopWoundBatch() Global Native
String Function PopEvent() Global Native
String Function PopDressLine() Global Native
String Function PopReviveLine() Global Native

Bool Function HasBody(Int aiActorFid) Global Native
Bool Function IsBuiltWhole(Int aiActorFid) Global Native
Int Function GetWoundedCellCount(Int aiActorFid) Global Native
Bool Function IsDismembered(Int aiActorFid) Global Native
Int Function GetPartsLostMask(Int aiActorFid) Global Native
Int Function GetPartsBornMask(Int aiActorFid) Global Native
Float Function GetPartIntegrityPct(Int aiActorFid, Int aiPartIdx) Global Native
Int Function GetPartLayersGoneMask(Int aiActorFid, Int aiPartIdx) Global Native
Float Function GetOwnFillFrac(Int aiActorFid) Global Native
Bool Function HasSkullFill(Int aiActorFid) Global Native
String Function GetBodyRemainStr(Int aiActorFid) Global Native
Int Function GetBloodSplatterPct() Global Native
Function SetBloodSplatterPct(Int aiPct) Global Native
Int Function GetFodderOverkillPct() Global Native
Function SetFodderOverkillPct(Int aiPct) Global Native
Function SetOverkillBonusPct(Int aiPct) Global Native
