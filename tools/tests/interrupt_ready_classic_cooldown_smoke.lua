-- interrupt_ready_classic_cooldown_smoke.lua <repoRoot> <flavor>
--
-- The interrupt-ready indicator reads its cooldowns from
-- C_Spell.GetSpellCooldownDuration. No Classic branch of Blizzard's UI calls
-- that function, so a Classic build without it must fall back to the plain
-- C_Spell.GetSpellCooldown table (the call Blizzard's Classic action buttons
-- make) instead of reporting "not ready" on every interruptible cast.
--
-- The fixture models the client: cooldown tables carry the global cooldown,
-- held cooldowns report isEnabled = false, time advances between frames, and
-- a Cooldown frame's SetCooldownFromDurationObject accepts native Duration
-- objects only. With the Duration API present the native path must stay the
-- only reader.
--
-- Plain Lua 5.1: repo root and client flavor (Mainline, Vanilla, TBC, Mists,
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Vanilla"

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local now = 1000
GetTime = function() return now end
GetTimePreciseSec = nil
issecretvalue = function() return false end

local timers = {}
C_Timer = {
    After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback, at = now } end,
    NewTimer = function() return { Cancel = function() end } end,
}
local wakeArms = 0
local Region = {}
Region.__index = Region
local named = {}
function Region:SetScript(name, callback) self.scripts[name] = callback end
function Region:RegisterEvent(event) self.events[event] = true end
function Region:UnregisterEvent(event) self.events[event] = nil end
function Region:UnregisterAllEvents() self.events = {} end
function Region:CreateTexture() return setmetatable({ scripts = {}, events = {} }, Region) end
function Region:SetAllPoints() end
function Region:SetPoint() end
function Region:ClearAllPoints() end
function Region:SetSize() end
function Region:SetTexture() end
function Region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function Region:SetAlpha(value) self.alpha = value end
function Region:SetAlphaFromBoolean(value, whenTrue, whenFalse) self.alpha = value and whenTrue or whenFalse end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:Clear() self.cleared = true end
function Region:GetHeight() return 18 end
function Region:SetDrawSwipe() end
function Region:SetDrawEdge() end
function Region:SetDrawBling() end
function Region:SetHideCountdownNumbers() end
function Region:SetCooldownFromDurationObject(duration)
    Check(type(duration) == "table" and duration.native == true,
        "a Cooldown frame was armed with something that is not a native Duration object")
    wakeArms = wakeArms + 1
end
CreateFrame = function(kind, name)
    local frame = setmetatable({ kind = kind, scripts = {}, events = {} }, Region)
    if name then named[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")
UnitClass = function() return "Warrior", "WARRIOR" end
C_SpellBook = { IsSpellKnownOrInSpellBook = function() return false end }
MSUF_ShouldUseMSUFCastbar = function() return true end
MSUF_DB = { general = { kickReadyShowTarget = true, kickReadyStyle = "box" } }

local PUMMEL = 6552
local cooldowns = {}
local plainReads, nativeReads = 0, 0
C_Spell = {
    GetSpellCooldown = function(spellID)
        plainReads = plainReads + 1
        local entry = cooldowns[spellID]
        if not entry then return { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 } end
        return { startTime = entry.start, duration = entry.duration, isEnabled = entry.enabled ~= false,
            isActive = entry.duration > 0, modRate = entry.rate or 1, isOnGCD = entry.duration <= 1.5 }
    end,
}
local withDurationAPI = flavor == "Mainline" or flavor == "Forever" or flavor == "MistsDuration"
if withDurationAPI then
    C_Spell.GetSpellCooldownDuration = function(spellID, ignoreGCD)
        nativeReads = nativeReads + 1
        Check(ignoreGCD == true, "the Duration API was asked to include the global cooldown")
        local entry = cooldowns[spellID]
        local finish = entry and entry.duration > 1.5 and entry.start + entry.duration or 0
        return { native = true,
            GetRemainingDuration = function() local left = finish - now; return left > 0 and left or 0 end,
            GetEndTime = function() return finish end,
            IsZero = function() return finish - now <= 0 end }
    end
end

local client = {
    IsRetail = flavor == "Mainline" or flavor == "Forever",
    IsForever = flavor == "Forever",
    IsVanilla = flavor == "Vanilla",
    IsTBC = flavor == "TBC",
    IsMists = flavor == "Mists" or flavor == "MistsDuration",
    IsClassic = flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists" or flavor == "MistsDuration",
}
local ns = { Client = client, ExportPublic = function(name, value) _G[name] = value end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))("MSUF", ns)
local eventFrame = Check(named.MSUF_InterruptReady_EventFrame, "interrupt-ready event frame is missing")
Check(_G.MSUF_KickReady_GetSpellID() == PUMMEL, "Warriors must interrupt with Pummel")

