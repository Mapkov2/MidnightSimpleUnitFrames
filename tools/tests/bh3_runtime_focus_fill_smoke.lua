-- Probe: Focus Interrupt Tracker icon readiness repaint under kickReadyStyle "fill".
-- Loads the real Castbars/MSUF_CastbarUtils.lua + Castbars/MSUF_InterruptReady.lua.
-- lua51 focuskick_fill_probe.lua <repoRoot>
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local KICK = 1766
local frameStamp = 100
local events, eventHandler = {}, nil
local wakeSets = 0

local function Run(style)
    for k in pairs(events) do events[k] = nil end
    wakeSets = 0
    _G.MSUF_DB = { general = {
        kickReadyShowTarget = true, kickReadyShowFocus = false, kickReadyShowBoss = false, kickReadyShowArena = false,
        enableFocusKickIcon = true, kickReadyStyle = style,
    } }
    _G.MSUF_EnsureDB = function() end
    _G.UnitClass = function() return "Rogue", "ROGUE" end
    _G.C_SpecializationInfo = { GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 259 end }
    _G.C_SpellBook = { IsSpellKnown = function(id) return id == KICK end }
    _G.GetTime = function() return frameStamp end
    _G.issecretvalue = function() return false end
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGBA = function() return r, g, b, a end } end
    _G.C_CurveUtil = {}
    _G.C_Timer = { After = function() end }
    local kick = { remaining = 8, endTime = 108 }
    function kick.GetRemainingDuration() return kick.remaining end
    function kick.IsZero() return kick.remaining <= 0 end
    function kick.GetEndTime() return kick.endTime end
    _G.C_Spell = { GetSpellCooldownDuration = function(id) return id == KICK and kick or nil end }
    _G.CreateFrame = function(frameType)
        if frameType == "Cooldown" then
            local w = {}
            for _, m in ipairs({ "Show", "SetSize", "SetAlpha", "SetDrawSwipe", "SetDrawEdge", "SetDrawBling", "SetHideCountdownNumbers", "Clear" }) do w[m] = function() end end
            function w.SetCooldownFromDurationObject() wakeSets = wakeSets + 1 end
            function w.SetScript(_, s, cb) if s == "OnCooldownDone" then w.done = cb end end
            return w
        end
        local f = {}
        f.RegisterEvent = function(_, e) events[e] = true end
        f.UnregisterEvent = function(_, e) events[e] = nil end
        f.UnregisterAllEvents = function() for e in pairs(events) do events[e] = nil end end
        f.SetScript = function(_, s, cb) if s == "OnEvent" then eventHandler = cb end end
        return f
    end
    local ns = { Public = {} }
    ns.ExportPublic = function(name, value) _G[name] = value; ns.Public[(name:gsub("^MSUF_", ""))] = value; return value end
    ns.Scheduler = { ScheduleAfter = function() end }
    ns.Util = { InCombat = function() return false end }
    _G.geterrorhandler = function() return print end
    _G.MSUF_ApplyCastbarOutline = function() end
    for _, file in ipairs({ "Kernel/MSUF_Boundary.lua", "Castbars/MSUF_CastbarUtils.lua", "Castbars/MSUF_InterruptReady.lua" }) do
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. file))("MidnightSimpleUnitFrames", ns)
    end
    local iconRepaints = 0
    _G.MSUF_FocusKick_RefreshReadyColor = function() iconRepaints = iconRepaints + 1 end

    -- The focus castbar (suppressed by the tracker, alpha 0) runs a cast.
    local focusBar = { unit = "focus", MSUF_castActive = true, statusBar = {} }
    _G.MSUF_FocusCastbar = focusBar
    _G.MSUF_KickReady_RefreshAll()                 -- unit-frame spawn
    _G.MSUF_KickReady_RefreshFrame(focusBar, nil)  -- cast start (driver ApplyColor path)
    local registered = events.SPELL_UPDATE_COOLDOWN == true
    local wakes = wakeSets
    -- Kick comes off cooldown mid-cast.
    kick.remaining = 0
    frameStamp = frameStamp + 1
    if events.SPELL_UPDATE_COOLDOWN then eventHandler(nil, "SPELL_UPDATE_COOLDOWN", KICK, KICK) end
    assert(registered and wakes >= 1 and iconRepaints >= 1, "focus tracker readiness lifecycle absent for " .. style)
    print(string.format("style=%-6s SPELL_UPDATE_COOLDOWN registered=%s  wake frames armed=%d  focus icon repaints=%d  (expected: true, >=1, 1)",
        style, tostring(registered), wakes, iconRepaints))
end

Run("border")
Run("fill")
