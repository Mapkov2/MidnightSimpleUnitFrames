-- forever_castbar_client_data_smoke.lua
-- WoW Forever is a Mainline client with Classic Era spell data and a second
-- Blizzard player castbar. This smoke pins the castbar files that branch on it:
--   Bridge:     GamepadPlayerCastingBarFrame is suppressed and restored with
--               PlayerCastingBarFrame, and a client without it (every other
--               client) still owns PlayerCastingBarFrame alone.
--   Interrupt:  Forever resolves the Vanilla interrupt table (no Paladin or
--               Hunter entry); Retail, Vanilla and a harness without
--               MSUF.Client keep their own tables.
--   GCD bar:    Forever registers UNIT_SPELLCAST_SUCCEEDED only while the client
--               knows the dummy spell 61304; every other client registers it
--               unconditionally, as before.
--   Ticks:      Forever and Classic Era use per-rank Era tick counts (Mind Flay
--               3, Hellfire 15); Retail, TBC and Mists keep the Retail table and
--               the 12-tick cap.
--   Contract:   the client fact is read once at file load in each gated file.
-- Run with Lua 5.1 and the repo root as arg 1.
local root = assert(arg[1], "repo root required"):gsub("\\", "/")

local BRIDGE_FILE = "MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Bridge.lua"
local INTERRUPT_FILE = "MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"
local GCD_FILE = "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarGCD.lua"
local TICKS_FILE = "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarChannelTicks.lua"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local FOREVER = { IsForever = true, IsRetail = true, IsClassic = false, Family = "Mainline", Flavor = "Mainline" }
local RETAIL = { IsForever = false, IsRetail = true, IsClassic = false, Family = "Mainline", Flavor = "Mainline" }
local VANILLA = { IsForever = false, IsRetail = false, IsClassic = true, IsVanilla = true, Family = "Classic", Flavor = "Vanilla" }
local TBC = { IsForever = false, IsRetail = false, IsClassic = true, IsTBC = true, Family = "Classic", Flavor = "TBC" }
local MISTS = { IsForever = false, IsRetail = false, IsClassic = true, IsMists = true, Family = "Classic", Flavor = "Mists" }

