Scriptname FL_GrindMe extends ActiveMagicEffect
{GRIND DOWN PLAYER. They are killed, and then ground away from the soles up --
 and the game is not allowed to fade out from under it until the grinding has
 finished.

 HOW THE FADE IS HELD OFF, AND WHY IT IS THE ONLY WAY.
 ------------------------------------------------------------------------
 Once the player is REALLY dead the engine owns what happens next: the death
 cam plays and then the load menu comes up, and nothing in Papyrus or in the
 game settings can stretch that. This was checked --
 Game.psc offers only FadeOutGame, which draws a fade of its own rather than
 governing the death one, and the only death-related settings in Skyrim.esm
 are fDeathForce*, fDeathRagdoll, fDeathWaitRoot and fKillCamBaseOdds: force,
 ragdoll and whether a kill cam happens at all. Nothing about its length.

 So the fade is not delayed. It is never STARTED, until the grind wants it.

 StartDeferredKill is the engine's own answer, and vanilla uses it for exactly
 this shape of problem -- DLC1dunHarkonBossBattle and DLC2MQ06MiraakBossBattle
 both hold a boss in an unkillable state until their scene is ready. While it
 is on, every kill on the actor is held: whatever reaches them during the
 grind, on the first row or any row after it, is absorbed and goes on
 being absorbed. They are dead in every way that matters
 and not dead in the one way that would end the scene.

 EndDeferredKill then releases it, and the death that was owed lands. The cam
 and the fade happen there, after the last row, as designed.

 THE INVULNERABILITY IS A DEBT. Actor.psc says it outright: "Be sure to call
 EndDeferredKill or the actor will be invulnerable." A script that starts one
 and dies before ending it leaves the player unkillable for the rest of the
 save, which is the worst bug this file could ship. So it is released from
 THREE places -- the last tick, OnEffectFinish, and a hard deadline that does
 not depend on the tick loop running at all -- and the `deferred` flag makes
 releasing it twice harmless.}

Spell Property Tick Auto
{FL_GrindTick_Spell, the same hidden per-row wound FL_Grind uses.}

Int Property Ticks = 24 Auto
Float Property Interval = 0.35 Auto

Bool Property UseForceRagdoll = true Auto
{Use ObjectReference.ForceAddRagdollToWorld -- a ragdoll with no force argument
 at all, so it cannot throw them. See Collapse().}

Float Property RagdollImpulse = 3.0 Auto
{The nudge that wakes the ragdoll once it is in the world. 0 disables it.

 WHY A NUDGE IS NEEDED AT ALL. ForceAddRagdollToWorld puts the ragdoll body
 into the physics world; it does not follow that the body is then MOVING. A
 ragdoll inserted at rest, in the pose the animation left them in, standing on
 a floor that is already supporting it, has nothing acting on it but gravity
 it is already balanced against. An impulse is what hands it to physics.

 STRAIGHT UP, AND HALF OF THE ONLY CALIBRATED NUMBER THIS MOD HAS. FL_Watch's
 Dismember throws (0, 0, 1) at magnitude 6.0 at the player and has done since
 the start without once launching them -- that is the tested
 ceiling for this actor, so half of it is the floor of a range known to be
 safe. Up rather than down because a downward impulse on a body already
 resting on the floor is absorbed by the floor, which is the one direction
 that can be applied and do nothing.

 THE OLD KnockAreaEffect PATH IS STILL HERE, behind RagdollForce, which is
 zero. It is kept rather than deleted because it costs two lines and the
 alternative is rewriting it from scratch if the chain below turns out to
 need it.}

