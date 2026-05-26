local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local C_AddOns = C_AddOns
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local type = type

local BCDM_TYPES = {
    "Utility",
    "CustomViewer",
    "Custom",
    "AdditionalCustom",
    "Item",
    "ItemSpell",
    "Trinket",
    "Power",
    "SecondaryPower",
    "CastBar",
    "Buffs",
    "BuffBar",
}

local BCDM_ANCHORS = {
    MSUF_player = "|cFFFFD700Midnight|rSimpleUnitFrames: Player Frame",
    MSUF_target = "|cFFFFD700Midnight|rSimpleUnitFrames: Target Frame",
    MSUF_focus = "|cFFFFD700Midnight|rSimpleUnitFrames: Focus Frame",
    MSUF_pet = "|cFFFFD700Midnight|rSimpleUnitFrames: Pet Frame",
    MSUF_targettarget = "|cFFFFD700Midnight|rSimpleUnitFrames: Target of Target Frame",
    MSUF_focustarget = "|cFFFFD700Midnight|rSimpleUnitFrames: Focus Target Frame",
    MSUF_boss1 = "|cFFFFD700Midnight|rSimpleUnitFrames: Boss 1 Frame",
    MSUF_boss2 = "|cFFFFD700Midnight|rSimpleUnitFrames: Boss 2 Frame",
    MSUF_boss3 = "|cFFFFD700Midnight|rSimpleUnitFrames: Boss 3 Frame",
    MSUF_boss4 = "|cFFFFD700Midnight|rSimpleUnitFrames: Boss 4 Frame",
    MSUF_boss5 = "|cFFFFD700Midnight|rSimpleUnitFrames: Boss 5 Frame",
}

local registered

local function ApplyUnitFrameAnchors()
    local UF = MSUF.UF
    local factory = UF and UF.Factory
    if not (UF and UF.spawned and factory and type(factory.Apply) == "function") then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        local order = UF.unitOrder
        for i = 1, order and #order or 0 do
            UF.pendingApply[order[i]] = true
        end
        if type(factory.EnsureDeferredDriver) == "function" then
            factory.EnsureDeferredDriver()
        end
        return
    end
    factory.Apply()
end

local function RegisterBCDMAnchors(applyAnchors)
    if registered then
        if applyAnchors then
            ApplyUnitFrameAnchors()
        end
        return true
    end
    if not (_G.MSUF_player or _G.MSUF_target) then
        return false
    end
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BetterCooldownManager")) then
        return false
    end

    local api = _G.BCDMG
    if not (api and type(api.AddAnchors) == "function") then
        return false
    end

    api:AddAnchors("MidnightSimpleUnitFrames", BCDM_TYPES, BCDM_ANCHORS)
    registered = true
    if applyAnchors then
        ApplyUnitFrameAnchors()
    end
    return true
end

MSUF.RegisterThirdPartyAnchors = RegisterBCDMAnchors

local watcher = CreateFrame and CreateFrame("Frame")
if watcher then
    watcher:RegisterEvent("PLAYER_LOGIN")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(self, event, addon)
        if event == "ADDON_LOADED" and addon ~= "BetterCooldownManager" then
            return
        end
        if RegisterBCDMAnchors(event == "ADDON_LOADED") then
            self:UnregisterEvent("PLAYER_LOGIN")
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
        end
    end)
end
