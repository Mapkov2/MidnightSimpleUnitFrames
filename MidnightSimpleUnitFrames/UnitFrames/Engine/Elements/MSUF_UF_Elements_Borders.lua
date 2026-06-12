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
local IsNil = V.IsNil or function(value) return value == nil end
local NotSecretValue = V.NotSecretValue or function(_) return true end
local IsSecretValue = _G.issecretvalue or function(_) return false end
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
local DEFAULT_HIGHLIGHT_PRIORITY = { "dispel", "aggro", "purge", "bossTarget" }

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
    local edges = frame.MSUFBorderEdges
    if frame._msufBorderThickness == thickness
        and frame._msufBorderLayoutReady == true
        and edges and edges.top and edges.bottom and edges.left and edges.right then
        return
    end
    local top = EnsureEdge(frame, "top")
    local bottom = EnsureEdge(frame, "bottom")
    local left = EnsureEdge(frame, "left")
    local right = EnsureEdge(frame, "right")
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
        if gf.RefreshBorder then
            gf.RefreshBorder()
        elseif gf.RefreshVisuals then
            gf.RefreshVisuals(nil, gf.DIRTY_BORDER or gf.DIRTY_VISUAL)
        elseif gf.MarkAllDirty then
            gf.MarkAllDirty(gf.DIRTY_BORDER or gf.DIRTY_VISUAL or 2)
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
    if cfg and cfg.aggro == true then
        return true
    end
    if cfg and cfg.dispel == true then
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
    local secretColor = IsSecretValue(r) or IsSecretValue(g) or IsSecretValue(b) or IsSecretValue(a)
    local showChanged = frame._msufBorderShown ~= show
    local colorChanged = secretColor == true
    if not colorChanged then
        if frame._msufBorderSecretColor == true then
            colorChanged = true
        else
            colorChanged = frame._msufBorderR ~= r
                or frame._msufBorderG ~= g
                or frame._msufBorderB ~= b
                or frame._msufBorderA ~= a
        end
    end
    if not (showChanged or colorChanged) then
        return
    end
    frame._msufBorderShown = show
    if secretColor then
        frame._msufBorderSecretColor = true
        frame._msufBorderR, frame._msufBorderG, frame._msufBorderB, frame._msufBorderA = nil, nil, nil, nil
    else
        frame._msufBorderSecretColor = nil
        frame._msufBorderR, frame._msufBorderG, frame._msufBorderB, frame._msufBorderA = r, g, b, a
    end
    for i = 1, #EDGE_KEYS do
        local edge = frame.MSUFBorderEdges[EDGE_KEYS[i]]
        if edge then
            if colorChanged then
                edge:SetVertexColor(1, 1, 1, 1)
                edge:SetColorTexture(r, g, b, a)
            end
            if showChanged then
                SetShown(edge, show)
            end
        end
    end
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

local function UnitDispelOverlayEnabled(frame)
    local overlay = frame and frame.MSUFSpec and frame.MSUFSpec.dispelOverlay
    return overlay and overlay.enabled == true or false
end

local function UnitDispelOverlayTarget(frame, cfg)
    if cfg and cfg.onHealth ~= false then
        return frame and (frame.hpBar or frame.Health or frame.health) or frame
    end
    return frame
end

local function EnsureUnitDispelOverlay(frame)
    local tex = frame and frame.MSUFUnitDispelOverlay
    if tex then return tex end
    if not frame then return nil end
    tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(1, 1, 1, 1)
    tex:Hide()
    frame.MSUFUnitDispelOverlay = tex
    return tex
end

