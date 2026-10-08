-- interrupt_ready_rank_cooldown_smoke.lua <repoRoot> <flavor>
--
-- Classic Era, TBC and WoW Forever keep one spell ID per rank. The
-- interrupt-ready indicator tracks the rank-1 ID, whose cooldown category the
-- other ranks (and, for Shamans, Flame Shock and Frost Shock) share, but
-- SPELL_UPDATE_COOLDOWN names the spell that was cast. A Kick rank 4, a
-- Pummel rank 2 or a Flame Shock must therefore repaint the indicator as
-- "not ready" instead of leaving it green until the hostile cast ends.
--
-- The fixture models the client: every member of a cooldown category reports
-- the category's cooldown, C_Spell.GetSpellName answers nil for a spell the
-- client has not cached yet (lazy-load backed), and a spell outside the
-- category leaves the indicator alone. Mainline and Mists have no ranks: there
-- the exact-ID filter stays the only check and no spell name is looked up.
-- The ranked path closes with an instruction budget for a repeated unrelated
-- cooldown event (one table read on top of the exact-ID filter).
--
-- Plain Lua 5.1: repo root and client flavor (Mainline, Vanilla, TBC, Mists,
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Vanilla"
local ranked = flavor == "Vanilla" or flavor == "TBC" or flavor == "Forever"

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local now = 1000
GetTime = function() return now end
GetTimePreciseSec = nil
issecretvalue = function() return false end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }

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
function Region:Clear() end
function Region:GetHeight() return 18 end
function Region:SetDrawSwipe() end
function Region:SetDrawEdge() end
function Region:SetDrawBling() end
function Region:SetHideCountdownNumbers() end
function Region:SetCooldownFromDurationObject(duration)
    Check(type(duration) == "table" and duration.native == true,
        "a Cooldown frame was armed with something that is not a native Duration object")
end
CreateFrame = function(kind, name)
    local frame = setmetatable({ kind = kind, scripts = {}, events = {} }, Region)
    if name then named[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")
C_SpellBook = { IsSpellKnownOrInSpellBook = function() return false end }
MSUF_ShouldUseMSUFCastbar = function() return true end
MSUF_DB = { general = { kickReadyShowTarget = true, kickReadyStyle = "box" } }

-- Spell data the fixture knows: name and cooldown category per spell ID.
local SPELLS = {
    [1766] = { "Kick", "kick" }, [1769] = { "Kick", "kick" },
    [6552] = { "Pummel", "pummel" }, [6554] = { "Pummel", "pummel" },
    [8042] = { "Earth Shock", "shock" }, [8044] = { "Earth Shock", "shock" },
    [8050] = { "Flame Shock", "shock" }, [8056] = { "Frost Shock", "shock" },
    [2098] = { "Eviscerate" }, [78] = { "Heroic Strike" }, [403] = { "Lightning Bolt" },
}
local categoryCD = {}
local uncached = {}
local nameReads = 0
local function CategoryEntry(spellID)
    local spell = SPELLS[spellID]
    return categoryCD[(spell and spell[2]) or spellID]
end
local withDurationAPI = flavor == "Mainline" or flavor == "Forever"
C_Spell = {
    GetSpellCooldown = function(spellID)
        local entry = CategoryEntry(spellID)
        if not entry then return { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 } end
        return { startTime = entry.start, duration = entry.duration, isEnabled = true, isActive = true, modRate = 1 }
    end,
    GetSpellName = function(spellID)
        nameReads = nameReads + 1
        if uncached[spellID] then
            uncached[spellID] = nil
            return nil
        end
        local spell = SPELLS[spellID]
        return spell and spell[1]
    end,
}
if withDurationAPI then
    C_Spell.GetSpellCooldownDuration = function(spellID, ignoreGCD)
        Check(ignoreGCD == true, "the Duration API was asked to include the global cooldown")
        local entry = CategoryEntry(spellID)
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
    IsMists = flavor == "Mists",
    IsClassic = flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists",
}

local target, eventFrame
local function Load(classToken)
    UnitClass = function() return classToken, classToken end
    local learned = ({ ROGUE = 1766, WARRIOR = 6552, SHAMAN = 8042 })[classToken]
    C_SpellBook.IsSpellKnownOrInSpellBook = function(spellID) return spellID == learned end
    categoryCD = {}
    named = {}
    local ns = { Client = client, ExportPublic = function(name, value) _G[name] = value end,
        Scheduler = { ScheduleAfter = function() return true end, CancelScheduled = function() return false end } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))("MSUF", ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))("MSUF", ns)
    eventFrame = Check(named.MSUF_InterruptReady_EventFrame, "interrupt-ready event frame is missing")
    target = { unit = "target", statusBar = CreateFrame("StatusBar"), MSUF_castActive = true,
        isNotInterruptible = false, MSUF_kickInterruptibleConfirmed = true }
    MSUF_TargetCastbar = target
    return _G.MSUF_KickReady_GetSpellID()
