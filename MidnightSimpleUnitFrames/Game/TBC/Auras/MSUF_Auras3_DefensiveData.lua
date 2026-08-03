--- TBC Classic player defensive aura IDs.
--- Baseline: WeakAuras TBC templates and ElvUI TBC defensive filters, 2026-08-02.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then A3 = {}; MSUF.MSUF_Auras3 = A3 end

A3.PlayerDefensiveDataVersion = "TBC-2.5.6.68941"
A3.PlayerDefensiveData = {
    DRUID = {
        { 22812, "Barkskin" }, { 22842, "Frenzied Regeneration" },
    },
    HUNTER = {
        { 19263, "Deterrence" },
    },
    MAGE = {
        { 1463, "Mana Shield" }, { 11426, "Ice Barrier" },
        { 11958, "Ice Block" }, { 27619, "Ice Block" },
        { 45438, "Ice Block" },
    },
    PALADIN = {
        { 498, "Divine Protection" }, { 5573, "Divine Protection" },
        { 642, "Divine Shield" }, { 1020, "Divine Shield" },
        { 1022, "Blessing of Protection" }, { 5599, "Blessing of Protection" },
        { 10278, "Blessing of Protection" }, { 1044, "Blessing of Freedom" },
        { 6940, "Blessing of Sacrifice" },
    },
    PRIEST = {
        { 17, "Power Word: Shield" }, { 33206, "Pain Suppression" },
    },
    ROGUE = {
        { 5277, "Evasion" }, { 31224, "Cloak of Shadows" },
    },
    SHAMAN = {
        { 974, "Earth Shield" }, { 30823, "Shamanistic Rage" },
    },
    WARLOCK = {
        { 7812, "Sacrifice" }, { 19028, "Soul Link" },
    },
    WARRIOR = {
        { 871, "Shield Wall" }, { 12975, "Last Stand" },
        { 20230, "Retaliation" }, { 23920, "Spell Reflection" },
    },
}
