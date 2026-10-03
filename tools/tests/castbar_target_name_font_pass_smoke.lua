-- castbar_target_name_font_pass_smoke.lua <repoRoot>
--
-- The cast target name of a target castbar takes its target's class colour
-- (CastbarDriver ApplyCastTargetTextColor). UnitSpellTargetClass is secret,
-- and C_ClassColor.GetClassColor builds a new ColorMixin per call, so one cast
-- asks for the colour once and remembers that it painted it
-- (fs._msufCastTargetClassSequence, wave 4 d5f67adce). The castbar font pass
-- (CastbarVisuals ApplyFont) writes the configured text colour onto the same
-- FontString and then repaints the cast target text for the running cast.
-- Before the fix the remembered sequence skipped that repaint: a font pass in
-- the middle of a cast left the name in the font colour until the next cast
-- (red without the fix, step 2). The plain-colour cache of a custom target
-- name colour went stale the same way (step 4).
--
-- Pinned with the real castbar stack (tools/tests/castbar_world.lua):
--   1. a cast paints its target's class colour, asking C_ClassColor once;
--   2. a font pass that rewrites the colour mid-cast repaints the class colour
--      (one more GetClassColor, the pass's own repaint);
--   3. a font pass that writes nothing (font cache current) keeps the colour
--      and asks C_ClassColor no more: the per-cast saving stays;
--   4. a custom target name colour comes back after a font pass rewrote it.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local EXTRA = {
    "MSUF_Require.lua", "MSUF_Castbars_Core.lua", "MSUF_CastbarStyle.lua", "MSUF_CastbarFrames.lua",
    "MSUF_CastbarAnchors.lua", "MSUF_PlayerCastbarRuntime.lua", "MSUF_CastbarPreviewEdit.lua",
    "MSUF_CastbarPreviews.lua", "MSUF_CastbarVisuals.lua", "MSUF_InterruptReady.lua",
    "MSUF_CastbarRounded.lua", "MSUF_CastbarVisualCompat.lua",
}

local MAGE = { 0.25, 0.78, 0.92 }
local classCalls = 0
local textColor = { 1, 1, 1 }
local customColor

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
    -- Kernel/MSUF_Util.lua: the cast time text writer.
    _G.MSUF_SetCastTimeText = function() end
    _G.MSUF_GetCastbarTimeFormat = function() return "CURRENT" end
    _G.MSUF_FormatCastbarTimeText = function(_, remaining) return string.format("%.1f", tonumber(remaining) or 0) end
    _G.MSUF_EnsureDB = function() end
    _G.MSUF_MarkFontApplyFailed = function() end
    _G.MSUF_GetCastbarTextColor = function() return textColor[1], textColor[2], textColor[3] end
    _G.MSUF_GetConfiguredFontColor = function() return 1, 1, 1 end
    _G.MSUF_GetCastbarBackgroundColor = function() return 0.176, 0.176, 0.176, 1 end
    _G.MSUF_NormalizeFontPath = function(path) return path end
    _G.MSUF_GetInternalFontPathByKey = function() return nil end
    _G.MSUF_UpdateCastbarEditInfo = function() end
    _G.MSUF_SyncCastbarPositionPopup = function() end
    _G.MSUF_EnsureCooldownWidthObservers = function() end
    -- Runtime/MSUF_Colors.lua: the shared custom target name colour.
    _G.MSUF_GetCastbarTargetNameColor = function()
        if customColor then return customColor[1], customColor[2], customColor[3], true end
        return 1, 1, 1, false
    end
    _G.C_ClassColor = { GetClassColor = function(class)
        classCalls = classCalls + 1
        Check(class == "MAGE", "unexpected class " .. tostring(class))
        return { GetRGB = function() return MAGE[1], MAGE[2], MAGE[3] end }
    end }
    _G.UnitShouldDisplaySpellTargetName = function() return true end
    _G.UnitSpellTargetName = function() return "Frostmage" end
    _G.UnitSpellTargetClass = function() return "MAGE" end
end

local world = World.New(root, "timer", { extra = EXTRA, setup = Setup, richWidgets = true })
local general = _G.MSUF_DB.general
general.castbarTargetShowTargetName = true

local frame = world:Driver("target")
local fs = world.NewWidget("FontString")
frame.castTargetText = fs
local writes = 0
function fs:SetTextColor(r, g, b)
    writes = writes + 1
    self.r, self.g, self.b = r, g, b
end
local function Is(color)
    return math.abs(fs.r - color[1]) < 1e-6 and math.abs(fs.g - color[2]) < 1e-6 and math.abs(fs.b - color[3]) < 1e-6
end
local function Color()
    return string.format("%.2f, %.2f, %.2f", fs.r or -1, fs.g or -1, fs.b or -1)
end

-- 1. The cast paints its target's class colour.
_G.MSUF_CastbarDriver_ApplyBackendState("target")
world:StartCast("target", "Frostbolt", 3, 77)
world:Fire(frame, "UNIT_SPELLCAST_START", "Frostbolt-guid", 133)
world:Advance(0.1)
Check(fs.text == "Frostmage" and fs.shown, "1: the cast shows no target name")
Check(Is(MAGE), "1: the target name is not in its class colour: " .. Color())
Check(classCalls == 1, "1: one cast asked C_ClassColor " .. classCalls .. " times")

-- 2. A font pass mid-cast rewrites the colour; the class colour comes back.
textColor = { 0.9, 0.8, 0.1 }
_G.MSUF_ApplyCastbarDetailLayout(frame, "target", general)
Check(Is(MAGE), "2: after a mid-cast font pass the name kept the font colour (" .. Color()
    .. "); the per-cast class cache skipped the repaint")
Check(classCalls == 2, "2: the font pass repaint asked C_ClassColor " .. (classCalls - 1) .. " times, not once")

-- 3. A font pass with a current font cache writes nothing and asks nothing.
writes = 0
_G.MSUF_ApplyCastbarDetailLayout(frame, "target", general)
Check(Is(MAGE) and writes == 0, "3: an unchanged font pass rewrote the colour " .. writes .. " times")
Check(classCalls == 2, "3: an unchanged font pass asked C_ClassColor again")
world:Fire(frame, "UNIT_SPELLCAST_DELAYED", "Frostbolt-guid", 133)
Check(Is(MAGE) and classCalls == 2, "3: a pushback repaint asked C_ClassColor again")

-- 4. A custom target name colour survives a font pass that rewrote it.
customColor = { 0.3, 0.9, 0.3 }
_G.MSUF_RefreshCastTargetText(frame)
Check(Is(customColor), "4: the custom target name colour was not applied: " .. Color())
textColor = { 0.2, 0.2, 0.9 }
_G.MSUF_ApplyCastbarDetailLayout(frame, "target", general)
Check(Is(customColor), "4: after a font pass the custom target name colour stayed lost: " .. Color())

print("castbar_target_name_font_pass_smoke: ok")
