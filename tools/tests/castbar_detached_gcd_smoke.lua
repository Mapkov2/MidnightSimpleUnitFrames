local root = assert(arg[1], "root required")
-- Client contracts this fixture holds the module to:
-- * PLAYER_REGEN_DISABLED is delivered before InCombatLockdown() turns true;
--   UnitAffectingCombat("player") already answers true.
-- * StatusBar:SetTimerDuration binds the bar natively. The castbar runtime's
--   ClearTimer only drops Lua bookkeeping, so the last bound duration keeps
--   driving the fill: an expired GCD duration shows a full bar. SetValue is
--   honoured only while the bar is bound to nothing or to a reset duration.
-- * The bar needs the Duration API; WoW Forever additionally needs spell 61304.
local frames, timers, lockdown, affecting, casts = {}, {}, false, false, 0
local layoutWrites = 0
local LAYOUT = { SetSize = true, SetPoint = true, ClearAllPoints = true, SetFont = true, SetAlpha = true }
local Region = {}
Region.__index = function(self, key)
    local method = Region[key]
    if method and LAYOUT[key] then
        return function(...) layoutWrites = layoutWrites + 1; return method(...) end
    end
    return method
end
local function Frame(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, events = {}, scripts = {}, shown = true }, Region)
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end
for _, key in ipairs({"SetFrameStrata", "EnableMouse", "SetAllPoints", "SetStatusBarTexture", "SetStatusBarColor",
    "SetMinMaxValues", "SetColorTexture", "SetTexture", "SetTexCoord", "SetTextColor"}) do Region[key] = function() end end
function Region.SetSize(self, w, h) self.width, self.height = w, h end
function Region.SetPoint(self, ...) self.point = {...} end
function Region.ClearAllPoints(self) self.point = nil end
function Region.SetAlpha(self, a) self.alpha = a end
function Region.SetValue(self, v) self.value = v end
function Region.SetTimerDuration(self, duration) self.bound = duration end
-- What the client draws: a bound, non-reset duration owns the fill.
function Region.Displayed(self)
    local bound = self.bound
    if bound and not bound.isReset then return bound.expired and 1 or 0.5 end
    return self.value or 0
end
function Region.SetText(self, v) self.text = v end
function Region.SetFont(self, ...) self.font = {...} end
function Region.SetShown(self, v) self.shown = v and true or false end
function Region.IsShown(self) return self.shown end
function Region.Show(self) self.shown = true end
function Region.Hide(self) self.shown = false end
function Region.CreateTexture(self) return Frame("Texture", nil, self) end
function Region.CreateFontString(self) return Frame("FontString", nil, self) end
function Region.RegisterEvent(self, e) self.events[e] = true end
function Region.RegisterUnitEvent(self, e) self.events[e] = true end
function Region.UnregisterEvent(self, e) self.events[e] = nil end
function Region.SetScript(self, k, v) self.scripts[k] = v end

