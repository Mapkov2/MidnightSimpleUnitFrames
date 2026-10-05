-- menu_color_picker_profile_switch_smoke.lua <repoRoot> <flavor>
--
-- The menu colour picker remembers the colours it opened with, without the
-- profile they came from. Its keyboard input propagates, so "/msuf load
-- Second" can switch the profile while it is open; Cancel then wrote the first
-- profile's colours into Second (bh2 CX-C3-01). The profile boundary
-- (MSUF.ProfileRuntime.BeforeMutation) now finishes the picker against the
-- profile it edited, the way closing the menu does: the first profile keeps
-- the picked colour and a later Cancel has nothing left to restore.
--
-- Boots the real core and Options graph and opens the real menu
-- (menu_core_world.lua). Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_color_picker_profile_switch_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "opt_colors" })
local M, e, core = mw.M, mw.env, mw.core
-- Colour-select surface the picker's wheel uses and the shared stubs leave out.
local methods = mw.world.widgets.Methods
function methods:SetColorWheelTexture(value) self.wheelTexture = value end
function methods:SetColorValueTexture(value) self.valueTexture = value end
function methods:SetColorWheelThumbTexture(value) self.wheelThumb = self:CreateTexture(); self.wheelThumb:SetTexture(value) end
function methods:SetColorValueThumbTexture(value) self.valueThumb = self:CreateTexture(); self.valueThumb:SetTexture(value) end
function methods:GetColorWheelThumbTexture() return self.wheelThumb end
function methods:GetColorValueThumbTexture() return self.valueThumb end
function methods:SetColorRGB(r, g, b)
    self.rgb = { r, g, b }
    local fn = self:GetScript("OnColorSelect")
    if fn then fn(self, r, g, b) end
end
function methods:GetColorRGB() return unpack(self.rgb or { 1, 1, 1 }) end
-- The runtime fanout of a profile switch is outside this contract.
for _, name in ipairs({ "MSUF_ApplyMsufScale", "MSUF_TargetSoundDriver_ApplySetting", "MSUF_NSRTNicknames_ApplySetting",
    "MSUF_EllesmereEditMode_SetEnabled", "MSUF_BlizzardEditMode_SetEnabled",
    "MSUF_Grid2EditMode_SetEnabled", "MSUF_DetailsEditMode_SetEnabled", "MSUF_DominosEditMode_SetEnabled",
    "MSUF_DandersEditMode_SetEnabled", "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll",
    "MSUF_ClassPower_Apply", "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged",
    "MSUF_ApplyAllCastbarsAndSync", "MSUF_UpdateAllFonts_Immediate", "MSUF_ApplyCurrentProfileGlobalUiScale",
    "MSUF_ForceReanchorAllUnitFrames_Once" }) do e[name] = function() end end
core.UF.DisableBlizzardFrames = function() end
core.UF.Apply = function() return true end
core.MSUF_ApplyGameplayVisuals = function() end
M.ApplyService.Flush = function() return true end

local first = M.EnsureDB()
local firstName = e.MSUF_ActiveProfile
first.general.unifiedBarR, first.general.unifiedBarG, first.general.unifiedBarB = 0.2, 0.4, 0.6
Check(e.MSUF_CopyProfile(firstName, "Second"), "the second profile was not created")
local second = e.MSUF_GlobalDB.profiles.Second
second.general.unifiedBarR, second.general.unifiedBarG, second.general.unifiedBarB = 0.9, 0.8, 0.7

local owner
for _, frame in ipairs(mw.world.widgets.frames) do
    if frame._msuf2ColorLabel == "Unified bar color" then owner = frame; break end
end
Check(owner, "the Unified bar color button was not built")
owner:SetRGB(0.2, 0.4, 0.6)
local picker
local openPicker = M.Widgets.OpenColorContextPicker
M.Widgets.OpenColorContextPicker = function(...)
    picker = openPicker(...)
    return picker
end
owner:GetScript("OnClick")(owner)
Check(picker and picker:IsShown(), "the colour picker did not open")
picker:Apply(0.1, 0.2, 0.3)
Check(first.general.unifiedBarR == 0.1, "the picker did not paint the first profile live")

-- The picker's keyboard input propagates: chat opens and the slash command runs.
e.SlashCmdList.MSUF2OPTIONS("load Second")
Check(e.MSUF_ActiveProfile == "Second", "the profile did not switch")
mw:RunTimers()
Check(not picker:IsShown(), "the colour picker stayed open across the profile switch")
Check(first.general.unifiedBarR == 0.1 and first.general.unifiedBarG == 0.2 and first.general.unifiedBarB == 0.3,
    "the profile switch did not keep the colour picked in the first profile")

-- A late Cancel (Escape or a click outside) must not reach the new profile.
picker:Finish(true)
Check(second.general.unifiedBarR == 0.9 and second.general.unifiedBarG == 0.8 and second.general.unifiedBarB == 0.7,
    string.format("Cancel after the switch wrote %.1f/%.1f/%.1f into the second profile",
        second.general.unifiedBarR, second.general.unifiedBarG, second.general.unifiedBarB))

print("menu_color_picker_profile_switch_smoke: " .. flavor
    .. " ok (the picker finishes against the profile it edited; the next profile keeps its colours)")