local function NewFrame(name)
    local frame = { name = name, events = {}, unitEvents = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
    function frame:SetScript(script, fn) if script == "OnEvent" then self.onEvent = fn end end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    return frame
end

local created
local function InstallCommonGlobals()
    created = {}
    _G.CreateFrame = function(_, name)
        local frame = NewFrame(name)
        created[#created + 1] = frame
        return frame
    end
    _G.issecretvalue = function() return false end
    _G.InCombatLockdown = function() return false end
    _G.C_Timer = { After = function() end, NewTimer = function() return {} end, NewTicker = function() return {} end }
    _G.GetTime = function() return 100 end
end

local function Namespace(client)
    return {
        Client = client,
        ExportPublic = function(name, value) _G[name] = value; return value end,
    }
end

-- Bridge ----------------------------------------------------------------------
local function NewCastbar(name)
    local bar = NewFrame(name)
    bar.unit, bar.showTradeSkills, bar.showShield, bar.shown = "player", true, false, false
    bar.events.UNIT_SPELLCAST_START = true
    bar.setUnitCalls = {}
    function bar:HookScript(script, fn) if script == "OnShow" then self.onShowHook = fn end end
    function bar:Show() self.shown = true; if self.onShowHook then self.onShowHook(self) end end
    function bar:SetUnit(unit, showTradeSkills, showShield)
        self.setUnitCalls[#self.setUnitCalls + 1] = { unit = unit, showTradeSkills = showTradeSkills, showShield = showShield }
        if unit then self.events.UNIT_SPELLCAST_START = true end
    end
    return bar
end

local backend
local function LoadBridge(withGamepad)
    InstallCommonGlobals()
    for _, name in ipairs({ "MSUF_IsCastbarEnabledForUnit", "MSUF_IsCastTimeEnabled", "MSUF_AreAnyCastbarsEnabled",
        "MSUF_Castbars_ForceHideAll", "MSUF_Castbars_OnSettingsChanged", "MSUF_Castbars_RunNextFrame",
        "MSUF_RegisterModule", "MSUF_EnsureDB" }) do
        _G[name] = nil
    end
    _G.MSUF_DB = { general = {} }
    _G.CastingBarFrame = nil
    _G.PlayerCastingBarFrame = NewCastbar("PlayerCastingBarFrame")
    _G.GamepadPlayerCastingBarFrame = withGamepad and NewCastbar("GamepadPlayerCastingBarFrame") or nil
    local ns = Namespace(nil)
    ns.MSUF_CastbarBackend = { Resolve = function() return backend end }
    assert(loadfile(root .. "/" .. BRIDGE_FILE))("MidnightSimpleUnitFrames", ns)
    return ns
end

local function CheckSuppressed(bar, label)
    Check(bar.shown == false, label .. ": " .. bar.name .. " must be hidden")
    Check(next(bar.events) == nil, label .. ": " .. bar.name .. " must lose its cast events")
    bar:Show()
    Check(bar.shown == false, label .. ": " .. bar.name .. " OnShow guard must hide it again")
end

local function CheckRestored(bar, label)
    local calls = bar.setUnitCalls
    Check(#calls == 2 and calls[1].unit == nil and calls[2].unit == "player"
        and calls[2].showTradeSkills == true and calls[2].showShield == false,
        label .. ": " .. bar.name .. " must be restored through SetUnit(nil) then SetUnit(\"player\", true, false)")
    bar:Show()
    Check(bar.shown == true, label .. ": " .. bar.name .. " OnShow guard must stand down once Blizzard owns it")
end

do -- (a) Forever: MSUF backend suppresses both player castbars, Blizzard restores both.
    backend = "MSUF"
    LoadBridge(true)
    Check(_G.MSUF_ApplyBlizzardCastbarOwnership() == true, "(a) ownership apply must find the castbars")
    CheckSuppressed(_G.PlayerCastingBarFrame, "(a)")
    CheckSuppressed(_G.GamepadPlayerCastingBarFrame, "(a)")
    backend = "BLIZZARD"
    _G.MSUF_ApplyBlizzardCastbarOwnership()
    CheckRestored(_G.PlayerCastingBarFrame, "(a)")
    CheckRestored(_G.GamepadPlayerCastingBarFrame, "(a)")
end

do -- (b) A client without the gamepad castbar keeps the single-frame path.
    backend = "MSUF"
    LoadBridge(false)
    Check(_G.MSUF_ApplyBlizzardCastbarOwnership() == true, "(b) ownership apply must find PlayerCastingBarFrame")
    CheckSuppressed(_G.PlayerCastingBarFrame, "(b)")
end

do -- (c) Combat defers ownership but still hides both bars.
    backend = "MSUF"
    LoadBridge(true)
    _G.InCombatLockdown = function() return true end
    Check(_G.MSUF_ApplyBlizzardCastbarOwnership() == false, "(c) combat apply must defer")
    Check(_G.GamepadPlayerCastingBarFrame.shown == false and _G.PlayerCastingBarFrame.shown == false,
        "(c) combat apply must hide both player castbars")
    Check(_G.GamepadPlayerCastingBarFrame.events.UNIT_SPELLCAST_START == true,
        "(c) combat apply must not unregister events")
end

-- Interrupt Ready ---------------------------------------------------------------
local function ResolveInterrupt(client, classToken)
    InstallCommonGlobals()
    _G.MSUF_KickReady_GetSpellID = nil
    _G.MSUF_DB = { general = { kickReadyShowTarget = true } }
    _G.MSUF_ShouldUseMSUFCastbar = function() return true end
    _G.UnitClass = function() return classToken, classToken end
    _G.C_SpellBook = { IsSpellKnownOrInSpellBook = function() return false end }
    _G.C_SpecializationInfo = nil
    assert(loadfile(root .. "/" .. INTERRUPT_FILE))("MidnightSimpleUnitFrames", Namespace(client))
    return _G.MSUF_KickReady_GetSpellID()
end

local ERA_INTERRUPTS = { WARRIOR = 6552, ROGUE = 1766, PRIEST = 15487, SHAMAN = 8042, MAGE = 2139,
    WARLOCK = 19647, DRUID = 16979 }
local RETAIL_INTERRUPTS = { WARRIOR = 6552, ROGUE = 1766, PRIEST = 15487, SHAMAN = 57994, MAGE = 2139,
    WARLOCK = 19647, DRUID = 106839, PALADIN = 96231, HUNTER = 147362 }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

for _, case in ipairs({
    { label = "(d) Forever", client = FOREVER, expected = ERA_INTERRUPTS },
    { label = "(d) Vanilla", client = VANILLA, expected = ERA_INTERRUPTS },
    { label = "(d) Retail", client = RETAIL, expected = RETAIL_INTERRUPTS },
    { label = "(d) no MSUF.Client", client = nil, expected = RETAIL_INTERRUPTS },
}) do
    for _, classToken in ipairs(CLASSES) do
        local spellID = ResolveInterrupt(case.client, classToken)
        Check(spellID == case.expected[classToken], string.format("%s %s: interrupt %s, expected %s",
            case.label, classToken, tostring(spellID), tostring(case.expected[classToken])))
    end
end

-- GCD bar -------------------------------------------------------------------------
local function GCDRegistered(client, spellAPI)
    InstallCommonGlobals()
    _G.MSUF_GCDBar_IsSupported = nil
    _G.MSUF_DB = { general = { showGCDBar = true } }
    _G.C_Spell = spellAPI
    assert(loadfile(root .. "/" .. GCD_FILE))("MidnightSimpleUnitFrames", Namespace(client))
    local driver
    for _, frame in ipairs(created) do
        if frame.name == "MSUF_GCDBarDriver" then driver = frame end
    end
    Check(driver and driver.onEvent and driver.events.PLAYER_ENTERING_WORLD, "GCD driver frame not created")
    driver.onEvent(driver, "PLAYER_ENTERING_WORLD")
    return driver.events.UNIT_SPELLCAST_SUCCEEDED == true, _G.MSUF_GCDBar_IsSupported(), driver
end

local missingDummy = { DoesSpellExist = function(spellID) return spellID ~= 61304 end }
local knownDummy = { DoesSpellExist = function(spellID) return spellID == 61304 end }

do
    local registered, supported, driver = GCDRegistered(FOREVER, missingDummy)
    Check(registered == false and supported == false, "(e) Forever without spell 61304 must not arm the GCD bar")
    _G.MSUF_SetGCDBarEnabled(true)
    Check(driver.events.UNIT_SPELLCAST_SUCCEEDED == nil and _G.MSUF_DB.general.showGCDBar == true,
        "(e) enabling on Forever without spell 61304 must keep the setting and register nothing")
    registered, supported = GCDRegistered(FOREVER, {})
    Check(registered == false and supported == false, "(e) Forever without C_Spell.DoesSpellExist must not arm the GCD bar")
    registered, supported = GCDRegistered(FOREVER, knownDummy)
    Check(registered == true and supported == true, "(e) Forever with spell 61304 must arm the GCD bar")
    for _, case in ipairs({ { "Retail", RETAIL }, { "Vanilla", VANILLA }, { "no MSUF.Client", nil } }) do
        registered, supported = GCDRegistered(case[2], missingDummy)
        Check(registered == true and supported == true, "(e) " .. case[1] .. " must keep the unconditional GCD registration")
    end
    registered = GCDRegistered(RETAIL, nil)
    Check(registered == true, "(e) Retail without C_Spell must keep the unconditional GCD registration")
end

-- Channel ticks -----------------------------------------------------------------
local function NewMarker()
    local marker = { shown = false }
    function marker:SetColorTexture() end
    function marker:SetAlpha() end
    function marker:SetWidth() end
    function marker:SetPoint() end
    function marker:ClearAllPoints() end
    function marker:Show() self.shown = true end
    function marker:Hide() self.shown = false end
    return marker
end

local function ShownTickMarkers(client, spellID)
    InstallCommonGlobals()
    _G.MSUF_PlayerChannelHasteMarkers_Update = nil
    _G.MSUF_DB = { general = { castbarShowChannelTicks = true }, player = { castbar = {} } }
    _G.IsPlayerSpell = function() return false end
    assert(loadfile(root .. "/" .. TICKS_FILE))("MidnightSimpleUnitFrames", Namespace(client))
    local statusBar = {}
    function statusBar:CreateTexture() return NewMarker() end
    function statusBar:GetWidth() return 200 end
    function statusBar:HookScript() end
    local frame = { unit = "player", MSUF_isChanneled = true, _msufActiveSpellID = spellID, statusBar = statusBar }
    _G.MSUF_PlayerChannelHasteMarkers_Update(frame, true)
    local shown = 0
    for _, marker in ipairs(frame._msufPlayerChannelHasteMarkers or {}) do
        if marker.shown then shown = shown + 1 end
    end
    return shown
end

for _, case in ipairs({
    -- Forever: markers = ticks - 1; unknown or Retail-only IDs keep the five-line default.
    { "Forever", FOREVER, 15407, 2 },   -- Mind Flay rank 1, 3 ticks
    { "Forever", FOREVER, 18807, 2 },   -- Mind Flay rank 6
    { "Forever", FOREVER, 5143, 2 },    -- Arcane Missiles rank 1, 3 ticks
    { "Forever", FOREVER, 5144, 3 },    -- Arcane Missiles rank 2, 4 ticks
    { "Forever", FOREVER, 25345, 4 },   -- Arcane Missiles rank 8, 5 ticks
    { "Forever", FOREVER, 755, 9 },     -- Health Funnel, 10 ticks
    { "Forever", FOREVER, 11684, 14 },  -- Hellfire rank 3, 15 ticks
    { "Forever", FOREVER, 12051, 5 },   -- Evocation: no per-tick effect, default layout
    { "Forever", FOREVER, 234153, 5 },  -- Retail Drain Life ID: absent on Forever, default layout
    { "Forever", FOREVER, 356995, 5 },  -- Retail Disintegrate: default layout
    -- Retail and the harness keep the Retail table.
    { "Retail", RETAIL, 15407, 5 },     -- Mind Flay, 6 ticks
    { "Retail", RETAIL, 234153, 4 },    -- Drain Life, 5 ticks
    { "Retail", RETAIL, 755, 4 },       -- Health Funnel, 5 ticks
    { "Retail", RETAIL, 1949, 5 },      -- Hellfire: not in the Retail table
    -- Classic Era runs the same spell data as Forever: Era table, 15-tick cap.
    { "Vanilla", VANILLA, 15407, 2 },   -- Mind Flay rank 1, 3 ticks
    { "Vanilla", VANILLA, 18807, 2 },   -- Mind Flay rank 6
    { "Vanilla", VANILLA, 5144, 3 },    -- Arcane Missiles rank 2, 4 ticks
    { "Vanilla", VANILLA, 755, 9 },     -- Health Funnel, 10 ticks
    { "Vanilla", VANILLA, 11684, 14 },  -- Hellfire rank 3, 15 ticks (above the Retail cap of 12)
    { "Vanilla", VANILLA, 234153, 5 },  -- Retail Drain Life ID: absent on Era, default layout
    -- TBC and Mists spell data is unverified: both stay on the Retail table.
    { "TBC", TBC, 15407, 5 },           -- Mind Flay, 6 ticks
    { "TBC", TBC, 755, 4 },             -- Health Funnel, 5 ticks
    { "TBC", TBC, 11684, 5 },           -- Hellfire rank 3: not in the Retail table
    { "Mists", MISTS, 15407, 5 },
    { "Mists", MISTS, 755, 4 },
    { "Mists", MISTS, 11684, 5 },
    { "no MSUF.Client", nil, 12051, 5 }, -- Evocation, 6 ticks
}) do
    local shown = ShownTickMarkers(case[2], case[3])
    Check(shown == case[4], string.format("(f) %s spell %d: %d tick markers shown, expected %d",
        case[1], case[3], shown, case[4]))
end

-- Source contracts ----------------------------------------------------------------
do
    local interrupt = Read(INTERRUPT_FILE)
    local _, interruptReads = interrupt:gsub("Client%.IsForever", "")
    Check(interruptReads == 1, "contract: " .. INTERRUPT_FILE .. " must read Client.IsForever exactly once, found " .. interruptReads)
    Check(interrupt:find("\nlocal IS_FOREVER = MSUF.Client ~= nil and MSUF.Client.IsForever == true\n", 1, true),
        "contract: " .. INTERRUPT_FILE .. " must read IS_FOREVER once at file load")
    -- The tick table keys on one named fact (the client runs Classic Era spell
    -- data), read once at file load, not on a second identity alias. TBC and
    -- Mists must not join it before their spell data is verified.
    local ticks = Read(TICKS_FILE)
    local _, foreverReads = ticks:gsub("Client%.IsForever", "")
    local _, vanillaReads = ticks:gsub("Client%.IsVanilla", "")
    Check(foreverReads == 1 and vanillaReads == 1,
        "contract: " .. TICKS_FILE .. " must read Client.IsForever and Client.IsVanilla exactly once each")
    Check(ticks:find("\nlocal HAS_ERA_SPELL_DATA = MSUF.Client ~= nil\n"
            .. "    and (MSUF.Client.IsForever == true or MSUF.Client.IsVanilla == true)\n", 1, true),
        "contract: " .. TICKS_FILE .. " must read HAS_ERA_SPELL_DATA once at file load")
    Check(ticks:find("\nlocal MAX_AUTO_TICK_COUNT = HAS_ERA_SPELL_DATA and 15 or 12\n", 1, true)
            and ticks:find("\nif HAS_ERA_SPELL_DATA then\n    CHANNEL_TICK_DATA = {}\n", 1, true),
        "contract: the Era tick table and its 15-tick cap must key on HAS_ERA_SPELL_DATA")
    for _, identity in ipairs({ "IS_FOREVER", "IsEra", "IsTBC", "IsMists", "IsClassic" }) do
        Check(not ticks:find(identity, 1, true),
            "contract: " .. TICKS_FILE .. " must not branch on " .. identity)
    end
    local gcd = Read(GCD_FILE)
    local _, gcdReads = gcd:gsub("Client%.IsForever", "")
    Check(gcdReads == 1 and gcd:find("\nlocal IS_FOREVER = ns.Client ~= nil and ns.Client.IsForever == true\n", 1, true),
        "contract: " .. GCD_FILE .. " must read IS_FOREVER once at file load")
    local bridge = Read(BRIDGE_FILE)
    local _, gamepadReads = bridge:gsub("GamepadPlayerCastingBarFrame\"%)", "")
    Check(gamepadReads == 1 and bridge:find('local gamepadPlayer = rawget(_G, "GamepadPlayerCastingBarFrame")', 1, true),
        "contract: the Bridge must look up GamepadPlayerCastingBarFrame once, nil-guarded")
    Check(not bridge:find("IsForever", 1, true), "contract: the Bridge gamepad lookup is a nil guard, not a client gate")
end

print("forever_castbar_client_data_smoke: ok")
