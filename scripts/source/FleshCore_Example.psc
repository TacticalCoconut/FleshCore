Scriptname FleshCore_Example extends Quest
{THE EXAMPLE CONSUMER. Two hundred lines that do one useful thing end to end, and
 the thing every developer copies before reading a word of documentation.

 This is a consumer's pattern -- the only third-party-shaped consumer FleshCore has
 ever had -- written down against FL_Api: gate on presence, gate on armed,
 gate on eligibility, act, listen for the answer, fall back at every step.
 It compiles beside the reference so it cannot rot.

 SOFT DEPENDENCY. This script names FL_Api, and FL_Api.pex ships with
 FleshCore. On a machine without FleshCore the calls below never run because
 IsInstalled() is asked FIRST and the plugin file test needs no script at all.
 Do NOT declare a FleshCore Form as a property and do NOT add FleshCore.esp
 as a master -- neither is needed, and either makes the dependency hard.}

Event OnInit()
    ; Listen for wounds. The registration is per-session, so it is made here
    ; and again on every load (OnPlayerLoadGame on a player alias, or your
    ; own load detection). The event's sender is the victim themselves.
    RegisterForModEvent("FleshCore_Wound", "OnFleshCoreWound")
EndEvent

Function TakeThemApart(Actor target)
    {What a mod calls when it wants FleshCore to do the work, with a fallback
     for every way FleshCore can say no.}
    If !Game.IsPluginInstalled("FleshCore.esp")
        Debug.Trace("[Example] no FleshCore -- doing it the old way")
        Fallback(target)
        Return
    EndIf
    If !FL_Api.CoreActive()
        ; The DLL loads a second or two after the save. A mod that fires in
        ; the first frames should wait or fall back, not fail.
        Debug.Trace("[Example] FleshCore installed but not armed yet -- fallback")
        Fallback(target)
        Return
    EndIf
    If !FL_Api.Targetable(target)
        Debug.Trace("[Example] FleshCore will not take them (reason " + FL_Api.WhyRefused(target) + ") -- fallback")
        Fallback(target)
        Return
    EndIf
    ; Ask before using anything optional. "wound" is in every build that has
    ; FL_Api at all; a token that is NOT there is a feature this build lacks.
    If !FL_Api.Has("wound")
        Fallback(target)
        Return
    EndIf
    If FL_Api.Wound(target, "decapitate")
        Debug.Trace("[Example] asked FleshCore to behead " + target + " -- the FleshCore_Wound event says what happened")
    Else
        Fallback(target)
    EndIf
EndFunction

Event OnFleshCoreWound(String eventName, String strArg, Float numArg, Form sender)
    {sender is the victim. strArg is '|'-separated and only ever grows at the
     end, so read it by index with FL_Api.Field and never split it yourself:
       0 flags     bit 0 set = they come apart (a kill unless FleshCore is
                   holding their death), bit 1 = the trunk, bit 11 (2048) =
                   they WOULD have died and a never-kill rule said no
       1 pieces    how many pieces were forged
       2 severed   how many separate sections they are in now}
    Actor target = sender as Actor
    If !target
        Return
    EndIf
    Int flags = FL_Api.Field(strArg, 0) as Int
    Bool comesApart = (flags % 2) == 1
    Debug.Trace("[Example] FleshCore wounded " + target + ": pieces=" + FL_Api.Field(strArg, 1) \
        + " sections=" + FL_Api.Field(strArg, 2) + " fatal=" + comesApart)
EndEvent

Function ProtectMyCompanion(Actor target, Bool on)
    {THE REGISTRY. A rule is a line any mod may write: a key, a value,
     your caller id, a priority. `immune` is any-true-wins, so no other mod can
     un-protect them; scalar keys go to the highest prio. Rules live for the
     session -- set them when your scene starts, clear them when it ends.}
    If !Game.IsPluginInstalled("FleshCore.esp") || !FL_Api.Has("registry")
        Return
    EndIf
    If on
        FL_Api.SetInt(target, "immune", 1, "Example")
        FL_Api.SetInt(target, "losslimb", 3, "Example", 10)   ; if they are ever un-immuned: three limb parts before they die
    Else
        FL_Api.ClearKey(target, "immune", "Example")
        FL_Api.ClearKey(target, "losslimb", "Example")
    EndIf
