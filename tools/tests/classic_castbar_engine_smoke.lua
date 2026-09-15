local root = assert(arg[1], "repository root argument missing")

local now = 1
local casting
local channeling
local castReads = 0
local channelReads = 0

_G.GetTime = function() return now end
_G.UnitCastingInfo = function()
    castReads = castReads + 1
    if not casting then return nil end
    return unpack(casting)
end
_G.UnitChannelInfo = function()
    channelReads = channelReads + 1
    if not channeling then return nil end
    return unpack(channeling)
end
_G.UnitCastingDuration = nil
_G.UnitChannelDuration = nil
_G.GetUnitEmpowerStageCount = nil
_G.issecretvalue = function() return false end
_G.MSUF_DB = { general = {} }

local namespace = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

local path = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarEngine.lua"
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))("MidnightSimpleUnitFrames", namespace)
assert(loadfile(path))("MidnightSimpleUnitFrames", namespace)
local engine = assert(namespace.MSUF_CastbarEngine, "castbar engine did not load")

-- Both supported Classic branches still expose the nine-value legacy cast
-- tuple: spellID is the ninth value and no Retail castBarID/delay follows it.
casting = { "Fireball", "Fireball", 135812, 1000, 3000, false, "cast-guid", true, 133 }
local cast = engine:BuildState("target")
assert(cast.active == true and cast.castType == "CAST", "legacy cast did not activate")
assert(cast.spellId == 133 and cast.castID == "cast-guid", "legacy cast tuple was decoded incorrectly")
assert(cast.castBarID == nil and cast.delayTimeMS == nil, "Retail-only cast fields leaked into legacy output")
assert(cast.apiNotInterruptibleRaw == true, "legacy cast interruptibility was lost")

local cached = engine:BuildState("target")
assert(cached == cast and castReads == 1 and channelReads == 0, "same-frame cast cache did not hold")

-- Classic channel tuples have eight values: notInterruptible at seven and
-- spellID at eight. Retail's empower fields therefore remain nil by design.
now = now + 1
casting = nil
channeling = { "Mind Flay", "Mind Flay", 136208, 4000, 7000, false, true, 15407 }
local channel = engine:BuildState("target", cast)
assert(channel.active == true and channel.castType == "CHANNEL", "legacy channel did not activate")
assert(channel.spellId == 15407 and channel.apiNotInterruptibleRaw == true,
    "legacy channel tuple was decoded incorrectly")
assert(channel.isEmpowered == nil and channel.numEmpowerStages == nil and channel.castBarID == nil,
    "Retail-only channel fields were synthesized on Classic")

now = now + 1
channeling = nil
casting = { "Smelt", "Smelt", 136241, 8000, 9000, true, "trade-guid", false, 2656 }
_G.MSUF_DB.general.castbarHideTradeSkills = true
local hidden = engine:BuildState("player")
assert(hidden.active == false and hidden.castType == "NONE", "Classic tradeskill cast filter failed")

-- Legacy clients report no delayTimeMS: UNIT_SPELLCAST_DELAYED moves the start
-- time instead. The shared resolver measures that shift per cast identity.
local resolvePushback = assert(_G.MSUF_Castbar_ResolvePushbackMS, "pushback resolver export missing")
local pushFrame = {}
assert(resolvePushback(pushFrame, { castType = "CAST", castID = "push-guid", startTimeMS = 1000 }) == nil,
    "first legacy cast sighting reported a pushback")
assert(resolvePushback(pushFrame, { castType = "CAST", castID = "push-guid", startTimeMS = 1400 }) == 400,
    "legacy start shift was not measured as a 400 ms pushback")
assert(resolvePushback(pushFrame, { castType = "CAST", castID = "next-guid", startTimeMS = 5000 }) == nil,
    "a new cast identity inherited the previous pushback")
assert(resolvePushback(pushFrame, {
    castType = "CAST", castID = "next-guid", castBarID = 7, startTimeMS = 5000, delayTimeMS = 250,
}) == 250, "Retail delayTimeMS was not passed through")
assert(resolvePushback(pushFrame, { castType = "CAST", castID = "next-guid", castBarID = 7, startTimeMS = 5400 }) == nil,
    "a Retail cast without delayTimeMS was measured with the legacy start shift")