local function LayoutUnitDispelOverlay(frame, tex, cfg)
    local target = UnitDispelOverlayTarget(frame, cfg)
    if not (target and tex) then return end
    local style = cfg and cfg.style or "FULL"
    if style ~= "TOP" and style ~= "BOTTOM" and style ~= "LEFT" and style ~= "RIGHT" then
        style = "FULL"
    end
    local size = tonumber(frame and frame.MSUFSpec and frame.MSUFSpec.border and frame.MSUFSpec.border.highlightThickness) or 3
    if size < 1 then size = 1 end
    if tex._msufOverlayTarget == target and tex._msufOverlayStyle == style and tex._msufOverlaySize == size then
        return
    end
    tex:ClearAllPoints()
    if style == "FULL" then
        tex:SetAllPoints(target)
    elseif style == "TOP" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetHeight(size)
    elseif style == "BOTTOM" then
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        tex:SetHeight(size)
    elseif style == "LEFT" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetWidth(size)
    else
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        tex:SetWidth(size)
    end
    tex._msufOverlayTarget = target
    tex._msufOverlayStyle = style
    tex._msufOverlaySize = size
end

local function SetUnitDispelOverlayColor(tex, r, g, b, a)
    if not tex then return end
    r, g, b, a = r or 0.25, g or 0.75, b or 1, a or 0.35
    if IsSecretValue(r) or IsSecretValue(g) or IsSecretValue(b) or IsSecretValue(a) then
        tex._msufDispelOverlaySecretColor = true
        tex._msufDispelOverlayR, tex._msufDispelOverlayG = nil, nil
        tex._msufDispelOverlayB, tex._msufDispelOverlayA = nil, nil
        tex:SetColorTexture(r, g, b, a)
        return
    end
    if tex._msufDispelOverlaySecretColor ~= true
        and tex._msufDispelOverlayR == r
        and tex._msufDispelOverlayG == g
        and tex._msufDispelOverlayB == b
        and tex._msufDispelOverlayA == a then
        return
    end
    tex._msufDispelOverlaySecretColor = nil
    tex._msufDispelOverlayR, tex._msufDispelOverlayG = r, g
    tex._msufDispelOverlayB, tex._msufDispelOverlayA = b, a
    tex:SetColorTexture(r, g, b, a)
end

local function UpdateUnitDispelOverlay(frame, cfg)
    local tex = frame and frame.MSUFUnitDispelOverlay
    if not (cfg and cfg.enabled == true and frame and frame._msufA3DispelOverlayActive == true) then
        if tex then SetShown(tex, false) end
        return
    end
    tex = tex or EnsureUnitDispelOverlay(frame)
    if not tex then return end
    LayoutUnitDispelOverlay(frame, tex, cfg)
    SetUnitDispelOverlayColor(tex,
        frame._msufA3DispelOverlayR or frame._msufA3DispelR or 0.25,
        frame._msufA3DispelOverlayG or frame._msufA3DispelG or 0.75,
        frame._msufA3DispelOverlayB or frame._msufA3DispelB or 1,
        tonumber(cfg.alpha) or 0.35)
    SetShown(tex, true)
end

local function NormalBorderColor(cfg)
    return cfg and cfg.r or 0, cfg and cfg.g or 0, cfg and cfg.b or 0, cfg and cfg.a or 1
end

local function HighlightPriorityOrder(cfg)
    local order = cfg and cfg.prioEnabled == true and cfg.prioOrder
    if type(order) == "table" then
        return order
    end
    return DEFAULT_HIGHLIGHT_PRIORITY
end

local function ApplyHighlightBorder(frame, cfg, key, testActive)
    if key == "dispel" then
        if testActive and DispelTestApplies(frame) then
            local r, g, b, a = DispelTestColor(frame)
            LayoutBorder(frame, BorderHighlightThickness(cfg))
            SetBorder(frame, true, r, g, b, a)
            return true
        end
        if cfg.dispel == true and frame._msufA3DispelActive == true then
            LayoutBorder(frame, BorderHighlightThickness(cfg))
            SetBorder(frame, true,
                frame._msufA3DispelR or 0.25,
                frame._msufA3DispelG or 0.75,
                frame._msufA3DispelB or 1,
                frame._msufA3DispelA or 1)
            return true
        end
    elseif key == "aggro" then
        if (testActive and AggroTestApplies(frame)) or (cfg.aggro and IsAggroBorderUnit(frame) and ThreatState(frame)) then
            LayoutBorder(frame, BorderHighlightThickness(cfg))
            SetBorder(frame, true, AggroColor(cfg))
            return true
        end
    elseif key == "purge" then
        if testActive and PurgeTestApplies(frame) then
            LayoutBorder(frame, BorderHighlightThickness(cfg))
            SetBorder(frame, true, PurgeColor(cfg))
            return true
        end
    elseif key == "bossTarget" then
        if testActive and BossTargetTestApplies(frame) then
            LayoutBorder(frame, BorderHighlightThickness(cfg))
            SetBorder(frame, true, BossTargetColor(cfg))
            return true
        end
    end
    return false
