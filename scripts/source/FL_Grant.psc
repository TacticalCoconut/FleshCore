Scriptname FL_Grant extends Quest
{Start-game enabled. Hands the player the Flense spell once, and tells
 FleshCore.dll where this plugin landed in the load order.

 The DLL derives every other record's full FormID from this quest's, and then
 validates each one against the live form table before it will arm -- so a
 stale file after a load-order change disarms cleanly instead of writing over
 somebody else's records.}

FormList Property SpellList Auto

Event OnInit()
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.ids.txt", "" + Self.GetFormID(), false, false)
EndEvent

Function Grant()
    Actor player = Game.GetPlayer()
    If !player || !SpellList
        Return
    EndIf
    Int i = 0
    Int n = 0
    While i < SpellList.GetSize()
        Spell s = SpellList.GetAt(i) as Spell
        If s && !player.HasSpell(s)
            player.AddSpell(s, false)
            n += 1
        EndIf
        i += 1
    EndWhile
    If n > 0
        Debug.Notification("[FleshCore] " + n + " spell(s) added")
    EndIf
EndFunction
