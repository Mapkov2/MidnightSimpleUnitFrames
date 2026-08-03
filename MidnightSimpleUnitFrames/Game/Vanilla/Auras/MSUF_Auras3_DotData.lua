--- Classic Era target DoT aura IDs.
--- Baseline: ElvUI Classic filters and Blizzard upstream/classic_era, 2026-08-03.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then A3 = {}; MSUF.MSUF_Auras3 = A3 end

A3.TargetDotDataVersion = "Vanilla-1.15.9.68940"
A3.TargetDotData = {
    DRUID = {
        { 1079, "Rip" }, { 1822, "Rake" }, { 5570, "Insect Swarm" },
        { 8921, "Moonfire" }, { 9007, "Pounce Bleed" },
    },
    HUNTER = {
        { 1978, "Serpent Sting" }, { 3034, "Viper Sting" },
        { 3043, "Scorpid Sting" }, { 13797, "Immolation Trap" },
        { 19386, "Wyvern Sting" },
    },
    MAGE = {
        { 133, "Fireball" }, { 11366, "Pyroblast" }, { 12654, "Ignite" },
    },
    PRIEST = {
        { 589, "Shadow Word: Pain" }, { 2944, "Devouring Plague" },
        { 14914, "Holy Fire" },
    },
    ROGUE = {
        { 703, "Garrote" }, { 1943, "Rupture" }, { 2818, "Deadly Poison" },
    },
    SHAMAN = { { 8050, "Flame Shock" } },
    WARLOCK = {
        { 172, "Corruption" }, { 348, "Immolate" },
        { 603, "Curse of Doom" }, { 980, "Curse of Agony" },
        { 18265, "Siphon Life" },
    },
    WARRIOR = { { 772, "Rend" }, { 12721, "Deep Wounds" } },
}
