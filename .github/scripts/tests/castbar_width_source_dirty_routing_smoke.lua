-- Standalone regression for dependency-targeted Castbar Auto Width refreshes.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local queued = {}
local retryTimers = 0
local bootFrame
local readCounts = { player = 0, target = 0, focus = 0, boss = 0 }
local applyCounts = { player = 0, target = 0, focus = 0, boss = 0 }

local function QueueNext(callback)
    queued[#queued + 1] = callback
end

local function DrainOne()
    Equal(#queued, 1, "expected one coalesced next-frame callback")
    local callback = queued[1]
    queued[1] = nil
    callback()
    Equal(#queued, 0, "flush queued unexpected follow-up work")
end

local function ResetCounters()
    for key in pairs(readCounts) do readCounts[key] = 0 end
    for key in pairs(applyCounts) do applyCounts[key] = 0 end
end

local function NewFrame(owner, width, height, shown)
    local frame = {
        owner = owner,
        width = width,
        height = height,
        scale = 1,
        shown = shown ~= false,
        hooks = {},
    }
    function frame:GetWidth()
        readCounts[self.owner] = readCounts[self.owner] + 1
        return self.width
    end
    function frame:GetHeight() return self.height end
    function frame:GetEffectiveScale() return self.scale end
    function frame:IsShown() return self.shown end
    function frame:IsProtected() return false end
    function frame:HookScript(script, callback)
        local callbacks = self.hooks[script] or {}
        callbacks[#callbacks + 1] = callback
        self.hooks[script] = callbacks
    end
    return frame
end

local function Fire(frame, script)
    local callbacks = frame.hooks[script] or {}
    for i = 1, #callbacks do callbacks[i](frame) end
end

local frames = {}
local sourceFrames = {}
for _, unit in ipairs({ "player", "target", "focus" }) do
    local health = NewFrame(unit, unit == "target" and 220 or 200, 20, true)
    local frame = NewFrame(unit, health.width, 36, unit ~= "target")
    frame.hpBar = health
    frames[unit] = frame
    sourceFrames[unit] = health
end
for i = 1, 5 do
    local health = NewFrame("boss", 240 + i, 18, true)
    local frame = NewFrame("boss", health.width, 32, true)
    frame.hpBar = health
    frames["boss" .. i] = frame
    sourceFrames["boss" .. i] = health
end

local function NewCastbar(owner)
    local frame = { owner = owner, width = 100, height = 18 }
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetEffectiveScale() return 1 end
    function frame:SetWidth(value)
        self.width = value
        applyCounts[self.owner] = applyCounts[self.owner] + 1
    end
    function frame:SetHeight(value) self.height = value end
    function frame:ApplyLayout() end
    return frame
end

_G.MSUF_PlayerCastbar = NewCastbar("player")
_G.MSUF_TargetCastbar = NewCastbar("target")
_G.MSUF_FocusCastbar = NewCastbar("focus")
_G.MSUF_BossCastbars = {}
for i = 1, 5 do _G.MSUF_BossCastbars[i] = NewCastbar("boss") end

local general = {
    enablePlayerCastbar = true,
    enableTargetCastbar = true,
    enableFocusCastbar = true,
    enableBossCastbar = true,
    castbarPlayerMatchWidth = "unitframe",
    castbarTargetMatchWidth = "unitframe",
    castbarFocusMatchWidth = "unitframe",
    bossCastbarMatchWidth = "unitframe",
    castbarPlayerBarHeight = 18,
    castbarTargetBarHeight = 18,
    castbarFocusBarHeight = 18,
    bossCastbarHeight = 18,
}

_G.MSUF_DB = { general = general }
_G.EnsureDB = function() end
_G.MSUF_ShouldUseMSUFCastbar = function() return true end
_G.MSUF_InCombat = false
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.MSUF_Castbars_RunNextFrame = QueueNext
_G.C_Timer = {
    After = function()
        retryTimers = retryTimers + 1
    end,
}
_G.CreateFrame = function()
    local frame = { scripts = {}, events = {} }
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    bootFrame = frame
    return frame
end

local namespace = {
    UF = {
        frames = frames,
        GetFrame = function(unit) return frames[unit] end,
    },
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
_G.MSUF_NS = namespace

local chunk, loadError = loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua")
Check(chunk ~= nil, loadError)
chunk("MidnightSimpleUnitFrames", namespace)

-- Seed hooks and numeric signatures for every configured source.
_G.MSUF_UpdateCastbarWidthSourceSync(general, nil, false)
DrainOne()
ResetCounters()
retryTimers = 0

-- Reusing already-hooked frames must remain valid and must not start retries.
_G.MSUF_UpdateCastbarWidthSourceSync(general, nil, true)
Equal(retryTimers, 0, "already-hooked sources incorrectly started a retry chain")
DrainOne()
for unit, count in pairs(applyCounts) do
    Equal(count, 0, "unchanged numeric signature reapplied " .. unit)
end
ResetCounters()

-- Showing target must inspect and resize target only, despite all sources being active.
frames.target.shown = true
Fire(frames.target, "OnShow")
DrainOne()
Check(readCounts.target > 0, "target source was not inspected after OnShow")
Equal(readCounts.player, 0, "target OnShow inspected player source")
Equal(readCounts.focus, 0, "target OnShow inspected focus source")
Equal(readCounts.boss, 0, "target OnShow inspected boss sources")
Check(applyCounts.target > 0, "target OnShow did not resize target castbar")
Equal(applyCounts.player, 0, "target OnShow resized player castbar")
Equal(applyCounts.focus, 0, "target OnShow resized focus castbar")
Equal(applyCounts.boss, 0, "target OnShow resized boss castbars")
ResetCounters()

-- Repeated source events coalesce, and unchanged geometry performs no apply.
Fire(frames.target, "OnShow")
Fire(frames.target, "OnShow")
DrainOne()
Equal(applyCounts.target, 0, "unchanged target geometry reapplied castbar")
ResetCounters()

sourceFrames.target.width = 260
Fire(sourceFrames.target, "OnSizeChanged")
Fire(sourceFrames.target, "OnSizeChanged")
DrainOne()
Check(applyCounts.target > 0, "changed target health width did not resize target castbar")
Equal(_G.MSUF_TargetCastbar.width, 260, "target castbar did not consume changed health width")
Equal(applyCounts.player, 0, "target health resize touched player castbar")
Equal(applyCounts.focus, 0, "target health resize touched focus castbar")
Equal(applyCounts.boss, 0, "target health resize touched boss castbars")
ResetCounters()

-- Boss sources share one logical castbar unit; one boss event must not fan out
-- into player/target/focus signature work.
frames.boss3.shown = false
Fire(frames.boss3, "OnHide")
DrainOne()
Check(readCounts.boss > 0 and applyCounts.boss > 0, "boss source change was not applied")
Equal(readCounts.player, 0, "boss source change inspected player source")
Equal(readCounts.target, 0, "boss source change inspected target source")
Equal(readCounts.focus, 0, "boss source change inspected focus source")
Equal(applyCounts.player, 0, "boss source change resized player castbar")
Equal(applyCounts.target, 0, "boss source change resized target castbar")
Equal(applyCounts.focus, 0, "boss source change resized focus castbar")
ResetCounters()

-- Removing a source must detach its logical dependency even though WoW hooks
-- themselves cannot be removed.
general.castbarTargetMatchWidth = nil
_G.MSUF_UpdateCastbarWidthSourceSync(general, "target", false)
Fire(frames.target, "OnHide")
Equal(#queued, 0, "retired target source still queued width work")

Check(bootFrame and bootFrame.scripts.OnEvent, "width-source lifecycle driver missing")
print("castbar width source dirty routing smoke: ok")
