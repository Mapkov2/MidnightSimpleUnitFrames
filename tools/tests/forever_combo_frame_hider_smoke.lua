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

local FOREVER = { IsForever = true, IsRetail = true, Family = "Mainline", Flavor = "Mainline" }

-- (a) Forever, default ownership: suppressed and kept suppressed.
do
    local UF = Load(FOREVER, {})
    local combo = _G.ComboFrame
    UF.DisableBlizzardFrames()
    CheckSuppressed(combo, "(a) Forever default")
    local hidden = combo.parent
    -- ComboFrame_Update shows it again on the next combo point: invisible.
    combo:Show()
    Check(combo.parent == hidden and hidden:IsShown() == false, "(a) a Blizzard re-show must stay under the hidden parent")
    combo:SetParent(UIParentStub)
    Check(combo.parent == hidden, "(a) a Blizzard reparent onto UIParent must be pulled back")
    Check(combo.hookCount == 1, "(a) ComboFrame must carry exactly one SetParent hook")
    -- A second apply (profile switch) must not stack another SetParent hook.
    UF.DisableBlizzardFrames()
    Check(combo.hookCount == 1, "(a) repeated applies must keep exactly one SetParent hook, got "
        .. tostring(combo.hookCount))
    Check(combo.parent == hidden and combo.shown == false, "(a) a repeated apply must keep ComboFrame suppressed")
end

-- (b) Forever, Blizzard Target frame kept: ComboFrame stays with it.
do
    local UF = Load(FOREVER, { target = { useBlizzardFrame = true } })
    UF.DisableBlizzardFrames()
    CheckUntouched(_G.ComboFrame, "(b) Blizzard Target kept")
    Check(_G.TargetFrame.parent == UIParentStub, "(b) TargetFrame must stay on UIParent")
end

-- (c) Forever, Blizzard Target-of-Target kept: TargetFrame and ComboFrame stay.
do
    local UF = Load(FOREVER, { targettarget = { useBlizzardFrame = true } })
    UF.DisableBlizzardFrames()
    CheckUntouched(_G.ComboFrame, "(c) Blizzard Target-of-Target kept")
    Check(_G.TargetFrame.parent == UIParentStub, "(c) TargetFrame must stay on UIParent")
end

-- (d) Not Forever: Retail, Classic and a harness without MSUF.Client.
do
    local clients = {
        { label = "(d) Retail", client = { IsForever = false, IsRetail = true, Flavor = "Mainline" } },
        { label = "(d) Vanilla", client = { IsForever = false, IsClassic = true, Flavor = "Vanilla" } },
        { label = "(d) no Client", client = nil },
    }
    for _, case in ipairs(clients) do
        local UF = Load(case.client, {})
        UF.DisableBlizzardFrames()
        CheckUntouched(_G.ComboFrame, case.label)
        Check(_G.TargetFrame.parent ~= UIParentStub, case.label .. ": TargetFrame must still be suppressed")
    end
end

-- (e) Forever without ComboFrame: no error.
do
    local UF = Load(FOREVER, {})
    _G.ComboFrame = nil
    local ok, err = pcall(UF.DisableBlizzardFrames)
    Check(ok, "(e) a missing ComboFrame raised: " .. tostring(err))
end

-- (f) Forever, combat, ComboFrame reports protected: deferred to regen.
do
    local UF = Load(FOREVER, {})
    local combo = _G.ComboFrame
    combo.protected = true
    _G.TargetFrame.protected = true
    inCombat = true
    UF.DisableBlizzardFrames()
    Check(combo.hideCalls == 0 and combo.shown == true, "(f) a protected ComboFrame must not be hidden in combat")
    Check(combo.setParentCalls == 0 and combo.parent == UIParentStub,
        "(f) a protected ComboFrame must not be reparented in combat")
    local watcher
    for _, frame in ipairs(created) do
        if frame.events.PLAYER_REGEN_ENABLED and frame.onEvent then watcher = frame end
    end
    Check(watcher ~= nil, "(f) combat suppression must arm a PLAYER_REGEN_ENABLED watcher")
    inCombat = false
    watcher.onEvent(watcher, "PLAYER_REGEN_ENABLED")
    Check(combo.shown == false, "(f) regen must hide the deferred ComboFrame")
    Check(combo.parent ~= UIParentStub and combo.parent == _G.TargetFrame.parent,
        "(f) regen must reparent the deferred ComboFrame into the hidden parent")
end

-- (g) Forever, combat, unprotected ComboFrame: suppressed at once.
do
    local UF = Load(FOREVER, {})
    inCombat = true
    UF.DisableBlizzardFrames()
    local combo = _G.ComboFrame
    Check(combo.shown == false and combo.parent ~= UIParentStub,
        "(g) an unprotected ComboFrame must be suppressed immediately in combat")
end

-- Source contracts.
do
    local kernel = Read(KERNEL_FILE)
    local _, reads = kernel:gsub("MSUF%.Client%.IsForever", "")
    Check(reads == 1, "contract: MSUF.Client.IsForever must be read exactly once, found " .. reads)
    Check(kernel:find("\nlocal IS_FOREVER = MSUF.Client ~= nil and MSUF.Client.IsForever == true\n", 1, true),
        "contract: IS_FOREVER must be a file-load local")
    local disable = kernel:match("local function DisableBlizzardFrames%(%)(.-)\nend\n")
    Check(disable, "contract: DisableBlizzardFrames body not found")
    local targetBlock = disable:match("if hideTarget and hideTargetTarget then(.-)\n    end\n")
    Check(targetBlock, "contract: Target ownership block not found")
    Check(targetBlock:find("if IS_FOREVER then%s+HandleFrame%(_G%.ComboFrame, nil, \"target\"%)"),
        "contract: ComboFrame must be handled inside the Target block behind IS_FOREVER")
    local _, comboCalls = kernel:gsub("_G%.ComboFrame", "")
    Check(comboCalls == 1, "contract: the Kernel must touch ComboFrame exactly once, found " .. comboCalls)
end

print("forever_combo_frame_hider_smoke: ok")
