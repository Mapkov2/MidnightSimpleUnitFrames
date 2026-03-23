local addonName, ns = ...

local EM2 = _G.MSUF_EM2
local GF = _G.MSUF_GroupFrames or ns.GroupFrames
if not (EM2 and EM2.Registry and EM2.PopupFactory and GF) then return end

local F = EM2.PopupFactory
local Group = {}
EM2.Group = Group

local popup

local function Conf(kind)
    return GF.GetConfig and GF.GetConfig(kind)
end

local function Apply(kind)
    local conf = Conf(kind)
    if not conf or not popup then return end
    conf.offsetX = tonumber(popup.xBox:GetText()) or conf.offsetX or 0
    conf.offsetY = tonumber(popup.yBox:GetText()) or conf.offsetY or 0
    conf.width = math.max(40, tonumber(popup.wBox:GetText()) or conf.width or 100)
    conf.height = math.max(12, tonumber(popup.hBox:GetText()) or conf.height or 24)
    conf.spacingX = tonumber(popup.sxBox:GetText()) or conf.spacingX or 0
    conf.spacingY = tonumber(popup.syBox:GetText()) or conf.spacingY or 0
    conf.columns = math.max(1, tonumber(popup.colsBox:GetText()) or conf.columns or 1)
    conf.maxFrames = math.max(1, tonumber(popup.maxBox:GetText()) or conf.maxFrames or 5)
    conf.showInEditMode = popup.editCB:GetChecked() and true or false
    GF.Refresh(kind)
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local function Sync(kind)
    local conf = Conf(kind)
    if not conf or not popup then return end
    popup.kind = kind
    popup._titleFS:SetText(kind == "party" and "Party Group" or "Raid Group")
    popup.xBox:SetText(tostring(conf.offsetX or 0))
    popup.yBox:SetText(tostring(conf.offsetY or 0))
    popup.wBox:SetText(tostring(conf.width or 100))
    popup.hBox:SetText(tostring(conf.height or 24))
    popup.sxBox:SetText(tostring(conf.spacingX or 0))
    popup.syBox:SetText(tostring(conf.spacingY or 0))
    popup.colsBox:SetText(tostring(conf.columns or 1))
    popup.maxBox:SetText(tostring(conf.maxFrames or 5))
    popup.editCB:SetChecked(conf.showInEditMode and true or false)
end

local function BuildPopup()
    if popup then return popup end
    popup = F.Panel("MSUF_EM2_GroupPopup", 380, 380, "Group")
    local top = popup._contentTop

    local c1, b1 = F.Card(popup, top, "Position & Size", -2, true)
    local r1 = F.PairRow(popup, b1, c1, { label1 = "X:", label2 = "Y:", key1 = "xBox", key2 = "yBox", onChanged = function() Apply(popup.kind) end })
    F.PairRow(popup, b1, c1, { label1 = "W:", label2 = "H:", key1 = "wBox", key2 = "hBox", anchorTo = r1, onChanged = function() Apply(popup.kind) end })
    c1:RecalcHeight()

    local c2, b2 = F.Card(popup, c1, "Layout", -6, true)
    local r2 = F.PairRow(popup, b2, c2, { label1 = "Gap X:", label2 = "Gap Y:", key1 = "sxBox", key2 = "syBox", onChanged = function() Apply(popup.kind) end })
    F.PairRow(popup, b2, c2, { label1 = "Cols:", label2 = "Max:", key1 = "colsBox", key2 = "maxBox", anchorTo = r2, onChanged = function() Apply(popup.kind) end })
    c2:RecalcHeight()

    local c3, b3 = F.Card(popup, c2, "Edit Mode", -6, true)
    F.CheckRow(popup, b3, c3, { label = "Show in Edit Mode", cbKey = "editCB", onChanged = function() Apply(popup.kind) end })
    c3:RecalcHeight()

    local ok, cancel = F.FooterButtons(popup)
    ok:SetScript("OnClick", function() Apply(popup.kind); popup:Hide() end)
    cancel:SetScript("OnClick", function() popup:Hide() end)
    popup:UpdateScrollHeight(360)
    return popup
end

function Group.OpenPopup(kind)
    BuildPopup()
    Sync(kind)
    popup:Show()
end

local function Register()
    EM2.Registry.Register({
        key = "group_party",
        label = "Party Group",
        order = 70,
        popupType = "group",
        canResize = true,
        canNudge = true,
        getFrame = function() return GF.GetContainer("party") end,
        getConf = function() return Conf("party") end,
        isEnabled = function() return true end,
    })
    EM2.Registry.Register({
        key = "group_raid",
        label = "Raid Group",
        order = 71,
        popupType = "group",
        canResize = true,
        canNudge = true,
        getFrame = function() return GF.GetContainer("raid") end,
        getConf = function() return Conf("raid") end,
        isEnabled = function() return true end,
    })
end

local previewFrame

local function EnsurePreviewPopup()
    if previewFrame then return previewFrame end
    local f = CreateFrame("Frame", "MSUF_GroupPreviewPopup", UIParent, "BackdropTemplate")
    f:SetSize(220, 100)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.03, 0.05, 0.12, 0.96)
    f:SetBackdropBorderColor(0.10, 0.20, 0.45, 0.90)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("Group Preview")
    title:SetTextColor(1, 0.82, 0, 1)

    local function MakeBtn(text, x, mode)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(56, 22)
        b:SetPoint("TOP", f, "TOP", x, -42)
        b:SetText(text)
        b:SetScript("OnClick", function()
            local newMode = mode
            if GF.GetPreviewMode and GF.GetPreviewMode() == mode then newMode = nil end
            GF.SetPreviewMode(newMode)
            f:Hide()
            if EM2.HUD and EM2.HUD.RefreshControls then EM2.HUD.RefreshControls() end
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
        return b
    end

    MakeBtn("Party", -58, "party")
    MakeBtn("Raid", 0, "raid")
    MakeBtn("Off", 58, nil)

    previewFrame = f
    return f
end

function Group.TogglePreviewPopup()
    local f = EnsurePreviewPopup()
    if f:IsShown() then f:Hide() else f:Show() end
end

function Group.GetPreviewMode()
    return GF.GetPreviewMode and GF.GetPreviewMode() or nil
end

C_Timer.After(0, Register)

function Group.ClosePopup() if popup then popup:Hide() end end
function Group.IsPopupOpen() return popup and popup:IsShown() or false end