EndFunction

Function MakeThemFragile(Actor target, Bool on)
    {THE TRIGGER TABLE. A row is a rule about BLOWS: what swung, how
     hard, and the wound it opens. This one says a slash of 15 % of their health
     or more cuts them -- for them alone, above FleshCore's own 25 % default,
     because prio 0 outranks the config's -1. Scope None would say everyone.}
    If !Game.IsPluginInstalled("FleshCore.esp") || !FL_Api.Has("trig")
        Return
    EndIf
    If on
        Int id = FL_Api.AddTrigger("Example", target, "slash", "pct", 15.0, "slabz", 5.0, 3)
        Debug.Trace("[Example] trigger row " + id + " registered for " + target)
    Else
        FL_Api.ClearTriggers("Example")
    EndIf
EndFunction

Function SayWhy(Actor target)
    {WhyNot: one word for a log line, so a scene that fell back can
     say why without a debugger. `ok` is the only word that means yes.}
    If Game.IsPluginInstalled("FleshCore.esp") && FL_Api.Has("whynot")
        Debug.Trace("[Example] FleshCore on " + target + ": " + FL_Api.WhyNot(target))
    EndIf
EndFunction

Function TakeTheirLeg(Actor target)
    {A COMMAND: one named part, one form, no record in the
     plugin. Answered by FL_Done on them (result 0 = done, detail = cells) and
     by FL_Wounded before that. WoundAt takes a world point instead.}
    If !Game.IsPluginInstalled("FleshCore.esp") || !FL_Api.Has("cmd")
        Fallback(target)
        Return
    EndIf
    Int ticket = FL_Api.WoundPart("Example", target, "slabz", 5.0, 3, "lthigh", "centre")
    Debug.Trace("[Example] asked for their left thigh -- ticket " + ticket + " (" + FL_Api.CodeName(ticket) + ")")
EndFunction

Event OnFLDone(String eventName, String strArg, Float numArg, Form sender)
    {FL_Done: verb|caller|result|detail, numArg the ticket, sender the target.
     Register it in OnInit beside FleshCore_Wound if you want the answers.}
    If FL_Api.Field(strArg, 1) == "Example"
        Debug.Trace("[Example] ticket " + (numArg as Int) + " " + FL_Api.Field(strArg, 0) + " -> result " \
            + FL_Api.Field(strArg, 2) + " (" + FL_Api.Field(strArg, 3) + ")")
    EndIf
EndEvent

Function WatchTheirWounds(Bool on)
    {THE ENGINE'S OWN EVENT: FL_Wounded carries what a wound took,
     part by part, and where. See OnFLWounded below.}
    If on
        RegisterForModEvent("FL_Wounded", "OnFLWounded")
        RegisterForModEvent("FL_Done", "OnFLDone")
    Else
        UnregisterForModEvent("FL_Wounded")
        UnregisterForModEvent("FL_Done")
    EndIf
EndFunction

Event OnFLWounded(String eventName, String strArg, Float numArg, Form sender)
    {origin|form|caller|cellsTaken|layers|partsTouched|partsRemain|partsLostMask|flags|x,y,z}
    Actor target = sender as Actor
    If !target
        Return
    EndIf
    String remain = FL_Api.Field(strArg, 6)
    Debug.Trace("[Example] " + target + " lost " + FL_Api.Field(strArg, 3) + " cell(s) of them " + FL_Api.Field(strArg, 5) \
        + " to a " + FL_Api.Field(strArg, 1) + " from " + FL_Api.Field(strArg, 2) + "; left thigh at " \
        + FL_Api.PartRemaining(remain, "lthigh") + "%")
EndEvent

Function WhenTheSceneEnds()
    {A SCENE RULE: when a the scene framework scene with a creature ends,
     detonate the victim. One line, no listener of your own.}
    If Game.IsPluginInstalled("FleshCore.esp") && FL_Api.Has("scenes")
        Int id = FL_Api.AddSceneRule("Example", "end", "creature", "", "victim", "detonate")
        Debug.Trace("[Example] scene rule " + id)
    EndIf
EndFunction

Function Fallback(Actor target)
    {Whatever your mod did before FleshCore existed. a consumer hands them to the
     Dismembering Framework here; a simpler mod just kills them.}
    target.Kill(None)
EndFunction
