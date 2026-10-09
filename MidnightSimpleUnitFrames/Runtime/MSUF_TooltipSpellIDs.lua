--- Persists the native "spell IDs in aura tooltips" client option across
--- sessions. WoW 12.1 ships this as the tooltipShowAuraSpellIDs CVar, but the
--- client deliberately resets it to 0 on every login.
---
--- Gated by Global > Misc "Show spell IDs in aura tooltips"
--- (general.tooltipShowAuraSpellIDs, default off). The login pass only ever
--- writes "1" while the MSUF toggle is on: with the toggle off, MSUF never
--- touches the CVar, so another addon or a manual /console setting keeps
--- ownership. Only an explicit user action on the toggle writes "0". A
--- profile switch (Apply without a value) writes "1" for a profile with the
--- toggle on and "0" only when MSUF itself turned the option on this session.
---
--- Cost profile: one PLAYER_LOGIN handler that drops both its event and its
--- script after the first dispatch, at most two SetCVar calls per login. Nothing
--- polls, and no protected or layout write is involved.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local _G = _G
local type = type

local CVAR_NAME = "tooltipShowAuraSpellIDs"

local ExportPublic = MSUF.ExportPublic

--- True while the current CVar value "1" was written by MSUF this session (the
--- client resets the option at login). Session state, never a CVar.
local spellIDsOwned, casterNamesOwned = false, false

local function IsEnabled()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general
    if type(general) ~= "table" then return false end
    return general.tooltipShowAuraSpellIDs == true
end

local function WriteCVar(enabled)
    local setCVar = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
    if type(setCVar) ~= "function" then return false end
    local getCVar = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
    if type(getCVar) == "function" and getCVar(CVAR_NAME) == nil then return false end
    setCVar(CVAR_NAME, enabled and "1" or "0")
    spellIDsOwned = enabled == true
    return true
end

--- Explicit user action (menu toggle): writes the CVar in both directions.
--- Without a value (profile switch) it follows the active profile's toggle:
--- "1" when on, "0" only when MSUF itself turned the option on.
local function ApplySetting(value)
    if value == nil then
        if IsEnabled() then return WriteCVar(true) end
        return spellIDsOwned and WriteCVar(false)
    end
    return WriteCVar(value == true)
end

if type(_G.CreateFrame) == "function" then
    local loginFrame = _G.CreateFrame("Frame")
    loginFrame:RegisterEvent("PLAYER_LOGIN")
    loginFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        self:SetScript("OnEvent", nil)
        --- Re-apply only the ON state. Never write "0" here: an off MSUF
        --- toggle must not disable spell IDs the user enabled elsewhere.
        if IsEnabled() then WriteCVar(true) end
        local applyCasterNames = _G.MSUF_ApplyTooltipCasterNames
        if type(applyCasterNames) == "function" and MSUF.TooltipSpellIDs
            and MSUF.TooltipSpellIDs.IsCasterNamesEnabled() then
            applyCasterNames(true)
        end
    end)
end

--- 12.1.5 adds the same shape for aura caster names: tooltipShowAuraCasterNames
--- colorises the caster by reaction or class in aura tooltips. Same ownership
--- rule as above - the login pass only ever writes "1", so an off MSUF toggle
--- never takes the option away from another addon or a manual /console setting.
--- Only an explicit user action writes "0". On Classic-era clients this file is
--- not in the TOC at all, so both toggles stay no-ops there.
local CASTER_CVAR_NAME = "tooltipShowAuraCasterNames"

local function IsCasterNamesEnabled()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general
    if type(general) ~= "table" then return false end
    return general.tooltipShowAuraCasterNames == true
end

local function WriteCasterCVar(enabled)
    local setCVar = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
    if type(setCVar) ~= "function" then return false end
    local getCVar = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
    if type(getCVar) == "function" and getCVar(CASTER_CVAR_NAME) == nil then return false end
    setCVar(CASTER_CVAR_NAME, enabled and "1" or "0")
    casterNamesOwned = enabled == true
    return true
end

local function ApplyCasterNamesSetting(value)
    if value == nil then
        if IsCasterNamesEnabled() then return WriteCasterCVar(true) end
        return casterNamesOwned and WriteCasterCVar(false)
    end
    return WriteCasterCVar(value == true)
end

MSUF.TooltipSpellIDs = {
    IsEnabled = IsEnabled,
    Apply = ApplySetting,
    IsCasterNamesEnabled = IsCasterNamesEnabled,
    ApplyCasterNames = ApplyCasterNamesSetting,
}

ExportPublic("MSUF_ApplyTooltipSpellIDs", ApplySetting)
ExportPublic("MSUF_ApplyTooltipCasterNames", ApplyCasterNamesSetting)
