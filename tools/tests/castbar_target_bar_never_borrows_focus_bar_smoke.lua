-- castbar_target_bar_never_borrows_focus_bar_smoke.lua <repoRoot>
--
-- The target castbar functions in Castbars/MSUF_CastbarAnchors.lua act on the
-- target bar only. Without a target bar (its castbar is off or not built yet)
-- the target re-anchor and the effective-size pass used to resolve the focus
-- bar instead: the target pass hid it when the target castbar was off, and
-- sized it with the target settings. The focus bar must stay as it is.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()

local failures = 0
local function Check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL " .. message)
    end
end

local EXTRA = {
    "MSUF_Require.lua", "MSUF_Castbars_Core.lua", "MSUF_CastbarStyle.lua", "MSUF_CastbarFrames.lua",
    "MSUF_CastbarAnchors.lua", "MSUF_PlayerCastbarRuntime.lua", "MSUF_CastbarVisuals.lua",
}

local owned = {}
local function Setup(ns)
    ns.UF = { frames = {}, GetFrame = function() return nil end }
    _G.MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    _G.MSUF_SetFontChecked = function(fs, path, size, flags) fs:SetFont(path, size, flags) return true end
    _G.MSUF_GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end
    _G.MSUF_GetFontFlags = function() return "OUTLINE" end
    _G.MSUF_IsPlayerInCombat = function() return false end
    _G.MSUF_SetTextIfChanged = function(fontString, text) fontString:SetText(text) end
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
    _G.MSUF_ShouldUseMSUFCastbar = function(unit) return owned[unit] == true end
end

local world = World.New(root, "timer", { extra = EXTRA, setup = Setup, richWidgets = true })
local general = _G.MSUF_DB.general
general.castbarTargetWidth, general.castbarTargetHeight = 333, 21

-- Only the focus bar exists.
local focus = world:Driver("focus")
Check(_G.MSUF_FocusCastbar == focus and _G.MSUF_TargetCastbar == nil, "the fixture must build the focus bar only")
local sizeCalls = 0
for _, method in ipairs({ "SetWidth", "SetHeight", "SetSize" }) do
    local original = focus[method]
    focus[method] = function(self, ...)
        sizeCalls = sizeCalls + 1
        return original(self, ...)
    end
end

-- 1. The target castbar is off, the focus castbar is on: re-anchoring the
--    target bar leaves the focus bar shown.
owned = { focus = true }
focus.shown = true
_G.MSUF_ReanchorTargetCastBar()
Check(focus.shown == true, "the target re-anchor hid the focus castbar (no target bar exists)")

-- 2. Both castbars are on: the target size pass without a target bar sizes nothing.
owned = { target = true, focus = true }
sizeCalls = 0
local applied = _G.MSUF_ApplyCastbarEffectiveSizeUnit("target")
Check(applied == false, "the target size pass without a target bar reported " .. tostring(applied))
Check(sizeCalls == 0, "the target size pass resized the focus castbar " .. sizeCalls .. " time(s)")

-- 3. The focus pass still reaches the focus bar.
sizeCalls = 0
Check(_G.MSUF_ApplyCastbarEffectiveSizeUnit("focus") == true, "the focus size pass found no focus bar")
Check(sizeCalls > 0, "the focus size pass did not resize the focus castbar")

-- 4. With a target bar built, the target pass sizes that bar and not the focus bar.
local target = world:Driver("target")
Check(_G.MSUF_TargetCastbar == target, "the fixture must build the target bar")
sizeCalls = 0
local targetCalls = 0
local original = target.SetWidth
target.SetWidth = function(self, ...)
    targetCalls = targetCalls + 1
    return original(self, ...)
end
Check(_G.MSUF_ApplyCastbarEffectiveSizeUnit("target") == true, "the target size pass found no target bar")
Check(targetCalls > 0, "the target size pass did not resize the target castbar")
Check(sizeCalls == 0, "the target size pass also resized the focus castbar")

if failures > 0 then error(("castbar target/focus isolation smoke: %d failure(s)"):format(failures)) end
print("castbar_target_bar_never_borrows_focus_bar_smoke: ok")
