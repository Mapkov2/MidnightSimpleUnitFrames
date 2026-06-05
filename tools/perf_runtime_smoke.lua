_G = _G or _ENV

table.wipe = table.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
_G.wipe = _G.wipe or table.wipe

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local root = "MidnightSimpleUnitFrames/"
if not exists(root .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua") then
    root = ""
end

local function loadAddon(path, MSUF)
    local chunk, err = loadfile(root .. path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local function fontString(shown)
    local fs = { shown = shown ~= false }
    function fs:IsShown() return self.shown == true end
    function fs:SetShown(value) self.shown = value == true end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:SetText(value) self.text = value end
    function fs:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
    function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    return fs
end

local function region(parent)
    local r = { parent = parent, shown = false }
    function r:SetShown(value) self.shown = value == true end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:SetAlpha(value) self.alpha = value end
    function r:SetColorTexture(r1, g1, b1, a1) self.colorTexture = { r1, g1, b1, a1 } end
    function r:SetVertexColor(r1, g1, b1, a1) self.vertexColor = { r1, g1, b1, a1 } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetPoint(...) self.points = { ... } end
    function r:SetAllPoints(target) self.allPoints = target or true end
    function r:SetHeight(value) self.height = value end
    function r:SetWidth(value) self.width = value end
    function r:SetSize(w, h) self.width, self.height = w, h or w end
    function r:SetFrameLevel(value) self.frameLevel = value end
    function r:GetFrameLevel() return self.frameLevel or 0 end
    function r:SetDrawLayer(layer, sub) self.drawLayer, self.subLayer = layer, sub end
    function r:GetParent() return self.parent end
    function r:EnableMouse() end
    function r:CreateTexture()
        local tex = region(self)
        self.createdTextures = (self.createdTextures or 0) + 1
        return tex
    end
    return r
end

local function frame()
    local f = region(nil)
    function f:CreateTexture()
        local tex = region(self)
        self.createdTextures = (self.createdTextures or 0) + 1
        return tex
    end
    return f
end

local function smokeTextRuntime()
    local MSUF = {}
    MSUF.UF = { elements = {}, RegisterElement = function(name, element) MSUF.UF.elements[name] = element end }
    MSUF.Secrets = { IsSecret = function() return false end, IsNil = function(value) return value == nil end }
    MSUF.Apply = {}
    MSUF.UFText = {
        tonumber = tonumber,
        type = type,
        format = string.format,
        floor = math.floor,
        max = math.max,
        abs = math.abs,
        GetTime = function() return 1 end,
        UnitHealth = function() return 100 end,
        UnitHealthMax = function() return 100 end,
        UnitPower = function() return 50 end,
        UnitPowerMax = function() return 100 end,
        UnitPowerType = function() return 0 end,
        UnitHealthPercent = function() return 100 end,
        UnitPowerPercent = function() return 50 end,
        IsSecret = function() return false end,
        IsNil = function(value) return value == nil end,
    }
    _G.MSUF_NS = MSUF
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua", MSUF)
    loadAddon("UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua", MSUF)

    local Text = MSUF.UFText
    local rtFns = assert(Text.RuntimeHotFunctions, "text runtime hot functions missing")
    local f = {
        unit = "player",
        hpTextLeft = fontString(true),
        powerTextLeft = fontString(true),
    }
    local spec = {
        showHealthText = true,
        showPowerText = true,
        power = { enabled = true },
        text = {
            healthLeft = "CURRENT",
            powerLeft = "CURRENT",
            healthThrottle = 0.1,
            powerThrottle = 0.1,
        },
    }
    local rt = Text.CompileTextRuntime(f, spec, spec.text)
    assert(rt.healthHot == rtFns.healthHot, "health hot function was not compiled")
    assert(rt.healthDirty == rtFns.healthDirty, "health dirty function was not compiled")
    assert(rt.powerHot == rtFns.powerHot, "power hot function was not compiled")
    assert(rt.powerDirty == rtFns.powerDirty, "power dirty function was not compiled")
end

local function smokeGroupRuntime()
    local MSUF = {}
    MSUF.UF = { elements = {}, RegisterElement = function(name, element) MSUF.UF.elements[name] = element end }
    MSUF.GF = {}
    MSUF.Secrets = { IsSecret = function() return false end, IsNil = function(value) return value == nil end, UnitMissing = function() return false end }
    MSUF.UFStatusRuntime = {}
    for _, key in ipairs({
        "UpdateRaidMarker", "UpdateLeaderPair", "UpdateReadyCheck", "UpdateSummon",
        "UpdateIncomingRes", "UpdatePhase", "UpdateStatusText", "UpdateRaidGroup", "UpdateRole",
    }) do
        MSUF.UFStatusRuntime[key] = function() end
    end

    _G.MSUF_NS = MSUF
    _G.MSUF = MSUF
    _G.MSUF_DB = { general = {}, gf_party = {} }
    _G.GetTime = function() return 1 end
    _G.GetNumGroupMembers = function() return 5 end
    _G.GetRaidRosterInfo = function() return nil end
    _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
    _G.UnitGUID = function(unit) return unit end
    _G.UnitHealthPercent = function() return 100 end
    _G.UnitThreatSituation = function() return 1 end
    _G.CreateFrame = function(_, _, parent)
        local holder = frame()
        holder.parent = parent
        return holder
    end

    MSUF.GF.GetConf = function()
        return {
            healthFadeEnabled = true,
            targetIndicator = true,
            hlFocusEnabled = true,
            ciEnabled = true,
            ciSlotBR = "aggro",
            statusText = true,
            statusGhostText = true,
            statusAFKText = true,
        }
    end

    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua", MSUF)
    loadAddon("UnitFrames/Engine/Group/MSUF_UF_Group_Indicators.lua", MSUF)

    local f = frame()
    f.unit = "party1"
    f.hpBar = region(f)
    f.hpText = fontString(true)
    f.hpTextLeft = fontString(true)
    f.hpTextCenter = fontString(true)
    f.hpTextRight = fontString(true)
    f.bg = region(f)
    f.hpBarBG = region(f)
    f.MSUFSpec = MSUF.GF.CompileSpec("party", f, "party1")

    MSUF.UF.elements.GroupStatusRuntime.Apply(f)
    assert(type(f.MSUFSpec.status.runtimeDispatch) == "table", "status runtimeDispatch missing")

    MSUF.UF.elements.GroupVisuals.Apply(f)
    assert(type(f.MSUFSpec.group.runtimeOnHealth) == "function", "group runtimeOnHealth missing")
    assert(type(f.MSUFSpec.group.runtimeOnTarget) == "function", "group runtimeOnTarget missing")
    assert(type(f.MSUFSpec.group.runtimeOnFocus) == "function", "group runtimeOnFocus missing")
    assert(type(f.MSUFSpec.group.runtimeOnRangeAlpha) == "function", "group runtimeOnRangeAlpha missing")

    MSUF.UF.elements.GroupCornerIndicators.Apply(f)
    assert(type(f.MSUFSpec.cornerIndicators.runtimeThreat) == "function", "corner runtimeThreat missing")
end

smokeTextRuntime()
smokeGroupRuntime()

print("perf runtime smoke ok")
