local addonName, ns = ...
ns = ns or {}

local panel, scopeButtons = nil, {}
local currentScope = "party"

local LEGACY_MAP = {
    bars = { showPowerBar = "showPowerBar", powerBarHeight = "powerBarHeight" },
    font = { showName = "showName", showHPText = "showHPText" },
    aura = { maxBuffs = "maxBuffs", maxDebuffs = "maxDebuffs", iconSize = "auraIconSize", excludeSated = "excludeSated" },
}

local function GroupDB()
    if type(_G.EnsureDB) == "function" then _G.EnsureDB() end
    local db = _G.MSUF_DB
    db.group = db.group or {}
    db.group.shared = db.group.shared or {}
    db.group.shared.bars = db.group.shared.bars or {}
    db.group.shared.font = db.group.shared.font or {}
    db.group.shared.aura = db.group.shared.aura or {}
    db.group.shared.aura.designer = db.group.shared.aura.designer or { text = "", groups = {} }
    db.group.party = db.group.party or {}
    db.group.raid = db.group.raid or {}
    db.group.party.overrides = db.group.party.overrides or { bars = {}, font = {}, aura = {} }
    db.group.raid.overrides = db.group.raid.overrides or { bars = {}, font = {}, aura = {} }
    return db.group
end

local function GetScopeDefaultY(scope)
    return (scope == "raid") and -400 or -200
end

local function GetScopeOffsets(conf, scope)
    local fn = _G.MSUF_Group_GetOffsets
    if type(fn) == "function" then
        return fn(conf, GetScopeDefaultY(scope))
    end
    local anchor = conf.anchor or { "TOPLEFT", nil, "TOPLEFT", 20, GetScopeDefaultY(scope) }
    return tonumber(conf.offsetX) or tonumber(anchor[4]) or 20, tonumber(conf.offsetY) or tonumber(anchor[5]) or GetScopeDefaultY(scope)
end

local function CategoryOverride(scope, category)
    local g = GroupDB()
    local scopeDB = g[scope]
    return scopeDB and scopeDB.overrides and scopeDB.overrides[category] or nil
end

local function IsCategoryOverrideEnabled(scope, category)
    local override = CategoryOverride(scope, category)
    return override and next(override) ~= nil or false
end

local function GetGroupValue(scope, category, key, fallback)
    if type(_G.MSUF_Group_GetSetting) == "function" then
        return _G.MSUF_Group_GetSetting(scope, category, key, fallback)
    end
    local g = GroupDB()
    local override = CategoryOverride(scope, category)
    if override and override[key] ~= nil then
        return override[key]
    end
    local sharedCategory = g.shared[category]
    if sharedCategory and sharedCategory[key] ~= nil then
        return sharedCategory[key]
    end
    local legacy = LEGACY_MAP[category] and LEGACY_MAP[category][key]
    if legacy and g.shared[legacy] ~= nil then
        return g.shared[legacy]
    end
    return fallback
end

local function WriteGroupValue(scope, category, key, value)
    local g = GroupDB()
    local sharedCategory = g.shared[category]
    local overrideEnabled = IsCategoryOverrideEnabled(scope, category)
    if overrideEnabled then
        g[scope].overrides[category][key] = value
    else
        sharedCategory[key] = value
    end
    local legacy = LEGACY_MAP[category] and LEGACY_MAP[category][key]
    if legacy then
        if overrideEnabled then
            g[scope].overrides[category][legacy] = nil
        else
            g.shared[legacy] = value
        end
    end
end

local function SetCategoryOverride(scope, category, enabled)
    local g = GroupDB()
    local override = g[scope].overrides[category]
    if enabled then
        if next(override) ~= nil then return end
        local sharedCategory = g.shared[category] or {}
        for key, value in pairs(sharedCategory) do
            if key ~= "designer" then
                override[key] = value
            elseif type(value) == "table" then
                override[key] = { text = value.text or "", groups = value.groups or {} }
            end
        end
    else
        g[scope].overrides[category] = {}
    end
end

