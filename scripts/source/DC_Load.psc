Scriptname DC_Load extends ReferenceAlias
{THE ONE THING PAPYRUS CANNOT LEARN ANY OTHER WAY: a save was loaded.

 Field report: an NPC's decals and voxelisation survived a save load within
 the same game session. The voxelisation half is FleshCore's
 and is fixed in its DLL. This is the decal half.}

; AND THIS SCRIPT IS THE PATH THAT DOES NOT WORK ON AN EXISTING SAVE.
;
; It was added as a new ReferenceAlias on DC_Quest, and OnPlayerLoadGame
; fired EXACTLY ZERO TIMES across a whole test run. The reason is not
; the script: a quest that is already running in a save has its alias set
; frozen, and an alias added to it afterwards is never instantiated. Nothing
; that lives on an alias of DC_Quest can ever run on a save that predates the
; alias.
;
; So it is no longer the mechanism. FleshCore's DLL now stamps a counter on
; every load and FL_Watch -- a quest script that HAS been ticking in that save
; since the day it was installed -- notices the stamp change and calls
; DC_Api.StripAll(). This alias is kept because it is the right and cheap
; mechanism on a save that was started with it present, and because both routes
; end in the same idempotent function: whichever of them arrives first strips
; the actors and empties the list, and the other finds nothing to do.

DC_Core Property Core = None Auto
{Unused, and kept because removing a property from a script that is already in
 a save is how a load-time error gets printed forever. The list lives in a file
 now -- see DC_Api's own note on why a FormList was the wrong place.}

Event OnPlayerLoadGame()
    ; ONE PASS, AND NO ForgetMarks. Whoever has 3D at this instant is dealt
    ; with; the ten-second window that catches the rest belongs to FL_Watch,
    ; which is the route that actually runs on an existing save. If FleshCore is
    ; not installed at all, one pass is still better than none.
    Debug.Trace("[DecalCore] alias saw the load: stripped " + DC_Api.StripAll() + " layer(s)")
EndEvent
