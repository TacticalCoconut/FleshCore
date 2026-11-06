Scriptname FL_KO_Hold extends Quest
{THE HOLD -- who is down, how they were put down, and the watchdog.

 WHY THE HOLD WORKS THIS WAY. A bleedout hold is wrong at its
 root, and what follows is the
 reasoning.

 WHAT THE DEFERRED-KILL HOLD DID, AND WHY IT COULD NOT WORK. It put the target
 into bleedout and took the recovery flag away. Bleedout, though, is a state
 the engine gives to ESSENTIAL and PROTECTED actors -- it is what they do
 INSTEAD of dying. FL_Knockout cleared both of those flags two lines before
 asking for it. So the target could not bleed out, their death was merely
 deferred, and they walked around at minus one health. And then the cure
 killed them, because ending the deferred kill let the lethal damage finally
 land, and the player got a bounty for it.

 SO NONE OF THAT IS USED. A target is never invulnerable
 while knocked out.

 NOT PRESENT ANYWHERE IN THE HOLD:
   StartDeferredKill  SetEssential  SetProtected  SetInvulnerable
   SetGhost           DamageActorValue
 Nothing this spell does makes anybody invulnerable and NOTHING TAKES THEIR
 HEALTH AWAY. SetNoBleedoutRecovery and RestoreActorValue each appear exactly
 once, in MigrateLegacyHolds and nowhere else, whose only job is to undo what
 the deferred-kill hold did to actors who are still held under it; EndDeferredKill is
 not called anywhere (see (g) below).
 They are an ordinary actor lying on the floor: a sword kills them, a FleshCore
 spell kills them, and the cure cannot kill them because nothing was ever
 deferred and nothing was ever taken off their health bar.

 WHAT HOLDS THEM DOWN (the notes below the docstring say why):

   SetUnconscious(true)     Actor.psc. The engine's own knockout: no
                            packages, no combat reaction, no alarm, no
                            dialogue. It does NOT keep them on the floor.
   Paralysis = 1            The actor VALUE, set with SetActorValue -- NOT
                            the Paralyze archetype, which is the rigid one.
                            Fortified by one it drops them into havok and the
                            engine will not stand them up until it is zero
                            again: limp, on the floor, killable. The pair
                            an external consumer already uses
                            (SettleCorpse, the technique external furniture uses).
   PushActorAway            ObjectReference.psc -- the fall, so they go
                            over instead of folding where they stand.

 NOTHING FREEZES THEIR AI. EnableAI(false) was the AI-freeze hold, and testing
 ruled it out: see (i) below.}

; NOTES ON THE HOLD.
;   (a) PutDown is latent for `settle` seconds and then froze their AI without
;       looking at the register again. A cure, the hour, or the killed-while-
;       held sweep can all release them inside that wait; the freeze then landed
;       on a target with no slot, so no watchdog would ever undo it.
;   (b) The `ticking` flag was a race between OnUpdate and PutDown that could
;       leave someone held with no update registered. RegisterForSingleUpdate
;       replaces a pending registration rather than stacking, so the flag bought
;       nothing; PutDown now always registers.
;   (c) FreezeAI on the PLAYER locks the player out of casting the cure, or
;       anything, until the hour expires. The player keeps their AI; the
;       unconscious flag holds on its own.
; (Kept out of the docstring above: Caprica fails to allocate once a
;  docstring passes about 4 KB.)
;

;   (d) A release is now a marked state, not an instant. LetUp stamps
;       releasingAt[slot] before it touches the engine and clears the slot only
;       after -- so PutDown, whether it is a fresh cast arriving during the
;       release or the settle wait ending inside it, sees the release and stands
;       aside instead of setting a flag LetUp is about to clear. OnUpdate
;       finishes any release that stalled for more than a tick. Slots in
;       release are skipped by the expiry and dead sweeps.
;   (e) The migration restores the deferred-kill hold's saved wasNoRecovery[] value
;       instead of clearing the flag for everybody it undoes.
;
; THE DEAD, THE MIGRATION, AND THE DROP.
;   (f) A target killed while held STOOD UP DEAD. The dead sweep called LetUp,
;       which gave their AI back and cleared the unconscious flag -- on a corpse.
;       A corpse is now left exactly as it lies: nothing is called on it. It is
;       remembered, and if it ever comes back alive (FleshCore's Restore
;       resurrects) what the hold set on them is given back then.
;   (g) The migration killed them and gave a bounty: EndDeferredKill lands the
;       deferred death whatever their health reads. It is never called; the stranded
;       actor is rebuilt with Resurrect() instead.
;   (h) A held target who stops being unconscious without the hold -- another mod, a
;       Restore, a console command -- is dropped from the register after two
;       ticks, with what the hold set on them given back.
;
; THE LIMP HOLD.
;   (i) EnableAI(false) WAS THE FREEZE, and it is not used. It caused each of these:
;       a target hit mid-animation stayed in that frame (the
;       statues mid-get-up, A-poses); FL_Watch's own revive lines read
;       `life=3 knock=5` on held targets -- knock state kQueued: the PushActorAway
;       was queued and NEVER PROCESSED, because switching the AI off stops the
;       process that drains the knock queue and drives the behaviour graph. A
;       corpse killed with their AI off read `life=1` (kDying) for the rest of
;       the session: the death transition itself never completes either. What
;       holds them on the floor now is the Paralysis actor value -- see the
;       docstring -- which the engine handles inside havok, with the AI running.
;       FreezeAI in the plugin is now False; PutDown ignores it either
;       way, and the settle wait it existed for is gone with it: PutDown is no
;       longer latent, so the re-check of (a) has nothing left to re-check.
;   (j) THE CORPSE LIST FORGOT EVERY CORPSE IN THE TICK IT LEARNED OF IT. Not
;       one `is alive again` line exists in a log with three held corpses
;       resurrected. OnUpdate read `now` at its top; the dead sweep then ran
;       LetUp -> RememberCorpse, which stamped corpseAt a few milliseconds
;       LATER; and CorpsePass in the same tick took `now < corpseAt` for a
;       restarted clock and forgot them. CorpsePass reads its own clock now, and
;       a clock that really did restart re-stamps the corpse instead of
;       dropping it -- because Paralysis persists through Resurrect (standard
;       consumer warning), a forgotten corpse is a target revived
;       paralysed for good. Revived() is the direct route: FL_Watch's Restore
;       calls it on every actor it brings back, so what they are owed comes back
;       in the same frame, not on the next tick.
;   (k) An AI-freeze hold carried over from an older save still has its AI off. On the
;       first tick under the new hold every such slot is exchanged: AI back on,
;       Paralysis on, the flag cleared -- so they lie limp like the others
;       instead of standing frozen until their cure.
;

