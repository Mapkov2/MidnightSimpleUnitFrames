--- UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua
--- Dummy Group Frame previews shared by Menu2 and Edit Mode.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetNumGroupMembers = GetNumGroupMembers
local UnitName = UnitName
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local floor, max, min = math.floor, math.max, math.min
local type, tonumber, tostring = type, tonumber, tostring

GF._previewFrames = GF._previewFrames or {}
GF._previewActive = GF._previewActive or {}
GF._previewShownCounts = GF._previewShownCounts or {}
GF._previewAnchorFrame = GF._previewAnchorFrame or {}
GF._previewContainer = GF._previewContainer or {}
GF._previewLayoutFrame = GF._previewLayoutFrame or {}

local PREVIEW_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID",
    "DEMONHUNTER", "EVOKER",
}
local PREVIEW_NAMES = { "Mapko", "Jaina", "Thrall", "Tyrande", "Anduin" }
local PREVIEW_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "HEALER" }

local VALID_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function NormalizeKind(kind)
    if kind == "gf_party" then return "party" end
    if kind == "gf_raid" then return "raid" end
    if kind == "gf_mythicraid" then return "mythicraid" end
    if kind == "party" or kind == "raid" or kind == "mythicraid" then return kind end
    return nil
end

local function IsRaidLikeKind(kind)
    return kind == "raid" or kind == "mythicraid"
end

local function AnchorPoint(conf)
    local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
    if not VALID_POINTS[point] then point = "CENTER" end
    return point
end

local function ResolveAnchorFrame(conf)
    local name = conf and (conf.anchorToFrame or conf.anchorFrame or conf.relativeTo or conf.anchorTo)
    if type(name) == "string" and name ~= "" and name ~= "FREE" and name ~= "UIParent" then
        local UF = MSUF and MSUF.UF
        if UF and UF.frames and UF.frames[name] then return UF.frames[name] end
        if _G[name] then return _G[name] end
    end
    return UIParent
end

local function DefaultCenter(kind)
    if IsRaidLikeKind(kind) then return -500, 0 end
    return -400, 0
end

local function DefaultPreviewCount(kind)
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end

local function ActivePreviewCount(kind)
    if not (GF._previewActive and GF._previewActive[kind] == true) then return nil end
    local n = tonumber(GF._previewShownCounts and GF._previewShownCounts[kind])
    if n and n > 0 then return floor(n + 0.5) end
    return DefaultPreviewCount(kind)
end

-- File-local: only used inside this file.
local function GetPositionCount(kind)
    kind = NormalizeKind(kind) or "party"
    local previewCount = ActivePreviewCount(kind)
    if previewCount then return previewCount end

    local conf = GF.GetConf and GF.GetConf(kind) or {}
    if kind == "party" then
        local n = GetNumSubgroupMembers and (GetNumSubgroupMembers() or 0) or 0
        if n > 0 and conf.showPlayer ~= false then
            n = n + 1
        elseif n == 0 and conf.showSolo == true and conf.showPlayer ~= false then
            n = 1
        end
        if n > 0 then return n end
        return 5
    end
    -- Raid-like: mirror the exact count the live header uses to center its
    -- anchor, so the preview box lands on the same spot as the real header
    -- (empty raid -> the live "unknown" count, not a hardcoded 30/20/40).
    if GF.GetLiveLayoutCount then
        local n = tonumber(GF.GetLiveLayoutCount(kind))
        if n and n > 0 then return floor(n + 0.5) end
    end
    local n = GetNumGroupMembers and (GetNumGroupMembers() or 0) or 0
    if n > 0 then return n end
    return kind == "mythicraid" and 20 or 40
end

function GF.SetPreviewAnchor(kind, parent)
    kind = NormalizeKind(kind)
    if not kind then return false end
    GF._previewAnchorFrame[kind] = parent
    return true
end

local PreviewsAllowed