end

local function Ready()
    local color = Check(target.kickReadyBox and target.kickReadyBox.fill.color, "no indicator box was painted")
    return color[1] == 0 and color[2] == 1
end
local function Event(spellID)
    now = now + 0.016
    eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", spellID, nil)
end
-- The hostile cast starts while the interrupt is ready, then the player casts
-- `castID`. Returns whether the indicator still shows "ready" afterwards.
local function CastAndPaint(classToken, castID)
    local tracked = Load(classToken)
    now = now + 0.016
    _G.MSUF_KickReady_RefreshFrame(target)
    Check(Ready() == true, classToken .. ": the interrupt is painted as not ready before anything was cast")
    local spell = SPELLS[castID]
    if spell and spell[2] then categoryCD[spell[2]] = { start = now, duration = 10 } end
    Event(castID)
    return Ready(), tracked
end

if ranked then
    local cases = {
        { "ROGUE", 1769, "Kick rank 4" },
        { "WARRIOR", 6554, "Pummel rank 2" },
        { "SHAMAN", 8044, "Earth Shock rank 2" },
        { "SHAMAN", 8050, "Flame Shock (shared shock cooldown)" },
        { "SHAMAN", 8056, "Frost Shock (shared shock cooldown)" },
    }
    for _, case in ipairs(cases) do
        local ready, tracked = CastAndPaint(case[1], case[2])
        Check(ready == false, case[3] .. " started the cooldown of tracked spell " .. tostring(tracked)
            .. ", but the indicator still shows ready")
        Check(_G.MSUF_KickReady_IsReady() == false, case[3] .. ": the interrupt reports ready while on cooldown")
    end

    -- A spell outside the category neither repaints nor counts as a rank.
    Load("ROGUE")
    now = now + 0.016
    _G.MSUF_KickReady_RefreshFrame(target)
    categoryCD.kick = { start = now, duration = 10 } -- started by a cast the client has not reported yet
    Event(2098)
    Check(Ready() == true, "an unrelated spell (Eviscerate) repainted the indicator")

    -- Lazy-loaded names: an answer missing a name is not remembered as "no match".
    Load("ROGUE")
    now = now + 0.016
    _G.MSUF_KickReady_RefreshFrame(target)
    uncached[1766] = true
    categoryCD.kick = { start = now, duration = 10 }
    Event(1769)
    Event(1769)
    Check(Ready() == false, "a Kick rank whose tracked name was not cached at the first event never matched again")

    -- Budget: a repeated unrelated cooldown event costs the exact-ID filter
    -- plus one cached table read (54 measured, 16 over the exact-ID filter
    -- alone). Frozen 2026-10-05 at the measured cost + 2 %.
    local BUDGET = 55
    for _ = 1, 50 do Event(2098) end
    local reads = nameReads
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1)
    for _ = 1, 200 do eventFrame.scripts.OnEvent(eventFrame, "SPELL_UPDATE_COOLDOWN", 2098, nil) end
    debug.sethook()
    local instructions = ticks / 200
    if arg[3] == "print" then print(string.format("unrelated ranked cooldown event %.1f instructions", instructions)) end
    Check(nameReads == reads, "a repeated unrelated cooldown event looked the spell name up again")
    Check(instructions <= BUDGET, string.format(
        "a repeated unrelated cooldown event costs %.1f instructions (budget %d)", instructions, BUDGET))
else
    -- Mainline and Mists: one ID per spell, so the exact filter stays alone.
    local tracked = Load("ROGUE")
    now = now + 0.016
    _G.MSUF_KickReady_RefreshFrame(target)
    nameReads = 0
    Event(2098)
    Check(nameReads == 0, "an unrelated cooldown event looked up a spell name on a client without ranks")
    Check(Ready() == true, "an unrelated spell repainted the indicator")
    categoryCD.kick = { start = now, duration = 10 }
    Event(tracked)
    Check(Ready() == false, "the tracked interrupt's own cooldown event did not repaint the indicator")
end

print("interrupt_ready_rank_cooldown_smoke: " .. flavor .. " OK")
