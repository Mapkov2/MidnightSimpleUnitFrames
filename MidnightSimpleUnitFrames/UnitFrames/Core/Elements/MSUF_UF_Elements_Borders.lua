local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local V = MSUF.UFVisuals or {}
local UF = V.UF or MSUF.UF
local CreateFrame = V.CreateFrame or CreateFrame
local UnitExists = V.UnitExists or UnitExists
local UnitThreatSituation = V.UnitThreatSituation or UnitThreatSituation
local UnitGroupRolesAssigned = V.UnitGroupRolesAssigned or UnitGroupRolesAssigned
local tonumber = V.tonumber or tonumber
local type = V.type or type
local DispelState = V.DispelState or (UF and UF.DispelState) or {}
local IsNil = V.IsNil or function(value) return value == nil end
local NotSecretValue = V.NotSecretValue or function(_) return true end
local EMPTY_EVENTS = V.EMPTY_EVENTS or {}
local BORDER_THREAT_EVENTS = V.BORDER_THREAT_EVENTS or { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local SetShown = V.SetShown

local Borders = {}
local IsAggroBorderUnit

function Borders.GetEvents(frame, spec)
    local cfg = spec and spec.border
    if not cfg then
        return EMPTY_EVENTS
    end
    if cfg.aggro == true and IsAggroBorderUnit(frame) then
        return BORDER_THREAT_EVENTS
    end
    return EMPTY_EVENTS
end

function Borders.GetUnitlessEvents(frame, spec)
    return EMPTY_EVENTS
end

local EDGE_KEYS = { "top", "bottom", "left", "right" }

local function EnsureBorderOverlay(parent)
    local overlay = parent.MSUFBorderOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, parent)
        overlay:SetAllPoints(parent)
        overlay:EnableMouse(false)
        parent.MSUFBorderOverlay = overlay
    end
    if parent.GetFrameLevel and overlay.SetFrameLevel then
        local level = (parent:GetFrameLevel() or 1) + 40
        if overlay._msufBorderLevel ~= level then
            overlay:SetFrameLevel(level)
            overlay._msufBorderLevel = level
        end
    end
    return overlay
end

local function EnsureEdge(parent, key)
    parent.MSUFBorderEdges = parent.MSUFBorderEdges or {}
    local overlay = EnsureBorderOverlay(parent)
    local edge = parent.MSUFBorderEdges[key]
    if edge and edge.GetParent and edge:GetParent() ~= overlay then
        edge:Hide()
        edge = nil
        parent.MSUFBorderEdges[key] = nil
    end
    if edge then
        return edge
    end
    edge = overlay:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(0, 0, 0, 1)
    parent.MSUFBorderEdges[key] = edge
    return edge
end

local function LayoutBorder(frame, thickness)
    EnsureBorderOverlay(frame)
    thickness = tonumber(thickness) or 1
    if thickness < 1 then
        thickness = 1
    end
    local top = EnsureEdge(frame, "top")
    local bottom = EnsureEdge(frame, "bottom")
    local left = EnsureEdge(frame, "left")
    local right = EnsureEdge(frame, "right")
    if frame._msufBorderThickness == thickness and frame._msufBorderLayoutReady == true then
        return
    end
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    left:ClearAllPoints()
    right:ClearAllPoints()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", thickness, thickness)
    top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -thickness, -thickness)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
    left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    right:SetWidth(thickness)
    frame._msufBorderThickness = thickness
    frame._msufBorderLayoutReady = true
end

local function BorderNormalEnabled(cfg)
    return cfg and cfg.enabled == true and (tonumber(cfg.thickness) or 0) > 0
end

local function IsBossUnit(unit)
    if type(unit) ~= "string" or unit:sub(1, 4) ~= "boss" then return false end
    local index = tonumber(unit:sub(5))
    return index ~= nil and index >= 1 and index <= 5
end

function IsAggroBorderUnit(frame)
    local unit = frame and frame.unit
    if unit == "player" or unit == "target" or unit == "focus" then return true end
    return IsBossUnit(unit) or (frame and frame.MSUFSpec and frame.MSUFSpec.scope == "group")
end