local function ParseDesignerText(text)
    local groups = {}
    if type(text) ~= "string" then return groups end
    for line in string.gmatch(text, "[^\r\n]+") do
        local name, ids = string.match(line, "^%s*([^=]+)%s*=%s*(.+)%s*$")
        if name and ids then
            local entry = { name = name, spells = {} }
            for rawID in string.gmatch(ids, "[^,%s]+") do
                local spellID = tonumber(rawID)
                if spellID and spellID > 0 then
                    entry.spells[spellID] = true
                end
            end
            if next(entry.spells) then
                groups[#groups + 1] = entry
            end
        end
    end
    return groups
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do
        out[k] = DeepCopy(vv)
    end
    return out
end

local function DesignerTextForScope(scope)
    local designer = GetGroupValue(scope, "aura", "designer", nil)
    if type(designer) == "table" and type(designer.text) == "string" then
        return designer.text
    end
    return ""
end

local function SaveDesigner(scope, text)
    local value = { text = text or "", groups = ParseDesignerText(text or "") }
    WriteGroupValue(scope, "aura", "designer", value)
end

local function RefreshRuntime()
    if type(_G.MSUF_SyncBlizzardGroupFrames) == "function" then _G.MSUF_SyncBlizzardGroupFrames() end
    if type(_G.MSUF_EnsureGroupFrames) == "function" then _G.MSUF_EnsureGroupFrames() end
    if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
    if type(_G.MSUF_Group_RefreshAll) == "function" then _G.MSUF_Group_RefreshAll() end
end

function _G.MSUF_SelectGroupOptionsScope(scope)
    currentScope = (scope == "raid") and "raid" or "party"
    if not panel then return end
    local g = GroupDB()
    local conf = g[currentScope]
    panel.title:SetText(currentScope == "raid" and "Raid Frames" or "Party Frames")
    panel.enableCB:SetChecked(g.enabled ~= false)
    panel.hideCB:SetChecked(g.hideBlizzard ~= false)
    local x, y = GetScopeOffsets(conf, currentScope)
    panel.xBox:SetText(x)
    panel.yBox:SetText(y)
    panel.wBox:SetText(conf.width or 90)
    panel.hBox:SetText(conf.height or 36)
    panel.spacingBox:SetText(conf.spacing or 2)
    panel.wrapBox:SetText(conf.wrapAfter or 5)
    panel.wrapLabel:SetShown(currentScope == "raid")
    panel.wrapBox:SetShown(currentScope == "raid")
    panel.growthValue = conf.growthDirection or "DOWN"
    panel.growthBtn:SetText("Growth: " .. panel.growthValue)

    panel.barsOverrideCB:SetChecked(IsCategoryOverrideEnabled(currentScope, "bars"))
    panel.fontOverrideCB:SetChecked(IsCategoryOverrideEnabled(currentScope, "font"))
    panel.auraOverrideCB:SetChecked(IsCategoryOverrideEnabled(currentScope, "aura"))

    panel.powerModeBtn.value = GetGroupValue(currentScope, "bars", "showPowerBar", "HEALER")
    panel.powerModeBtn:SetText("Power: " .. panel.powerModeBtn.value)
    panel.powerHeightBox:SetText(GetGroupValue(currentScope, "bars", "powerBarHeight", 3))

    panel.showNameCB:SetChecked(GetGroupValue(currentScope, "font", "showName", true) == true)
    panel.showHPTextCB:SetChecked(GetGroupValue(currentScope, "font", "showHPText", false) == true)
    panel.nameSizeBox:SetText(GetGroupValue(currentScope, "font", "nameSize", 11))
    panel.hpSizeBox:SetText(GetGroupValue(currentScope, "font", "hpSize", 10))

    panel.maxBuffsBox:SetText(GetGroupValue(currentScope, "aura", "maxBuffs", 3))
    panel.maxDebuffsBox:SetText(GetGroupValue(currentScope, "aura", "maxDebuffs", 3))
    panel.iconSizeBox:SetText(GetGroupValue(currentScope, "aura", "iconSize", 16))
    panel.excludeSatedCB:SetChecked(GetGroupValue(currentScope, "aura", "excludeSated", true) == true)
    panel.designerEdit:SetText(DesignerTextForScope(currentScope))

    for key, btn in pairs(scopeButtons) do
        if btn._label then btn._label:SetTextColor(key == currentScope and 0.38 or 0.72, key == currentScope and 0.65 or 0.74, 1, 1) end
    end
end

local function MakeLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function MakeBox(parent, x, y, w)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(w or 60, 20)
    eb:SetAutoFocus(false)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return eb
end

local function MakeCheck(parent, text, x, y, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    fs:SetText(text)
    cb.label = fs
    if onClick then cb:SetScript("OnClick", onClick) end
    return cb
end

local function Apply()
    if not panel then return end
    local g = GroupDB()
    local conf = g[currentScope]
    g.enabled = panel.enableCB:GetChecked() and true or false
    g.hideBlizzard = panel.hideCB:GetChecked() and true or false

    local setFn = _G.MSUF_Group_SetOffsets
    local x = tonumber(panel.xBox:GetText()) or 20
    local y = tonumber(panel.yBox:GetText()) or GetScopeDefaultY(currentScope)
    if type(setFn) == "function" then
        setFn(conf, x, y, GetScopeDefaultY(currentScope))
    else
        conf.offsetX, conf.offsetY = x, y
        conf.anchor = conf.anchor or { "TOPLEFT", nil, "TOPLEFT", x, y }
        conf.anchor[4], conf.anchor[5] = x, y
    end
    conf.width = tonumber(panel.wBox:GetText()) or conf.width or 90
    conf.height = tonumber(panel.hBox:GetText()) or conf.height or 36
    conf.spacing = tonumber(panel.spacingBox:GetText()) or conf.spacing or 2
    conf.wrapAfter = tonumber(panel.wrapBox:GetText()) or conf.wrapAfter or 5
    conf.growthDirection = panel.growthValue or conf.growthDirection or "DOWN"

    SetCategoryOverride(currentScope, "bars", panel.barsOverrideCB:GetChecked() == true)
    SetCategoryOverride(currentScope, "font", panel.fontOverrideCB:GetChecked() == true)
    SetCategoryOverride(currentScope, "aura", panel.auraOverrideCB:GetChecked() == true)

    WriteGroupValue(currentScope, "bars", "showPowerBar", panel.powerModeBtn.value or "HEALER")
    WriteGroupValue(currentScope, "bars", "powerBarHeight", tonumber(panel.powerHeightBox:GetText()) or 3)
    WriteGroupValue(currentScope, "font", "showName", panel.showNameCB:GetChecked() == true)
    WriteGroupValue(currentScope, "font", "showHPText", panel.showHPTextCB:GetChecked() == true)
    WriteGroupValue(currentScope, "font", "nameSize", tonumber(panel.nameSizeBox:GetText()) or 11)
    WriteGroupValue(currentScope, "font", "hpSize", tonumber(panel.hpSizeBox:GetText()) or 10)
    WriteGroupValue(currentScope, "aura", "maxBuffs", tonumber(panel.maxBuffsBox:GetText()) or 3)
    WriteGroupValue(currentScope, "aura", "maxDebuffs", tonumber(panel.maxDebuffsBox:GetText()) or 3)
    WriteGroupValue(currentScope, "aura", "iconSize", tonumber(panel.iconSizeBox:GetText()) or 16)
    WriteGroupValue(currentScope, "aura", "excludeSated", panel.excludeSatedCB:GetChecked() == true)
    SaveDesigner(currentScope, panel.designerEdit:GetText() or "")

    RefreshRuntime()
    _G.MSUF_SelectGroupOptionsScope(currentScope)
end

function _G.MSUF_EnsureGroupOptionsPanelBuilt()
    if panel then return panel end
    panel = CreateFrame("Frame", "MSUF_GroupOptionsPanel", UIParent)
    panel:SetSize(760, 760)
    panel:Hide()
    panel.title = MakeLabel(panel, "Party Frames", 16, -16)

    local function makeScope(label, scope, x)
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(80, 22)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -12)
        b._label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b._label:SetPoint("CENTER")
        b._label:SetText(label)
        b:SetScript("OnClick", function() _G.MSUF_SelectGroupOptionsScope(scope) end)
        scopeButtons[scope] = b
        return b
    end
    makeScope("Party", "party", 520)
    makeScope("Raid", "raid", 608)

    panel.enableCB = MakeCheck(panel, "Enable Party/Raid Frames", 20, -50, Apply)
    panel.hideCB = MakeCheck(panel, "Hide Blizzard Party/Raid Frames", 20, -78, Apply)

    MakeLabel(panel, "X", 20, -126)
    panel.xBox = MakeBox(panel, 80, -120)
    MakeLabel(panel, "Y", 160, -126)
    panel.yBox = MakeBox(panel, 220, -120)
    MakeLabel(panel, "Width", 20, -160)
    panel.wBox = MakeBox(panel, 80, -154)
    MakeLabel(panel, "Height", 160, -160)
    panel.hBox = MakeBox(panel, 220, -154)
    MakeLabel(panel, "Spacing", 20, -194)
    panel.spacingBox = MakeBox(panel, 80, -188)
    panel.wrapLabel = MakeLabel(panel, "Wrap", 160, -194)
    panel.wrapBox = MakeBox(panel, 220, -188)

    panel.growthValue = "DOWN"
    panel.growthBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.growthBtn:SetSize(120, 24)
    panel.growthBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -228)
    panel.growthBtn:SetText("Growth: DOWN")
    panel.growthBtn:SetScript("OnClick", function(self)
        local order = { "DOWN", "UP", "RIGHT", "LEFT" }
        local current = panel.growthValue or "DOWN"
        local nextIndex = 1
        for i, v in ipairs(order) do
            if v == current then nextIndex = (i % #order) + 1 break end
        end
        panel.growthValue = order[nextIndex]
        self:SetText("Growth: " .. panel.growthValue)
        Apply()
    end)

    MakeLabel(panel, "Bars Override", 20, -278)
    panel.barsOverrideCB = MakeCheck(panel, "Override shared bar settings", 20, -298, Apply)
    panel.powerModeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.powerModeBtn:SetSize(140, 24)
    panel.powerModeBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -328)
    panel.powerModeBtn.value = "HEALER"
    panel.powerModeBtn:SetScript("OnClick", function(self)
        local order = { "HEALER", "ALL", "NONE" }
        local current = self.value or "HEALER"
        local nextIndex = 1
        for i, v in ipairs(order) do
            if v == current then nextIndex = (i % #order) + 1 break end
        end
        self.value = order[nextIndex]
        self:SetText("Power: " .. self.value)
        Apply()
    end)
    MakeLabel(panel, "Power Height", 180, -334)
    panel.powerHeightBox = MakeBox(panel, 270, -328)

    MakeLabel(panel, "Font Override", 20, -378)
    panel.fontOverrideCB = MakeCheck(panel, "Override shared font settings", 20, -398, Apply)
    panel.showNameCB = MakeCheck(panel, "Show Name", 20, -428, Apply)
    panel.showHPTextCB = MakeCheck(panel, "Show HP Text", 140, -428, Apply)
    MakeLabel(panel, "Name Size", 20, -462)
    panel.nameSizeBox = MakeBox(panel, 100, -456)
    MakeLabel(panel, "HP Size", 180, -462)
    panel.hpSizeBox = MakeBox(panel, 250, -456)

    MakeLabel(panel, "Aura Override", 20, -506)
    panel.auraOverrideCB = MakeCheck(panel, "Override shared aura settings", 20, -526, Apply)
    MakeLabel(panel, "Max Buffs", 20, -560)
    panel.maxBuffsBox = MakeBox(panel, 100, -554)
    MakeLabel(panel, "Max Debuffs", 180, -560)
    panel.maxDebuffsBox = MakeBox(panel, 280, -554)
    MakeLabel(panel, "Icon Size", 360, -560)
    panel.iconSizeBox = MakeBox(panel, 430, -554)
    panel.excludeSatedCB = MakeCheck(panel, "Exclude Sated / Exhaustion", 20, -590, Apply)

    MakeLabel(panel, "Aura Designer (Blizzard whitelist groups, 12.0 live via CompactRaidFrame cache)", 20, -630)
    local designerBG = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    designerBG:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -650)
    designerBG:SetSize(500, 82)
    designerBG:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    designerBG:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    designerBG:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    panel.designerEdit = CreateFrame("EditBox", nil, designerBG)
    panel.designerEdit:SetMultiLine(true)
    panel.designerEdit:SetFontObject("GameFontHighlightSmall")
    panel.designerEdit:SetPoint("TOPLEFT", designerBG, "TOPLEFT", 6, -6)
    panel.designerEdit:SetPoint("BOTTOMRIGHT", designerBG, "BOTTOMRIGHT", -6, 6)
    panel.designerEdit:SetAutoFocus(false)
    panel.designerEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local applyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    applyBtn:SetSize(120, 24)
    applyBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 540, -650)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", Apply)

    local copyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    copyBtn:SetSize(160, 24)
    copyBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 540, -682)
    copyBtn:SetText("Copy overrides to other")
    copyBtn:SetScript("OnClick", function()
        local g = GroupDB()
        local srcKey = currentScope
        local dstKey = (currentScope == "party") and "raid" or "party"
        g[dstKey].overrides.bars = DeepCopy(g[srcKey].overrides.bars or {})
        g[dstKey].overrides.font = DeepCopy(g[srcKey].overrides.font or {})
        g[dstKey].overrides.aura = DeepCopy(g[srcKey].overrides.aura or {})
        Apply()
    end)

    local designerHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    designerHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 540, -718)
    designerHint:SetWidth(190)
    designerHint:SetJustifyH("LEFT")
    designerHint:SetJustifyV("TOP")
    designerHint:SetText("Format:\nExternal=102342,6940,33206\nHaste=2825,32182,80353")

    local function bindApply(editBox)
        editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Apply() end)
    end
    for _, box in ipairs({ panel.xBox, panel.yBox, panel.wBox, panel.hBox, panel.spacingBox, panel.wrapBox, panel.powerHeightBox, panel.nameSizeBox, panel.hpSizeBox, panel.maxBuffsBox, panel.maxDebuffsBox, panel.iconSizeBox }) do
        bindApply(box)
    end

    panel:SetScript("OnShow", function() _G.MSUF_SelectGroupOptionsScope(currentScope) end)
    panel.__MSUF_MirrorHeaderTargets = { panel.title }
    return panel
end
