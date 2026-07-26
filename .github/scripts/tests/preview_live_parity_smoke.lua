-- Preview <-> live parity coverage.
--
-- 1) Write direction: a preview handle nudge (conf.hpOffsetX/Y write) must
--    move the LIVE unit frame text after the standard recompile+apply chain.
--    Loads the REAL unit Config compiler and REAL Text layout element.
-- 2) Read direction: the preview must mirror the live unit state (exact
--    name/class/HP/power/level) with per-field mock fallback and zero
--    combat-time sampling (LiveUnitData contract).
-- 3) Wiring contracts keep the render/driver plumbing in place.
_G = _G or _ENV

local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function ReadSource(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

-- ================================================================ 1) write direction
do
    _G.InCombatLockdown = function() return false end
    _G.IsInInstance = function() return false end
    _G.GetInstanceInfo = function() return "none" end
    _G.IsPVPTimerRunning = function() return false end
    _G.UnitIsPVP = function() return false end
    _G.UnitIsPVPFreeForAll = function() return false end
    _G.UnitClass = function() return "Rogue", "ROGUE" end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.issecretvalue = function() return false end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.GetTime = function() return 0 end
    _G.CreateFrame = function()
        local f = {}
        function f:RegisterEvent() end
        function f:RegisterUnitEvent() end
        function f:UnregisterEvent() end
        function f:UnregisterAllEvents() end
        function f:SetScript() end
        function f:HookScript() end
        function f:Show() end
        function f:Hide() end
        function f:IsShown() return false end
        return f
    end

    local UF = {}
    UF.Clamp01 = function(v, fb)
        v = tonumber(v)
        if v == nil then v = fb end
        if v == nil then return nil end
        if v < 0 then return 0 elseif v > 1 then return 1 end
        return v
    end
    UF.Clamp = function(v, lo, hi)
        v = tonumber(v) or 0
        if lo and v < lo then v = lo end
        if hi and v > hi then v = hi end
        return v
    end
    UF.NumberWithFallback = function(v, fb)
        local n = tonumber(v)
        if n == nil then return fb end
        return n
    end
    UF.NormalizeDispelDetectTrigger = function(v) return v or "ALWAYS" end
    UF.NormalizeDispelOverlayTrigger = function(v) return v or "ALWAYS" end
    UF.NormalizeDispelOverlayStyle = function(v) return v or "FILL" end
    UF.NormalizeRangeFadeLayerMode = function(v) return v or "ALL" end
    UF.NormalizeAbsorbTestScope = function(v) return v or "NONE" end
    UF.AbsorbTextureTestEnabledForScope = function() return false end
    UF.NormalizePredictionTestCategory = function(v) return v end
    UF.ConfigScopedValue = function(conf, general, key, fallback)
        if conf and conf[key] ~= nil then return conf[key] end
        if general and general[key] ~= nil then return general[key] end
        return fallback
    end
    UF.CompileBorderPriority = function() return nil end
    UF.ResolveBarGradient = function() return nil end
    UF.FillPredictionColors = function(t) return t end
    UF.InvalidatePVPIndicatorContext = function() end
    UF.PVPIndicatorContextActive = function() return false end
    UF.RefreshPVPIndicatorContext = function() end
    UF.ShouldUseMSUFCastbar = function() return true end
    UF.IsManagedUnit = function(unit)
        return unit == "player" or unit == "target" or unit == "focus" or unit == "pet"
            or unit == "targettarget" or unit == "focustarget"
            or (type(unit) == "string" and unit:match("^boss%d$")) ~= nil
    end
    UF.ConfigKeyForUnit = function(unit)
        if type(unit) == "string" and unit:match("^boss%d$") then return "boss" end
        return unit
    end
    UF.unitOrder = { "player", "target" }
    UF.Secrets = { IsSecret = function() return false end, UnitMissing = function() return false end }
    UF.RefreshElements = function() return true end
    UF.Layers = {}
    UF.elements = {}

    local MSUF = { UF = UF }
    MSUF.ExportPublic = function(name, value)
        _G[name] = value
        return value
    end
    UF.ExportPublic = MSUF.ExportPublic
    _G.MSUF_NS = MSUF

    _G.MSUF_DB = {
        general = { fontSize = 14 },
        player = { showHP = true, showName = true, showPower = true },
        target = {},
    }

    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua"))
    chunk("MidnightSimpleUnitFrames", MSUF)
    local Config = assert(UF.Config, "Config missing")

    local function FontString(parent)
        local fs = { parent = parent, shown = false, setPointCount = 0 }
        function fs:GetParent() return self.parent end
        function fs:SetParent(p) self.parent = p end
        function fs:ClearAllPoints() end
        function fs:SetPoint(point, target, relPoint, x, y)
            self.setPointCount = self.setPointCount + 1
            self.point, self.target, self.relPoint, self.x, self.y = point, target, relPoint, x, y
        end
        function fs:SetJustifyH(j) self.justify = j end
        function fs:SetWordWrap() end
        function fs:SetNonSpaceWrap() end
        function fs:SetDrawLayer(layer, sub) self.drawLayer, self.subLayer = layer, sub end
        function fs:SetTextColor(...) self.color = { ... } end
        function fs:SetText(text) self.text = text end
        function fs:SetWidth(w) self.width = w end
        function fs:SetShown(s) self.shown = s == true end
        function fs:IsShown() return self.shown == true end
        function fs:Show() self.shown = true end
        function fs:Hide() self.shown = false end
        function fs:SetAlpha(a) self.alpha = a end
        function fs:GetText() return self.text end
        return fs
    end
    local function Overlay(parent)
        local o = { parent = parent }
        function o:SetAllPoints() end
        function o:EnableMouse() end
        function o:SetClipsChildren() end
        function o:SetFrameLevel(l) self.frameLevel = l end
        function o:GetFrameLevel() return self.frameLevel or 0 end
        function o:CreateFontString() return FontString(self) end
        return o
    end

    local Text = {
        CreateFrame = function(_, _, parent) return Overlay(parent) end,
        UF = UF,
        tonumber = tonumber,
        floor = math.floor,
        max = math.max,
        EMPTY_EVENTS = {},
        DrawSubLayer = function(layer, fallback) return tonumber(layer) or fallback end,
        ClampFrameLayer = function(layer, fallback) return tonumber(layer) or fallback end,
        GetLayerBaseLevel = function() return 0 end,
        SetFrameLevelCached = function(frame, level) if frame and frame.SetFrameLevel then frame:SetFrameLevel(level) end end,
        SetShownCached = function(region, shown) if region then region:SetShown(shown) end end,
        SetTextCached = function(region, text) if region then region:SetText(text) end end,
        SetFont = function() return true end,
        SetNameTextColor = function() end,
        NameTextColor = function() return 1, 1, 1, 1 end,
        ResolveHealthTextModes = function(text)
            text = text or {}
            return text.healthLeft, text.healthCenter, text.healthRight
        end,
        CompileTextRuntime = function() return {} end,
        UpdateHealthTextColor = function() end,
        SetHealthTextColor = function() end,
    }
    MSUF.UFText = Text
    local layoutChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))
    layoutChunk("MidnightSimpleUnitFrames", MSUF)

    local frame = { unit = "player", MSUFUnitKey = "player" }
    function frame:GetFrameLevel() return 1 end
    function frame:GetWidth() return 275 end

    local spec1 = assert(Config.RefreshUnit("player"), "player spec did not compile")
    Text.Create(frame, spec1)
    Text.Apply(frame, spec1)
    local hpRight = assert(frame.hpTextRight, "hpTextRight sink missing after apply")
    local y0 = hpRight.y
    local count0 = hpRight.setPointCount
    Check(y0 ~= nil, "hpTextRight was never anchored")

    -- Unchanged re-apply keeps the skip contract (perf) intact.
    Text.Apply(frame, Config.RefreshUnit("player"))
    Check(hpRight.setPointCount == count0, "unchanged re-apply repeated SetPoint work")

    -- Exact preview nudge write (WriteHandleOffsets equivalent): live must move.
    local conf = _G.MSUF_DB.player
    conf.hpOffsetX = tonumber(conf.hpOffsetX) or -4
    conf.hpOffsetY = (tonumber(conf.hpOffsetY) or -4) + 2
    Text.Apply(frame, assert(Config.RefreshUnit("player")))
    Check(hpRight.y == y0 + 2,
        "live hp text did not follow the preview base-offset nudge (expected y="
        .. tostring(y0 + 2) .. ", got " .. tostring(hpRight.y) .. ")")

    -- Per-slot nudge parity for the right slot key.
    local slotY0 = hpRight.y
    conf.hpTextRightOffsetY = (tonumber(conf.hpTextRightOffsetY) or 0) + 3
    Text.Apply(frame, assert(Config.RefreshUnit("player")))
    Check(hpRight.y == slotY0 + 3, "live hp text did not follow the preview slot-offset nudge")
