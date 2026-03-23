local addonName, ns = ...

local Roster = ns.GroupRoster or _G.MSUF_GroupRoster
local Update = ns.GroupUpdate or _G.MSUF_GroupUpdate
if not (Roster and Update) then return end

local GroupFrames = {}
ns.GroupFrames = GroupFrames
_G.MSUF_GroupFrames = GroupFrames

local containers = {}
local ClickCastFrames = _G.ClickCastFrames or {}
_G.ClickCastFrames = ClickCastFrames
local KINDS = { "party", "raid" }
local MAX_BUTTONS = { party = 5, raid = 40 }
local DEFAULTS = {
    party = { width = 132, height = 28, spacingX = 0, spacingY = 4, columns = 1, maxFrames = 5, offsetX = 420, offsetY = -260 },
    raid  = { width = 92, height = 22, spacingX = 4, spacingY = 4, columns = 5, maxFrames = 40, offsetX = 420, offsetY = -24 },
}

local function GetDB(kind)
    local db = _G.MSUF_DB
    if not db and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
        db = _G.MSUF_DB
    end
    if not db then
        _G.MSUF_DB = _G.MSUF_DB or {}
        db = _G.MSUF_DB
    end
    db.groupFrames = db.groupFrames or {}
    db.groupFrames[kind] = db.groupFrames[kind] or {}
    local conf = db.groupFrames[kind]
    local def = DEFAULTS[kind]
    for k, v in pairs(def) do
        if conf[k] == nil then conf[k] = v end
    end
    if conf.enabled == nil then conf.enabled = true end
    if conf.showInEditMode == nil then conf.showInEditMode = true end
    if conf.growDown == nil then conf.growDown = true end
    return conf
end

local function IsEditMode()
    return (_G.MSUF_EM2 and _G.MSUF_EM2.State and _G.MSUF_EM2.State.IsActive and _G.MSUF_EM2.State.IsActive())
        or (_G.MSUF_UnitEditModeActive and true or false)
end

local function IsPreviewActive(kind)
    return Roster.GetPreviewMode and Roster.GetPreviewMode() == kind
end

local function ShouldShow(kind, unitCount)
    local conf = GetDB(kind)
    if conf.enabled == false then return false end
    if IsPreviewActive(kind) then return true end
    if kind == "party" then
        if IsInRaid and IsInRaid() then return false end
        if unitCount > 0 then return true end
    elseif kind == "raid" then
        if IsInRaid and IsInRaid() and unitCount > 0 then return true end
    end
    if IsEditMode() and conf.showInEditMode then return true end
    return false
end

local function ApplyContainerPoint(holder, conf)
    holder:ClearAllPoints()
    holder:SetPoint(conf.point or "TOPLEFT", UIParent, conf.relPoint or conf.point or "TOPLEFT", conf.offsetX or 0, conf.offsetY or 0)
end

local function CreateButton(parent, kind, index)
    local btn = CreateFrame("Button", "MSUF_Group_" .. kind .. index, parent, "BackdropTemplate,SecureUnitButtonTemplate,PingableUnitFrameTemplate")
    btn.kind = kind
    btn.index = index
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("*type1", "target")
    btn:SetAttribute("*type2", "togglemenu")

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()

    btn.hpBar = CreateFrame("StatusBar", nil, btn)
    btn.hpBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.hpBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.hpBar:SetMinMaxValues(0, 1)

    btn.powerBar = CreateFrame("StatusBar", nil, btn)
    btn.powerBar:SetPoint("TOPLEFT", btn.hpBar, "BOTTOMLEFT", 0, 0)
    btn.powerBar:SetPoint("TOPRIGHT", btn.hpBar, "BOTTOMRIGHT", 0, 0)
    btn.powerBar:SetHeight(3)
    btn.powerBar:SetMinMaxValues(0, 1)
    btn.powerBar:SetStatusBarColor(0.15, 0.45, 0.88, 1)

    btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.nameText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btn.nameText:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.nameText:SetJustifyH("LEFT")

    btn.statusText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.statusText:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.statusText:SetJustifyH("RIGHT")
    btn.statusText:Hide()

    btn.unitLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableTiny")
    btn.unitLabel:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -3)
    btn.unitLabel:SetTextColor(1, 0.82, 0, 0.8)
    btn.unitLabel:Hide()

    btn.border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.border:SetAllPoints()
    btn.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    btn:SetScript("OnEnter", function(self)
        if self.border and self.border.SetBackdropBorderColor then
            self.border:SetBackdropBorderColor(1, 0.82, 0, 0.65)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.border and self.border.SetBackdropBorderColor then
            self.border:SetBackdropBorderColor(0.10, 0.20, 0.42, 0.35)
        end
    end)

    ClickCastFrames[btn] = true
    return btn
end

local function EnsureContainer(kind)
    if containers[kind] then return containers[kind] end
    local holder = CreateFrame("Frame", "MSUF_GroupHolder_" .. kind, UIParent, "BackdropTemplate")
    holder.kind = kind
    holder.buttons = {}
    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 4)
    holder.label:SetText(kind == "party" and "MSUF Party" or "MSUF Raid")
    holder.label:SetTextColor(1, 0.82, 0, 0.95)
    holder.bg = holder:CreateTexture(nil, "BACKGROUND")
    holder.bg:SetAllPoints()
    holder.bg:SetColorTexture(0.03, 0.05, 0.12, 0.08)
    holder.border = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    holder.border:SetAllPoints()
    holder.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    holder.border:SetBackdropBorderColor(0.10, 0.20, 0.45, 0.30)

    for i = 1, MAX_BUTTONS[kind] do
        holder.buttons[i] = CreateButton(holder, kind, i)
    end

    containers[kind] = holder
    return holder
