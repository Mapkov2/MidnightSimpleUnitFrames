-- interrupt_ready_mists_hunter_smoke.lua <repoRoot>
--
-- Mists Classic runs the 5.4 ruleset. Counter Shot (147362) is the hunter
-- interrupt for Beast Mastery and Survival. For Marksmanship, Silencing Shot
-- (34490) replaces Counter Shot and is no longer a talent (5.4 patch notes:
-- "Silencing Shot replaces Counter Shot for Marksmanship and is no longer a
-- talent"). Each specialization therefore has exactly one interrupt, and the
-- replaced spell is inactive: the fixture makes it report no cooldown, so an
-- indicator that reads it would claim "ready" while the real interrupt
-- recovers. The spell book answers "known" for both spells on Marksmanship
-- (an overridden base spell can stay in the book), so the choice must not
-- hang on spell-book membership.
--
-- The matrix runs with C_Spell.GetSpellCooldownDuration (the 5.5.4 client,
-- upstream/classic SpellDocumentation.lua) and without it (the plain
-- C_Spell.GetSpellCooldown fallback). A specialization change re-resolves the
-- spell through PLAYER_SPECIALIZATION_CHANGED, without a reload. TBC keeps
-- Silencing Shot alone.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local COUNTER_SHOT, SILENCING_SHOT = 147362, 34490
local SPECS = {
    { id = 253, name = "Beast Mastery", active = COUNTER_SHOT, replaced = SILENCING_SHOT,
        known = { [COUNTER_SHOT] = true } },
    { id = 254, name = "Marksmanship", active = SILENCING_SHOT, replaced = COUNTER_SHOT,
        known = { [COUNTER_SHOT] = true, [SILENCING_SHOT] = true } },
    { id = 255, name = "Survival", active = COUNTER_SHOT, replaced = SILENCING_SHOT,
        known = { [COUNTER_SHOT] = true } },
}

local mode = "?"
local function Check(condition, message)
    if not condition then error(mode .. ": " .. message, 2) end
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
CreateFrame = function(kind, name)
    local frame = setmetatable({ kind = kind, scripts = {}, events = {} }, Region)
    if name then named[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")
UnitClass = function() return "Hunter", "HUNTER" end
MSUF_ShouldUseMSUFCastbar = function() return true end
MSUF_DB = { general = { kickReadyShowTarget = true, kickReadyStyle = "box" } }

local known, specID, cooldowns = {}, nil, {}
C_SpellBook = { IsSpellKnownOrInSpellBook = function(spellID) return known[spellID] == true end }
C_SpecializationInfo = {
    GetSpecialization = function() return specID and 1 or nil end,
    GetSpecializationInfo = function(index) Check(index == 1, "unexpected specialization index"); return specID end,
}

-- Every spell's cooldown is its own; the inactive replaced spell has none.
local function Finish(spellID)
    local entry = cooldowns[spellID]
    return entry and entry.duration > 1.5 and entry.start + entry.duration or 0
end
local function InstallSpellAPI(withDuration)
    C_Spell = {
        GetSpellCooldown = function(spellID)
            local entry = cooldowns[spellID]
            if not entry then return { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 } end
            return { startTime = entry.start, duration = entry.duration, isEnabled = true, isActive = true, modRate = 1 }
        end,
    }
    if withDuration then
        C_Spell.GetSpellCooldownDuration = function(spellID, ignoreGCD)
            Check(ignoreGCD == true, "the Duration API was asked to include the global cooldown")
            local finish = Finish(spellID)
            return { GetRemainingDuration = function() local left = finish - now; return left > 0 and left or 0 end,
                GetEndTime = function() return finish end,
                IsZero = function() return finish - now <= 0 end }
        end
    end
end

local function Load(flavor)
    local client = { IsRetail = false, IsForever = false, IsVanilla = false, IsTBC = flavor == "TBC",
        IsMists = flavor == "Mists", IsClassic = true }
    local ns = { Client = client, ExportPublic = function(name, value) _G[name] = value end,
        Scheduler = { ScheduleAfter = function() return true end, CancelScheduled = function() return false end } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))("MSUF", ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))("MSUF", ns)
    return _G.MSUF_KickReady_GetSpellID()
end

local function ExpectSpec(spec)
    local label = spec.name

    -- Both off cooldown: ready.
    cooldowns = {}
    now = now + 1
    Check(_G.MSUF_KickReady_IsReady() == true, label .. ": the interrupt off cooldown does not read ready")

    -- The active interrupt recovers; the replaced spell reports no cooldown.
    cooldowns = { [spec.active] = { start = now, duration = 24 } }
    now = now + 1
    Check(_G.MSUF_KickReady_IsReady() == false,
        label .. ": reads ready while its interrupt recovers (the replaced spell has no cooldown)")

    -- The replaced spell on a cooldown of its own must not hide a ready interrupt.
    cooldowns = { [spec.replaced] = { start = now, duration = 24 } }
    now = now + 1
    Check(_G.MSUF_KickReady_IsReady() == true, label .. ": a cooldown on the replaced spell hid a ready interrupt")

    -- The active interrupt comes back: ready again.
    cooldowns = { [spec.active] = { start = now - 30, duration = 24 } }
    now = now + 1
    Check(_G.MSUF_KickReady_IsReady() == true, label .. ": does not read ready once its interrupt has recovered")

    Check(_G.MSUF_KickReady_GetSpellID() == spec.active,
        label .. " hunters must track spell " .. spec.active .. ", got " .. tostring(_G.MSUF_KickReady_GetSpellID()))
end

for _, withDuration in ipairs({ true, false }) do
    mode = withDuration and "Mists (GetSpellCooldownDuration)" or "Mists (GetSpellCooldown only)"
    InstallSpellAPI(withDuration)

    -- A fresh load per specialization (login with that specialization).
    for _, spec in ipairs(SPECS) do
        specID, known, cooldowns = spec.id, spec.known, {}
        Load("Mists")
        ExpectSpec(spec)
    end

    -- One load, specialization changes in place (cold path, no reload).
    specID, known, cooldowns = SPECS[1].id, SPECS[1].known, {}
    Load("Mists")
    _G.MSUF_KickReady_RefreshAll()
    local eventFrame = Check(named.MSUF_InterruptReady_EventFrame, "interrupt-ready event frame is missing")
    Check(eventFrame.events.PLAYER_SPECIALIZATION_CHANGED == true, "the specialization change is not watched")
    for _, index in ipairs({ 2, 3, 2, 1 }) do
        local spec = SPECS[index]
        specID, known = spec.id, spec.known
        eventFrame.scripts.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
        ExpectSpec(spec)
    end
end

-- TBC keeps its table: Silencing Shot alone.
mode = "TBC"
InstallSpellAPI(false)
specID, known, cooldowns = nil, { [SILENCING_SHOT] = true }, {}
Check(Load("TBC") == SILENCING_SHOT, "TBC hunters no longer track Silencing Shot")

print("interrupt_ready_mists_hunter_smoke: OK")