assert(resolvePushback(pushFrame, { castType = "CAST", castID = "chan-guid", startTimeMS = 6000 }) == nil,
    "legacy sighting before the channel check reported a pushback")
assert(resolvePushback(pushFrame, { castType = "CHANNEL", castID = "chan-guid", startTimeMS = 6300 }) == nil,
    "a channel was measured with the legacy cast start shift")

_G.MSUF_DB.general.castbarShowPushback = true
local suffixText
local suffixFrame = { MSUF_castActive = true, castText = { SetText = function(_, value) suffixText = value end } }
suffixFrame._msufPushbackMS = resolvePushback(suffixFrame, { castType = "CAST", castID = "fire-guid", startTimeMS = 2000 })
suffixFrame._msufPushbackMS = resolvePushback(suffixFrame, { castType = "CAST", castID = "fire-guid", startTimeMS = 2400 })
_G.MSUF_CB_ApplyTexts(suffixFrame, nil, "Fireball", nil)
assert(suffixText == "Fireball +0.4", "legacy pushback suffix was not rendered: " .. tostring(suffixText))

-- Player path: ApplyCastState stores the shared resolver's result after
-- ApplyActiveCast's timing reset. Classic derives it from a moved start for the
-- same castID; Retail-shaped state keeps its client delayTimeMS.
_G.MSUF_GetReverseFillSafe = function() return false end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitHasVehicleUI = function() return false end
_G.issecure = function() return true end
local retailState
namespace.Castbars = {
    Engine = {
        Invalidate = function() end,
        BuildState = function(_, unit, previous)
            if retailState then return retailState end
            return engine:BuildState(unit, previous)
        end,
    },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua"))("MidnightSimpleUnitFrames", namespace)
local castPlayer = assert(_G.MSUF_PlayerCastbar_Cast, "player castbar cast export missing")
local noop = function() end
local playerFrame = {
    unit = "player",
    statusBar = { SetMinMaxValues = noop, SetValue = noop, SetStatusBarColor = noop, GetWidth = function() return 200 end },
    Show = noop,
    SetScript = noop,
}
now = now + 1
casting = { "Frostbolt", "Frostbolt", 135846, 20000, 22500, false, "player-guid", false, 116 }
castPlayer(playerFrame)
assert(playerFrame.MSUF_castActive == true and playerFrame._msufPushbackMS == nil,
    "player cast start reported a pushback: " .. tostring(playerFrame._msufPushbackMS))
now = now + 1
casting = { "Frostbolt", "Frostbolt", 135846, 20400, 22900, false, "player-guid", false, 116 }
castPlayer(playerFrame)
assert(playerFrame._msufPushbackMS == 400,
    "player castbar did not derive the legacy pushback from the moved start: " .. tostring(playerFrame._msufPushbackMS))
now = now + 1
retailState = {
    active = true, unit = "player", castType = "CAST", spellName = "Fireball", text = "Fireball",
    startTimeMS = 30000, endTimeMS = 32500, castID = "retail-guid", castBarID = 11, spellId = 133,
    delayTimeMS = 250,
}
castPlayer(playerFrame)
assert(playerFrame._msufPushbackMS == 250,
    "player castbar dropped the client delayTimeMS on Retail-shaped state: " .. tostring(playerFrame._msufPushbackMS))
retailState = nil
casting = nil

-- Target driver and shared runtime through the real Vanilla load graph. Both
-- sections run on a fresh namespace; every global they install or re-export is
-- restored afterwards so the source checks below see the original state.
do
    local savedGlobals = {}
    for key, value in pairs(_G) do savedGlobals[key] = value end