;   (l) Paralysis is given back AS IT WAS, like the flag: the base value is
;       read before the hold sets it and restored after (wasParalysis[],
;       corpseParalysis[]). an external consumer holds the player at 1 during its
;       own recovery; a cure that set 0 would have stood them up out of it.
;   (m) Revived() and CorpsePass no longer touch a target the register HOLDS: a
;       corpse revived by something else and knocked out again inside the hour
;       would have had the new hold torn down by the old corpse entry; and a
;       held target resurrected inside the dead sweep's 5-second window (still
;       in held[], not yet in corpses[]) is now released properly by Revived()
;       instead of being dropped ten seconds later by the (h) path.
;   (n) ExchangeFrozenHolds puts the limp hold on EVERY living held target from
;       the AI-freeze hold, not only the ones whose AI was off; the AI is what is
;       gated on that hold's flag.
;   (o) The (h) drop watches Paralysis as well as the flag: another mod taking
;       either off them is a hold that is no longer holding, and the register
;       follows reality after two ticks either way, giving back what is left.
;   (p) The shove marker is disabled and deleted on the NEXT tick, not in the
;       frame it pushed from: the push is a queued knock whose source should
;       still exist when the queue drains.
;
; ON INTERLEAVINGS. Papyrus runs this
;   script on several threads at once -- its own tick, a Cure's or a Knockout's
;   effect thread, FL_Watch's beat -- and a function body is not a critical
;   section: another thread can run between any two instructions, and every
;   native call is a place the VM may switch. So:
;   (q) A slot is CLAIMED before anything else and the claim is read back. Two
;       casts in the same window used to both read the same free index, and
;       the second overwrote the first: a target put down with no slot, no
;       watchdog, no hour, and a Cure that says they are not held.
;   (r) The drop path of (h)/(o) marks the release (releasingAt) before it
;       touches them, like LetUp, so a cast landing inside it is refused instead
;       of claiming a target whose slot is cleared a moment later; and it reads
;       IsDead() again before giving anything back.
;   (s) Revived() trusts "they are held again" only when that hold is not itself
;       mid-release: LetUp's dead branch remembers the corpse one instruction
;       before it clears the slot, and inside that instruction they are in both
;       lists.
;   (t) The shove marker is retired only once it is a second old, so a tick
;       that interleaves with a fresh Shove cannot delete a marker whose push
;       is still queued.
;   (u) A prior Paralysis base of 1 or more on anybody but the player is not
;       believed: it is the leftover of a hold or a corpse settle, and a cure
;       that faithfully restored it would "release" them into the same
;       paralysis. Zero is stored and the log says so.
;   (v) The earlier migration calls nothing on a corpse (rule (f))
;       RememberCorpse claims its slot the way PutDown does and restarts
;       the tick; the two one-time migrations are gated by one write of
;       builtVersion, before either runs, so a second thread cannot run the
;       other one over the same array.

Actor[] held
Float[] until
Float[] span
Bool[]  wasUnconscious
Bool[]  wasAIOff
Float[] releasingAt
Bool[]  awakeSeen
Float[] wasParalysis
; CORPSES. A target killed while held keeps whatever the hold set on them -- see (f).
; These remember what they are owed if they ever come back alive.
Actor[] corpses
Bool[]  corpseAIOff
Bool[]  corpsePrior
Float[] corpseAt
Float[] corpseParalysis
; THE LAST SHOVE MARKER, disabled and deleted on the next tick -- see (p) and
; (t) -- and when it was placed, on the application clock.
ObjectReference shoveMarker = None
Float shoveAt = 0.0
; DECLARED, NEVER WRITTEN. The deferred-kill hold saved each held actor's prior
; bleedout-recovery flag under this name; declaring it again lets an older save
; hand the values to MigrateLegacyHolds. On any newer save it is simply None.
Bool[]  wasNoRecovery
Int builtVersion = 0

