-- Fonts and textures that other addons register with LibSharedMedia while the
-- player is in combat must still reach MSUF once combat ends, and must reach it
-- once: Kernel/MSUF_Libs.lua keeps one LibSharedMedia callback for the whole
-- session and parks every media refresh behind one PLAYER_REGEN_ENABLED
-- listener while combat lasts. It must not unregister and re-register the
-- callback on every combat edge, nor walk every LibSharedMedia hash table when
-- combat ends to find out what changed. Runs the real LibStub, CallbackHandler,
-- LibSharedMedia and Libs.lua against a small client stub.
-- Usage: lua tools/tests/lsm_media_registered_in_combat_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local addon = repo .. "/MidnightSimpleUnitFrames/"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- Client stubs shared by every world. ---------------------------------------
strmatch = string.match
function geterrorhandler() return function(err) error(err, 0) end end
function GetLocale() return "enUS" end
bit = { band = function(a, b)
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end }
local realXpcall = xpcall
function xpcall(fn, handler, ...)
    local args, count = { ... }, select("#", ...)
    return realXpcall(function() return fn(unpack(args, 1, count)) end, handler)
end

local function NewWorld(startInCombat)
    local world = { combat = startInCombat == true, frames = {}, timers = {}, counts = {}, scheduled = {}, order = {} }

    for _, name in ipairs({ "bars", "castbars", "iconPacks", "icons", "fonts", "group", "registerCallback",
        "unregisterCallback", "hashTable" }) do
        world.counts[name] = 0
    end
    local counts = world.counts

    function InCombatLockdown() return world.combat end
    function CreateFrame()
        local frame = { events = {}, scripts = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(kind, fn) self.scripts[kind] = fn end
        function frame:Hide() end
        world.frames[#world.frames + 1] = frame
        return frame
    end
    C_Timer = { After = function(_, fn) world.timers[#world.timers + 1] = fn end }

    -- Observers for everything a media refresh may touch.
    MSUF_UpdateAllBarTextures = function() counts.bars = counts.bars + 1 end
    MSUF_UpdateCastbarTextures = function() counts.castbars = counts.castbars + 1 end
    MSUF_RefreshStatusIconPacks = function() counts.iconPacks = counts.iconPacks + 1 end
    MSUF_RequestStatusIconsRefreshForCurrent = function() counts.icons = counts.icons + 1 end
    MSUF_RequestFontRecovery = function() counts.fonts = counts.fonts + 1 end
    MSUF_NormalizeFontKey = function(key) return key end
    MSUF_DB = { general = { fontKey = "Configured Font" } }
    MSUF_ScheduleOnce = nil
    MSUF_BUNDLED_FONTS_REGISTERED = nil
    MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED = nil
    MSUF_LSM_CallbacksRegistered = nil

    -- A fresh library stack per world.
    LibStub = nil
    for _, path in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
        "Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua" }) do
        assert(loadfile(addon .. path))()
    end
    local LSM = LibStub("LibSharedMedia-3.0")
    world.LSM = LSM
    local register, unregister, hashTable = LSM.RegisterCallback, LSM.UnregisterCallback, LSM.HashTable
    LSM.RegisterCallback = function(...)
        counts.registerCallback = counts.registerCallback + 1
        return register(...)
    end
    LSM.UnregisterCallback = function(...)
        counts.unregisterCallback = counts.unregisterCallback + 1
        return unregister(...)
    end
    LSM.HashTable = function(...)
        counts.hashTable = counts.hashTable + 1
        return hashTable(...)
    end

    local ns = {
        Client = { Family = "Mainline" },
        GF = { RefreshVisuals = function() counts.group = counts.group + 1 end },
    }
    ns.ExportPublic = function(name, value)
        _G[name] = value
        return value
    end
    ns.Optional = function(name)
        local value = _G[name]
        if type(value) == "function" or type(value) == "table" then return value end
        return nil
    end
    world.ns = ns
    assert(loadfile(addon .. "Kernel/MSUF_Libs.lua"))("MidnightSimpleUnitFrames", ns)

    -- The keyed scheduler loads after Libs.lua; model its next-frame queue.
    MSUF_ScheduleOnce = function(key, fn)
        if world.scheduled[key] == nil then
            world.scheduled[key] = fn
            world.order[#world.order + 1] = key
        end
    end

    function world:Settle()
        for _ = 1, 20 do
            local timers, order = self.timers, self.order
            if #timers == 0 and #order == 0 then return end
            self.timers, self.order = {}, {}
            for _, fn in ipairs(timers) do fn() end
            for _, key in ipairs(order) do
                local fn = self.scheduled[key]
                self.scheduled[key] = nil
                fn()
            end
        end
        error("media refresh never settled")
    end

    function world:Fire(event)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event) end
        end
    end

    function world:EnterCombat()
        self.combat = true
        self:Fire("PLAYER_REGEN_DISABLED")
    end

    function world:LeaveCombat()
        self.combat = false
        self:Fire("PLAYER_REGEN_ENABLED")
    end

    function world:Snapshot()
        local copy = {}
        for key, value in pairs(counts) do copy[key] = value end
        return copy
    end

    return world
end

local function Delta(world, before, key) return world.counts[key] - before[key] end
local BAR = "Interface\\AddOns\\Media\\Bar.tga"
local FONT = "Interface\\AddOns\\Media\\Font.ttf"

-- 1. Out of combat: each kind refreshes what it always refreshed. ------------
do
    local world = NewWorld(false)
    local LSM = world.LSM
    Check(LSM:HashTable("font").EXPRESSWAY ~= nil, "the bundled fonts were not registered at load")
    Check(MSUF_LSM_CallbacksRegistered == true, "the LibSharedMedia callback was not announced")
    Check(world.counts.registerCallback == 1, "the callback must be registered once at load")
    world:Settle()

    local before = world:Snapshot()
    LSM:Register("statusbar", "Late Bar", BAR)
    world:Settle()
    Check(Delta(world, before, "bars") == 1 and Delta(world, before, "castbars") == 1, "a statusbar must refresh bars and castbars once")
    Check(Delta(world, before, "iconPacks") == 1 and Delta(world, before, "icons") == 1, "a statusbar must refresh the status icons once")
    Check(Delta(world, before, "group") == 1, "a statusbar must refresh the group frames once")
    Check(Delta(world, before, "fonts") == 0, "a statusbar must not refresh fonts")

    before = world:Snapshot()
    LSM:Register("font", "Unrelated Font", FONT)
    world:Settle()
    Check(Delta(world, before, "fonts") == 0, "an unrelated font must not refresh fonts outside combat")
    LSM:Register("font", "Configured Font", FONT)
    world:Settle()
    Check(Delta(world, before, "fonts") == 1, "the configured font registering must refresh fonts")

    before = world:Snapshot()
    LSM:Register("background", "Late Background", BAR)
    LSM:Register("msuf_statusicon", "Late Icon", BAR)
    world:Settle()
    Check(Delta(world, before, "iconPacks") == 1 and Delta(world, before, "bars") == 0,
        "background and status icon media refresh the icon packs only (once)")
end

-- 2. In combat: nothing runs until combat ends, then each kind applies once. -
do
    local world = NewWorld(false)
    local LSM = world.LSM
    world:Settle()
    local before = world:Snapshot()

    world:EnterCombat()
    LSM:Register("statusbar", "Combat Bar", BAR)
    LSM:Register("statusbar", "Combat Bar Two", BAR)
    LSM:Register("font", "Combat Font", FONT)
    LSM:Register("background", "Combat Background", BAR)
    world:Settle()
    for _, key in ipairs({ "bars", "castbars", "iconPacks", "icons", "fonts", "group" }) do
        Check(Delta(world, before, key) == 0, key .. " refreshed while the player was in combat")
    end
    Check(LSM:HashTable("font")["Combat Font"] == FONT, "the font was not registered with LibSharedMedia")

    world:LeaveCombat()
    world:Settle()
    Check(Delta(world, before, "bars") == 1 and Delta(world, before, "castbars") == 1,
        "textures registered in combat must apply once after combat, bars " .. Delta(world, before, "bars"))
    Check(Delta(world, before, "iconPacks") == 1 and Delta(world, before, "icons") == 1,
        "status icons registered in combat must apply once after combat")
    Check(Delta(world, before, "fonts") == 1, "a font registered in combat must apply once after combat")
    Check(Delta(world, before, "group") >= 1, "group frames must repaint after combat")

    -- Nothing pending: later combat edges do no media work.
    before = world:Snapshot()
    world:EnterCombat()
    world:LeaveCombat()
    world:Settle()
    for _, key in ipairs({ "bars", "castbars", "iconPacks", "icons", "fonts", "group" }) do
        Check(Delta(world, before, key) == 0, key .. " refreshed on a combat edge with nothing registered")
    end

    -- The callback is still live after combat.
    LSM:Register("statusbar", "After Combat Bar", BAR)
    world:Settle()
    Check(Delta(world, before, "bars") == 1, "the callback stopped working after combat")
end

-- 3. The configured font arriving in combat applies after combat. -------------
do
    local world = NewWorld(false)
    local LSM = world.LSM
    world:Settle()
    MSUF_DB.general.fontKey = "Late Configured Font"
    local before = world:Snapshot()
    world:EnterCombat()
    LSM:Register("font", "Late Configured Font", FONT)
    world:LeaveCombat()
    world:Settle()
    Check(Delta(world, before, "fonts") == 1, "the configured font registered in combat was not applied after combat")
end

-- 4. One callback for the session; combat edges do no library work. ----------
do
    local world = NewWorld(false)
    world:Settle()
    local before = world:Snapshot()
    for _ = 1, 3 do
        world:EnterCombat()
        world:LeaveCombat()
        world:Settle()
    end
    Check(world.counts.registerCallback == 1, "the callback was registered again on a combat edge")
    Check(world.counts.unregisterCallback == 0, "the callback was unregistered on a combat edge")
    Check(Delta(world, before, "hashTable") == 0,
        "combat edges walked LibSharedMedia tables (" .. Delta(world, before, "hashTable") .. " lookups)")
end

-- 5. A client that starts in combat registers the bundle after combat. --------
do
    local world = NewWorld(true)
    local LSM = world.LSM
    Check(LSM:HashTable("font") == nil or LSM:HashTable("font").EXPRESSWAY == nil,
        "bundled media registered with LibSharedMedia during combat")
    Check(MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED == true, "the deferred bundle was not announced")
    world:Settle()
    Check(MSUF_BUNDLED_FONTS_REGISTERED ~= true, "the bundle registered while the player was in combat")
    local before = world:Snapshot()

    world:LeaveCombat()
    world:Settle()
    Check(LSM:HashTable("font").EXPRESSWAY ~= nil, "the bundled fonts never registered after combat")
    Check(LSM:HashTable("statusbar")["MSUF Charcoal"] ~= nil, "the bundled textures never registered after combat")
    Check(MSUF_BUNDLED_FONTS_REGISTERED == true and MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED == nil,
        "the deferred bundle flags were not settled")
    Check(Delta(world, before, "bars") >= 1 and Delta(world, before, "fonts") >= 1,
        "the deferred bundle did not refresh bars and fonts after combat")

    before = world:Snapshot()
    LSM:Register("statusbar", "After Start Bar", BAR)
    world:Settle()
    Check(Delta(world, before, "bars") == 1, "the callback was never registered after a start in combat")
end

print("lsm_media_registered_in_combat_smoke: OK")
