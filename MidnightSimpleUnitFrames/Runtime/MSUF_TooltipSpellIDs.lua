--- Persists the native "spell IDs in aura tooltips" client option across
--- sessions. WoW 12.1 ships this as the tooltipShowAuraSpellIDs CVar, but the
--- client deliberately resets it to 0 on every login.
---
--- Gated by Global > Misc "Show spell IDs in aura tooltips"
--- (general.tooltipShowAuraSpellIDs, default off). The login pass only ever
--- writes "1" while the MSUF toggle is on: with the toggle off, MSUF never
--- touches the CVar, so another addon or a manual /console setting keeps
--- ownership. Only an explicit user action on the toggle writes "0".
---
--- Cost profile: one PLAYER_LOGIN handler that drops both its event and its
--- script after the first dispatch, at most one SetCVar per login. Nothing
--- polls, and no protected or layout write is involved.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local _G = _G
local type = type

local CVAR_NAME = "tooltipShowAuraSpellIDs"

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function IsEnabled()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general
    if type(general) ~= "table" then return false end
    return general.tooltipShowAuraSpellIDs == true
end

local function WriteCVar(enabled)
    local setCVar = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
    if type(setCVar) ~= "function" then return false end
    setCVar(CVAR_NAME, enabled and "1" or "0")
    return true
end

--- Explicit user action (menu toggle, Assistant): writes the CVar in both
--- directions. `value` falls back to the saved setting when omitted.
local function ApplySetting(value)
    if value == nil then value = IsEnabled() end
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
    end)
end

MSUF.TooltipSpellIDs = {
    IsEnabled = IsEnabled,
    Apply = ApplySetting,
}

ExportPublic("MSUF_ApplyTooltipSpellIDs", ApplySetting)