; EIGHT AT ONCE. The number is a literal in EnsureArrays because Papyrus will
; not size an array from a variable, so no property pretends to control it.

Event OnInit()
    EnsureArrays()
EndEvent

Function EnsureArrays()
    If !held
        held = new Actor[8]
    EndIf
    If !until
        until = new Float[8]
    EndIf
    If !span
        span = new Float[8]
    EndIf
    If !wasUnconscious
        wasUnconscious = new Bool[8]
    EndIf
    If !wasAIOff
        wasAIOff = new Bool[8]
    EndIf
    If !releasingAt
        releasingAt = new Float[8]
    EndIf
    If !awakeSeen
        awakeSeen = new Bool[8]
    EndIf
    If !wasParalysis
        wasParalysis = new Float[8]
    EndIf
    If !corpses
        corpses = new Actor[8]
    EndIf
    If !corpseAIOff
        corpseAIOff = new Bool[8]
    EndIf
    If !corpsePrior
        corpsePrior = new Bool[8]
    EndIf
    If !corpseAt
        corpseAt = new Float[8]
    EndIf
    If !corpseParalysis
        corpseParalysis = new Float[8]
    EndIf
    ; ONE WRITE GATES BOTH -- see (v). Whichever thread gets here first owns the
    ; migrations; any other reads 3 and walks past.
    If builtVersion < 3
        Int was = builtVersion
        builtVersion = 3
        If was < 2
            MigrateLegacyHolds()
        EndIf
        ExchangeFrozenHolds()
    EndIf
EndFunction

Function MigrateLegacyHolds()
    {UNDO THE DEFERRED-KILL HOLD ON ANYBODY STILL HELD BY IT. Runs once, ever.

     A SAVE FROM THE DEFERRED-KILL HOLD IS THE ONE REAL HAZARD. Papyrus
     keeps a script's variables across a recompile by NAME, so a save made
     while somebody was knocked out arrives here with held[] still populated
     -- but that actor is carrying StartDeferredKill and a cleared bleedout
     recovery flag from the deferred-kill hold, and the new hold has no EndDeferredKill
     in it to ever pair with. They would be invulnerable for the life of the
     save, with nothing left in the game that knew to fix them.


     THE ORDER MATTERS. Health goes back FIRST
     and the deferred kill is ended SECOND. The old LetUp did it the other way
     round -- EndDeferredKill, then restore -- and on a target sitting at minus
     one health that lands their deferred death the instant the kill stops being
     deferred. That is, mechanically, why casting Knockout Cure killed the
     target and drew a bounty. Restore first and there is no lethal
     damage left pending when the deferral lifts.

     It does not use SlotOf or LetUp: both call EnsureArrays, which calls this,
     and EnsureArrays writes builtVersion before calling, so nothing re-enters.}
    Int i = 0
    While i < held.Length
        Actor a = held[i]
        If a
            Debug.Trace("[FleshCore] MIGRATING an old-format knockout on " + a \
                + " -- health " + a.GetActorValue("Health") + ", undoing it before it strands them")
            If !a.IsDead()
                a.RestoreActorValue("Health", a.GetActorValueMax("Health"))
            EndIf
            ; Given back as they came in, if the deferred-kill hold recorded it.
            Bool priorNoRecovery = false
            If wasNoRecovery && i < wasNoRecovery.Length
                priorNoRecovery = wasNoRecovery[i]
            EndIf
            a.SetNoBleedoutRecovery(priorNoRecovery)
            ; THE DEFERRAL IS NEVER ENDED BY HAND -- see (g). Ending it fired the
            ; death with their health already restored (seen in testing).
            ; The stranded actor is REBUILT instead: Resurrect() on a living actor
            ; is documented in FL_Watch as rebuilding their 3D, refilling their health
            ; and resetting their inventory -- a fresh process, which is the only
            ; clean way out of a state the engine offers no way to cancel. The
            ; inventory reset is the price, and it is paid only by an actor the
            ; deferred-kill hold stranded. The player cannot be resurrected and is left as
            ; they are, with the log saying so.
            If a == Game.GetPlayer()
                Debug.Trace("[FleshCore] MIGRATION: the player is stranded under an old-format deferred kill; " \
                    + "Resurrect() does not work on the player -- left alive and deferred")
            ElseIf !a.IsDead()
                a.Resurrect()
            EndIf
            ; ONLY THE LIVING -- rule (f): a corpse given its flag back and its AI
            ; stands up dead. The deferred-kill hold never set Paralysis, so nothing else
            ; is owed to a corpse.
            If !a.IsDead()
                a.SetUnconscious(false)
                a.EnableAI(true)
                a.StopCombatAlarm()
            EndIf
            Debug.Trace("[FleshCore] MIGRATION done on " + a + " -- health " + a.GetActorValue("Health") \
                + " dead=" + a.IsDead() + " bleedout=" + a.IsBleedingOut() \
                + " (the old deferral was NOT ended by hand; if it survived the rebuild they cannot die in this save)")
            held[i] = None
            until[i] = 0.0
            span[i] = 0.0
        EndIf
        i += 1
    EndWhile