local function IsPurgeBorderUnit(frame)
    local unit = frame and frame.unit
    return unit == "target" or unit == "focus" or unit == "targettarget"
end

local function TestScopeApplies(frame, scope)
    if not frame then return false end
    scope = scope or "shared"
    if scope == "shared" then return true end
    local spec = frame.MSUFSpec
    local groupKind = frame._msufGFKind or spec and spec.groupKind
    if scope == "party" or scope == "gf_party" then
        return groupKind == "party"
    elseif scope == "raid" or scope == "gf_raid" then
        return groupKind == "raid" or groupKind == "mythicraid"
    elseif scope == "mythicraid" or scope == "gf_mythicraid" then
        return groupKind == "mythicraid"
    elseif groupKind then
        return false
    elseif scope == "boss" then
        return IsBossUnit(frame.unit)
    end
    return frame.unit == scope or frame.configKey == scope or frame.unitKey == scope
end

local function RefreshBorderTestFrames()
    if UF and UF.RefreshBorders then
        UF.RefreshBorders()
    end
    local gf = MSUF and MSUF.GF
    if gf then
        if gf.RefreshVisuals then
            gf.RefreshVisuals()
        elseif gf.MarkAllDirty then
            gf.MarkAllDirty((gf.DIRTY_VISUAL or 2) + (gf.DIRTY_LAYOUT or 32))
        end
    end
end

local function RefreshBorderTestModesActive()
    _G.MSUF_BorderTestModesActive = _G.MSUF_AggroBorderTestMode == true
        or _G.MSUF_DispelBorderTestMode == true
        or _G.MSUF_PurgeBorderTestMode == true
        or _G.MSUF_BossTargetBorderTestMode == true
end

local function SetBorderTestMode(flag, scopeFlag, active, scope)
    _G[flag] = active == true
    if scopeFlag then _G[scopeFlag] = scope or "shared" end
    RefreshBorderTestModesActive()
    RefreshBorderTestFrames()
    return true
end

_G.MSUF_SetAggroBorderTestMode = _G.MSUF_SetAggroBorderTestMode or function(active, scope)
    return SetBorderTestMode("MSUF_AggroBorderTestMode", "MSUF_AggroBorderTestScope", active, scope)
end

_G.MSUF_SetDispelBorderTestMode = _G.MSUF_SetDispelBorderTestMode or function(active, scope)
    return SetBorderTestMode("MSUF_DispelBorderTestMode", "MSUF_DispelBorderTestScope", active, scope)
end

_G.MSUF_SetPurgeBorderTestMode = _G.MSUF_SetPurgeBorderTestMode or function(active, scope)
    return SetBorderTestMode("MSUF_PurgeBorderTestMode", "MSUF_PurgeBorderTestScope", active, scope)
end

_G.MSUF_SetBossTargetBorderTestMode = _G.MSUF_SetBossTargetBorderTestMode or function(active)
    return SetBorderTestMode("MSUF_BossTargetBorderTestMode", nil, active, "boss")
end

local function AggroTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_AggroBorderTestMode == true
        and IsAggroBorderUnit(frame)
        and TestScopeApplies(frame, _G.MSUF_AggroBorderTestScope)
end

local function DispelTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_DispelBorderTestMode == true
        and TestScopeApplies(frame, _G.MSUF_DispelBorderTestScope)
end

local function PurgeTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_PurgeBorderTestMode == true
        and IsPurgeBorderUnit(frame)
        and TestScopeApplies(frame, _G.MSUF_PurgeBorderTestScope)
end

local function BossTargetTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_BossTargetBorderTestMode == true
        and IsBossUnit(frame and frame.unit)
end

local function BorderHighlightEnabled(frame, cfg)
    if cfg and (cfg.dispel == true or cfg.aggro == true or cfg.purge == true) then
        return true
    end
    if _G.MSUF_BorderTestModesActive ~= true then
        return false
    end
    return AggroTestApplies(frame)
        or DispelTestApplies(frame)
        or PurgeTestApplies(frame)
        or BossTargetTestApplies(frame)
end