    local function NoOp() end
    local widgetMeta = {
        __index = function(_, key)
            -- Any CamelCase method is a no-op, except the native timer API,
            -- which stays absent exactly as on a Classic client.
            if type(key) == "string" and key ~= "SetTimerDuration" and key ~= "ClearTimerDuration"
                and key:match("^%u%a*$") then
                return NoOp
            end
            return nil
        end,
    }
    local function NewWidget()
        local widget = setmetatable({ scripts = {}, shown = true, texts = {} }, widgetMeta)
        function widget:SetScript(name, handler) self.scripts[name] = handler end
        function widget:GetScript(name) return self.scripts[name] end
        function widget:IsShown() return self.shown == true end
        function widget:Show() self.shown = true end
        function widget:Hide() self.shown = false end
        function widget:SetText(text)
            self.text = text
            self.texts[#self.texts + 1] = text
        end
        function widget:GetText() return self.text end
        function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
        function widget:GetMinMaxValues() return self.minValue or 0, self.maxValue or 1 end
        function widget:SetValue(value) self.value = value end
        function widget:GetValue() return self.value or 0 end
        function widget:GetStatusBarColor() return 1, 0.7, 0, 1 end
        return widget
    end

    local pendingAfter = {}
    _G.C_Timer = { After = function(_, callback) pendingAfter[#pendingAfter + 1] = callback end }
    _G.wipe = function(tbl)
        for key in pairs(tbl) do tbl[key] = nil end
        return tbl
    end
    _G.UnitExists = function() return true end
    _G.UnitIsDeadOrGhost = function() return false end
    _G.CreateFrame = function() return NewWidget() end
    _G.UIParent = NewWidget()
    _G.GameFontHighlight = NewWidget()

    local driverNamespace = {
        ExportPublic = function(name, value)
            _G[name] = value
            return value
        end,
        Client = { IsClassic = true, IsVanilla = true },
    }
    local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    manifest.LoadSelected(root, "Vanilla", driverNamespace, {
        "Castbars/MSUF_CastbarUtils.lua",
        "Castbars/MSUF_CastbarRuntime.lua",
        "Castbars/MSUF_CastbarEngine.lua",
        "Castbars/MSUF_CastbarDriver.lua",
    })
    -- The client runs zero-delay callbacks on the next frame; the files above
    -- re-resolve their late-bound helpers there.
    for index = 1, #pendingAfter do pendingAfter[index]() end
    pendingAfter = {}
    _G.MSUF_DB.general.castbarShowPushback = true

    -- a) Legacy pushback through the real target driver. Classic cast tuples
    -- carry no delayTimeMS, so UNIT_SPELLCAST_DELAYED only moves startTimeMS;
    -- the driver measures that shift and repaints the "+x.x" suffix, and a new
    -- castID starts without one.
    do
        local driven = assert(_G.MSUF_CreateCastBar("MSUF_EngineSmokeTargetCastBar", "target"),
            "driver castbar missing")
        driven.statusBar = NewWidget()
        driven.castText = NewWidget()
        local function FireCast(event) driven.scripts.OnEvent(driven, event, "target") end

        now = now + 1
        local startMS = math.floor(now * 1000)
        casting = { "Fireball", "Fireball", 135812, startMS, startMS + 3000, false, "driver-guid", false, 133 }
        FireCast("UNIT_SPELLCAST_START")
        assert(driven.MSUF_castActive == true and driven._msufPushbackMS == nil,
            "driver START reported a pushback: " .. tostring(driven._msufPushbackMS))
        assert(driven.castText.text == "Fireball",
            "driver START painted an unexpected cast text: " .. tostring(driven.castText.text))

        now = now + 0.2
        casting = { "Fireball", "Fireball", 135812, startMS + 400, startMS + 3400, false, "driver-guid", false, 133 }
        FireCast("UNIT_SPELLCAST_DELAYED")
        assert(driven._msufPushbackMS == 400,
            "driver did not measure the legacy start shift: " .. tostring(driven._msufPushbackMS))
        assert(driven.castText.text == "Fireball +0.4",
            "driver did not repaint the pushback suffix: " .. tostring(driven.castText.text))

        now = now + 0.2
        startMS = math.floor(now * 1000)
        casting = { "Frostbolt", "Frostbolt", 135846, startMS, startMS + 2500, false, "driver-next-guid", false, 116 }
        FireCast("UNIT_SPELLCAST_START")
        assert(driven._msufPushbackMS == nil and driven.castText.text == "Frostbolt",
            "a new driver cast inherited the pushback: " .. tostring(driven.castText.text))
        casting = nil
    end

    -- b) Retail-shaped state through Runtime:ApplyActive with the driver's live
    -- options. The client delayTimeMS is stored before the cast text write, so
    -- the very first paint of the pushed-back cast already carries the suffix.
    do
        local applyActive = assert(_G.MSUF_Castbar_ApplyActiveDuration, "ApplyActive export missing")
        local liveOptions = { skipColor = true, skipRegister = true, skipTimeText = true, skipShow = true }
        local frame = NewWidget()
        frame.unit = "target"
        frame._msufBarKey = "target"
        frame.statusBar = NewWidget()
        frame.castText = NewWidget()
        frame.timeText = NewWidget()
        local duration = {
            GetRemainingDuration = function() return 2.5 end,
            GetTotalDuration = function() return 2.9 end,
        }

        assert(applyActive(frame, {
            active = true, unit = "target", castType = "CAST", spellName = "Fireball", text = "Fireball",
            castID = "runtime-guid", castBarID = 3, spellSequenceID = 3, delayTimeMS = 400,
            durationObj = duration,
        }, liveOptions) == true, "ApplyActive rejected a Retail-shaped pushed-back cast")
        local firstPaint
        for index = 1, #frame.castText.texts do
            local text = frame.castText.texts[index]
            if type(text) == "string" and text:find("Fireball", 1, true) then
                firstPaint = text
                break
            end
        end
        assert(firstPaint == "Fireball +0.4",
            "ApplyActive first painted the pushed-back cast without its suffix: " .. tostring(firstPaint))
        assert(frame._msufPushbackMS == 400,
            "ApplyActive did not keep the client delayTimeMS: " .. tostring(frame._msufPushbackMS))

        assert(applyActive(frame, {
            active = true, unit = "target", castType = "CAST", spellName = "Frostbolt", text = "Frostbolt",
            castID = "runtime-next-guid", castBarID = 4, spellSequenceID = 4,
            durationObj = duration,
        }, liveOptions) == true, "ApplyActive rejected a Retail-shaped cast without delay")
        assert(frame._msufPushbackMS == nil and frame.castText.text == "Frostbolt",
            "a Retail cast without delayTimeMS inherited the pushback: " .. tostring(frame.castText.text))
    end

    local addedGlobals = {}
    for key in pairs(_G) do
        if savedGlobals[key] == nil then addedGlobals[#addedGlobals + 1] = key end
    end
    for index = 1, #addedGlobals do _G[addedGlobals[index]] = nil end
    for key, value in pairs(savedGlobals) do
        if _G[key] ~= value then _G[key] = value end
    end
end

local runtimeFile = assert(io.open(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua", "rb"))
local runtimeSource = runtimeFile:read("*a")
runtimeFile:close()
local impl = assert(runtimeSource:find("local function PlayerCastbarOnEventImpl", 1, true),
    "player castbar event implementation missing")
local interrupted = assert(runtimeSource:find('if event == "UNIT_SPELLCAST_INTERRUPTED" then', impl, true),
    "player castbar interrupted branch missing")
local unitGuard = assert(runtimeSource:find("if not ActiveUnitMatches(frame, eventUnit) then return end", interrupted, true),
    "player castbar interrupted branch has no unit guard")
assert(not runtimeSource:sub(interrupted, unitGuard):find("HasActivePlayerCast", 1, true),
    "late player interrupt feedback still requires an API-active cast after STOP")
assert(runtimeSource:find("frame._msufPlayerInterruptCastGUID = interruptCastGUID", 1, true)
    and runtimeSource:find("select(2, ...) == frame._msufPlayerInterruptCastGUID", 1, true)
    and runtimeSource:find("GetTime() <= frame._msufPlayerInterruptCastDeadline", 1, true),
    "player castbar does not retain and verify the stopped cast identity")

local previewFile = assert(io.open(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarPreviews.lua", "rb"))
local previewSource = previewFile:read("*a")
previewFile:close()
assert(not previewSource:find('"PVP_MATCH_STATE_CHANGED"', 1, true),
    "Classic castbar previews reintroduced an event absent from supported Classic clients")
for _, event in ipairs({
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "ENCOUNTER_START", "ENCOUNTER_END",
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}) do
    assert(previewSource:find('"' .. event .. '"', 1, true),
        "Classic castbar preview lifecycle lost supported event: " .. event)
end

print("classic castbar engine smoke passed")