EndFunction

Function ExchangeFrozenHolds()
    {Targets held under the AI-freeze hold have no limp hold, and most have their AI off
     -- see (i), (k) and (n). Runs once. Every living held target gets the limp
     hold in place, and their AI back if it was taken; they stay held, so their
     cure, their hour and their death all still work as before. A corpse remembered
     by the AI-freeze hold keeps its corpseAIOff flag; CorpsePass and Revived() still
     honour it, so nothing is exchanged there.}
    Int i = 0
    While i < held.Length
        Actor a = held[i]
        If a
            Bool aiWasOff = wasAIOff[i]
            wasAIOff[i] = false
            If !a.IsDead()
                If aiWasOff
                    a.EnableAI(true)
                EndIf
                wasParalysis[i] = PriorParalysis(a)
                a.SetActorValue("Paralysis", 1.0)
                Debug.Trace("[FleshCore] EXCHANGED a frozen hold on " + a \
                    + " for the limp hold -- Paralysis on, AI " + StringIf(aiWasOff, "back on", "was never taken") \
                    + "; they are still held")
            ElseIf aiWasOff
                ; Dead with their AI off: the (f) rule says a corpse is not touched.
                ; The dead sweep will remember them on its next tick.
                Debug.Trace("[FleshCore] " + a + " is a corpse frozen by an old-format hold -- left as they lie")
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

Int Function SlotOf(Actor who)
    ; NONE IS NOT A SLOT. held[] is None in every free slot, so without this
    ; guard SlotOf(None) returns the index of the first FREE one -- and LetUp
    ; would then clear a slot that was never taken and call EnableAI on None.
    If !who
        Return -1
    EndIf
    EnsureArrays()
    Int i = 0
    While i < held.Length
        If held[i] == who
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Int Function FreeSlot()
    EnsureArrays()
    Int i = 0
    While i < held.Length
        If !held[i]
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Bool Function IsHeld(Actor who)
    Return who && SlotOf(who) >= 0
EndFunction

; ---- PUTTING THEM DOWN ------------------------------------------------------
Bool Function PutDown(Actor who, Actor pusher = None, Float seconds = 3600.0, Float shove = 1.0, Bool freezeAI = false, Float settle = 0.0)
    {Down, and not getting up. Idempotent -- a second call on somebody already
     held does nothing.

     RETURNS FALSE IF THE HOLD DID NOT TAKE, and the caller is told rather than
     the register silently claiming somebody who is still walking around.

     freezeAI AND settle ARE RETIRED -- see (i). Both stay in the signature
     because FL_Knockout's compiled call passes six arguments and Papyrus binds
     by position; neither is read. The plugin's FreezeAI property is False.

     NOTHING HERE WAITS ANY MORE. The slot is claimed, the three calls land,
     the deadline is written and the watchdog is registered in one pass, and
     nothing after the calls re-reads the register -- so there is no window
     for a release to open under it, and nothing to re-check.}
    If !who || who.IsDead()
        Return false
    EndIf
    Int have = SlotOf(who)
    If have >= 0
        ; HELD -- unless they are on their way up right now, in which case this cast
        ; has lost: LetUp is about to clear their flag and their slot, and claiming
        ; them again here would leave a registered target standing. Refused, and
        ; the caster is told; a recast a moment later takes.
        If releasingAt[have] > 0.0
            Return false
        EndIf
        Return true
    EndIf
    ; EVERYTHING THE SLOT NEEDS IS READ BEFORE IT IS CLAIMED -- see (q). The
    ; watchdog looks only at slots whose held[] is set, so a slot whose
    ; deadline and flags are already written is what it must find the moment
    ; the claim lands; the old order (claim, then a native call, then the
    ; deadline) left one tick's read of an unset deadline reading as EXPIRED.
    Float deadline = Utility.GetCurrentRealTime() + seconds
    Bool priorFlag = who.IsUnconscious()
    ; GIVEN BACK AS THEY CAME IN, like the flag -- see (l) and (u). The BASE
    ; value: a Paralyze spell's own modifier sits on top of it and is not the hold's.
    Float priorPara = PriorParalysis(who)

    Int slot = FreeSlot()
    If slot < 0
        Debug.Trace("[FleshCore] the hold is full -- " + who + " stays up")
        Return false
    EndIf
    until[slot] = deadline
    span[slot] = seconds
    wasUnconscious[slot] = priorFlag
    wasAIOff[slot] = false
    awakeSeen[slot] = false
    releasingAt[slot] = 0.0
    wasParalysis[slot] = priorPara

    ; CLAIMED WITH NOTHING BETWEEN THE READ AND THE WRITE, AND READ BACK
    ; TWICE: once at once, once after the first native call, which is where
    ; the VM switches threads. Another cast in the same window may have taken
    ; this index (it wins: this one stands aside and says so), or may have
    ; claimed THEM in a lower slot (it wins too: they are held, this is a
    ; duplicate). Nothing has been done to them before the second read-back.
    held[slot] = who
    If held[slot] != who
        Debug.Trace("[FleshCore] two casts raced for one slot -- " + who + " stands aside; recast if they are still up")
        Return false
    EndIf
    If SlotOf(who) != slot
        held[slot] = None
        Return true
    EndIf

    ; NOTHING THIS SPELL DOES MAY RAISE AN ALARM. Testing drew a bounty out of the
    ; old cure; that came from the death, which is gone, but the cast itself
    ; should be quiet too. StopCombatAlarm is in Actor.psc.
    who.StopCombatAlarm()
    If held[slot] != who
        Debug.Trace("[FleshCore] two casts raced for one slot -- " + who + " stands aside; recast if they are still up")
        Return false
    EndIf

    ; 1. THE ENGINE'S OWN KNOCKOUT: no reactions, no alarm, no dialogue.
    who.SetUnconscious(true)

    ; 2. THE LIMP HOLD. Paralysis 1 hands them to havok and keeps them there --
    ;    whatever animation they were in, including a get-up, which is what the
    ;    A-posed statues seen in testing were waiting to finish.
    who.SetActorValue("Paralysis", 1.0)

    ; 3. THE FALL. The actor PushActorAway is CALLED ON is the source and the
    ;    ARGUMENT is the one thrown -- backwards, it throws the player. With no
    ;    pusher, or themselves as the pusher (a self-cast), they are pushed from a
    ;    marker placed a step in front of them, so they go over backwards.
    If pusher && pusher != who
        pusher.PushActorAway(who, shove)
    Else
        Shove(who, shove)
    EndIf

    ; LOGGED, AND CHECKED: THE CHECK IS WHAT MADE THE LAST TWO FAILURES
    ; EASY TO UNDERSTAND. Every fact the log can get.
    Debug.Trace("[FleshCore] HOLD on " + who \
        + " -- unconscious=" + who.IsUnconscious() \
        + " paralysis=" + who.GetActorValue("Paralysis") \
        + " health=" + who.GetActorValue("Health") \
        + " dead=" + who.IsDead() \
        + " (health deliberately untouched; no deferred kill; AI running; killable)")
    StartTicking()
    Return true
