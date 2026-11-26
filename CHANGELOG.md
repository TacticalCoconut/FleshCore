# Changelog

## v0.2.0 Beta

### New

- **Darker blood and flesh,** with the same colours. Compared with v0.1.1, cut flesh and fat are about 60% darker, and blood on skin about two thirds darker. Blood splats and blood coats use new, smaller splatter textures that are darker still.
- **The Grinder spells** (optional; they need [Leash Framework](https://www.nexusmods.com/skyrimspecialedition/mods/187303) 1.1.8):
  - **Spawn Grinder** puts a grinder with two spiked rollers in front of you. Activate its base to switch it on or off.
  - **Grinder Hook** chains the one you hit to the nearest grinder and pulls them into the rollers, where FleshCore grinds them. Someone the chain cannot hold, such as a creature, is dragged in by the hook's winch.
  - Turn both spells on or off in the MCM: **Controls**, **Grinder Spells**. **Rollers grind bystanders** (off by default) lets the rollers take anyone else who touches them.
  - Without Leash Framework the spells are not added, the MCM row says "Requires Leash Framework", and the rest of FleshCore works as before. `FleshCore.esp` does not need Leash Framework to load.
- **Khajiit and Argonian heads** no longer get a human skull inside when they are cut.
- **Ambush enemies** that the game creates during play (playable races) can be cut too.
- **Swing angles.** A cut follows the direction of the swing more closely, and spells cast in third person aim where you look.
- **Bone-crack sound** and a short hit-stop when a bone breaks or a part comes off.
- **Leg wounds slow them down,** in steps. Losing a leg no longer counts as losing the abdomen, and losing two limbs no longer counts as losing the chest.
- **Blood washes off in water.**
- **The HQ:** a Blood Splatter switch and slider, a Fodder Overkill slider, and the sliders that did nothing before now work. Lethality keeps skin at or above flesh, and flesh at or above bone.
- **For modders:** instant body-status checks (`HasBody`, `IsDismembered`, `GetPartIntegrityPct` and more, see FleshCore-API.md), commands and events sent in memory instead of through files, and a way to raise the Fodder Overkill chance for a while (the `FC_OverkillBonusSet` mod event or `FL_Native.SetOverkillBonusPct`).

### Fixed

- Pieces from a body whose mesh was swapped while it was being read (for example by a body-shape change) no longer come out as long stretched triangles.
- Casting Restore no longer resets the look of people who are standing; only those who are down are cleaned up.
- Blood bursts mark people who are lying down.
- A dropped piece no longer shows the look of an earlier piece: there are 64 pieces in the pool instead of 20.
- Skin shows under torn clothes, helmets survive a cut, and weapons, shields and quivers worn on the back are no longer cut.
- Outfits are dressed with flesh evenly, and outfits that share slots no longer starve each other.
- Wounds are saved and loaded more safely, and survive a change of cell size.
- Wounds are worked out faster, and a body only comes apart where its parts really touch.
- Mod folders and files with non-English names are found.
- After an update, FleshCore no longer uses the list of loose files the old version saved (`SKSE/Plugins/FleshCore.loose_manifest.bin`), which could hide the new version's files; it builds a new list.
- The MCM's preset texts say what each level does; the lethality text was wrong from 65 to 84. The rows are now named Gore Damage and Lethality.
- Voice lines play on time right after a load, and no old voice line plays at start-up.
- The background work pauses during a load screen and while the game shuts down.
- Files that SkyrimNet add-ons write during play are found.
- Children are never cut, also when only their voice type says they are children.
- Fewer repeated lines in the log.

## v0.1.1 Beta

- Unused functions have been removed.
- Fixed pieces sometimes coming out black.
- Pieces are closer to the body's colour.
- Fixed the HQ not showing saved switches and sliders.
- Bisect cuts a body in two: the half that falls away drops as one piece.
- Fixed some worn gear, such as helmets, being cut and dropped far from where it is worn.
- A severed head keeps the target's face.
- A severed head keeps their face's own colouring and detail.
- Hair, brows and beards in a severed head keep their colour, soft edges and shading.
- Horns, frills and brows on a severed Argonian or Orc head keep their own colour.
- Hair that was drawn twice in a severed head is drawn once.
- Hair, eyes and brows in a severed piece no longer get a flesh lining.
- Pieces drop with their skin drawn by the game's skin shader.

## v0.1 Beta

First public release.
