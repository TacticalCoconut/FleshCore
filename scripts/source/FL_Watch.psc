Scriptname FL_Watch extends Quest
{The one thing the DLL cannot do for itself: put objects in the world.

 FleshCore separates flesh from inside the engine, on any hit, with no spell
 and no script running -- so there is nothing to hang an OnEffectStart on.
 This quest watches for what the DLL leaves behind and places the pieces it has
 already forged and already repointed.

 ONE READER, ONE FILE PER WOUND. This used to be a single mailbox file that the
 DLL appended to and that BOTH this script and FL_Wound truncated as they read
 it. That is a shared mutable object with no lock and three parties on it, and
 the consequences were what testing showed: a wound landing between
 a reader's read and that same reader's blanking was ERASED, and its pieces
 never spawned. With the watcher polling twice a second the window was open
 twice a second -- after the first set of pieces dropped, none dropped
 for anyone else.

 Now the DLL writes each wound to its OWN file, named by its own sequence
 number, and nobody truncates anything. This script is the only reader, it
 claims each number exactly once, and there is no shared mutable state left for
 anything to race on. FL_Wound no longer reads at all -- a second reader with
 its own idea of which wounds it had seen would place every piece twice.

 A POLL, DELIBERATELY. An SKSE plugin can dispatch a mod event straight into
 Papyrus, and that would be neater than this; it also means calling one more
 engine address, and an address that is wrong crashes the game rather than
 logging a complaint. A file-existence check twenty times a second cannot crash
 anything, so it is a poll while that address rests on a single source.}

