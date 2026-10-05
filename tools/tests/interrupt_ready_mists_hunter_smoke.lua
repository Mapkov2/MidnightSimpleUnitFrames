-- interrupt_ready_mists_hunter_smoke.lua <repoRoot>
--
-- Mists Classic runs the 5.4 ruleset: Counter Shot (147362) is every hunter
-- specialization's baseline interrupt, and Silencing Shot (34490) is a talent
-- any specialization can take. The interrupt-ready indicator must track
-- Counter Shot for Beast Mastery, Marksmanship and Survival alike, and join
-- Silencing Shot only while the spell book has it (the indicator is ready
-- when either interrupt is). TBC keeps Silencing Shot alone.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
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

local known, specID, cooldowns = {}, 253, {}
C_SpellBook = { IsSpellKnownOrInSpellBook = function(spellID) return known[spellID] == true end }
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return specID end,
}
C_Spell = {
    GetSpellCooldown = function(spellID)
        local entry = cooldowns[spellID]
        if not entry then return { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 } end
        return { startTime = entry.start, duration = entry.duration, isEnabled = true, isActive = true, modRate = 1 }
    end,
}

local function Load(flavor)
    local client = { IsRetail = false, IsForever = false, IsVanilla = false, IsTBC = flavor == "TBC",
        IsMists = flavor == "Mists", IsClassic = true }
    local ns = { Client = client, ExportPublic = function(name, value) _G[name] = value end,
        Scheduler = { ScheduleAfter = function() return true end, CancelScheduled = function() return false end } }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))("MSUF", ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))("MSUF", ns)
    return _G.MSUF_KickReady_GetSpellID()
end

local SPEC_NAMES = { [253] = "Beast Mastery", [254] = "Marksmanship", [255] = "Survival" }
for _, spec in ipairs({ 253, 254, 255 }) do
    specID, known, cooldowns = spec, {}, {}
    Check(Load("Mists") == 147362, "Mists " .. SPEC_NAMES[spec] .. " hunters do not track Counter Shot")
    now = now + 1
    Check(_G.MSUF_KickReady_IsReady() == true, "Counter Shot off cooldown is not ready")
    cooldowns[147362] = { start = now, duration = 24 }
    now = now + 1
    Check(_G.MSUF_KickReady_IsReady() == false, "Counter Shot on cooldown still reads ready")
end

-- A talented Silencing Shot joins the union while Counter Shot recovers.
specID, known, cooldowns = 254, { [34490] = true }, {}
Load("Mists")
cooldowns[147362] = { start = now, duration = 24 }
now = now + 1
Check(_G.MSUF_KickReady_IsReady() == true, "a ready talented Silencing Shot was ignored while Counter Shot recovers")
cooldowns[34490] = { start = now, duration = 20 }
now = now + 1
Check(_G.MSUF_KickReady_IsReady() == false, "both hunter interrupts on cooldown still read ready")

-- TBC keeps its table: Silencing Shot alone.
specID, known, cooldowns = nil, {}, {}
Check(Load("TBC") == 34490, "TBC hunters no longer track Silencing Shot")

print("interrupt_ready_mists_hunter_smoke: OK")