local function BorderNormalThickness(cfg)
    local thickness = cfg and tonumber(cfg.thickness) or nil
    if not thickness or thickness < 1 then
        return 1
    end
    return thickness
end

local function BorderHighlightThickness(cfg)
    local thickness = cfg and tonumber(cfg.highlightThickness) or nil
    if not thickness or thickness < 1 then
        thickness = cfg and tonumber(cfg.thickness) or nil
    end
    if not thickness or thickness < 1 then
        return 1
    end
    return thickness
end

local function SetBorder(frame, show, r, g, b, a)
    if not frame.MSUFBorderEdges then
        return
    end
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    if frame._msufBorderShown == show
        and frame._msufBorderR == r
        and frame._msufBorderG == g
        and frame._msufBorderB == b
        and frame._msufBorderA == a then
        return
    end
    frame._msufBorderShown = show
    frame._msufBorderR, frame._msufBorderG, frame._msufBorderB, frame._msufBorderA = r, g, b, a
    for i = 1, #EDGE_KEYS do
        local edge = frame.MSUFBorderEdges[EDGE_KEYS[i]]
        if edge then
            edge:SetVertexColor(r, g, b, a)
            SetShown(edge, show)
        end
    end
end

local function AuraBorderState(frame)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.border
    local wantsDispel = cfg and cfg.dispel == true
    if frame._msufUFBorderAuraStateKnown == true and frame._msufUFBorderAuraEnabled == (wantsDispel and true or false) then
        return frame._msufUFBorderAuraState,
            frame._msufUFBorderAuraColorR,
            frame._msufUFBorderAuraColorG,
            frame._msufUFBorderAuraColorB,
            frame._msufUFBorderAuraColorA
    end
    if frame._msufGFBorderAuraStateKnown == true and frame._msufGFBorderAuraEnabled == (wantsDispel and true or false) then
        return frame._msufGFBorderAuraState,
            frame._msufGFBorderAuraColorR,
            frame._msufGFBorderAuraColorG,
            frame._msufGFBorderAuraColorB,
            frame._msufGFBorderAuraColorA
    end
    return nil
end

local function ThreatState(frame)
    if not (UnitThreatSituation and frame and frame.unit) then
        return false
    end
    local unit = frame.unit
    local spec = frame.MSUFSpec
    if spec and spec.scope == "group" then
        local exists = UnitExists and UnitExists(unit)
        if not IsNil(exists) and NotSecretValue(exists) and exists == false then
            return false
        end
        local cfg = spec.border
        local mode = cfg and cfg.aggroMode
        if mode == "TANK" or mode == "HEALER" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
            if IsNil(role) or not NotSecretValue(role) or role ~= mode then
                return false
            end
        end
        local status = UnitThreatSituation(unit)
        if IsNil(status) or not NotSecretValue(status) then
            return false
        end
        status = tonumber(status)
        return status ~= nil and status >= 1
    end

    local status
    if unit == "player" then
        status = UnitThreatSituation("player", "target")
        if IsNil(status) then
            status = UnitThreatSituation("player")
        end
    else
        status = UnitThreatSituation("player", unit)
    end
    if IsNil(status) or not NotSecretValue(status) then
        return false
    end
    status = tonumber(status)
    return status ~= nil and status >= 2
end

local function GeneralDB()
    local db = _G.MSUF_DB
    return db and db.general or nil
end

local function DispelTestColor(frame)
    local dispel = frame and frame.MSUFSpec and frame.MSUFSpec.dispel
    if dispel and dispel.colorMode == "TYPE" then
        local dispelType = tostring(_G.MSUF_DispelBorderTestType or "Magic")
        local prefix = "type" .. dispelType
        return dispel[prefix .. "R"] or dispel.r or 0.25,
            dispel[prefix .. "G"] or dispel.g or 0.75,
            dispel[prefix .. "B"] or dispel.b or 1,
            1
    end
    return dispel and dispel.r or 0.25, dispel and dispel.g or 0.75, dispel and dispel.b or 1, 1
end

local function AggroColor(cfg)
    return cfg and cfg.aggroR or 1.00,
        cfg and cfg.aggroG or 0.55,
        cfg and cfg.aggroB or 0.00,
        1
