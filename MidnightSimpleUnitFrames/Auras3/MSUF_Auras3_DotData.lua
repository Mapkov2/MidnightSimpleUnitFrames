--- Auras3/MSUF_Auras3_DotData.lua
--- Curated player DoT aura IDs for the target-only unit-frame container.
---
--- Data baseline:
---   Retail 12.0.7.68453 (2026-07-18 hotfix data)
---   PTR    12.1.0.68745 (2026-07-16 hotfix data)
--- Aura IDs were cross-checked against Blizzard CDN spell data via the
--- SimulationCraft SpellDataDump generator. Channels and non-damaging marks
--- are intentionally excluded; this list contains target-visible periodic
--- damage auras only.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

A3.TargetDotDataVersion = "12.0.7.68453+12.1.0.68745"
A3.TargetDotData = {
    DEATHKNIGHT = {
        { 55078, "Blood Plague" }, { 55095, "Frost Fever" },
        { 191587, "Virulent Plague" }, { 343294, "Soul Reaper" },
        { 444633, "Undeath" }, { 1240996, "Dread Plague" },
        { 1241786, "Infected Claws" },
    },
    DEMONHUNTER = {
        { 204598, "Sigil of Flame" }, { 207407, "Soul Carver" },
        { 207771, "Fiery Brand" }, { 345335, "The Hunt" },
        { 390181, "Soulscar" }, { 391191, "Burning Wound" },
        { 462030, "Sigil of Doom" }, { 1256667, "Catastrophe" },
    },
    DRUID = {
        { 1079, "Rip" }, { 155625, "Moonfire" }, { 155722, "Rake" },
        { 164812, "Moonfire" }, { 164815, "Sunfire" },
        { 192090, "Thrash" }, { 202347, "Stellar Flare" },
        { 274838, "Feral Frenzy" }, { 325733, "Adaptive Swarm" },
        { 439531, "Bloodseeker Vines" }, { 1244079, "Frantic Frenzy" },
        { 1263250, "Astral Smolder" }, { 1270292, "Lunar Beam" },
    },
    EVOKER = {
        { 353759, "Deep Breath" }, { 357209, "Fire Breath" },
        { 361500, "Living Flame" }, { 409776, "Obsidian Shards" },
        { 441172, "Melt Armor" }, { 444017, "Enkindle" },
        { 456657, "Firestorm" },
    },
    HUNTER = {
        { 162487, "Steel Trap" }, { 212431, "Explosive Shot" },
        { 217200, "Barbed Shot" }, { 269576, "Master Marksman" },
        { 269747, "Wildfire Bomb" }, { 321538, "Bloodshed" },
        { 394371, "Hit the Mark" }, { 459560, "Laceration" },
        { 468572, "Black Arrow" }, { 1253171, "Wildfire Bomb" },
    },
    MAGE = {
        { 12654, "Ignite" }, { 114923, "Nether Tempest" },
        { 155158, "Meteor Burn" }, { 217694, "Living Bomb" },
        { 438671, "Living Bomb" }, { 449561, "Meteorite Burn" },
        { 468655, "Frostfire Bolt" }, { 1221389, "Freezing" },
    },
    MONK = {
        { 123725, "Breath of Fire" }, { 124280, "Touch of Karma" },
        { 450763, "Aspect of Harmony" }, { 1292919, "Coalescence" },
    },
    PALADIN = {
        { 273481, "Expurgation" }, { 383346, "Expurgation" },
        { 403695, "Truth's Wake" }, { 408399, "Heartfire" },
        { 423379, "Holy Reverberation" }, { 431380, "Dawnlight" },
        { 431414, "Sun Sear" }, { 447142, "Templar Slash" },
    },
    PRIEST = {
        { 589, "Shadow Word: Pain" }, { 14914, "Holy Fire" },
        { 34914, "Vampiric Touch" }, { 204213, "Purge the Wicked" },
        { 335467, "Devouring Plague" }, { 451740, "Purge the Wicked" },
        { 1280134, "Searing Light" },
    },
    ROGUE = {
        { 703, "Garrote" }, { 1943, "Rupture" },
        { 2818, "Deadly Poison" }, { 121411, "Crimson Tempest" },
        { 324073, "Serrated Bone Spike" }, { 360194, "Deathmark" },
        { 381628, "Internal Bleeding" }, { 385627, "Kingsbane" },
        { 409604, "Soulrip" }, { 424493, "Shadow Rupture" },
    },
    SHAMAN = {
        { 188389, "Flame Shock" }, { 305484, "Lightning Lasso" },
        { 427729, "Molten Slag" },
    },
    WARLOCK = {
        { 980, "Agony" }, { 27243, "Seed of Corruption" },
        { 146739, "Corruption" }, { 157736, "Immolate" },
        { 205179, "Phantom Singularity" }, { 316099, "Unstable Affliction" },
        { 325640, "Soul Rot" }, { 386931, "Vile Taint" },
        { 445474, "Wither" }, { 450538, "Soul Anathema" },
        { 460553, "Doom" }, { 1219045, "Unstable Affliction" },
    },
    WARRIOR = {
        { 205546, "Odyn's Fury" }, { 215537, "Trauma" },
        { 262115, "Deep Wounds" }, { 384318, "Thunderous Roar" },
        { 385060, "Odyn's Fury" }, { 388539, "Rend" },
        { 426284, "Finishing Wound" }, { 1300690, "Bloody Rebuke" },
    },
}
