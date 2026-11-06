Scriptname FL_Grind extends ActiveMagicEffect
{GRIND DOWN. They are taken apart a lattice row at a time, from the soles up.

 The whole progression lives in the DLL's `grind` wound form, which ignores
 the aim entirely and takes the LOWEST surviving row of their lattice -- the
 same licence the `halve` form already takes to read a height out of their own
 anatomy rather than out of where the spell landed. One application is a slice
 off their feet. The row it removes is the row that was holding up the next one,
 so the following application finds a new lowest row and takes that.

 Which means this script does not track progress and could not get it wrong.
 There is no height to carry, no part list to walk, no state that a save could
 catch halfway. It counts to Ticks and stops; the lattice is the marker.

 The tick spell is Self-delivery and cast BY THEM: the grind never consults the
 aim, so the caster only has to be somebody, and making it them keeps the whole
 effect inside the one actor it belongs to. It is deliberately not in
 FL_SpellList -- the player must never find it in the Magic menu.

 WHY IT USED TO STOP AT THE WAIST, AND WHAT HOLDS IT OPEN NOW.
 ------------------------------------------------------------------------
 Field report: Grind Down stopped at the waist and needed a recast to continue.
 Not a coincidence and not a budget: the waist is roughly where the rows taken
 so far are enough to kill them, and A MAGIC EFFECT ENDS WHEN ITS TARGET DIES.
 The engine dispels their active effects on death, OnEffectFinish fires, and the
 handler below sets `left = 0` and unregisters -- exactly as written. The tick
 loop was doing its job right up to the instant the thing it lived inside
 ceased to exist. A recast starts a new effect on the corpse, which is why a
 recast continued it.

 So the fix is not in the loop. It is to stop them dying until the loop is
 done, and the mechanism is the one FL_GrindMe already uses on the player:
 StartDeferredKill. Vanilla holds Harkon and Miraak in exactly this state
 while a scene plays -- DLC1dunHarkonBossBattle and DLC2MQ06MiraakBossBattle
 -- and while it is on, every kill on the actor is absorbed, including
 FL_Watch's own "they have lost too much, kill them". They are dead in every way
 that matters and not dead in the one way that would end this effect.

 THE INVULNERABILITY IS A DEBT, and Actor.psc says so outright: "Be sure to
 call EndDeferredKill or the actor will be invulnerable." An NPC left holding
 one is a permanently unkillable NPC in a kept save. So it is
 released from THREE independent places -- the last row, OnEffectFinish, and
 a hard deadline that does not depend on the tick loop running at all -- and
 `deferred` makes releasing it twice harmless. This is the same three-way
 discipline FL_GrindMe carries, for the same reason.}

Spell Property Tick Auto
{FL_GrindTick_Spell. Its magic effect is the one carrying the `grind` W row.}

Int Property Ticks = 24 Auto
{How many rows to take at most. At 6.0 units a row and a target about 120 units
 tall, twenty-four rows is more than the whole body -- which is the point:
 the spell should finish them rather than stop at their waist. It ends early on
 its own when there is nothing left to take.}