local duration
local function Load(client, spellAPI)
    frames, timers, casts = {}, {}, 0
    lockdown, affecting = false, false
    MSUF_DetachedGCDBar, MSUF_GCDBarDriver = nil, nil
    CreateFrame = Frame
    UIParent = Frame("Frame")
    GameFontHighlightSmall = { GetFont = function() error("the detached bar must use the castbar font") end }
    MSUF_GetFontPath = function() return "castbar-font" end
    MSUF_GetFontFlags = function() return "THICKOUTLINE" end
    InCombatLockdown = function() return lockdown end
    UnitAffectingCombat = function(unit) return unit == "player" and affecting end
    MSUF_Castbar_PlainNumber = function(v) return type(v) == "number" and v or nil end
    MSUF_DB = { general = { showGCDBar = true, gcdBarDetached = true, gcdBarIdle = false } }
    duration = { GetRemainingDuration = function() return .9 end }
    C_Spell = spellAPI
    C_DurationUtil = { CreateDuration = function()
        return { Reset = function(self) self.isReset = true end }
    end }
    -- The finish deadline goes through Kernel/MSUF_Scheduler.lua; a plain GCD
    -- never polls and never builds a C_Timer handle.
    C_Timer = { NewTimer = function() error("the GCD bar must not create a C_Timer handle") end,
        NewTicker = function() error("plain GCD must not poll") end }
    local scheduler = {
        ScheduleAfter = function(key, delay, fn)
            timers[#timers + 1] = { delay = delay, fn = fn, key = key }
            return true
        end,
        CancelScheduled = function() return false end,
    }
    MSUF_CastbarRuntime = { RetainDuration = function(_, _, d) return d end,
        ApplyTimer = function(_, bar, d) assert(d == duration); bar:SetTimerDuration(d); casts = casts + 1; return true end,
        BindNativeTimeText = function(_, f, d) f.timeBound = d end,
        DisableNativeTimeText = function(_, f) f.timeBound = nil end,
        -- The real ClearTimer keeps the native binding.
        ClearTimer = function() return false end }
    local mover
    MSUF_EditModeAPI = { RegisterElement = function(_, spec) mover = spec; return true end }
    MSUF_PlayerCastbar = Frame("Frame")
    MSUF_PlayerCastbar.shown = false
    MSUF_PlayerCastbar.MSUF_castActive = true
    local ns = { Client = client, ExportPublic = function(k, v) _G[k] = v end, Scheduler = scheduler }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarGCD.lua"))("MSUF", ns)
    return MSUF_GCDBarDriver, function() return mover end
end
local function LiveSpellAPI(extra)
    local api = { GetSpellInfo = function(id) return { name = "Spell", iconID = id, castTime = 0 } end,
        GetSpellCooldown = function() return { isActive = true } end,
        GetSpellCooldownDuration = function(id) assert(id == 61304); return duration end }
    for key, value in pairs(extra or {}) do api[key] = value end
    return api
end

-- 1. Midnight: the separate bar animates, finishes empty and follows combat.
do
    local driver, Mover = Load({ IsForever = false }, LiveSpellAPI())
    local function Event(e, id)
        if e == "PLAYER_REGEN_DISABLED" then affecting = true end
        if e == "PLAYER_REGEN_ENABLED" then lockdown, affecting = false, false end
        driver.scripts.OnEvent(driver, e, "player", nil, id)
        if e == "PLAYER_REGEN_DISABLED" then lockdown = true end
    end
    Event("PLAYER_ENTERING_WORLD")
    assert(driver.events.UNIT_SPELLCAST_SUCCEEDED and not driver.events.PLAYER_REGEN_DISABLED)
    local mover = Mover()
    assert(mover and mover.isEnabled() and not MSUF_DetachedGCDBar.shown)
    local bar = MSUF_DetachedGCDBar
    assert(bar.castText.font[1] == "castbar-font" and bar.castText.font[3] == "THICKOUTLINE",
        "the separate GCD bar ignores the castbar font")
    layoutWrites = 0
    Event("UNIT_SPELLCAST_SUCCEEDED", 123)
    assert(casts == 1 and bar.shown and bar.statusBar.bound == duration and bar.timeBound == duration,
        "detached GCD did not animate during a real player cast")
    assert(not MSUF_PlayerCastbar.shown and #timers == 1, "separate GCD borrowed player frame or duplicated timers")
    duration.expired = true
    timers[1].fn()
    assert(not bar.shown and bar.statusBar.bound ~= duration, "the finished GCD still drives the separate bar")
    assert(layoutWrites == 0, "an instant cast relaid the separate GCD bar out (" .. layoutWrites .. " writes)")
    MSUF_DB.general.gcdBarIdle = true; MSUF_GCDBar_RefreshLayout()
    assert(bar.shown and bar.statusBar.value == 0, "idle background missing")
    assert(bar.statusBar:Displayed() == 0, "the idle background still shows the finished GCD as a full bar")
    -- A second GCD with the idle background on also ends empty.
    duration.expired = nil
    Event("UNIT_SPELLCAST_SUCCEEDED", 123)
    duration.expired = true
    timers[#timers].fn()
    assert(bar.shown and bar.statusBar:Displayed() == 0, "the idle bar stays full after a GCD")
    mover.setPosition({ x = 71, y = -92 }); assert(MSUF_DB.general.gcdBarX == 71 and bar.point[4] == 71)
    mover.onSessionChanged(true); assert(bar.castText.text == "GCD" and bar.statusBar.value == .65)
    assert(bar.statusBar:Displayed() == .65, "the Edit Mode sample is hidden by a stale timer binding")
    mover.onSessionChanged(false); assert(bar.castText.text == "")
    MSUF_DB.general.gcdBarCombatOnly = true; MSUF_GCDBar_RefreshLayout()
    assert(not bar.shown and driver.events.PLAYER_REGEN_DISABLED)
    Event("PLAYER_REGEN_DISABLED")
    assert(bar.shown, "the combat-only idle bar did not appear at the pull")
    Event("PLAYER_REGEN_ENABLED")
    assert(not bar.shown, "the combat-only idle bar stayed after combat")
    Event("PLAYER_REGEN_DISABLED")
    assert(bar.shown)
    MSUF_SetGCDBarEnabled(false)
    assert(not bar.shown and not driver.events.UNIT_SPELLCAST_SUCCEEDED and not driver.events.PLAYER_REGEN_DISABLED)
    assert(not driver.scripts.OnUpdate, "GCD introduced a per-frame update")
end

-- 2. Clients that cannot drive the bar keep an imported separate bar away.
local function CheckUnsupported(label, client, spellAPI)
    local driver, Mover = Load(client, spellAPI)
    MSUF_DB.general.gcdBarIdle = true
    driver.scripts.OnEvent(driver, "PLAYER_ENTERING_WORLD")
    assert(not (MSUF_DetachedGCDBar and MSUF_DetachedGCDBar.shown), label .. ": an empty separate GCD bar is shown")
    local mover = Mover()
    assert(not (mover and mover.isEnabled()), label .. ": the separate GCD bar has an Edit Mode mover")
    return driver
end
do
    local driver = CheckUnsupported("Forever without the GCD spell", { IsForever = true },
        LiveSpellAPI({ DoesSpellExist = function(id) assert(id == 61304); return false end }))
    assert(not driver.events.UNIT_SPELLCAST_SUCCEEDED, "Forever without the GCD spell listens for casts")
    assert(MSUF_GCDBar_IsSupported() == false, "Forever without the GCD spell claims support")
end
CheckUnsupported("client without the Duration API", { IsForever = false, IsClassic = true },
    { GetSpellInfo = function(id) return { name = "Spell", iconID = id, castTime = 0 } end,
      GetSpellCooldown = function() return { isActive = true } end })
do
    -- The spell-data answer is read once, not on every instant cast.
    local lookups = 0
    local driver = Load({ IsForever = true }, LiveSpellAPI({ DoesSpellExist = function() lookups = lookups + 1; return true end }))
    driver.scripts.OnEvent(driver, "PLAYER_ENTERING_WORLD")
    for _ = 1, 5 do
        driver.scripts.OnEvent(driver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 123)
        if timers[#timers] then timers[#timers].fn() end
    end
    assert(MSUF_GCDBar_IsSupported() == true, "Forever with the GCD spell must arm the bar")
    assert(MSUF_DetachedGCDBar and casts == 5, "Forever with the GCD spell did not run the separate bar")
    assert(lookups == 1, "the Forever spell data was asked " .. lookups .. " times instead of once")
end

-- 3. The castbar page offers the section where the runtime can fill it and
--    greys the separate-bar controls with their two switches.
do
    local f = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", "rb"))
    local page = f:read("*a"):gsub("\r\n", "\n"); f:close()
    local probe = assert(page:match("\nlocal function GCDBarSupported%(%)\n(.-)\nend\n"), "castbar page lost its GCD probe")
    assert(probe:find("MSUF_GCDBar_IsSupported", 1, true), "the castbar page probe ignores the runtime's GCD answer")
    local sync = assert(page:match("\n    syncGCD = function%(%)\n(.-)\n    end\n"), "castbar page lost its GCD sync")
    assert(sync:find("SetControlsEnabled(detachedControls, master and ReadGBool(\"gcdBarDetached\", false))", 1, true)
        and sync:find("SetControlsEnabled(masterControls, master)", 1, true),
        "separate GCD controls are not greyed with their switches")
    for _, key in ipairs({ "gcdBarIdle", "gcdBarCombatOnly", "gcdBarWidth", "gcdBarHeight", "gcdBarX", "gcdBarY", "gcdBarOpacity" }) do
        assert(page:find('"' .. key .. '"', 1, true), "castbar page lost " .. key)
    end
    assert(page:find('for _, key in ipairs({ "gcdBarIdle", "gcdBarCombatOnly", "gcdBarWidth", "gcdBarHeight", "gcdBarX", "gcdBarY", "gcdBarOpacity" }) do', 1, true),
        "the greyed set no longer lists every separate-bar control")
end
print("castbar_detached_gcd_smoke: ok")
