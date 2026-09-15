-- Runtime smoke for the shared Retail/Classic arena trinket provider.
-- Covers Retail DurationObject/native texture relay, Classic C_PvP timing,
-- the event-driven Mists combat-log fallback, and the 5-slot TBC/Mists
-- arena slot count (Mainline stays at three).

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local modulePath = "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua"

local function NewRegion()
    local region = {}
    function region:SetAllPoints() end
    function region:SetTexCoord() end
    function region:SetTexture(texture) self.texture = texture end
    return region
end

local function NewFrame(name, parent)
    local frame = { name = name, parent = parent, scripts = {} }
    function frame:SetSize() end
    function frame:SetFrameStrata() end
    function frame:SetAllPoints() end
    function frame:SetDrawEdge() end
    function frame:ClearAllPoints() end
    function frame:SetPoint(_, relativeTo) self.relativeTo = relativeTo end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:CreateTexture()
        self.createdTexture = NewRegion()
        return self.createdTexture
    end
    function frame:SetCooldown(startTime, duration)
        self.startTime = startTime
        self.duration = duration
        self.cleared = nil
    end
    function frame:SetCooldownFromDurationObject(duration)
        self.durationObject = duration
        self.cleared = nil
    end
    function frame:Clear()
        self.startTime = nil
        self.duration = nil
        self.durationObject = nil
        self.cleared = true
    end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:RegisterEvent(event) self.registeredEvent = event end
    return frame
end

local baseTonumber = tonumber

