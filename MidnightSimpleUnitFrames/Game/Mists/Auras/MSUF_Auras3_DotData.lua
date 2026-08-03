--- Mists Classic target DoT aura IDs.
--- Baseline: WeakAuras Mists templates and ElvUI Mists filters, 2026-08-02.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then A3 = {}; MSUF.MSUF_Auras3 = A3 end

A3.TargetDotDataVersion = "Mists-5.5.4.68806"
A3.TargetDotData = {
    DEATHKNIGHT = {
        { 55078, "Blood Plague" }, { 55095, "Frost Fever" },
        { 114866, "Soul Reaper" },
    },
    DRUID = {
        { 1079, "Rip" }, { 1822, "Rake" }, { 8921, "Moonfire" },
        { 9007, "Pounce Bleed" }, { 33745, "Lacerate" },
        { 77758, "Thrash" }, { 93402, "Sunfire" },
    },
    HUNTER = {
        { 3674, "Black Arrow" }, { 53301, "Explosive Shot" },
        { 118253, "Serpent Sting" }, { 120699, "Lynx Rush" },
        { 120761, "Glaive Toss" }, { 131894, "A Murder of Crows" },
    },
    MAGE = {
        { 12654, "Ignite" }, { 11366, "Pyroblast" },
        { 44457, "Living Bomb" }, { 83853, "Combustion" },
        { 112948, "Frost Bomb" }, { 114923, "Nether Tempest" },
        { 413841, "Ignite" },
    },
    MONK = {
        { 122470, "Touch of Karma" }, { 123725, "Breath of Fire" },
    },
    PALADIN = {
        { 31803, "Censure" }, { 114916, "Execution Sentence" },
        { 114919, "Arcing Light" },
    },
    PRIEST = {
        { 589, "Shadow Word: Pain" }, { 2944, "Devouring Plague" },
        { 14914, "Holy Fire" }, { 34914, "Vampiric Touch" },
    },
    ROGUE = {
        { 703, "Garrote" }, { 1943, "Rupture" },
        { 2818, "Deadly Poison" }, { 89775, "Hemorrhage" },
        { 122233, "Crimson Tempest" },
    },
    SHAMAN = {
        { 8050, "Flame Shock" },
    },
    WARLOCK = {
        { 172, "Corruption" }, { 348, "Immolate" }, { 980, "Agony" },
        { 27243, "Seed of Corruption" }, { 30108, "Unstable Affliction" },
        { 47960, "Shadowflame" }, { 48181, "Haunt" },
        { 146739, "Corruption" },
    },
    WARRIOR = {
        { 113344, "Bloodbath" }, { 115767, "Deep Wounds" },
    },
}