end

local function LayoutContainer(kind)
    local holder = EnsureContainer(kind)
    local conf = GetDB(kind)
    local cols = math.max(1, tonumber(conf.columns) or 1)
    local width = tonumber(conf.width) or DEFAULTS[kind].width
    local height = tonumber(conf.height) or DEFAULTS[kind].height
    local sx = tonumber(conf.spacingX) or 0
    local sy = tonumber(conf.spacingY) or 0
    local maxFrames = math.min(MAX_BUTTONS[kind], tonumber(conf.maxFrames) or MAX_BUTTONS[kind])
    local shown = 0

    for i = 1, MAX_BUTTONS[kind] do
        local btn = holder.buttons[i]
        btn:SetSize(width, height)
        btn.powerBar:SetHeight(kind == "party" and 3 or 2)
        if i <= maxFrames then
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            local x = col * (width + sx)
            local y = -row * (height + sy)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
            shown = i
        else
            btn:Hide()
        end
    end

    local rows = math.max(1, math.ceil(maxFrames / cols))
    holder:SetSize((math.min(cols, maxFrames) * width) + (math.max(0, math.min(cols, maxFrames) - 1) * sx), (rows * height) + (math.max(0, rows - 1) * sy))
    ApplyContainerPoint(holder, conf)
    return shown
end

local function BindButtonUnit(button, unit)
    Roster.ClearButtonMap(button)
    button.unit = unit
    if unit and not unit:match("^preview_") then
        button:SetAttribute("unit", unit)
        Roster.RegisterButton(unit, button)
    else
        button:SetAttribute("unit", nil)
    end
end

local function RefreshKind(kind)
    local holder = EnsureContainer(kind)
    local conf = GetDB(kind)
    local units = Roster.GetUnits(kind)
    local maxFrames = math.min(MAX_BUTTONS[kind], tonumber(conf.maxFrames) or MAX_BUTTONS[kind])
    LayoutContainer(kind)

    for i = 1, MAX_BUTTONS[kind] do
        local btn = holder.buttons[i]
        local unit = units[i]
        if unit and i <= maxFrames then
            BindButtonUnit(btn, unit)
            Update.ApplyUnit(btn, unit, kind, i)
            btn:Show()
        elseif IsEditMode() and conf.showInEditMode and i <= math.min(maxFrames, kind == "party" and 5 or 20) then
            local previewUnit = (kind == "party" and "preview_party" or "preview_raid") .. i
            BindButtonUnit(btn, previewUnit)
            Update.ApplyUnit(btn, previewUnit, kind, i)
            btn:Show()
        else
            BindButtonUnit(btn, nil)
            btn:Hide()
        end
    end

    holder.label:SetShown(IsEditMode() or IsPreviewActive(kind))
    holder:SetShown(ShouldShow(kind, #units))
end

function GroupFrames.Refresh(kind)
    if kind then
        RefreshKind(kind)
        return
    end
    for i = 1, #KINDS do RefreshKind(KINDS[i]) end
end

function GroupFrames.ApplyStyle(kind)
    if kind then
        local holder = EnsureContainer(kind)
        for i = 1, #holder.buttons do
            Update.ApplySharedStyle(holder.buttons[i], kind)
        end
        RefreshKind(kind)
        return
    end
    for i = 1, #KINDS do GroupFrames.ApplyStyle(KINDS[i]) end
end

function GroupFrames.GetContainer(kind)
    return EnsureContainer(kind)
end

function GroupFrames.GetConfig(kind)
    return GetDB(kind)
end

function GroupFrames.SetPreviewMode(mode)
    if Roster and Roster.SetPreviewMode then
        Roster.SetPreviewMode(mode)
    end
end

function GroupFrames.GetPreviewMode()
    return Roster and Roster.GetPreviewMode and Roster.GetPreviewMode() or nil
end

function GroupFrames.TryEnable()
    EnsureContainer("party")
    EnsureContainer("raid")
    GroupFrames.Refresh()
end

Roster.RegisterListener(function(event, payload)
    if event == "unit" and payload then
        local buttons = Roster.IterButtons(payload)
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn:IsShown() then
                    Update.ApplyUnit(btn, payload, btn.kind, btn.index)
                end
            end
        end
        return
    end
    GroupFrames.Refresh()
end)

C_Timer.After(0, function()
    GroupFrames.TryEnable()
    if hooksecurefunc then
        if type(_G.MSUF_UpdateAllFonts) == "function" then
            hooksecurefunc(_G, "MSUF_UpdateAllFonts", function() GroupFrames.ApplyStyle() end)
        end
        if type(_G.MSUF_RefreshAllIdentityColors) == "function" then
            hooksecurefunc(_G, "MSUF_RefreshAllIdentityColors", function() GroupFrames.ApplyStyle() end)
        end
        if type(_G.ApplyAllSettings) == "function" then
            hooksecurefunc(_G, "ApplyAllSettings", function() GroupFrames.Refresh() end)
        end
    end
end)