EndFunction

Function Shove(Actor who, Float shove)
    {The fall for a target with nobody to push them. An XMarker (Skyrim.esm
     0x3B) is placed a step in front of them and pushes them away from itself,
     then goes. The Creation Kit's own note on PushActorAway: "Use an
     XMarkerHeading object to control the exact direction in which the actor
     will be pushed." A havok impulse is the fallback if the marker form cannot
     be found; Paralysis has already dropped them, so at worst they fold where
     they stand instead of going over.}
    Form xm = Game.GetForm(0x0000003B)
    If !xm
        who.ApplyHavokImpulse(0.0, 0.0, 1.0, 6.0)
        Return
    EndIf
    ; The previous marker, if a tick has not taken it yet, goes now: it is at
    ; least a frame old and its push has long been drained -- see (p).
    RetireMarker()
    ObjectReference m = who.PlaceAtMe(xm)
    If !m
        who.ApplyHavokImpulse(0.0, 0.0, 1.0, 6.0)
        Return
    EndIf
    ; Forward is (sin z, cos z) in this engine's heading; Math.Sin takes degrees.
    ; SetPosition rather than MoveTo: a marker has no 3D to move, and MoveTo is
    ; the one that may go latent.
    Float z = who.GetAngleZ()
    m.SetPosition(who.GetPositionX() + 48.0 * Math.Sin(z), \
                  who.GetPositionY() + 48.0 * Math.Cos(z), \
                  who.GetPositionZ())
    m.PushActorAway(who, shove)
    shoveMarker = m
    shoveAt = Utility.GetCurrentRealTime()
EndFunction

Function RetireMarker()
    {Disable, then delete, the marker of the last self-shove -- the idiom for a
     reference PlaceAtMe made -- once it is a second old, so its push has been
     drained -- see (p) and (t). A clock that went backwards under it means a
     reload, and the marker is older than it looks.}
    If shoveMarker
        Float now = Utility.GetCurrentRealTime()
        If now - shoveAt > 1.0 || now < shoveAt
            shoveMarker.Disable()
            shoveMarker.Delete()
            shoveMarker = None
        EndIf
    EndIf
EndFunction

Float Function PriorParalysis(Actor who)
    {Their Paralysis base before the hold, as it will be given back -- see (u).
     One or more on anybody but the player is not theirs: it is what a hold or a
     corpse settle left on them, and handing it back would be a cure that does
     nothing. The player keeps theirs: an external consumer holds them at one on
     purpose during its own recovery.}
    Float base = who.GetBaseActorValue("Paralysis")
    If base >= 1.0 && who != Game.GetPlayer()
        Debug.Trace("[FleshCore] " + who + " came in with Paralysis already at " + base \
            + " -- taken as left over by a hold; the cure will take them to zero")
        Return 0.0
    EndIf
    Return base
