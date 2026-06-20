-- Assistant UnitFrame anchoring value tables.
-- Loaded after MSUF_AssistantRegistry_Unitframes_Data.lua so the shared data table exists.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.UnitframeRegistryData or {}
A.UnitframeRegistryData = Data

Data.ANCHOR_TARGET_VALUES = {
    "GLOBAL", "EssentialCooldownViewer", "UtilityCooldownViewer",
    "BuffIconCooldownViewer", "player", "target", "targettarget",
    "focustarget", "focus", "pet",
}
Data.ANCHOR_TARGET_TERMS = {
    GLOBAL = { "global", "global anchor", "default" },
    EssentialCooldownViewer = {
        "essential cooldown viewer", "essential cooldown manager",
        "essential cooldownmanager", "essential cooldowns",
        "cooldown manager", "cooldownmanager", "cooldowns manager", "cdm", "ecv",
    },
    UtilityCooldownViewer = {
        "utility cooldown viewer", "utility cooldown manager",
        "utility cooldownmanager", "utility cooldowns", "ucv",
    },
    BuffIconCooldownViewer = {
        "tracked buffs viewer", "tracked buff viewer",
        "buff icon cooldown viewer", "tracked buffs", "tracked buffs manager",
    },
    targettarget = { "targettarget", "target of target", "tot" },
    focustarget = { "focustarget", "focus target" },
}
Data.ANCHOR_TARGET_ALIAS_BASE = {
    global = "GLOBAL",
    default = "GLOBAL",
    ["global anchor"] = "GLOBAL",
    ["essential cooldown viewer"] = "EssentialCooldownViewer",
    ["essential cooldown manager"] = "EssentialCooldownViewer",
    ["essential cooldownmanager"] = "EssentialCooldownViewer",
    ["essential cooldowns"] = "EssentialCooldownViewer",
    ["cooldown manager"] = "EssentialCooldownViewer",
    cooldownmanager = "EssentialCooldownViewer",
    ["cooldowns manager"] = "EssentialCooldownViewer",
    cdm = "EssentialCooldownViewer",
    ecv = "EssentialCooldownViewer",
    ["utility cooldown viewer"] = "UtilityCooldownViewer",
    ["utility cooldown manager"] = "UtilityCooldownViewer",
    ["utility cooldownmanager"] = "UtilityCooldownViewer",
    ["utility cooldowns"] = "UtilityCooldownViewer",
    ucv = "UtilityCooldownViewer",
    ["tracked buffs viewer"] = "BuffIconCooldownViewer",
    ["tracked buff viewer"] = "BuffIconCooldownViewer",
    ["buff icon cooldown viewer"] = "BuffIconCooldownViewer",
    ["tracked buffs"] = "BuffIconCooldownViewer",
    ["tracked buffs manager"] = "BuffIconCooldownViewer",
    player = "player",
    target = "target",
    targettarget = "targettarget",
    ["target of target"] = "targettarget",
    tot = "targettarget",
    focustarget = "focustarget",
    ["focus target"] = "focustarget",
    focus = "focus",
    pet = "pet",
}
Data.ANCHOR_POINT_VALUES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
