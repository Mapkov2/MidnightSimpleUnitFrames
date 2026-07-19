-- Runtime regression for Edit Mode's dirty-only idle/combat lifecycle.
local root = arg and arg[1] or "."
local layoutPath = root .. "/MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_Layout.lua"
local corePath = root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Core.lua"

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local timers = {}
_G.C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}

local function RunTimer()
    local timer = table.remove(timers, 1)
    Check(timer ~= nil, "expected queued timer")
    timer.callback()
end

local function Frame(name)
    local frame = { name = name, shown = true, scripts = {} }
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    return frame
end

_G.UIParent = Frame("UIParent")
_G.CreateFrame = function(_, name)
    local frame = Frame(name)
    if name then _G[name] = frame end
    return frame
end

local state = { combat = false, moverSyncs = 0, hudRefreshes = 0 }
local MSUF = {}
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

local EM2 = {
    Util = {
        Round = function(value) return math.floor((tonumber(value) or 0) + 0.5) end,
        IsConfigCombatLocked = function() return state.combat end,
    },
    State = { IsActive = function() return true end },
    Movers = {
        IsShown = function() return true end,
        SyncAll = function() state.moverSyncs = state.moverSyncs + 1 end,
    },
    HUD = {
        IsShown = function() return true end,
        RefreshControls = function() state.hudRefreshes = state.hudRefreshes + 1 end,
    },
}
_G.MSUF_EM2 = EM2

local chunk, loadError = loadfile(layoutPath)
Check(chunk ~= nil, loadError)
chunk("MidnightSimpleUnitFrames", MSUF)
Check(type(_G.MSUF_InstallEditLayoutUI) == "function", "layout installer was not exported")
_G.MSUF_InstallEditLayoutUI("MidnightSimpleUnitFrames", MSUF)
Check(EM2.Ticker and type(EM2.Ticker.Start) == "function", "Ticker API was not installed")

EM2.Ticker.Start()
Equal(#timers, 1, "Ticker.Start did not coalesce initial work")
local tickerFrame = _G.MSUF_EM2_TickerFrame
Check(tickerFrame and not tickerFrame:IsShown(), "idle ticker frame remained visible")
Check(tickerFrame.scripts.OnUpdate == nil, "idle ticker retained OnUpdate")
RunTimer()
Equal(state.moverSyncs, 1, "initial mover sync")
Equal(state.hudRefreshes, 1, "initial HUD refresh")
Equal(#timers, 0, "initial dirty sync scheduled recurring idle work")

EM2.Ticker.RequestIdleSync("hud")
EM2.Ticker.RequestIdleSync("hud")
Equal(#timers, 1, "duplicate HUD dirties were not coalesced")
RunTimer()
Equal(state.moverSyncs, 1, "HUD-only dirty unexpectedly synced movers")
Equal(state.hudRefreshes, 2, "HUD-only dirty did not refresh once")
Equal(#timers, 0, "HUD dirty sync became recurring")

state.combat = true
EM2.Ticker.RequestIdleSync()
Equal(#timers, 0, "combat request armed Edit Mode idle work")
Equal(state.moverSyncs, 1, "combat request synced movers")
Equal(state.hudRefreshes, 2, "combat request refreshed HUD")

state.combat = false
EM2.Ticker.RequestIdleSync()
Equal(#timers, 1, "post-combat dirty request was not queued")
EM2.Ticker.Stop()
RunTimer()
Equal(state.moverSyncs, 1, "stale timer survived Ticker.Stop")
Equal(state.hudRefreshes, 2, "stale HUD timer survived Ticker.Stop")
Check(not tickerFrame:IsShown() and tickerFrame.scripts.OnUpdate == nil,
    "Ticker.Stop did not fully detach the driver")

local coreHandle = assert(io.open(corePath, "rb"))
local coreSource = coreHandle:read("*a")
coreHandle:close()
Check(coreSource:find('local wantedMode = active and "active" or (pendingCombatExitApply and "regen" or nil)', 1, true)
    and coreSource:find('elseif wantedMode == "regen" then', 1, true),
    "combat exit retains the full Edit Mode event set while waiting for regen")

local layoutHandle = assert(io.open(layoutPath, "rb"))
local layoutSource = layoutHandle:read("*a")
layoutHandle:close()
Check(not layoutSource:find("EDIT_IDLE_HUD_SYNC_INTERVAL", 1, true)
    and not layoutSource:find("EDIT_IDLE_MOVER_SYNC_INTERVAL", 1, true),
    "periodic Edit Mode idle polling returned")
Check(layoutSource:find("EM2.Snap.HideGuides(true)", 1, true)
    and layoutSource:find("if guideFadeFrame then guideFadeFrame:Hide() end", 1, true),
    "combat/stop teardown leaves the snap-guide OnUpdate armed")

print("PASS Edit Mode idle lifecycle: dirty-only one-shots, coalescing, combat/stop teardown")