end

-- ================================================================ 2) read direction
do
    local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
    _G.issecretvalue = function(value) return value == SECRET end

    local units = {
        target = {
            name = "Dummy Target", className = "Mage", class = "MAGE", race = "Construct",
            level = 82, isPlayer = false, classification = "elite", dead = false, reaction = 2,
            hp = 350, hpMax = 1000, powerType = 0, powerToken = "MANA", power = 60, powerMax = 200,
            absorb = 4200,
        },
        boss1 = {
            name = "Council Boss", className = "Warlock", class = "WARLOCK", race = "Demon",
            level = -1, isPlayer = false, classification = "worldboss", dead = false, reaction = 2,
            hp = 8000000, hpMax = 10000000, powerType = 0, powerToken = "MANA", power = 1, powerMax = 1,
            absorb = 0,
        },
    }
    local inCombat = false
    _G.InCombatLockdown = function() return inCombat end
    _G.UnitExists = function(u) return units[u] ~= nil end
    _G.UnitName = function(u) return units[u] and units[u].name end
    _G.UnitClass = function(u) return units[u] and units[u].className, units[u] and units[u].class end
    _G.UnitRace = function(u) return units[u] and units[u].race end
    _G.UnitLevel = function(u) return units[u] and units[u].level end
    _G.UnitIsPlayer = function(u) return units[u] and units[u].isPlayer end
    _G.UnitClassification = function(u) return units[u] and units[u].classification end
    _G.UnitIsDeadOrGhost = function(u) return units[u] and units[u].dead end
    _G.UnitReaction = function(u) return units[u] and units[u].reaction end
    _G.UnitHealth = function(u) return units[u] and units[u].hp end
    _G.UnitHealthMax = function(u) return units[u] and units[u].hpMax end
    _G.UnitPowerType = function(u) return units[u] and units[u].powerType, units[u] and units[u].powerToken end
    _G.UnitPower = function(u) return units[u] and units[u].power end
    _G.UnitPowerMax = function(u) return units[u] and units[u].powerMax end
    _G.UnitGetTotalAbsorbs = function(u) return units[u] and units[u].absorb end

    local modelNamespace = {
        MSUF2 = {
            KeySetFromWords = function(words)
                local out = {}
                for word in words:gmatch("%S+") do out[word] = true end
                return out
            end,
            WordList = function(words)
                local out = {}
                for word in words:gmatch("%S+") do out[#out + 1] = word end
                return out
            end,
            AssignNamedValues = function(target, names, ...)
                local index = 0
                for name in names:gmatch("%S+") do
                    index = index + 1
                    target[name] = select(index, ...)
                end
            end,
        },
    }
    local modelChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Model.lua"))
    modelChunk("MidnightSimpleUnitFrames", modelNamespace)
    local Model = assert(modelNamespace.UFPreview and modelNamespace.UFPreview.Model, "preview model missing")
    local LiveUnitData = assert(Model.LiveUnitData, "LiveUnitData missing from preview model")
    local UNIT_DATA = assert(Model.UNIT_DATA, "UNIT_DATA missing from preview model")

    local live = assert(LiveUnitData("target"), "live target snapshot missing")
    Check(live.name == "Dummy Target", "live name not mirrored")
    Check(live.class == "MAGE" and live.className == "Mage", "live class not mirrored")
    Check(live.hpCur == 350 and live.hpMax == 1000, "live exact HP values not mirrored")
    Check(math.abs(live.hp - 0.35) < 1e-9, "live HP fraction not mirrored")
    Check(live.powerCur == 60 and live.powerMax == 200, "live exact power values not mirrored")
    Check(live.powerToken == "MANA", "live power token not mirrored")
    Check(live.level == "82", "live level not mirrored")
    Check(live.elite == true, "live elite classification not mirrored")
    Check(live.reactionKind == "enemy", "live reaction not mirrored")
    Check(live.absorb == 4200, "live absorb not mirrored")
    Check(live.liveUnit == "target", "live unit token missing")

    -- Boss preview key maps to boss1 and classifies as boss.
    local boss = assert(LiveUnitData("boss"), "live boss snapshot missing")
    Check(boss.name == "Council Boss", "boss snapshot did not read boss1")
    Check(boss.level == "??", "boss level -1 must render as ??")
    Check(boss.npcKind == "npcBoss", "boss type classification not mirrored")

    -- Missing unit: snapshot absent, render falls back to the stylized mock.
    Check(LiveUnitData("focus") == nil, "missing unit must fall back to mock data")
    local fallback = LiveUnitData("focus") or UNIT_DATA.focus
    Check(fallback == UNIT_DATA.focus, "render fallback expression must select the mock")

    -- Secret values never leak: the poisoned field falls back per-field.
    units.target.hp = SECRET
    local secretLive = assert(LiveUnitData("target"), "secret-guarded snapshot missing")
    Check(secretLive.hpCur == nil and secretLive.hpMax == nil, "secret HP leaked into exact values")
    Check(secretLive.hp == UNIT_DATA.target.hp, "secret HP must fall back to the stylized fraction")
    Check(secretLive.name == "Dummy Target", "unrelated fields must stay live under secret HP")
    units.target.hp = 350

    -- Combat: sampling is refused outright (previews only refresh out of combat).
    inCombat = true
    Check(LiveUnitData("target") == nil, "live sampling must be refused in combat")
    inCombat = false

    -- Zero absorb keeps the stylized element sample instead of blanking it.
    units.target.absorb = 0
    Check(LiveUnitData("target").absorb == nil, "zero absorb must fall back to the stylized sample")
    units.target.absorb = 4200
end

-- ================================================================ 3) wiring contracts
do
    local render = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
    Check(render:find("local data = (D.LiveUnitData and D.LiveUnitData(key)) or UNIT_DATA[key] or UNIT_DATA.player or {}", 1, true) ~= nil,
        "unit preview refresh no longer prefers the live snapshot")
    Check(render:find("tonumber(data.hpMax) or 1000000", 1, true) ~= nil
        and render:find("tonumber(data.hpCur) or floor(hpMax * data.hp + 0.5)", 1, true) ~= nil,
        "unit preview hp text no longer uses exact live values")
    Check(render:find("copy.hpCur = nil", 1, true) ~= nil and render:find("copy.powerCur = nil", 1, true) ~= nil,
        "combat animation copy must strip exact values so texts follow the animated fraction")
    Check(render:find('D.LiveUnitData("targettarget")', 1, true) ~= nil,
        "ToT inline preview no longer prefers the live snapshot")
    Check(render:find("D.SyncLiveStateDriver(box, key)", 1, true) ~= nil,
        "unit preview refresh no longer keeps the live-state driver bound")
    Check(render:find("_G.SetPortraitTexture(mock.portrait.tex, data.liveUnit)", 1, true) ~= nil,
        "unit preview no longer mirrors the live portrait")

    local view = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua")
    Check(view:find('driver:RegisterEvent("PLAYER_REGEN_DISABLED")', 1, true) ~= nil
        and view:find("driver:UnregisterAllEvents()", 1, true) ~= nil,
        "unit live-state driver lost its combat drop contract")
    Check(view:find("ReleaseUnitPreviewLiveState(self)", 1, true) ~= nil,
        "unit live-state driver is not released on hide")

    local groupRender = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
    Check(groupRender:find('MSUF.UFPreview.LiveUnitData("player")', 1, true) ~= nil,
        "group preview scene no longer samples the live player")
    Check(groupRender:find("(liveData and liveData.hp) or 0.72", 1, true) ~= nil,
        "group preview hp fraction no longer mirrors the live player")
    Check(groupRender:find("(scene.liveData and scene.liveData.hpMax) or 1000000", 1, true) ~= nil
        and groupRender:find("(scene.liveData and scene.liveData.powerMax) or 100", 1, true) ~= nil,
        "group preview texts no longer use exact live values")
    Check(groupRender:find("(scene.liveData and scene.liveData.name)", 1, true) ~= nil,
        "group preview name no longer mirrors the live player")

    local groupNative = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua")
    Check(groupNative:find("function box:ArmLiveStateDriver()", 1, true) ~= nil
        and groupNative:find("function box:ReleaseLiveStateDriver()", 1, true) ~= nil,
        "group live-state driver lifecycle missing")

    local model = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Model.lua")
    Check(model:find("MSUF_UFCore_RequestLayoutForUnit", 1, true) == nil,
        "dead MSUF_UFCore_RequestLayoutForUnit call must stay removed")
    Check(model:find("elseif type(_G.MSUF_UFCore_NotifyConfigChanged) == \"function\" then", 1, true) ~= nil,
        "panel-less preview commits lost their full-apply fallback")
end

print("PREVIEW LIVE PARITY SMOKE PASS - nudges reach live frames; previews mirror live state with zero combat sampling")
