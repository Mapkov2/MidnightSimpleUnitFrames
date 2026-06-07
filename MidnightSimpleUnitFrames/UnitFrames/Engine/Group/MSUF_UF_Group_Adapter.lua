local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.AttachFrame and UF.ApplySpec) then return end

local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local table_remove = table.remove
local Secrets = MSUF.Secrets or {}
local UnitMissing = Secrets.UnitMissing or function(_) return false end

GF.frames = GF.frames or setmetatable({}, { __mode = "k" })
GF.frameList = GF.frameList or {}
GF._scanScheduled = GF._scanScheduled or {}
GF._scanScheduledKind = GF._scanScheduledKind or {}
local scanScheduled = GF._scanScheduled
local scanScheduledKind = GF._scanScheduledKind
local scanSeen = setmetatable({}, { __mode = "k" })
local scanNonce = setmetatable({}, { __mode = "k" })
local scanUnit = setmetatable({}, { __mode = "k" })
local scanKind = setmetatable({}, { __mode = "k" })
local attrUnit = setmetatable({}, { __mode = "k" })
local attrHooked = setmetatable({}, { __mode = "k" })
local childKind = setmetatable({}, { __mode = "k" })
local NO_UNIT = false
local appliedSerial = setmetatable({}, { __mode = "k" })
local appliedUnit = setmetatable({}, { __mode = "k" })
local appliedKind = setmetatable({}, { __mode = "k" })
local appliedPowerEnabled = setmetatable({}, { __mode = "k" })
local appliedPowerHeight = setmetatable({}, { __mode = "k" })
local UNIT_ATTR = "unit"
local UNIT_CHANGED_REASON = "MSUF_UNIT_IDENTITY"

local APPLY_MASK = {
    Health = true, Power = true, Text = true, NameText = true,
    HealthText = true, PowerText = true, StatusIndicators = true,
    GroupStatusRuntime = true, Prediction = true,
    Alpha = true,
    Borders = true, GroupRangeFade = true, GroupVisuals = true,
    GroupCornerIndicators = true,
}
GF.GROUP_APPLY_MASK = APPLY_MASK

local UNIT_CHANGE_FAST_MASK = {
    GroupRangeFade = true,
    Prediction = true,
}

local ApplyUnitChangeFast

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

------------------------------------------------------------------------
-- Click-cast compatibility
------------------------------------------------------------------------
GF.ClickCastEnabled = true

local function ClickCastFrames(create)
    local frames = rawget(_G, "ClickCastFrames")
    if type(frames) ~= "table" and create == true then
        frames = {}
        _G.ClickCastFrames = frames
    end
    return type(frames) == "table" and frames or nil
end

local function Clique()
    local clique = rawget(_G, "Clique")
    return type(clique) == "table" and clique or nil
end

local function RefreshCliqueEnterLeave(clique, frame)
    if InCombat() or not (clique and frame) then return end
    if not (type(clique.ccframes) == "table" and clique.ccframes[frame]) then return end
    if type(clique.UnwrapOnEnterOnLeave) == "function"
        and type(clique.WrapOnEnterOnLeave) == "function"
    then
        clique:UnwrapOnEnterOnLeave(frame)
        clique:WrapOnEnterOnLeave(frame)
    elseif type(clique.ApplyAttributes) == "function" then
        clique:ApplyAttributes()
    end
end

function GF.RegisterClickCastFrame(frame, refreshEnterLeave)
    if not (frame and frame.RegisterForClicks) then return false end
    if frame._msufGFIsPreviewFrame or frame._msufGFPreviewActive then return false end

    local frames = ClickCastFrames(true)
    if frames then frames[frame] = true end
    frame._msufGFClickCastRegistered = true

    local clique = Clique()
    if not (clique and type(clique.ccframes) == "table") then return true end
    if InCombat() then return true end

    if type(clique.RegisterUnitFrame) == "function" then
        clique:RegisterUnitFrame(frame)
    end
    if refreshEnterLeave == true then
        RefreshCliqueEnterLeave(clique, frame)
    end
    return true
end

function GF.UnregisterClickCastFrame(frame)
    if not frame then return false end
    local frames = ClickCastFrames(false)
    if frames then frames[frame] = nil end
    frame._msufGFClickCastRegistered = nil

    local clique = Clique()
    if not clique or InCombat() then return true end

    if type(clique.UnregisterUnitFrame) == "function" then
        clique:UnregisterUnitFrame(frame)
    else
        if type(clique.UnwrapOnEnterOnLeave) == "function"
            and type(clique.ccframes) == "table"
            and clique.ccframes[frame]
        then
            clique:UnwrapOnEnterOnLeave(frame)
        end
        if type(clique.ccframes) == "table" then
            clique.ccframes[frame] = nil
        end
        if type(clique.ApplyAttributes) == "function" then
            clique:ApplyAttributes()
        end
    end
    return true