EndFunction

; ---- LETTING THEM UP --------------------------------------------------------
Bool Function LetUp(Actor who, Bool getUp = true)
    {Undo, in the reverse order.

     THE FLAG FIRST, THEN THE PARALYSIS. Paralysis going back to zero is what
     makes the engine stand them up out of the ragdoll; they should be a target who
     can move by the time that happens, not one still marked unconscious.

     THEIR HEALTH IS NOT TOUCHED HERE EITHER. The deferred-kill hold restored it, which
     only made sense because that hold had taken it away. More to the point,
     the old cure
     KILLED THEM, and no line in this function can.}
    Int slot = SlotOf(who)
    If slot < 0
        Return false
    EndIf
    If releasingAt[slot] > 0.0
        ; Somebody is already letting them up -- the cure cast twice, or the
        ; watchdog and the cure in the same tick. Once is enough.
        Return false
    EndIf
    ; THE RELEASE IS MARKED BEFORE THE ENGINE IS TOUCHED. From here until the
    ; slot is cleared they read as held-and-releasing: PutDown refuses them, the
    ; sweeps skip them, and a second LetUp returns above.
    releasingAt[slot] = Utility.GetCurrentRealTime()
    Bool wasFrozen = wasAIOff[slot]
    Bool priorUnconscious = wasUnconscious[slot]
    Float priorParalysis = wasParalysis[slot]

    If who.IsDead()
        ; A CORPSE IS LEFT EXACTLY AS IT LIES -- see (f). Giving a dead target their
        ; AI back and clearing their unconscious flag stood them up. Nothing is
        ; called on them; what they are owed is remembered in case they come back.
        RememberCorpse(who, wasFrozen, priorUnconscious, priorParalysis)
        held[slot] = None
        until[slot] = 0.0
        span[slot] = 0.0
        wasAIOff[slot] = false
        awakeSeen[slot] = false
        releasingAt[slot] = 0.0
        Debug.Trace("[FleshCore] " + who + " is dead -- left as they lie (Paralysis stays, flag stays); " \
            + "they come back only if they are revived")
        Return true
    EndIf

    If wasFrozen
        ; An AI-freeze hold that ExchangeFrozenHolds did not reach.
        who.EnableAI(true)
    EndIf
    ; Given back as they came in -- if somebody else had them unconscious before
    ; this spell touched them, that is theirs and not this spell's to clear.
    who.SetUnconscious(priorUnconscious)
    ; AND THE HOLD COMES OFF -- back to the base value they came in with, which
    ; is zero for everybody the game made; the engine stands them up out of the
    ; ragdoll by itself.
    who.SetActorValue("Paralysis", priorParalysis)

    If getUp && !who.IsDead()
        who.StopCombatAlarm()
    EndIf

    ; CLEARED LAST, AND ONLY IF IT IS STILL THEIRS. A stalled release that OnUpdate
    ; finished may already have handed the slot to somebody else.
    If held[slot] == who
        held[slot] = None
        until[slot] = 0.0
        span[slot] = 0.0
        wasAIOff[slot] = false
        awakeSeen[slot] = false
        releasingAt[slot] = 0.0
    EndIf

    Debug.Trace("[FleshCore] RELEASED " + who \
        + " -- unconscious=" + who.IsUnconscious() \
        + " paralysis=" + who.GetActorValue("Paralysis") \
        + " health=" + who.GetActorValue("Health") \
        + " dead=" + who.IsDead())
    Return true
EndFunction

; ---- CORPSES ---------------------------------------------------------------
Function RememberCorpse(Actor who, Bool aiOff, Bool prior, Float paralysis)
    {They died while held. Remember what the hold set on them so it can be given back
     if they are ever alive again -- FleshCore's Restore resurrects, and a revived
     target with Paralysis still at 1 would lie there for good.}
    EnsureArrays()
    Int i = 0
    While i < corpses.Length
        If corpses[i] == who
            Return
        EndIf
        i += 1
    EndWhile
    i = 0
    While i < corpses.Length
        If !corpses[i]
            ; CLAIMED AND READ BACK, as PutDown does -- see (q) and (v).
            corpses[i] = who
            If corpses[i] == who
                corpseAIOff[i] = aiOff
                corpsePrior[i] = prior
                corpseParalysis[i] = paralysis
                corpseAt[i] = Utility.GetCurrentRealTime()
                ; The tick is what gives a corpse back what it is owed; make
                ; sure there is one, whoever called.
                StartTicking()
                Return
            EndIf
        EndIf
        i += 1
    EndWhile
    ; Not fatal: FleshCore's Restore takes Paralysis to zero on everybody it
    ; brings back whether or not this list knows them, and death itself clears
    ; the unconscious life state (the log reads unconscious=False on every held
    ; corpse). Only a revival by something else would leave them lying there.
    Debug.Trace("[FleshCore] no room to remember the corpse of " + who \
        + " -- Restore still resets their Paralysis; anything else that revives them may leave them lying")