end

function Borders.Create(frame)
    LayoutBorder(frame, 1)
end

function Borders.Apply(frame, spec)
    local cfg = spec and spec.border
    local overlayCfg = spec and spec.dispelOverlay
    if frame then
        frame._msufBorderRuntimeCfg = cfg
        frame._msufBorderRuntimeOverlayCfg = overlayCfg
        frame._msufBorderRuntimeNormal = BorderNormalEnabled(cfg) or nil
        frame._msufBorderRuntimeHighlight = BorderHighlightEnabled(frame, cfg) or nil
    end
    UpdateUnitDispelOverlay(frame, overlayCfg)
    if not cfg or not (BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg)) then
        LayoutBorder(frame, 1)
        SetBorder(frame, false)
    elseif cfg.aggro == true or cfg.dispel == true or UnitDispelOverlayEnabled(frame) then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        Borders.Update(frame, "MSUF_BORDER_APPLY", frame.unit)
    else
        LayoutBorder(frame, BorderNormalThickness(cfg))
        SetBorder(frame, true, NormalBorderColor(cfg))
    end
end

function Borders.IsEnabled(frame, spec)
    local cfg = spec and spec.border
    return BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg) or UnitDispelOverlayEnabled(frame) or false
end

function Borders.Disable(frame)
    if frame and frame.MSUFUnitDispelOverlay then
        frame.MSUFUnitDispelOverlay:Hide()
    end
    if frame then
        frame._msufBorderRuntimeCfg = nil
        frame._msufBorderRuntimeOverlayCfg = nil
        frame._msufBorderRuntimeNormal = nil
        frame._msufBorderRuntimeHighlight = nil
    end
    SetBorder(frame, false)
end

function Borders.Update(frame)
    local cfg = frame and frame._msufBorderRuntimeCfg
    local overlayCfg = frame and frame._msufBorderRuntimeOverlayCfg
    if cfg == nil and frame and frame.MSUFSpec then
        cfg = frame.MSUFSpec.border
        overlayCfg = frame.MSUFSpec.dispelOverlay
    end
    UpdateUnitDispelOverlay(frame, overlayCfg)
    local normalEnabled = frame and frame._msufBorderRuntimeNormal == true
    local highlightEnabled = frame and frame._msufBorderRuntimeHighlight == true
    if _G.MSUF_BorderTestModesActive == true then
        highlightEnabled = BorderHighlightEnabled(frame, cfg)
    end
    if not cfg or not (normalEnabled or highlightEnabled) then
        SetBorder(frame, false)
        return
    end
    local testActive = _G.MSUF_BorderTestModesActive == true
    local priority = HighlightPriorityOrder(cfg)
    for i = 1, #priority do
        if ApplyHighlightBorder(frame, cfg, priority[i], testActive) then
            return
        end
    end
    if not normalEnabled then
        SetBorder(frame, false)
        return
    end
    LayoutBorder(frame, BorderNormalThickness(cfg))
    SetBorder(frame, true, NormalBorderColor(cfg))
end

UF.RegisterElement("Borders", Borders)

local function RefreshUnitDispelFrame()
    if UF and UF.RefreshBorders then
        UF.RefreshBorders()
    end
    return true
end

_G.MSUF_RefreshUnitDispelOverlays = RefreshUnitDispelFrame
_G.MSUF_RefreshUnitDispelOverlay = RefreshUnitDispelFrame