end

local function PurgeColor(cfg)
    local general = GeneralDB()
    return cfg and cfg.purgeR or tonumber(general and (general.hlPurgeColorR or general.purgeBorderColorR)) or 1.00,
        cfg and cfg.purgeG or tonumber(general and (general.hlPurgeColorG or general.purgeBorderColorG)) or 0.85,
        cfg and cfg.purgeB or tonumber(general and (general.hlPurgeColorB or general.purgeBorderColorB)) or 0.00,
        1
end

local function BossTargetColor(cfg)
    if cfg and cfg.bossTargetR then
        return cfg.bossTargetR or 1, cfg.bossTargetG or 0.82, cfg.bossTargetB or 0, 1
    end
    local general = GeneralDB()
    local color = general and general.bossTargetHighlightColor
    if type(color) == "table" then
        return tonumber(color[1]) or 1, tonumber(color[2]) or 0.82, tonumber(color[3]) or 0, tonumber(color[4]) or 1
    end
    return 1, 0.82, 0, 1
end

function Borders.Create(frame)
    LayoutBorder(frame, 1)
end

function Borders.Apply(frame, spec)
    local cfg = spec and spec.border
    if not cfg or not (BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg)) then
        LayoutBorder(frame, 1)
        SetBorder(frame, false)
    elseif cfg.dispel == true or cfg.aggro == true or cfg.purge == true then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        Borders.Update(frame, "MSUF_BORDER_APPLY", frame.unit)
    else
        LayoutBorder(frame, BorderNormalThickness(cfg))
        SetBorder(frame, true, cfg.r or 0, cfg.g or 0, cfg.b or 0, cfg.a or 1)
    end
end

function Borders.IsEnabled(frame, spec)
    local cfg = spec and spec.border
    return BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg) or false
end

function Borders.Disable(frame)
    SetBorder(frame, false)
end

function Borders.Update(frame)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.border
    local normalEnabled = BorderNormalEnabled(cfg)
    if not cfg or not (normalEnabled or BorderHighlightEnabled(frame, cfg)) then
        SetBorder(frame, false)
        return
    end
    local testActive = _G.MSUF_BorderTestModesActive == true
    local auraState, auraR, auraG, auraB, auraA = AuraBorderState(frame)
    if testActive and DispelTestApplies(frame) then
        local r, g, b, a = DispelTestColor(frame)
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, r, g, b, a)
        return
    end
    if cfg.dispel and auraState == "dispel" then
        local r, g, b, a = auraR or 0.25, auraG or 0.75, auraB or 1, auraA or 1
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, r, g, b, a)
        return
    end
    if (testActive and AggroTestApplies(frame)) or (cfg.aggro and IsAggroBorderUnit(frame) and ThreatState(frame)) then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, AggroColor(cfg))
        return
    end
    if testActive and PurgeTestApplies(frame) then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, PurgeColor(cfg))
        return
    end
    if testActive and BossTargetTestApplies(frame) then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, BossTargetColor(cfg))
        return
    end
    if not normalEnabled then
        SetBorder(frame, false)
        return
    end
    LayoutBorder(frame, BorderNormalThickness(cfg))
    SetBorder(frame, true, cfg.r or 0, cfg.g or 0, cfg.b or 0, cfg.a or 1)
end

UF.RegisterElement("Borders", Borders)

local function RefreshUnitDispelFrame(frame)
    if not frame then return end
    local active = frame._msufActiveElements
    if not active then return end
    local unit = frame.unit
    if not unit or unit == "" then return end
    local event = "MSUF_DISPEL_REFRESH"
    local dispel = UF.elements and UF.elements.DispelOverlay
    if active.DispelOverlay == true and dispel and dispel.Update then
        dispel.Update(frame, event, unit)
    end
    if active.Borders == true then
        Borders.Update(frame, event, unit)
    end
end

_G.MSUF_RefreshUnitDispelOverlays = function()
    if UF.ForEachFrame then
        UF.ForEachFrame(RefreshUnitDispelFrame)
    end
end
_G.MSUF_RefreshUnitDispelOverlay = RefreshUnitDispelFrame
