local addonName, ns = ...

local function GetGF()
    return _G.MSUF_GroupFrames or (ns and ns.GroupFrames)
end

local panel

local function DB(kind)
    local gf = GetGF()
    return gf and gf.GetConfig and gf.GetConfig(kind)
end

local function Apply(kind)
    local gf = GetGF()
    if not gf then return end
    gf.ApplyStyle(kind)
    gf.Refresh(kind)
    if _G.MSUF_EM2 and _G.MSUF_EM2.Movers and _G.MSUF_EM2.Movers.SyncAll then
        _G.MSUF_EM2.Movers.SyncAll()
    end
end

local function MakeCheckbox(parent, text, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local label = cb.Text or cb.text or _G[(cb:GetName() or "") .. "Text"]
    if label and label.SetText then label:SetText(text) end
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    cb.Refresh = function()
        cb:SetChecked(getter() and true or false)
    end
    return cb
end

local function MakeEdit(parent, label, x, y, width, getter, setter)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(label)

    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width or 54, 20)
    eb:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEnterPressed", function(self)
        setter(self:GetText())
        self:ClearFocus()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        setter(self:GetText())
    end)
    eb.Refresh = function()
        eb:SetText(tostring(getter() or ""))
    end
    return eb
end

local function BuildSection(parent, kind, title, x)
    local host = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    host:SetSize(360, 270)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -54)
    host:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    host:SetBackdropColor(0.03, 0.05, 0.12, 0.92)
    host:SetBackdropBorderColor(0.10, 0.20, 0.45, 0.55)

    local hdr = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", host, "TOPLEFT", 12, -12)
    hdr:SetText(title)
    hdr:SetTextColor(1, 0.82, 0, 1)

    local conf = function() return DB(kind) end
    local refreshers = {}

    refreshers[#refreshers + 1] = MakeCheckbox(host, "Enabled", 12, -38, function() return conf().enabled ~= false end, function(v) conf().enabled = v; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeCheckbox(host, "Show in Edit Mode", 120, -38, function() return conf().showInEditMode ~= false end, function(v) conf().showInEditMode = v; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeCheckbox(host, "Bar Override", 12, -68, function() return conf().barOverride == true end, function(v) conf().barOverride = v; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeCheckbox(host, "Font Override", 120, -68, function() return conf().fontOverride == true end, function(v) conf().fontOverride = v; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeCheckbox(host, "Color Override", 240, -68, function() return conf().colorOverride == true end, function(v) conf().colorOverride = v; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeCheckbox(host, "Use Class Colors", 12, -98, function() return conf().useClassColors ~= false end, function(v) conf().useClassColors = v; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeCheckbox(host, "Dark Mode", 160, -98, function() return conf().darkMode == true end, function(v) conf().darkMode = v; Apply(kind) end)

    refreshers[#refreshers + 1] = MakeEdit(host, "Width", 12, -132, 44, function() return conf().width end, function(v) conf().width = tonumber(v) or conf().width; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeEdit(host, "Height", 118, -132, 44, function() return conf().height end, function(v) conf().height = tonumber(v) or conf().height; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeEdit(host, "Cols", 228, -132, 44, function() return conf().columns end, function(v) conf().columns = tonumber(v) or conf().columns; Apply(kind) end)

    refreshers[#refreshers + 1] = MakeEdit(host, "Gap X", 12, -164, 44, function() return conf().spacingX end, function(v) conf().spacingX = tonumber(v) or conf().spacingX; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeEdit(host, "Gap Y", 118, -164, 44, function() return conf().spacingY end, function(v) conf().spacingY = tonumber(v) or conf().spacingY; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeEdit(host, "Max", 228, -164, 44, function() return conf().maxFrames end, function(v) conf().maxFrames = tonumber(v) or conf().maxFrames; Apply(kind) end)

    refreshers[#refreshers + 1] = MakeEdit(host, "Font Size", 12, -196, 44, function() return conf().nameFontSize or 11 end, function(v) conf().nameFontSize = tonumber(v) or conf().nameFontSize; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeEdit(host, "Color R", 118, -196, 44, function() return conf().colorR or 0.18 end, function(v) conf().colorR = tonumber(v) or conf().colorR; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeEdit(host, "Color G", 228, -196, 44, function() return conf().colorG or 0.55 end, function(v) conf().colorG = tonumber(v) or conf().colorG; Apply(kind) end)
    refreshers[#refreshers + 1] = MakeEdit(host, "Color B", 12, -228, 44, function() return conf().colorB or 0.88 end, function(v) conf().colorB = tonumber(v) or conf().colorB; Apply(kind) end)

    function host:Refresh()
        for i = 1, #refreshers do
            if refreshers[i] and refreshers[i].Refresh then refreshers[i]:Refresh() end
        end
    end

    return host
end

function ns.MSUF_EnsureGroupOptionsPanelBuilt()
    if panel then
        if panel.Refresh then panel:Refresh() end
        return panel
    end

    panel = CreateFrame("Frame", "MSUF_GroupOptionsPanel", UIParent, "BackdropTemplate")
    panel:SetAllPoints()
    panel.__MSUF_MirrorNoRestoreShow = true

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Group Frames")
    title:SetTextColor(1, 0.82, 0, 1)

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Party and Raid group frames with Midnight-native edit-mode hooks.")

    panel.partySection = BuildSection(panel, "party", "Party", 16)
    panel.raidSection = BuildSection(panel, "raid", "Raid", 400)

    local preview = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    preview:SetSize(140, 24)
    preview:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -340)
    preview:SetText("Toggle Party Preview")
    preview:SetScript("OnClick", function()
        local gf = GetGF()
        if not gf then return end
        local nextMode = (gf.GetPreviewMode and gf.GetPreviewMode() == "party") and nil or "party"
        gf.SetPreviewMode(nextMode)
        panel:Refresh()
    end)

    local previewRaid = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    previewRaid:SetSize(140, 24)
    previewRaid:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    previewRaid:SetText("Toggle Raid Preview")
    previewRaid:SetScript("OnClick", function()
        local gf = GetGF()
        if not gf then return end
        local nextMode = (gf.GetPreviewMode and gf.GetPreviewMode() == "raid") and nil or "raid"
        gf.SetPreviewMode(nextMode)
        panel:Refresh()
    end)

    function panel:Refresh()
        if self.partySection and self.partySection.Refresh then self.partySection:Refresh() end
        if self.raidSection and self.raidSection.Refresh then self.raidSection:Refresh() end
    end

    panel:Refresh()
    return panel
end

_G.MSUF_EnsureGroupOptionsPanelBuilt = ns.MSUF_EnsureGroupOptionsPanelBuilt
