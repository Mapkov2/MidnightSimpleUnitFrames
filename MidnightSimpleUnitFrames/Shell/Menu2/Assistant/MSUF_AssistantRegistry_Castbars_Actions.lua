-- Assistant Castbar preview and reset actions.
-- Loaded after MSUF_AssistantRegistry_Castbars.lua; keeps action metadata outside setting helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local C = A.RegistryCore
if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(C) ~= "table" then return end

local UNIT_LABELS = C.UNIT_LABELS or {}
local GeneralDB = C.GeneralDB
local CallGlobal = C.CallGlobal
local ApplyCastbar = C.ApplyCastbar

if type(GeneralDB) ~= "function" or type(CallGlobal) ~= "function" or type(ApplyCastbar) ~= "function" then return end

local CASTBAR_PREVIEW_UNITS = { player = true, target = true, focus = true, boss = true }
local CASTBAR_PREVIEW_TYPES = { normal = true, channel = true, empowered = true }

local function NormalizeCastbarPreviewUnit(unit)
    unit = tostring(unit or ""):lower()
    if unit == "boss1" or unit == "bosses" then unit = "boss" end
    return CASTBAR_PREVIEW_UNITS[unit] and unit or "player"
end

local function NormalizeCastbarPreviewType(kind)
    kind = tostring(kind or ""):lower()
    if kind == "channeled" or kind == "channelled" then kind = "channel" end
    if kind == "empower" then kind = "empowered" end
    return CASTBAR_PREVIEW_TYPES[kind] and kind or "normal"
end

local function OpenCastbarPage()
    if M and type(M.Open) == "function" then
        return M.Open("opt_castbar") ~= false
    end
    if M and type(M.SelectPage) == "function" then
        return M.SelectPage("opt_castbar") ~= false
    end
    return false
end

local function UnitLabel(unit)
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    local label = UNIT_LABELS[unit]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    return tostring(unit or "Unit Frame")
end

Registry:RegisterAction({
    key = "preview_castbar",
    label = "Preview Cast Bar",
    type = "preview",
    category = "Appearance / Cast Bars",
    aliases = {
        "preview castbar", "castbar preview", "show castbar preview", "castbar vorschau", "zauberleiste vorschau",
        "preview player castbar", "preview target castbar", "preview focus castbar", "preview boss castbar",
        "spieler zauberleiste vorschau", "ziel zauberleiste vorschau", "fokus zauberleiste vorschau", "boss zauberleiste vorschau",
        "preview channel castbar", "preview empowered castbar", "preview castbar interrupt",
        "kanalisierte zauberleiste vorschau", "empowered zauberleiste vorschau", "unterbrochene zauberleiste vorschau",
    },
    combatSafe = true,
    run = function(args)
        args = type(args) == "table" and args or {}
        local unit = NormalizeCastbarPreviewUnit(args.unit)
        local kind = NormalizeCastbarPreviewType(args.kind or args.castType)
        M._msuf2CastbarPreviewUnit = unit
        M._msuf2CastbarPreviewType = kind
        if M and type(M.SetCastbarPreviewUnit) == "function" then M.SetCastbarPreviewUnit(unit) end
        if M and type(M.SetCastbarPreviewType) == "function" then M.SetCastbarPreviewType(kind) end
        if args.interrupt then
            if M and type(M.PlayCastbarPreviewInterrupt) == "function" then
                M.PlayCastbarPreviewInterrupt()
            elseif M then
                M._msuf2CastbarPreviewInterruptPending = true
            end
        end
        local opened = OpenCastbarPage()
        local unitLabel = UnitLabel(unit)
        local typeLabel = kind == "channel" and "channel" or (kind == "empowered" and "empowered" or "normal")
        local suffix = args.interrupt and " with interrupt feedback" or ""
        return true, (opened and "Opened" or "Prepared") .. " " .. tostring(unitLabel) .. " " .. typeLabel .. " castbar preview" .. suffix .. "."
    end,
})

Registry:RegisterAction({
    key = "reset_focus_kick_position",
    label = "Reset Focus Kick Position",
    type = "reset",
    category = "Appearance / Cast Bars",
    aliases = {
        "reset focus kick position",
        "reset focus interrupt tracker position",
        "focus kick reset position",
        "focus kick position zuruecksetzen",
        "fokus kick position zuruecksetzen",
        "fokus interrupt tracker position zuruecksetzen",
        "fokus kick anzeige zuruecksetzen",
    },
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.focusKickIconOffsetX = 300
        g.focusKickIconOffsetY = 0
        CallGlobal("MSUF_UpdateFocusKickIconOptions")
        ApplyCastbar("MSUF2_FOCUS_KICK_RESET")
        return true, "Done. Reset Focus Kick position."
    end,
})