local function EnsureContainer(kind, parent)
    local desiredParent = parent or UIParent
    local container = GF._previewContainer[kind]
    if not container then
        container = CreateFrame("Frame", "MSUF_GFPreviewContainer_" .. kind, desiredParent)
        container:EnableMouse(false)
        GF._previewContainer[kind] = container
    end
    if container:GetParent() ~= desiredParent then container:SetParent(desiredParent) end

    local layout = GF._previewLayoutFrame[kind]
    if not layout then
        layout = CreateFrame("Frame", "MSUF_GFPreviewLayout_" .. kind, container)
        layout:EnableMouse(false)
        GF._previewLayoutFrame[kind] = layout
    end
    if layout:GetParent() ~= container then layout:SetParent(container) end
    return container, layout
end

local function PositionContainer(kind, count)
    local conf = GF.GetConf and GF.GetConf(kind) or {}
    local posCount = GetPositionCount(kind) or DefaultPreviewCount(kind)
    local dx, dy, posW, posH = GF.GetGridMetrics(kind, posCount)
    local _, _, _, _, w, h, spacing, growth, upc, _, _, _, primary, _, _, blockW, blockH = GF.GetGridMetrics(kind, count)
    local parent = GF._previewAnchorFrame and GF._previewAnchorFrame[kind]
    local container, layout = EnsureContainer(kind, parent or UIParent)

    container:ClearAllPoints()
    container:SetSize(max(posW or w or 1, 1), max(posH or h or 1, 1))
    if parent then
        container:SetPoint("CENTER", parent, "CENTER", 0, 0)
    else
        local cx, cy = tonumber(conf.offsetX), tonumber(conf.offsetY)
        if cx == nil or cy == nil then cx, cy = DefaultCenter(kind) end
        local point = AnchorPoint(conf)
        container:SetPoint(point, ResolveAnchorFrame(conf), point, floor(cx + 0.5), floor(cy + 0.5))
    end

    layout:ClearAllPoints()
    layout:SetSize(max(posW or w or 1, 1), max(posH or h or 1, 1))
    local point = AnchorPoint(conf)
    layout:SetPoint(point, container, point, -(dx or 0), -(dy or 0))
    layout.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
    layout._msufIsGroupFrame = true
    layout._msufGFKind = kind
    layout._msufGFPreviewLayout = true
    layout._msufGFDragCenterToGridX = dx or 0
    layout._msufGFDragCenterToGridY = dy or 0
    container:Show()
    layout:Show()
    return container, layout, w, h, spacing or 1, growth or "DOWN", upc or 5, primary, blockW, blockH
end

local function SetShown(region, shown)
    if region and region.SetShown then region:SetShown(shown and true or false) end
end

local function SetText(region, text)
    if region and region.SetText then region:SetText(text or "") end
end

local function SetBar(bar, value, maxValue, r, g, b, a)
    if not bar then return end
    if bar.SetMinMaxValues then bar:SetMinMaxValues(0, maxValue or 100) end
    if bar.SetValue then bar:SetValue(value or 0) end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1) end
    if bar.Show then bar:Show() end
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.25, 0.75, 0.30
end

local function PreviewHealthColor(frame, class, hpPct)
    local health = frame and frame.MSUFSpec and frame.MSUFSpec.health
    local mode = health and health.mode
    if mode == "gradient" then
        local r = hpPct > 0.5 and (1 - (hpPct - 0.5) * 2) or 1
        local g = hpPct > 0.5 and 1 or hpPct * 2
        return r, g, 0
    elseif mode == "custom" or mode == "unified" or mode == "dark" then
        return health.r or 0.1, health.g or 0.6, health.b or 0.9
    end
    return ClassColor(class)
end

local function ShortName(name, frame)
    local rt = frame and frame._msufTextRuntime
    local maxChars = rt and tonumber(rt.nameShortenMax) or 0
    if maxChars > 0 and type(name) == "string" and #name > maxChars then
        return name:sub(1, maxChars) .. ((rt and rt.nameShortenDots == false) and "" or "...")
    end
    return name
end

local function PercentFactory(pct)
    pct = floor((pct or 0) + 0.5)
    return function() return pct end
end

