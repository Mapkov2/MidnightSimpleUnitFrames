-- forever_combo_frame_hider_smoke.lua
-- WoW Forever excludes every Retail combo point bar for its camelot game type,
-- so Blizzard's ComboFrame (a UIParent child that Camelot re-anchors to
-- TargetFrame) is its only combo point display. The Mainline Kernel hider in
-- Kernel/MSUF_BlizzardFrames.lua must suppress it together with TargetFrame on
-- Forever only. This smoke pins:
--   Forever:  default ownership reparents ComboFrame into the MSUF hidden
--             parent, hides it, unregisters its events and keeps it there
--             when Blizzard code reparents it onto UIParent.
--   Gate:     a kept Blizzard Target or Target-of-Target frame, a missing
--             ComboFrame, a missing MSUF.Client and a non-Forever client all
--             leave ComboFrame untouched.
--   Combat:   a ComboFrame that reports protected in combat is neither hidden
--             nor reparented until PLAYER_REGEN_ENABLED; an unprotected one is
--             suppressed at once.
--   Contract: the client fact is read once at file load and the ComboFrame
--             call sits inside the Target ownership block.
-- Run with Lua 5.1 and the repo root as arg 1.
local root = assert(arg[1], "repo root required"):gsub("\\", "/")

local KERNEL_FILE = "MidnightSimpleUnitFrames/Kernel/MSUF_BlizzardFrames.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local inCombat
local created

local function NewFrame(name, shown)
    local frame = { name = name, shown = shown ~= false, events = { SOME_EVENT = true },
        protected = false, hideCalls = 0, setParentCalls = 0 }
    function frame:SetParent(parent) self.setParentCalls = self.setParentCalls + 1; self.parent = parent end
    function frame:GetParent() return self.parent end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.hideCalls = self.hideCalls + 1; self.shown = false end
    function frame:SetAllPoints() end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
    function frame:SetScript(script, fn) if script == "OnEvent" then self.onEvent = fn end end
    function frame:IsProtected() return self.protected end
    function frame:IsForbidden() return false end
    return frame
end

-- Post-hook with the same ordering as hooksecurefunc.
local function InstallPostHook(object, method, hook)
    object.hookCount = (object.hookCount or 0) + 1
    local original = object[method]
    object[method] = function(self, ...)
        original(self, ...)
        hook(self, ...)
    end
end

local UIParentStub

local function Load(client, db)
    created = {}
    inCombat = false
    UIParentStub = NewFrame("UIParent", true)
    _G.UIParent = UIParentStub
    _G.CreateFrame = function(_, name)
        local frame = NewFrame(name, true)
        created[#created + 1] = frame
        return frame
    end
    _G.InCombatLockdown = function() return inCombat end
    _G.hooksecurefunc = InstallPostHook
    _G.MAX_BOSS_FRAMES = 5
    _G.MSUF_GetCastbarBackend = function() return "MSUF" end
    _G.MSUF_DB = db or {}
    _G.TargetFrame = NewFrame("TargetFrame", true)
    _G.TargetFrame.parent = UIParentStub
    _G.ComboFrame = NewFrame("ComboFrame", true)
    _G.ComboFrame.parent = UIParentStub

    local MSUF = { UF = {}, Client = client }
    local chunk = assert(loadfile(root .. "/" .. KERNEL_FILE))
    chunk("MidnightSimpleUnitFrames", MSUF)
    Check(type(MSUF.UF.DisableBlizzardFrames) == "function", "Kernel must export DisableBlizzardFrames")
    return MSUF.UF
end

local function CheckUntouched(combo, label)
    Check(combo.parent == UIParentStub, label .. ": ComboFrame must stay on UIParent")
    Check(combo.shown == true and combo.hideCalls == 0, label .. ": ComboFrame must not be hidden")
    Check(combo.events.SOME_EVENT == true, label .. ": ComboFrame events must stay registered")
    Check(combo.setParentCalls == 0, label .. ": ComboFrame must not be reparented")
end

local function CheckSuppressed(combo, label)
    local hidden = combo.parent
    Check(hidden ~= nil and hidden ~= UIParentStub, label .. ": ComboFrame must be reparented away from UIParent")
    Check(hidden == _G.TargetFrame.parent, label .. ": ComboFrame must share TargetFrame's hidden parent")
    Check(hidden:IsShown() == false, label .. ": the holding parent must be hidden")
    Check(combo.shown == false, label .. ": ComboFrame must be hidden")
    Check(next(combo.events) == nil, label .. ": ComboFrame events must be unregistered")
end

for _,flavor in ipairs({"Vanilla","TBC","Mists"}) do
 local uf=Load({IsClassic=true,Flavor=flavor},{})
 uf.DisableBlizzardFrames();CheckSuppressed(_G.ComboFrame,flavor)
 local uf=Load({IsClassic=true,Flavor=flavor},{target={useBlizzardFrame=true}})
 uf.DisableBlizzardFrames();CheckUntouched(_G.ComboFrame,flavor.." native target")
end
local uf=Load({IsRetail=true},{})
uf.DisableBlizzardFrames();CheckUntouched(_G.ComboFrame,"Mainline")
print("PASS Classic target-owned combo frame with native-target and Mainline controls")