Float Property Interval = 0.35 Auto
{Seconds between rows. Slow enough to read as grinding rather than as one
 blow; fast enough that Ticks rows fit inside the effect's own duration.}

Bool Property UseForceRagdoll = true Auto
{ObjectReference.ForceAddRagdollToWorld -- puts their ragdoll into the physics
 world. Takes no arguments, so it cannot throw them.}

Float Property PushSelf = 1.0 Auto
{PushActorAway force applied to them BY THEMSELVES, or 0 for off.

 THEY KEPT STANDING UP. At first the grind stopped
 when they died, so they never had the chance. Then they were held alive with
 StartDeferredKill so the grind could finish -- correct, and it turned them into
 a live actor being hurt, who does what a live actor does: gets back on their
 feet, over and over, while their legs are being taken off. Field report: the target
 being ground down tried repeatedly to get up during the grind.

 This is FL_GrindMe's Collapse chain, which the player already had and
 the victim never had at all. Used self-to-self by Bethesda:
 DLC2CycloneEffectScript.psc calls `Target.PushActorAway(Target, Force)`.
 1.0 is what FL_Watch.Dismember uses on every victim it ragdolls.}

Float Property RagdollImpulse = 3.0 Auto
{The nudge that wakes the ragdoll once it is in the world, on the FIRST
 collapse only. Half of FL_Watch's tested 6.0.}

Bool Property Quiet = true Auto
{Keep the grind a crime nobody reports. 

 WHY THIS IS NEEDED. Field report: Grind Down gave the player a
 bounty. No other spell in this mod does, and the records are not the
 reason -- FL_GrindDown_Effect carries exactly the flags every wound effect
 carries (NoDeathDispel, NOT Hostile) and those raise no alarm at all.

 What is different is BEHAVIOUR, and it arrived in three steps.
 Every other spell kills them on the first blow, unattributed: FL_Watch.Dismember
 calls Kill() with no argument precisely so there is "no bounty, no aggro, no
 witnesses turning on the player". The grind cannot do that -- it was given
 StartDeferredKill so it could finish before the death cam, which means they are
 ALIVE for the whole ten seconds. Then FL_Grind was given the collapse chain
 and then it fired every row. So a living, named NPC is now knocked to the
 floor once a third of a second, in front of whoever is standing there, and
 PushActorAway is the one call in that chain the engine treats as physical
 interference -- vanilla only ever issues it from hostile shouts.

 THE COUNTER IS ALREADY IN THIS MOD. FL_Decal carries it,
 for the same shape of problem: the effect is non-Hostile, but
 a projectile landing on someone still starts a fight, and it answers with
 StopCombatAlarm + StopCombat on the target. That is what runs here, at the
 start, on every row, and once more after the death.

 UNPROVEN: that the push is what the engine scores. What is
 certain is that the bounty comes with the window in which they
 are alive and being handled, and that this is the mod's own proven answer to
 "something non-Hostile started a fight anyway". It does not stop the bounty alone,
 so OnEffectStart also sets their crime faction to None while Quiet is on -- which works by removing
 their ability to report at all, and is a debt that has to be given back.}

Float Property Deadline = 20.0 Auto
{Seconds after which the hold is released no matter what. Longer than
 Ticks * Interval with room to spare, and it exists only so that a tick loop
 which somehow stops -- a save reloaded mid-grind, a script latency spike, a
 cell unloading under them -- cannot leave them invulnerable for the rest of the
 save. It is checked FIRST in OnUpdate and unconditionally, so it still holds
 if every other branch below is wrong about something.}

Actor victim
Int   left = 0
Int   took = 0
Bool  deferred = false
Bool  pinned   = false
Faction crimeWas = None
Bool  crimeHeld = false
Float started = 0.0

Event OnEffectStart(Actor akTarget, Actor akCaster)
    victim = akTarget
    left = Ticks
    took = 0
    If !victim || !Tick
        ; Log it rather than doing nothing silently: a missing property here is
        ; a plugin that was rebuilt without its script wiring, and the symptom
        ; -- a spell that flies, hits, and produces absolutely nothing -- gives
        ; no hint at all on its own.
        Debug.Trace("[FleshCore] Grind Down: no " + "victim/tick spell, nothing to do")
        Return
    EndIf
    started = Utility.GetCurrentRealTime()
    ; ORDER MATTERS: the hold goes on BEFORE the first row is taken, because
    ; the first row is what starts them dying.
    victim.StartDeferredKill()
    deferred = true
    ; PINNED, so there is no attempt to answer. Released in Release(),
    ; before the kill, or they cannot fall over.
    victim.SetDontMove(true)
    pinned = true
    ; ---- AND THEY CANNOT REPORT IT ---------------------------------
    ;
    ; Hush() alone did not hold: in testing, grinding still
    ; placed a bounty. StopCombatAlarm stops combat and alarms AGAINST
    ; this actor, and the bounty is scored against the PLAYER -- so it was
    ; aimed the wrong way round, the same mistake
    ; in shape as the PushActorAway one caught earlier.
    ;
    ; GetCrimeFaction is "the faction this actor reports crimes to", so
    ; taking it away for the length of the grind removes the reporting
    ; rather than trying to quiet the report. A DEBT like every other hold
    ; in this file: the original is kept and given back in Release(), on
    ; every exit including the early ones. An actor left with no crime
    ; faction is an actor nobody can commit a crime against for the rest
    ; of the save, which would be a far worse bug than the one it fixes.
    If Quiet
        crimeWas = victim.GetCrimeFaction()
        crimeHeld = true
        victim.SetCrimeFaction(None)
    EndIf
    Hush()
    Collapse(true)
    RegisterForSingleUpdate(Interval)
EndEvent

Event OnUpdate()
    If deferred && (Utility.GetCurrentRealTime() - started) > Deadline
        Debug.Trace("[FleshCore] Grind Down: deadline reached -- releasing the hold")
        left = 0
        Release()
        Return
    EndIf
    If left <= 0 || !victim
        Release()
        Return
    EndIf
    ; STOP WHEN THEY ARE GONE RATHER THAN GRINDING AIR. A fully stripped body
    ; still exists as a reference; the tick would keep firing, the DLL would
    ; find no live row and return nothing, and the log would fill with wounds
    ; that took no cells.
    If victim.IsDisabled() || victim.IsDeleted()
        left = 0
        Release()
        Return
    EndIf
    left -= 1
    took += 1
    ; EVERY ROW, NOT EVERY THIRTEENTH.
    ;
    ; FL_GrindMe re-asserted its ragdoll every 13 rows, on a number calibrated
    ; when a grind took forty-odd ticks. A higher per-tick cell cap later
    ; made the whole grind finish in a dozen or so, so 13 bought exactly two
    ; collapses -- which in play was ragdoll, try to get up,
    ; ragdoll again, get up again, and the Papyrus log shows precisely two
    ; collapse lines, four seconds apart.
    ;
    ; Re-asserting every row is safe because of what the chain is made of: the
    ; impulse -- the only part that can accumulate into a launch -- is carried
    ; by the FIRST collapse alone, and a knockdown on a body already on the
    ; floor is absorbed by the floor. Re-inserting a ragdoll that is already in
    ; the world costs nothing.
    Collapse(false)
    Hush()
    Tick.Cast(victim, victim)
    If left > 0
        RegisterForSingleUpdate(Interval)
    Else
        ; THE LAST ROW HAS BEEN TAKEN -- SO THEY DIE NOW, ON THIS TICK. The old
        ; spare tick was reasoned about draining the wound file and it cost the
        ; death: a third of a second is long enough to stand up in. FL_Watch's
        ; poll drains the file on its own schedule and outlives this effect.
        Release()
    EndIf
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    ; The effect's duration is the outer bound. If it runs out first the
    ; grinding stops there, which is right: the magic ended.
    ; It is also the second of the three ways the hold gets released -- and
    ; the one that fires if they somehow die anyway.
    Release()
EndEvent

Function Release()
    {Let the death that has been owed since the first row actually land.}
    UnregisterForUpdate()
    left = 0
    ; THE PIN COMES OFF ON EVERY EXIT, including the ones that return early.
    ; SetDontMove is a debt in exactly the way the deferred kill is, and an
    ; actor left holding one stands rooted to the spot for the rest of the save.
    If pinned && victim
        pinned = false
        victim.SetDontMove(false)
    EndIf
    ; The crime faction goes back before anything else can return.
    If crimeHeld && victim
        crimeHeld = false
        victim.SetCrimeFaction(crimeWas)
    EndIf
    If !deferred || !victim
        Return
    EndIf
    deferred = false
    victim.EndDeferredKill()
    ; AND KILL THEM EXPLICITLY -- but only if this spell actually took anything.
    ; EndDeferredKill releases the state; whether a kill absorbed while it was
    ; on is replayed afterwards is undocumented, and
    ; a target left standing with no legs would be a
    ; worse outcome than a redundant Kill() on somebody the engine already
    ; considers dead. The `took` guard is what stops a spell that ended before
    ; its first row -- a dispel, a cell change -- from killing someone it never
    ; touched.
    ; PAST THE DEFEAT FRAMEWORK. Acheron converts a death into defeat --
    ; bleeding out, immune, ALIVE -- which is why the player got up without
    ; a body and why a skull spell alone did not kill. DisableProcessing is
    ; Acheron's own switch for this and it is global, so it is held for one
    ; call with nothing between that can return early, and the result is
    ; checked afterwards.
    If took > 0 && !victim.IsDead()
        Bool guarded = Game.IsPluginInstalled("Acheron.esm")
        If guarded
            Acheron.DisableProcessing(true)
        EndIf
        victim.Kill()
        If guarded
            Acheron.DisableProcessing(false)
            If Acheron.IsDefeated(victim)
                Debug.Trace("[FleshCore] grind: still DEFEATED after the kill")
            EndIf
        EndIf
    EndIf
    ; AND ONCE MORE AFTER THE DEATH. The kill itself is unattributed, but the
    ; ten seconds before it were not silent, and an alarm already raised does
    ; not clear itself because its subject stopped moving.
    Hush()
EndFunction

Function Hush()
    {Stop anyone treating this as an assault. Cheap enough to run every row, and
     it has to: a witness who arrives on row nine is as good at reporting it as
     one who was there for row one.}
    If Quiet && victim
        victim.StopCombatAlarm()
        victim.StopCombat()
    EndIf
EndFunction

Function Collapse(Bool nudge)
    {Put them on the floor and keep them there. FL_GrindMe's chain, verbatim, for
     the victim rather than the player -- see PushSelf's note for why they need
     one at all now.


     WHY THEY WERE STANDING UP DEAD, AND WHY THEY KEPT TRYING TO RISE.
     ------------------------------------------------------------------
     Field report: an NPC killed by Grind Down was dead, and their body could be
     searched, but they were standing up with their head playing an idle
     animation as if they were still alive. And the player still TRIED to
     get up, and once the body was gone, got up and did not die.

     Both come from the same root. StartDeferredKill keeps them ALIVE -- that is
     its whole purpose, and it is what lets the grind finish before the death
     cam starts. A live actor whose ragdoll is in the world will always try to
     stand again: that is the animation graph doing its job, and knocking them
     down once per row is fighting the symptom.

     Worse, the thing doing the knocking was making the corpse. NOT ONE of
     Skyrim's own scripts calls ForceAddRagdollToWorld (FL_GrindMe notes the
     same) -- and yet the grind began calling it every 0.22 seconds, a dozen
     times in a row. An animation graph re-entered into ragdoll that often has
     no clean transition left to a death, which is what "dead,
     searchable, standing in an idle" looks like.

     Three measures, each answering one of the two symptoms:

       1. ForceAddRagdollToWorld fires ONCE, on the first collapse. It is the
          insertion that gives the impulse something to act on; it does not
          need repeating and repeating it is what broke the death.
       2. SetDontMove(true) holds them for the length of the grind. It is
          Bethesda's own way to pin an actor -- DLC2_SF_DLC2MQ02MiraakApocryp
          calls SetDontMove(true) on the dragon to hold it through a scene --
          and unlike a knockdown it removes the ATTEMPT rather than answering
          it: they must not get the chance even to
          ATTEMPT to get up.
       3. The death lands on the SAME tick as the last row. The old loop spent
          one more Interval before releasing, and that spare third of a second
          is the window they used to stand up in.

     SetDontMove IS A DEBT, exactly like the deferred kill, and it is released
     in the same three places and before the kill -- a pinned actor cannot fall
     over, so releasing it after Kill() would leave the corpse standing for the
     opposite reason.

     THE ORDER IS THE POINT. ForceAddRagdollToWorld gives the impulse something
     to act on: an impulse on an actor whose ragdoll is not in the world is
     absorbed by the animation graph, one on an actor whose ragdoll IS in the
     world is physics.}
    If !victim
        Return
    EndIf
    ; ONCE, ON THE FIRST COLLAPSE ONLY -- see the note on Collapse.
    If nudge && UseForceRagdoll
        victim.ForceAddRagdollToWorld()
    EndIf
    If PushSelf > 0.0
        victim.PushActorAway(victim, PushSelf)
    EndIf
    If nudge && RagdollImpulse > 0.0
        victim.ApplyHavokImpulse(0.0, 0.0, 1.0, RagdollImpulse)
    EndIf
EndFunction