end

local function ApplyClickCast(frame, spec)
    local layout = spec and spec.groupLayout
    if layout and layout.clickCastEnabled == false then
        return GF.UnregisterClickCastFrame(frame)
    end
    return GF.RegisterClickCastFrame(frame, true)
end

function GF.RefreshClickCastFrames()
    if not GF.ForEachFrame then return false end
    GF.ForEachFrame(function(frame)
        ApplyClickCast(frame, frame and frame.MSUFSpec)
    end, true)
    return true
end

local function TooltipAllowed()
    local tooltips = MSUF and MSUF.Tooltips
    if tooltips and type(tooltips.Allowed) == "function" then
        return tooltips.Allowed()
    end
    return true
end

local function ShowTooltip(frame)
    if not (frame and frame.unit) or UnitMissing(frame.unit) then
        return
    end
    if not TooltipAllowed() then
        return
    end
    local tooltips = MSUF and MSUF.Tooltips
    if tooltips and type(tooltips.ShowUnit) == "function" then
        tooltips.ShowUnit(frame, frame.unit)
        return
    end
    if UnitFrame_OnEnter then
        UnitFrame_OnEnter(frame)
    elseif GameTooltip then
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetUnit(frame.unit)
        GameTooltip:Show()
    end
end

local function EnsureHoverLine(parent, key)
    parent._msufGFHoverLines = parent._msufGFHoverLines or {}
    local tex = parent._msufGFHoverLines[key]
    if not tex then
        tex = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        parent._msufGFHoverLines[key] = tex
    end
    return tex
end

local function SetHoverShown(frame, shown)
    local holder = frame and frame.highlightBorder
    if not holder then return end
    holder:SetShown(shown == true)
end

local function ShowHoverHighlight(frame)
    local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.group
    if not (cfg and cfg.hoverHighlightEnabled == true) then
        SetHoverShown(frame, false)
        return
    end
    local holder = frame.highlightBorder
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:EnableMouse(false)
        frame.highlightBorder = holder
    end
    local edge = tonumber(cfg.hoverHighlightSize) or 1
    if edge < 1 then edge = 1 end
    local r, g, b = cfg.hoverHighlightR or 1, cfg.hoverHighlightG or 1, cfg.hoverHighlightB or 1
    local top = EnsureHoverLine(holder, "top")
    local bottom = EnsureHoverLine(holder, "bottom")
    local left = EnsureHoverLine(holder, "left")
    local right = EnsureHoverLine(holder, "right")
    top:ClearAllPoints()
    top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -edge, 0)
    top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", edge, 0)
    top:SetHeight(edge)
    bottom:ClearAllPoints()
    bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -edge, 0)
    bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", edge, 0)
    bottom:SetHeight(edge)
    left:ClearAllPoints()
    left:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, edge)
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, -edge)
    left:SetWidth(edge)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, edge)
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, -edge)
    right:SetWidth(edge)
    for _, tex in pairs(holder._msufGFHoverLines) do
        tex:SetVertexColor(r, g, b, 1)
        tex:Show()
    end
    if holder.SetFrameLevel and frame.GetFrameLevel then
        holder:SetFrameLevel((frame:GetFrameLevel() or 0) + 2)
    end
    holder:Show()
end

local function HookButton(frame)
    if frame._msufGFHooked then return end
    frame._msufGFHooked = true
    frame:HookScript("OnEnter", function(self)
        ShowHoverHighlight(self)
        if _G.MSUF_RoundedUF_OnGroupMouseover then
            _G.MSUF_RoundedUF_OnGroupMouseover(self, true)
        end
        if not TooltipAllowed() then return end
        self._msufGFTooltipToken = (self._msufGFTooltipToken or 0) + 1
        local token = self._msufGFTooltipToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                if self._msufGFTooltipToken ~= token then return end
                if self.IsMouseOver and not self:IsMouseOver() then return end
                ShowTooltip(self)
            end)
        else
            ShowTooltip(self)
        end
    end)
    frame:HookScript("OnLeave", function(self)
        if _G.MSUF_RoundedUF_OnGroupMouseover then
            _G.MSUF_RoundedUF_OnGroupMouseover(self, false)
        end
        SetHoverShown(self, false)
        self._msufGFTooltipToken = (self._msufGFTooltipToken or 0) + 1
        local tooltips = MSUF and MSUF.Tooltips
        if tooltips and type(tooltips.HideUnit) == "function" then tooltips.HideUnit(self)
        elseif UnitFrame_OnLeave then UnitFrame_OnLeave(self)
        elseif GameTooltip then GameTooltip:Hide() end
    end)
end

