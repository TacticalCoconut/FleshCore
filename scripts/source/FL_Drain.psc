Scriptname FL_Drain extends ActiveMagicEffect
{VOXEL DRAIN: the vampire drains voxels gradually
 over the feed. This script rides on FL_VoxelDrain_Effect (0x94B), a copy of
 the vampire's own drain -- same beam, same absorb of health, same keyword --
 and it does ONE thing: it tells the engine when the feed ENDS.

 The feed itself is the DLL's. The effect's apply reaches the DLL's magic sink
 before any script runs, the sink finds the effect's DR row in FleshCore.cfg.txt
 and arms a drain on them: so many cells a second, taken as one bite a second at
 the row's anchor, for up to the row's seconds after the last apply. A
 concentration spell applies for as long as the caster holds the key, so the
 clock is pushed on each apply and the drain runs while the beam is on them.
 Papyrus is not on that path and adds nothing to it -- what it alone knows is
 the moment the beam comes OFF them, which is this effect's OnEffectFinish: the
 caster let go, or they died, or the effect was dispelled. StopDrain then ends
 the feed at once rather than letting the row's seconds run down on a target
 nobody is feeding on.

 Nothing here holds a form: the engine is reached through FL_Api's command
 file like any other caller, under FleshCore's own name.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    If akTarget
        Debug.Trace("[FleshCore] Voxel Drain: the feed on " + akTarget.GetDisplayName() + " begins")
    EndIf
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    If !akTarget
        Return
    EndIf
    Int t = FL_Api.StopDrain("FleshCore", akTarget)
    Debug.Trace("[FleshCore] Voxel Drain: the feed on " + akTarget.GetDisplayName() + " ends (ticket " + t + ")")
EndEvent
