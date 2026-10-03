-- castbar_preview_native_conceal_smoke.lua <repoRoot>
--
-- Blizzard's PlayerCastingBarFrame is a managed frame on every client (mirror:
-- BottomManagedFrameTemplate on Mainline and Forever, UIParentBottomManaged-
-- FrameTemplate on the Classic clients). Its OnHide removes it from the bottom
-- managed-frame container and lays the container out, which also places
-- ExtraAbilityContainer; a Hide() from addon code runs that layout tainted.
-- The castbar re-anchor pass (CastbarAnchors ReanchorPlayerCastBarBase) calls
-- MSUF_HideBlizzardPlayerCastbar (CastbarPreviews) whenever MSUF owns the
-- player castbar, and it hid the bar (red without the fix). It now conceals a
-- shown managed bar through the Bridge's owner (alpha 0, no mouse), and the
-- Bridge's release gives the alpha back.
--
-- Pinned with the real castbar stack (tools/tests/castbar_world.lua), Bridge
-- and previews loaded in TOC order:
--   1. a hidden bar: events released, no Hide/Show, nothing else written;
--   2. a shown managed bar (Blizzard Edit Mode, a cast in flight): concealed,
--      never hidden;
--   3. Blizzard owning the player castbar again: the alpha and mouse come back.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local EXTRA = {
    "MSUF_Require.lua", "MSUF_Castbars_Core.lua", "MSUF_CastbarStyle.lua", "MSUF_CastbarFrames.lua",
    "MSUF_Castbars_Backend.lua", "MSUF_Castbars_Bridge.lua",
    "MSUF_CastbarAnchors.lua", "MSUF_PlayerCastbarRuntime.lua", "MSUF_CastbarPreviewEdit.lua",
    "MSUF_CastbarPreviews.lua", "MSUF_CastbarVisuals.lua", "MSUF_InterruptReady.lua",
    "MSUF_CastbarRounded.lua", "MSUF_CastbarVisualCompat.lua",
}

local function Setup(ns)
    ns.UF = { frames = {}, GetFrame = function() return nil end }
    ns.RoundedSurface = {
        ClearMasks = function() end, BeginMaskRefresh = function() end,
        EndMaskRefresh = function() end, MaskTextureWith = function() end,
    }
    _G.MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    _G.MSUF_SetFontChecked = function(fs, path, size, flags) fs:SetFont(path, size, flags) return true end
    _G.MSUF_GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end
    _G.MSUF_GetFontFlags = function() return "OUTLINE" end
    _G.MSUF_IsPlayerInCombat = function() return false end
    _G.MSUF_SetTextIfChanged = function(fontString, text) fontString:SetText(text) end
    _G.MSUF_SetCastTimeText = function() end
    _G.MSUF_GetCastbarTimeFormat = function() return "CURRENT" end
    _G.MSUF_FormatCastbarTimeText = function(_, remaining) return string.format("%.1f", tonumber(remaining) or 0) end
    _G.MSUF_EnsureDB = function() end
    _G.MSUF_MarkFontApplyFailed = function() end
    _G.MSUF_GetCastbarTextColor = function() return 1, 1, 1 end
    _G.MSUF_GetConfiguredFontColor = function() return 1, 1, 1 end
    _G.MSUF_GetCastbarBackgroundColor = function() return 0.176, 0.176, 0.176, 1 end
    _G.MSUF_NormalizeFontPath = function(path) return path end
    _G.MSUF_GetInternalFontPathByKey = function() return nil end
    _G.MSUF_UpdateCastbarEditInfo = function() end
    _G.MSUF_SyncCastbarPositionPopup = function() end
    _G.MSUF_EnsureCooldownWidthObservers = function() end
end

local world = World.New(root, "timer", { extra = EXTRA, setup = Setup, richWidgets = true })
Check(world.loaded["MSUF_Castbars_Bridge.lua"] and world.loaded["MSUF_CastbarPreviews.lua"], "harness: castbar files missing")
local general = _G.MSUF_DB.general

-- Blizzard's bar: every call MSUF makes is logged; Hide/Show/SetShown on a
-- shown managed bar is the tainted container layout.
local calls = {}
local bar = { name = "PlayerCastingBarFrame", isManagedFrame = true, shown = false, alpha = 1, mouse = false,
    events = { UNIT_SPELLCAST_START = true }, unit = "player", showTradeSkills = true, showShield = false }
local function Log(method) calls[#calls + 1] = method end
function bar:IsShown() return self.shown end
function bar:Show() Log("Show"); self.shown = true end
function bar:Hide()
    Log("Hide")
    Check(not self.shown, "MSUF hid the shown managed PlayerCastingBarFrame (tainted container layout)")
end
function bar:SetShown() Log("SetShown"); error("MSUF called SetShown on PlayerCastingBarFrame") end
function bar:GetAlpha() return self.alpha end
function bar:SetAlpha(alpha) Log("SetAlpha"); self.alpha = alpha end
function bar:IsMouseEnabled() return self.mouse end
function bar:EnableMouse(enabled) Log("EnableMouse"); self.mouse = enabled == true end
function bar:UnregisterAllEvents() Log("UnregisterAllEvents"); self.events = {} end
function bar:HookScript(script, fn) Log("HookScript"); if script == "OnShow" then self.onShow = fn end end
function bar:SetUnit(unit)
    Log("SetUnit")
    if unit then self.events.UNIT_SPELLCAST_START = true end
end
_G.PlayerCastingBarFrame = bar
_G.CastingBarFrame = nil

local function Calls()
    return table.concat(calls, ",")
end

-- 1. A hidden bar: the previews release its events and write nothing else.
_G.MSUF_HideBlizzardPlayerCastbar()
Check(next(bar.events) == nil, "1: the previews kept the Blizzard castbar's cast events")
Check(Calls() == "UnregisterAllEvents", "1: unexpected calls on a hidden bar: " .. Calls())

-- 2. A shown managed bar (Blizzard Edit Mode, a cast in flight).
calls = {}
bar.shown, bar.alpha, bar.mouse = true, 0.7, true
bar.events.UNIT_SPELLCAST_START = true
_G.MSUF_HideBlizzardPlayerCastbar()
Check(bar.shown, "2: the shown managed bar was hidden")
Check(bar.alpha == 0 and bar.mouse == false and next(bar.events) == nil,
    "2: the shown managed bar was not concealed: alpha " .. tostring(bar.alpha) .. ", mouse " .. tostring(bar.mouse))
_G.MSUF_HideBlizzardPlayerCastbar()
Check(bar.alpha == 0, "2: a second pass changed the concealed bar")

-- 3. Blizzard owns the player castbar again: the Bridge gives the alpha back.
general.castbarPlayerBackend = "BLIZZARD"
_G.MSUF_ApplyBlizzardCastbarOwnership()
Check(bar.alpha == 0.7 and bar.mouse == true, "3: the release did not restore the concealed bar: alpha "
    .. tostring(bar.alpha) .. ", mouse " .. tostring(bar.mouse))
for _, method in ipairs(calls) do
    Check(method ~= "Hide" and method ~= "Show" and method ~= "SetShown", "3: MSUF called " .. method .. " on the bar")
end

print("castbar_preview_native_conceal_smoke: ok")
