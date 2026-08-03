--- Mists Classic player defensive aura IDs.
--- Baseline: ElvUI Mists TurtleBuffs plus WeakAuras Mists player buffs, 2026-08-02.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then A3 = {}; MSUF.MSUF_Auras3 = A3 end

A3.PlayerDefensiveDataVersion = "Mists-5.5.4.68806"
A3.PlayerDefensiveData = {
    DEATHKNIGHT = {
        { 48707, "Anti-Magic Shell" }, { 48792, "Icebound Fortitude" },
        { 49039, "Lichborne" }, { 50461, "Anti-Magic Zone" },
        { 55233, "Vampiric Blood" }, { 81256, "Dancing Rune Weapon" },
    },
    DRUID = {
        { 22812, "Barkskin" }, { 22842, "Frenzied Regeneration" },
        { 61336, "Survival Instincts" }, { 102342, "Ironbark" },
    },
    HUNTER = {
        { 19263, "Deterrence" }, { 53480, "Roar of Sacrifice" },
    },
    MAGE = {
        { 11426, "Ice Barrier" }, { 45438, "Ice Block" },
        { 110960, "Greater Invisibility" }, { 115610, "Temporal Shield" },
    },
    MONK = {
        { 115213, "Avert Harm" }, { 116849, "Life Cocoon" },
        { 120954, "Fortifying Brew" }, { 122278, "Dampen Harm" },
        { 122783, "Diffuse Magic" }, { 131523, "Zen Meditation" },
    },
    PALADIN = {
        { 498, "Divine Protection" }, { 642, "Divine Shield" },
        { 1022, "Hand of Protection" }, { 1038, "Hand of Salvation" },
        { 1044, "Hand of Freedom" }, { 6940, "Hand of Sacrifice" },
        { 31821, "Aura Mastery" }, { 31850, "Ardent Defender" },
        { 70940, "Divine Guardian" }, { 86659, "Guardian of Ancient Kings" },
        { 132403, "Shield of the Righteous" },
    },
    PRIEST = {
        { 17, "Power Word: Shield" }, { 33206, "Pain Suppression" },
        { 47585, "Dispersion" }, { 47753, "Divine Aegis" },
        { 47788, "Guardian Spirit" }, { 62618, "Power Word: Barrier" },
        { 114214, "Angelic Bulwark" },
    },
    ROGUE = {
        { 1966, "Feint" }, { 5277, "Evasion" },
        { 31224, "Cloak of Shadows" }, { 45182, "Cheating Death" },
        { 74001, "Combat Readiness" },
    },
    SHAMAN = {
        { 974, "Earth Shield" }, { 30823, "Shamanistic Rage" },
        { 98007, "Spirit Link Totem" }, { 108271, "Astral Shift" },
        { 114893, "Stone Bulwark" },
    },
    WARLOCK = {
        { 104773, "Unending Resolve" }, { 108359, "Dark Regeneration" },
        { 108366, "Soul Leech" }, { 108416, "Sacrificial Pact" },
        { 110913, "Dark Bargain" },
    },
    WARRIOR = {
        { 871, "Shield Wall" }, { 12975, "Last Stand" },
        { 23920, "Spell Reflection" }, { 55694, "Enraged Regeneration" },
        { 97463, "Rallying Cry" }, { 112048, "Shield Barrier" },
        { 114028, "Mass Spell Reflection" }, { 118038, "Die by the Sword" },
        { 132404, "Shield Block" },
    },
}