local function ApplyPreviewText(frame, hp, hpMax, power, powerMax)
    local text = MSUF and MSUF.UFText
    local rt = frame and frame._msufTextRuntime
    if not (text and rt and text.UpdateTextSlots) then return end

    rt.healthTextPending = nil
    rt.healthTimerActive = nil
    rt.pendingHP = nil
    rt.pendingHPMax = nil
    rt.nextHealthTextTime = nil
    rt.healthMissing = max(0, (hpMax or 0) - (hp or 0))
    text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, PercentFactory((hp / max(hpMax, 1)) * 100), rt.healthNeedsPercent, rt)

    rt.powerTextPending = nil
    rt.powerTimerActive = nil
    rt.pendingPower = nil
    rt.pendingPowerMax = nil
    rt.nextPowerTextTime = nil
    text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, PercentFactory((power / max(powerMax, 1)) * 100), rt.powerNeedsPercent, rt)
end

local function ApplyRoleIcon(frame, kind, role)
    if not frame.roleIcon then return end
    local status = frame.MSUFSpec and frame.MSUFSpec.status
    if not (GF.GetRoleTexture and status and status.role) then
        frame.roleIcon:Hide()
        return
    end
    local path, l, r, t, b = GF.GetRoleTexture(kind, role, status.role.style)
    if path then
        frame.roleIcon:SetTexture(path)
        frame.roleIcon:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
        frame.roleIcon:Show()
    else
        frame.roleIcon:Hide()
    end
end

local function ApplyLeaderIcon(frame, kind, assist)
    local tex = assist and frame.assistIcon or frame.leaderIcon
    if not tex then return end
    local fn = assist and GF.GetAssistTexture or GF.GetLeaderTexture
    if type(fn) ~= "function" then tex:Hide(); return end
    local path, l, r, t, b = fn(kind)
    tex:SetTexture(path)
    tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
    tex:Show()
end

local function ApplyPreviewStatus(frame, kind, index, role)
    ApplyRoleIcon(frame, kind, role)
    if index == 1 then ApplyLeaderIcon(frame, kind, false) else SetShown(frame.leaderIcon, false) end
    if index == 2 then ApplyLeaderIcon(frame, kind, true) else SetShown(frame.assistIcon, false) end
    if frame.raidIcon and index == 1 then
        frame.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        frame.raidIcon:SetTexCoord(0, 0.25, 0, 0.25)
        frame.raidIcon:Show()
    else
        SetShown(frame.raidIcon, false)
    end
    if frame.readyCheckIcon and (index == 1 or index == 3) then
        frame.readyCheckIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        frame.readyCheckIcon:Show()
    else
        SetShown(frame.readyCheckIcon, false)
    end
    if frame.resurrectIcon and index == 3 then
        frame.resurrectIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        frame.resurrectIcon:Show()
    else
        SetShown(frame.resurrectIcon or frame.incomingResIndicatorIcon, false)
    end
    local pvpIcon = frame.pvpIcon or frame.pvpIndicatorIcon
    if pvpIcon and index == 2 then
        if pvpIcon.SetAtlas then
            pvpIcon:SetAtlas("UI-HUD-UnitFrame-Player-PVP-AllianceIcon")
        else
            pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance")
            if pvpIcon.SetTexCoord then pvpIcon:SetTexCoord(0, 1, 0, 1) end
        end
        pvpIcon:Show()
    else
        SetShown(pvpIcon, false)
    end
    if frame.phaseIcon and index == 4 then
        frame.phaseIcon:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
        frame.phaseIcon:Show()
    else
        SetShown(frame.phaseIcon, false)
    end
    if frame.raidGroupNameText and frame.MSUFSpec and frame.MSUFSpec.status and frame.MSUFSpec.status.raidGroup then
        frame.raidGroupNameText:SetText(tostring(((index - 1) % 5) + 1))
        frame.raidGroupNameText:Show()
    else
        SetShown(frame.raidGroupNameText, false)
    end
    SetShown(frame.statusIndicatorText, false)
end