local function RunScenario(kind)
    local framesByName = {}
    local allFrames = {}
    local callbacks = {}
    local arenaFrames = {}
    local slot = kind == "tbc5" and 5 or 1
    local slotUnit = "arena" .. slot
    local liveUnits = { [slotUnit] = true }
    local requests = 0
    local now = 50
    local currentClassicInfo = { 42292, 0, 5000, 120000 }

    for index = 1, 6 do arenaFrames["arena" .. index] = NewFrame("arena" .. index) end
    -- Mainline publishes 3 slots and TBC/Mists 5. The 3-slot Classic scenario
    -- leaves the global unset to exercise the module fallback of three.
    _G.MSUF_MAX_ARENA_FRAMES = ({ retail = 3, mists = 5, tbc5 = 5 })[kind]

    _G.UIParent = NewFrame("UIParent")
    _G.CreateFrame = function(_, name, parent)
        local frame = NewFrame(name, parent)
        allFrames[#allFrames + 1] = frame
        if name then framesByName[name] = frame end
        return frame
    end
    _G.UnitExists = function(unit) return liveUnits[unit] == true end
    _G.IsInInstance = function() return true, "arena" end
    _G.GetTime = function() return now end
    _G.UnitGUID = function(unit) return unit == slotUnit and "enemy-guid-1" or nil end
    _G.GetSpellTexture = function(spellID) return spellID + 1000, spellID + 2000 end
    _G.C_Item = { GetItemIconByID = function(itemID) return itemID + 3000 end }
    _G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    _G.tonumber = function(value, base)
        if _G.issecretvalue(value) then error("secret value reached tonumber") end
        return baseTonumber(value, base)
    end
    _G.WOW_PROJECT_MAINLINE = nil
    _G.WOW_PROJECT_ID = nil
    _G.Enum = { PvPMatchState = { Engaged = 3 } }
    _G.MSUF_DB = { arena = { enabled = true, showTrinket = true } }
    _G.MSUF_EventBus_Register = function(event, _, callback) callbacks[event] = callback end
    _G.hooksecurefunc = function(receiver, method, callback)
        local original = receiver[method]
        receiver[method] = function(self, ...)
            local values = { original(self, ...) }
            callback(self, ...)
            return unpack(values)
        end
    end

    local nativeIcon = NewRegion()
    local nativeCooldown = NewFrame("nativeCooldown")
    _G.CompactArenaFrameMember1 = {
        CcRemoverFrame = { Icon = nativeIcon, Cooldown = nativeCooldown },
    }
    _G.CompactArenaFrameMember2 = nil
    _G.CompactArenaFrameMember3 = nil

    local durationObject = { retailDuration = true }
    _G.C_PvP = {
        IsMatchConsideredArena = function() return true end,
        IsMatchActive = function() return false end,
        IsMatchComplete = function() return false end,
        GetActiveMatchState = function() return _G.Enum.PvPMatchState.Engaged end,
        RequestCrowdControlSpell = function(unit)
            Check(unit == slotUnit, kind .. " requested the wrong unit")
            requests = requests + 1
        end,
        GetArenaCrowdControlDuration = function() return durationObject end,
        GetArenaCrowdControlInfo = function()
            return unpack(currentClassicInfo)
        end,
    }
    _G.C_Spell = { GetSpellTexture = function(spellID) return spellID + 4000 end }

    local MSUF = {
        Client = {
            IsRetail = kind == "retail",
            IsMists = kind == "mists",
            IsTBC = kind == "classic" or kind == "tbc5",
        },
        UF = { GetFrame = function(unit) return arenaFrames[unit] end },
        Secrets = { UnitExistsPlain = function(unit) return liveUnits[unit] == true end },
        ExportPublic = function(name, value)
            _G[name] = value
            return value
        end,
    }
    _G.MSUF_NS = MSUF

    if kind ~= "retail" then
        _G.C_PvP.GetArenaCrowdControlDuration = nil
    end
    if kind == "mists" then
        currentClassicInfo = { nil, nil, 0, 0 }
        _G.CombatLogGetCurrentEventInfo = function()
            return now, "SPELL_CAST_SUCCESS", false, "enemy-guid-1",
                "Enemy", 0, 0, nil, nil, nil, nil, 42292
        end
    else
        _G.CombatLogGetCurrentEventInfo = nil
    end

    assert(loadfile(modulePath))("MidnightSimpleUnitFrames", MSUF)
    local holder = framesByName["MSUF_ArenaTrinket" .. slot]
    Check(holder and holder.createdTexture, kind .. " did not create the trinket holder")
    Check(holder.shown == true, kind .. " did not show the live arena slot")

    _G.MSUF_ArenaMatch_SyncTrinketIcons()
    _G.MSUF_ArenaMatch_SyncTrinketIcons()
    Check(requests == 1, kind .. " did not limit requests to one per visible slot")

    if kind == "retail" then
        Check(callbacks.PVP_MATCH_STATE_CHANGED ~= nil,
            "Retail did not register its match-state event")
        Check(callbacks.COMBAT_LOG_EVENT_UNFILTERED == nil,
            "Retail registered the Mists combat-log fallback")
        Check(holder.cooldown.durationObject == durationObject,
            "Retail did not use the secret-safe DurationObject")

        callbacks.ARENA_CROWD_CONTROL_SPELL_UPDATE(
            "ARENA_CROWD_CONTROL_SPELL_UPDATE", slotUnit, { secret = true }, { secret = true })
        Check(holder.cooldown.durationObject == durationObject,
            "Retail secret response escaped into the Classic numeric path")

        local secretTexture = { secret = true }
        nativeIcon:SetTexture(secretTexture)
        Check(holder.createdTexture.texture == secretTexture,
            "Retail did not relay Blizzard's secret trinket texture")
        nativeCooldown:SetCooldown(10, 120)
        Check(holder.cooldown.durationObject == durationObject,
            "Retail native cooldown hook did not refresh the DurationObject")
        callbacks.ARENA_COOLDOWNS_UPDATE("ARENA_COOLDOWNS_UPDATE")
        Check(requests == 1, "Retail response event re-requested crowd-control data")

        liveUnits.arena4 = true
        callbacks.ARENA_OPPONENT_UPDATE("ARENA_OPPONENT_UPDATE", "arena4", "seen")
        Check(framesByName.MSUF_ArenaTrinket4 == nil,
            "Retail created a trinket holder beyond its three arena slots")
        Check(requests == 1, "Retail requested crowd-control data for arena4")
    elseif kind == "classic" or kind == "tbc5" then
        Check(callbacks.PVP_MATCH_STATE_CHANGED == nil,
            "Classic registered the Retail match-state event")
        Check(holder.cooldown.startTime == 5 and holder.cooldown.duration == 120,
            "Classic did not convert C_PvP milliseconds to seconds")
        Check(holder.createdTexture.texture == 44292,
            "Classic did not apply the spell texture")

        currentClassicInfo = { 59752, 123, 9000, 90000 }
        callbacks.ARENA_CROWD_CONTROL_SPELL_UPDATE(
            "ARENA_CROWD_CONTROL_SPELL_UPDATE", slotUnit, 59752, 123)
        Check(holder.cooldown.startTime == 9 and holder.cooldown.duration == 90,
            "Classic spell response did not refresh the cooldown")
        Check(holder.createdTexture.texture == 3123,
            "Classic did not prefer the delivered item texture")
        Check(requests == 1, "Classic response event re-requested crowd-control data")

        callbacks.ARENA_CROWD_CONTROL_SPELL_UPDATE(
            "ARENA_CROWD_CONTROL_SPELL_UPDATE", slotUnit, { secret = true }, { secret = true })
        Check(holder.createdTexture.texture == 3123,
            "Classic secret response replaced the last plain trinket texture")
        if kind == "tbc5" then
            Check(holder.name == "MSUF_ArenaTrinket5" and holder.relativeTo == arenaFrames.arena5,
                "TBC 5-slot client did not anchor the arena5 trinket holder")
            Check(framesByName.MSUF_ArenaTrinket4 and framesByName.MSUF_ArenaTrinket4.shown == false,
                "TBC 5-slot client did not keep the empty arena4 holder hidden")
            Check(framesByName.MSUF_ArenaTrinket6 == nil,
                "TBC 5-slot client created a trinket holder beyond arena5")
        end
    else
        Check(callbacks.COMBAT_LOG_EVENT_UNFILTERED ~= nil,
            "Mists did not register its combat-log fallback")
        callbacks.COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED")
        Check(holder.cooldown.startTime == 50 and holder.cooldown.duration == 120,
            "Mists did not start the 120-second combat-log fallback")
        callbacks.ARENA_COOLDOWNS_UPDATE("ARENA_COOLDOWNS_UPDATE")
        Check(holder.cooldown.startTime == 50 and holder.cooldown.duration == 120,
            "Mists public API miss cleared an active fallback")
        now = 171
        callbacks.ARENA_COOLDOWNS_UPDATE("ARENA_COOLDOWNS_UPDATE")
        Check(holder.cooldown.cleared == true,
            "Mists did not expire its combat-log fallback")
        Check(requests == 1, "Mists response event re-requested crowd-control data")
    end

    for index = 1, #allFrames do
        Check(allFrames[index].scripts.OnUpdate == nil,
            kind .. " installed an OnUpdate polling path")
    end
end

RunScenario("retail")
RunScenario("classic")
RunScenario("mists")
RunScenario("tbc5")

local moduleHandle = assert(io.open(modulePath, "rb"))
local moduleSource = moduleHandle:read("*a")
moduleHandle:close()
Check(not moduleSource:find("WOW_PROJECT_ID", 1, true),
    "arena trinkets must trust Client.IsRetail, not a WOW_PROJECT_ID fallback")

print("arena_trinket_tracking_smoke: ok")