Float Property SpawnClearance = 14.0 Auto
{How far out from their centre a piece is moved before its 3D arrives, so its
 collision shape does not begin inside the ragdoll's. Zero disables it.}

Float Property SpawnLift = 6.0 Auto
{How far up a piece is moved as well, so one cut from a body lying flat clears
 the floor instead of spawning through it.}

Bool Property WoundSplatter = false Auto
{Play the large blood impact once per wound, from the victim's origin. OFF: it
 is fired straight down from a point that is already inside the floor, so the
 decal is clipped by its own projection box -- the square frame with the white
 outline. The per-shard impacts, which land on real surfaces, are unaffected.}

Bool Property UseDismemberingFramework = false Auto
{Hand each placed piece to Dismembering Framework's UpdateLimbScaleAndTint.
 OFF: FleshCore now bakes their real skin colour into the mesh itself, so there
 is nothing left for DF to correct, and the call scales a havok reference --
 which rebuilds its 3D and delays the shard.}

Bool Property ProbeVerbose = false Auto
{Turn the diagnostic traces back on. They are off because they are not free:
 the placement dossier and the live-piece census both run on the path between
 the blow landing and the shard appearing. FL_Chunk has a property of the same
 name; set both to bring the whole picture back.}

FormList Property Pool = None Auto
{Twenty chunk Activators, whose models the DLL repoints at the meshes it
 forged out of the victim's own geometry.}

Float Property Interval = 0.05 Auto
{Seconds between checks. This is the entire delay between the engine
 finishing a wound and the pieces appearing, so it is as short as the engine
 will honour: the check itself is one file-existence test on a name that is
 usually absent, and costs nothing when there is nothing to find. Papyrus will
 not beat a frame whatever is asked of it, so this is the floor.}

ImpactDataSet Property Squish = None Auto
{The same flesh-and-blood impact set the shards use. Played once downward from
 the victim as their wound's shards are placed: the squelch of the wound itself,
 and blood on whatever they are standing over.}

Armor Property Interior = None Auto
{The fallback flesh layers, for a body that arrives with no fill baked into it.
 Now every player-race body is already solid, so the DLL asks for this
 only when it meets a body that has none at all.}

FormList Property SpellList = None Auto
{Every wounding spell this mod defines. FL_Grant hands them over at OnInit,
 which fires once per save -- so a spell APPENDED to the plugin after that day
 would never reach a save that already existed. The watcher re-checks the list
 once a minute and grants whatever is missing, which is how a spell added in a
 later version arrives without a new game.}

Int nextWound = 1
; THE EVENT FILES: FleshCore.ev<N>.txt, read in order like the wound
; files, each one sent on as a mod event from the sender it names. Restarted
; at 1 wherever nextWound is.
Int nextEvent = 1
; The last FL_Wounded payload, verbatim, for get_script_property readers:
; the same string FL_Effects keeps per actor.
String Property LastWound Auto Hidden
Int lastStamp = 0
; THE STAMP IS COMPARED AS TEXT. The DLL writes GetTickCount() | 1
; as an unsigned decimal, and between 24.8 and 49.7 days of machine uptime
; that is above what an Int can hold; what `as Int` makes of such a string
; is undocumented, and if it saturates, every session in
; that fortnight reads as the same number and no new session is ever noticed.
; Text has no such ceiling. lastStamp stays for the trace line.
String lastStampText = ""
Int lastLoad = 0
; The application clock at the last beat that saw no new load, saved with the
; game. It only ever runs forward inside one process, so a first beat that
; finds it AHEAD of the clock is proof of a new process -- see CheckLoad.
Float lastBeatAt = 0.0
Int stripPasses = 0
Int beats = 0
Bool probedSession = false   ; PROBE (see FL_Probe.psc)

; ---- ON-SCREEN DRESSING NOTICES (top-left) --------------------
;
; Debug.Notification is the upper-left corner message. One line per actual
; EQUIP, so it tracks the thing itself rather than the intention: "dressed" the
; first time they put the interior on, "re-seated" when a forced retry takes it
; off and puts it back, and "REFUSED" only when the ENGINE asked for them by name
; and this script turned them down -- which is the one case worth a
; notification, and is rare because the background sweep never sets abForce.
;
; A plain variable, not a script property: FL_Watch's property list is recorded
; in the ESP's VMAD, so adding a property here
; would drag a record change behind it. Flip this to false to silence them.
Bool announceDressing = false
Bool moaned = false

; ---- THE PRE-DRESS AFTER A LOAD ----------------------------------
;
; The dressing cannot be pushed into the loading screen for the
; player and the five NPCs nearest where the save puts them, not into the screen
; itself -- nothing of FleshCore's runs before the actors exist, and this script only
; learns of a load from the DLL's stamp (CheckLoad) -- but it can go to the first beats
; after it, the same slot the decal reconcile already uses. The window takes
; the player once, and on every pass the five nearest living actors in high
; process that WhyRefused accepts; each is offered ONCE per window: whoever
; has something in the body slot gets the interior through Dress() -- the
; sweep's own path, unforced -- and whoever is naked gets the head fill alone
; (their own body carries its meat). The passes repeat only so that an actor
; whose 3D was not up on the first beat is still one of the five when it is.
; See PreDressPass.
;
; Plain variables, not properties, for the reason announceDressing gives.
;
; A NEW VARIABLE'S INITIALISER IS NOT APPLIED TO AN EXISTING SAVE.
; `Bool preDressOnLoad = true` once shipped, and a test log
; printed "pre-dressing ... for 0 passes (head None)" on the fresh save. The
; Papyrus rule: an initialiser is applied when the script instance is CREATED
; (OnInit's moment); an instance rebuilt from a save takes the save's values,
; and a variable the save does not carry takes the TYPE'S default -- false,
; 0, None -- whatever is written beside it here. The log fits that rule (it
; would also fit OnInit having run and set skipFirstWindow; the same fix
; survives both). So a switch that means "on" must be spelled so that FALSE
; is on: preDressOff = false is that switch. Every other variable added alongside it
; means what a zero means and was unaffected.
Bool preDressOff = true      ; flip to TRUE to switch the pre-dress and load-time head learn off

; ---- THE PANEL HOTKEY ------------------------------------------
;
; The panel opens by hotkey, by default a double tap on
; '.'. The key is watched HERE and not in the DLL, and the reason is worth
; writing down: this plugin has no input machinery and facts.h has no input
; address, so a DLL-side key would mean a new engine offset -- a second input path
; and a new crash surface -- to do a thing the engine already does safely from
; up here. When the double tap lands, one spell is cast at the player; the
; DLL's magic sink sees it on the frame it arrives, on the game's thread, and
; toggles the view. The spell IS the signal: no new channel, no polling, no
; file.
;
; EVERY ONE OF THESE MEANS WHAT A ZERO MEANS, by a rule learned the hard way
; -- a variable a save does not carry comes back as the type's default, not
; as the initialiser written beside it. Zero here reads as "the row has not
; been read yet", and the next load reads it.
Int   panelKey    = 0        ; the DX scan code currently registered; 0 = none
Int   panelDouble = 0        ; the double-tap window in ms; 0 = the row has not been loaded
Int   panelSpell  = 0        ; local id of the spell that opens it; 0 = not loaded yet
; The application clock at the previous tap. It serialises with the save and
; comes back from an older session looking like the distant past, which is
; right for a double-tap window: the first tap after a load is a first
; tap. Noted here because CheckLoad goes out of its way to clear
; every OTHER booking made against this clock.
Float panelTapAt  = 0.0
; The MCM's override. 0 = the player has never chosen and the PK row stands,
; -1 = they cleared it deliberately, which is a choice and must not be read as
; "never chose"; anything else is their key. Zero is the only safe spelling for
; unset, because a variable a save does not carry comes back as the type's
; default -- the rule above.
Int   panelKeyMCM = 0
Bool skipFirstWindow = false ; set by OnInit: a NEW GAME's first stamp opens no window (the Helgen cart)
Int predressPasses = 0       ; passes left in the window; 0 is closed
Int predressChanged = 0      ; actors on whom the window put an interior or a head
Int predressSeen = 0         ; the longest high-process list any pass of the window saw
Bool predressPlayerDone = false
Form[] predressDone          ; targets already offered this window (they still count among the five)
Form[] predressSkip          ; actors the gate refused, or dead, this window (they do not count)
Int predressDoneN = 0
Int predressSkipN = 0
String lastGrantsRaw = "-"
String lastPiecesRaw = "-"   ; what FleshCore.pieces.txt said when LearnPieceCap last read it
Bool piecesTrimPending = false   ; the floor is still over a lowered cap -- FL_Chunk.TrimPieceRing every four beats

; THE ENGINE ASKS FOR A MODEL ONCE, SO EVERY PLACED PIECE IS WATCHED.
;
; The forged files are sound -- a piece
; that loaded and a piece that never did differ in nothing but their vertex
; counts, parsed field against field. The paths are right, the records hold,
; placement runs. And still, within one wound, placed in one frame, one
; piece can appear while the piece beside it never does, and the odds fall
; as a session goes on.
;
; That is a race on OPENING the file, lost sometimes, then usually -- any
; other process holding each new file while it reads it fits
; this shape.
; Skyrim asks for a model ONCE: lose the race and the reference
; stays 3D-less forever, and its piece never
; drops.
;
; So placement is not fire-and-forget. Every placed piece is remembered
; here with the moment it was placed, and Heal() watches it: a piece
; that gets its 3D leaves the watch, and one still without 3D after
; twenty seconds is written to the log and its slot released.
; Nothing is deleted or placed again: a deadline cannot know how long a
; piece needs, and Heal() explains what a retry cost. A watch needs only
; the piece and when it was placed, which is what these two arrays
; hold.
ObjectReference[] hRef
Float[] hWhen
; Where the next remembered piece goes. A ring, so the slot it points at is
; both the first unused one and, after a wrap, the oldest -- see Remember.
Int hCursor = 0

; RETIRING PIECES BY POOL RECORD WAS TRIED AND WITHDRAWN.
;
; This once deleted the previous piece from a record as that record was claimed
; again, on the theory that the twenty-first piece of a session -- the first to
; reuse a record -- was where parts stopped appearing. It was not: in testing
; pieces stopped after the FIRST wound, long before any record
; came round. What the retirement did do was kill pieces at roughly ten seconds
; old under fast casting, well inside the forty-five seconds FL_Chunk gives them
; and possibly before their 3D had even finished arriving.
;
; FL_Chunk has managed its own lifetime since it was written. It does so again.

Event OnInit()
    ; A quest script's OnInit runs once, when the quest starts: on a new game,
    ; or when this plugin first enters an existing save. The DLL stamps a new
    ; game exactly like a load, so CheckLoad fires in the first beats of the
    ; Helgen cart; the pre-dress window and the load-time head learn
    ; sit that one out -- six equips and six biped rebuilds in a scripted
    ; scene is not what they are for. The random sweep runs there exactly as
    ; it always has. On the existing-save case the flag costs one window, and
    ; the next load has it.
    skipFirstWindow = true
    RegisterForModEvent("PaSo_TrapFollower", "OnPaSoTrapFollower")
    Quest mcm = Game.GetFormFromFile(0x000A01, "FleshCore.esp") as Quest
    If mcm != None
        mcm.EnsureRegistered()
    EndIf
    RegisterForSingleUpdate(Tick())
EndEvent

Event OnKeyDown(Int keyCode)
    {The double tap that opens the panel.

     CHEAP FIRST. This fires for one registered key only, but it fires on every
     press of it, so the two tests that cost nothing come before the two that
     do not.

     MENU MODE IS REFUSED. A '.' typed into the console, or into any text field
     the game owns, must not open a configuration panel behind it.
     IsInMenuMode is false while the panel itself is up -- a PrismaUI view is
     not one of the game's menus -- so the same double tap still closes it,
     which is what a toggle is for.}
    If keyCode != panelKey || panelKey <= 0 || panelSpell <= 0
        Return
    EndIf
    If Utility.IsInMenuMode()
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    If panelTapAt > 0.0 && (now - panelTapAt) <= (panelDouble as Float) / 1000.0
        ; A tap that completed a pair is spent: three taps are one open and
        ; then a first tap, not two opens.
        panelTapAt = 0.0
        Actor player = Game.GetPlayer()
        Spell open = Game.GetFormFromFile(panelSpell, "FleshCore.esp") as Spell
        If open && player
            ; Source and target both the player -- the idiom the retired quest and
            ; FL_Grind already use for a self-delivered spell.
            open.Cast(player, player)
        Else
            Debug.Trace("[FleshCore] watcher: the panel spell " + panelSpell \
                        + " is not in the plugin -- the double tap did nothing")
        EndIf
    Else
        panelTapAt = now
    EndIf
EndEvent

Float Function Tick()
    {THE PROPERTY CANNOT BE TRUSTED TO BE FAST. A property filled in the plugin
     record beats the default written here, and the test log says the value it
     is actually running with is 0.5 -- five hundred milliseconds of dead time
     between the engine finishing a wound and anything appearing. That is most
     of the short delay seen in testing before the pieces drop.

     So the property is honoured only if it asks for something at least this
     quick. Anything slower, or unset, gets a twentieth of a second, which is
     about as fine as Papyrus will actually deliver.}
    If Interval <= 0.0 || Interval > 0.05
        Return 0.05
    EndIf
    Return Interval
EndFunction

Event OnUpdate()
    beats += 1
    ; PROBE -- once per session, dump what the ENGINE actually loaded for
    ; FL_Interior: its armature, each addon's slot mask, mesh path and full race
    ; list. An offline reading sees only the ESP bytes on
    ; disk, and this is where those can disagree with what got loaded.
    If ProbeVerbose && !probedSession
        probedSession = true
        FL_Probe.Session(Interior)
    EndIf
    ; A LOAD IS CHECKED FIVE TIMES A SECOND, NOT ONCE.
    ;
    ; The session check below is once a second because a session change costs
    ; nothing to notice late. A LOAD does: until this fires, every target on
    ; screen is still wearing marks from a timeline that has been undone, and
    ; the wound files of that timeline are still sitting there waiting to be
    ; replayed onto them. Drain() reads a file on every single tick, so four
    ; extra reads a second is not a cost worth weighing against a second of
    ; that.
    If beats % 4 == 0
        CheckLoad()
        StripPass()
        ; The same slot, on purpose: the first pre-dress pass runs in the very
        ; beat that noticed the load, and the rest follow at a fifth of a
        ; second while 3D arrives. Costs nothing outside its window.
        PreDressPass()
    EndIf
    ; The engine restarts its wound numbering every session and stamps the
    ; session so this script knows to restart with it. Checked once a second;
    ; anything more often is a file read for nothing.
    If beats % 20 == 0
        CheckSession()
    EndIf
    ; BEFORE Drain, deliberately: Drain is where a wound kills the player and
    ; raises the death camera, and a restore beat that ran after it in the
    ; same frame could undo the raise before a frame was drawn.
    If beats % 20 == 7
        DeathCamBack(false)
    EndIf
    Drain()
    ; THE ENGINE'S EVENTS, every other beat: one file test when idle.
    If beats % 2 == 0
        EventPass()
    EndIf
    ; EVERY BEAT, AND IT HAS TO BE. A registered lift is due three beats after
    ; the wound that asked for it -- a seventh of a second -- so a pass that ran
    ; on any slower schedule than the tick itself would be the delay rather than
    ; measuring it. It walks four slots and does nothing at all when they are
    ; empty, which is every beat but the two or three after a Detonate.
    TrunkLiftPass()
    ; A revived target is looked at again a second later, and again after that,
    ; until they are actually up -- see ReviveCheckPass. Twice a second, like the
    ; bleed: its deadlines are seconds apart, and Heal's note above says what a
    ; sixteen-slot walk on every beat costs for nothing.
    If beats % 10 == 3
        ReviveCheckPass()
    EndIf
    If beats % 5 == 2
        VoiceMouthPass()
    EndIf
    ; Twice a second is enough for a pool that grows over twelve seconds, and
    ; it keeps the spend predictable: at most two marks a second per bleeding
    ; target, whatever the frame rate is doing.
    If beats % 10 == 5
        TrunkBleedPass()
    EndIf
    ; HEAL IS A WATCH, NOT A DEADLINE, so it does not need every tick. It walks
    ; thirty-two slots and asks Is3DLoaded() of each live one; at a twentieth
    ; of a second that was up to two hundred native calls a second spent
    ; confirming that pieces which load in a third of a second have loaded.
    ; Every half second says the same thing for a twentieth of the cost.
    If beats % 10 == 0
        Heal()
    EndIf
    ; DRESSING IS LATENCY AFTER ALL, and the test log settled it. The DLL
    ; writes FleshCore.dress.txt the instant it voxelises a target hollow --
    ; RequestDressing rewrites the whole file on every undressed wound -- so the
    ; request is on disk within milliseconds. What was slow was this side.
    ;
    ; At 40 beats and a measured tick of about a tenth of a second, that is one look every four
    ; seconds, and a target is normally cut within a second or two of being
    ; walked up to. Every one of those cuts opened a body whose meat had been
    ; asked for and not yet delivered, and a target could wait over a minute
    ; between being asked for
    ; and their geometry finally changing.
    ;
    ; It is ONE file read. Drain() already reads a file on every single tick and
    ; the comment above it makes exactly this argument for exactly this reason.
    ; Four beats is ~0.4s, a tenth of the old wait for a tenth of Drain's cost.
    If beats % 4 == 0
        DressRequested()
        ReviveRequested()
        ; a lowered piece cap is cleared down to in batches of 32, one
        ; batch every four beats, so a big drop never holds this tick up.
        If piecesTrimPending
            piecesTrimPending = FL_Chunk.TrimPieceRing()
        EndIf
    EndIf
    ; THE BACKGROUND SWEEP IS THE HEAVIEST THING ON THIS TICK, and it is pure
    ; housekeeping. FindRandomActorFromRef searches a 3000-unit radius and Dress
    ; then inspects whoever it finds; the tick already runs slower
    ; than the 0.05s asked for, which means the VM is not keeping up, and every
    ; tick it falls behind is added to the delay between a blow landing and its
    ; shards being placed. Once every thirty seconds is plenty for finding a
    ; target who has no interior yet.
    ; WIDENED, BUT NOT BY MUCH, AND THE COMMENT ABOVE IS WHY.
    ;
    ; This sweep is the ONLY net that reaches a target the engine cannot
    ; classify -- one whose outfit covers them completely and supplies no body,
    ; so no shape of theirs reads as player-race skin and the DLL's own eligibility
    ; test refuses them before it can ask for anything. The wound path now asks
    ; on their behalf, but only once they have been shot at; this is what gets them
    ; ready beforehand.
    ;
    ; One random actor every thirty seconds was too thin a net for that. Two
    ; every ten seconds is six times the reach for two extra native calls in
    ; that window, and Dress refuses a non-target in three cheap tests before
    ; it touches anything. The tick ALREADY runs slower than the
    ; 0.05s asked for, so this is the most it may cost.
    If beats % 40 == 0
        String gnow = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.grants.txt")
        If gnow != lastGrantsRaw
            RegrantSpells()
        EndIf
        ; the HQ's "Pieces kept on the ground", one more small file on
        ; the same beat as the grants; acted on only when it changed.
        LearnPieceCap(false)
    EndIf
    If beats >= 1200
        beats = 0
        AssertIdentity()
        RegrantSpells()
        Debug.Trace("[FleshCore] watcher alive (tick " + Tick() + "s, next wound " + nextWound + ")")
    EndIf
    RegisterForSingleUpdate(Tick())
EndEvent

; ============================ ACHERON ==================================
;
; A DEFEAT FRAMEWORK CAN EAT EVERY KILL.
;
; Acheron's own log, read during testing: "Loaded 3 Victims from cosave",
; "Loaded 3 Pacified from cosave". Its purpose is to intercept a death and
; convert it to DEFEAT, and its own header states the consequence:
;
;   ; A defeated actor is bleeding out and immune to damage
;   ; A defeated actor is always pacified
;
; Bleeding out is ALIVE. That one mechanism was behind three separate test
; results: the player getting up without a body after a grind, an NPC being
; impossible to revive, and a skull spell alone not killing. FleshCore's Kill()
; was never late and never unattributed-and-ignored -- it was being converted.
;
; Everything below uses Acheron's own documented API:
;   Function DisableProcessing(bool abDisable) native global   ; hit processing
;   bool Function IsDefeated(Actor akActor) native global
;   Function RescueActor(Actor akActor, bool abRelease = true) native global
;
; GUARDED, because a native global from a plugin that is not installed errors at
; runtime. The check is Game.IsPluginInstalled and it is cached, because it
; cannot change within a session.

Int  acheronKnown = 0        ; 0 unasked, 1 present, -1 absent
Int  killGuard = 0           ; kills in flight under Acheron's switch -- see KillForReal
Armor headFill = None        ; the head armour, learned from either mailbox -- or from the config's X row at a load
Armor retiredHead = None     ; FL_Head (0x860), resolved once, taken off when it is not headFill
Bool  retiredHeadAsked = false
; the knockout register, FL_KOHold_Quest (0x88D), resolved once by
; local id like the retired head -- a property would be one more entry in this
; quest's script data, and FormIDs never move in this plugin. See Hold().
Quest koHold = None
Bool  koHoldAsked = false
Race  beast1 = None          ; the four races the head fill was never built for
Race  beast2 = None
Race  beast3 = None
Race  beast4 = None
Bool  beastAsked = false
Keyword noStripKey = None    ; the scene framework's NoStrip, resolved once per session
Bool  noStripAsked = false

; ---- THE DEATH HOLD ---------------------------------------------
;
; One actor at a time whose next dismemberment must NOT kill them: the retired quest
; takes their head with FleshCore's own Decapitate while they are knocked out, and
; the design is "beheaded but not dead". Drain honours it in the two places a
; wound kills -- Dismember, and the player-dies-of-anything rule -- and nowhere
; else: they still bleed, their pieces still land, a Detonate still lifts them.
;
; The deadline is real time and it survives a clock restart the way
; FL_KO_Hold's does: (until - now) can never exceed the span within one
; session, so a larger value means the application restarted, and the hold is
; re-based rather than left open for hours. the retired quest releases it itself on
; every path; the deadline is the net under that.
Actor heldDeath = None
Float heldDeathUntil = 0.0
Float heldDeathSpan = 0.0

; ---- THEIR INTERIOR STAYS ON THROUGH A the scene framework SCENE -----------------
;
; the scene framework strips by biped slot, and its default female strip mask has 30, 47 and
; 54 in it -- the test head, and the slots the fill and the lining wear. So a
; target who went into a scene solid came out of it hollow, and a Detonate at
; the end of one (which is what a consumer now does) found no head to split. the scene framework's
; own exemption is a keyword, NoStrip (the scene plugin 0x2F16E), on the armour
; itself; stamping head armour with it is established practice among
; head-replacement mods, and it is done here the same way. The stamp is not saved
; with the game, so it is made again on every engine session and every load,
; and once more when the head armour is first learned from a mailbox.
Bool Function StampNoStrip(Form akWhat)
    If akWhat == None
        Return false
    EndIf
    ; RESOLVED ONCE, like RetiredHead() and IsBeast(). DressRequested calls
    ; this on every non-empty mailbox read -- five times a second -- and the
    ; two lookups below sat ABOVE the HasKeyword early-out, so a keyword that
    ; was stamped once was re-resolved by filename for the rest of the session.
    ; Cleared on load with the other caches, because a Form resolved in one
    ; session is not one to trust in the next.
    If !noStripAsked
        noStripAsked = true
        If Game.IsPluginInstalled("FleshCore.esp")
            noStripKey = None
        EndIf
    EndIf
    Keyword noStrip = noStripKey
    If noStrip == None
        Return false
    EndIf
    If akWhat.HasKeyword(noStrip)
        Return true
    EndIf
    PO3_SKSEFunctions.AddKeywordToForm(akWhat, noStrip)
    Debug.Trace("[FleshCore] NoStrip keyword stamped on " + akWhat)
    Return true
EndFunction

Function StampAllNoStrip()
    StampNoStrip(Interior)
    ; The head armour is learned from a mailbox, and on a save that has never
    ; asked for a dress it is still None here -- which would leave the head
    ; strippable in exactly the first scene this exists for. So the shipped
    ; head is stamped by its own id when nothing better is known: FL_Head is
    ; 0x860 in this plugin's frozen layout (the X row of the config carries the
    ; same number), and a learned head, when there is one, is stamped as well.
    ; BOTH OF THEM, ALWAYS. The fill later moved onto a second armour on
    ; another biped slot, and slot 47 is in the scene framework's default strip mask exactly
    ; as 30 was. Stamping only the learned one leaves the other strippable in
    ; the first scene of a session that has not yet had a mailbox -- and which
    ; one is "the other" depends on a config row, which is the wrong thing for
    ; this to depend on. Both ids are frozen-layout facts.
    StampNoStrip(Game.GetFormFromFile(0x00000860, "FleshCore.esp") as Armor)
    StampNoStrip(Game.GetFormFromFile(0x0000088C, "FleshCore.esp") as Armor)
    If headFill
        StampNoStrip(headFill)
    EndIf
EndFunction

Bool Function HasAcheron()
    If acheronKnown == 0
        If Game.IsPluginInstalled("Acheron.esm")
            acheronKnown = 1
        Else
            acheronKnown = -1
        EndIf
        Debug.Trace("[FleshCore] Acheron " + (acheronKnown == 1))
    EndIf
    Return acheronKnown == 1
EndFunction

Function HoldDeath(Actor who, Float seconds = 300.0)
    {Their next dismemberment does not kill them, for `seconds` or until released.}
    If !who
        Return
    EndIf
    If heldDeath && heldDeath != who
        Debug.Trace("[FleshCore] death hold moves from " + heldDeath + " to " + who)
    EndIf
    heldDeath = who
    heldDeathSpan = seconds
    heldDeathUntil = Utility.GetCurrentRealTime() + seconds
    Debug.Trace("[FleshCore] death HELD on " + who + " for " + seconds + "s")
EndFunction

Function ReleaseDeath(Actor who)
    {The hold comes off. Only theirs: releasing somebody else's is a no-op.}
    If who && heldDeath == who
        heldDeath = None
        heldDeathUntil = 0.0
        heldDeathSpan = 0.0
        Debug.Trace("[FleshCore] death RELEASED on " + who)
    EndIf
EndFunction

Bool Function DeathHeld(Actor who)
    {Is their death held right now? Expiry and a restarted clock are handled here,
     on the read, so nothing has to tick for the hold to lapse.}
    If !who || heldDeath != who
        Return false
    EndIf
    Float now = Utility.GetCurrentRealTime()
    If (heldDeathUntil - now) > heldDeathSpan
        heldDeathUntil = now + heldDeathSpan
        Debug.Trace("[FleshCore] the real-time clock restarted under the death hold on " + who + " -- re-based")
    EndIf
    If now > heldDeathUntil
        Debug.Trace("[FleshCore] the death hold on " + who + " EXPIRED")
        heldDeath = None
        heldDeathUntil = 0.0
        heldDeathSpan = 0.0
        Return false
    EndIf
    Return true
EndFunction

Function KillForReal(Actor vic)
    {Kill them past the defeat framework.

     DisableProcessing is Acheron's own switch for exactly this and it is
     GLOBAL, so it is a debt in the way every other hold in this mod is: it goes
     off, the kill lands, it comes straight back on, with nothing between them
     that can return early. Held for one call and no longer.

     AND THEN IT CHECKS. Acheron's switch is documented as disabling HIT
     processing, and whether that covers a scripted Kill() is not something this
     file can prove from the header -- so if they come out of it still defeated,
     the log says so rather than leaving it to be rediscovered in play.}
    If !vic
        Return
    EndIf
    If vic == Game.GetPlayer()
        Game.SetPlayerAIDriven(false)
        Game.EnablePlayerControls(true, true, true, true, true, true, true, true, 0)
    EndIf
    Bool guarded = HasAcheron()
    If guarded
        ; A GLOBAL SWITCH, COUNTED. This runs on this script's beat and
        ; on the retired quest's thread; two kills in flight used to let the first
        ; one's re-enable land under the second one's Kill().
        killGuard += 1
        Acheron.DisableProcessing(true)
        Acheron.DisableConsequence(true)
        If Acheron.IsDefeated(vic) || Acheron.IsPacified(vic)
            Acheron.RescueActor(vic, true)
            Acheron.ReleaseActor(vic)
        EndIf
    EndIf
    ActorBase ab = vic.GetActorBase()
    If ab
        If ab.IsEssential()
            ab.SetEssential(false)
        EndIf
        If ab.IsProtected()
            ab.SetProtected(false)
        EndIf
    EndIf
    vic.EndDeferredKill()
    vic.Kill()
    If !vic.IsDead()
        vic.KillEssential()
    EndIf
    If !vic.IsDead()
        vic.KillSilent()
    EndIf
    If guarded
        If Acheron.IsDefeated(vic) || Acheron.IsPacified(vic)
            Debug.Trace("[FleshCore] " + vic + " was defeated/pacified across Kill() -- rescuing and re-killing")
            Acheron.RescueActor(vic, true)
            Acheron.ReleaseActor(vic)
            vic.Kill()
            If !vic.IsDead()
                vic.KillEssential()
            EndIf
        EndIf
        killGuard -= 1
        If killGuard <= 0
            killGuard = 0
            Acheron.DisableProcessing(false)
            Acheron.DisableConsequence(false)
        EndIf
    EndIf
    If !vic.IsDead()
        vic.StopCombat()
        vic.StopCombatAlarm()
        vic.SetActorValue("Aggression", 0.0)
        vic.SetActorValue("Assistance", 0.0)
        vic.SetUnconscious(true)
        vic.SetRestrained(true)
        vic.SetNoBleedoutRecovery(true)
        vic.SetActorValue("Paralysis", 1.0)
        Float curHP = vic.GetActorValue("Health")
        If curHP > -500.0
            vic.DamageActorValue("Health", curHP + 1000.0)
        EndIf
    EndIf
EndFunction

Function AssertIdentity()
    {Re-write where this plugin landed, every minute, from the one script that
     is always running.

     FL_Grant writes FleshCore.ids.txt in OnInit -- which fires ONCE per save.
     When the plugin's load-order identity moves (an ESL flag change does it),
     the stale file points the DLL at records that no longer exist and the
     engine sits disarmed with no other code path that would ever correct it.
     This script extends Quest on the same record, so its own FormID is the
     same fact FL_Grant writes; asserting it once a minute means any future
     identity change heals within a minute of loading, instead of never.}
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.ids.txt", "" + Self.GetFormID(), false, false)
    Quest mcm = Game.GetFormFromFile(0x000A01, "FleshCore.esp") as Quest
    If mcm != None
        mcm.EnsureRegistered()
    EndIf
EndFunction

Function RegrantSpells()
    {Hand over any spell the player has not got, once a minute, forever.

     FL_Grant does this in OnInit -- which fires ONCE, on the save that first
     loaded the plugin. Every spell added to this mod after that day would
     therefore never reach a save that already existed: the record is in the
     file, the record is in the spell list, and nothing ever looks at the list
     again.

     The list is read through this script's OWN property rather than by reaching
     across to FL_Grant, which sits on the same quest record: Caprica will not
     cast between two sibling scripts, and a property costs nothing but a line
     in the plugin's script data -- no record, no FormID, nothing that can
     renumber. This is the same self-healing shape as AssertIdentity: the fix
     is a minute of patience rather than a new save.}
    ; ---- THE RETIREMENT FIRST, because it does not need the list ---------
    ;
    ; A spell that is no longer in FL_SpellList stops being GRANTED, and that
    ; is all it stops: a save that already has it keeps it forever, castable
    ; and inert, because its wound row is gone from the config too. These two
    ; were meant to go, so they are removed from them as well.
    ;
    ; By local id and not by property: adding two properties would mean two
    ; more entries in the plugin's script data, and these records are being
    ; retired, not wired in. FormIDs never move in this plugin, so 0x888 and
    ; 0x88A are facts.
    ;
    ; DropSpell used to sit at the bottom of this function, under the
    ; `If !SpellList` return -- so on a save whose SpellList property failed to
    ; fill, the two retired spells would never come off the player at all.
    ; Taking something away has nothing to do with the list of things to give.
    Int gone = 0
    gone += DropSpell(0x00000888)         ; FL_DetonateAlt_Spell
    gone += DropSpell(0x0000088A)         ; the alt burst spell
    ; ---- The retired Sequence -----------------------------------------------------------
    ; The Sequence is not offered: its two spells are
    ; retired outright (the effect stub is a no-op, the HQ neither lists nor grants
    ; them, the grant loop below refuses them whatever grants.txt says, and
    ; FL_Api.Cast refuses them). The four white-mark spells are no longer
    ; granted by the base mod: the records stay (the FL_Api kinds the alt mark /
    ; the alt burst still resolve them, consumers cast 0x885 directly), they are
    ; simply off the player's spellbook and out of FL_SpellList. Same DropSpell
    ; precedent, same reason as 0x888/0x88A above.
    gone += DropSpell(0x00000894)         ; retired spell 0x894        -- retired
    gone += DropSpell(0x000008A9)         ; retired spell 0x8A9       -- retired
    gone += DropSpell(0x00000846)         ; the mark spell         -- "Splatter (White)": no longer granted by the base mod
    gone += DropSpell(0x00000852)         ; the self mark spell     -- "Splatter (White, Self)": FL_Api kind "the alt mark" still resolves it
    gone += DropSpell(0x00000882)         ; the alt burst spell     -- "Detonate (White)"
    gone += DropSpell(0x00000885)         ; the self alt burst spell -- "Detonate (White, Self)": FL_Api kind "the alt burst"; consumers cast it directly
    If gone > 0
        Debug.Notification("[FleshCore] " + gone + " retired spell(s) removed")
        Debug.Trace("[FleshCore] watcher removed " + gone + " retired spell(s)")
    EndIf
    If !SpellList
        Return
    EndIf
    Actor player = Game.GetPlayer()
    If !player
        Return
    EndIf
    ; ---- THE GRANT GATE -----------------------------------------
    ;
    ; Design note: ALL spells created so far are treated
    ; as debug spells. A published library does not put sixty
    ; spells in a stranger's spellbook. So the list is no longer the truth
    ; about who gets what; FleshCore.grants.txt is -- one decimal local id per
    ; line, the panel writes it, this reads it, and both directions are
    ; enforced: a spell on the list is added, a spell off it is removed.
    ;
    ; THE FILE IS THE ONLY TRUTH, AND NOTHING HERE FILLS IT. (it was once seeded
    ; from the spellbook on every load; the watcher no longer does that.)
    ; SeedGrants below only creates the file EMPTY when it is missing -- it
    ; never reads the spellbook. The HQ's Grant / Revoke writes the file (the
    ; DLL's "FleshCore.grants.txt written" line); this syncs the loaded save's
    ; spellbook TO the file's content for the spells in FL_SpellList -- listed
    ; and missing is added, unlisted and present is removed -- on every load,
    ; every minute, and within seconds of the file changing (OnUpdate re-reads
    ; it every 40 beats). So a save with spells and no file loses them on the
    ; first beat, and whatever the file lists reaches any save that loads. The
    ; one thing this never does is invent a grant.
    String gfile = "Data/SKSE/Plugins/FleshCore.grants.txt"
    SeedGrants()
    String rawGrants = MiscUtil.ReadFromFile(gfile)
    lastGrantsRaw = rawGrants
    ; Framed with newlines so "22" cannot match inside "2221".
    String granted = "\n" + rawGrants + "\n"
    Int i = 0
    Int n = 0
    Int taken = 0
    While i < SpellList.GetSize()
        Spell sp = SpellList.GetAt(i) as Spell
        If sp
            Int lid = Math.LogicalAnd(sp.GetFormID(), 0xFFFFFF)
            ; 0x894 / 0x8A9 are retired: never wanted, whatever the file says.
            Bool want = lid != 0x894 && lid != 0x8A9 && StringUtil.Find(granted, "\n" + lid + "\n") >= 0
            Bool has = player.HasSpell(sp)
            If want && !has
                player.AddSpell(sp, false)
                n += 1
            ElseIf !want && has
                player.RemoveSpell(sp)
                taken += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    ; Also sync the self-amputation and self-detonate spells in FleshCore.esp (0x089E, 0x08A0, 0x08A2, 0x08A4, 0x08A6)
    Int[] selfLimbIds = new Int[5]
    selfLimbIds[0] = 0x089E
    selfLimbIds[1] = 0x08A0
    selfLimbIds[2] = 0x08A2
    selfLimbIds[3] = 0x08A4
    selfLimbIds[4] = 0x08A6
    Int sl = 0
    While sl < 5
        Int slid = selfLimbIds[sl]
        Spell ssp = Game.GetFormFromFile(slid, "FleshCore.esp") as Spell
        If ssp
            Bool swant = StringUtil.Find(granted, "\n" + slid + "\n") >= 0
            Bool shas = player.HasSpell(ssp)
            If swant && !shas
                player.AddSpell(ssp, false)
                n += 1
            ElseIf !swant && shas
                player.RemoveSpell(ssp)
                taken += 1
            EndIf
        EndIf
        sl += 1
    EndWhile
    Spell panelSp = Game.GetFormFromFile(0x08C3, "FleshCore.esp") as Spell
    If panelSp && player.HasSpell(panelSp) && StringUtil.Find(granted, "\n" + 0x08C3 + "\n") < 0
        player.RemoveSpell(panelSp)
        taken += 1
    EndIf
    ; Remove any lingering DismembermentSpells.esp spells if present on an existing save
    If Game.IsPluginInstalled("DismembermentSpells.esp")
        Int dsi = 0x0813
        While dsi <= 0x0824
            Spell dssp = Game.GetFormFromFile(dsi, "DismembermentSpells.esp") as Spell
            If dssp && player.HasSpell(dssp)
                player.RemoveSpell(dssp)
                taken += 1
            EndIf
            dsi += 1
        EndWhile
        Spell dsSelf = Game.GetFormFromFile(0x0827, "DismembermentSpells.esp") as Spell
        If dsSelf && player.HasSpell(dsSelf)
            player.RemoveSpell(dsSelf)
            taken += 1
        EndIf
        Int dsdi = 0x0832
        While dsdi <= 0x083A
            Spell dsdsp = Game.GetFormFromFile(dsdi, "DismembermentSpells.esp") as Spell
            If dsdsp && player.HasSpell(dsdsp)
                player.RemoveSpell(dsdsp)
                taken += 1
            EndIf
            dsdi += 1
        EndWhile
    EndIf
    If n > 0
        Debug.Notification("[FleshCore] " + n + " spell(s) granted")
        Debug.Trace("[FleshCore] watcher granted " + n + " spell(s) from the grants file")
    EndIf
    If taken > 0
        Debug.Notification("[FleshCore] " + taken + " spell(s) withdrawn")
        Debug.Trace("[FleshCore] watcher withdrew " + taken + " spell(s) the grants file does not list")
    EndIf
EndFunction

Function SeedGrants(Bool onLoad = false)
    {Ensure FleshCore.grants.txt exists, starting empty so no FleshCore spells
     are ever granted by default unless explicitly granted in the HQ menu.}
    String gfile = "Data/SKSE/Plugins/FleshCore.grants.txt"
    If !MiscUtil.FileExists(gfile)
        MiscUtil.WriteToFile(gfile, "", false, false)
        Debug.Trace("[FleshCore] watcher: created empty FleshCore.grants.txt (no spells granted by default)")
    EndIf
EndFunction

Int Function DropSpell(Int localId)
    {Take one retired spell off the player. Returns 1 if it was there.}
    Spell sp = Game.GetFormFromFile(localId, "FleshCore.esp") as Spell
    Actor player = Game.GetPlayer()
    If sp && player && player.HasSpell(sp)
        player.RemoveSpell(sp)
        Return 1
    EndIf
    Return 0
EndFunction

Bool Function IsBeast(Actor a)
    {Argonian or Khajiit, either living or vampire.

     RESOLVED ONCE, like RetiredHead(). Four Game.GetFormFromFile calls per
     SeatHead would be up to a thousand mod-by-filename lookups a second on a
     busy dressing pass -- none of them short-circuits for a human, which is
     the common case.}
    If !beastAsked
        beastAsked = true
        beast1 = Game.GetFormFromFile(0x00013740, "Skyrim.esm") as Race  ; Argonian
        beast2 = Game.GetFormFromFile(0x0008883A, "Skyrim.esm") as Race  ; Argonian vampire
        beast3 = Game.GetFormFromFile(0x00013745, "Skyrim.esm") as Race  ; Khajiit
        beast4 = Game.GetFormFromFile(0x00088845, "Skyrim.esm") as Race  ; Khajiit vampire
    EndIf
    Race rc = a.GetRace()
    Return rc && (rc == beast1 || rc == beast2 || rc == beast3 || rc == beast4)
EndFunction

FL_KO_Hold Function Hold()
    {The knockout register, or None on a plugin without one. Asked before a
     Restore resurrects anybody -- see ReviveRequested -- and told afterwards.
     Says so, once per session, if it cannot be found: a silent None here
     would bring the old failure back with nothing in the log to say why.}
    If !koHoldAsked
        koHoldAsked = true
        koHold = Game.GetFormFromFile(0x0000088D, "FleshCore.esp") as Quest
        If !(koHold as FL_KO_Hold)
            Debug.Trace("[FleshCore] the knockout register (FL_KOHold_Quest 0x88D) could not be resolved -- Restore will treat knocked-out targets as down")
        EndIf
    EndIf
    Return koHold as FL_KO_Hold
EndFunction

Armor Function RetiredHead()
    {FL_Head, 0x860 -- the slot-30 head FleshCore used to equip.

     RESOLVED ONCE. Dress() runs up to five times a second per name in the
     mailbox, and a by-filename lookup on every one of those is the kind of
     cost this script caches everywhere else.}
    If !retiredHeadAsked
        retiredHeadAsked = true
        retiredHead = Game.GetFormFromFile(0x00000860, "FleshCore.esp") as Armor
    EndIf
    Return retiredHead
EndFunction

Function SeatHead(Actor a)
    {PUT THE HEAD FILL ON THEM, AND TAKE OFF THE RETIRED ONE.

     Which armour `headFill` is comes from field zero of either mailbox, and
     the engine reads it from one line of FleshCore.cfg.txt. Now that
     line names FL_HeadFill, which lives on biped slot 47 and leaves their own
     head alone; before it, it named FL_Head, which lives on slot 30 and made
     the engine hide their real head -- which is why every dressed target used to
     be bald.

     The retired armour is named by its local id rather than by a property:
     FormIDs never move in this plugin, so 0x860 is a fact, and adding a
     property to retire a record is the wrong way round. It is taken off ONLY
     when it is not the one the config named.

     PUT THE X ROW BACK TO FL_Head AND THIS SEATS IT AND NOTHING ELSE -- but
     not quite as the old code did, and the difference is deliberate: this function
     also refuses a beast target and refuses to fight another mod for the slot,
     and the old code did neither. On the rollback path that means a target wearing a
     slot-30 helmet keeps it and gets no head fill, where the old code would have
     knocked the helmet off.}
    If !a || !headFill
        Return
    EndIf
    ; ---- NOT WHILE THE SEQUENCE OWNS THEIR DEATH ------------------
    ;
    ; They are decapitated ON PURPOSE for as long as DeathHeld(a) is true --
    ; the retired quest's own "a neck cut that needs no skull" -- and neither the
    ; dress mailbox nor the general sweep knew that: RequestDressing fires
    ; the instant their Decapitate wound leaves them without a head fill, the
    ; same way it would for any ordinary wound, and this function used to
    ; seat the fill right back on regardless of why they have none. The equip
    ; that followed rebuilt their 3D; the DLL's own watch noticed and re-cut
    ; the newly-seated shape onto their still-standing wound the moment it
    ; did (flesh.cpp's WatchOne / the warm thread's reread, "put back: N
    ; wounded cell(s) re-cut onto their new 3D") -- and the mark saw their head
    ; reappear and vanish again mid-scene, one of the bugs seen in testing.
    ; PreDressOne already refuses this for the load sweep alone (its own
    ; "neck cut that needs no skull" note, gated on Unconscious/Paralysis);
    ; this is the same refusal, asked the more direct way, for every caller
    ; -- the mailbox and the general sweep never had it at all, and even
    ; PreDressOne's own gate does not reach the scene itself, where they are
    ; stood up (LetUp) but still DeathHeld until OnSceneEnd releases them.
    If DeathHeld(a)
        Return
    EndIf
    ; ---- NOT ON A BEAST TARGET -------------------------------------------
    ;
    ; The fill was sampled from a human FaceGen head and nothing about it was
    ; ever measured against an Argonian or a Khajiit: their heads are different
    ; meshes and a human skull inside a muzzle is a bug
    ; with a texture on it. FL_HeadFill is a DefaultRace ARMO and both races
    ; are playable, so WhyRefused lets them through -- this is the only gate.
    ; They keep their own faces and get no fill until there is one built for
    ; them.
    ; THE RETIRED HEAD STILL COMES OFF THEM. They get no fill, but a human
    ; FaceGen head on a lizard is what FL_Head was doing to them and it has to
    ; stop whether or not there is anything to put in its place. Without this,
    ; every Argonian and Khajiit in an existing save keeps the slot-30 head for
    ; the life of that save while the targets around them get their faces back.
    If IsBeast(a)
        Armor beastOld = RetiredHead()
        If beastOld && beastOld != headFill && a.IsEquipped(beastOld)
            a.UnequipItem(beastOld, false, true)
        EndIf
        Return
    EndIf
    ; ---- NOTHING TO DO IS THE COMMON CASE, AND IT COSTS THREE CALLS ------
    ;
    ; Dress() calls this on every pass, up to five times a second per name in
    ; the mailbox, and almost every one of those targets is already correctly
    ; seated. Answering that with GetRace, GetSlotMask, GetWornForm, two
    ; IsEquipped and a GetItemCount is six natives to do nothing.
    ;
    ; BOTH CONDITIONS, though: they are only finished when they wear the head
    ; the config named AND is not still wearing the one it retired. Slot 30
    ; and slot 47 are different slots and they can hold both at once, which is
    ; the state an upgraded save starts in.
    Armor oldHead = RetiredHead()
    Bool stillOld = oldHead && oldHead != headFill && a.IsEquipped(oldHead)
    If a.IsEquipped(headFill) && !stillOld
        Return
    EndIf
    ; ---- AND NEVER FIGHT ANOTHER MOD FOR THE SLOT ------------------------
    ;
    ; The head fill lives on biped slot 47 and it is not alone there.
    ; A large load order can hold hundreds of
    ; records declaring
    ; slot 47, ARMOs among them,
    ; across dozens of mods -- capes, accessory sets and SMP outfits, and no
    ; framework. Slots 61 and 54 are busy too,
    ; and slot 55 -- which FleshCore also ships on --
    ; is busier still.
    ;



    ;
    ; So a collision is not a rare accident, and the wrong answer is to equip
    ; anyway: EquipItem would knock their cape off, their outfit's own script or
    ; the next re-seat would put it back, and the two would take turns for the
    ; rest of the save. They keep what they are already wearing, their head simply
    ; has no fill, and the log names the item so it can be decided rather than
    ; discovered.
    ; THE MASK COMES FROM THE ARMOUR, NOT FROM A NUMBER HERE. Armor.GetSlotMask
    ; is SKSE's own (Armor.psc), so this asks about whatever slot the config
    ; named -- 47 for FL_HeadFill, 30 if the X row is ever pointed back at
    ; FL_Head. A hardcoded 47 would ask the wrong question the moment it is.
    Form worn = a.GetWornForm(headFill.GetSlotMask())
    If worn && worn != (headFill as Form)
        ; NOT Debug.Trace ALONE. Papyrus logging is often off,
        ; so a trace here
        ; would satisfy nobody. One line per collision in a file of its own,
        ; naming the actor and the item that holds the slot, so those records
        ; can be decided about rather than discovered.
        ;
        ; AND THROTTLED, HARD. This is a synchronous open/append/close, and the
        ; path it sits on runs at five hertz per name in the mailbox -- the
        ; same path the re-seat below throttles to one pass in a hundred for
        ; exactly this reason. A beat is 0.05 s and the counter runs to 1200
        ; before it resets, so `beats % 400` is beats 400, 800 and 1200: three
        ; passes a minute, GLOBAL rather than per target -- on one of those
        ; passes every colliding actor in it writes a line. The collision is a
        ; standing state, not an event, so three passes a minute is more than
        ; enough to name it. The Return is OUTSIDE the throttle: they are left
        ; alone on every pass and logged on a few.
        If beats % 400 == 0
            MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.slot.txt", \
                Utility.GetCurrentRealTime() + " " + a + " slot held by " + worn + "\n", \
                true, false)
        EndIf
        Return
    EndIf
    ; ---- AND ONLY NOW DOES THE RETIRED HEAD COME OFF ---------------------
    ;
    ; STRICTLY AFTER the occupancy check, and the order matters. If
    ; the slot is taken they keep everything they had, including the slot-30
    ; head from an older save -- bald, as the old head left them, but with a
    ; skull and a brain in the lattice. Taking the old head off first and then
    ; discovering the new one cannot be seated would leave them with NEITHER,
    ; and a target with no head fill cannot be killed by a head wound at all.
    If stillOld
        a.UnequipItem(oldHead, false, true)
    EndIf
    If a.GetItemCount(headFill) < 1
        a.AddItem(headFill, 1, true)
    EndIf
    If !a.IsEquipped(headFill)
        a.EquipItem(headFill, false, true)
    EndIf
EndFunction

; THE ONE LOAD THIS USED TO MISS. The docstring below says the DLL's
; counter "disagrees with the file exactly once per load" -- WITHIN ONE ENGINE
; SESSION. The DLL's counter starts at zero in every process, so the first
; load of a session is stamp 1, the second stamp 2; and lastLoad is a script
; variable, so it comes back from the save. Load a save that was made after
; the first load of an earlier session, as the first load of this one, and
; the file says 1 and the save says 1: nothing in CheckLoad fired, and at first
; nothing else noticed -- no strip window, no head forget, no
; death-camera restore, on the most ordinary launch there is (launch,
; Continue, play, save, quit; launch, Continue).
; CheckSession is what always notices a new engine session; CheckLoad's
; matched branch asks it on the spot when the application clock proves a new
; process, and CheckSession's own once-a-second slot asks otherwise. On a new
; session it sets lastLoad back to zero and calls CheckLoad again -- same
; slice, before Drain.
;
; (Kept out of the docstring below: Caprica refuses a
; docstring past about four kilobytes -- "Failed while allocating a Heap!" --
; and CheckLoad's is the longest in the file.)
Function CheckLoad()
    {A SAVE WAS LOADED. Two things have to happen, and neither of them can be
     noticed from inside Papyrus.

     WHY THE COUNTER IS IN THE DLL. OnPlayerLoadGame is received by
     ReferenceAlias, ActiveMagicEffect and the player's own Actor scripts
     (SKSE's Actor.psc) -- never by a Quest script -- and an alias added
     to a quest that is already running in a save is never instantiated --
     DecalCore's DC_Load fired exactly zero times across a whole test run
     for that reason. And a
     script cannot notice the load by watching its own state, because its own
     state is what rolled back: this script announced "engine session N
     -- wound sequence restarted at 1" twenty seconds after a load, with the
     session file untouched for four minutes. Nothing had restarted. lastStamp
     had rolled back to a value from the save.

     A counter the DLL owns cannot roll back. Whatever this script's memory of
     it reverts to, it disagrees with the file exactly once per load -- within
     one engine session; the comment above this function has the other case.

     WHAT IT UNDOES.

       * THE WOUND SEQUENCE. nextWound rolls back with everything else, and the
         wound files it then re-claims describe dismemberments that were undone
         by the load. In one test this replayed w1, w2 and w3 onto the
         same two targets four times over the following twenty seconds -- which
         is very likely why voxelisation seemed to survive save loads in testing:
         they came back whole, and then the ghost of the old
         wound cut them apart again. The DLL now deletes those files and rewinds
         its own counter to one on the same event, so both sides restart
         together.
       * THE MARKS -- AND THIS IS NO LONGER A STRIP. Every layer painted
         before the load is still on the node afterwards: DecalCore's
         persist = false writes go into the live 3D and a same-session load does
         not rebuild 3D that is already resident. Those marks belong to a
         timeline the load undid, so they still all have to come off. What is
         new is that they do not all stay off. Field report:

             decals and voxels were cleared on every load, whether or not they
              were there when the save was made.


         So the window now runs both halves in order: DC_Api.StripAll puts every
         live layer back to RaceMenu's default, and DC_Api.RestoreAll then
         repaints whatever the LOADED SAVE's own record says each actor was
         wearing. Load a save made before the paint and the record is empty and
         they end clean; load a save made after it and the record holds their marks
         and they go back on. DecalCore's two containers -- a JsonUtil file that
         survives the load for the strip, StorageUtil in the save for the
         restore -- are what make those two answers different; the note is in
         DC_Api above WornKey().

         BeginRestore is called HERE and not from StripPass because the snapshot
         must be taken once per load, not once per pass: it is the list of who
         still needs putting back, and the passes empty it.}
    String st = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.load.txt")
    If st == ""
        Return
    EndIf
    Int v = st as Int
    If v == lastLoad
        ; THE COLLISION CASE, see the docstring. Noticed on THIS beat
        ; when it can be, and by CheckSession's own slot within a second
        ; otherwise -- without a file read: the application clock never runs
        ; backwards inside one process, so a saved lastBeatAt that is AHEAD of
        ; it means this is a new process, and a new process is a new engine
        ; session. (A save made early in a short session and loaded late in a
        ; long launch reads as "not ahead" and simply waits for the slot.) On
        ; a new session CheckSession zeroes lastLoad and calls back in; that
        ; inner call handles the load and this one returns into it done.
        Float now = Utility.GetCurrentRealTime()
        If now < lastBeatAt
            CheckSession()
        EndIf
        lastBeatAt = now
        Return
    EndIf
    lastLoad = v
    RegisterForModEvent("PaSo_TrapFollower", "OnPaSoTrapFollower")
    Quest mcm = Game.GetFormFromFile(0x000A01, "FleshCore.esp") as Quest
    If mcm != None
        mcm.EnsureRegistered()
    EndIf
    ; RESET FIRST, STRIP SECOND. The reset is this script's own variables and
    ; cannot fail; the strip reaches into another mod and a dozen native calls.
    ; If anything in there throws, the wound replay is already stopped.
    nextWound = 1
    nextEvent = 1
    moaned = false
    ; ---- AND THE HEAD ARMOUR IS FORGOTTEN, NOT REMEMBERED ----------------
    ;
    ; headFill is a plain script VARIABLE, so Papyrus serialises it into the
    ; save. An older save comes back holding FL_Head -- the armour
    ; that was later retired -- and the record still resolves, so nothing would ever
    ; notice. SeatHead would then put the slot-30 head back on targets who were
    ; about to have it taken off, until the first mailbox of the session
    ; happened to overwrite it; and on a save where every target near them is
    ; already filled, the DLL has no reason to send one and that never comes.
    ;
    ; Forgetting it is safe in both directions: SeatHead does nothing at all
    ; while it is None, and the very next dress or revive request carries the
    ; id the config named.
    headFill = None
    ; And the two lookup caches beside it, for the same reason: they are plain
    ; script variables, so they serialise, and a Form resolved in one session
    ; is not something to trust in the next.
    retiredHeadAsked = false
    beastAsked = false
    noStripAsked = false
    koHoldAsked = false
    ; ---- AND LEARNED BACK FROM THE CONFIG AT ONCE ----------------
    ;
    ; The pre-dress below runs in the beats after this, before any mailbox has
    ; had a reason to come -- on a save where everyone near them is already
    ; filled the DLL has nothing to ask for, and SeatHead does nothing while
    ; headFill is None. So the X row is read from FleshCore.cfg.txt here: the
    ; same file, the same row and the same decimal the DLL reads. A config
    ; rolled back to FL_Head is followed exactly as the mailbox would follow
    ; it, and the next mailbox re-teaches the same id.
    ;
    ; THIS REACHES PAST THE PRE-DRESS, and deliberately. Dress() seats the
    ; head on an already-dressed target only while headFill is known, so the
    ; random sweep used to do that only after the session's first mailbox --
    ; and a naked target, whom the DLL never asks for, got their skull and brain
    ; only if the sweep happened to reach them after one. With the head known
    ; from the first beat, the sweep seats it from the first beat; so does the
    ; slot-47 collision line in SeatHead. Under the same switch as the pass,
    ; so that switching this off restores the old order exactly -- and not
    ; on a new game's stamp either (skipFirstWindow), so the Helgen cart sees
    ; exactly the sweep it has always seen, heads included only after the
    ; first mailbox, as before.
    announceDressing = false
    preDressOff = true
    If !skipFirstWindow
        LearnHeadFromConfig()
    EndIf
    ; DELIBERATELY OUTSIDE THAT GATE. The head learn sits out a new game
    ; because six equips inside a scripted scene is not what it is for; a key
    ; registration costs nothing and a new game should have its panel too.
    LearnPanelFromConfig()
    SeedGrants(true)
    lastGrantsRaw = "-"
    RegrantSpells()
    ; ---- AND THE MCM IS TOLD A LOAD HAPPENED --------------------
    ;
    ; SkyUI's documented route to OnGameReload is a ReferenceAlias on the
    ; player carrying SKI_PlayerLoadGameAlias, whose entire body is
    ; `(GetOwningQuest() as SKI_QuestBase).OnGameReload()`. That is one call,
    ; and this script already knows a load happened -- it is what CheckLoad is
    ; FOR. So the call is made from here and the MCM's quest needs no alias at
    ; all, which keeps the new QUST record to the shape every other quest in
    ; this plugin already has: StartGameEnabled, no aliases, one script.
    ;
    ; The cast answers None when SkyUI is not installed, because FL_MCM's
    ; parent is SkyUI's script and the VM will not have loaded it. Nothing here
    ; cares, which is the point.
    ; AS A MOD EVENT, NOT A CAST. This once cast the MCM's quest to
    ; SKI_QuestBase here, which put SkyUI's type into the one script that must
    ; load on every machine FleshCore is published to. A string-keyed mod
    ; event names nothing: FL_MCM registers for it if it is there, and if it
    ; is not, the event is sent to no one. SKSE's own Form.psc says mod-event
    ; registrations have to be refreshed after each game load, and FL_MCM's
    ; quest has no alias to tell it one happened, so the quest is registered
    ; for this event here, by its form, right before the event goes out.
    Quest mcmQuest = Game.GetFormFromFile(0x000008C4, "FleshCore.esp") as Quest
    If mcmQuest
        mcmQuest.RegisterForModEvent("FleshCore_GameReload", "OnFleshCoreReload")
    EndIf
    SendModEvent("FleshCore_GameReload")
    ; A load is the one moment the process may be carrying a death-camera
    ; setting this script's own memory of has rolled back with the save; the
    ; file remembers, and this puts it back whatever the script recalls.
    DeathCamBack(true)
    ; The revive checks are booked against the application clock, which does
    ; not roll back with a save; a slot booked in a timeline that is gone would
    ; otherwise wait for a moment that never comes and stay taken.
    ;
    ; SLOT BY SLOT, NOT `reviver = None`. Caprica 0.3.0 compiles the whole-
    ; array None assignment to a CAST the VM refuses -- "Cannot cast from None
    ; to Form[]" on every load. Element writes need no cast.
    If reviver
        Int rv = 0
        While rv < reviver.Length
            reviver[rv] = None
            rv += 1
        EndWhile
    EndIf
    ; AND THE BLEEDS, THE LIFTS AND THE WATCHED PIECES, for the same reason:
    ; all three are booked on the application clock and all three
    ; arrays persist. Across a quit and a reload their deadlines sit far in the
    ; future -- a target bleeding at the save kept dropping blood until the OLD
    ; clock's value came round, and a lift booked then never fired and kept
    ; its slot. The wounds they belong to were undone by the load anyway.
    If bleeder
        Int bl = 0
        While bl < bleeder.Length
            bleeder[bl] = None
            bl += 1
        EndWhile
    EndIf
    If lifter
        Int lf = 0
        While lf < lifter.Length
            lifter[lf] = None
            lf += 1
        EndWhile
    EndIf
    If hRef
        Int hr = 0
        While hr < hRef.Length
            hRef[hr] = None
            hr += 1
        EndWhile
    EndIf
    ; FIFTY PASSES AT A FIFTH OF A SECOND IS TEN SECONDS, and the window exists
    ; because PostLoadGame -- which is what stamps the counter -- is not a
    ; promise that anyone's 3D has arrived. StripAll deals with whoever is up
    ; on each pass and leaves the rest; ForgetMarks closes the window.
    stripPasses = 50
    ; AND THE PRE-DRESS WINDOW OPENS WITH IT: fifteen passes on the
    ; same fifth-of-a-second slot -- three seconds asked for, longer when the
    ; tick runs slow -- for the reason the strip has fifty: the stamp is not a
    ; promise that anyone's 3D has arrived. The opening pass runs this beat. Not
    ; on the stamp a new game writes (skipFirstWindow, see OnInit).
    predressPasses = 0
    skipFirstWindow = false
    ; AND THE SAVE'S OWN RECORD IS SNAPSHOTTED FOR THOSE PASSES TO WORK THROUGH.
    ; Read now rather than per pass because StorageUtil has just rolled back with
    ; the save and this is the moment it says what the save says.
    Int owed = DC_Api.BeginRestore()
    ; AND THE SESSION STAMP IS ADOPTED HERE TOO.
    ;
    ; lastStamp rolled back with everything else, so CheckSession is going to
    ; fire on one of the next one-second beats and set nextWound back to 1 all
    ; over again. That is harmless in this instant and is NOT harmless a second
    ; from now: by then the DLL may have forged wound 1 of the new timeline and
    ; this script may already have placed it, and being sent back to 1 would
    ; place it a second time. Reading the stamp here means CheckSession finds
    ; nothing to announce and nothing to reset.
    String ss = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.session.txt")
    If ss != ""
        lastStampText = ss
        lastStamp = ss as Int
    EndIf
    ; The stamp CheckSession would have made is made here instead, because the
    ; stamp adopted above is what stops CheckSession from noticing.
    StampAllNoStrip()
    Debug.Trace("[FleshCore] watcher: save loaded (load stamp " + v \
                + ") -- wound sequence restarted at 1, reconciling decals for 10s (" \
                + DC_Api.MarkedCount() + " actor(s) may be dirty, " + owed \
                + " the save says should be wearing marks), pre-dressing the player and the five nearest for " \
                + predressPasses + " passes (head " + headFill + ")")
EndFunction

Function StripPass()
    {One pass of the post-load decal reconcile, and the end of the window.

     TWO HALVES, IN THIS ORDER, AND THE ORDER IS THE FIX. StripAll clears
     every live mark -- unconditionally, because all of it was written into a
     timeline the load undid. RestoreAll then puts back only what the loaded
     save's own record says. Run the other way round, the strip would erase the
     restore in the same pass and case B would fail.

     BOTH HALVES ARE PER-PASS FOR THE SAME REASON: PostLoadGame, which is what
     stamps the counter this window opens on, is not a promise that anyone's 3D
     has arrived. Each half deals with whoever is up and leaves the rest.

     Runs from the same slot as CheckLoad, so it costs one extra pair of calls
     every fifth of a second for ten seconds after a load and nothing at all the
     rest of the time.}
    If stripPasses <= 0
        Return
    EndIf
    stripPasses -= 1
    Int wiped = DC_Api.StripAll()
    Int restored = DC_Api.RestoreAll()
    If wiped > 0 || restored > 0
        Debug.Trace("[FleshCore] watcher: pass " + (50 - stripPasses) \
                    + " after the load -- " + wiped + " decal layer(s) stripped, " \
                    + restored + " actor(s) put back to what the save was made with")
    EndIf
    ; Nobody left to clean AND nobody left to put back, or the window is up:
    ; either way, close it.
    ;
    ; BOTH HALVES OF THAT TEST MATTER. With MarkedCount() alone,
    ; on the second case -- loading a
    ; save that was made in an EARLIER RUN of the game -- the strip list is empty
    ; on pass one, because nothing has been painted in this run yet.
    ; The window would close a fifth of a second after the load, before a
    ; single actor's 3D had arrived, and restore nobody.
    If stripPasses <= 0 || (DC_Api.MarkedCount() < 1 && DC_Api.PendingRestoreCount() < 1)
        stripPasses = 0
        DC_Api.ForgetMarks()
    EndIf
EndFunction

Function CheckSession()
    {A new engine session restarts the wound numbering at one. Without this the
     script would sit waiting for wound 431 of a game that is no longer running
     and never place anything again.}
    String st = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.session.txt")
    If st == ""
        Return
    EndIf
    ; As text, not as a number -- see lastStampText. An older save
    ; carries "" here and answers "changed" once, on its first beat,
    ; where CheckLoad's own adoption has not already made the two equal.
    If st != lastStampText
        lastStampText = st
        lastStamp = st as Int
        nextWound = 1
        nextEvent = 1
        Debug.Trace("[FleshCore] watcher: engine session " + lastStamp + " -- wound sequence restarted at 1")
        ; A new engine session is a new form table: the stamp is gone with it.
        StampAllNoStrip()
        ; AND THE LOAD THAT LED HERE IS MADE VISIBLE. Reaching
        ; this line means a load happened that CheckLoad did not fire on: the
        ; VM only runs once a save is loaded, and CheckLoad adopts the session
        ; stamp whenever it fires, so the two disagree -- in practice -- only
        ; when the DLL's fresh per-process load counter happened to equal the
        ; value this script saved (see CheckLoad's docstring; the other way in
        ; is a session file that read empty at the moment CheckLoad fired).
        ; Zero is a value the file never holds, and CheckLoad is called HERE,
        ; in the same slice as the nextWound reset above and before Drain has
        ; run: two resets with a Drain between them is the double-placement
        ; the docstring above CheckLoad's stamp adoption describes, and this
        ; is that hazard from the other side. The inner CheckLoad fires, adopts
        ; the stamp, and every later CheckSession finds nothing to do. This
        ; runs from CheckLoad's own beat when the clock gives the process
        ; away, and from the once-a-second slot when it does not; either way
        ; it sits before Drain in the tick.
        lastLoad = 0
        CheckLoad()
    EndIf
EndFunction

Function Drain()
    {Claim wound files in order. Each number is read once and never again, so
     nothing has to be blanked and nothing can be lost to someone else's write.}
    If !Pool
        ; LOGGED ONCE, LOUDLY. This script is now the ONLY placer, so an
        ; unwired Pool means no piece of any wound ever reaches the world.
        If !moaned
            moaned = true
            Debug.Trace("[FleshCore] watcher has NO POOL -- it can place nothing")
        EndIf
        Return
    EndIf
    Int guard = 0
    While guard < 8
        String path = "Data/SKSE/Plugins/FleshCore.w" + nextWound + ".txt"
        Bool here = MiscUtil.FileExists(path)
        String out = ""
        Bool whole = false
        If here
            out = MiscUtil.ReadFromFile(path)
            ; THE TERMINATOR IS THE PROOF THE FILE IS FINISHED. The forge
            ; thread opens, writes and closes; a reader that looks in between
            ; sees a file that exists and is empty. Rather than treat that as a
            ; wound with no pieces, wait and read it whole.
            Int len = StringUtil.GetLength(out)
            whole = len > 0 && StringUtil.SubString(out, len - 1, 1) == "#"
        EndIf
        If !whole
            ; A WOUND NUMBER THAT NEVER ARRIVES USED TO STOP THE MOD DEAD.
            ;
            ; The engine takes its sequence number BEFORE it writes, so a write
            ; that fails -- a scanner holding the folder, a full disk, anything
            ; -- consumes a number that no file will ever carry. This reader
            ; walked the sequence in strict order and simply waited for it, and
            ; waited, and no piece of any later wound ever spawned again. That
            ; is a permanent, silent death for the whole feature, and it needed
            ; one file check to avoid.
            ;
            ; The forge writes wounds in order on one thread, so if the NEXT
            ; number is already on disk, this one is finished or is never
            ; coming. Either way it is safe to step over.
            If (here || (beats % 20) == 0) && MiscUtil.FileExists("Data/SKSE/Plugins/FleshCore.w" + (nextWound + 1) + ".txt")
                Debug.Trace("[FleshCore] watcher: wound " + nextWound + " never arrived whole -- skipping it")
                nextWound += 1
                guard += 1
            Else
                Return
            EndIf
        Else
            ; HOW LATE THE PIECES ARE. The engine stamps its log with the
            ; moment it posted a wound; this stamps the moment the wound was
            ; picked up. The gap between them is how long a mesh sat on disk
            ; before anything asked for it, and that is the exact interval a
            ; race would have to live in.
            If ProbeVerbose
                Debug.Trace("[FleshCore] PROBE drain w=" + nextWound + " picked up at " \
                            + Utility.GetCurrentRealTime() + " (tick " + Tick() + "s)")
            EndIf
            nextWound += 1
            guard += 1
            PlaceLine(out)
        EndIf
    EndWhile
EndFunction

Function EventPass()
    {Relay the engine's events. Each FleshCore.ev<N>.txt is
     "<name>|<senderFormID>|<numArg>|<strArg>\n#", read once in order, and
     sent as a mod event FROM THE SENDER it names, so a handler's fourth
     argument is the victim (or the command's target); a sender of 0 is this
     quest. FL_Wounded also updates LastWound and the per-actor state string
     here, which is what FL_Api.BodyState reads.}
    Int guard = 0
    While guard < 8
        String path = "Data/SKSE/Plugins/FleshCore.ev" + nextEvent + ".txt"
        If !MiscUtil.FileExists(path)
            Return
        EndIf
        String out = MiscUtil.ReadFromFile(path)
        Int len = StringUtil.GetLength(out)
        If len == 0 || StringUtil.SubString(out, len - 1, 1) != "#"
            If MiscUtil.FileExists("Data/SKSE/Plugins/FleshCore.ev" + (nextEvent + 1) + ".txt")
                nextEvent += 1
                guard += 1
            Else
                Return
            EndIf
        Else
            nextEvent += 1
            guard += 1
            ; strip the "\n#" the DLL wrote last
            Int cut = len - 2
            While cut > 0 && StringUtil.SubString(out, cut - 1, 1) == "\n"
                cut -= 1
            EndWhile
            RelayEvent(StringUtil.SubString(out, 0, cut))
        EndIf
    EndWhile
EndFunction

Function RelayEvent(String line)
    String[] f = StringUtil.Split(line, "|")
    If f.Length < 4
        Return
    EndIf
    String name = f[0]
    Int senderId = f[1] as Int
    Float num = f[2] as Float
    ; everything after the third '|' is the payload, pipes included
    Int skip = StringUtil.GetLength(f[0]) + StringUtil.GetLength(f[1]) + StringUtil.GetLength(f[2]) + 3
    String payload = StringUtil.SubString(line, skip, StringUtil.GetLength(line) - skip)
    Form sender = None
    If senderId != 0
        sender = Game.GetFormEx(senderId)
    EndIf
    If name == "FL_Wounded" && sender
        LastWound = payload
        StorageUtil.SetStringValue(sender, "FC_state", payload)
        NotifySkyrimNetWound(sender as Actor, payload)
    ElseIf name == "FL_Restored" && sender
        StorageUtil.UnsetStringValue(sender, "FC_state")
        StorageUtil.UnsetIntValue(sender, "FC_SNLostMask")
        StorageUtil.UnsetIntValue(sender, "FC_CorpseDress")
        CleanFEC(sender as Actor)
    ElseIf name == "FL_TestReport"
        StorageUtil.SetStringValue(None, "FC_LastTestReport", payload)
        Debug.Notification(payload)
        Debug.Trace("[FleshCore Tester] " + payload)
    ElseIf name == "FL_PresetApplied"
        StorageUtil.SetIntValue(None, "FC_PresetId", num as Int)
        StorageUtil.SetStringValue(None, "FC_PresetName", payload)
        Debug.Notification("[FleshCore] Combat Preset applied: " + payload)
    EndIf
    If sender
        sender.SendModEvent(name, payload, num)
    Else
        SendModEvent(name, payload, num)
    EndIf
EndFunction

Function NotifySkyrimNetWound(Actor vic, String payload)
    {Inform SkyrimNet of grievous wounds, exploded bodies, bisections, lost limbs,
     and decapitations from FL_Wounded. Active only when SkyrimNet.esp is installed.}
    If !vic || payload == ""
        Return
    EndIf
    If !Game.IsPluginInstalled("SkyrimNet.esp") || StorageUtil.GetIntValue(None, "FC_SkyrimNetOn", 1) == 0
        Return
    EndIf
    String wForm = FL_Api.Field(payload, 1)
    Int cellsTaken = FL_Api.Field(payload, 3) as Int
    String touched = FL_Api.Field(payload, 5)
    Int lostMask = FL_Api.Field(payload, 7) as Int
    Int flags = FL_Api.Field(payload, 8) as Int
    Int prevLostMask = StorageUtil.GetIntValue(vic, "FC_SNLostMask", 0)
    Int newLostMask = Math.LogicalAnd(lostMask, Math.LogicalNot(prevLostMask))
    If lostMask != prevLostMask
        StorageUtil.SetIntValue(vic, "FC_SNLostMask", Math.LogicalOr(prevLostMask, lostMask))
    EndIf
    Bool isBlast = (flags / 1024 % 2 == 1) || (wForm == "detonate") || (wForm == "detonatealt")
    Bool headLost = (flags / 4096 % 2 == 1)
    Bool trunkLost = Math.LogicalAnd(newLostMask, 12) != 0
    Bool lArmLost = Math.LogicalAnd(newLostMask, 112) != 0
    Bool rArmLost = Math.LogicalAnd(newLostMask, 896) != 0
    Bool lLegLost = Math.LogicalAnd(newLostMask, 7168) != 0
    Bool rLegLost = Math.LogicalAnd(newLostMask, 57344) != 0
    Bool isSevered = headLost || trunkLost || lArmLost || rArmLost || lLegLost || rLegLost || (flags % 2 == 1 && newLostMask != 0)
    Bool noKill = DeathHeld(vic) || (flags / 2048 % 2 == 1) || FL_Api.NoKill(vic)
    Float now = Utility.GetCurrentRealTime()
    Float lastAt = StorageUtil.GetFloatValue(vic, "FC_SNLastTime", 0.0)
    Int lastSev = StorageUtil.GetIntValue(vic, "FC_SNLastSev", 0)
    Int curSev = 1
    If isBlast
        curSev = 4
    ElseIf isSevered
        curSev = 3
    ElseIf cellsTaken >= 25
        curSev = 2
    EndIf
    If (now - lastAt) < 1.5 && curSev <= lastSev && !headLost && !trunkLost
        Return
    EndIf
    StorageUtil.SetFloatValue(vic, "FC_SNLastTime", now)
    StorageUtil.SetIntValue(vic, "FC_SNLastSev", curSev)
    String vName = vic.GetDisplayName()
    If vName == ""
        ActorBase ab = vic.GetActorBase()
        If ab
            vName = ab.GetName()
        EndIf
        If vName == ""
            vName = "Someone"
        EndIf
    EndIf
    String evType = "fleshcore_wound"
    String msg = ""
    If isBlast
        evType = "fleshcore_explosion"
        If wForm == "detonatealt" || (flags / 256 % 4 == 2)
            msg = vName + "'s body violently explodes apart from overwhelming internal pressure into visceral chunks!"
        Else
            msg = vName + "'s body violently explodes apart into bloody chunks and torn flesh!"
        EndIf
    ElseIf headLost
        evType = "fleshcore_decapitation"
        If noKill
            msg = vName + " has been decapitated, their head severed cleanly from their neck, yet their headless body impossibly remains alive!"
        Else
            msg = vName + " has been decapitated, their head severed cleanly from their shoulders!"
        EndIf
    ElseIf trunkLost
        evType = "fleshcore_bisection"
        msg = vName + " has been violently bisected, their torso cleaved in two!"
    ElseIf lArmLost || rArmLost || lLegLost || rLegLost
        evType = "fleshcore_dismemberment"
        String limbs = ""
        If lArmLost && rArmLost
            limbs = "both arms"
        ElseIf lArmLost
            limbs = "left arm"
        ElseIf rArmLost
            limbs = "right arm"
        EndIf
        If lLegLost && rLegLost
            If limbs != ""
                limbs += " and both legs"
            Else
                limbs = "both legs"
            EndIf
        ElseIf lLegLost
            If limbs != ""
                limbs += " and left leg"
            Else
                limbs = "left leg"
            EndIf
        ElseIf rLegLost
            If limbs != ""
                limbs += " and right leg"
            Else
                limbs = "right leg"
            EndIf
        EndIf
        If limbs == ""
            limbs = "limb"
        EndIf
        If !noKill && (flags % 2 == 1 || vic.IsDead())
            msg = vName + " has had their " + limbs + " violently severed in a fatal dismemberment!"
        Else
            msg = vName + " has had their " + limbs + " violently severed!"
        EndIf
    Else
        String region = "body"
        If StringUtil.Find(touched, "head") >= 0
            region = "head"
        ElseIf StringUtil.Find(touched, "chest") >= 0 || StringUtil.Find(touched, "abdomen") >= 0
            region = "torso"
        ElseIf StringUtil.Find(touched, "arm") >= 0 || StringUtil.Find(touched, "hand") >= 0
            region = "arm"
        ElseIf StringUtil.Find(touched, "thigh") >= 0 || StringUtil.Find(touched, "calf") >= 0 || StringUtil.Find(touched, "foot") >= 0
            region = "leg"
        EndIf
        msg = vName + " suffers a grievous flesh wound tearing open their " + region + "!"
    EndIf
    SkyrimNetApi.RegisterEvent(evType, msg, vic, None)
    If curSev >= 2 && StorageUtil.GetIntValue(None, "FC_SkyrimNetDirect", 1) != 0
        Float lastGlobal = StorageUtil.GetFloatValue(None, "FC_SNGlobalDirectAt", 0.0)
        If (now - lastGlobal) >= 4.0
            StorageUtil.SetFloatValue(None, "FC_SNGlobalDirectAt", now)
            SkyrimNetApi.DirectNarration(msg, vic, None)
        EndIf
    EndIf
EndFunction

Function NotifySkyrimNetFromPlace(Actor vic, Int flags, Int placed, Int severed, String[] prov)
    {Fallback SkyrimNet notification from PlaceLine when a wound places pieces before
     or without FL_Wounded.}
    If !vic || placed <= 0
        Return
    EndIf
    If !Game.IsPluginInstalled("SkyrimNet.esp")
        Return
    EndIf
    If StorageUtil.GetIntValue(None, "FC_SkyrimNetOn", 1) == 0
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Float lastAt = StorageUtil.GetFloatValue(vic, "FC_SNLastTime", 0.0)
    If (now - lastAt) < 1.5
        Return
    EndIf
    Int lostMask = 0
    String touched = ""
    If prov.Length > 0
        Int i = 0
        While i < prov.Length
            If prov[i] != ""
                String[] g = StringUtil.Split(prov[i], ":")
                If g.Length >= 4
                    Int pBit = g[0] as Int
                    Int isSec = g[3] as Int
                    If pBit == 1 && StringUtil.Find(touched, "head") < 0
                        touched += "head,"
                    ElseIf (pBit == 2 || pBit == 3) && StringUtil.Find(touched, "chest") < 0
                        touched += "chest,"
                    ElseIf pBit >= 4 && pBit <= 9 && StringUtil.Find(touched, "arm") < 0
                        touched += "arm,"
                    ElseIf pBit >= 10 && pBit <= 15 && StringUtil.Find(touched, "thigh") < 0
                        touched += "thigh,"
                    EndIf
                    If isSec != 0 && pBit >= 2 && pBit <= 15
                        lostMask = Math.LogicalOr(lostMask, Math.LeftShift(1, pBit))
                    EndIf
                EndIf
            EndIf
            i += 1
        EndWhile
    EndIf
    String synth = "place|-|FC|" + (placed * 12) + "|0|" + touched + "|-|" + lostMask + "|" + flags + "|0,0,0"
    NotifySkyrimNetWound(vic, synth)
EndFunction

Function PlaceLine(String out)
    {One wound: "N|victim|flags|severed|slot0|anchor0|slot1|anchor1|...|#"
     -- or, from an engine with `E` on, a TRIPLE per piece:
     "N|victim|flags|severed|slot0|anchor0|ref0|slot1|anchor1|ref1|...|#"
     where ref is the FormID (signed) of a reference the ENGINE has already
     placed and positioned, or 0 for a piece this script is to place itself.
     Which of the two the line is comes from its field count alone -- four
     head fields, two or three per piece, one terminator -- so an older
     engine and a newer one are both read correctly by this one reader.

     WHY EVERY INSTRUCTION IN THIS LOOP IS COUNTED.
     -----------------------------------------------------------------
     Measured, the loop costs a tenth to a quarter of a second per piece.




     PlaceAtMe and SetPosition, the two heavy natives, are about a quarter of it.
     The other three quarters are in neither of them -- and both of them
     land almost exactly on one frame each, which
     is the signature of a script being suspended and resumed rather than
     one doing slow work.

     That is the Papyrus update budget. The VM gets fUpdateBudgetMS of
     wall time per frame -- 1.2ms by default, when the INI's
     [Papyrus] block does not set it -- shared across every script in the
     load order at once. A loop that runs long is not slow; it is
     REPEATEDLY SUSPENDED, and it resumes a frame later each time. So the
     cost of this loop is not the cost of its calls, it is the NUMBER OF
     INSTRUCTIONS it spends before it can finish: every native, every
     function call, every cast is another slice of a budget it is
     sharing with the whole game.

     Which is why this loop reads their centre once instead of twice a
     piece, reads a node in one array call instead of four, inlines what
     it used to call, and no longer times itself per piece. And why the
     single largest remaining lever is not in this file at all -- it is
     fUpdateBudgetMS.


     THE POOL RECORD IS NAMED PER PIECE. It used to be one starting record and
     the script derived the rest as start+k, which meant that a piece the forge
     refused -- or a pool record that could not be repointed -- silently shifted
     every remaining piece of that wound onto somebody else's mesh. The engine
     knows which record it repointed; now it says so.

     FLAGS bit 0 is TRUE DISMEMBERMENT: this blow left them in pieces that no
     longer reach each other through living flesh. SEVERED says how many of the
     N are those pieces -- whole limbs and body halves rather than debris -- and
     the engine appends them last, so they are the final `severed` entries.}
    String[] part = StringUtil.Split(out, "|")
    If part.Length < 4
        Return
    EndIf
    Int n = part[0] as Int
    ; ---- TWO FIELDS PER PIECE, OR THREE ------------------------------
    ;
    ; The engine's line is field-counted, and the count says which grammar it
    ; is: 5 + 2n fields (head, pairs, "#") or 5 + 3n (head, triples, "#"). A
    ; line that matches neither is read as pairs, which is what every line
    ; from older engines was and what the guard on the loop already copes
    ; with when a line is short.
    Int stride = 2
    If part.Length == 5 + 3 * n
        stride = 3
    EndIf
    ; ---- PROVENANCE, before the terminator --------
    ;
    ; A newer engine writes one more block after the last pair or triple:
    ; "|P|part:layers:cells:section;..." with one entry per piece in the
    ; same order, so the field count is 7 + 2n or 7 + 3n and field
    ; 4 + stride*n reads "P". An older engine writes no block and an older
    ; script ignores it; this reader tolerates both.
    ; NO `= None` ON AN ARRAY LOCAL: Caprica 0.3.0 compiles `= None`
    ; on an array variable as `cast ::temp0, None`, which fails in the VM
    ; ("Cannot cast from None to String[]"). An uninitialised local array in
    ; Papyrus is already None by default with zero instructions emitted.
    String[] prov
    If part.Length == 7 + 3 * n && part[4 + 3 * n] == "P"
        stride = 3
        prov = StringUtil.Split(part[5 + 3 * n], ";")
    ElseIf part.Length == 7 + 2 * n && part[4 + 2 * n] == "P"
        stride = 2
        prov = StringUtil.Split(part[5 + 2 * n], ";")
    EndIf
    String victimText = part[1]
    Int flags = part[2] as Int
    Int severed = part[3] as Int
    ; ---- THE KICK AND THE MARK, OUT OF THE SAME WORD ----------------
    ;
    ; Bits 0 and 1 are what they always were. Bits 2-7 are the wound's kick,
    ; bits 8-9 the mark it forces onto its pieces (0 none, 1 blood, 2 alt),
    ; both straight off the W row -- flesh.cpp packs them exactly so. Papyrus
    ; has no shift, so they are divided out. The kick is handed to each
    ; severed section on the call that already tells it what it is; the mark
    ; goes into DecalCore's pending slot below, as every mark does.
    Int kick = flags / 4 % 64
    Int forced = flags / 256 % 4
    ObjectReference victim = Game.GetFormEx(part[1] as Int) as ObjectReference
    If !victim
        Debug.Trace("[FleshCore] watcher: no victim for '" + part[1] + "'")
        Return
    EndIf
    Actor vic = victim as Actor
    ; ---- THE EVENT -----------------------------------------------
    ;
    ; The first thing a consumer can LISTEN to. Sent from the victim themselves
    ; (Form.SendModEvent makes the caller the sender), so a handler's fourth
    ; argument is their Form and needs no lookup. Payload is '|'-separated and
    ; only ever grows at the end -- FL_Api.Field reads it by index:
    ;     0 flags       bit 0 = they come apart (a kill unless held),
    ;                   bit 1 = the trunk; bit 11 (2048) = they would have
    ;                   died and a never-kill rule said no; the rest
    ;                   are FleshCore's own
    ;     1 pieces      how many were forged
    ;     2 severed     how many separate sections they are in now
    ; numArg is the flags word again, for a handler that wants no parsing.
    ; Sent BEFORE the kill below, so a handler sees them alive and can act --
    ; a held death (the Sequence) is reported exactly like any other.
    If vic
        vic.SendModEvent("FleshCore_Wound", flags + "|" + n + "|" + severed, flags as Float)
    EndIf
    ; THEY DIE FIRST, AND THEY DIE BEFORE THEIR PIECES LAND.
    ;
    ; The order matters. Killing them drops them out of whatever animation they
    ; were in and into a ragdoll, and the ragdoll settles over the next second
    ; -- so doing it now means the severed limbs arrive while the rest of them
    ; is already falling, rather than a beat after they have finished. It is also
    ; done whether or not any piece was forged: the flesh has left them either
    ; way, and a target standing up with no legs is worse than a missing gib.
    Bool noKillVic = false
    If vic
        noKillVic = DeathHeld(vic) || (flags / 2048 % 2 == 1) || FL_Api.NoKill(vic) \
            || ((flags % 2 == 0) && FL_Api.GetInt(vic, "headfatal") == 0)
    EndIf
    ; NOT A FAILED REVIVE: a wound that kills them, or that finds them
    ; dead because the blow's own damage got there first, takes them out of the
    ; revive ladder before it can stand them back up. See EndReviveCheck. The
    ; same wound books the corpse for its interior (see DressRequested).
    If vic && (vic.IsDead() || (flags % 2 == 1 && !noKillVic))
        EndReviveCheck(vic)
        If StorageUtil.GetIntValue(vic, "FC_CorpseDress") == 0
            StorageUtil.SetIntValue(vic, "FC_CorpseDress", 1)
            ; Listed again, once: a pass may have spent their name a beat ago.
            MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.dress.txt", "|" + part[1], true, false)
        EndIf
    EndIf
    If flags % 2 == 1 && vic
        If noKillVic
            ; A held death -- the Sequence's decapitation, or a NoKill/registry override.
            ; They come apart and stay alive; no kill, no ragdoll, no flag clearing.
            Debug.Trace("[FleshCore] " + vic + " was severed but their death is HELD / NoKill -- not killed")
        Else
            Dismember(vic)
        EndIf
    EndIf
    ; ---- AND A DETONATE SENDS WHAT IS LEFT OF THEM UP -----------------------
    ;
    ; Design note: Detonate sends the main body a little way into the air.
    ;
    ; flags bit 10, value 1024, set by the DLL on a Detonate wound and read the
    ; way every other field of this word is -- Papyrus has no shift, so it is
    ; divided out, exactly as the kick and the mark are above.
    ;
    ; REGISTERED, NOT FIRED. The lift has to come a moment after Dismember, and
    ; the reason is FL_GrindMe's, worked out at length there (FL_GrindMe.psc,
    ; Collapse): an impulse on an actor whose ragdoll is not yet in the physics
    ; world is absorbed by the animation graph. Dismember has just called Kill
    ; on them one instruction ago. A Utility.Wait here would suspend the whole
    ; placement loop, which is the one thing this function may never do, so they
    ; go into a slot with a time on it and OnUpdate's TrunkLiftPass fires it.
    If flags / 1024 % 2 == 1 && vic
        BeginTrunkLift(vic)
    EndIf
    ; ---- THE PLAYER DIES BY THE SAME RULE --------------------------------------
    ;
    ; No separate rule here: for the player the DLL sets bit 0 only when a
    ; named part is lost to something other than a spell, so a non-fatal cut
    ; or a spell wound never kills them. The kill above is the only one, after
    ; the same noKillVic test as anyone's (DeathHeld, bit 11 nolethal,
    ; FL_Api.NoKill, or a non-lethal headfatal=0 override).




    ; ---- THEY BLEED WHILE THEY STILL HAVE A TRUNK ----------------------------
    ;
    ; flags bit 1, set by the DLL out of the section pass: their main mass still
    ; holds a chest and/or an abdomen. Started here rather than inside
    ; Dismember because it is not about dismemberment -- a bite that takes a
    ; handful of cells and severs nothing still opens them, and that is the
    ; common case.
    If vic && flags / 2 % 2 == 1
        BeginTrunkBleed(vic)
    EndIf
    If n <= 0
        Return
    EndIf
    ; THE LOOP IS TIMED ONCE PER WOUND -- t0 below, one reading after the loop.
    ; Clock reads inside it would spend the per-frame budget the docstring
    ; describes, so pieces are not timed one by one.


    ; FOUR NATIVE CALLS PER PIECE BECOME ONE.
    ;
    ; From SKSE's own NetImmerse.psc:
    ;
    ;   ; Array based functions, return true when successful, false when
    ;   ; unsuccessful (node did not exist, or array wrong size)
    ;   ; returns the node's world position into the specify array,
    ;   ; must be size of 3
    ;   bool Function GetNodeWorldPosition(ObjectReference ref, string node,
    ;                                      float[] in, bool firstPerson)
    ;
    ; It returns FALSE when the node does not exist, which is precisely the
    ; guard HasNode was there to provide -- so HasNode and the three separate
    ; GetNodeWorldPositionX/Y/Z reads collapse into this one call, with the
    ; same safety. The array is allocated once for the whole wound, not once
    ; per piece: `new` is not free either.
    Float[] np = new Float[3]
    Bool df = Game.IsPluginInstalled("Dismembering Framework.esm")
    Int k = 0
    Int placed = 0
    Int byEngine = 0        ; how many of them the engine had already made
    Int size = Pool.GetSize()
    ; THEIR CENTRE, READ ONCE. It used to be read twice per piece inside the
    ; loop, and it is the same answer every time -- they are a ragdoll settling,
    ; not a thing that moves metres between two pieces. Reading it here also
    ; makes every piece of one wound push out from the SAME centre, which is
    ; what "radially outward" was always supposed to mean.
    Float vx = victim.GetPositionX()
    Float vy = victim.GetPositionY()
    ; AND THE CLOCK. This loop is the entire gap between the blow landing
    ; and the last piece appearing, and until now nothing measured it: the
    ; engine timed the forge, FL_Chunk timed its own 3D, and the half second
    ; per piece in between belonged to nobody. It does now.
    Float t0 = Utility.GetCurrentRealTime()
    ; `slot % size` on an empty list is a division by zero, which aborts this
    ; function in the middle of a wound. A wired-but-empty FormList is a
    ; plugin-build fault, so it is worth one loud line rather than one silent
    ; Papyrus error per wound forever.
    If size <= 0
        If !moaned
            moaned = true
            Debug.Trace("[FleshCore] watcher: the pool list is EMPTY -- nothing can be placed")
        EndIf
        Return
    EndIf
    ; WHAT THEY WERE WEARING, ASKED ONCE FOR THE WHOLE WOUND.
    ;
    ; Field report: a marked character's shards came out clean. They had to -- the
    ; marks live on RaceMenu overlay nodes and FleshCore skips those at harvest
    ; because voxelising them was what turned the shards black.
    ;
    ; So the mark is carried across by hand. A shard keeps their body's texture
    ; coordinates, so DC_Api.CoatSkin puts the OVERLAY art back on it in the
    ; same body UV and the blood lands where it sat on them.
    ;
    ; Asked here and not inside the loop: reading their overlay layers is six
    ; native calls, and this loop is the window between the blow landing and
    ; the first piece appearing that this file works to
    ; shorten. Once per wound, not once per piece.
    ; victim is an ObjectReference here, not an Actor -- the cast is required
    ; and returns None for anything that is not one, which MarkOn treats as
    ; unmarked.
    Int mark = -1
    ; A FORCED MARK OUTRANKS WHAT THEY WORE. the alt burst's row says 2,
    ; so every piece of them leaves in alt at the heaviest band whether or not
    ; anyone painted them first; the blood coat FL_Chunk gives every piece
    ; unconditionally goes on underneath it, as it does under any mark. 1 is
    ; blood, which the piece already wears, so it is the same as none. The
    ; packing is DC_Api's own: kind * 10 + level, level 5 the heaviest of six.
    If forced == 2
        mark = DC_Api.ALT() * 10 + 5
    ElseIf DC_Api.PaintReady()
        mark = DC_Api.MarkOn(victim as Actor)
    EndIf
    ; LEFT FOR THE PIECES TO COLLECT, NOT APPLIED HERE.
    ;
    ; CoatSkin used to be called on each piece the instant PlaceAtMe returned. That
    ; is the one thing this file already knows not to do: "PlaceAtMe hands back
    ; a reference whose 3D has not loaded yet", says FL_Chunk, which is
    ; why the impulse waits for OnLoad. An effect shader has nothing to attach
    ; to either. The placement loop takes on the order of a hundred milliseconds PER PIECE,
    ; so the 3D is emphatically not there yet.
    ;
    ; So the mark is left where each piece can collect it in its own OnLoad.
    DC_Api.SetPendingMark(mark)
    While k < n && (5 + stride * k) < part.Length
        Int slot = part[4 + stride * k] as Int
        String nd = part[5 + stride * k]
        ; the reference the engine already made for this piece, or 0.
        Int refId = 0
        If stride == 3
            refId = part[6 + stride * k] as Int
        EndIf
        Bool isSection = (k >= n - severed)
        Form base = Pool.GetAt(slot % size)
        If base
            ; PERSISTENT WHILE IT LIVES. A reference created without this is a
            ; TEMPORARY one, and the engine is entitled to reclaim a temporary
            ; reference it does not consider worth keeping -- which matches
            ; "PlaceAtMe returned something and nothing appeared".
            ; The save does not grow for it: FL_Chunk disables and deletes each
            ; piece forty-five seconds after it is made, whether it was ever
            ; seen or not.
            ; ---- OR THE ENGINE ALREADY MADE IT --------------------
            ;
            ; With `E` on in FleshCore.cfg.txt the engine created this
            ; reference itself, on the game's thread, the frame after its mesh
            ; was written -- persistent, enabled, and already moved to the
            ; same spot the SetPosition below would have put it. It was also
            ; told what it is (section or shard, kick, mark) through its own
            ; roll angle, which FL_Chunk read in its OnInit; see FL_Chunk.
            ; So for such a piece this loop makes nothing, moves nothing and
            ; tells it nothing: it looks the reference up and carries on with
            ; the bookkeeping every piece gets.
            ObjectReference piece = None
            If refId != 0
                piece = Game.GetFormEx(refId) as ObjectReference
                If !piece
                    Debug.Trace("[FleshCore] watcher: the engine says it placed " + refId \
                                + " on pool " + slot + " but no such reference resolves")
                EndIf
            Else
                piece = victim.PlaceAtMe(base, 1, true, false)
                If !piece
                    Debug.Trace("[FleshCore] watcher: PlaceAtMe gave nothing for pool " + slot)
                EndIf
            EndIf
            If piece
                ; PROVENANCE ON THE PIECE: one native on a form key,
                ; not a call into the fresh object. FL_Api.ShardProvenance
                ; reads it; a piece without it is indistinguishable from
                ; "not FleshCore's".
                If prov && k < prov.Length && prov[k] != ""
                    StorageUtil.SetStringValue(piece, "FC_prov", victimText + "|" + prov[k])
                EndIf
                ; A PIECE OF SOMEONE MARKED IS ALSO MARKED.
                ;
                ; EffectShader.Play is a native call ON THE SHADER, not a
                ; cross-script call into the piece, so it does not wait on the
                ; new object's OnInit the way CameFromPool below does -- which
                ; is why that one is paid only under ProbeVerbose and this one
                ; can be paid always.
                ; THE EVIDENCE FOR THE ABOVE, ONCE PER WOUND: this
                ; reports False while the 3D is still on its way; True would mean
                ; the 3D was ready after all.
                If k == 0
                    Debug.Trace("[DecalCore] wound mark " + mark \
                        + "; first piece had 3D at placement: " + piece.Is3DLoaded())
                EndIf
                ; WHICH RECORD THIS CAME FROM, told to the piece itself, so that
                ; when it gives up it can ask the engine what that record points
                ; at by then. A piece whose mesh was repointed out from under it
                ; by a later wound looks, from up here, exactly like a piece
                ; whose mesh never loaded.
                ; DIAGNOSTIC ONLY, AND OFF THE CRITICAL PATH.
                ;
                ; poolSlot exists for exactly one thing: AskTheEngine, which a
                ; piece calls when it never got 3D at all, so the DLL can say
                ; what its pool record points at by now. Nothing in the normal
                ; life of a shard reads it.
                ;
                ; But this is a CROSS-SCRIPT CALL INTO AN OBJECT THAT WAS
                ; CREATED A MOMENT AGO, and the VM will not run it until that
                ; object's own OnInit has been dispatched -- so the placement
                ; loop stops here, per piece, waiting on a queue it is also
                ; feeding. On a heavily scripted load order that wait is most
                ; of the gap between one piece appearing and the next.
                ;
                ; So it is paid only when the answer will be looked at.
                If ProbeVerbose
                    FL_Chunk pc = piece as FL_Chunk
                    If pc
                        pc.CameFromPool(slot)
                    EndIf
                EndIf
                ; THE CENSUS IS NOT FREE AND THIS IS THE CRITICAL PATH.
                ; Watching() walks thirty-two slots calling Is3DLoaded() on
                ; each, once PER PIECE PLACED -- up to two hundred native calls
                ; inside a single wound's placement, in the exact window
                ; between the blow landing and the shard appearing that this
                ; code works to keep short. It answered its question (the
                ; count had nothing to do with the failures); it does not get
                ; to keep charging for it.
                If ProbeVerbose
                    Debug.Trace("[FleshCore] PROBE placed " + piece \
                        + " pool=" + slot \
                        + " base=" + base \
                        + " node='" + nd + "'" \
                        + " section=" + isSection \
                        + " 3DatOnce=" + piece.Is3DLoaded() \
                        + " victim3D=" + victim.Is3DLoaded() \
                        + " live=" + Watching())
                EndIf
                ; REMEMBER, INLINED. A Papyrus function call is not free, and
                ; this one is four assignments. Every instruction in this loop
                ; competes for the VM's per-frame budget -- see the note at
                ; the top of PlaceLine -- so a call frame per piece is a real
                ; cost for no benefit. Remember() is kept for other callers.
                If !hRef
                    hRef = new ObjectReference[32]
                    hWhen = new Float[32]
                EndIf
                hRef[hCursor] = piece
                ; t0, not a fresh reading. Every piece of one wound is placed
                ; inside a fraction of a second and the only thing this stamp
                ; is ever compared against is a TWENTY SECOND threshold, so a
                ; clock call per piece buys nothing and costs a native.
                hWhen[hCursor] = t0
                hCursor += 1
                If hCursor >= 32
                    hCursor = 0
                EndIf
                ; A SEVERED SECTION IS NOT DEBRIS. It is a piece of a person:
                ; it stays on the floor for minutes rather than seconds, and it
                ; is not flung -- a torso that cartwheels across the room reads
                ; as a bouncing prop, where one that drops where it was cut
                ; reads as what it is. FL_Chunk is told before its 3D arrives,
                ; because OnLoad is where it decides how hard to throw itself
                ; and PlaceAtMe attaches 3D a frame or more later.
                ; (not for an engine-placed piece -- its roll told it,
                ; before its OnInit ran, and this call would only stall here
                ; on that OnInit for nothing.)
                If isSection && refId == 0
                    FL_Chunk ch = piece as FL_Chunk
                    If ch
                        ; AND THE KICK RIDES ON THE SAME CALL -- see
                        ; FL_Chunk.ItIsAPieceOfTheBody for why it is not a slot.
                        ch.ItIsAPieceOfTheBody(kick)
                    EndIf
                EndIf
                ; ---- PUT IT WHERE IT GOES, IN ONE MOVE -------------------
                ;
                ; ONE MOVE PER PIECE, AND IT HAPPENS BEFORE THE 3D EXISTS.
                ; This is the entire spawn delay, and the log named it:
                ; every piece was thrown 0.13 to 0.25s after its OWN placement
                ; -- fast -- while the placements themselves were half a second
                ; apart, and each piece's 3D went GOT -> lost -> GOT -> lost ->
                ; GOT before the next one was even created. Two losses, two
                ; moves:
                ;
                ;   MoveToNode  is a MOVE. It realises the reference at the
                ;               target, which attaches the 3D there and then.
                ;   SetPosition then lands on a reference whose 3D is already
                ;               built, and moving a built havok body rebuilds
                ;               it -- the same rebuild SetScale and
                ;               SetMotionType were each removed for.
                ;
                ; So the destination is now WORKED OUT before the piece is
                ; touched, and applied once. NetImmerse.GetNodeWorldPosition*
                ; reads the bone's world position off their skeleton directly --
                ; three native reads, no move, nothing realised -- and the
                ; single SetPosition that follows lands within a few
                ; milliseconds of PlaceAtMe, long before the 3D arrives about
                ; 0.18s later. Moving a reference that has no 3D yet is free
                ; and invisible; that was always the intent of the clearance,
                ; and it is only true now.
                ;
                ; The arithmetic is unchanged: out along the vector from their
                ; centre to the bone, which for a limb points through the
                ; surface, plus a lift so a piece cut from a body lying flat
                ; clears the floor instead of spawning through it. Verified as
                ; the same destination the two-move version computed.
                ;
                ; HasNode stays. GetNodeWorldPositionX on a node they do not
                ; have returns 0.0, and a piece flung to the world origin is a
                ; far worse failure than a piece left where PlaceAtMe put it.
                ; (an engine-placed piece was moved by the engine with
                ; this same arithmetic -- clearance and lift are carried to
                ; the DLL on the cfg's E line -- so it is not moved twice.)
                If refId == 0 && nd != "" && nd != "-" && NetImmerse.GetNodeWorldPosition(victim, nd, np, false)
                    Float nx = np[0]
                    Float ny = np[1]
                    Float nz = np[2]
                    Float ox = nx - vx
                    Float oy = ny - vy
                    Float len = Math.sqrt(ox * ox + oy * oy)
                    If len > 0.001
                        Float push = SpawnClearance / len
                        piece.SetPosition(nx + ox * push, ny + oy * push, nz + SpawnLift)
                    Else
                        piece.SetPosition(nx, ny, nz + SpawnLift)
                    EndIf
                EndIf
                ; DISMEMBERING FRAMEWORK IS NO LONGER ASKED TO TINT THIS.
                ;
                ; It never could. Its job is to write a skin tint onto a limb,
                ; and until now every piece this mod forged carried the
                ; 100-byte type-0 shader block, which has no tint field at all
                ; -- so the call had nowhere to put a colour and a target with an unusual skin
                ; colour still dropped white shards. The colour is now measured
                ; off their own live shader and baked into the mesh before it is
                ; ever written, which is both correct and free.
                ;
                ; It is also off the critical path now, and that matters: the
                ; function is called UpdateLimbScaleAndTint, scaling a havok
                ; reference rebuilds its 3D, and a rebuild is the one thing this
                ; code is trying to stop paying for.
                ; The constant is tested FIRST so the other two are never
                ; evaluated. Free, and this loop counts instructions.
                If UseDismemberingFramework && df && vic
                    DismemberingFramework.UpdateLimbScaleAndTint(piece, vic)
                EndIf
                ; NOT KICKED FROM HERE. PlaceAtMe hands back a reference whose
                ; 3D has not been built yet, so an impulse thrown in this frame
                ; lands on a havok body that does not exist -- 43 of them in one
                ; test's log, every one "Object has no 3D", every one lost.
                ; FL_Chunk has always thrown its own from OnLoad, which is the
                ; frame the body becomes real. This was a second kick that could
                ; never land, and its errors were mistaken for evidence that the
                ; mesh had failed to load.
                placed += 1
                If refId != 0
                    byEngine += 1
                EndIf
            EndIf
        EndIf
        k += 1
    EndWhile
    ; LOGGED, because its silence used to prove nothing. The watcher
    ; consumed lines and logged only that it had found them, so a log full of
    ; "found 72 chars" was equally consistent with every piece landing and with
    ; none of them landing.
    ; THE COST OF THIS LOOP, IN THE LOG, PERMANENTLY.
    ;
    ; Not a probe: one line per wound, and it is the only number that can tell
    ; "the pieces were slow to build" from "the pieces were slow to be asked
    ; for". Those used to be indistinguishable, and each piece
    ; reporting its own 0.18s while the wound took four seconds is how
    ; that looks from the inside.
    Float ms = (Utility.GetCurrentRealTime() - t0) * 1000.0
    Int denom = placed
    If denom < 1
        denom = 1
    EndIf
    Debug.Trace("[FleshCore] watcher placed " + placed + " of " + n + " piece(s) on " + victim \
                + " (" + severed + " severed section(s), flags " + flags \
                + ", " + byEngine + " placed by the engine)" \
                + " -- placement loop " + ms + "ms" \
                + ", " + (ms / denom) + "ms/piece")
    ; THE RAW LINE, KEPT. Every piece that ever appears in the game appears
    ; because this string parsed correctly, and it has never been written down.
    ; A wound whose pieces did not show up and a wound whose line was malformed
    ; produced the same log, and the parser is field-counted -- one wrong
    ; separator silently drops every piece after it.
    If ProbeVerbose
        Debug.Trace("[FleshCore] PROBE line w=" + part[0] + " raw='" + out + "'" \
                    + " fields=" + part.Length + " live=" + Watching())
    EndIf
    If placed > 0
        If severed > 0
            Debug.Notification("[FleshCore] dismembered -- " + severed + " section(s) taken")
        Else
            Debug.Notification("[FleshCore] " + placed + " shard(s) taken")
        EndIf
        ; THE WOUND-LEVEL SPLATTER IS OFF, and it is the one that has been
        ; producing the square frame with the white edge.
        ;
        ; It is the LARGE impact -- 80 to 128 units, the size of the artefact in
        ; the screenshots -- and unlike every vanilla use of that record it is
        ; not played at a surface a weapon just struck. It is played from the
        ; VICTIM'S ORIGIN, straight down, for 160 units. A ragdoll's origin sits
        ; at or below the floor it is lying on, so the projection box starts
        ; inside the geometry it is meant to land on and the decal is cut off at
        ; a straight boundary where the box ends, with the border texels smeared
        ; along the cut.
        ;
        ; Three attempts to tune the record itself -- vanilla sizes, vanilla
        ; texture set, vanilla orientation -- changed nothing, because the
        ; record was never the problem; where it is played from is. The shards
        ; each play their own small impact where they actually come to rest
        ; (FL_Chunk.Land), which is a real surface contact and looks right, so
        ; the floor still gets blood.
        ;
        ; Set true to bring it back.
        If Squish && WoundSplatter
            victim.PlayImpactEffect(Squish, "", 0.0, 0.0, -1.0, 160.0, false, false)
        EndIf
        If vic
            NotifySkyrimNetFromPlace(vic, flags, placed, severed, prov)
        EndIf
    EndIf
EndFunction

Function Dismember(Actor vic)
    {THEY COME APART, SO THEY DIE, AND WHAT IS LEFT OF THEM FALLS.

     Three things, and each is here for its own reason.

     PROTECTION FIRST. A Protected or Essential actor survives Kill() in
     silence, and this must not stay silent: their leg is already
     gone from the mesh by the time this runs, so an actor who shrugs off the
     death stands there walking around a body they no longer have. The same
     clearing FL_Wound does for a deliberate cast is done here, because the
     engine wounds on ordinary hits too and those never go through the spell.

     THE KILL IS UNATTRIBUTED. Kill() with no argument kills them without naming
     a murderer, which is the standing rule for everything this mod does: no
     bounty, no aggro, no witnesses turning on the player for a spell that is
     meant to be studied rather than fought with.

     AND THEN THE RAGDOLL. A killed actor plays a death ANIMATION, which is a
     target lowering themselves gracefully to the floor on legs that are lying six
     feet away. PushActorAway is the engine's own ragdoll trigger; the push
     itself is small, because the point is the ragdoll and not the flight.

     READ THE SIGNATURE. It is declared on ObjectReference as

         Function PushActorAway(Actor akActorToPush, float aiKnockbackForce)
         ; Pushes the passed-in actor away from this object

     -- so the actor it is CALLED ON is the source and the ARGUMENT is the one
     that gets thrown. Written the other way round, every dismemberment threw
     THE PLAYER across the room and left the victim standing. That is why
     every hit with a voxelising spell knocked the player to the
     ground. The player pushes them; they are the argument.

     When they ARE the player there is nobody to push them, so they take a small
     impulse straight up instead.}
    If vic.IsDead()
        Return
    EndIf
    Actor pusher = Game.GetPlayer()
    If vic != pusher
        ActorBase ab = vic.GetActorBase()
        If ab
            ab.SetProtected(false)
            ab.SetEssential(false)
        EndIf
    EndIf
    ; Design note: when the player dies a FleshCore death, the camera sits
    ; a little further out than usual. Raised BEFORE the kill, while
    ; the caller (consumers) is still holding them in third person -- see
    ; DeathCamOut (an INI setting, and no forced third person).
    If pusher && pusher == vic
        DeathCamOut()
    EndIf
    KillForReal(vic)
    If pusher && pusher != vic
        pusher.PushActorAway(vic, 1.0)
    Else
        vic.ApplyHavokImpulse(0.0, 0.0, 1.0, 6.0)
    EndIf
    Debug.Trace("[FleshCore] " + vic + " was severed -- killed and ragdolled")
EndFunction

Int Function Watching()
    {How many pieces this watcher is currently holding, and how many of them
     have 3D.

     Packed as loaded*100 + held, because one Trace field is cheaper than two
     and these two numbers are only ever read together. The question behind it
     is whether the failures start once some number of pieces are alive at once
     -- a limit being hit -- or whether the count has nothing to do with it.
     That was unanswerable before: nothing ever counted them.}
    If !hRef
        Return 0
    EndIf
    Int held = 0
    Int live = 0
    Int i = 0
    While i < 32
        If hRef[i]
            held += 1
            If hRef[i].Is3DLoaded()
                live += 1
            EndIf
        EndIf
        i += 1
    EndWhile
    Return live * 100 + held
EndFunction

ObjectReference[] Function LiveShards()
    {The pieces in the ring that are non-null and have 3D.
     The ring wraps at 32 and nothing removes a deleted piece from it,
     so the filter is the contract. FL_Api.PlacedShards reads this.}
    ObjectReference[] out = new ObjectReference[32]
    Int n = 0
    If !hRef
        Return out
    EndIf
    Int i = 0
    While i < 32
        If hRef[i] && hRef[i].Is3DLoaded()
            out[n] = hRef[i]
            n += 1
        EndIf
        i += 1
    EndWhile
    Return out
EndFunction

Function Remember(ObjectReference piece)
    If !hRef
        hRef = new ObjectReference[32]
        hWhen = new Float[32]
    EndIf
    ; A CURSOR, NOT A SCAN. This used to walk all thirty-two slots twice over
    ; -- once for the first empty one, once for the oldest -- per piece placed,
    ; inside the loop that is the entire spawn delay. It is a ring buffer
    ; written in time order, so the slot after the last one written IS both the
    ; first unused slot and, once it has wrapped, the oldest: the same answer
    ; the scan gave, for two operations instead of two hundred.
    Int slot = hCursor
    hCursor += 1
    If hCursor >= 32
        hCursor = 0
    EndIf
    hRef[slot] = piece
    hWhen[slot] = Utility.GetCurrentRealTime()
EndFunction

Function Heal()
    {WATCH THE PLACED PIECES. DO NOT TOUCH THEM.

     DELETING A PIECE AND PLACING IT AGAIN IS WHAT EATS THE SHARDS, SO THIS
     FUNCTION NEVER DOES IT.

     A retry only helped while the forged files would not open at all -- the
     shader declared the geometry skinned while the shape carried no skin
     instance, so NOTHING ever got 3D. Now that the meshes load, a retry is
     the problem instead of the cure: at a four-second deadline it replaced
     every piece of a wound and then gave up on the replacements too.





     Pieces of a few hundred kB do not all attach inside four seconds. They
     were still attaching; the retry deleted them halfway there, placed a
     replacement, and lost the same race again.


     A longer deadline is no cure: it is the same mistake with a bigger
     number.
     A deadline cannot know how long a piece needs, and
     guessing wrong DESTROYS a piece that was fine. So there is no deadline and
     no replacement. A piece is watched, and if it is still 3D-less
     after twenty seconds that is written to the log and the slot is
     released.}
    If !hRef
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Int i = 0
    While i < 32
        ObjectReference piece = hRef[i]
        If piece
            If piece.Is3DLoaded()
                hRef[i] = None
            ElseIf now - hWhen[i] > 20.0
                Debug.Trace("[FleshCore] watcher: a piece was still 3D-less after 20s" \
                            + " -- left alone, not replaced (" + piece + ")" \
                            + " disabled=" + piece.IsDisabled() \
                            + " deleted=" + piece.IsDeleted() \
                            + " cell=" + piece.GetParentCell() \
                            + " base=" + piece.GetBaseObject() \
                            + " live=" + Watching())
                hRef[i] = None
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

Function ReviveRequested()
    {The engine has un-cut everyone and names who it was holding; this puts the
     dead ones back on their feet.

     WHY THE SCRIPT AND NOT THE DLL. The DLL does not kill either -- it flags a
     blow as fatal and this side calls Kill. Resurrect is the same kind of call,
     so it comes back the same way, through the same one-file mailbox the
     dressing requests already use.

     ONLY THE DEAD. Resurrect() on a living actor is not a no-op: it rebuilds
     their 3D, refills their inventory from their template and cancels whatever they
     were doing. The restore is supposed to be invisible to anyone still
     standing, so IsDead() is the gate and it is not optional.}
    String req = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.revive.txt")
    If req == ""
        Return
    EndIf
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.revive.txt", "", false, false)
    String[] ids = StringUtil.Split(req, "|")
    ; FIELD ZERO IS THE HEAD, NOT AN ACTOR. The engine names it because this
    ; script has no property for it and Resurrect() takes it off them.
    Armor headArmor = None
    If ids.Length > 0 && ids[0] != "" && ids[0] != "0"
        headArmor = Game.GetFormEx(ids[0] as Int) as Armor
        If headArmor
            headFill = headArmor
            StampNoStrip(headFill)
        EndIf
    EndIf
    Int k = 1
    Int back = 0
    While k < ids.Length && k < 64
        If ids[k] != ""
            Actor a = Game.GetFormEx(ids[k] as Int) as Actor
            ; ---- DEAD IS NOT THE ONLY WAY TO BE DOWN -----------------------
            ;
            ; Field report: in Dragonsreach, for example, an NPC could not be revived
            ; after being voxelised. The DLL hands them over -- the log says
            ; "6 actor(s) handed to the watcher" on every cast -- so the name
            ; arrives and the gate is what drops them.
            ;
            ; With ACHERON installed, its own log says what it is doing:
            ; "Loaded 3 Victims from cosave", "Loaded 3 Pacified from cosave".
            ; Acheron's whole purpose is to intercept a death and convert it to
            ; DEFEAT, and by its own header a defeated actor is bleeding out and
            ; immune to damage -- ALIVE. IsDead() is false for them, forever, and
            ; a gate that asks only that question will never pick them up.
            ;
            ; So the question widens to the one that was always meant: are they
            ; DOWN? Dead, bleeding out, or unconscious all count. A target still
            ; on their feet is still excluded, which is the reason the gate exists
            ; -- Resurrect() on someone standing rebuilds their 3D, refills their
            ; inventory from their template and cancels what they were doing.
            ;
            ; LIMIT: if Acheron holds them in a state that reports
            ; none of these three, this does not reach them either, and the fix
            ; is a call in Acheron's own API. The
            ; trace below says which of the three it was, so the log
            ; answers that.
            Bool down = false
            Bool defeated = false
            FL_KO_Hold reg = Hold()
            If a
                CleanFEC(a)
                defeated = HasAcheron() && Acheron.IsDefeated(a)
                down = a.IsDead() || defeated || a.IsBleedingOut() || a.IsUnconscious()
                ; ---- KNOCKED OUT IS NOT DOWN TO THIS SPELL ----
                ;
                ; A target the knockout register holds is unconscious on purpose
                ; and ALIVE. Resurrect() on them is the destructive case the
                ; note above warns about -- rebuilt 3D, inventory from their
                ; template, whatever they were doing cancelled -- and a later
                ; test did that to two held targets.
                ; Restore un-cuts them like everybody else; standing them up is
                ; the Cure's job. A held target who is DEAD is a corpse and is
                ; resurrected as before; the register is told, below.
                If down && !a.IsDead() && reg && reg.IsHeld(a)
                    down = false
                    Debug.Trace("[FleshCore] revive: " + a + " is knocked out by FleshCore and alive -- left held; the Cure stands them up")
                ElseIf !down
                    Debug.Trace("[FleshCore] revive: " + a + " is not down " \
                        + "(dead=" + a.IsDead() + " bleedout=" + a.IsBleedingOut() \
                        + " unconscious=" + a.IsUnconscious() + ") -- left alone")
                EndIf
            EndIf
            If a && down
                ; LOGGED BEFORE IT IS DONE. Field report: an NPC killed
                ; by Detonate came back whole from a Restore but never got up,
                ; and the log of that revive said nothing at all -- this path
                ; only spoke for the targets it left alone. The engine's own two
                ; state words are read through PapyrusExtender: life (0 alive,
                ; 1 dying, 2 dead, 3 unconscious, 7 essential-down, 8 bleedout)
                ; and knock (0 normal, 3 out, 5 queued, 6 getting up, 7 down),
                ; the enums in ActorState.h; raw numbers, so a reading that
                ; does not fit is still in the log.
                Debug.Trace("[FleshCore] revive: " + a + " is down (life=" \
                    + PO3_SKSEFunctions.GetActorState(a) + " knock=" \
                    + PO3_SKSEFunctions.GetActorKnockState(a) + " dead=" + a.IsDead() \
                    + " bleedout=" + a.IsBleedingOut() + " unconscious=" + a.IsUnconscious() \
                    + " defeated=" + defeated + ") -- " \
                    + StringIf(defeated && !a.IsDead(), "Acheron rescue", "Resurrect"))
                ; ---- WHAT RESURRECT TAKES AWAY -------------------------
                ;
                ; Resurrect() does not just stand them up: it resets the actor,
                ; and an actor reset comes back with their BASE inventory. So they
                ; lose the interior this mod equipped on them -- which is why a
                ; restored corpse stopped rendering flesh inside their clothing
                ; from then on -- and they lose the test head. Both are things
                ; this side put on them, so both are this side's to put back.
                ;
                ; ---- DEFEATED IS NOT DEAD, AND MUST NOT BE RESURRECTED ----
                ;
                ; A defeated target is ALIVE -- bleeding out and immune. Resurrect
                ; on someone alive is destructive: it rebuilds their 3D, refills
                ; their inventory from their template and cancels what they were doing.
                ; Acheron's own RescueActor is the supported way out of the state
                ; it put them in, so that is what they get; only somebody actually
                ; dead is resurrected.
                If defeated && !a.IsDead()
                    Acheron.RescueActor(a)
                Else
                    a.Resurrect()
                    ; PARALYSIS SURVIVES RESURRECT (standard
                    ; own warning, consumer scripts), and a target revived
                    ; with it at 1 lies there for good. The knockout hold sets
                    ; it on every target it puts down and leaves it on their
                    ; corpse, and a consumer sets it on its corpses too -- so a body
                    ; brought back here is taken to zero unconditionally, the
                    ; way a consumer's RecoverPlayer does, before the register is told.
                    ; The register then gives back the rest of what it set (the
                    ; flag, and the AI under the AI-freeze hold) in this same frame
                    ; rather than on its next tick.
                    a.SetActorValue("Paralysis", 0.0)
                    If reg
                        reg.Revived(a)
                    EndIf
                EndIf
                ; The interior for clothed actors and head fill for all,
                ; unforced so a naked body is not given a duplicate 129 MB interior.
                Dress(a, false)
                ; ---- AND THE HEAD COMES BACK THROUGH Dress(), NOT HERE ----
                ;
                ; This used to add and equip the head armour itself whenever they
                ; had been wearing one. Now that is wrong twice over:
                ; SeatHead inside Dress() has a beast-race guard and a slot-47
                ; occupancy check, and an unguarded EquipItem here walks past
                ; both. Resurrect() refills their inventory from their template, so
                ; the cape SeatHead had just decided not to fight for could be
                ; back on them -- and this line would knock it straight off
                ; again, every revive, for the rest of the save. Dress(a, true)
                ; above already re-seats the head; one path, one set of rules.
                ; ---- AND THEY ARE CLEANED, BECAUSE NOTHING ELSE EVER DID ----
                ;
                ; Field report: restored targets were still covered in alt.
                ; There were two separate reasons for it, so
                ; there are two calls.
                ;
                ; THE COAT. DC_Api.CoatSkin and DC_Api.Coat play an effect
                ; shader with a duration of -1.0, which the engine reads as
                ; forever, and at first DecalCore had no call that stopped
                ; one. the burst script coats them at the heaviest band on every
                ; cast; Resurrect does not touch a shader. Both kinds are taken
                ; off because a target can have been shot with either and this
                ; is not the place to work out which.
                ;
                ; THE OVERLAY MARKS. Those are RaceMenu node properties, and
                ; Resurrect leaves them alone as well -- and the save's own
                ; record of them would have the next load paint them back on
                ; whatever this did. ClearMarks is the pair: the live layers
                ; and the record together.
                ;
                ; AFTER the dressing and the head, deliberately. Both of those
                ; put ARMOUR on them, and an overlay is written onto the 3D they
                ; are wearing; cleaning first and equipping after invites the
                ; rebuild an equip can queue to arrive on top of the clean.
                DC_Api.Uncoat(a, DC_Api.ALT())
                DC_Api.Uncoat(a, DC_Api.BLOOD())
                DC_Api.ClearMarks(a)
                CleanFEC(a)
                ; AND THEY ARE LOOKED AT AGAIN, because Resurrect() returning is
                ; not evidence that they got up -- see ReviveCheckPass.
                BeginReviveCheck(a)
                back += 1
            EndIf
        EndIf
        k += 1
    EndWhile
    If back > 0
        Debug.Notification("[FleshCore] restored; " + back + " revived")
    Else
        Debug.Notification("[FleshCore] restored")
    EndIf
EndFunction

Function CleanFEC(Actor a)
    {Remove Frozen Electrocuted Combustion (FEC.esp) charred/skeleton/drained meshes,
     shaders, and permanent death-effect state when an actor is restored or revived.}
    If !a || !Game.IsPluginInstalled("FEC.esp")
        Return
    EndIf
    FEC_Utility.AssignPermanentDeathEffect(a, -1)
    FEC_Utility.AssignTemporaryDeathEffect(a, -1)
    FEC_Utility.SendFECResetEvent(a, 0, true)
    FEC_Utility.SendFECResetEvent(a, 1, true)
    FEC_Utility.ResetHead(a)
    PO3_SKSEFunctions.RemoveAllModItems(a, "FEC.esp", false)
    PO3_SKSEFunctions.StopAllShaders(a)
    PO3_SKSEFunctions.ResetActor3D(a, "po3_FEC")
    PO3_SKSEFunctions.SetSkinAlpha(a, 1.0)
    a.SetAlpha(1.0, false)
EndFunction

String Function JoinId(String list, String id)
    {A mailbox list: ids joined by '|'.}
    If list == ""
        Return id
    EndIf
    Return list + "|" + id
EndFunction

Function DressRequested()
    {The engine names who has no interior; this puts one on them -- up to 8 living
     actors per pass, each handed a Dress on a stack of its own (DressDispatch), so
     a fight's targets are dressed side by side rather than in turn, then one corpse.

     THE DEAD ARE DRESSED TOO. The interior takes about ten seconds
     to land and nearly every first blow is fatal, so a target struck on sight
     dies without it. Skipping the dead here left those corpses
     hollow -- FIELD: 10 bodies of 51 opened hollow and 8 of them never
     got it. But a biped rebuild on a ragdoll is a visible pop, so a corpse is
     dressed only if a FleshCore wound touched it (PlaceLine books them: 1 in
     FC_CorpseDress) and only once (2), one a pass and after the living, so a
     fight is not held up for its own dead. Never one already wearing it: forced,
     Dress re-seats what is worn. And never with the head fill: `gone` holds only
     the layers a cell had, so a skull seated on a corpse that lost its head has
     nothing cutting it and the head comes back.}
    String req = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.dress.txt")
    If req == ""
        Return
    EndIf
    MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.dress.txt", "", false, false)
    String[] ids = StringUtil.Split(req, "|")
    Int k = 0
    String headToken = "0"
    If ids.Length > 0 && ids[0] != "" && ids[0] != "0"
        Armor h = Game.GetFormEx(ids[0] as Int) as Armor
        If h
            headFill = h
            StampNoStrip(headFill)
            headToken = ids[0]
            k = 1
        EndIf
    EndIf
    Int dressedCount = 0
    Int handed = 0
    String leftover = ""
    String dead = ""
    While k < ids.Length && k < 64
        If ids[k] != ""
            Actor a = Game.GetFormEx(ids[k] as Int) as Actor
            If a && !a.IsDisabled()
                If a.IsDead()
                    dead = JoinId(dead, ids[k])
                ElseIf dressedCount < 8
                    handed = DressDispatch(a, false)
                    If handed > 0
                        dressedCount += 1
                    ElseIf handed < 0
                        leftover = JoinId(leftover, ids[k])
                    EndIf
                Else
                    leftover = JoinId(leftover, ids[k])
                EndIf
            EndIf
        EndIf
        k += 1
    EndWhile
    If dead != ""
        String[] corpses = StringUtil.Split(dead, "|")
        Bool served = dressedCount >= 8
        k = 0
        While k < corpses.Length
            If served
                leftover = JoinId(leftover, corpses[k])
            Else
                Actor c = Game.GetFormEx(corpses[k] as Int) as Actor
                If c && StorageUtil.GetIntValue(c, "FC_CorpseDress") == 1 && c.Is3DLoaded() && !c.IsEquipped(Interior)
                    If DressDispatch(c, true) > 0
                        StorageUtil.SetIntValue(c, "FC_CorpseDress", 2)
                        served = true
                    EndIf
                EndIf
            EndIf
            k += 1
        EndWhile
    EndIf
    ; Not on top of a request the DLL wrote during this pass: that one names
    ; everybody still undressed, these included.
    If leftover != "" && MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.dress.txt") == ""
        MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.dress.txt", headToken + "|" + leftover, false, false)
    EndIf
EndFunction

; ---- ONE DRESS, ONE STACK -------------------------------------------------
;
; DressRequested used to dress its targets IN TURN, inside this tick, and every
; Dress is a dozen or more native calls, each waiting for the game's thread.
; FIELD PROOF: six targets requested within twelve seconds, with the game in
; focus, were dressed one after another -- 10, 22, 28, 32, 33 and 37 seconds
; later -- each waiting for every Dress ahead of it, and the tick's other passes
; waiting for all of them. A mod event's handler runs on a stack of its own, so
; each target is now handed one: their native calls wait side by side, and the
; tick goes straight back to its other passes.
;
; `dressing` holds whom a handed-out Dress is working on, or finished with
; under fifteen seconds ago (`dressingDone`). The mailbox is rewritten whole on
; every request, so a body the engine never counts as dressed -- in testing, an
; Argonian whose interior never drew -- is named again pass after pass. FIELD
; PROOF: one fight sent 97 Dresses to 30 targets, one of them 15 times and
; several three to five times in three seconds, each taking off an interior
; they already wore and putting it back. So a target is dressed at most once
; in fifteen seconds, and a slot still in flight frees itself after twenty if
; its Dress never returns. A new process's clock starts again at zero, so a
; slot stamped later than now belongs to another session and is free. When no
; slot is free, the cooling one finished longest ago gives way; only when all
; 32 are in flight does a target wait for the next pass.
Form[] dressing
Float[] dressingAt
Bool[] dressingDone

Int Function DressDispatch(Actor a, Bool abNoHead)
    {Hands one Dress to a stack of its own: a mod event whose sender is the
     target, answered by OnFleshCoreDress. 1: handed out. 0: a Dress is working
     on them, or finished under fifteen seconds ago. -1: every slot is in
     flight, so the caller keeps them for the next pass.}
    If !a
        Return 0
    EndIf
    If !dressing || !dressingDone || dressing.Length != 32
        dressing = new Form[32]
        dressingAt = new Float[32]
        dressingDone = new Bool[32]
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Int slot = -1
    Int oldest = -1
    Int i = 0
    While i < 32
        Float age = now - dressingAt[i]
        Bool vacant = !dressing[i] || age < 0.0 || (dressingDone[i] && age >= 15.0) || (!dressingDone[i] && age >= 20.0)
        If dressing[i] == a
            If !vacant
                Return 0
            EndIf
            slot = i
        ElseIf vacant
            If slot < 0
                slot = i
            EndIf
        ElseIf dressingDone[i] && (oldest < 0 || dressingAt[i] < dressingAt[oldest])
            oldest = i
        EndIf
        i += 1
    EndWhile
    If slot < 0
        slot = oldest
    EndIf
    If slot < 0
        Return -1
    EndIf
    dressing[slot] = a
    dressingAt[slot] = now
    dressingDone[slot] = false
    ; Mod-event registrations do not survive a load (SKSE's Form.psc), so this
    ; one is made again right before the event that needs it; registering
    ; twice changes nothing.
    RegisterForModEvent("FleshCore_Dress", "OnFleshCoreDress")
    Float noHead = 0.0
    If abNoHead
        noHead = 1.0
    EndIf
    a.SendModEvent("FleshCore_Dress", "", noHead)
    Return 1
EndFunction

Function OnFleshCoreDress(String eventName, String strArg, Float numArg, Form sender)
    {One target's Dress, on a stack of its own (DressDispatch). numArg 1 leaves
     the head fill off, as for a corpse.}
    Actor a = sender as Actor
    If a
        Dress(a, true, numArg == 1.0)
    EndIf
    If dressing && dressingDone
        Int i = dressing.Find(sender)
        If i >= 0
            dressingAt[i] = Utility.GetCurrentRealTime()
            dressingDone[i] = true
        EndIf
    EndIf
EndFunction

Function Dress(Actor akActor, Bool abForce = false, Bool abNoHead = false)
    {Give an eligible body its interior, once, silently. abNoHead leaves the head
     fill off: a corpse's, see DressRequested.}
    If !akActor || !Interior || akActor.IsDisabled() || (!abForce && akActor.IsDead())
        If ProbeVerbose && akActor && abForce
            FL_Probe.Snapshot(akActor, Interior, "GATE-null-or-disabled")
        EndIf
        Return
    EndIf
    Bool wasWorn = akActor.IsEquipped(Interior)
    Int why = FL_Wound.WhyRefused(akActor)
    If why != 0
        If abForce
            If ProbeVerbose
                FL_Probe.Snapshot(akActor, Interior, "GATE-not-targetable")
            EndIf
            If announceDressing
                Debug.Notification("FleshCore: REFUSED " + akActor.GetDisplayName() \
                    + " -- not targetable")
            EndIf
        EndIf
        If why == 2
            MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.refused.txt", \
                akActor.GetFormID() + "\n", true, false)
        EndIf
        Return
    EndIf
    If !abForce && wasWorn
        If headFill && headFill != RetiredHead()
            SeatHead(akActor)
        EndIf
        Return
    EndIf
    Armor wornBody = akActor.GetWornForm(0x00000004) as Armor
    If !wornBody && !wasWorn
        If !abNoHead && headFill && headFill != RetiredHead()
            SeatHead(akActor)
        EndIf
        Return
    EndIf
    If !NiOverride.HasOverlays(akActor)
        NiOverride.AddOverlays(akActor)
    EndIf
    If akActor.GetItemCount(Interior) < 1
        akActor.AddItem(Interior, 1, true)
    EndIf
    If ProbeVerbose
        FL_Probe.Snapshot(akActor, Interior, "PRE-EQUIP")
    EndIf
    If wasWorn && abForce
        akActor.UnequipItem(Interior, false, true)
    EndIf
    akActor.EquipItem(Interior, false, true)
    If !abNoHead && headFill && headFill != RetiredHead()
        SeatHead(akActor)
    EndIf
    If wornBody && wornBody != Interior && wornBody != headFill && akActor.GetWornForm(0x00000004) != wornBody
        If akActor.GetItemCount(wornBody) < 1
            akActor.AddItem(wornBody, 1, true)
        EndIf
        akActor.EquipItem(wornBody, false, true)
    EndIf
    If ProbeVerbose
        FL_Probe.Snapshot(akActor, Interior, "POST-EQUIP")
        MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.dressing.log", \
            Utility.GetCurrentRealTime() + " equip " + akActor + "\n", true, false)
    EndIf
    If announceDressing
        Debug.Notification("FleshCore: dressed " + akActor.GetDisplayName())
    EndIf
    Debug.Trace("[FleshCore] dressed " + akActor)
EndFunction

; ---- THE PRE-DRESS AFTER A LOAD ----------------------------------
;
; WHAT IT BUYS, AND FOR WHOM. A body whose outfit covers it completely shows
; the DLL no player-race skin, so the DLL's cheap walk (JudgeFlesh) calls it
; "not flesh" -- until their next equip -- and never builds it; the first cast
; on it opens nothing, the wound path asks for a dress, and the second cast
; opens meat. Until now only two things reached such a body beforehand: the
; random sweep (two actors every hundred beats -- about ten seconds as the
; tick is measured) and being hit. This reaches the player and the five
; nearest at once, on the load. The interior carries a hidden copy of their own
; skin, and the DLL's walk does not skip hidden shapes, so once it is on them
; the roster's next offer finds them eligible and builds them on the warm
; thread -- and the first blow pays for a wound and nothing else. A body with
; skin showing was never this problem: the DLL pre-warms it itself and asks
; for its interior through the mailbox; this only gets there first.
;
; WITHIN THE DLL'S TEN-SECOND POST-LOAD WINDOW, an equip clears the "not
; flesh" write-off but queues no walk (the equip sink, flesh.cpp: "NOT THE
; LOAD'S OWN EQUIPS"). The roster sweep, queued 1.5 s after the load behind
; the warm thread's other work, puts every loaded actor on the roster, and
; the ticker offers four of the never-offered every half second whenever the
; warm thread is idle -- typically they are walked within a few seconds. The
; worst case is an actor the roster offered BEFORE their interior landed (a
; late 3D, or the DLL's own 2 s retry): they are offered again only after the
; roster's 20 s cooldown, so about twenty seconds after the load. Before
; this they were walked, judged not flesh, and never BUILT until something hit
; them.
;
; WHAT AN EQUIP COSTS ON A BODY THE DLL ALREADY HOLDS. A target cut before the
; save is re-cut by RestoreFromSave inside PostLoadGame and then WATCHED for
; sixty seconds on the game's own thread (flesh.cpp, WatchOne): any equip
; that changes their shape count inside that minute re-voxelises them there and
; then, on the frame; after the minute the same equip is re-read on the warm
; thread. So for them an equip in this window costs what the sweep would only
; charge if it happened to reach them inside the watch, and off-thread after.
; It falls only on such a target who still lacks something: a clothed cut
; target was dressed to be cut and wears both; a NAKED cut target was cut off
; their own baked fill, is never asked for by the DLL, and after an unequipall
; lacks the head, as is usual in testing. The dead are left out of the five
; altogether: a save made in the middle of a fight can have a dozen cut
; corpses at the player's feet, and re-voxelising every one of them on the
; frame in the first second buys nothing a corpse can use. So is a target held
; unconscious or paralysed (the knockout register's): a biped rebuild on a
; ragdoll is a visible pop; their head is left to the sweep, which has no such
; guard, and the Sequence's Decapitate on them is a neck cut that needs no
; skull. A standing naked cut target among the five pays one
; on-thread voxelise in the fade-in for their skull and brain; that is the
; trade, and it is stated here so the log reader expects the [LOAD] line.

Int[] Function CfgRow(String cfg, String token, Int fields)
    {The first `fields` numeric columns of the LAST row whose first
     tab-separated field is exactly `token`. Columns that are not there, or not
     numbers, come back as -1.

     WHY THIS EXISTS AT ALL. LearnHeadFromConfig below reads ONE number and
     cannot read two: Papyrus has no break, so its digit loop exits by setting
     its own index to the end of the string, and the cursor is destroyed on the
     way out. Copying that block four times would read the first column four
     times. This one carries a `done` flag instead, so the cursor survives and
     the columns can be walked.

     The row is found the way the DLL finds it and the way LearnHeadFromConfig
     already does: by the newline that starts it, with the character after the
     token required to be a TAB (ordinal 9) so that PK is never read as P --
     the DLL compares whole tokens for the same reason, which is why P, the
     chunk pool's row, is safe from this one. The LAST matching row wins, as it
     does there.}
    Int[] out = Utility.CreateIntArray(fields, -1)
    Int total = StringUtil.GetLength(cfg)
    Int tlen  = StringUtil.GetLength(token)
    Int at = -1
    If StringUtil.Find(cfg, token, 0) == 0
        at = 0
    Else
        at = StringUtil.Find(cfg, "\n" + token, 0)
        If at >= 0
            at += 1
        EndIf
    EndIf
    Int found = -1
    While at >= 0 && at < total
        If at + tlen < total && StringUtil.AsOrd(StringUtil.GetNthChar(cfg, at + tlen)) == 9
            found = at
        EndIf
        at = StringUtil.Find(cfg, "\n" + token, at + 1)
        If at >= 0
            at += 1
        EndIf
    EndWhile
    If found < 0
        Return out
    EndIf
    Int k = found + tlen
    Int col = 0
    Bool done = false
    While !done && col < fields
        ; Tabs and blanks between columns; a newline is the end of the row.
        While k < total && (StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k)) == 9 \
                         || StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k)) == 32)
            k += 1
        EndWhile
        If k >= total
            done = true
        ElseIf StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k)) == 10 \
            || StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k)) == 13
            done = true
        Else
            Int value = 0
            Int digits = 0
            Bool inNum = true
            While inNum && k < total
                Int c = StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k))
                If c >= 48 && c <= 57
                    value = value * 10 + (c - 48)
                    digits += 1
                    k += 1
                Else
                    inNum = false
                EndIf
            EndWhile
            If digits > 0
                out[col] = value
                col += 1
            Else
                ; A column that is not a number: stop rather than guess what it
                ; meant. Everything read so far stands.
                done = true
            EndIf
        EndIf
    EndWhile
    Return out
EndFunction

Function LearnPanelFromConfig()
    {Read the PK row and register the panel's hotkey.

     PK <on> <dxScanCode> <doubleMs> <effectLocal> <spellLocal> <pauseGame>

     Column 4 is the DLL's -- the magic effect it watches for. Column 5 is
     this script's: the SPELL that carries that effect, which is what gets
     cast. They are two records and two numbers, and neither is derived from
     the other.

     RE-REGISTERED ON EVERY LOAD, because a key registration does not survive
     one: it is per-session state held by the engine, not by the save. Not
     gated on skipFirstWindow the way the head learn is -- a new game should
     have its panel from the first beat, and registering a key costs nothing
     in the Helgen cart.}
    String cfg = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.cfg.txt")
    If cfg == ""
        Debug.Trace("[FleshCore] watcher: no config to read -- the panel hotkey is not registered")
        Return
    EndIf
    ; ---- LP <maxLive> <shardLife> <sectionLife> -- THE LIVE-PIECE CAP ----
    ; Read here because this runs on every load and the file is already in hand.
    ; FL_Chunk reads these three at its OnInit and in Life(); a missing row or
    ; column (-1) unsets the key, so the script's own default property applies
    ; exactly as if the row had never been written. The DLL reads the same row
    ; and says it in its [CFG] block, so the two sides cannot disagree silently.
    ; The piece ring itself is not cleared on load (unless the
    ; HQ's cap below is under what the save has down -- LearnPieceCap trims to
    ; it): it lives in the co-save, a
    ; loaded piece keeps its place (OnInit runs once per object, never again on
    ; a load), and a piece that is gone reads back as None and drains in
    ; FL_Chunk.JoinPieceRing's Shift loop.
    Int[] lp = CfgRow(cfg, "LP", 3)
    If lp[0] >= 0
        StorageUtil.SetIntValue(None, "FC_maxpieces", lp[0])
    Else
        StorageUtil.UnsetIntValue(None, "FC_maxpieces")
    EndIf
    If lp[1] > 0
        StorageUtil.SetFloatValue(None, "FC_shardlife", lp[1] as Float)
    Else
        StorageUtil.UnsetFloatValue(None, "FC_shardlife")
    EndIf
    If lp[2] > 0
        StorageUtil.SetFloatValue(None, "FC_sectionlife", lp[2] as Float)
    Else
        StorageUtil.UnsetFloatValue(None, "FC_sectionlife")
    EndIf
    Debug.Trace("[FleshCore] watcher: live-piece cap " + lp[0] + ", shard life " + lp[1] + " s, section life " + lp[2] + " s (LP row; -1 = FL_Chunk's default)")
    ; and the HQ's slider over it, put back even if unchanged, because
    ; the row above has just overwritten FC_maxpieces.
    LearnPieceCap(true)
    Int[] pk = CfgRow(cfg, "PK", 6)
    If pk[0] <= 0
        ; No row, or the row says off. Anything registered by a previous
        ; session of this process is taken back, so switching it off in the
        ; file and loading a save is enough to be rid of it.
        If panelKey > 0
            UnregisterForKey(panelKey)
            Debug.Trace("[FleshCore] watcher: the panel is off in the config -- key " + panelKey + " released")
        EndIf
        panelKey = 0
        panelSpell = 0
        Return
    EndIf
    Int want = pk[1]
    If want <= 0
        want = 52              ; DIK_PERIOD -- the '.' on the main keyboard
    EndIf
    ; ---- AND THE MCM WINS, IF THE PLAYER HAS SAID ANYTHING -----------------
    ;
    ; The config row is the DEFAULT, not the final word. This function runs on
    ; every load, so without this the file would take the player's key back every
    ; time they loaded a save -- the setting would appear to work and then
    ; silently undo itself, which is worse than not offering it at all.
    If panelKeyMCM == -1
        If panelKey > 0
            UnregisterForKey(panelKey)
        EndIf
        panelKey = 0
        panelSpell = pk[4]
        panelDouble = pk[2]
        If panelDouble <= 0
            panelDouble = 300
        EndIf
        Debug.Trace("[FleshCore] watcher: the panel hotkey is cleared in the MCM -- no key registered")
        Return
    ElseIf panelKeyMCM > 0
        want = panelKeyMCM
    EndIf
    If panelKey > 0 && panelKey != want
        UnregisterForKey(panelKey)
    EndIf
    panelKey = want
    RegisterForKey(panelKey)
    panelDouble = pk[2]
    If panelDouble <= 0
        panelDouble = 300
    EndIf
    panelSpell = pk[4]
    panelTapAt = 0.0
    If panelSpell <= 0
        Debug.Trace("[FleshCore] watcher: the PK row names no spell (column 5) -- the key is registered but nothing will open")
    Else
        Debug.Trace("[FleshCore] watcher: panel hotkey is a double tap on DX scan code " + panelKey \
                    + " within " + panelDouble + " ms, casting " + panelSpell)
    EndIf
EndFunction

Function LearnPieceCap(Bool abAfterRow)
    {THE HQ'S PIECE CAP. Once the HQ's "Pieces kept on the ground"
     slider has been moved, the DLL writes its number to FleshCore.pieces.txt
     whenever it changes; until then it writes the file empty. This hands the
     number to FL_Chunk's ring as FC_maxpieces and clears the floor down to it
     (FL_Chunk.TrimPieceRing, 32 a batch, the rest every four beats in
     OnUpdate), so lowering the slider empties the floor within a few seconds
     and every piece born after clears the oldest past it. 0 is no limit: a
     piece then goes when its own lifetime ends.

     abAfterRow is LearnPanelFromConfig's call: the LP row has just set
     FC_maxpieces from the config, so the HQ's number is put back even if it
     has not changed since it was last read. The tick's call, every forty
     beats, acts only on a change. An empty, missing or garbled file changes
     nothing, and the LP row stands, read on every load as before; it
     also forgets the last number read, which is kept in the save, so the
     slider's next number counts as a change even if it is that same one.}
    String raw = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.pieces.txt")
    If raw == "" || !StringUtil.IsDigit(StringUtil.GetNthChar(raw, 0))
        lastPiecesRaw = "-"
        Return
    EndIf
    If raw == lastPiecesRaw && !abAfterRow
        Return
    EndIf
    lastPiecesRaw = raw
    Int cap = raw as Int
    StorageUtil.SetIntValue(None, "FC_maxpieces", cap)
    piecesTrimPending = FL_Chunk.TrimPieceRing()
    Debug.Trace("[FleshCore] watcher: pieces kept on the ground " + cap + " (the HQ, over the LP row; 0 = no limit) -- FL_Chunk clears the oldest past it")
EndFunction

Function SetPanelKeyOverride(Int k)
    {Called by FL_MCM when the player rebinds, clears or resets the panel key.
     0 puts the config's PK row back in charge, -1 is cleared, anything else is
     their key. Applied at once and again on every load, because
     LearnPanelFromConfig re-reads the file each time.}
    panelKeyMCM = k
    LearnPanelFromConfig()
EndFunction

Int Function PanelKeyInUse()
    {The key actually registered right now, so the MCM can show the truth
     rather than its own idea of it. 0 means none.}
    Return panelKey
EndFunction

Int Function PanelDoubleMs()
    {The double-tap window in force.}
    If panelDouble <= 0
        Return 300
    EndIf
    Return panelDouble
EndFunction

Function LearnHeadFromConfig()
    {Read the X row of FleshCore.cfg.txt and resolve the head fill it names.

     The head armour has always been learned from field zero of a mailbox,
     because the engine is the side that knows the id -- and it knows it from
     exactly this row. After a load the mailbox may not come for a long time,
     and the pre-dress runs in the beats after the stamp. So the row is read
     as the DLL reads it (LoadConfig, flesh.cpp): the line whose first
     tab-separated field is X, its second field through atoi -- leading
     blanks skipped, digits until the first non-digit -- and when the file
     carries more than one X row the LAST one wins, as it does there. Two
     differences remain and neither can bite the shipped file: Papyrus
     compares strings without case, so a row beginning with a lowercase x is
     taken here and ignored there, and atoi accepts a sign where this reads
     zero; the config has never carried either. No row, or a row that reads
     zero, leaves headFill None and the pass seats no head -- what older code
     did until the first mailbox.

     CHEAP ON PURPOSE. This runs on the load beat, beside the strip window's
     opening pass. Find() jumps from one row beginning with X to the next
     (there is one), so a 170-row file costs a handful of natives rather than
     two per row.}
    String cfg = MiscUtil.ReadFromFile("Data/SKSE/Plugins/FleshCore.cfg.txt")
    If cfg == ""
        Debug.Trace("[FleshCore] watcher: FleshCore.cfg.txt could not be read -- the head is learned from the first mailbox")
        Return
    EndIf
    Int total = StringUtil.GetLength(cfg)
    Int headId = 0
    Int rows = 0
    ; `at` is the index of a row's first character. The first row has no
    ; newline before it, so it is looked at by hand; every other row is found
    ; by the newline that starts it.
    Int at = -1
    If StringUtil.GetNthChar(cfg, 0) == "X"
        at = 0
    Else
        at = StringUtil.Find(cfg, "\nX", 0)
        If at >= 0
            at += 1
        EndIf
    EndIf
    While at >= 0 && at < total
        ; The tab is 9 and has no case; the digits are 48-57 likewise. The
        ; letter was compared as a string above because AsOrd on a letter may
        ; answer either case (StringUtil.psc's own note).
        If at + 1 < total && StringUtil.AsOrd(StringUtil.GetNthChar(cfg, at + 1)) == 9
            rows += 1
            Int k = at + 2
            Int value = 0
            ; atoi: leading blanks are skipped...
            While k < total && (StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k)) == 32 \
                                || StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k)) == 9)
                k += 1
            EndWhile
            ; ...then digits, up to the first character that is not one.
            While k < total
                Int c = StringUtil.AsOrd(StringUtil.GetNthChar(cfg, k))
                If c >= 48 && c <= 57
                    value = value * 10 + (c - 48)
                    k += 1
                Else
                    k = total
                EndIf
            EndWhile
            headId = value
        EndIf
        at = StringUtil.Find(cfg, "\nX", at + 1)
        If at >= 0
            at += 1
        EndIf
    EndWhile
    If headId <= 0
        Debug.Trace("[FleshCore] watcher: no X row in FleshCore.cfg.txt names a head (" + rows \
                    + " X row(s)) -- the head is learned from the first mailbox")
        Return
    EndIf
    Armor h = Game.GetFormFromFile(headId, "FleshCore.esp") as Armor
    If !h
        Debug.Trace("[FleshCore] watcher: the config's X row names " + headId \
                    + ", which is not an armour in FleshCore.esp -- no head seated by the pre-dress")
        Return
    EndIf
    headFill = h
    Debug.Trace("[FleshCore] watcher: head fill " + h + " learned from the config's X row (" + headId + ")")