local function NormalizeAttrUnit(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return NO_UNIT
end

local function StoredAttrUnit(frame)
    local value = attrUnit[frame]
    if value == NO_UNIT then
        return nil
    end
    if value ~= nil then
        return value
    end
    return frame and frame.unit or nil
end

local function OnChildAttributeChanged(self, name, value)
    if name ~= UNIT_ATTR then return end
    local rawUnit = NormalizeAttrUnit(value)
    local oldUnit = StoredAttrUnit(self)
    local kind = childKind[self] or self._msufGFKind

    if attrUnit[self] == rawUnit then
        if rawUnit == NO_UNIT then
            if not oldUnit and not self.unit then
                return
            end
        elseif self.MSUFSpec and scanUnit[self] == rawUnit then
            if not kind or scanKind[self] == kind then
                return
            end
        end
    end

    if rawUnit == NO_UNIT then
        if not oldUnit and not self.unit then
            return
        end
        attrUnit[self] = rawUnit
        self.unit = nil
        self.unitKey = nil
        UF.OnUnitChanged(self, oldUnit, nil)
        scanUnit[self] = nil
        return
    end

    if oldUnit == rawUnit and self.MSUFSpec and scanUnit[self] == rawUnit then
        if not kind or scanKind[self] == kind then
            return
        end
    end

    UF.OnUnitChanged(self, oldUnit, rawUnit)
    local applied = kind and ApplyUnitChangeFast(self, kind, rawUnit)
    if kind and not applied then
        applied = GF.ApplyButton(self, kind, "UNIT_CHANGED")
    end
    if applied then
        attrUnit[self] = rawUnit
        return
    end
end

local function InstallChildAttrHook(child, kind)
    if not (child and child.HookScript) then return end
    if kind then childKind[child] = kind end
    if attrHooked[child] then return end
    attrHooked[child] = true
    child:HookScript("OnAttributeChanged", OnChildAttributeChanged)
end

local function HeaderLayoutNonce(frame)
    local parent = frame and frame.GetParent and frame:GetParent()
    if parent and parent.GetAttribute then
        return parent:GetAttribute("_msufLayoutNonce") or 0
    end
    return 0
end

local function TrackFrame(frame)
    if GF.frames[frame] ~= true then
        GF.frames[frame] = true
        GF.frameList[#GF.frameList + 1] = frame
    end
end

local function MarkApplied(frame, kind, unit, spec)
    local power = spec and spec.power
    appliedSerial[frame] = spec and spec._msufGFCompileSerial or 0
    appliedUnit[frame] = unit
    appliedKind[frame] = kind
    appliedPowerEnabled[frame] = power and power.enabled or false
    appliedPowerHeight[frame] = power and power.height or 0
end

local function HasSameApplyState(frame, kind, unit, spec)
    local power = spec and spec.power
    return frame
        and frame.MSUFSpec
        and appliedSerial[frame] == (spec and spec._msufGFCompileSerial or 0)
        and appliedUnit[frame] == unit
        and appliedKind[frame] == kind
        and appliedPowerEnabled[frame] == (power and power.enabled or false)
        and appliedPowerHeight[frame] == (power and power.height or 0)
end

ApplyUnitChangeFast = function(frame, kind, unit)
    if not (frame and kind and type(unit) == "string" and unit ~= "" and frame.MSUFSpec and GF.CompileSpec) then
        return false
    end

    childKind[frame] = kind
    frame._msufGFKind = kind
    frame._msufIsGroupFrame = true
    frame.unit = unit
    frame.unitKey = unit
    frame.configKey = "gf_" .. kind

    local spec = GF.CompileSpec(kind, frame, unit)
    UF.SetFrameSpec(frame, spec, unit)

    local power = spec and spec.power
    local sameStructure = appliedSerial[frame] == (spec and spec._msufGFCompileSerial or 0)
        and appliedKind[frame] == kind
        and appliedPowerEnabled[frame] == (power and power.enabled or false)
        and appliedPowerHeight[frame] == (power and power.height or 0)

    if sameStructure and frame.ForceUpdate then
        frame:ForceUpdate(UNIT_CHANGED_REASON)
    elseif sameStructure then
        UF.ApplySpec(frame, spec, UNIT_CHANGED_REASON, UNIT_CHANGE_FAST_MASK)
    else
        UF.ApplySpec(frame, spec, UNIT_CHANGED_REASON, APPLY_MASK)
    end
    MarkApplied(frame, kind, unit, spec)
    attrUnit[frame] = unit

    local layoutNonce = HeaderLayoutNonce(frame)
    scanNonce[frame] = layoutNonce
    scanUnit[frame] = unit
    scanKind[frame] = kind
    TrackFrame(frame)
    return true
end

function GF.UntrackFrame(frame)
    if not frame then return end
    if GF.UnregisterClickCastFrame then
        GF.UnregisterClickCastFrame(frame)
    end
    if UF and UF.DetachFrame then
        UF.DetachFrame(frame)
    end
    GF.frames[frame] = nil
    scanNonce[frame] = nil
    scanUnit[frame] = nil
    scanKind[frame] = nil
    attrUnit[frame] = nil
    childKind[frame] = nil
    appliedSerial[frame] = nil
    appliedUnit[frame] = nil
    appliedKind[frame] = nil
    appliedPowerEnabled[frame] = nil
    appliedPowerHeight[frame] = nil
    local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.unit
    local uf = _G.MSUF_UnitFrames
    if type(unit) == "string" and uf and uf[unit] == frame then
        uf[unit] = nil
    end
    local list = GF.frameList
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == frame then
            table_remove(list, i)
        end
    end
end

function GF.ApplyButton(frame, kind, reason)
    if not frame then return false end
    local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.unit
    if type(unit) ~= "string" or unit == "" then return false end
    local layoutNonce = HeaderLayoutNonce(frame)

    if reason == "MSUF_GF_SCAN"
        and frame.MSUFSpec
        and scanNonce[frame] == layoutNonce
        and scanUnit[frame] == unit
        and scanKind[frame] == kind then
        return true
    end

    childKind[frame] = kind
    frame._msufGFKind = kind
    frame._msufIsGroupFrame = true
    frame.unit = unit
    frame.unitKey = unit
    frame.configKey = "gf_" .. kind

    local spec = GF.CompileSpec(kind, frame, unit)
    UF.SetFrameSpec(frame, spec, unit)
    if HasSameApplyState(frame, kind, unit, spec) then
        attrUnit[frame] = unit
        scanNonce[frame] = layoutNonce
        scanUnit[frame] = unit
        scanKind[frame] = kind
        TrackFrame(frame)
        return true
    end

    UF.AttachFrame(frame, { scope = "group", ownEvents = false })
    InstallChildAttrHook(frame, kind)
    HookButton(frame)

    if not InCombat() then
        if frame.SetSize then
            frame:SetSize(spec.width, spec.height)
        end
        if frame.RegisterForClicks then
            frame:RegisterForClicks("AnyUp")
        end
        if frame.SetAttribute then
            frame:SetAttribute("*type1", "target")
            frame:SetAttribute("*type2", "togglemenu")
        end
    end
    UF.ApplySpec(frame, spec, reason or "MSUF_GF_APPLY", APPLY_MASK)
    MarkApplied(frame, kind, unit, spec)
    attrUnit[frame] = unit
    ApplyClickCast(frame, spec)
    if not (spec.group and spec.group.hoverHighlightEnabled == true) then
        SetHoverShown(frame, false)
    end
    scanNonce[frame] = layoutNonce
    scanUnit[frame] = unit
    scanKind[frame] = kind

    TrackFrame(frame)
    return true
end

local function ScanOneChild(child, kind, token)
    if not (child and child.GetAttribute) then return false end
    if scanSeen[child] == token then return false end
    scanSeen[child] = token
    InstallChildAttrHook(child, kind)
    if not child:GetAttribute("unit") then return false end
    GF.ApplyButton(child, kind, "MSUF_GF_SCAN")
    return true
end

local function ScanChildVarargs(kind, token, ...)
    local found = false
    for i = 1, select("#", ...) do
        if ScanOneChild(select(i, ...), kind, token) then
            found = true
        end
    end
    return found
end

function GF.ScanHeader(key, kind)
    local header = GF.headers and GF.headers[key]
    if not header then return end
    GF._scanSeenToken = (GF._scanSeenToken or 0) + 1
    local token = GF._scanSeenToken
    if header.GetChildren then
        return ScanChildVarargs(kind, token, header:GetChildren())
    end
    return false
end

local function ScheduleScanAfter(key, kind, delay)
    if not (C_Timer and C_Timer.After) then return end
    local scheduleKey = tostring(key) .. ":" .. tostring(delay)
    scanScheduledKind[scheduleKey] = kind
    if scanScheduled[scheduleKey] then return end
    scanScheduled[scheduleKey] = true
    C_Timer.After(delay, function()
        scanScheduled[scheduleKey] = nil
        local scanKind = scanScheduledKind[scheduleKey]
        scanScheduledKind[scheduleKey] = nil
        GF.ScanHeader(key, scanKind)
    end)
end

function GF.ScheduleScan(key, kind)
    GF.ScanHeader(key, kind)
    if C_Timer and C_Timer.After then
        ScheduleScanAfter(key, kind, 0.05)
    end
end

function GF.ForEachFrame(fn, includeHidden)
    if type(fn) ~= "function" then return end
    for i = 1, #GF.frameList do
        local frame = GF.frameList[i]
        if frame and GF.frames[frame] == true and (includeHidden == true or not frame.IsShown or frame:IsShown()) then
            fn(frame, frame.unit, frame._msufGFKind)
        end
    end
end