EndFunction

Int Function CorpseSlot(Actor who)
    If !who
        Return -1
    EndIf
    EnsureArrays()
    Int i = 0
    While i < corpses.Length
        If corpses[i] == who
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Function GiveBack(Actor c, Bool aiOff, Bool prior, Float paralysis)
    {What they were owed, returned: the AI if it was taken, the flag and the
     Paralysis base as they were before the hold.}
    If aiOff
        c.EnableAI(true)
    EndIf
    c.SetUnconscious(prior)
    c.SetActorValue("Paralysis", paralysis)
EndFunction

Function Revived(Actor who)
    {Told by whoever resurrected them -- FL_Watch, on every actor its Restore
     brings back. What they are owed comes back NOW, in the same frame as the
     resurrection, rather than on the next tick. Two cases, see (m): a corpse
     this list remembers, and a target still in held[] because the dead sweep
     had not yet reached them when they were killed and revived. Anybody else is
     not the hold's and nothing is done.}
    If !who || who.IsDead()
        Return
    EndIf
    Int c = CorpseSlot(who)
    If c >= 0
        ; INTO LOCALS FIRST, ON PURPOSE -- the Caprica temp hazard, see OnUpdate.
        Bool aiOff = corpseAIOff[c]
        Bool prior = corpsePrior[c]
        Float para = corpseParalysis[c]
        corpses[c] = None
        Int again = SlotOf(who)
        If again >= 0 && releasingAt[again] <= 0.0
            ; Knocked out again since they died: the hold owns them now and the
            ; corpse entry is stale. Forgotten, nothing given back. A slot that
            ; is mid-release is LetUp's dead branch clearing them -- see (s) --
            ; and that is not a new hold.
            Debug.Trace("[FleshCore] " + who + " is held again -- their old corpse entry dropped")
            Return
        EndIf
        GiveBack(who, aiOff, prior, para)
        Debug.Trace("[FleshCore] " + who + " was revived -- their flag and Paralysis given back on the spot")
        Return
    EndIf
    Int slot = SlotOf(who)
    If slot >= 0 && releasingAt[slot] <= 0.0
        ; Killed and brought back between two ticks. Released as if cured,
        ; without the get-up alarm: LetUp reads them as alive and gives back
        ; the flag and the Paralysis base.
        Debug.Trace("[FleshCore] " + who + " was revived while still on the register -- released")
        LetUp(who, false)
    EndIf
EndFunction

Bool Function CorpsePass()
    {Every tick: give a revived corpse back what it is owed; forget what is gone.
     Returns true while anything is still remembered.

     ITS OWN CLOCK -- see (j). The tick's `now` was read before the dead sweep
     that may just have remembered a corpse, so measured against it every fresh
     corpse looked like one stamped in the future.}
    Float now = Utility.GetCurrentRealTime()
    Bool any = false
    Int i = 0
    While i < corpses.Length
        Actor c = corpses[i]
        If c
            If c.IsDeleted()
                corpses[i] = None
            ElseIf !c.IsDead()
                Bool aiOff = corpseAIOff[i]
                Bool prior = corpsePrior[i]
                Float para = corpseParalysis[i]
                corpses[i] = None
                Int again = SlotOf(c)
                If again >= 0 && releasingAt[again] <= 0.0
                    ; Revived and knocked out again before this tick saw them:
                    ; the hold owns them now -- see (m) and (s).
                    Debug.Trace("[FleshCore] " + c + " is alive and held again -- their old corpse entry dropped")
                Else
                    GiveBack(c, aiOff, prior, para)
                    Debug.Trace("[FleshCore] " + c + " is alive again -- their flag and Paralysis given back")
                EndIf
            ElseIf now < corpseAt[i]
                ; The application clock restarted under them (a quit and a
                ; reload). Re-stamped, not forgotten: what they are owed does not
                ; expire with the session.
                corpseAt[i] = now
                any = true
            ElseIf now - corpseAt[i] > 3600.0
                ; an hour dead: the body is the game's now
                corpses[i] = None
            Else
                any = true
            EndIf
        EndIf
        i += 1
    EndWhile
    Return any
EndFunction

; ---- THE WATCHDOG ----------------------------------------------------------
;
; MUCH LESS CRITICAL THAN IT WAS. The old watchdog
; existed because StartDeferredKill left an actor who could never be killed
; again, and a script stopping between the two calls stranded them forever.
; Nothing here defers a kill, so the worst thing left dangling is an NPC lying
; paralysed -- annoying, fixable by casting the cure, and not a permanent hole
; in the world. The timer is ONE REAL HOUR rather than a
; safety valve set to ten minutes.
;
; THE DEADLINE IS KEPT IN A CLOCK THAT RESTARTS, AND THAT IS HANDLED. Utility
; .psc calls GetCurrentRealTime "the number of seconds since the application
; started" -- not since the save. until[i] was set to (an earlier now) + span[i]
; and now only increases within a session, so until[i] - now <= span[i] holds at
; every instant of that session and a larger value is IMPOSSIBLE. Seeing one
; means the clock restarted; there is no false positive to trade against.
Function StartTicking()
    ; ALWAYS. RegisterForSingleUpdate REPLACES a pending registration rather than
    ; stacking one, so calling it on every PutDown is free -- and the flag it
    ; used to hide behind was a race: OnUpdate reads an empty register, PutDown
    ; claims a slot and sees the flag still up so does not register, OnUpdate
    ; clears the flag and does not re-register. Nobody watched them after that:
    ; the hold held, but the hour and the killed-while-held sweep were dead.
    RegisterForSingleUpdate(5.0)
EndFunction

Event OnUpdate()
    EnsureArrays()
    Float now = Utility.GetCurrentRealTime()
    Int r = 0
    While r < held.Length
        If held[r] && (until[r] - now) > span[r]
            Debug.Trace("[FleshCore] the real-time clock restarted under a hold on " \
                + held[r] + " -- deadline re-based to " + span[r] + "s from now")
            until[r] = now + span[r]
        EndIf
        r += 1
    EndWhile
    Bool any = false
    Int i = 0
    While i < held.Length
        Actor a = held[i]
        If a && releasingAt[i] > 0.0
            ; A RELEASE IN FLIGHT IS LEFT ALONE FOR ONE TICK. If it is still
            ; marked after that, or the clock went backwards under it, the
            ; LetUp that started it died mid-way; finish what it began so they are
            ; not stranded half-released with a slot nobody will ever clear.
            If now - releasingAt[i] > 5.0 || now < releasingAt[i]
                Debug.Trace("[FleshCore] the release of " + a + " did not finish -- finishing it")
                ; INTO LOCALS FIRST, ON PURPOSE. Handed two Bool array reads as
                ; arguments, Caprica can put both in the SAME temp and pass
                ; the second value twice.
                Bool lateAIOff = wasAIOff[i]
                Bool latePrior = wasUnconscious[i]
                Float latePara = wasParalysis[i]
                If a.IsDead()
                    RememberCorpse(a, lateAIOff, latePrior, latePara)
                Else
                    GiveBack(a, lateAIOff, latePrior, latePara)
                EndIf
                held[i] = None
                until[i] = 0.0
                span[i] = 0.0
                wasAIOff[i] = false
                releasingAt[i] = 0.0
            Else
                any = true
            EndIf
        ElseIf a
            If now > until[i]
                Debug.Trace("[FleshCore] the hold on " + a + " EXPIRED -- releasing them")
                LetUp(a, true)
            ElseIf a.IsDead()
                ; THEY WERE KILLED WHILE DOWN, WHICH IS WHAT THE HOLD ALLOWS. Off the
                ; register; LetUp leaves a corpse exactly as it lies -- see (f).
                Debug.Trace("[FleshCore] " + a + " was KILLED while held -- clearing the hold")
                LetUp(a, false)
            ElseIf !a.IsUnconscious() || a.GetActorValue("Paralysis") <= 0.0
                ; SOMEBODY ELSE WOKE THEM -- see (h) and (o): the flag or the
                ; Paralysis gone without the hold. Two ticks in a row, so a flicker
                ; does not drop a real hold. What is left of the hold's goes back --
                ; the flag to what it was, the Paralysis base to what it was --
                ; and the register stops claiming a target who is not held.
                If awakeSeen[i]
                    ; MARKED FIRST, like LetUp -- see (r): a cast landing while
                    ; this gives their state back is refused, not registered on a
                    ; slot that is cleared a moment later.
                    releasingAt[i] = now
                    Debug.Trace("[FleshCore] " + a + " is no longer held by what we set (unconscious=" \
                        + a.IsUnconscious() + " paralysis=" + a.GetActorValue("Paralysis") \
                        + ") and we did not do it -- hold dropped, AI " \
                        + StringIf(wasAIOff[i], "given back", "was never taken"))
                    Bool dropAIOff = wasAIOff[i]
                    Bool dropPrior = wasUnconscious[i]
                    Float dropPara = wasParalysis[i]
                    If a.IsDead()
                        ; They died during the trace. A corpse is not touched.
                        RememberCorpse(a, dropAIOff, dropPrior, dropPara)
                    Else
                        GiveBack(a, dropAIOff, dropPrior, dropPara)
                    EndIf
                    held[i] = None
                    until[i] = 0.0
                    span[i] = 0.0
                    wasAIOff[i] = false
                    awakeSeen[i] = false
                    releasingAt[i] = 0.0
                Else
                    awakeSeen[i] = true
                    any = true
                EndIf
            Else
                awakeSeen[i] = false
                any = true
            EndIf
        EndIf
        i += 1
    EndWhile
    If CorpsePass()
        any = true
    EndIf
    ; The last self-shove's marker has done its work -- see (p).
    RetireMarker()
    If any
        RegisterForSingleUpdate(5.0)
    EndIf
EndEvent

String Function StringIf(Bool abTest, String asYes, String asNo)
    If abTest
        Return asYes
    EndIf
    Return asNo
EndFunction