EndFunction

Bool Function PreDressListed(Form[] list, Int count, Form who)
    {Is `who` one of the first `count` entries? Script-level compares, no natives.}
    Int j = 0
    While j < count
        If list[j] == who
            Return true
        EndIf
        j += 1
    EndWhile
    Return false
EndFunction

Function PreDressPass()
    {One pass of the post-load pre-dress: the player once, then the five
     nearest, each offered once per window.

     WHO. PO3_SKSEFunctions.GetActorsByProcessingLevel(0) is the engine's own
     high-process list -- the actors around the player that it is fully
     simulating, aiLevel 0 taken (an assumption:
     PO3_SKSEFunctions.psc declares the
     function with no doc comment at all)
     as the highest tier -- so
     there is no radius to guess at. Ranked
     by distance from the player, whether or not their 3D is up yet -- so a
     target whose 3D is still to come keeps their place among the five. They are
     offered anyway (an inventory equip needs no 3D to be asked for), but
     they are remembered as DONE only once their 3D is up: whether an equip asked
     before their 3D exists takes is undocumented, so
     until then they are asked again on every pass, and Dress() answers a
     worn interior with an early return. The five nearest that WhyRefused
     accepts and that are alive are the five; horses, dogs and draugr are in
     the list and refused by the same gate the sweep uses, so none of them
     takes a place, and neither does a corpse (see the note above). A
     refusal is remembered for the window -- up to sixty-four of them -- so
     a room of thirty draugr is gated once, not fifteen times.

     WHAT. PreDressOne: Dress() for a body with something in its body slot,
     the head alone for a naked one. Each target is offered once and then
     only counted: the passes repeat so that a target whose 3D was not in the
     list on the first beat is still one of the five when it is, not so that
     the same five are asked again.

     COST. One native array and one GetDistance per actor in high process on
     every pass; the gate, the worn-slot read and the dress on each NEW actor
     among the nearest, once. Fifteen passes after a load, never otherwise;
     it shares the fifth-of-a-second slot with CheckLoad and StripPass.}
    If predressPasses <= 0
        Return
    EndIf
    predressPasses -= 1
    Actor player = Game.GetPlayer()
    If !player || !Interior || !predressDone || !predressSkip
        predressPasses = 0
        Return
    EndIf
    If !predressPlayerDone
        predressPlayerDone = true
        If FL_Wound.WhyRefused(player) == 0
            predressChanged += PreDressOne(player)
        EndIf
    EndIf
    Actor[] near = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    Int n = near.Length
    If n > predressSeen
        predressSeen = n
    EndIf
    If n > 0
        ; -1.0 marks a slot that is out: not an actor, the player, or already
        ; taken this pass. A real distance is never negative.
        Float[] dist = Utility.CreateFloatArray(n)
        Int i = 0
        While i < n
            Actor c = near[i]
            If !c || c == player
                dist[i] = -1.0
            Else
                dist[i] = c.GetDistance(player)
            EndIf
            i += 1
        EndWhile
        ; Five places: the nearest slot still in, taken out, then placed,
        ; skipped, or gated and offered. Bounded by n whatever the gate says,
        ; since every turn takes one slot out.
        Int chosen = 0
        While chosen < 5
            Int best = -1
            Float bestD = 0.0
            i = 0
            While i < n
                If dist[i] >= 0.0 && (best < 0 || dist[i] < bestD)
                    best = i
                    bestD = dist[i]
                EndIf
                i += 1
            EndWhile
            If best < 0
                chosen = 5
            Else
                dist[best] = -1.0
                Actor a = near[best]
                If PreDressListed(predressDone, predressDoneN, a)
                    chosen += 1                       ; already offered: still one of the five
                ElseIf !PreDressListed(predressSkip, predressSkipN, a)
                    If a.IsDead() || a.IsDisabled() || FL_Wound.WhyRefused(a) != 0
                        If predressSkipN < predressSkip.Length
                            predressSkip[predressSkipN] = a
                            predressSkipN += 1
                        EndIf
                    ElseIf predressDoneN < predressDone.Length
                        ; Remembered only with their 3D up (the docstring says
                        ; why); until then they are asked again next pass.
                        If a.Is3DLoaded()
                            predressDone[predressDoneN] = a
                            predressDoneN += 1
                        EndIf
                        predressChanged += PreDressOne(a)
                        chosen += 1
                    Else
                        chosen = 5                    ; the window's budget of targets is spent
                    EndIf
                EndIf
            EndIf
        EndWhile
    EndIf
    If predressPasses <= 0
        Debug.Trace("[FleshCore] watcher: pre-dress after the load done -- " + predressChanged \
                    + " actor(s) given an interior or a head, " + predressDoneN \
                    + " target(s) offered, " + predressSkipN + " refused or dead, " \
                    + predressSeen + " in high process at most")
        MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.dressing.log", \
            Utility.GetCurrentRealTime() + " predress done: " + predressChanged \
            + " changed, " + predressDoneN + " offered, " + predressSkipN + " skipped, " \
            + predressSeen + " in high process\n", true, false)
        ; AND THE LISTS ARE EMPTIED. Both are script variables, so every actor
        ; they hold is a reference the save keeps alive; a spawned actor held
        ; here would outlive their cleanup. Element by element, never `= None`
        ; (the Caprica cast CheckLoad's reviver note describes).
        Int e = 0
        While e < predressDoneN
            predressDone[e] = None
            e += 1
        EndWhile
        e = 0
        While e < predressSkipN
            predressSkip[e] = None
            e += 1
        EndWhile
        predressDoneN = 0
        predressSkipN = 0
    EndIf
EndFunction

Int Function PreDressOne(Actor a)
    {Give one gated actor what they lack for a first cast to open onto meat.
     Returns 1 if the inventory answers, in this same frame, that an interior
     or a head went on that was not on before; 0 otherwise.

     CLOTHED OR NAKED IS THE BODY SLOT'S FLAG. GetWornForm walks their inventory
     for a worn item whose biped flags include slot 32 (SKSE's PapyrusActor.cpp:
     MatchBySlot over ExtraContainerChanges::FindEquipped); the race's own skin
     is not an inventory item, so a naked body answers None. An item flagged
     for the body slot is what replaces their body mesh -- the one that carries
     their fill -- with its own, so they take the sweep's path: Dress(), unforced,
     interior and head together. A naked body keeps its meat and can lack only
     the skull and the brain, so they get SeatHead alone -- and only when the
     config has moved the head off the retired armour, the condition Dress()
     puts on its own early SeatHead, so a rolled-back X row behaves as it
     always did. SeatHead is asked even when they already wear the fill: an
     upgraded save can have them wearing the retired slot-30 head beside the
     slot-47 fill (SeatHead's own note), and SeatHead is what takes it off.

     NOT ON A TARGET WHO IS DOWN. The head alone is skipped for an actor who is
     unconscious or paralysed -- the knockout register's targets, ragdolled on
     the floor: a biped rebuild on a ragdoll is a visible pop, they are the
     cut-and-watched body the note above prices; their head is deferred to the
     sweep, and the Sequence's Decapitate is a neck cut that needs no skull
     (the W row for 2169 names the neck). The clothed path is not gated this
     way: an interior is what makes them a target at all, and the register
     holds only targets the DLL already knows.

     THE INTERIOR IS NOT PUT ON A NAKED BODY. The sweep would; this does not,
     because at a load the six are equipped together, and an interior on a
     body that already carries its fill is a hundred megabytes for nothing.
     Either equip is still an equip to the DLL: a body it already holds is
     re-read on the warm thread, and one it re-cut at the load on the game's
     thread (the note above).}
    If !a || a.IsDisabled()
        Return 0
    EndIf
    Bool hadHead = headFill && a.IsEquipped(headFill)
    If a.GetWornForm(0x00000004)
        Bool hadInt = a.IsEquipped(Interior)
        Dress(a, false)
        If !hadInt && a.IsEquipped(Interior)
            Return 1
        EndIf
        If headFill && !hadHead && a.IsEquipped(headFill)
            Return 1
        EndIf
        Return 0
    EndIf
    If headFill && headFill != RetiredHead()
        If a.IsUnconscious() || a.GetActorValue("Paralysis") > 0.0
            Return 0
        EndIf
        SeatHead(a)
        If !hadHead && a.IsEquipped(headFill)
            ; The same shape as Dress()'s "equip" line, and read the same way:
            ; the inventory's answer in the frame of the equip.
            MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.dressing.log", \
                Utility.GetCurrentRealTime() + " predress head " + a + "\n", true, false)
            If announceDressing
                Debug.Notification("FleshCore: head fill on " + a.GetDisplayName())
            EndIf
            Debug.Trace("[FleshCore] pre-dress: head fill seated on the naked " + a)
            Return 1
        EndIf
    EndIf
    Return 0
EndFunction

; ---- THE CONTINUOUS BLEED ------------------------------------------------
;
; While a target still has a trunk in one piece, they go on bleeding for a
; few seconds after the blow -- heavy at first and tapering to nothing, which
; is what an opened body does and also what the decal pool can afford.
;
; HEAVY THEN TAPERING, and the taper is the point rather than decoration. A
; flat rate for twelve seconds spends the same marks and reads as a leak; a
; front-loaded one reads as pressure falling. So the first seconds drop two
; marks a pass and the last ones drop one every other pass.
;
; The list is parallel arrays rather than a struct because Papyrus has no
; structs, and it is small on purpose: four targets bleeding at once is already
; more than a fight produces.

Int    Property BleedSlots  = 4    Auto
{How many targets may be bleeding at once. The fifth to be wounded takes the
 slot of whichever is furthest through their own bleed.}

Float  Property BleedFor    = 12.0 Auto
{Seconds a trunk bleeds for.}

; Form[] rather than Actor[]: SKSE gives CreateFormArray but no
; CreateActorArray, and `new Actor[n]` demands a literal size, which
; BleedSlots is not. Cast on read.
Form[] bleeder
Float[] bleedEnds
Float[] bleedStart

Function EnsureBleedArrays()
    If bleeder.Length == BleedSlots
        Return
    EndIf
    bleeder    = Utility.CreateFormArray(BleedSlots)
    bleedEnds  = Utility.CreateFloatArray(BleedSlots)
    bleedStart = Utility.CreateFloatArray(BleedSlots)
EndFunction

Function BeginTrunkBleed(Actor who)
    {Start or restart their bleed. A second wound on the same target restarts the
     clock rather than adding a second entry -- they are one body and it is one
     wound channel.}
    If !who || BleedFor <= 0.0
        Return
    EndIf
    EnsureBleedArrays()
    Float now = Utility.GetCurrentRealTime()
    Int i = 0
    Int free = -1
    Int oldest = 0
    Float oldestEnd = 0.0
    While i < bleeder.Length
        If bleeder[i] == who
            bleedEnds[i] = now + BleedFor
            bleedStart[i] = now
            Return
        EndIf
        If !bleeder[i] && free < 0
            free = i
        EndIf
        ; The one closest to finishing is the one to displace.
        If i == 0 || bleedEnds[i] < oldestEnd
            oldest = i
            oldestEnd = bleedEnds[i]
        EndIf
        i += 1
    EndWhile
    Int slot = free
    If slot < 0
        slot = oldest
    EndIf
    bleeder[slot] = who
    bleedEnds[slot] = now + BleedFor
    bleedStart[slot] = now
EndFunction

Function TrunkBleedPass()
    {One pass over everyone bleeding. Runs twice a second.}
    If bleeder.Length < 1
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Int i = 0
    While i < bleeder.Length
        Actor who = bleeder[i] as Actor
        If who
            If now >= bleedEnds[i] || who.IsDisabled() || who.IsDeleted()
                bleeder[i] = None
            Else
                ; How far through, 0.0 at the wound and 1.0 at the end.
                Float t = 0.0
                Float span = bleedEnds[i] - bleedStart[i]
                If span > 0.0
                    t = (now - bleedStart[i]) / span
                EndIf
                ; TWO MARKS EARLY, ONE LATE, NONE AT THE VERY END. The middle
                ; band drops one a pass; past three quarters it drops one every
                ; other pass, which is the tail of the taper.
                Int drops = 1
                If t < 0.25
                    drops = 2
                ElseIf t > 0.75
                    drops = 0
                    If (Utility.GetCurrentRealTime() * 2.0) as Int % 2 == 0
                        drops = 1
                    EndIf
                EndIf
                Int d = 0
                While d < drops
                    ; Straight down, from them, onto whatever they are standing
                    ; on. DC_Api.Splat is the same call the shards use.
                    DC_Api.Splat(who, DC_Api.BLOOD(), DC_Api.LARGE())
                    d += 1
                EndWhile
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

; ---- AND THE BLAST LIFT --------------------------------------------------
;
; Design note: Detonate sends the main body a little way into the air.
;
; A Detonate wound is the one blow in this mod that is an EXPLOSION rather than
; a cut, and the body it leaves behind has until now dropped exactly like the
; body a knife leaves. The DLL marks those wounds with bit 10 of the flags word;
; PlaceLine registers the victim here and this fires them, once, three beats
; later.
;
; WHY IT IS NOT DONE WHERE IT IS DECIDED. Dismember kills them one instruction
; earlier, and a killed actor is still in their animation graph for a moment
; afterwards. FL_GrindMe worked through precisely this and wrote the
; conclusion down (FL_GrindMe.psc, Collapse): ForceAddRagdollToWorld puts the
; ragdoll body into the physics world, and an impulse only means anything once
; it is there. The wait is a seventh of a second because that is three of this
; script's own beats, and PlaceLine may not wait for anything.
;
; THE SAME PARALLEL-ARRAY SHAPE AS THE BLEED, for the same reason: Papyrus has
; no structs, and a wound is not going to produce five simultaneous victims.
; Four slots, no property to set them from -- see the note above announceDressing
; about what adding one to this script costs.

Float Property LiftForce = 45.0 Auto
{How hard a Detonate throws what is left of them straight up. 0 disables it.

 FORTY-FIVE, AND EVERY NUMBER IN THAT RANGE IS SOMEBODY ELSE'S MEASUREMENT.
 The only calibrated magnitude this mod owns is Dismember's 6.0, which
 has thrown the player straight up on every self-inflicted dismemberment since
 the start with no report of them leaving the ground -- so 6.0 is the ceiling of
 INVISIBLE, not the floor of visible, and asking for visible means going well
 past it.

 Bethesda's own number for this exact gesture is the other end. In
 DLC1MagicEatenByBatsScript the bleeding actor is jerked repeatedly with
 ApplyHavokImpulse at magnitudes of 50.0 and 45.0 -- a corpse
 being visibly thrown about, which is the effect wanted here, at the scale
 Skyrim itself uses for it. Forty-five is the gentler of that pair.

 It is a property so testing can move it without a rebuild; it is not set in
 the plugin record, so this default is what runs.}

; Form[] rather than Actor[], for the bleed list's reason: SKSE gives
; CreateFormArray and no CreateActorArray. A literal four here, so the plain
; `new` will do and nothing has to be created lazily from a property.
Form[] lifter
Float[] liftAt

Function BeginTrunkLift(Actor who)
    {Book them a lift. A second Detonate on the same target restarts the clock
     rather than taking a second slot -- they are one body and it is one shove.}
    If !who || LiftForce <= 0.0
        Return
    EndIf
    If !lifter
        lifter = new Form[4]
        liftAt = new Float[4]
    EndIf
    ; THREE BEATS. The tick is a twentieth of a second (Tick()), so this is
    ; about a seventh of a second after the kill -- long enough for the death
    ; to have taken them out of their animation, short enough to read as part of
    ; the same blast rather than as something that happened to them afterwards.
    Float when = Utility.GetCurrentRealTime() + 0.15
    Int i = 0
    Int free = -1
    Int soonest = 0
    Float soonestAt = 0.0
    While i < lifter.Length
        If lifter[i] == who
            liftAt[i] = when
            Return
        EndIf
        If !lifter[i] && free < 0
            free = i
        EndIf
        ; The one closest to firing is the one to displace -- it is the one
        ; whose wound is oldest, exactly as in BeginTrunkBleed.
        If i == 0 || liftAt[i] < soonestAt
            soonest = i
            soonestAt = liftAt[i]
        EndIf
        i += 1
    EndWhile
    Int slot = free
    If slot < 0
        slot = soonest
    EndIf
    lifter[slot] = who
    liftAt[slot] = when
EndFunction

Function TrunkLiftPass()
    {One pass over everyone with a lift due. Runs on every beat.

     THE SLOT IS RELEASED BEFORE THE IMPULSE, not after, so that a call which
     somehow does not return cannot leave them booked for a lift on every beat
     for the rest of the session. Each fires once, and that is all.}
    ; Heal's guard rather than the bleed's, because this array is
    ; built on first use and there is no Ensure- function to have run.
    If !lifter
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Int i = 0
    While i < lifter.Length
        Actor who = lifter[i] as Actor
        If who && now >= liftAt[i]
            lifter[i] = None
            If !who.IsDisabled() && !who.IsDeleted()
                ; THE ORDER IS THE POINT, and it is FL_GrindMe's order: the
                ; ragdoll goes into the physics world first, because that is
                ; what gives the impulse something to act on.
                who.ForceAddRagdollToWorld()
                who.ApplyHavokImpulse(0.0, 0.0, 1.0, LiftForce)
                Debug.Trace("[FleshCore] blast lift: " + who + " thrown up at " + LiftForce)
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction


; ---- AND THE REVIVE IS CHECKED -----------------------------------------
;
; Field report: an NPC killed by Detonate had their body brought back by Restore
; but was not revived. The Papyrus log of that test
; (the Restore came ten seconds after the detonation) shows the revive path ran
; for them -- the 'dressed' line is the Dress() call that only the down branch
; makes -- and then nothing, because Resurrect() returns nothing and this side
; never looked at them again. Ten seconds later the game was saved, and in that
; save they read dead=False: so the engine had them ALIVE, lying on the floor
; in their death pose, and nothing ever stood them up. Whether Resurrect() failed
; outright on them, or stood them up in the engine's books and left their ragdoll
; where it was, is what the first check below reads and logs.
;
; The ladder, gentlest first, one rung per check; UP releases them at any check.
; The times are floors: the pass runs twice a second on paper and less often
; on a slow tick, and each rung is booked from when the previous
; one actually fired, so the last can land nearer nine seconds than six.
;   check 1 (+1.0 s)  still dead       -> Resurrect() again
;                     Acheron-defeated -> RescueActor
;                     alive but down   -> EnableAI + EvaluatePackage
;   check 2 (+2.5 s)  still dead       -> Resurrect() again + ResetHealthAndLimbs
;                     alive but down   -> ForceRemoveRagdollFromWorld: the
;                                         documented inverse of the call that
;                                         put their ragdoll into the world
;   check 3 (+4.0 s)  still dead       -> logged, and nothing more
;                     alive but down   -> Disable/Enable without the fade: a
;                                         rebuilt 3D. Never for the player, and
;                                         never for a target sitting in something
;                                         (GetSitState != 0) -- a piece of furniture
;                                         is not this script's to empty.
;   check 4 (+5.5 s)  the final word, in the log, whatever it is
;
; UP means: knock state normal (0) or getting up (6), life state alive (0),
; and neither bleeding out nor unconscious -- the same width as the gate that
; booked them, or the checker would call up a target its caller called down.
;
; SAME PARALLEL-ARRAY SHAPE AS THE LIFT. Sixteen slots: the revive file names
; up to sixty-three targets but a scene usually has a handful dead at once, and a
; seventeenth is simply not checked -- they still got their Resurrect(). Bookings
; are staggered a tenth of a second per slot so a whole Restore's worth of
; targets do not reach the same rung on the same beat.

Form[]  reviver
Float[] reviveAt
Int[]   reviveStage

Function BeginReviveCheck(Actor who)
    {Book them for the first check a second from now.}
    If !who
        Return
    EndIf
    If !reviver
        reviver = new Form[16]
        reviveAt = new Float[16]
        reviveStage = new Int[16]
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Int i = 0
    Int free = -1
    While i < reviver.Length
        If reviver[i] == who
            reviveAt[i] = now + 1.0 + (i * 0.1)
            reviveStage[i] = 1
            Return
        EndIf
        If !reviver[i] && free < 0
            free = i
        EndIf
        i += 1
    EndWhile
    If free < 0
        Debug.Trace("[FleshCore] revive check: no slot for " + who + " -- resurrected, not checked")
        Return
    EndIf
    reviver[free] = who
    reviveAt[free] = now + 1.0 + (free * 0.1)
    reviveStage[free] = 1
EndFunction

Function EndReviveCheck(Actor who)
    {Let them go: a death this mod deals is not a failed revive.

     The ladder cannot tell the two apart -- dead is dead to ReviveCheck, and a
     dead target in a slot is "STILL DEAD after the revive" and gets Resurrect().
     FIELD: a guard revived by a Restore lost their right
     forearm to a greatsword ten seconds later, which was fatal, and 3.6 s later the
     ladder's first look found them dead and stood them back up -- with the cut
     carried onto the new body. PlaceLine calls this for every wound that kills
     them or finds them dead. A death with no FleshCore wound in it (fire, a
     fall, FL_Effects' leg rule on a body with no fatal wound) is not seen here,
     and inside the ladder's few seconds it is still undone.}
    If !who || !reviver
        Return
    EndIf
    Int i = reviver.Find(who)
    If i >= 0
        reviver[i] = None
        Debug.Trace("[FleshCore] revive check: " + who + " was killed by a wound -- released, not resurrected")
    EndIf
EndFunction

Function ReviveCheckPass()
    {One pass over everyone with a check due. Runs on every beat; nothing to do
     on almost all of them.}
    If !reviver
        Return
    EndIf
    Float now = Utility.GetCurrentRealTime()
    Int i = 0
    While i < reviver.Length
        Actor who = reviver[i] as Actor
        ; A booking more than a minute in the future is one made on an older
        ; application clock (a quit and a reload): it is dropped, not waited on.
        If who && reviveAt[i] > now + 60.0
            reviver[i] = None
        ElseIf who && now >= reviveAt[i]
            Int stage = reviveStage[i]
            ; The slot is advanced BEFORE the check, so a call that does not
            ; return cannot leave them checked twice a second for the session.
            If stage >= 4
                reviver[i] = None
            Else
                reviveStage[i] = stage + 1
                reviveAt[i] = now + 1.5
            EndIf
            If ReviveCheck(who, stage)
                reviver[i] = None
            EndIf
        EndIf
        i += 1
    EndWhile
EndFunction

Bool Function ReviveCheck(Actor a, Int stage)
    {Are they up? True releases them. Otherwise the rung for this stage.}
    If a.IsDisabled() || a.IsDeleted()
        Return true
    EndIf
    CleanFEC(a)
    ; A TARGET THE KNOCKOUT HOLDS IS NOT ON THE FLOOR BY ACCIDENT. They
    ; can arrive here alive and held -- revived by a Restore and knocked out
    ; again inside this ladder's six seconds -- and every rung below would
    ; dismantle the hold: AI and package, the ragdoll out of the world, a
    ; rebuilt 3D. The register owns them; the slot is released.
    FL_KO_Hold reg = Hold()
    If reg && !a.IsDead() && reg.IsHeld(a)
        Debug.Trace("[FleshCore] revive check " + stage + ": " + a + " is held by the knockout -- left to it")
        Return true
    EndIf
    Int life = PO3_SKSEFunctions.GetActorState(a)
    Int knock = PO3_SKSEFunctions.GetActorKnockState(a)
    Bool dead = a.IsDead()
    Bool bleeding = a.IsBleedingOut()
    Bool unconscious = a.IsUnconscious()
    Bool defeated = HasAcheron() && Acheron.IsDefeated(a)
    ; Any knock state but normal (0) and the get-up itself (6) is 'on the
    ; floor': 1 and 2 are the explosion that a Detonate's own push is, 3-5 and
    ; 7 the lying there. Written as an exclusion so a value this list does not
    ; know still counts as down.
    Bool floor = (knock != 0 && knock != 6)
    ; Life 3 unconscious, 7 essential-down and 8 bleedout are down without
    ; being dead -- the shape Acheron leaves, and the shape the booking gate
    ; asked about.
    Bool down = floor || bleeding || unconscious || life == 3 || life == 7 || life == 8
    String s = "[FleshCore] revive check " + stage + ": " + a + " life=" + life \
        + " knock=" + knock + " dead=" + dead + " bleedout=" + bleeding \
        + " unconscious=" + unconscious + " defeated=" + defeated
    ; ---- STILL DEAD ---------------------------------------------------
    If dead || life == 1 || life == 2
        If stage == 1
            a.Resurrect()
            Debug.Trace(s + " -- STILL DEAD after the revive; Resurrect() called again")
        ElseIf stage == 2
            a.Resurrect()
            a.ResetHealthAndLimbs()
            Debug.Trace(s + " -- STILL DEAD; Resurrect() again and their health and limbs reset")
        Else
            Debug.Trace(s + " -- STILL DEAD after three Resurrect() calls; nothing further is tried. Include this log in a bug report.")
        EndIf
        Return false
    EndIf
    ; ---- UP -----------------------------------------------------------
    If !down
        Debug.Trace(s + " -- UP")
        Return true
    EndIf
    ; ---- ALIVE, BUT ACHERON HOLDS THEM ----------------------------------
    ; Only while they are actually on the floor: a target up on their feet but still
    ; carrying the flag is recovering, and the first rescue is left to work.
    If defeated && floor
        Acheron.RescueActor(a, true)
        Debug.Trace(s + " -- alive but Acheron holds them defeated; RescueActor")
        Return false
    EndIf
    ; ---- ALIVE, ON THE FLOOR ------------------------------------------
    If stage == 1
        a.EnableAI(true)
        a.EvaluatePackage()
        Debug.Trace(s + " -- alive but on the floor; AI re-enabled and their package re-evaluated")
        Return false
    EndIf
    If stage == 2
        ; The documented inverse of TrunkLiftPass's ForceAddRagdollToWorld:
        ; 'alive in the engine's books, ragdoll still in the world' is the
        ; stated hypothesis, and this is the one call that addresses it.
        a.ForceRemoveRagdollFromWorld()
        a.EnableAI(true)
        Debug.Trace(s + " -- alive but still on the floor; their ragdoll taken out of the physics world")
        Return false
    EndIf
    If stage == 3
        If a == Game.GetPlayer()
            Debug.Trace(s + " -- alive but on the floor, and they are the player: not disabled; left to the game")
            Return false
        EndIf
        If a.GetSitState() != 0
            Debug.Trace(s + " -- alive but on the floor, and sitting in something (sit state " \
                + a.GetSitState() + "): not disabled; whatever holds them keeps them")
            Return false
        EndIf
        ; A REBUILT 3D. Disable and Enable without the fade take them out of
        ; the world and put them back from their record at the spot they lie on.
        ; What the engine does with a live actor's pose on that rebuild is
        ; not something the headers state -- the next check reads it. Their
        ; inventory is untouched (only Resurrect resets it), so the interior
        ; stays on them and Dress is not called: it would only thrash the
        ; 128 MB mesh, and a call made before their 3D is back could register
        ; overlays onto nothing for the rest of the save.
        a.Disable(false)
        a.Enable(false)
        Debug.Trace(s + " -- alive but still on the floor; disabled and re-enabled for a rebuilt 3D")
        Return false
    EndIf
    Debug.Trace(s + " -- STILL ON THE FLOOR after every rung; nothing further is tried. Include this log in a bug report.")
    Return true
EndFunction

String Function StringIf(Bool abTest, String asYes, String asNo)
    If abTest
        Return asYes
    EndIf
    Return asNo
EndFunction

; ---- THE DEATH CAMERA -----------------------------------------------------
;
; Design note: when the player dies a FleshCore death, the camera sits
; a little further out than usual. The third-person camera's distance is
; bounded by two INI settings in [Camera], fVanityModeMinDist (155 as shipped)
; and fVanityModeMaxDist (600); Utility.SetINIFloat writes them (this used to
; write a GAME setting of that name, which does not exist, and the
; Papyrus log said so on every death). Raising the minimum pushes the camera
; out to at least that far. WHETHER THE ENGINE APPLIES A CHANGED MINIMUM TO A
; CAMERA ALREADY IN THIRD PERSON, without a zoom event, is UNKNOWN; this
; is the lever most likely to be right.
;
; PUT BACK THROUGH A FILE, NOT A VARIABLE. INI settings live in the process
; and are not saved; a script variable IS saved, and a death followed by a
; reload rolls it back to before the death -- leaving the setting raised with
; nothing that remembers it was. The previous value is written to
; FleshCore.cam.txt when it is raised and read back from there when it is
; restored: on the beat once they are alive again, and on every load.

Float Property DeathCamMinDist = 320.0 Auto
{How far out the camera is pushed when the player dies a FleshCore death; the
 shipped minimum is 155. 0 disables it.}

; When it was raised, on the application clock. A restore is refused for six
; seconds after: the frameworks around a player death (Acheron, this mod's
; own revive) can read them as not dead within a beat of the kill, and a zoom
; undone inside a second was never seen. Rolls back to 0.0 with a save, which
; satisfies the hold -- and a load restores unconditionally anyway.
Float deathCamAt = 0.0

; THE FILE IS A NUMBER, NEVER EMPTY-MEANS-SOMETHING. PapyrusUtil's header says
; only "Read string from file" / "Write string to file" -- nothing about a
; missing file, nothing about whether an empty write truncates -- so armed is
; "the file holds a number above zero" and disarmed is the string "0". A
; missing, empty or truncated file all read 0.0 and mean the same thing.
String Function CamFile() global
    Return "Data/SKSE/Plugins/FleshCore.cam.txt"
EndFunction

Function DeathCamOut()
    If DeathCamMinDist <= 0.0
        Return
    EndIf
    If (MiscUtil.ReadFromFile(CamFile()) as Float) > 0.0
        Return          ; already out, and the old value already on file
    EndIf
    ; AN INI SETTING, NOT A GAME SETTING. This once asked
    ; Game.GetGameSettingFloat for this and the Papyrus log answered, on
    ; every death: Error: Game setting "fVanityModeMinDist" does not exist.
    ; fVanityModeMinDist and fVanityModeMaxDist live in Skyrim.ini's [Camera]
    ; section, and the calls for those are Utility.GetINIFloat (SKSE's
    ; Utility.psc) and Utility.SetINIFloat (vanilla, Utility.psc), with
    ; the "name:Section" spelling the console's setini uses. The camera never
    ; moved because a setting that does not exist was being written.
    Float prev = Utility.GetINIFloat("fVanityModeMinDist:Camera")
    If prev <= 0.0
        prev = 155.0    ; the shipped value, if the setting read as nothing
    EndIf
    ; THE FILE FIRST, AND ONLY THEN THE SETTING. If the write fails there is
    ; nothing that remembers the old value, and a raised minimum with no
    ; record would outlive every save in the process.
    If !MiscUtil.WriteToFile(CamFile(), "" + prev, false, false)
        Debug.Trace("[FleshCore] death camera: could not write " + CamFile() + " -- not raised")
        Return
    EndIf
    Float want = DeathCamMinDist
    Float top = Utility.GetINIFloat("fVanityModeMaxDist:Camera")
    If top > 0.0 && want > top
        want = top      ; never a minimum above the maximum
    EndIf
    deathCamAt = Utility.GetCurrentRealTime()
    Utility.SetINIFloat("fVanityModeMinDist:Camera", want)
    ; NO ForceThirdPerson. The engine's own death handling puts a
    ; dying player in third person; forcing it a moment before the kill
    ; bought nothing, and the one launch that ran it was
    ; followed by a camera that would not enter third person again. Whether
    ; the two are connected is unknown; the call was redundant either way.
    ; Whether the engine re-clamps a camera that is ALREADY in third person to
    ; a changed minimum is unknown, and so is whether the DEATH camera state --
    ; the one they are in a moment after this -- is bounded by these two
    ; settings at all, rather than only the ordinary third-person state.

    Debug.Trace("[FleshCore] death camera: fVanityModeMinDist:Camera " + prev + " -> " + want)
EndFunction

Function DeathCamBack(Bool abForce)
    {Restore the minimum distance the file remembers -- when they are alive
     again and the hold has passed, or unconditionally on a load.}
    Float prev = MiscUtil.ReadFromFile(CamFile()) as Float
    If prev <= 0.0
        Return          ; not raised, or already put back
    EndIf
    If !abForce
        If Utility.GetCurrentRealTime() - deathCamAt < 6.0
            Return
        EndIf
        Actor p = Game.GetPlayer()
        If p && p.IsDead()
            Return
        EndIf
    EndIf
    ; VALIDATED: a file anyone can edit, and 0.0 is what a bad string casts
    ; to -- a minimum of 0 is a broken camera for the session.
    Float top = Utility.GetINIFloat("fVanityModeMaxDist:Camera")
    If prev < 1.0 || (top > 0.0 && prev > top)
        prev = 155.0
    EndIf
    MiscUtil.WriteToFile(CamFile(), "0", false, false)
    Utility.SetINIFloat("fVanityModeMinDist:Camera", prev)
    Debug.Trace("[FleshCore] death camera: fVanityModeMinDist:Camera back to " + prev)
EndFunction

Function OnPaSoTrapFollower(String eventName, String strArg, Float numArg, Form sender)
    {Automatically restore FleshCore wounds/head-fills on the player whenever an external
     aftermath mod fires this mod event, even on an untouched that mod install.}
    Actor p = Game.GetPlayer()
    If !p
        Return
    EndIf
    FL_Api.Restore(p)
    FL_Api.SetNoKill(p, false)
    Utility.Wait(1.6)
    FL_Api.Restore(p)
    FL_Api.SetNoKill(p, false)
EndFunction

Function VoiceMouthPass()
    Actor spk = StorageUtil.GetFormValue(None, "FL_LastVoiceSpeaker") as Actor
    If !spk
        Return
    EndIf
    Float until = StorageUtil.GetFloatValue(None, "FL_LastVoiceUntil", 0.0)
    Float now = Utility.GetCurrentRealTime()
    If spk.IsDead() || now >= until
        If spk.IsDead()
            MiscUtil.WriteToFile("Data/SKSE/Plugins/FleshCore.voice.txt", "STOP|0", false, false)
        EndIf
        If spk.Is3DLoaded()
            spk.SetExpressionPhoneme(0, 0)
            spk.SetExpressionPhoneme(1, 0)
            spk.SetExpressionPhoneme(5, 0)
        EndIf
        StorageUtil.UnsetFormValue(None, "FL_LastVoiceSpeaker")
        Return
    EndIf
    If spk.Is3DLoaded()
        Int ph = (beats / 5) % 4
        If ph == 0
            spk.SetExpressionPhoneme(0, 60)
            spk.SetExpressionPhoneme(1, 15)
            spk.SetExpressionPhoneme(5, 25)
        ElseIf ph == 1
            spk.SetExpressionPhoneme(0, 30)
            spk.SetExpressionPhoneme(1, 50)
            spk.SetExpressionPhoneme(5, 15)
        ElseIf ph == 2
            spk.SetExpressionPhoneme(0, 75)
            spk.SetExpressionPhoneme(1, 20)
            spk.SetExpressionPhoneme(5, 35)
        Else
            spk.SetExpressionPhoneme(0, 20)
            spk.SetExpressionPhoneme(1, 35)
            spk.SetExpressionPhoneme(5, 10)
        EndIf
    EndIf
EndFunction