Float Property PushSelf = 1.0 Auto
{PushActorAway force applied to them BY THEMSELVES, or 0 for off. This is the link
 that was missing.


 Skyrim itself calls PushActorAway self-to-self. DLC2CycloneEffectScript.psc,
 shipped by Bethesda:



     Target.PushActorAway(Target, Force)

 The same actor as source and as argument -- the Cyclone shout, which visibly
 throws whoever it lands on.


 AND IT IS THE EXACT CALL THAT USED TO KNOCK THE PLAYER DOWN. FL_Watch.Dismember
 once had its arguments the wrong way round, and in testing every hit
 with a voxelising spell knocked the player to the ground -- because the
 player was the ARGUMENT, and the argument is the one that gets thrown. That bug
 is the only proven way this mod has ever put the player on the floor. It
 is now pointed at them deliberately.

 1.0 is the force Dismember uses on every victim it ragdolls, and the same 1.0
 that knocked the player down when it landed on them. It is a ragdoll trigger
 rather than a launch: the engine's own knockdown, not a throw.}

Float Property RagdollForce = 0.0 Auto
{KnockAreaEffect magnitude, or 0 for off -- and it is off.

 IT WAS TRIED AND IT DID NOT WORK. It shipped once on the strength of
 DLC1ArkngthamzRumbleTrigSCRIPT calling GetPlayer().KnockAreaEffect(0.3, 16)
 during the cave-in, and in testing the player
 was not ragdolled before being ground down.

 The reading that fits is that it is an AREA effect centred on the reference
 it is called on and knocks down the actors AROUND that reference rather than
 the reference itself -- which is consistent with the vanilla script, where
 what the rumble is meant to floor is whoever is standing in the tunnel, not
 the trigger. Left at zero and left in place.}

Float Property RagdollRadius = 16.0 Auto
{Vanilla's own radius for the player knockdown. Small enough that it is them
 and not the room -- this is an AREA effect, and a bystander standing on top
 of them would go down too.}

Int Property RagdollEvery = 1 Auto
{Re-assert the ragdoll every N rows. 0 collapses them once and no more.

 ONE, BECAUSE A LARGER NUMBER LEAVES GAPS TO RISE IN. A grind finishes
 in a dozen or so ticks,
 so a setting of thirteen
 puts them down only twice -- the
 Papyrus log has exactly two lines, four seconds apart -- and in between they
 got up. Field report: the player ragdolled, tried to get up, ragdolled
 again, and got up again.

 Every row is safe for the reason the last paragraph below gives:
 it is the IMPULSE that accumulates into a launch, and the
 impulse is carried by the first collapse alone. PushActorAway is a knockdown,
 and a knockdown on a body already on the floor is absorbed by the floor.

 ROWS ARE 0.22 SECONDS APART (the effect's Interval in the plugin), so at
 the default of one they are put down again long before they can rise.
 A larger N gives them N * 0.22 seconds between collapses, and about 2.8
 seconds -- thirteen rows -- is already enough for them to get up.




 AND ONLY THE FIRST COLLAPSE CARRIES THE IMPULSE. Collapse takes a `nudge`
 argument for it. Re-inserting a ragdoll costs nothing, but repeating an
 upward impulse on a body that is already limp is how a gentle number becomes
 a launch -- one on top of another, on something with no
 animation holding it down. The later collapses re-assert the ragdoll and
 nothing else.}

Float Property Deadline = 20.0 Auto
{Seconds after which the deferred kill is released no matter what. Longer than
 Ticks * Interval with room to spare, and it exists only so that a tick loop
 which somehow stops -- a save reloaded mid-grind, a script latency spike --
 cannot leave them invulnerable.}

Actor me
Int   left = 0
Bool  deferred = false
Bool  pinned   = false
Float started = 0.0

Event OnEffectStart(Actor akTarget, Actor akCaster)
    me = akTarget
    If !me
        Return
    EndIf
    started = Utility.GetCurrentRealTime()
    ; ORDER MATTERS: the hold goes on BEFORE the first row is taken, because
    ; the first row is what triggers the kill that must be held.
    me.StartDeferredKill()
    deferred = true
    ; PINNED, so there is no attempt to answer. SetDontMove is Bethesda's
    ; own way to hold an actor -- DLC2_SF_DLC2MQ02MiraakApocryp calls it on
    ; the dragon to hold it through a scene -- and unlike a knockdown it
    ; removes the ATTEMPT rather than answering it. Released in Release(),
    ; BEFORE the kill, or they cannot fall over.
    me.SetDontMove(true)
    pinned = true
    If !Tick
        Debug.Trace("[FleshCore] Grind Down Player: no tick spell -- releasing at once")
        Release()
        Return
    EndIf
    left = Ticks
    ; The one collapse that carries the impulse -- see RagdollEvery's note.
    Collapse(true)
    Debug.Notification("Ground down.")
    RegisterForSingleUpdate(Interval)
EndEvent

Event OnUpdate()
    ; The deadline is checked first and unconditionally, so it holds even if
    ; every other branch below is wrong about something.
    If deferred && (Utility.GetCurrentRealTime() - started) > Deadline
        Debug.Trace("[FleshCore] Grind Down Player: deadline reached -- releasing")
        left = 0
        Release()
        Return
    EndIf
    If left <= 0 || !me
        Release()
        Return
    EndIf
    left -= 1
    ; Put them back down if they have had time to start getting up. Counted from
    ; rows taken rather than from the clock, so it stays in step with the grind
    ; if the tick rate is ever changed.
    If RagdollEvery > 0 && (Ticks - left) % RagdollEvery == 0
        Collapse(false)
    EndIf
    Tick.Cast(me, me)
    If left > 0
        RegisterForSingleUpdate(Interval)
    Else
        ; THE LAST ROW HAS BEEN TAKEN -- SO THEY DIE NOW, ON THIS TICK.
        ;
        ; This used to spend one more Interval before releasing, reasoned about
        ; draining the final wound file. That reasoning was about the CUT and it
        ; cost the DEATH: a third of a second is exactly long enough to stand up
        ; in, and testing showed it: once their body was completely
        ; gone, they got up and did not die. They cannot be given a tick they can
        ; use. FL_Watch's poll drains the file on its own schedule and outlives
        ; this effect, so the pieces land on a corpse instead of on a target who
        ; is about to become one.
        Release()
    EndIf
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    ; The effect's own duration running out is the second of the three ways
    ; the hold is released.
    Release()
EndEvent

Function Release()
    {Let the death that has been owed since the first row actually land.}
    UnregisterForUpdate()
    ; THE PIN COMES OFF ON EVERY EXIT, and before the kill. SetDontMove is a
    ; debt exactly as the deferred kill is: an actor left holding one stands
    ; rooted for the rest of the save, and a pinned actor cannot ragdoll, so
    ; releasing it after Kill() would leave the corpse standing for the
    ; opposite reason.
    If pinned && me
        pinned = false
        me.SetDontMove(false)
    EndIf
    If !deferred || !me
        Return
    EndIf
    deferred = false
    me.EndDeferredKill()
    ; AND KILL THEM EXPLICITLY. EndDeferredKill releases the state; whether a
    ; kill that was absorbed while it was on is replayed afterwards is
    ; undocumented, and a
    ; target left standing with no legs would be a worse outcome than a
    ; redundant Kill() on somebody the engine already considers dead.
    ; PAST THE DEFEAT FRAMEWORK. Acheron converts a death into defeat --
    ; bleeding out, immune, ALIVE -- which matches what testing showed: once their
    ; body was completely gone, they got up and did not die. The release was moved
    ; onto the same tick on the reading that the death was arriving
    ; late; it was not late, it was being converted. DisableProcessing is
    ; Acheron's own switch, held for one call with nothing between that can
    ; return early, and the result is checked afterwards.
    If !me.IsDead()
        Bool guarded = Game.IsPluginInstalled("Acheron.esm")
        If guarded
            Acheron.DisableProcessing(true)
        EndIf
        me.Kill()
        If guarded
            Acheron.DisableProcessing(false)
            If Acheron.IsDefeated(me)
                Debug.Trace("[FleshCore] grind self: the player is STILL " \
                    + "DEFEATED after the kill -- Acheron's switch does not " \
                    + "cover a scripted Kill() on them")
            EndIf
        EndIf
    EndIf
EndFunction

Function Collapse(Bool nudge)
    {Put them on the floor.

     A CHAIN AND NOT A CANDIDATE, because a single call that does nothing
     costs a whole test to find out. KnockAreaEffect alone was tried first, and
     in testing the player was not ragdolled before being ground down.
     Everything below fires in one pass, so a
     mechanism that does nothing is covered by the next rather than costing
     another test.


     TWO CONSTRAINTS. They are ALIVE --
     deliberately, held that way by the deferred kill so the death cam cannot
     start -- and they are ALONE in the sense that
     matters: that FL_Watch's `pusher.PushActorAway(vic, 1.0)` needs a second
     reference to push from, and here there is none. That does not rule out
     PushActorAway, because Skyrim ships the self-to-self call:

     DLC2CycloneEffectScript.psc calls `Target.PushActorAway(Target, Force)`.

     It is also the ONLY thing that has ever demonstrably knocked the player to
     the ground in this mod -- when Dismember had its arguments reversed and the
     player was the one being thrown. So the bug that
     ragdolled them is now used on purpose, as step 2.

     SO: RAGDOLL FIRST, THEN THROW THEM, THEN WAKE WHAT IS LEFT.

     1. ForceAddRagdollToWorld. Declared on ObjectReference in
        ObjectReference.psc -- "Forcibly adds / removes the ragdoll for a
        reference to the world" -- and it takes no arguments, which is the one
        property this needs above all others: a call with nothing to throw them
        with cannot throw them. Its weakness:
        NOT ONE of Skyrim's own scripts calls it, so what it does here
        is a signature and a doc comment rather than an observation. That is
        why it is not shipped alone.

     2. A small impulse straight up. ApplyHavokImpulse is what FL_Watch already
        falls back to when the victim is the player, so it is not a new
        mechanism in this mod, and step 1 is what makes it mean something: an
        impulse on an actor whose ragdoll is not in the world is absorbed by
        the animation graph, an impulse on one whose ragdoll IS in the world is
        physics. RagdollImpulse's own note works the magnitude out.

     3. KnockAreaEffect, off. Kept for the reason RagdollForce's note gives.

     THE ORDER IS THE POINT. The impulse comes after the insertion because it
     is the insertion that gives it something to act on.}
    If !me
        Return
    EndIf
    ; ONCE, ON THE FIRST COLLAPSE ONLY. NOT ONE of Skyrim's own scripts calls
    ; this, as the note above says, and the grind once began calling
    ; it every 0.22s. An animation graph re-entered into ragdoll a dozen times
    ; in a row has no clean transition left to a death -- which is what
    ; "dead, searchable, standing in an idle" looks like.
    If nudge && UseForceRagdoll
        me.ForceAddRagdollToWorld()
    EndIf
    ; THE ONE THAT IS PROVEN. Every collapse gets it, not only the first: unlike
    ; an upward impulse, a knockdown on a body already on the floor is absorbed
    ; by the floor rather than accumulating into a launch, and re-asserting it is
    ; the reason for collapsing them again after they have had time to rise.
    If PushSelf > 0.0
        me.PushActorAway(me, PushSelf)
    EndIf
    If nudge && RagdollImpulse > 0.0
        me.ApplyHavokImpulse(0.0, 0.0, 1.0, RagdollImpulse)
    EndIf
    If RagdollForce > 0.0
        me.KnockAreaEffect(RagdollForce, RagdollRadius)
    EndIf
    Debug.Trace("[FleshCore] Grind Down Player: collapse -- ragdoll=" \
        + UseForceRagdoll + " push=" + PushSelf + " nudge=" + nudge \
        + " impulse=" + RagdollImpulse + " knock=" + RagdollForce)
EndFunction
