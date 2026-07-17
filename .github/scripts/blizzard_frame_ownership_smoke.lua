-- Regression smoke for independent MSUF/Blizzard unitframe ownership.
-- Run from the repository root with Lua 5.1:
--   lua .github/scripts/blizzard_frame_ownership_smoke.lua

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local checks = 0
local function Equal(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function Contains(text, needle, label)
    Equal(text:find(needle, 1, true) ~= nil, true, label)
end

local function Omits(text, needle, label)
    Equal(text:find(needle, 1, true) == nil, true, label)
end

local function NewFrame(name)
    local frame = {
        name = name,
        hidden = false,
        unregisters = 0,
        scripts = {},
    }
    function frame:UnregisterAllEvents() self.unregisters = self.unregisters + 1 end
    function frame:Hide() self.hidden = true end
    function frame:Show() self.hidden = false end
    function frame:IsProtected() return false end
    function frame:IsForbidden() return false end
    function frame:SetAllPoints() self.allPoints = true end
    function frame:SetParent(parent)
        self.parent = parent
        if self.setParentHook then self.setParentHook(self, parent) end
    end
    function frame:GetParent() return self.parent end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    return frame
end

_G.UIParent = NewFrame("UIParent")
_G.InCombatLockdown = function() return false end
_G.CreateFrame = function() return NewFrame("anonymous") end
_G.hooksecurefunc = function(frame, method, callback)
    assert(method == "SetParent")
    frame.setParentHook = callback
end

local MSUF = { UF = {} }
local kernel = assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_BlizzardFrames.lua"))
kernel("MidnightSimpleUnitFrames", MSUF)

local UNIT_KEYS = { "player", "target", "targettarget", "focus", "focustarget", "pet", "boss" }
local function Reset(flags, globalDisable)
    _G.MSUF_DB = {
        general = { disableBlizzardUnitFrames = globalDisable ~= false },
    }
    for i = 1, #UNIT_KEYS do
        local key = UNIT_KEYS[i]
        _G.MSUF_DB[key] = {
            enabled = true,
            useBlizzardFrame = flags and flags[key] == true or false,
        }
    end
    _G.PlayerFrame = NewFrame("player")
    _G.PetFrame = NewFrame("pet")
    _G.TargetFrame = NewFrame("target")
    _G.TargetFrameToT = NewFrame("targettarget")
    _G.TargetFrame.totFrame = _G.TargetFrameToT
    _G.FocusFrame = NewFrame("focus")
    _G.FocusFrameToT = NewFrame("focustarget")
    _G.FocusFrame.totFrame = _G.FocusFrameToT
    _G.BossTargetFrameContainer = NewFrame("bossContainer")
    for i = 1, 5 do _G["Boss" .. i .. "TargetFrame"] = NewFrame("boss" .. i) end
end

local function Killed(frame)
    return frame.hidden == true and frame.unregisters > 0
end

Reset({})
MSUF.UF.DisableBlizzardFrames()
Equal(Killed(_G.PlayerFrame), true, "default player is suppressed")
Equal(Killed(_G.PetFrame), true, "default pet is suppressed")
Equal(Killed(_G.TargetFrame), true, "default target is suppressed")
Equal(Killed(_G.TargetFrameToT), true, "default targettarget is suppressed")
Equal(Killed(_G.FocusFrame), true, "default focus is suppressed")
Equal(Killed(_G.FocusFrameToT), true, "default focustarget is suppressed")
Equal(Killed(_G.BossTargetFrameContainer), true, "default boss container is suppressed")

Reset({ player = true, target = true, targettarget = true, focus = true, focustarget = true, pet = true, boss = true })
MSUF.UF.DisableBlizzardFrames()
Equal(_G.PlayerFrame.unregisters, 0, "forced player remains Blizzard-owned")
Equal(_G.PetFrame.unregisters, 0, "forced pet remains Blizzard-owned")
Equal(_G.TargetFrame.unregisters, 0, "forced target remains Blizzard-owned")
Equal(_G.TargetFrameToT.unregisters, 0, "forced targettarget remains Blizzard-owned")
Equal(_G.FocusFrame.unregisters, 0, "forced focus remains Blizzard-owned")
Equal(_G.FocusFrameToT.unregisters, 0, "forced focustarget remains Blizzard-owned")
Equal(_G.BossTargetFrameContainer.unregisters, 0, "forced boss container remains Blizzard-owned")
for i = 1, 5 do
    Equal(_G["Boss" .. i .. "TargetFrame"].unregisters, 0, "forced boss member remains Blizzard-owned " .. i)
end

Reset({ target = true, focus = true })
MSUF.UF.DisableBlizzardFrames()
Equal(_G.TargetFrame.unregisters, 0, "Blizzard target can remain without targettarget")
Equal(Killed(_G.TargetFrameToT), true, "targettarget can be suppressed below Blizzard target")
Equal(_G.FocusFrame.unregisters, 0, "Blizzard focus can remain without focustarget")
Equal(Killed(_G.FocusFrameToT), true, "focustarget can be suppressed below Blizzard focus")

Reset({ targettarget = true, focustarget = true })
MSUF.UF.DisableBlizzardFrames()
Equal(_G.TargetFrame.unregisters, 0, "forced targettarget keeps Blizzard target parent")
Equal(_G.TargetFrameToT.unregisters, 0, "forced targettarget remains Blizzard-owned")
Equal(_G.FocusFrame.unregisters, 0, "forced focustarget keeps Blizzard focus parent")
Equal(_G.FocusFrameToT.unregisters, 0, "forced focustarget remains Blizzard-owned")

Reset({ player = true })
_G.MSUF_DB.player.enabled = false
MSUF.UF.DisableBlizzardFrames()
Equal(_G.PlayerFrame.unregisters, 0, "Blizzard player is independent from MSUF enabled")
Equal(MSUF.UF.ShouldUseMSUFUnitFrame("player"), true, "Blizzard ownership never disables MSUF creation")

Reset({}, false)
MSUF.UF.DisableBlizzardFrames()
Equal(_G.PlayerFrame.unregisters, 0, "global Blizzard visibility keeps player")
Equal(_G.TargetFrame.unregisters, 0, "global Blizzard visibility keeps target")
Equal(MSUF.UF.ShouldUseMSUFUnitFrame("target"), true, "global Blizzard visibility does not disable MSUF")

local factory = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua")
Omits(factory, "UF.ShouldUseMSUFUnitFrame", "factory has no Blizzard-ownership branch")

local profiles = Read("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
Contains(profiles, "dst.useBlizzardFrame = dst.forceHideBlizzard == false", "UUF ForceHideBlizzard maps per unit")

local menu = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
Contains(menu, "Force Blizzard frame on", "Frame Basics exposes Blizzard ownership")
Contains(menu, 'SettingMeta(ctx, "basics.force_blizzard_frame", unit, "useBlizzardFrame")', "ownership control has exact setting metadata")
Contains(menu, "Independent from MSUF Enable; /reload required.", "menu explains independent ownership")

local defaults = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
Contains(defaults, "u.useBlizzardFrame = false", "ownership defaults off")

print(string.format("blizzard_frame_ownership_smoke: %d checks passed", checks))