-- File-local: only used inside this file (preview-frame data population).
local function ApplyPreviewData(frame, index, kind)
    if not frame then return false end
    kind = NormalizeKind(kind) or "party"
    local class = PREVIEW_CLASSES[((index - 1) % #PREVIEW_CLASSES) + 1]
    local role = PREVIEW_ROLES[((index - 1) % #PREVIEW_ROLES) + 1]
    local playerName = UnitName and UnitName("player")
    local name = (index == 1 and playerName) or PREVIEW_NAMES[((index - 1) % #PREVIEW_NAMES) + 1]

    frame._msufGFPreviewActive = true
    frame._msufGFPreviewIndex = index
    frame._msufGFPreviewClass = class
    frame._msufGFPreviewRole = role
    frame._msufGFIsPreviewFrame = true
    frame._msufIsGroupFrame = true
    frame._msufGFKind = kind

    if frame.nameText and frame.nameText:IsShown() then
        frame.nameText:SetText(ShortName(name or "Preview", frame))
        frame.nameText:SetTextColor(ClassColor(class))
        frame.nameText:Show()
    end

    local hpPct = min(0.95, 0.34 + (((index * 13) % 55) * 0.01))
    local hpMax = 100
    local hp = floor(hpPct * hpMax + 0.5)
    SetBar(frame.hpBar or frame.Health or frame.health, hp, hpMax, PreviewHealthColor(frame, class, hpPct))

    local powerMax = 100
    local power = min(powerMax, 35 + ((index * 11) % 55))
    local powerBar = frame.targetPowerBar or frame.powerBar or frame.Power or frame.power
    if powerBar and (not powerBar.IsShown or powerBar:IsShown()) then
        SetBar(powerBar, power, powerMax, 0.10, 0.45, 0.95, 1)
    end

    ApplyPreviewText(frame, hp, hpMax, power, powerMax)
    ApplyPreviewStatus(frame, kind, index, role)
    if GF.PreviewSpellIndicators then GF.PreviewSpellIndicators(frame, kind, nil, nil) end
    if GF.PreviewFrameAuras then GF.PreviewFrameAuras(frame, kind, index) end
    if GF.PreviewPrivateAuras then GF.PreviewPrivateAuras(frame, kind) end
    frame:Show()
    return true
end

-- File-local: only used inside this file (preview-frame data teardown).
local function ClearPreviewData(frame)
    if not frame then return end
    frame._msufGFPreviewActive = nil
    frame._msufGFPreviewIndex = nil
    SetText(frame.nameText, "")
    SetText(frame.hpTextLeft, "")
    SetText(frame.hpTextCenter, "")
    SetText(frame.hpTextRight, "")
    SetText(frame.powerTextLeft, "")
    SetText(frame.powerTextCenter, "")
    SetText(frame.powerTextRight, "")
    SetShown(frame.roleIcon, false)
    SetShown(frame.raidIcon, false)
    SetShown(frame.leaderIcon, false)
    SetShown(frame.assistIcon, false)
    SetShown(frame.readyCheckIcon, false)
    SetShown(frame.resurrectIcon or frame.incomingResIndicatorIcon, false)
    SetShown(frame.pvpIcon or frame.pvpIndicatorIcon, false)
    SetShown(frame.phaseIcon, false)
    SetShown(frame.raidGroupNameText, false)
    SetShown(frame.statusIndicatorText, false)
    if GF.HideSpellIndicators then GF.HideSpellIndicators(frame) end
    if GF.HideFrameAuras then GF.HideFrameAuras(frame) end
    if GF.HidePreviewPrivateAuras then GF.HidePreviewPrivateAuras(frame) end
end

local function PlacePreviewFrame(frame, layout, index, w, h, spacing, growth, upc)
    local row = (index - 1) % upc
    local col = floor((index - 1) / upc)
    if growth == "UP" then
        frame:SetPoint("BOTTOMLEFT", layout, "BOTTOMLEFT", col * (w + spacing), row * (h + spacing))
    elseif growth == "RIGHT" then
        frame:SetPoint("TOPLEFT", layout, "TOPLEFT", row * (w + spacing), -col * (h + spacing))
    elseif growth == "LEFT" then
        frame:SetPoint("TOPRIGHT", layout, "TOPRIGHT", -row * (w + spacing), -col * (h + spacing))
    else
        frame:SetPoint("TOPLEFT", layout, "TOPLEFT", col * (w + spacing), -row * (h + spacing))
    end
end

local function SetPreservedPreviewPoint(frame, layout, index, w, h, spacing, growth, primary, blockW, blockH)
    -- primary/blockW/blockH come from GF.GetPreservedRaidGridMetrics so the
    -- preview's per-group block layout matches the live secure header exactly
    -- (it is no longer a hardcoded 5-wide assumption). Fall back to the same
    -- derivation the metrics use (primary = min(unitsPerColumn, 5)) only if the
    -- caller failed to thread them through, so the two never silently diverge
    -- when unitsPerColumn ~= 5.
    if not primary then
        local conf = layout and layout._msufGFKind and GF.GetConf and GF.GetConf(layout._msufGFKind)
        local upc = floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
        if upc < 1 then upc = 1 end
        primary = min(upc, 5)
    end
    if primary < 1 then primary = 1 end
    local blockColumns = max(1, floor((5 + primary - 1) / primary))
    blockW = blockW or (blockColumns * w + max(0, blockColumns - 1) * spacing)
    blockH = blockH or (primary * h + max(0, primary - 1) * spacing)
    local groupIndex = floor((index - 1) / 5)
    local withinGroup = (index - 1) % 5
    local minor = floor(withinGroup / primary)
    local major = withinGroup % primary
    if growth == "UP" then
        frame:SetPoint("BOTTOMLEFT", layout, "BOTTOMLEFT", groupIndex * (blockW + spacing) + minor * (w + spacing), major * (h + spacing))
    elseif growth == "RIGHT" then
        frame:SetPoint("TOPLEFT", layout, "TOPLEFT", major * (w + spacing), -(groupIndex * (blockH + spacing) + minor * (h + spacing)))
    elseif growth == "LEFT" then
        frame:SetPoint("TOPRIGHT", layout, "TOPRIGHT", -major * (w + spacing), -(groupIndex * (blockH + spacing) + minor * (h + spacing)))
    else
        frame:SetPoint("TOPLEFT", layout, "TOPLEFT", groupIndex * (blockW + spacing) + minor * (w + spacing), -major * (h + spacing))
    end
end

local function PositionPreviewFrame(frame, layout, index, kind, w, h, spacing, growth, upc, primary, blockW, blockH)
    frame:ClearAllPoints()
    local conf = GF.GetConf and GF.GetConf(kind) or nil
    if IsRaidLikeKind(kind) and conf and conf.preserveRaidGroups == true then
        SetPreservedPreviewPoint(frame, layout, index, w, h, spacing, growth, primary, blockW, blockH)
    else
        PlacePreviewFrame(frame, layout, index, w, h, spacing, growth, upc)
    end
end

local function EnsurePreviewFrame(kind, index, parent)
    local frames = GF._previewFrames[kind]
    if not frames then
        frames = {}
        GF._previewFrames[kind] = frames
    end
    local frame = frames[index]
    if frame then
        if frame:GetParent() ~= parent then frame:SetParent(parent) end
        return frame
    end

    frame = CreateFrame("Button", "MSUF_GFPreview_" .. kind .. "_" .. index, parent, "BackdropTemplate")
    frame._msufGFIsPreviewFrame = true
    frame._msufGFPreviewActive = true
    frame._msufGFKind = kind
    frame._msufIsGroupFrame = true
    frame.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
    frame.unit = "player"
    frame.unitKey = "player"
    if frame.SetAttribute then frame:SetAttribute("unit", "player") end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if frame.RegisterForClicks then frame:RegisterForClicks("LeftButtonUp") end
    frames[index] = frame
    return frame
end

function GF.ShowPreview(kind, count)
    if InCombat() then return false end
    if type(PreviewsAllowed) == "function" and not PreviewsAllowed() then return false end
    kind = NormalizeKind(kind) or "party"
    count = floor((tonumber(count) or DefaultPreviewCount(kind)) + 0.5)
    if count < 1 then count = DefaultPreviewCount(kind) end

    GF._previewActive[kind] = true
    GF._previewShownCounts[kind] = count

    local container, layout, w, h, spacing, growth, upc, primary, blockW, blockH = PositionContainer(kind, count)
    local frames = GF._previewFrames[kind] or {}
    GF._previewFrames[kind] = frames
    for i = 1, count do
        local frame = EnsurePreviewFrame(kind, i, layout)
        frame:SetSize(w, h)
        frame.unit = "player"
        frame.unitKey = "player"
        if frame.SetAttribute then frame:SetAttribute("unit", "player") end
        if GF.ApplyButton then GF.ApplyButton(frame, kind, "MSUF_GF_PREVIEW") end
        PositionPreviewFrame(frame, layout, i, kind, w, h, spacing, growth, upc, primary, blockW, blockH)
        ApplyPreviewData(frame, i, kind)
    end
    for i = count + 1, #frames do
        local frame = frames[i]
        if frame then
            ClearPreviewData(frame)
            frame:Hide()
        end
    end
    container:Show()
    return true
end

function GF.HidePreview(kind)
    kind = NormalizeKind(kind) or "party"
    GF._previewActive[kind] = nil
    GF._previewShownCounts[kind] = nil
    local frames = GF._previewFrames[kind]
    if frames then
        for i = 1, #frames do
            if frames[i] then
                ClearPreviewData(frames[i])
                frames[i]:Hide()
            end
        end
    end
    local container = GF._previewContainer[kind]
    if container then container:Hide() end
    return true
end

function GF.RefreshPreviewLayout(kind)
    if InCombat() then return false end
    if kind == nil then
        local any = false
        for _, activeKind in ipairs({ "party", "raid", "mythicraid" }) do
            if GF._previewActive and GF._previewActive[activeKind] then
                any = GF.RefreshPreviewLayout(activeKind) or any
            end
        end
        return any
    end
    kind = NormalizeKind(kind) or "party"
    if not (GF._previewActive and GF._previewActive[kind]) then return false end
    local count = GF._previewShownCounts[kind] or DefaultPreviewCount(kind)
    local _, layout, w, h, spacing, growth, upc, primary, blockW, blockH = PositionContainer(kind, count)
    local frames = GF._previewFrames[kind]
    if not frames then return false end
    for i = 1, #frames do
        local frame = frames[i]
        if frame and frame:IsShown() then
            if frame:GetParent() ~= layout then frame:SetParent(layout) end
            frame:SetSize(w, h)
            if GF.ApplyButton then GF.ApplyButton(frame, kind, "MSUF_GF_PREVIEW_REFRESH") end
            PositionPreviewFrame(frame, layout, i, kind, w, h, spacing, growth, upc, primary, blockW, blockH)
            ApplyPreviewData(frame, i, kind)
        end
    end
    return true
end

GF.RefreshPreviewBox = GF.RefreshPreviewLayout

PreviewsAllowed = function()
    if _G.MSUF_UnitEditModeActive == true then return true end
    if _G.MSUF2_GFPagePreviewActive == true then return true end
    local panel = _G.MSUF_GFOptionsPanel
    return panel and panel.IsShown and panel:IsShown() or false
end

function GF.HideOrphanedPreviews()
    if PreviewsAllowed() then return false end
    local hidden = false
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        if GF._previewActive[kind] then
            GF.HidePreview(kind)
            hidden = true
        end
    end
    return hidden
end

_G.MSUF_GF_ShowPreview = function(kind, count) return GF.ShowPreview(kind, count) end
_G.MSUF_GF_HidePreview = function(kind) return GF.HidePreview(kind) end
_G.MSUF_GF_SetPreviewAnchor = function(kind, parent) return GF.SetPreviewAnchor(kind, parent) end
_G.MSUF_GF_RefreshPreviewLayout = function(kind) return GF.RefreshPreviewLayout(kind) end
_G.MSUF_GF_RefreshPreviewBox = _G.MSUF_GF_RefreshPreviewLayout