local target = { unit = "target", statusBar = CreateFrame("StatusBar"), MSUF_castActive = true,
    isNotInterruptible = false, MSUF_kickInterruptibleConfirmed = true }
MSUF_TargetCastbar = target

local function Paint()
    now = now + 0.016
    _G.MSUF_KickReady_RefreshFrame(target)
    local box = Check(target.kickReadyBox and target.kickReadyBox.fill.color, "no indicator box was painted")
    local color = target.kickReadyBox.fill.color
    return color[1] == 0 and color[2] == 1, box
end
local function Event()
    now = now + 0.016
    eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", PUMMEL)
end

-- 1. Nothing on cooldown.
Check(Paint() == true, "an interrupt off cooldown is painted as not ready")
Check(_G.MSUF_KickReady_IsReady() == true, "an interrupt off cooldown reports not ready")

-- 2. Only the global cooldown runs after another ability.
cooldowns[PUMMEL] = { start = now, duration = 1.5 }
Event()
Check(Paint() == true, "the global cooldown alone made the interrupt look unavailable")

-- 3. Pummel used two seconds ago: ten second cooldown.
cooldowns[PUMMEL] = { start = now - 2, duration = 10 }
timers = {}
Event()
Check(Paint() == false, "an interrupt on cooldown is painted as ready")
Check(_G.MSUF_KickReady_IsReady() == false, "an interrupt on cooldown reports ready")
if not withDurationAPI then
    local timer = timers[#timers]
    Check(timer and math.abs(timer.delay - 8.05) < 0.1,
        "no wake was scheduled for the end of the plain cooldown (delay " .. tostring(timer and timer.delay) .. ")")
    -- 4. The cooldown ends; the wake repaints.
    now = now + 8.1
    timer.callback()
    Check(target.kickReadyBox.fill.color[1] == 0 and target.kickReadyBox.fill.color[2] == 1,
        "the indicator did not turn ready when the cooldown ended")
    Check(_G.MSUF_KickReady_IsReady() == true, "the interrupt still reports not ready after its cooldown")

    -- 5. A held cooldown never reads as ready and schedules no wake.
    cooldowns[PUMMEL] = { start = now, duration = 10, enabled = false }
    timers = {}
    Event()
    Check(Paint() == false, "a held cooldown is painted as ready")
    Check(#timers == 0, "a held cooldown scheduled a wake")

    -- 6. A cooldown rate speeds the recovery up.
    cooldowns[PUMMEL] = { start = now, duration = 10, rate = 2 }
    timers = {}
    Event()
    now = now + 5.2
    Check(Paint() == true, "a doubled cooldown rate was ignored")

    Check(plainReads > 0 and nativeReads == 0, "the plain fallback was not the cooldown reader")
    Check(wakeArms == 0, "the plain cooldown view armed a native completion frame")
else
    Check(nativeReads > 0 and plainReads == 0, "the plain table was read although the Duration API exists")
end

print("interrupt_ready_classic_cooldown_smoke: " .. flavor .. " OK")
